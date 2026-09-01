# Arquitectura — Aura Studio Windows

> Referencia normativa para toda fase de `PLAN-aura-studio-windows-v2.md`
> (carpeta padre, `docs/plans/`). Transcribe los principios 6–7 de ese plan
> más las convenciones que ya están en uso en el código real de la VM —
> no es aspiracional, es lo que el port ya hace y debe seguir haciendo.
> Ante una convención nueva que contradiga esto, la sesión que la propone la
> documenta aquí explicando por qué, no la deja implícita en el diff.

## Fluent 2 de verdad (principio 6 del plan)

- **Cero colores hardcodeados en XAML** fuera de `Resources/AuraPalette.xaml`
  (paleta de marca) y `Resources/Styles.xaml` (tokens semánticos): toda
  pantalla nueva consume `ThemeResource` del sistema o esos tokens — nunca un
  `Color`/`SolidColorBrush` con valores literales sueltos en una página.
- `Resources/AuraPalette.xaml` es una **transcripción** de
  `studio/AuraStudio/Sources/AuraStudio/Generated/AuraPalette.swift` (fuente
  de verdad del firmware, generada con `design-system/generate.py`): cada
  canal 0…1 del Swift × 255. Nunca se inventan valores nuevos a mano, y al
  mover `FIRMWARE_VERSION` se vuelve a transcribir el archivo completo —
  igual que en macOS se reemplaza entero el `.swift`. Define los tres temas
  (`Light`, `Dark`, `HighContrast`); en contraste alto la paleta de marca se
  retira y manda el tema del usuario.
- **El acento de los controles es el del sistema**
  (`AccentFillColorDefaultBrush` y familia), no el de marca: Fluent 2 respeta
  el color de acento que el usuario eligió en Windows, y el principio 6 del
  plan lo pide explícitamente como criterio de aceptación. La app de macOS
  tiñe todo con el acento de marca porque en macOS ese es el idioma de la
  plataforma; acá no. El acento de marca queda como `AuraBrandAccentBrush`
  para los momentos de identidad de la app, no para pintar cada botón. Por lo
  mismo, un botón principal se hace con `AuraPrimaryButtonStyle`, que deriva
  de `AccentButtonStyle` del sistema y hereda sus estados (hover, pressed,
  deshabilitado) y su comportamiento en contraste alto — nunca con una
  plantilla propia con colores literales.
- **Espaciado y tipografía por token**, no por número suelto:
  `AuraSpacing*`/`AuraPageMargin`/`AuraCardPadding` (escala de 4 px de Fluent)
  y los estilos `AuraPageTitleTextStyle`/`AuraSectionTitleTextStyle`/
  `AuraSecondaryTextStyle`/`AuraCaptionTextStyle`.
- **Los glifos de Segoe Fluent Icons se verifican antes de usarlos**, no se
  escriben de memoria: el rango de uso privado no falla en compilación ni en
  runtime, simplemente dibuja otra cosa. En la Fase 1, `E94A` — que venía del
  código previo como icono de "Dispositivos" — resultó ser el signo de
  división. Se comprueban renderizando la fuente a una imagen y mirándola
  (ver el método en `ESTADO-PORT.md`).
- Tipografía: rampa de **Segoe UI Variable**. Iconografía: **Segoe Fluent
  Icons**.
- Fondo de ventana: **Mica** (`SystemBackdrop`), con fallback a
  `DesktopAcrylicBackdrop`/sólido en Windows 10 (Mica es exclusivo de
  Windows 11).
- Claro/oscuro y acento del sistema deben funcionar en toda pantalla nueva
  sin código adicional por pantalla — es responsabilidad de los tokens
  compartidos, no de cada vista.

## Arquitectura de capas (principio 7 del plan)

```
AuraStudio.Core/         lógica portable, SIN dependencias de Windows
  Networking/             clientes HTTP (MusicBrainz, TMDB, FanartTV, …)

AuraStudio.App/
  Platform/               APIs de Windows exclusivamente (WMI, Win32 P/Invoke,
                          Credential Manager, DiskPart/Format-Volume). Nada de
                          lógica de negocio aquí — solo el puente a la API nativa.
  Services/               implementaciones detrás de interfaz (Services/I*.cs),
                          para poder mockear en tests de ViewModels.
  ViewModels/             CommunityToolkit.Mvvm, propiedades parciales.
  Views/                  XAML + code-behind mínimo (solo resolución de DI y
                          glue de UI, nunca lógica de negocio).
```

