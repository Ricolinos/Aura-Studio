# Propuesta B7b — selector de idioma, aplicación de cultura, instalador y B7c

> PLAN-studio-ajustes-3.md §3 (Fase B7b). Encargo de la Maestra, mecánico,
> mientras el Experto cierra B7a real (extracción → `.resx`/`ResourceManager`
> aplicada). **Documento, no código**: propone diseño y deja las decisiones
> de implementación para quien escriba B7b. Contra el árbol de
> `origin/main` en el momento de escribir esto (B7a real todavía no
> mergeado); los nombres de tipos/miembros nuevos son propuestas, no
> contrato cerrado.

## 1. Selector de idioma en Ajustes

### Dónde vive el ajuste

Mismo lugar y mismo patrón que `AppTheme` (`IAppPreferences.cs`,
`AppPreferences.cs`): un campo nuevo en `PreferencesFile`, expuesto por
`IAppPreferences`, con el mismo criterio de resiliencia que ya tiene toda
la clase — un valor que no se puede leer o que no se reconoce cae al
predeterminado, nunca rompe el arranque.

**Propuesta de tipo**: `string? Language` (no un enum como `AppTheme`).
Motivo: los seis valores son nombres de cultura reales
(`es`/`en`/`ja`/`de`/`ru`/`fr`), y una cultura YA es una cadena en todo el
resto de .NET (`CultureInfo.GetCultureInfo(name)`); un enum obligaría a un
`switch` de ida y vuelta entre el enum y el nombre de cultura en cada
punto de uso, sin ganar nada — a diferencia de `AppTheme`, donde
`Light`/`Dark`/`System` no son nombres que ninguna API de .NET espera.
`null` = "Seguir al sistema" (el valor por omisión, sin que haga falta un
tercer caso especial como `AppTheme.System`). Guardado como texto, mismo
criterio que el resto de las preferencias de opción (sobrevive un valor
que una build anterior no conocía, en vez de romper la lectura del
archivo entero).

```csharp
// IAppPreferences.cs
string? Language { get; set; } // null = "Seguir al sistema"; si no, "es"/"en"/"ja"/"de"/"ru"/"fr"

// AppPreferences.cs — PreferencesFile
public string? Language { get; init; }
```

### Cómo se muestra

Cada idioma en **su propio idioma** (como pide el encargo, y como ya hacen
casi todos los selectores de idioma de cualquier sistema — nadie quiere
leer "Japanese" para encontrar japonés): `Español`, `English`, `日本語`,
`Deutsch`, `Русский`, `Français`. Son seis literales fijos — el nombre de
un idioma en sí mismo NO se traduce nunca, así que no son candidatos a
`.resx` (paridad con como ya lo hace `ThemeOptions`/`ThemeSystem` en
`AppStrings`, que si son textos normales). "Seguir al sistema" sí es
texto de interfaz y sí va en `.resx`, en las seis traducciones.

**Orden de la lista**: "Seguir al sistema" primero, siempre — es el valor
por omisión, y ponerlo aparte (no alfabético con los demás) es lo que deja
claro que es un caso distinto, no un séptimo idioma. Los seis después, en
el orden que decida la Maestra (alfabético por nombre nativo es razonable
y no necesita mantenimiento).

### El aviso si hace falta reinicio

Depende de la decisión de la sección 2. Si la app se reinicia sola al
cambiar (opción recomendada ahí), el selector puede ni necesitar un aviso
—el cambio ya se ve de inmediato, reiniciado—; si en cambio se decide
pedirle al usuario que reinicie a mano, el texto (nuevo, en `.resx`, las
seis traducciones): algo del estilo *"Aura Studio se reinicia para aplicar
el idioma."* si el reinicio es automático (una frase de aviso, no de
pedido), o *"Cierra y vuelve a abrir Aura Studio para ver el cambio."* si
es manual. Se decide junto con el mecanismo, no antes.

## 2. Cómo se aplica la cultura

### El punto exacto: `Program.Main`, antes de `Application.Start`

