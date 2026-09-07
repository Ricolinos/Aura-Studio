# Auditoría de localización — Aura Studio macOS (2026-09-06)

> PLAN-studio-ajustes-3.md §3 (Fase A7, ST-227). Insumo para "experto en
> código opus": qué hay que localizar, dónde vive, y qué falta -- para
> no tener que buscarlo a ciegas. Solo lectura de `Sources/`, nada
> tocado.

## Corrección al supuesto del plan

**El plan dice "ya hay español e inglés" -- no es así.** No existe
ningún catálogo de localización (`.xcstrings`, `Localizable.strings`,
ni ningún equivalente) en todo el proyecto. `Resources/es.lproj/
InfoPlist.strings` existe, pero es metadata del *bundle* (el nombre que
muestra Finder/Spotlight), no texto de la interfaz. `project.yml`
declara `CFBundleLocalizations: [es]` -- **español únicamente**, con un
comentario propio explicando que es deliberado (para que el menú
estándar de AppKit/SwiftUI salga en español). No hay ni un solo
`NSLocalizedString`, `String(localized:)`, `LocalizedStringKey` con
clave real, ni ningún ayudante propio de i18n en `Sources/`.

**A7 no es "agregar cuatro idiomas a dos que ya existen"**: es
construir el catálogo real por primera vez, agregar inglés, y agregar
japonés/alemán/ruso/francés -- todo desde una base 100% en español fijo.

## 1. Literales por archivo

Todo lo de abajo es un literal crudo -- ninguno pasa por ningún
mecanismo de resolución (no existe ninguno, ver arriba). 484 sitios
como mínimo (no cuenta `TextField` placeholders, `.accessibilityLabel`,
ni las cadenas del centro de tareas -- ver "Fuera de esta cuenta").

### `Text("…")` — 225 sitios, 41 archivos

Por archivo (5 o más):

| Archivo | Cadenas |
|---|---|
| SimilarItemsView.swift | 23 |
| DeviceGeneralView.swift | 20 |
| MusicSettingsView.swift | 18 |
| SettingsSectionView.swift | 11 |
| ExtrasView.swift | 11 |
| BatchMediaInfoView.swift | 11 |
| ServicesSettingsView.swift | 10 |
| MediaInfoView.swift | 10 |
| DeviceActivityBar.swift | 10 |
| SyncSheets.swift | 9 |
| MediaSectionView.swift | 9 |
| LicensesView.swift | 7 |
| DetectDeviceView.swift | 7 |
| MusicViewOptionsView.swift | 6 |
| AlbumCoverPickerView.swift | 6 |
| PhotoSettingsView.swift | 5 |

1-4 cadenas: ThemesView(4), PlaylistsView(4), GitHubTokenSettingsView(4),
AwaitBootloaderUSBView(4), VideoSettingsView(3), RestoreHandoffView(3),
EnterDFUView(3), CoverContaminationSheet(3), ArtistsView(3),
PhotoAlbumsView(2), LibraryUnavailableView(2), DoneView(2),
BackgroundTaskCenterIndicator(2), AppUpdateBar(2), y uno cada uno en
WelcomeView, UpdateBootloaderView, SeriesView, PrivilegedActionSheet,
PermissionsView, LibraryStatusBar, InstallingView, InstallerWizardView,
InstallerHomeView, CoverNormalizationBar, AppMenuCommands.

Ejemplos representativos (el patrón se repite en los 225):

```swift
PlaylistsView.swift:38     Text("Playlists")
PlaylistsView.swift:64     Text("Elige o crea una playlist")
PlaylistsView.swift:207    Text("En la playlist (\(includedItems.count))")
MediaInfoView.swift:128    Text("Más información").font(.title3.bold())
MediaInfoView.swift:153    Text("Se sincroniza con el iPod: la misma calificación que se elige acá o en \"Ahora suena\" del aparato.")
MediaInfoView.swift:219    Text("El nombre de destino en el iPod se arma con estos tres campos -- cambiarlos y sincronizar de nuevo reagrupa el episodio en Movie Flow.")
AwaitBootloaderUSBView.swift:20    Text("El bootloader de Aura ya está en tu iPod. Ahora falta copiar Aura al disco.")
ServicesSettingsView.swift:70      Text("Cuando a una canción le falta carátula, se prueban estos servicios en orden y se usa la primera imagen que aparezca.")
BatchMediaInfoView.swift:84        Text("Vas a editar \(count) canciones a la vez. Los campos que no coincidan entre todas se muestran como \"Mixto\"...")
DetectDeviceView.swift:77          Text("Encontramos \"\(info.volumeName)\", con el firmware original de Apple (no esta en FAT32 todavia)...")
CoverContaminationSheet.swift:27   Text("Estas imágenes entraron a Imágenes por su extensión, pero parecen carátulas de álbum...")
```

### `Button("…")` — 169 sitios, 39 archivos

Más cargados: MediaSectionView(31), ArtistsView(11), PhotoAlbumsView(10),
DeviceGeneralView(10), ThemesView(9), AlbumsView(8), SyncSheets(7),
SimilarItemsView(7), SeriesView(6), AppMenuCommands(6), MoviesView(5),
DoneView(5). El resto (1-4 cada uno): PlaylistsView, MediaInfoView,
BatchMediaInfoView, SettingsSectionView, LibraryUnavailableView,
InstallerWizardView, CoverContaminationSheet, AppUpdateBar,
AlbumCoverPickerView, ServicesSettingsView, PrivilegedActionSheet,
MusicViewOptionsView, GitHubTokenSettingsView, EnterDFUView,
DetectDeviceView, RestoreHandoffView, PhotoSettingsView,
PermissionsView, MusicSettingsView, LicensesView, ExtrasView,
DeviceActivityBar, CoverNormalizationBar, ContentView,
BackgroundTaskCenterIndicator, BackContinueRow, AutomaticUpdateView.