Reglas duras:

- **MVVM estricto.** Nada de lógica de negocio en code-behind de `Views/*.xaml.cs`.
- **DI por constructor** vía `ServiceCollection` (`App.Services`, definido en
  `App.xaml.cs`). Nunca *service locator* dentro de un ViewModel — el único
  lugar permitido para `App.Services.GetRequiredService<T>()` es el
  code-behind de una página, para resolver el ViewModel que XAML no puede
  construir por DI directamente (ver patrón "página resuelve su VM" abajo).
- **Servicios detrás de interfaz** (`Services/I*.cs`) siempre que el
  servicio tenga estado, dependencias externas (red, disco, WMI) o vaya a
  necesitar un doble de prueba. Un servicio sin interfaz es una señal de
  que no se pensó en testear el ViewModel que lo consume.
- **Core nunca importa nada de Windows** (`System.Management`, WinRT, Win32).
  Si un módulo portado desde Swift necesita una API de plataforma, esa parte
  vive en `AuraStudio.App/Platform/`, no en Core — aunque el Swift original
  la tuviera junto a la lógica pura (el Swift mezcla más de lo que este port
  debe mezclar).

### Patrón: página resuelve su propio ViewModel

WinUI 3 no soporta inyectar un ViewModel con dependencias por constructor
directo en XAML (`<vm:XyzViewModel />` falla con `WMC0100` si el tipo no
tiene constructor público sin argumentos). El patrón en uso:

```csharp
// code-behind de la página, NO en el ViewModel ni en lógica de negocio
public XyzPage()
{
    InitializeComponent();
    ViewModel = App.Services.GetRequiredService<XyzViewModel>();
}
```

No se agrega un `IServiceLocator` propio ni un contenedor paralelo — es
justo el único punto donde `GetRequiredService` es aceptable.

## CommunityToolkit.Mvvm 8.4 — propiedades parciales

`[ObservableProperty]` en Mvvm 8.4 **requiere propiedades parciales**, no
campos privados con guion bajo — de lo contrario el analizador marca
`MVVMTK0045`. Eso a su vez requiere `<LangVersion>preview</LangVersion>` en
`AuraStudio.App.csproj` (sin eso, el generador de código no emite la mitad
de implementación de la propiedad parcial y el build falla con `CS9248`).

```csharp
public partial class XyzViewModel : ObservableObject
{
    [ObservableProperty]
    private partial string Nombre { get; set; }

    public XyzViewModel()
    {
        Nombre = "valor por defecto"; // los valores por defecto van en el
                                       // constructor — una propiedad parcial
                                       // no admite inicializador en la
                                       // declaración.
    }
}
```

## Detección de hardware: subclaseo Win32 clásico

No existe equivalente directo a `WM_DEVICECHANGE` en WinUI 3/WinRT. Se
captura con subclaseo clásico de Win32 sobre el `HWND` de la ventana:

- `SetWindowLongPtrW(GWLP_WNDPROC, …)` + `CallWindowProcW(...)` para
  encadenar al procedimiento de ventana original — **no** el patrón de
  `SetWindowSubclass`/comctl32 (requiere una clase `partial` con
  `[LibraryImport]` que no encaja bien con este subclaseo).
- El delegado del nuevo WndProc se guarda como **campo de instancia** para
  que el GC no lo recolecte mientras la ventana sigue apuntando a él (bug
  clásico de P/Invoke con delegados).
- `WM_DEVICECHANGE` con `DBT_DEVICEARRIVAL` se debounce (750 ms, colapsa la
  ráfaga de mensajes que dispara un solo evento físico) + un reintento a
  2.5 s para recoger la letra de unidad que Windows a veces asigna tarde.
  Implementado con `DispatcherQueueTimer` de un solo disparo, en el hilo de
  UI.
- La enumeración de discos usa **WMI** (`Win32_DiskDrive`, correlación con
  `Win32_PnPEntity`/USBSTOR), vía el paquete `System.Management` — no está
  en el BCL de .NET, hay que declararlo explícitamente.

## Seguridad de disco (principios no negociables del `CLAUDE.md` del repo)

Todo lo nuevo en `Platform/`/`Services/` que toque el disco del iPod hereda
sin excepción:

- Identificación multi-criterio, nunca por identificador hardcodeado.
- `Ambiguous` (dos o más discos califican) **nunca** expone candidatos
  seleccionables — se detiene y se le dice al usuario.
