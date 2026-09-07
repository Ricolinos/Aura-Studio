# Auditoría de localización — Aura Studio Windows (2026-09-07)

> PLAN-studio-ajustes-3.md §3 (Fase B7, ST-240/B0). Insumo para quien haga
> B7a/B7b/B7c: qué hay que localizar, dónde vive, y qué falta — para no
> tener que buscarlo a ciegas. Solo lectura, nada tocado. Calca la
> estructura de `Aura-Studio/docs/auditoria-idiomas.md` (Mac, origin/main
> `a078036`) para que las dos auditorías se lean igual.

## Corrección al supuesto del plan, versión Windows

El plan dice "ya hay español e inglés" para las dos plataformas. Para
Windows tampoco es así, pero de otra forma que en Mac: **no hay ningún
`.resw` en todo el repo** (confirmado, cero resultados), así que no hay
un catálogo de recursos real — pero **sí existe una clase centralizadora
de cadenas**, `AuraStudio.App.Resources.AppStrings` (585 líneas, 231
miembros que devuelven `string`), que ya es un paso adelantado sobre el
punto de partida de Mac (que no tiene ni eso). El problema no es "no hay
ningún mecanismo": es que **la mitad de los textos de cara al usuario
pasan por `AppStrings` y la otra mitad son literales sueltos en XAML y en
C#**, sin ningún criterio documentado de cuándo usar cuál — y `AppStrings`
en sí mismo son cadenas en español fijas, no claves de un catálogo con
traducciones.

**B7a no es "agregar cuatro idiomas": es decidir si `AppStrings` se
convierte en la capa de acceso sobre `Resources.resw` (migrar sus 231
miembros a claves .resw, conservando la API que ya usan las vistas) o si
se reemplaza — y, en cualquier caso, mover a esa misma capa los ~300
literales sueltos que hoy no pasan por ella.**

## 1. Dónde viven las cadenas hoy

### `AppStrings.cs` — 231 miembros, 585 líneas

Static class, `AuraStudio.App/Resources/AppStrings.cs`. Mezcla:
propiedades simples (`public static string AppName => "Aura Studio";`) y
métodos con la pluralización ya resuelta por parámetro (ver §3). Es lo
más parecido a un catálogo que existe, pero **el valor sigue siendo un
literal en español dentro del getter** — no hay separación entre clave y
traducción, así que "agregar un idioma" hoy significaría un
`if (culture == ...)` por cada uno de los 231, no cargar un `.resw`
distinto.

### Literales en XAML — 146 sitios como mínimo, 13 archivos

Atributos `Text=`, `Content=`, `Header=`, `PlaceholderText=`, `Title=`,
`Description=` con un literal entre comillas (no `{x:Bind}` ni
`{StaticResource}`). No se contó texto inline `<TextBlock>…</TextBlock>`
(cero sitios: WinUI, en este código, usa la forma de atributo para texto
fijo, así que esa categoría no suma nada aparte).

| Archivo | Cadenas |
|---|---|
| Views/SettingsPage.xaml | 76 |
| Views/ThemesPage.xaml | 13 |
| Views/DeviceListPage.xaml | 13 |
| Views/ExtrasPage.xaml | 12 |
| Views/PlaylistsPage.xaml | 8 |
| Views/ArtistsPage.xaml | 8 |
| Views/SimilarItemsPage.xaml | 7 |
| Views/ShellPage.xaml | 3 |
| Views/SongsPage.xaml | 2 |
| Views/MediaGridPage.xaml | 1 |
| Views/InstallerPage.xaml | 1 |
| MainWindow.xaml | 1 |
| Controls/LibraryStatusStrip.xaml | 1 |

`SettingsPage.xaml` concentra más de la mitad (76 de 146) — coherente con
ser la pantalla con más texto explicativo de la app (siete secciones,
cada una con descripciones largas). `LicensesPage.xaml` no aparece: su
contenido sale de datos (nombres de licencia, URLs), no de literales fijos.

