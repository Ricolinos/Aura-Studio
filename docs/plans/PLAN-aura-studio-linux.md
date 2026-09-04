# PLAN — Aura Studio para Linux (Avalonia UI): reconocimiento y propuesta

> **Estado: propuesta, sin aprobar.** No se ha escrito una línea de código.
> Este documento es el resultado del reconocimiento pedido (puntos 1–3) y la
> propuesta de arquitectura para que el dueño la revise antes de implementar.
>
> Fecha del reconocimiento: 2026-09-02, dentro de la VM Ubuntu 26.04 LTS ARM64
> (Parallels, Apple Silicon, sin Rosetta), la misma Mac que hospeda la VM de
> Windows.

---

## 0. Resumen para decidir rápido

- **Avalonia UI se confirma**, y con más margen del que sugería la corazonada.
  No es solo que sea XAML: es que los 5 154 renglones de ViewModels del port de
  Windows **no importan un solo tipo de WinUI** (dos excepciones puntuales,
  ambas de una línea). Lo que hay que traducir son 2 384 renglones de XAML con
  un catálogo de controles que Avalonia + FluentAvalonia cubre casi 1:1.
- **.NET 10 (`net10.0`), sin multi-targeting.** Ubuntu 26.04 lo tiene en su
  propio archivo (`dotnet-sdk-10.0`, 10.0.111, arm64) y `AuraStudio.Core` ya
  apunta ahí. **El problema de versiones que sufrió Windows no tiene análogo
  aquí** — fue del Windows SDK / Windows App SDK, no de .NET (§3).
- **Hay una corrección de premisa que cambia el plan:** los ViewModels **no
  están** en `AuraStudio.Core`; viven dentro del proyecto WinUI
  (`AuraStudio.App/ViewModels/`). Reutilizarlos exige promoverlos a un proyecto
  compartido — y eso **toca el árbol de Windows**, que hoy está verde y
  probado. Es la única decisión de este plan que necesita coordinación con el
  port de Windows, y está aislada en la Fase 1 (§6).
- **Hay un bloqueador real y no negociable para el instalador:**
  `mks5lboot` para Linux **no existe** — el Release publica un binario Mach-O
  arm64 (macOS), y el `.exe` de Windows es un cross-compile propio con la
  procedencia GPL §3 todavía abierta. Sin ese binario, la parte de flasheo DFU
  del port de Linux no se puede terminar (§8). El resto de la app —biblioteca,
  sincronización, temas, extras— no depende de él.

---

## 1. Lo que dicen `DECISIONS.md` y los `CLAUDE.md` (punto 1 del encargo)

### Lo que ya está decidido y este port hereda sin discusión

De `Aura-Studio/CLAUDE.md` y de los principios 1–7 de
`Aura/docs/plans/PLAN-aura-studio-windows-v2.md`:

1. **Seguridad de disco.** Identificación multi-criterio (removible + externo
   obligatorios; VID/PID `0x05AC`/`0x1261`, o modelo con "iPod", o vendor Apple
   + tamaño plausible), nunca identificadores fijos, **ambigüedad = detenerse**
   (jamás "el más probable"), **re-verificación inmediata antes de toda
   operación destructiva**, y confirmación explícita mostrando nombre,
   identificador, tamaño y bus.
2. **Dos hechos nunca fusionados** (ST-016): `runningFirmware` sale *solo* de
   los descriptores USB; `firmware` describe los archivos del disco. `isAura`
   exige evidencia de ejecución.
3. **Operaciones privilegiadas siempre nativas.** Pantalla propia que explica
   qué va a pasar y por qué, **antes** del diálogo del sistema. Nunca se le pide
   al usuario abrir una terminal ni escribir un comando. (Cumplible en Linux con
   polkit — §7.)
4. **Contratos inmutables desde aquí:** `CONTRATO-firmware-studio.md`,
   `CONTRATO-formato-tema.md`, `CONTRATO-dispositivo.md`,
   `docs/contracts/library-layout-v1.md`.
5. **GPL v2 de lo embebido:** pantalla de Licencias obligatoria antes de
   considerar completa cualquier v1.
6. **Español de México sin voseo** en todo texto de cara al usuario y en la
   documentación.
7. **Artefactos del firmware solo por Release**, verificados con SHA-256 contra
   `checksums.txt`.
8. **MVVM estricto**, DI por constructor, servicios detrás de interfaz, Core sin
   dependencias de plataforma, APIs nativas confinadas a `Platform/`.
9. **`DECISIONS.md` es la fuente de verdad**, numeración `ST-NNN`. Último
   asignado: **ST-139**. Este port empezaría en **ST-140**.

### Lo que NO está decidido

**No hay una sola decisión sobre Linux, Avalonia ni GTK en `DECISIONS.md`.**
Se buscó explícitamente (`linux`, `avalonia`, `gtk`) y no hay nada. Territorio
nuevo por completo: todo lo de este plan que se apruebe entra como decisión
nueva, no como aplicación de una existente.

### Lo que el port de Windows enseñó y aplica aquí

- **ST-078 → el principio detrás**: fijar la versión de la plataforma contra lo
  que la máquina *realmente* tiene, no contra lo que la documentación sugiere.
- **ST-079**: el acento y el idioma visual son de la plataforma anfitriona, no
  de macOS. En Linux eso significa: tipografía y acento del sistema
  (GNOME/Adwaita), no Segoe ni el acento de marca en cada botón.
- **ST-088 / ST-131**: nada de actualizar estado observable fuera del hilo de
  interfaz. Aquí se hereda entero, con `Dispatcher.UIThread` de Avalonia.
- **ST-122**: la app corría sin conciencia de DPI y por eso no le llegaba la
  rueda del mouse. **El análogo en Linux es Wayland + escalado fraccionario**
  (§9, riesgo 1) — se verifica en pantalla en la Fase 0, no al final.