- **Re-verificación inmediata antes de toda operación destructiva**
  (formatear, flashear, borrar árbol) — nunca confiar en una consulta
  anterior, sin importar cuán reciente.
- Confirmación explícita mostrando nombre, identificador (letra de unidad
  en Windows, no BSD), tamaño y bus antes de tocar el disco.
- **Dos hechos nunca fusionados** (ST-016): `RunningFirmware` sale
  *solo* de los descriptores USB (qué firmware atiende el bus ahora);
  `VolumeProbe`/`aura.cfg` describen qué hay copiado en el disco. Un
  módulo nuevo que necesite "¿está Aura corriendo?" nunca lo infiere de
  archivos en el volumen.

## Strings es-MX

**Decidido en la Fase 1 (ST-079): clase estática, no `.resw`.**
`AuraStudio.App/Resources/AppStrings.cs` es la única tabla de texto de cara
al usuario; el razonamiento completo está en el comentario de esa clase y
resumido en `DECISIONS.md`. En corto: la app tiene un solo idioma por regla
del repo, así que lo que aporta MRT no se usa y a cambio cuesta verificación
en tiempo de compilación (un `x:Uid` mal escrito falla en silencio y deja el
texto vacío en pantalla).

Reglas de uso:

- Todo texto de cara al usuario **sale de `AppStrings`**, nunca literal en
  XAML ni en un ViewModel. Desde XAML se consume con
  `{x:Bind res:AppStrings.NavGeneral}` (x:Bind resuelve propiedades
  estáticas; su modo por omisión, OneTime, es el correcto para una
  constante), con `xmlns:res="using:AuraStudio.App.Resources"`.
- Los mensajes con datos se escriben como **método** (`DeviceAmbiguous(int)`,
  `SectionPendingDetail(string)`), no concatenando en la vista.
- Español de México sin voseo, siempre (regla del `CLAUDE.md` del repo).
- Si algún día hace falta un segundo idioma, se agrega el patrón del Swift
  (resolvedor de idioma + segunda tabla) **sin** migrar a `.resw`.

## Estado de sesión del dispositivo

`Services/IDeviceSessionService` (singleton) es la **única** fuente de "qué
iPod hay conectado" en toda la app. Ninguna página ni ViewModel vuelve a
consultar `IUsbDeviceWatcher` por su cuenta: eso llevaba a que dos pantallas
discreparan y a re-enumerar WMI varias veces por evento. Es el equivalente
del `IPodMonitor` que macOS instancia una sola vez en `ContentView` y le pasa
a todas las secciones.

Publica `State` (`Detecting`/`NotConnected`/`Connected`/`Ambiguous`),
`Device`, `Identification`, `StatusMessage`, `LibraryLocked` y el evento
`Changed`.

**Única excepción deliberada:** `DeviceSafetyValidator` sigue yendo directo al
watcher. Es correcto y no debe "arreglarse": la re-verificación previa a una
operación destructiva no puede confiar en estado cacheado, por reciente que
sea (regla del `CLAUDE.md` del repo).

### Nada de E/S de dispositivos en constructores ni antes de `Activate()`

**Regla dura, nacida de un defecto real que dejaba la app sin ventana.**
`UsbDeviceWatcher` enumeraba discos por WMI **en su constructor**. Como lo
resuelve la DI desde el constructor de `MainWindow`, esa enumeración corría en
el hilo de UI *antes* de `window.Activate()`: con un disco USB en mal estado
—el iPod a medio morir en el passthrough de Parallels, con `E:` registrada pero
sin responder— el proveedor de discos de WMI se atoraba, `MoveNext()` se
bloqueaba en código nativo, y la ventana quedaba creada con la geometría
correcta y **oculta para siempre**. Peor: mientras ese proceso siguiera vivo,
WMI quedaba atorado para todo el sistema.

Por lo tanto:

- **Un constructor que resuelve la DI es trivial**: asigna campos y se suscribe
  a eventos. No consulta WMI, no abre dispositivos, no toca la red, no enumera
  volúmenes.
- **El camino de arranque hasta `Activate()` no hace E/S de dispositivos.** El
  primer sondeo lo dispara la ventana desde su evento `Activated`
  (`IDeviceSessionService.StartInitialScan`, idempotente), ya en pantalla.