### Literales en C#, fuera de `AppStrings` — al menos 130 sitios, tres focos

No es un conteo exhaustivo de *todo* literal en C# (eso incluiría rutas,
claves de preferencias, nombres de columna de log) — es la cuenta de tres
patrones concretamente de cara al usuario:

- **`MenuEntry(id, "texto", …)`** en `Core/Library/ContextMenu.cs`: 57
  sitios. Es el catálogo entero de los menús contextuales (documento de
  paridad ST-105) — "Buscar carátulas del álbum...", "Eliminar álbum",
  "Marcar como favorito", etc. — ninguno pasa por `AppStrings`.
- **`StatusMessage = "…"`** (la barra de estado / avisos de una acción)
  en `AuraStudio.App`: 23 sitios.
- **`Title =`/`PrimaryButtonText =`/`CloseButtonText =`/`SecondaryButtonText =`
  literales** de `ContentDialog` en código-behind: 23 sitios.

Total de estos tres focos: **103 sitios**, sin contar los que sí usan
interpolación con datos del usuario dentro de un literal (esos también
cuentan para el total pero complican la extracción — un buen candidato a
"revisar en B7a" en vez de asumir que se resuelven solos).

### Fuera de esta cuenta (marcado para B7a/B7b, no auditado a fondo por tiempo)

- `AutomationProperties.Name` (accesibilidad) — probablemente varios más
  literales, no se contaron.