- **Regla de arranque de `ARQUITECTURA.md`**: ningún constructor resuelto por DI
  hace E/S de dispositivos, y el camino hasta mostrar la ventana no toca discos.
  Nació de un defecto que dejaba la app sin ventana y colgaba WMI para todo el
  sistema. Aquí aplica igual contra UDisks2/D-Bus.

---

## 2. Estado real de `AuraStudio.Core` (punto 2 del encargo)

### Veredicto: está mucho mejor de lo que la pregunta temía, y peor de lo que la premisa decía

**Lo bueno.** `AuraStudio.Core` son **95 archivos, 15 163 renglones**, con:

- `TargetFramework: net10.0` puro. **Una sola dependencia externa: TagLibSharp
  2.3.0** (LGPL, multiplataforma, sin componentes nativos de Windows).
- **Cero** `using` de `System.Management`, `Windows.*`, `Microsoft.Win32`,
  `WinRT` o `Microsoft.UI`.
- **Cero** `DllImport`/`LibraryImport`/`Marshal`.
- **Cero** `OperatingSystem.IsWindows` / `RuntimeInformation` / `[SupportedOSPlatform]`.
- Las rutas se arman con `Path.Combine` + `Replace('/', Path.DirectorySeparatorChar)`
  de forma consistente (~20 sitios), que es exactamente el patrón correcto.
- 70 archivos de pruebas, **1 081 casos verdes** en un proyecto que también es
  `net10.0` puro.

**La corrección de premisa.** El encargo dice que el port de Windows «extrajo la
lógica de negocio **y los ViewModels** a AuraStudio.Core». Los ViewModels
**no están ahí**: están en `studio/windows/AuraStudio.App/ViewModels/`, dentro
del proyecto WinUI. Son 15 archivos, 5 154 renglones.

La buena noticia es que están limpios igual. Sus `using`, contados:

```
15 CommunityToolkit.Mvvm.ComponentModel      2 System.Collections.ObjectModel
 9 AuraStudio.App.Services   (interfaces)    2 AuraStudio.Core.Networking
 8 AuraStudio.Core.Library                   1 System.Reflection
 8 AuraStudio.App.Resources  (AppStrings)    1 System.Net.Http
 7 CommunityToolkit.Mvvm.Input               1 AuraStudio.App.Platform  ← única fuga
 7 AuraStudio.Core
 3 AuraStudio.Core.Installer
```

**Ni un solo `using Microsoft.UI` ni `Windows.*`.** Las únicas dos fugas reales,
ambas de una línea:

| Archivo | Fuga | Arreglo |
|---|---|---|
| `SyncViewModel.cs:36-37` | `Microsoft.UI.Dispatching.DispatcherQueue.GetForCurrentThread()` | `IUiDispatcher` detrás de interfaz |
| `SettingsViewModel.cs:3` | `using AuraStudio.App.Platform` | ya hay `IApiKeyStore` en Core; se usa esa |

Y `ARQUITECTURA.md` documenta una regla que resulta ser un **regalo** para
Avalonia: *«Sin `Visibility` en los ViewModels — publican booleanos de dominio
(`HasDevice`, `IsAmbiguous`, `LibraryEnabled`) y la vista los traduce»*. Avalonia
usa `IsVisible` (booleano) en vez de `Visibility`, así que los cuatro
convertidores de Windows **desaparecen** en vez de portarse.

### Las fugas de Windows que sí hay en Core, una por una

Son pocas y están acotadas. Ninguna obliga a un rediseño:

| Archivo | Qué es | Gravedad | Propuesta |
|---|---|---|---|
| `PhysicalDrivePath.cs` | Parsea `\\.\PhysicalDrive2`. Concepto exclusivo de Windows, aunque el código sea C# puro. | Baja | Se queda (no estorba) y se agrega `DevicePathLinux` (`/dev/sdX`, `/dev/nvmeXnY`) con el mismo rigor: rechazo estricto, nunca adivinar. Es el número que recibe el formateo — si se parsea mal, se formatea otro disco. |
| `PnpDeviceId.cs` | Parser de `USBSTOR\Disk&Ven_…`. | Baja | Se queda. El hermano de Linux es un parser de sysfs (`/sys/bus/usb/devices/*/{idVendor,idProduct,manufacturer,product}`), también función pura y probable sin hardware. **En Linux esto sale mejor que en Windows**: se leen el VID/PID reales y los descriptores de cadena, que es literalmente lo que ST-016 y el `CLAUDE.md` piden, sin pasar por las cadenas SCSI. |
| `Media/FfmpegLocator.cs` | Rutas de winget/chocolatey/scoop **y `PATH.Split(';')`**. | **Media — es un defecto** | El separador de `PATH` en Linux es `:`. Se usa `Path.PathSeparator` y se agregan las rutas de Linux. Corregir `Split(';')` es un arreglo válido para Windows también. |
| `Media/FfmpegLocator.cs:ExecutableName` | `const string = "ffmpeg.exe"` | Media | Pasa a resolverse por plataforma. |
| `FirmwareArtifacts.cs:106` | `const Mks5lbootFileName = "mks5lboot.exe"` | Media | Igual: nombre por plataforma. Ver §8. |
| `Installer/PrivilegedOperation.cs` | `DiskNumber` (int) y dos operaciones (`Pause/ResumeAppleMobileDeviceService`) que no existen en Linux. | Media | El `enum` crece con los casos de Linux; `DiskNumber` se generaliza a un identificador de dispositivo validado. **La forma del diseño se conserva entera**: lista cerrada de operaciones, `Validate()` que se vuelve a correr en el proceso elevado, `DryRun`. Es lo mejor que hay en el árbol y no se toca. |
| `Library/LibraryStore.cs:51` | Comparación de contención de rutas con `OrdinalIgnoreCase`. | **Alta en Linux — es un defecto latente** | En un sistema de archivos sensible a mayúsculas, `/home/x/Musica` y `/home/x/MUSICA` son carpetas distintas, y hoy `IsProtected` diría que la segunda está protegida. Protege de más, no de menos, así que no destruye nada — pero es incorrecto. La comparación tiene que ser sensible a mayúsculas en Linux. |
| `Library/LibraryStore.cs:14` | `DefaultRoot` = `SpecialFolder.MyDocuments` + `"Aura Studio"` | Baja | En Linux devuelve `$XDG_DOCUMENTS_DIR` o `$HOME`. Funciona; hay que verificar en pantalla que caiga donde el usuario espera. |
| `Installer/ReleaseCache.cs` | Comentario que dice `%LOCALAPPDATA%`. | Nula | Solo el comentario; la implementación real está en la app. En Linux: `$XDG_CACHE_HOME`. |