- **Toda consulta a WMI lleva plazo** (`EnumerationOptions` con `Timeout`,
  `ReturnImmediately = true`, `Rewindable = false` — es la combinación con la
  que WMI respeta el plazo en vez de esperar), **más** un presupuesto de tiempo
  externo en el sondeo como red de seguridad. Si se agota, se abandona y se
  reporta "no encontrado": mejor eso que una app colgada.
- **Un dispositivo que no responde se salta.** La regla que ya existía —"un
  disco que desaparece a mitad de consulta no tumba la enumeración"— se extiende
  a "un disco que no responde tampoco impide arrancar".
- La interfaz distingue **"todavía no busqué"** de **"busqué y no hay nada"**
  (`IUsbDeviceWatcher.HasScanned`, estado `Detecting`): arrancar afirmando que
  no hay iPod antes de haber mirado es mentirle al usuario.

Excepción acotada y consciente: leer un archivo local chico y propio (el JSON de
preferencias en `AppPreferences`) en un constructor es aceptable — no es un
dispositivo, no puede bloquearse en un driver y ya falla a prueba de todo. Si
alguna vez crece a algo que pueda tardar, se mueve fuera del constructor como
todo lo demás.

### ViewModels suscritos a la sesión son singleton

Las páginas se reconstruyen en cada navegación. Un ViewModel transitorio
suscrito a `Changed` dejaría una suscripción viva por cada visita — fuga y
trabajo duplicado. Por eso `ShellViewModel`, `DeviceListViewModel`,
`SettingsViewModel`, `InstallerViewModel` y `SyncViewModel` se registran como
**singleton**; es además el mismo motivo por el que macOS sube el ViewModel
del instalador al contenedor raíz (D-187): navegar y volver retoma la
pantalla donde iba.

## Ventana, respaldo y tema

`MainWindow` no tiene interfaz: hospeda `Views/ShellPage` y se ocupa solo de
lo propio de una ventana. Toda la UI vive en páginas, porque `Window` de
WinUI 3 no es un `FrameworkElement` (sin `DataContext`, sin `RequestedTheme`,
sin soporte pleno de `x:Bind`).

- **Respaldo**: Mica si `MicaController.IsSupported()`; si no,
  `DesktopAcrylicBackdrop`; si tampoco, fondo sólido del sistema. Mica es de
  Windows 11 y el mínimo del proyecto es 10.0.19041 — nunca puede quedar una
  ventana transparente. La página raíz va con `Background="Transparent"`: un
  fondo opaco taparía el Mica.
- **Tema**: `ElementTheme.Default` sigue al sistema; Ajustes lo fija en claro
  u oscuro solo para esta app. La barra de título se pide **aparte**
  (`AppWindow.TitleBar.PreferredTheme`): es del sistema, no del árbol XAML, y
  sin eso una app en oscuro sobre un Windows en claro queda con el marco del
  color contrario.
- **Geometría**: se guarda al cerrar y se restaura al abrir, pero solo si
  sigue cayendo sobre una pantalla que exista hoy — con un monitor
  desconectado, la posición vieja dejaría la ventana fuera de vista.

### Preferencias

`Services/IAppPreferences` sobre un JSON en
`%LOCALAPPDATA%\Aura Studio\preferences.json`. La app corre **sin empaquetar**
(`WindowsPackageType None`), así que `Windows.Storage.ApplicationData` no está
disponible. Nunca deja caer una excepción de disco a la UI: perder una
preferencia es recuperable, no abrir la app no lo es. **Las API keys no van
acá** — Credential Manager vía `IApiKeyStore` (D-203/ST-032).

### Sin `Visibility` en los ViewModels

Los ViewModels publican booleanos de dominio (`HasDevice`, `IsAmbiguous`,
`LibraryEnabled`); la vista los traduce con
`Converters/BoolToVisibilityConverter` (`ConverterParameter="invertir"` para
el caso negado). Traducir estado de dominio a tipos de interfaz es trabajo de
la vista.

## Contratos inmutables

`CONTRATO-firmware-studio.md`, `CONTRATO-formato-tema.md`,
`CONTRATO-dispositivo.md` y `docs/contracts/library-layout-v1.md` (todos en
la raíz de `Aura-Studio/`) son la frontera con el firmware. Ningún cambio a
lo que ahí se describe se implementa desde una sesión de Windows sin pasar
primero por una decisión abierta documentada — ni siquiera si "solo" es la
versión de Windows la que lo necesita.