- Mensajes de excepción/`errores.log` — no son de cara al usuario en el
  sentido de esta auditoría (van a un archivo técnico), pero unos pocos sí
  se muestran en un diálogo (ver `PermissionsView`/`PrivilegedActionSheet`
  del lado Mac; en Windows, `Platform/PrivilegedRunner.cs` y las pantallas
  del instalador tienen su propio texto explicativo, no contado acá.
- Texto armado con `string.Join`/interpolación compleja (p. ej. el resumen
  de `LibraryViewModel.SummaryOf`, ya usa `AppStrings` para las partes
  pluralizadas pero el separador `" · "` y la puntuación son literales).

## 2. Cómo se usa la localización hoy: parcial, sin criterio

A diferencia de Mac (100% literal, ni un solo sitio con mecanismo), acá
**hay** un mecanismo (`AppStrings`) y una parte real de la app sí pasa por
él — pero no hay ninguna regla que diga qué va en `AppStrings` y qué no.
Comparando dos pantallas: `SongsPage.xaml` (2 literales, el resto viene de
`AppStrings`/ViewModels) contra `SettingsPage.xaml` (76 literales
directos, casi nada de `AppStrings`) — la diferencia parece ser
simplemente **cuándo se escribió cada pantalla**, no una decisión de
diseño. B7a tiene que decidir la regla de una vez (probablemente: todo
texto de cara al usuario pasa por el mismo mecanismo, sea cual sea, y
`AppStrings` dejar de tener el valor adentro) y aplicarla pareja.

## 3. Plurales: ya centralizados en su mayoría, pero binarios

A diferencia de Mac (ternarios sueltos por todo el código), Windows
**ya tiene el patrón concentrado**: 27 sitios de `count == 1 ? "singular"
: "plural"` en total, y una buena parte vive **dentro de `AppStrings`**
como métodos (`AppStrings.LibraryTracks(int)`, `AppStrings.LibraryPhotos(int)`,
etc. — el propio archivo declara la pluralización como parte de su API
pública, no dispersa por las vistas). Eso es una ventaja real sobre Mac
para B7a: migrar `AppStrings` ya trae consigo migrar la mayoría de los
plurales a un solo lugar.

**Sigue siendo binario (singular/plural del español)**, igual que Mac: no
alcanza para ruso (3 formas) ni hace falta para japonés (ninguna). B7a
necesita el mismo mecanismo real de reglas de plural que pide el plan para
Mac — y como la mayoría ya vive en `AppStrings`, es un solo lugar para
cambiarlo, no 27.

## 4. Fechas y números: hardcodeado a `es-MX`, no es "confirmar", es arreglar

A diferencia de Mac (`Locale.current` por omisión, solo falta confirmar),
Windows tiene un problema real y concreto: `MediaTableRow.cs:53` declara

```csharp
private static readonly CultureInfo DisplayCulture = CultureInfo.GetCultureInfo("es-MX");
```

y la usa para **tres** propiedades de cara al usuario:
`DiscNumberText`/`TrackNumberText` (formato de número, `:99` — menos
grave, casi neutro entre culturas) y, la que sí importa,
`AddedAtText` (línea 115):

```csharp
Item.AddedAt?.ToString("d 'de' MMMM 'de' yyyy", DisplayCulture)
```

El patrón de formato **tiene la gramática del español escrita a mano**
(las palabras `'de'` son literales, no parte de ningún token de fecha) —
en inglés saldría literalmente "6 de September de 2026", no algo que se
arregle solo cambiando `DisplayCulture`. **Esto necesita reescribirse
para B7**, no solo verificarse: `DisplayCulture` tiene que volverse la
cultura activa de verdad (`CultureInfo.CurrentCulture` o la que elija el
selector de idioma de Ajustes) y el formato de fecha tiene que ser uno
que .NET traduzca solo (`"D"`/`"d"` estándar, o un patrón por cultura),
no una plantilla con palabras de un idioma incrustadas.

No se encontraron otros formateadores de fecha visibles al usuario fuera
de `MediaTableRow.cs` (los `ToString("O")`/`ToString("yyyy...")` del resto
del código son timestamps internos — bitácora, IDs, JSON — sin relación
con el idioma, igual que en Mac).

## 5. Textos técnicos compartidos con Mac (para B7a/traducción única)

El plan (§0.4, §2) pide que "Cómo guardar tu música" (los dos modos,
beneficios y desventajas) y los avisos de actualización se traduzcan una
vez y se copien a la otra plataforma. En Windows, el texto de
almacenamiento ya existe, completo, en
`AuraStudio.App/ViewModels/SettingsViewModel.cs:157-159`
(`CopyMediaDetail`) — dos párrafos largos, uno por modo, muy cercanos en
tono y contenido al texto que el plan describe para la sección "Cómo
guardar tu música" del §2 (beneficios/desventajas de copiar vs.
referenciar). Quien escriba el texto compartido definitivo en B1/A1
debería partir de este texto de Windows o el equivalente de Mac —
cualquiera de los dos, pero **uno solo**, para no traducir dos redacciones
distintas a cinco idiomas cada una.

Los avisos de actualización de la app (no del firmware) todavía no
existen en Windows como funcionalidad (no hay "buscar actualizaciones de
Aura Studio" implementado del lado Windows a la fecha de esta auditoría);
cuando exista, su texto es candidato directo a compartir con el
equivalente de Mac.

## 6. Escala

14 archivos XAML en `AuraStudio.App/Views` + `Controls` + `MainWindow.xaml`.
Total de literales de interfaz encontrados fuera de `AppStrings`: 146
(XAML) + 57 (`MenuEntry`) + 23 (`StatusMessage`) + 23 (`ContentDialog`) =
**249 como mínimo** (piso, no techo — ver "Fuera de esta cuenta" en §1),
más los 231 miembros de `AppStrings` que sí están centralizados pero
siguen siendo español fijo sin traducción. **Total aproximado de
superficie a traducir: ~480 cadenas**, del mismo orden que las 484 de
Mac, pero con ~230 de ellas ya en un solo archivo en vez de dispersas —
eso hace a B7a de Windows estructuralmente más simple que el de Mac en la
parte de *extracción*, y estructuralmente igual de necesario en la parte
de *fecha/plural real* (§3, §4).

Concentración más pesada: `SettingsPage.xaml` (76) y `ContextMenu.cs` (57,
los diez menús del documento de paridad ST-105) suman casi la mitad del
total fuera de `AppStrings`.