**Lo que hay que subrayar como hallazgo positivo:** `Installer/Fat32Formatter.cs`
escribe las estructuras FAT32 **él mismo** sobre un `Stream`
(`WriteStructures(Stream volume, Fat32Layout layout, …)`), e
`Installer/MasterBootRecord.cs` arma la tabla de particiones byte a byte. Ninguno
de los dos invoca `diskpart` ni `Format-Volume`. Eso significa que **el camino
destructivo —la parte más delicada del programa— se reutiliza tal cual en
Linux**; lo único que cambia es quién abre el dispositivo en crudo y con qué
permisos. Son 32 casos de prueba que ya cubren esa lógica y que valen para las
tres plataformas.

### Balance

| Capa | Renglones | Reutilización en Linux |
|---|---|---|
| `AuraStudio.Core` | 15 163 | **~99 %** (las fugas de la tabla son unos 60 renglones en total) |
| Pruebas de Core | 1 081 casos | **100 %**, corren tal cual con `dotnet test` |
| ViewModels | 5 154 | **~98 %** (dos fugas de una línea) |
| `Services/I*.cs` (interfaces) | ~200 | **~95 %** (renombrar `OpenInExplorer` → `OpenInFileManager`) |
| `Resources/AppStrings.cs` | 486 | **~96 %** (19 renglones nombran Windows) |
| `Services/*.cs` (implementaciones) | 2 427 | ~60 % |
| `Platform/*.cs` | 2 746 | **0 %** — se reescribe (§7) |
| `Views/*.xaml` + code-behind | 5 285 | Se traduce, no se reutiliza |

---

## 3. Compatibilidad de versiones: qué le pasó a Windows y qué aplica aquí (punto 3 del encargo)

Sí hay documentación, y es detallada: `studio/windows/docs/ESTADO-PORT.md`
§«Diagnóstico del fallo de XamlCompiler — RESUELTO», más ST-078.

### Qué pasó exactamente

Un `XamlCompiler` que moría **con código 1 y sin mensaje útil por consola**
(Visual Studio sí mostraba el rastro: `Unknown type 'Color'`, `Unknown member
'Width' en 'Window'`). Causa raíz: el csproj pedía
`net10.0-windows10.0.19041.0`, pero la VM solo tenía instalado el Windows SDK
`10.0.26100.0` — sin la carpeta `10.0.19041.0` bajo `Windows Kits\10\UnionMetadata`,
`Platforms\UAP` y `References`. Sin esa Union Metadata (`Windows.winmd`) no se
resuelven los tipos WinRT básicos.

Arreglarlo arrastró una cadena: TFM → `net10.0-windows10.0.26100.0`; Windows App
SDK **1.7.250310001 → 2.4.0** (la 1.7 no tiene `Microsoft.Windows.SDK.BuildTools`
compatible con el SDK 26100); y con la 2.4.0 hubo que subir `BuildTools` a
`10.0.26100.4654` porque NU1605 lo exigió por degradación de paquete.

### La conclusión que importa

**Nada de eso fue un problema de la versión de .NET.** Fue del **Windows SDK y
del Windows App SDK** — dos ejes que solo existen en el TFM
`netX.Y-windowsA.B.C.D`. `AuraStudio.Core` estuvo en `net10.0` puro desde el
principio y **nunca dio un problema de versión**.

En Linux **no existe ninguno de esos dos ejes**: el TFM es `net10.0` a secas, sin
componente de plataforma, sin Union Metadata, sin SDK del sistema operativo que
tenga que coincidir con nada. **La clase entera de fallo desaparece.**

### Versión propuesta: `net10.0`

```
$ apt-cache policy dotnet-sdk-10.0
  Candidate: 10.0.111-0ubuntu1~26.04.1   (arm64, archivo principal de Ubuntu)
```

- Es **exactamente el mismo TFM que `AuraStudio.Core` y sus pruebas** →
  **cero multi-targeting**, cero `#if`, un solo grafo de paquetes.
- .NET 10 es **LTS**.
- Está en el archivo de Ubuntu 26.04 para arm64, así que se instala con
  `apt` sin agregar el feed de Microsoft. **Recomendación explícita: usar el
  paquete de la distribución y NO agregar `packages.microsoft.com`** — tenerlos
  los dos en Ubuntu es una fuente conocida de instalaciones dobles y `dotnet
  --list-sdks` inconsistente. Un solo origen.
- No hay razón para bajar a `net8.0`: Avalonia 11 publica destinos
  `netstandard2.0` y `net8.0`, que `net10.0` consume sin problema.

### El análogo real del problema de Windows, y cómo se evita

El eje de versión frágil en Linux **no es .NET, es la pareja Avalonia ↔ tiempo
de ejecución gráfico** (X11/Wayland, mesa, fuentes). Se aplica la misma lección
que ST-078: **fijar la versión contra lo que la máquina realmente tiene, no
contra lo que la documentación promete**. Traducido a una compuerta:

> **La Fase 0 no cierra hasta que una ventana vacía de Avalonia con
> FluentAvalonia arranque en esta VM, en esta sesión de GNOME/Wayland, y se
> vea en pantalla** — con claro/oscuro del sistema, escalado fraccionario y
> rueda del mouse verificados. Recién ahí se fijan las versiones exactas en el
> csproj. **Antes de eso no se escribe una sola vista.**

Es la compuerta que el port de Windows habría querido tener antes de escribir
XAML a ciegas.

---