Contrato de la Maestra: `CultureInfo.CurrentCulture`/`CurrentUICulture` se
fijan **antes de crear cualquier vista**. En este código eso no es
`App.OnLaunched` (ahí ya se creó `App`, que en su constructor llama
`InitializeComponent()` — y aunque `App.xaml` en sí no crea vistas, es
más tarde de lo necesario) ni siquiera el constructor de `App`: es
**`Program.Main`**, antes de `Application.Start(...)` — el archivo ya
existe con ese propósito exacto (`Program.cs`, "poder mirar los
argumentos antes de arrancar la interfaz").

```csharp
// Program.cs — Main, antes de Application.Start
CultureInfo culture = ResolveStartupCulture(); // sección siguiente
CultureInfo.CurrentCulture = culture;
CultureInfo.CurrentUICulture = culture;

WinRT.ComWrappersSupport.InitializeComWrappers();
Application.Start(parameters => { /* ... */ });
```

Es antes de `PrivilegedHost.TryHandle`, no después: ese camino no abre
ventana, pero si algún día un mensaje de ese proceso relanzado necesita
texto localizado (hoy no lo necesita — no hay ninguna cadena de cara al
usuario en ese camino), ya está listo.

### Leer la preferencia sin tocar disco más de una vez

Hoy `App.ConfigureServices()` construye `AppPreferences` (o la variante
con override de `AURA_STUDIO_PREFERENCES`) como parte del registro DI —
una lectura de disco, en el momento de resolver el primer servicio que la
necesite. Si `Program.Main` también necesita leer `Language` ANTES de que
exista el contenedor DI, la lectura ingenua sería una `AppPreferences`
aparte ahí y otra distinta dentro de `ConfigureServices()` — dos lecturas
del mismo archivo, y peor: dos objetos que empiezan a divergir en cuanto
uno cambie algo antes de que el otro exista.

**Propuesta**: construir la `AppPreferences` real UNA vez, en
`Program.Main`, antes de `Application.Start`, leer `Language` de ahí para
resolver la cultura, y pasar esa MISMA instancia a `App` (constructor o
un campo estático que `ConfigureServices()` consuma en vez de construir
una nueva):

```csharp
// Program.cs
Services.IAppPreferences preferences = BuildPreferences(); // la misma lógica
                                                             // que hoy vive en
                                                             // ConfigureServices()
CultureInfo.CurrentCulture = CultureInfo.CurrentUICulture =
    ResolveStartupCulture(preferences.Language);

Application.Start(parameters =>
{
    // ...
    _ = new App(preferences); // ConfigureServices() registra ESTA instancia,
                               // no construye una propia
});
```

Con esto, `Language` (y todo lo demás de `AppPreferences`) se lee del
disco **una sola vez** por arranque, sin importar cuántos servicios lo
consuman después.

### Cambiar el idioma en Ajustes: reiniciar la app, no recrear la ventana

Las dos opciones y sus riesgos, en WinUI 3 sin empaquetar:

**(a) Recrear la ventana** (destruir `MainWindow`, cambiar
`CurrentUICulture`, construir una `MainWindow` nueva y sus páginas). Riesgo
real y específico de este proyecto: hay bastante estado vivo en
singletons de la sesión —`IDeviceSessionService`, `LibraryViewModel`,
`BackgroundTaskCenter`, `InstallerFlowRegistry`— construidos una vez en
`ConfigureServices()` y compartidos por toda la app (ST-202/ST-203 los
sacaron de las vistas justamente para que sobrevivieran a la navegación).
Recrear solo la ventana los deja intactos, que suena bien, pero significa
reconstruir TODO el árbol visual (`ShellPage` y las quince y pico páginas
que cuelgan de ella) mientras un dispositivo puede seguir sincronizando en
segundo plano — una ventana de carreras real entre "la UI vieja se está
destruyendo" y "un evento de `IDeviceSessionService` intenta actualizar un
control que ya no existe". Ninguna prueba de este repo cubre ese camino
hoy, y en un WinUI 3 sin empaquetar (sin el ciclo de vida más manejado de
una app empaquetada) el margen de error es mayor.

**(b) Reiniciar el proceso entero** (relanzar el `.exe`, salir del
actual). Ninguna carrera con estado en memoria —no hay estado que
sobreviva, todo se reconstruye desde cero, que es exactamente el punto—.
El costo es un parpadeo (la app cierra y vuelve a abrir) y perder
transitoriamente cualquier operación en curso: pero cambiar el idioma NO
es una acción que nadie haga a mitad de una sincronización o una
instalación por accidente —es un ajuste, en una pantalla dedicada—, así
que ese costo es aceptable y, más importante, **es el mismo patrón que
Windows entero usa para su propio selector de idioma** ("reiniciar para
aplicar"), que es justo la expectativa que ya tiene cualquier usuario de
Windows.

**Recomendación: (b), reiniciar el proceso.** Relanzar el propio `.exe`
(`Process.Start(Environment.ProcessPath!)` + `Environment.Exit(0)` desde
el hilo de UI, con el guardado de preferencias ya hecho ANTES de lanzar el
nuevo proceso — el nuevo arranque lee `Language` del disco y ya la
encuentra puesta). Nunca mitad y mitad: no se intenta refrescar página por
página ni se deja "para la próxima vez que abras la app" sin decirlo —la
Sección 1 ya prevé el aviso.

### El fallo que hay que evitar: cultura fija en un campo `static readonly`

Ya existe en el código de HOY, en dos archivos, y es la forma exacta del
error que "Seguir al sistema" + selector volvería peor si no se corrige
al mismo tiempo que se aplica la cultura dinámicamente:

```csharp
// AuraStudio.Core/Library/MediaTableRow.cs:47 y :53
public static readonly StringComparer NaturalOrder = StringComparer.Create(
    CultureInfo.GetCultureInfo("es-MX"), CompareOptions.IgnoreCase | CompareOptions.NumericOrdering);
private static readonly CultureInfo DisplayCulture = CultureInfo.GetCultureInfo("es-MX");

// AuraStudio.Core/Library/LibraryStatusSummary.cs:69
private static readonly CultureInfo DisplayCulture = CultureInfo.GetCultureInfo("es-MX");
```

Un campo `static readonly` se evalúa **una sola vez**, la primera vez que
el tipo se toca — antes o después de que `Program.Main` fije
`CurrentUICulture` según lo que haga el JIT/el orden de carga de tipos, y
después nunca más, pase lo que pase con la cultura activa. Con un solo
idioma fijo (es-MX, hoy) da igual: el valor que hardcodea es el único que
existía. En cuanto exista un selector, dos usuarios abriendo la misma
build —uno con "Seguir al sistema" en una Windows en inglés, otro que
eligió "Русский" a mano— verían el MISMO orden natural y el MISMO formato
de fecha, porque el campo se congeló la primera vez que alguien miró una
canción, sin que a nadie se le vuelva a preguntar.

**La corrección real, no un parche**: estos dos campos tienen que dejar de
ser `static readonly` y volverse **propiedades** que lean
`CultureInfo.CurrentCulture` (o `CurrentUICulture`, según corresponda) en
cada acceso — nunca guardar la cultura en un campo. Es exactamente el
`docs/auditoria-idiomas.md` §4 que dejó B0 ("esto necesita reescribirse
para B7, no solo verificarse"), y el propio formato de fecha de
`MediaTableRow.cs:115` (`"d 'de' MMMM 'de' yyyy"`, gramática española
incrustada en el patrón) necesita además cambiar de patrón —a uno estándar
(`"D"`/`"d"`) que .NET traduce solo por cultura— no solo dejar de estar
fijo. `ExtraerCadenasWindows` (`FixedCultureExtractor`) ya detecta ambas
formas del defecto (cultura fija y patrón con palabras incrustadas) y las
marca aparte en `revision.csv` — son 4 sitios hoy, confirmados por el
propio arnés.

## 3. Comprobación del instalador

### Lo que ya hace `dotnet publish` solo, y lo que no

Con `.resx`/`ResourceManager` (decisión de B7a), un `.resx` no neutro
(`AppStrings.en.resx`, `.ja.resx`, etc.) genera un **ensamblado satélite**
por cultura: `<cultura>\AuraStudio.App.resources.dll`, uno por carpeta,
dentro del árbol publicado. El `.resx` **neutro** (el que corresponde al
idioma fuente, español) se compila DENTRO del ensamblado principal —no
genera una carpeta `es\` aparte—, así que de las seis culturas, la
comprobación tiene que esperar **cinco carpetas satélite**
(`en`/`ja`/`de`/`ru`/`fr`), no seis.

Verificado en `AuraStudio.App.csproj`: hoy **no existe**
`<SatelliteResourceLanguages>`. Sin esa propiedad, MSBuild no sabe qué
culturas empaquetar como satélite y podría publicar todas las que
encuentre `.resx` para, incluidas culturas de paquetes NuGet de terceros
que no le importan a nadie acá. **B7b/B7a real tiene que agregarla**:

```xml
<!-- AuraStudio.App.csproj -->
<SatelliteResourceLanguages>en;ja;de;ru;fr</SatelliteResourceLanguages>
```

El `.iss` (`installer/AuraStudio.iss`, sección `[Files]`) **no necesita
ningún cambio**: ya empaqueta `Source: "{#PublishDir}\*"` con
`recursesubdirs createallsubdirs` — copia TODO lo que haya bajo el
publish, satélites incluidos, sin que nadie tenga que nombrar las
carpetas de cultura a mano. Confirmado leyendo el `.iss` real, no
asumido.

### Lo que sí hace falta: una comprobación en `Make-Installer.ps1`, estilo `$imprescindibles`

`Make-Installer.ps1` ya tiene exactamente el patrón a calcar —el array
`$imprescindibles` (`AuraStudio.App.exe`, `AuraStudio.App.pri`,
`artifacts\mks5lboot.exe`, etc.), con `Test-Path` por cada uno y `throw`
si falta algo, ANTES de empaquetar—. La propuesta es agregar ahí mismo
(no una función aparte: es la misma comprobación de "publish completo",
no una categoría distinta) una entrada por satélite:

```powershell
$imprescindibles = @(
    'AuraStudio.App.exe',
    'AuraStudio.App.pri',
    'AuraStudio.Core.dll',
    'Microsoft.WindowsAppRuntime.Bootstrap.dll',
    'artifacts\mks5lboot.exe',
    'artifacts\rockbox.ipod',
    'artifacts\metro\rockbox.ipod',
    'artifacts\moonlit\rockbox.ipod',
    # B7b: un satélite de recursos por cultura no fuente. "es" no aparece:
    # es el idioma fuente, va adentro de AuraStudio.App.dll, no en carpeta propia.
    'en\AuraStudio.App.resources.dll',
    'ja\AuraStudio.App.resources.dll',
    'de\AuraStudio.App.resources.dll',
    'ru\AuraStudio.App.resources.dll',
    'fr\AuraStudio.App.resources.dll'
)
```

Con esto, `$faltan`/`throw` ya cubre el caso —el mismo mecanismo que
evitó que el instalador saliera sin `AuraStudio.App.pri`— sin escribir
ninguna función nueva.

### La comprobación de arnés que pide B8

Ítem separado del punto anterior: **B8 necesita poder correr esto sin
empaquetar** (contra el árbol de `dotnet publish` directo, no contra el
`.exe` del Setup ya instalado — más rápido, y no depende de tener Inno
Setup instalado). Propuesta: una función reutilizable,
`Test-SatellitesPresentes` (o el nombre que decida quien lo escriba), que
reciba el `$publishDir` y devuelva qué falta —mismo contrato que
`Test-DiferenciasEntreArquitecturas`, que ya avisa sin detener—, para que
`Make-Installer.ps1` la llame durante el empaquetado real Y B8 la llame
aparte contra un publish de prueba. Verificar además, con
`System.Reflection.AssemblyName`/`System.Globalization.CultureInfo`, que
el `.exe` publicado **carga** cada satélite (no solo que el archivo
existe): instanciar un `ResourceManager` apuntando al ensamblado principal
y pedir `GetString` con cada `CultureInfo` de las seis, confirmando que no
lanza `MissingManifestResourceException` y que el resultado para las
cinco no-fuente es distinto del que da la cultura fuente (si diera igual,
el satélite existe pero está vacío o no se está usando). Esto es lo que
de verdad prueba "las seis culturas funcionan", no solo que sus archivos
están en el disco.

## 4. Plurales y anchos: qué capturar en B7c

### Formas de plural por idioma (regla CLDR, la que aplica el propio .NET)

| Idioma | Formas | Notas |
|---|---|---|
| Español (es) | 2 (singular/plural) | Ya es el estado actual, 48+ sitios inventariados en ST-247 |
| Inglés (en) | 2 (singular/plural) | Igual que español en estructura, distinta palabra |
| Alemán (de) | 2 (singular/plural) | Igual estructura que es/en |
| Francés (fr) | 2, pero el corte es en 0 y 1 (no solo en 1) | `0 fichier`/`1 fichier` cuentan como singular en francés — un mecanismo que solo mire `== 1` como hace hoy el código clasifica mal el caso de 0 |
| Japonés (ja) | 1 (sin distinción) | Ningún ternario ni regla de plural — una sola forma para cualquier cantidad, y es un error de más (no de menos) escribir una regla ahí |
| Ruso (ru) | 3 (uno/pocos/muchos) | Regla real: termina en 1 (no 11) → forma "uno"; termina en 2-4 (no 12-14) → "pocos"; el resto → "muchos". Ninguna de las 48+ instancias de `n == 1 ? singular : plural` de hoy alcanza para esto — necesitan el mecanismo de reglas real que pide el plan (§3), no una tercera cadena a mano |

Esto confirma lo que ya dice el plan: el mecanismo de plural tiene que ser
por REGLAS de CLDR (o lo que exponga `System.Globalization`/el paquete que
se elija), no la generalización directa del patrón
`count == 1 ? "singular" : "plural"` que domina el código hoy — ese
patrón ya falla para francés (el 0) y no alcanza para ruso (3 formas).

### Pantallas para capturar en B7c, por riesgo de ancho

Prioridad alta —texto corto, control de ancho fijo o casi fijo, donde
japonés (caracteres anchos, kanji denso) y ruso (palabras largas: "Papelera
de reciclaje" → "Корзина", pero "archivos huérfanos" → "файлы-сироты",
bastante más largo) truncan primero:

1. **Barra de estado** (`LibraryStatusStrip`) — texto corto en un
   espacio angosto de la ventana, con contadores (`AppStrings.LibraryTracks`
   y demás). El primer lugar donde un plural ruso mal medido se corta.
2. **Botones de Ajustes** — `SettingsPage.xaml` es la pantalla con más
   literales (76, ST-240) y varios botones de ancho ajustado al texto en
   español (`Button Content=`, sin `MinWidth` explícito en varios casos) —
   "Buscar huérfanos"/"Limpiar archivos huérfanos" en ruso o alemán
   (alemán compone palabras largas: "Dateibereinigung"-estilo) son los
   candidatos más probables a desbordar.
3. **Menús contextuales** (`ContextMenuBuilder`, los diez documentos de
   paridad ST-105) — un `MenuFlyoutItem` mide su ancho por el texto más
   largo del menú; un ítem en ruso/alemán que duplique el largo del
   español puede ensanchar TODO el menú, no solo esa fila — vale la pena
   una captura de al menos el menú de Canciones (el más largo) en los seis
   idiomas.
4. **El diálogo de confirmación de Eliminar** (`DeleteConfirmation`, B5) y
   **"Limpiar archivos huérfanos"** (Ajustes, B5) — texto con conteo y
   tamaño interpolados (`{0} archivos ({1}) van a la Papelera de
   reciclaje.`) — el candidato más directo a que una traducción más larga
   rompa el `TextWrapping`/ancho del `ContentDialog`, y es nuevo (B5), sin
   ningún precedente visual todavía en ningún idioma.

No incluidas a propósito, menor riesgo: las pantallas del Instalador
(textos largos, ya envueltos en párrafos con `TextWrapping="Wrap"` —
tolerantes a idiomas más largos por diseño) y "Cómo guardar tu música"
(mismo motivo, párrafos explicativos ya pensados para envolver).

## Lo que este documento NO decide

- El nombre final de los tipos/miembros propuestos (`Language`,
  `ResolveStartupCulture`, `Test-SatellitesPresentes`) — son legibles y
  consistentes con el resto del código, no un contrato cerrado.
- Si "Seguir al sistema" reintenta detectar la cultura de Windows en cada
  arranque o solo la primera vez — detalle de `ResolveStartupCulture`,
  para quien implemente B7b.
- Qué exactamente hace `.iss` cuando Inno Setup necesita saber en qué
  idioma mostrarse A SÍ MISMO (`[Languages]`/`[LangOptions]`, hoy solo
  `es`) — es el idioma del INSTALADOR, un problema separado del idioma de
  la app instalada, y no estaba en el alcance de este encargo.