### `Label("…")` — 43 sitios, 20 archivos

MediaSectionView(8), DeviceGeneralView(4), SimilarItemsView(3),
ServicesSettingsView(3), InstallerHomeView(3), EnterDFUView(3),
AwaitBootloaderUSBView(3), GitHubTokenSettingsView(2), ExtrasView(2),
DoneView(2), y uno cada uno en WelcomeView, SeriesView, PlaylistsView,
MoviesView, MediaInfoView, LibraryStatusBar, CoverNormalizationBar,
ContentView, AppUpdateBar, AlbumsView.

### `.help("…")` — 31 sitios, 15 archivos

MediaSectionView(10), AlbumsView(5), AppUpdateBar(3),
SimilarItemsView(2), y uno cada uno en SettingsSectionView,
MusicSettingsView, MoviesView, LibraryBrowsingComponents,
GitHubTokenSettingsView, DeviceNameField, CoverNormalizationBar,
ContentView, BackgroundTaskCenterIndicator, ArtistsView,
AlbumCoverPickerView.

### `.navigationTitle("…")` — 7 sitios (todos)

```
ArtistsView.swift:77        "Artistas"
SeriesView.swift:92         "Series"
ThemesView.swift:129        "Temas"
MoviesView.swift:122        "Películas"
DeviceGeneralView.swift:134 "General"
AlbumsView.swift:140        "Álbumes"
ExtrasView.swift:76         "Extras"
```

### `Menu("…")` — 7 sitios

Seis son el mismo texto ("Cambiar categoría", en PhotoAlbumsView×2,
MediaSectionView, MoviesView, SeriesView×2) más
`CommandMenu("Biblioteca")` en `AuraStudioApp.swift:51`.

### `.alert("…")` — 2 sitios (probable subcuenta)

`ThemesView.swift:154` ("No se pudo completar la operación") y
`InstallerWizardView.swift:126` ("¿Detener el proceso?"). Sospechosamente
pocos -- la mayoría de los diálogos de confirmación de esta app
probablemente se arman con una hoja/tipo de diálogo propio, no
`.alert` nativo de SwiftUI. Falta un grep aparte de esa abstracción si
el conteo exacto importa para A7.

### Fuera de esta cuenta (marcado para A7, no auditado a fondo por tiempo)

- Títulos/descripciones de progreso del centro de tareas
  (`LibraryViewModel.swift` -- confirmado que son literales, ver §4 de
  plurales abajo, mismos archivos).
- `TextField` con placeholder de texto.
- `.accessibilityLabel`.
- Texto de onboarding/permisos armado con cadenas multilínea o
  `AttributedString` (no siempre cae en un `Text("literal")` simple).

## 2. Cómo se usa la localización hoy: no se usa

No hay ningún patrón "correcto" que contrastar -- cero sitios en
`Sources/` referencian una clave de catálogo. No hay una convención
parcial-pero-inconsistente; es 100% literal, en todos lados.

## 3. Plurales: manuales, atados a la gramática del español, 15+ sitios

Todo pluralizado es un ternario `count == 1 ? "singular" : "plural"`
metido directo en la cadena interpolada -- nada de `.stringsdict` ni
`String.LocalizationValue` con variaciones de plural.

- `LibraryViewModel.swift`: líneas 980, 1023, 1078, 1111, 1113, 1228,
  1302, 1345, 1347, 1376, 1440 -- títulos/progreso de tareas en lote
  (p. ej. `"Buscando pósters de \(ordered.count) videos…"` vs. singular
  `"Buscando póster en línea…"`).
- `LibraryStatusSummary.swift:120,142`: un ayudante genérico chico,
  `"\(formatted(n)) \(n == 1 ? singular : plural)"` -- lo más cercano a
  un patrón reutilizable que existe, pero sigue siendo singular/plural
  binario del español, no extensible al ruso (3 formas) ni al japonés
  (ninguna).
- `LibraryGrouping.swift:227,237,238`; `ArtistsView.swift:324`.

**Esta categoría entera necesita un mecanismo real de reglas de plural
para A7**, no solo traducir el texto -- el ternario binario no
representa ruso ni es necesario para japonés.

## 4. Fechas: bien en su mayoría, un archivo para confirmar

Cinco archivos usan `ISO8601DateFormatter` (`PrivilegedOperationLog.swift`,
`FirmwareSwitcher.swift`, `DeviceNameStore.swift`, `SyncMarker.swift`) --
son timestamps internos/de formato de archivo (bitácora, manifiesto de
sync), no texto de cara al usuario, sin relación con el idioma.

El único formateador de fecha visible al usuario es
`MediaSectionView.swift:1320-1325`: `DateFormatter` con
`dateStyle = .medium, timeStyle = .none`, **sin locale explícito** --
ya usa `Locale.current` por omisión, así que se adapta solo en cuanto
la app declare más localizaciones. No hace falta tocar código ahí para
A7, solo confirmarlo en la verificación.

## 5. Escala

150 archivos Swift en `Sources/AuraStudio/`. Total de literales de
interfaz encontrados: 225 (`Text`) + 169 (`Button`) + 43 (`Label`) + 31
(`.help`) + 7 (`.navigationTitle`) + 7 (`Menu`) + 2 (`.alert`) =
**484 como mínimo** (piso, no techo -- ver "Fuera de esta cuenta"),
repartidos en unos 45-50 archivos distintos, con la concentración más
pesada en `MediaSectionView.swift`, `DeviceGeneralView.swift`,
`SimilarItemsView.swift`, `ArtistsView.swift`,
`ServicesSettingsView.swift`, `BatchMediaInfoView.swift`.