## 4. Validación de la arquitectura: Avalonia, y por qué no las otras

Se pidió validar, no asumir. Con el reconocimiento en la mano:

### Avalonia UI — se confirma

| Argumento | Evidencia del reconocimiento |
|---|---|
| Los ViewModels ya son portables | 5 154 renglones, cero `using` de WinUI, dos fugas de una línea |
| CommunityToolkit.Mvvm funciona igual | Es una librería de .NET puro, sin nada de plataforma. `[ObservableProperty]`, `[RelayCommand]`, `WeakReferenceMessenger` idénticos |
| El catálogo de controles se cubre | Inventario real del XAML: `TextBlock` 254, `StackPanel` 117, `Button` 72, `Grid` 62, `Border` 39, `NavigationViewItem` 29, `ItemsControl` 28, `FontIcon` 25, `DataTemplate` 22, `RadioButton` 16, `InfoBar` 16, `ListView` 11, `ScrollViewer` 10, `CheckBox` 10, `TextBox`/`ComboBox` 6, `SelectorBarItem` 6, `ToggleSwitch` 5, `ProgressBar` 5, `NavigationView` 4… **Todo eso existe en Avalonia 11 o en FluentAvalonia** |
| La tabla de Canciones no necesita `DataGrid` | `SongsPage.xaml` no usa `DataGrid` (WinUI 3 no tiene): son encabezados con `ItemsControl` + renglones con `ListView`. En Avalonia son `ItemsControl` + `ListBox`. La lógica de columnas ya está en Core (`MusicTableColumn.cs`, 13 casos) |
| `Visibility` desaparece | ST de `ARQUITECTURA.md`: los VM publican booleanos de dominio. Avalonia usa `IsVisible` booleano → los 4 convertidores de Windows se borran |
| DI idéntica | `Microsoft.Extensions.DependencyInjection` es el mismo paquete |
| El patrón «la página resuelve su VM» mejora | En Avalonia se puede inyectar el VM por constructor de verdad, sin el rodeo de `App.Services.GetRequiredService` que WinUI obliga (`WMC0100`) |

**Lo que hay que saber que sí cambia** (reglas de traducción, no obstáculos):

- `x:Bind` **no existe** en Avalonia. Se usa `{CompiledBinding}` con
  `x:CompileBindings="True"` en cada `UserControl` — que da la misma
  verificación en tiempo de compilación que motivó la decisión de `AppStrings`
  como clase estática en ST-079. **La razón de esa decisión sobrevive intacta.**
- `{ThemeResource}` → `{DynamicResource}`.
- `Visibility` → `IsVisible`.
- `<Page>` → `<UserControl>`; `Frame` + `NavigationView` los da FluentAvalonia.
- Estilos: Avalonia usa selectores tipo CSS (`Style Selector="Button.primary"`)
  y `ControlTheme`. `Resources/Styles.xaml` y `AuraPalette.xaml` se re-escriben,
  pero **`AuraPalette` sigue siendo una transcripción de
  `Generated/AuraPalette.swift`**, no valores inventados — la regla del
  `CLAUDE.md` se mantiene palabra por palabra.
- Tipografía e iconos: Segoe UI Variable y Segoe Fluent Icons **no existen en
  Linux y no se pueden redistribuir**. Se usa la tipografía del sistema
  (Adwaita/Ubuntu Sans en GNOME) y **Fluent UI System Icons** (MIT, de
  Microsoft, redistribuible) o el conjunto de símbolos de FluentAvalonia. Es la
  misma disciplina de licencias que el `CLAUDE.md` impone para los temas con
  SF Pro/SF Symbols. **Y se hereda la lección de ST-079: los glifos se verifican
  renderizándolos y mirándolos, no se escriben de memoria.**

### GTK4 nativo — descartado, y ahora con números

No es «más esfuerzo» en abstracto: es que **tira a la basura los 5 154 renglones
de ViewModels**. GTK4 con GObject no habla `INotifyPropertyChanged`; habría que
reescribir todo el patrón MVVM contra propiedades de GObject y `GtkExpression`,
o construir una capa puente que sería más código que las vistas. Y el XAML no se
traduce, se rehace en Blueprint/`.ui`. Confirmado el descarte.

### Uno Platform — la única alternativa que merecía mirarse, y por qué tampoco

Uno es el único camino que permitiría reutilizar el XAML de WinUI **casi
literal** (mismos espacios de nombres `Microsoft.UI.Xaml`), con destino Linux
por Skia. Se consideró en serio y se descarta por tres razones concretas:

1. **El premio es chico.** El XAML son 2 384 renglones. Lo caro de este port
   nunca fue el XAML — es la capa de plataforma (§7), y Uno no ayuda ahí ni un
   poco.
2. **El precio es arrastrar el sistema de tipos de WinUI a Linux**, que es
   exactamente la dependencia de la que este port quiere salir. El objetivo
   declarado es que el Core sea reutilizable *entre* plataformas, no que Linux
   herede el acoplamiento de Windows.
3. **El escritorio Linux es el destino menos maduro de Uno**, mientras que para
   Avalonia es el escenario de primera clase.

**Recomendación: Avalonia UI 11.x + FluentAvalonia. Sin reservas.**

---

## 5. Estructura de proyecto propuesta

```
Aura-Studio/
  studio/
    AuraStudio/                       (macOS, Swift — no se toca)
    windows/                          (WinUI 3 — solo se toca lo de la Fase 1)
      AuraStudio.Core/                ← se comparte, no se copia
      AuraStudio.App/
      tests/AuraStudio.Core.Tests/
    linux/                            ← NUEVO
      AuraStudio.Linux.slnx
      AuraStudio.Desktop/             app Avalonia, net10.0
        Program.cs
        App.axaml(.cs)                DI raíz (ServiceCollection)
        MainWindow.axaml(.cs)
        Views/                        .axaml + code-behind mínimo
        Platform/                     APIs de Linux, y NADA más
          UDisksDiskEnumerator.cs
          SysfsUsbReader.cs
          PolkitPrivilegedRunner.cs
          PrivilegedHost.cs
          SecretServiceCredentialStore.cs
          SkiaImageResizer.cs
          SkiaPlaylistArtGenerator.cs
          SkiaCoverThumbnailCache.cs
          ExifReader.cs
          FfmpegRunner.cs             (portable desde Windows, casi tal cual)
          VolumeManager.cs            xdg-open / udisksctl unmount
        Services/                     implementaciones de las interfaces
        Resources/
          AuraPalette.axaml           transcripción de AuraPalette.swift
          Styles.axaml
      tools/
      scripts/
        fetch-firmware.sh             (se reusa el de la raíz)
        make-appimage.sh              (Fase 7)
      docs/
        ESTADO-PORT-LINUX.md          bitácora viva, igual que Windows
        MAPPING-LINUX.md
      artifacts/                      gitignorado, lo puebla fetch-firmware.sh
    shared/                           ← NUEVO (ver §6)
      AuraStudio.Presentation/        ViewModels + interfaces + AppStrings
```

**Por qué `studio/linux/` y no un repositorio aparte:** `AuraStudio.Core` se
referencia por ruta relativa (`ProjectReference`), igual que hace Windows. Un
repo separado obligaría a publicar el Core como paquete NuGet, con su propio
versionado y su propia deriva — exactamente lo que el `CLAUDE.md` prohíbe para
los artefactos del firmware, por las mismas razones.

### Los csproj

**`AuraStudio.Desktop/AuraStudio.Desktop.csproj`**

```xml
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <!-- Sin componente de plataforma en el TFM: es justo el eje que
         hizo fallar al XamlCompiler de Windows (ST-078) y en Linux
         no existe. Mismo TFM que Core y que las pruebas. -->
    <TargetFramework>net10.0</TargetFramework>
    <RuntimeIdentifiers>linux-arm64;linux-x64</RuntimeIdentifiers>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
    <!-- Igual que en Windows: CommunityToolkit.Mvvm 8.4 solo genera
         [ObservableProperty] sobre propiedades parciales (MVVMTK0045). -->
    <LangVersion>preview</LangVersion>
    <BuiltInComInteropSupport>false</BuiltInComInteropSupport>
    <ApplicationManifest>app.manifest</ApplicationManifest>
    <AvaloniaUseCompiledBindingsByDefault>true</AvaloniaUseCompiledBindingsByDefault>
  </PropertyGroup>

  <ItemGroup>
    <!-- Versiones EXACTAS a fijar en la Fase 0, después de verificar que
         una ventana arranca en esta VM. No antes. -->
    <PackageReference Include="Avalonia" Version="11.*" />
    <PackageReference Include="Avalonia.Desktop" Version="11.*" />
    <PackageReference Include="Avalonia.Themes.Fluent" Version="11.*" />
    <PackageReference Include="Avalonia.Diagnostics" Version="11.*"
                      Condition="'$(Configuration)'=='Debug'" />
    <PackageReference Include="FluentAvaloniaUI" Version="2.*" />
    <PackageReference Include="Microsoft.Extensions.DependencyInjection" Version="9.0.0" />
    <!-- D-Bus: UDisks2 (discos) y Secret Service (claves). Reemplaza a
         System.Management/WMI y al Credential Manager. -->
    <PackageReference Include="Tmds.DBus.Protocol" Version="0.*" />
    <!-- Imágenes: no hay WIC en Linux. Skia ya viene con Avalonia, pero
         se declara explícito porque Platform/ lo usa directo. -->
    <PackageReference Include="SkiaSharp" Version="3.*" />
  </ItemGroup>

  <ItemGroup>
    <ProjectReference Include="../../windows/AuraStudio.Core/AuraStudio.Core.csproj" />
    <ProjectReference Include="../../shared/AuraStudio.Presentation/AuraStudio.Presentation.csproj" />
  </ItemGroup>

  <ItemGroup>
    <!-- Artefactos del firmware junto al ejecutable, igual que Windows:
         es donde los busca FirmwareArtifacts.DirectoryFor. -->
    <None Include="../artifacts/**/*" LinkBase="artifacts"
          CopyToOutputDirectory="PreserveNewest" />
  </ItemGroup>

</Project>
```

**Notas sobre decisiones del csproj que conviene discutir:**

- `TreatWarningsAsErrors` desde el primer día, como los tres csproj de Windows.
  La compuerta «0 warnings» se vuelve mecánica en vez de manual.
- `AvaloniaUseCompiledBindingsByDefault` es el equivalente de haber tenido
  `x:Bind` por omisión: un `{Binding}` con nombre mal escrito falla en
  compilación en vez de dejar el texto vacío en pantalla — que es literalmente
  el argumento de ST-079 contra los `.resw`.
- Sobre `AuraStudio.Core.csproj` referenciado desde `studio/windows/`: es feo
  que un proyecto de Linux apunte a una carpeta llamada «windows». **Propuesta
  a decidir por el dueño:** mover `AuraStudio.Core` y sus pruebas a
  `studio/shared/`, que es donde ya pertenecen conceptualmente. Es un `git mv`
  más dos rutas de `ProjectReference`, pero **toca el árbol de Windows** y
  merece su propia decisión. Si se prefiere no tocarlo ahora, la ruta relativa
  funciona igual y se difiere.

---

## 6. La única pieza que exige tocar el port de Windows

Los ViewModels, las interfaces `Services/I*.cs` y `Resources/AppStrings.cs` están
dentro del proyecto WinUI. Hay tres caminos:

**(a) Promoverlos a `studio/shared/AuraStudio.Presentation/` — recomendado.**
Proyecto `net10.0` que depende de `AuraStudio.Core` + `CommunityToolkit.Mvvm`.
Windows y Linux lo referencian los dos. Es un movimiento mecánico (cambio de
espacio de nombres), precedido de tres arreglitos:

1. `IUiDispatcher` detrás de interfaz → `SyncViewModel` deja de tocar
   `DispatcherQueue`. Implementaciones: `DispatcherQueue` en Windows,
   `Dispatcher.UIThread` en Avalonia.
2. `SettingsViewModel` usa `IApiKeyStore` (que ya está en Core) en vez de
   `AuraStudio.App.Platform`.
3. `AppStrings` se parte: la tabla compartida (≈467 renglones) y una tabla
   por plataforma para los 19 renglones que nombran a Windows («Abrir en el
   Explorador», «winget install Gyan.FFmpeg», el texto del Administrador de
   credenciales, la guía de «Dispositivos Apple»). En Linux ese texto habla del
   gestor de archivos, de `apt install ffmpeg` y del llavero de GNOME.

**El costo real y honesto:** ese movimiento deja el port de Windows sin compilar
hasta que se termina, y **la compuerta que lo verifica
(`dotnet build -p:Platform=ARM64` con la app WinUI) solo corre en la VM de
Windows**. Así que es trabajo que se hace **desde la VM de Windows**, en una
sesión propia, con las compuertas de ese port. **No se puede hacer bien desde
aquí.** Es la única dependencia cruzada de este plan y por eso es su propia
fase.

**(b) Compilación enlazada** — `<Compile Include="../../windows/AuraStudio.App/ViewModels/**/*.cs" />`.
No toca Windows en absoluto y el precedente existe en el repo
(`tools/ImageResizerCheck` «compila el mismo archivo fuente del resizer sin
arrastrar WinUI»). Sirve para arrancar y probar que la interfaz de Avalonia
funciona antes de pedir un movimiento en el árbol de Windows. Como estado final
para 5 154 renglones es frágil: cualquiera que edite un VM en Windows rompe
Linux sin enterarse.

**(c) Duplicar** — no. Dos copias divergen; es lo contrario del objetivo.

**Propuesta: (b) para arrancar en la Fase 1, (a) como cierre coordinado en la
Fase 2**, para que la interfaz de Linux ya esté probada cuando se pida tocar el
árbol de Windows. Si el dueño prefiere hacer (a) de una vez, se hace primero y
este plan empieza en la Fase 2.

---

## 7. La capa de plataforma: mapa 1:1

Es el 100 % del trabajo genuinamente nuevo: 2 746 renglones de `Platform/` que
se reescriben.

| Windows (`Platform/`) | Linux | Notas |
|---|---|---|
| `WmiDiskEnumerator.cs` (322) — WMI `Win32_DiskDrive` | **UDisks2 por D-Bus** (`org.freedesktop.UDisks2`) | Da removible, bus de conexión (`usb`), modelo, vendor, tamaño, puntos de montaje y **señales de cambio** (`InterfacesAdded`, `PropertiesChanged`) |
| Subclaseo Win32 de `WM_DEVICECHANGE` en `MainWindow` | **Las mismas señales de UDisks2** | **Mejora clara**: desaparece el subclaseo de `SetWindowLongPtrW`, el delegado que hay que mantener vivo contra el GC, el debounce de 750 ms y el reintento a 2.5 s. D-Bus entrega un evento por cambio real. Se conserva un debounce corto por prudencia |
| Cadenas SCSI vía `PnpDeviceId` | **sysfs**: `/sys/bus/usb/devices/*/{idVendor,idProduct,manufacturer,product}` | **Mejora sustancial para ST-016 y para el `CLAUDE.md`**: se leen el VID/PID reales (`05ac`/`1261`) y los descriptores de cadena del USB, sin root. Es *la* señal que el `CLAUDE.md` llama «la única que sobrevive cuando el USB lo atiende Aura/Rockbox» |
| `PrivilegedRunner.cs` (218) — verbo `runas` + UAC | **`pkexec` (polkit)** | **La arquitectura se conserva entera**: relanzar el propio ejecutable con una petición JSON, que el proceso elevado **vuelve a validar** antes de tocar nada, más `DryRun`. Solo cambia el verbo. Y **se cumple la promesa del `CLAUDE.md`**: polkit muestra un diálogo nativo de GNOME, nunca se le pide al usuario abrir una terminal. La pantalla propia que explica qué va a pasar sigue yendo *antes* |
| `PrivilegedHost.cs` (478) — WMI + `SafeFileHandle` | Misma forma, con `/dev/…` | `Fat32Formatter.WriteStructures` y `MasterBootRecord` **se reutilizan tal cual**: ya escriben sobre un `Stream`. Aquí ese `Stream` es un `FileStream` sobre `/dev/sdX` abierto por el proceso elevado |
| `VolumeLock.cs` (274) — `FSCTL_LOCK_VOLUME` | `umount` + `O_EXCL` sobre el dispositivo de bloque | En Linux abrir un dispositivo de bloque con `O_EXCL` es el candado, y el núcleo lo respeta |
| `CredentialStore.cs` (167) — Credential Manager | **Secret Service por D-Bus** (llavero de GNOME / libsecret) | Misma forma que el Llavero de macOS. Cumple D-203/ST-032: las claves nunca en un JSON de preferencias |
| `ImageResizer.cs`, `PlaylistArtGenerator.cs`, `CoverThumbnailCache.cs`, `PhotoExifReader.cs` (660) — WIC | **SkiaSharp** | Avalonia ya trae Skia. **La estrategia de ST-083 se hereda exacta**: macOS *pide* JPEG baseline a ImageIO; WIC no lo permite, así que Windows **verifica** la salida con `JpegMarkers.cs` de Core y falla si no lo es. Skia también produce baseline por omisión → mismo verificador, misma prueba, mismo `tools/ImageResizerCheck` |
| `FfmpegRunner.cs` (174) | **Se porta casi tal cual** | Solo usa `System.Diagnostics.Process`. Y en Linux ffmpeg es `apt install ffmpeg`, no la odisea de winget |
| `DfuFlashRunner.cs` (192) | Misma forma, otro binario | **Bloqueado por §8** |
| `AppleDeviceSupport.cs` (112) — servicio móvil de Apple | **No aplica** | En Linux no hay servicio de Apple que se quede con el USB. El DFU va por libusb con una regla de udev — **más simple que Windows**, sin controlador propietario. Los dos casos `Pause/ResumeAppleMobileDeviceService` de `PrivilegedOperation` no tienen contraparte |
| `VolumeManager.cs` (58) — `explorer.exe` + verbo COM | `xdg-open` y `udisksctl unmount` | **Mejora**: `udisksctl` sí informa si la expulsión falló. Es justo el pendiente que Windows dejó anotado en «Post-plan» |

**Observación que vale la pena decir en voz alta:** varias piezas salen *mejor*
en Linux que en Windows — los descriptores USB reales para ST-016, las señales
de UDisks2 en lugar del subclaseo Win32, la expulsión que informa su resultado.
No es un port de segunda.

---

## 8. El bloqueador: `mks5lboot` para Linux

Verificado en el árbol:

```
studio/windows/artifacts/mks5lboot     → Mach-O 64-bit arm64 executable   (macOS)
studio/windows/artifacts/mks5lboot.exe → PE32, Intel i386                 (Windows)
```

El Release del firmware publica **un solo `mks5lboot`, y es Mach-O de macOS** —
el comentario de `mks5lboot.exe.origin` lo llama «binario de Unix», pero el
archivo real es Mach-O arm64. Windows resolvió esto con un cross-compile propio
cuya procedencia GPL §3 **sigue abierta** («se compiló de un árbol sucio…
bloquea el release público»).

**Para Linux no hay ningún camino que respete el `CLAUDE.md` hoy**, porque la
regla es *«Artefactos del firmware solo por Release»* y no hay un ELF
`linux-arm64`/`linux-x64` en ningún Release. Las opciones, todas cruzando la
frontera con `Aura-Firmware`:

1. **Que el Release publique `mks5lboot-linux-arm64` y `-x64`** (y de paso
   `-windows-x64`, que cerraría también el pendiente GPL de Windows). Es lo
   correcto y lo que el contrato §A pide. **Requiere una decisión coordinada con
   el firmware y una entrada en `CONTRATO-firmware-studio.md` §A.**
2. Cross-compilar desde aquí — **prohibido por el `CLAUDE.md`** («nunca compilar
   el firmware desde aquí»), y repetiría el problema de procedencia de Windows.
3. Diferir todo el instalador DFU a una fase posterior y entregar primero la app
   sin flasheo.

**Recomendación: (1) como decisión abierta a plantear al dueño ahora, y (3) como
plan de trabajo mientras tanto.** El instalador es una de nueve pantallas; la
biblioteca, la sincronización, los temas y los extras —que es donde el usuario
pasa el 95 % del tiempo— no dependen de ese binario.

Consecuencia directa en el orden de fases: **el instalador va al final, no al
principio**, al revés que en el port de Windows.

---

## 9. Fases propuestas

Cada fase = una o más sesiones abiertas en `Aura-Studio/`. Compuertas de salida
obligatorias en todas, calcadas del protocolo del plan de Windows:

- `dotnet build studio/linux` → **0 errores, 0 warnings**
- `dotnet test studio/windows/tests/AuraStudio.Core.Tests` → **1 081/1 081**
  (el Core se comparte: si Linux lo rompe, se sabe aquí)
- **Arrancar la app y verificarlo en pantalla**, con captura en
  `studio/linux/docs/ESTADO-PORT-LINUX.md`
- `MAPPING-LINUX.md` actualizado
- Decisiones nuevas → `DECISIONS.md` como `ST-140+`

---

### Fase 0 — Piso verificado *(corta; nada de app todavía)*

1. `sudo apt install dotnet-sdk-10.0` (paquete de Ubuntu, **no** el feed de
   Microsoft). Verificar `dotnet --info`.
2. **Compilar `AuraStudio.Core` y correr sus 1 081 pruebas en Linux/ARM64.**
   Es el primer dato duro que falta y no cuesta nada obtenerlo. Si algo falla
   ahí, se sabe antes de invertir en interfaz.
3. Ventana vacía de Avalonia + FluentAvalonia arrancando **en esta sesión de
   GNOME/Wayland**, verificada en pantalla: claro/oscuro del sistema, escalado
   fraccionario, rueda del mouse, redimensionado.
4. **Recién ahí** se fijan las versiones exactas en el csproj y se escribe
   `ESTADO-PORT-LINUX.md`.

**Criterio de aceptación:** una captura de una ventana vacía y un `dotnet test`
verde. **Sin esto no se escribe una vista.**

### Fase 1 — Cimientos: sesión de dispositivo, navegación, tema

- ViewModels por compilación enlazada (§6, opción b) para no bloquearse.
- `Platform/UDisksDiskEnumerator.cs` + `SysfsUsbReader.cs`, detrás de
  `IUsbDeviceWatcher` (la interfaz ya existe y ya es portable).
- `IDeviceSessionService` cableado. **Se hereda la regla dura**: ningún
  constructor resuelto por DI hace E/S de dispositivos; el primer sondeo lo
  dispara la ventana ya en pantalla; toda consulta a D-Bus lleva plazo.
- Shell con `NavigationView` de FluentAvalonia, misma estructura que Windows.
- `Resources/AuraPalette.axaml` transcrito de `Generated/AuraPalette.swift`.
- Tipografía e iconos del sistema; glifos **verificados renderizándolos**.

**Criterio:** navegación completa, tema claro/oscuro siguiendo a GNOME, y el
iPod real detectado por USB con su VID/PID leído de sysfs.

### Fase 2 — `AuraStudio.Presentation` *(desde la VM de Windows)*

El movimiento de §6 opción (a), con las compuertas del port de Windows.
Al terminar, Linux cambia la compilación enlazada por un `ProjectReference`.

### Fase 3 — Biblioteca local

Es la fase más grande y la que más valor entrega. `LibraryStore`,
`LibraryIngest`, la tabla de Canciones, Artistas, Álbumes, Listas, Fotos, Video.
Casi todo ya está en Core; aquí es traducir vistas.

Incluye la corrección de `LibraryStore.cs:51` (§2) y **una prueba nueva que la
cubra en un sistema de archivos sensible a mayúsculas**.

**Punto de atención heredado de ST-087, ST-102 y ST-107:** la carpeta de
biblioteca se comparte entre macOS, Windows y ahora Linux. El catálogo se
escribe canónico y se lee tolerante. Y **los acentos en NFC (ST-062) importan
más aquí**: Linux guarda los bytes del nombre tal cual, sin la normalización de
APFS. Es candidato a un caso de prueba propio.

### Fase 4 — Sincronización al iPod

`SyncPlanner`/`LibrarySyncEngine`/`LibrarySyncFinalizer` ya están en Core.
Falta el montaje/desmontaje, el marcador `sync-pending.json` y ffmpeg.

**Criterio de aceptación fuerte, calcado del de Windows:** comparar los archivos
del contrato que produce Linux contra los que produce macOS **sobre la misma
biblioteca de prueba**. Windows dejó ese punto sin cerrar; conviene no
heredarlo.

### Fase 5 — Temas

`ThemeValidator`/`ThemePackager`/`ThemeInstaller` ya están en Core. Se valida
**antes** de instalar; nunca se ofrece compartir un tema con
`theme_redistributable: no` — se deshabilita con explicación, no se oculta.

### Fase 6 — Ajustes, servicios en línea y Extras

`SecretServiceCredentialStore` para fanart.tv y TMDB. `AppPreferences` en
`$XDG_CONFIG_HOME/aura-studio/preferences.json`.

### Fase 7 — Instalador DFU **(bloqueada por §8)**

Solo empieza cuando exista un `mks5lboot` de Linux por Release. Lo que sí se
puede adelantar sin él: la pantalla de **Licencias** (obligatoria por GPL v2
antes de considerar completa cualquier v1) y las pantallas del asistente.

### Fase 8 — Empaquetado y auditoría de paridad

Auditoría pantalla por pantalla contra macOS y Windows. Empaquetado a decidir
con el dueño: **AppImage** (nada que instalar, corre en cualquier distro) vs.
**Flatpak** (integración con GNOME Software, pero el sandbox complica el acceso
a dispositivos de bloque y a polkit) vs. **.deb**. Recomendación preliminar:
AppImage primero, por la misma lógica con la que Windows eligió Inno Setup por
usuario y sin UAC (ST-135) — y porque el sandbox de Flatpak choca de frente con
lo que esta app necesita hacer con el disco.

---

## 10. Riesgos vivos del port de Linux

1. **Wayland y escalado fraccionario.** Avalonia en Linux usa X11 como respaldo
   maduro; bajo GNOME Wayland corre por XWayland. Es el análogo exacto de
   ST-122 (la app sin conciencia de DPI a la que no le llegaba la rueda del
   mouse). **Se verifica en pantalla en la Fase 0**, no al final.
2. **`mks5lboot` inexistente para Linux** (§8). Bloquea el instalador. Es lo
   único que necesita una decisión del dueño **antes** de arrancar.
3. **DFU por passthrough de Parallels.** El modo disco ya está probado en la VM
   de Windows; el modo DFU **no** — y tiene otro VID/PID, así que hay que
   re-autorizar el passthrough. En Linux además hace falta una regla de udev
   para que el usuario pueda hablarle por libusb sin ser root. Es el riesgo #1
   heredado del plan de Windows, todavía abierto.
4. **La carpeta compartida de Parallels (`/media/psf/…`).** Windows anotó que
   compilar .NET sobre el share puede ser lento o dar bloqueos raros. Aquí ya se
   nota. **Propuesta: el checkout de trabajo va a disco local de la VM** y se
   sincroniza por git; solo la biblioteca de medios se lee del share.
5. **Deriva del contrato.** macOS y el firmware siguen evolucionando (contrato
   v17 vigente). Cada fase que toque contrato relee la versión vigente; no
   confía en lo que este plan diga de memoria.
6. **Tres apps sobre la misma carpeta de biblioteca.** El «Post-plan» de Windows
   ya anotaba que falta un candado suave entre macOS y Windows. Con Linux son
   tres. No lo empeora este port, pero sube la probabilidad de que ocurra.

---

## 11. Lo que necesito del dueño antes de escribir código

1. **¿Se autoriza pedir un `mks5lboot` de Linux al Release del firmware?**
   Es la única decisión que bloquea una fase entera. Si la respuesta es «todavía
   no», se planifica con el instalador al final y se sigue.
2. **¿Se mueve `AuraStudio.Core` a `studio/shared/`?** Limpia la rareza de que
   Linux apunte a `studio/windows/AuraStudio.Core`, pero toca el árbol de
   Windows. Si no, la ruta relativa funciona igual.
3. **`AuraStudio.Presentation` (§6): ¿ahora o después?** Recomiendo después
   (Fase 2), con la interfaz de Linux ya probada. Es trabajo que se hace desde
   la VM de Windows, no desde aquí.
4. **Empaquetado (§Fase 8):** AppImage, Flatpak o .deb. No bloquea nada ahora,
   pero conviene saberlo pronto porque condiciona cómo se accede al disco.
5. **¿El iPod se va a pasar a esta VM por USB?** Hoy `lsusb` no lo ve. La Fase 1
   no cierra sin él.

---

## Apéndice — Entorno verificado (2026-09-02)

```
Ubuntu 26.04 LTS (Resolute Raccoon), aarch64, kernel 7.0.0-29-generic
GNOME sobre Wayland
dotnet:            NO instalado
dotnet-sdk-10.0:   disponible en el archivo de Ubuntu, 10.0.111-0ubuntu1~26.04.1 (arm64)
ffmpeg:            NO instalado
lsusb/lsblk/udevadm: presentes
iPod:              NO conectado (lsusb solo muestra los aparatos virtuales de Parallels)
git:               NO instalado en esta VM  ← hace falta para las compuertas
```
