# Mapeo Swift (macOS) → C# (Windows) — Aura Studio

> Bitácora de portado. Se actualiza al cierre de cada fase del
> `PLAN-aura-studio-windows-v2.md` (carpeta padre `docs/plans/`). La verdad
> de qué compila y qué prueba pasa es el build/test real, no este archivo —
> ante duda, corre las compuertas de la fase (ver plan, §Protocolo de
> ejecución) y corrige esta tabla si no coincide.

Estado verificado el 2026-09-01, al cerrar la **Ronda de ajustes 4** (la última
antes del primer commit): `dotnet build studio/windows -p:Platform=ARM64` →
0 errores/0 warnings (`TreatWarningsAsErrors` activo en los 3 csproj);
`dotnet test studio/windows/tests/AuraStudio.Core.Tests` → **1081/1081** verdes;
app arrancada y verificada en pantalla contra el iPod real del dueño (capturas
en `docs/capturas/r3-*.png` y `r4-*.png`), incluida una sincronización completa
de 399 archivos.

> **Sobre esta tabla y las rondas de ajustes.** Las filas de abajo se escribieron
> por fases y las rondas 1–4 movieron varias cosas de lugar (Artistas dejó de ser
> cuadrícula, Sincronizar dejó de ser sección, Extras dejó de ser marcador). Lo
> que se sabe desactualizado está corregido acá; **la auditoría exhaustiva
> pantalla por pantalla vive en `ESTADO-PORT.md`**, que es la fuente cuando las
> dos discrepen.

## Estructura de proyecto (nombres reales)

- `AuraStudio.Core/` — class library `net10.0`, portable (sin dependencias
  de Windows). Lógica de negocio y modelos de contrato.
- `AuraStudio.App/` — shell WinUI 3 (**no** `AuraStudio.Win/`, nombre
  descartado). `net10.0-windows10.0.26100.0`,
  `TargetPlatformMinVersion 10.0.19041.0`, Windows App SDK 2.4.0.
  `Platform/` = APIs de Windows (WMI, Win32, Credential Manager); `Services/`
  = implementaciones detrás de interfaz; `ViewModels/` = CommunityToolkit.Mvvm
  con propiedades parciales; `Views/` = páginas XAML.
- `tests/AuraStudio.Core.Tests/` — xUnit, corre en la VM (antes se pensaba
  correr en la Mac; ya no aplica, ver premisa del plan v2).
- `artifacts/` — `mks5lboot.exe` cross-compilado, sin probar contra el iPod.
- `scripts/` — `FirmwareFetch.ps1`, `Setup-WindowsDev.ps1`, `BuildAndRun.bat`,
  `Make-Icon.ps1` (regenera `Assets/AuraStudio.ico` desde el master del dueño en
  `icono/Aura icono.png`, que es la fuente única y no se edita).
- `icono/` — master del icono entregado por el dueño. Solo se lee.
- `AuraStudio.Windows.slnx` — solución. **Fase 0 corrigió** el mapeo de
  plataforma: `Solution="*|ARM64"` apuntaba a `Project="x64"` en
  `AuraStudio.App` (silenciosamente compilaba x64 al pedir ARM64); ahora
  mapea a `Project="ARM64"`.

## Core (`AuraStudio.Core/`) — lógica portable con tests

| Swift (macOS) | C# (Windows) | Estado |
|---|---|---|
| `Services/IPodDiskIdentifier.swift` | `IPodDiskIdentifier.cs` | ✅ portado, 13 casos |
| `Services/USBDeviceIdentity.swift` | `USBDeviceIdentity.cs` | ✅ portado, 6 casos |
| — (no existe en Swift; USB de Windows expone PnP IDs, no IOKit) | `PnpDeviceId.cs` | ✅ nuevo, específico Windows, 18 casos — parser `USBSTOR\...` / `USB\VID_xxxx&PID_xxxx` |
| `Services/PathSanitizer.swift` | `PathSanitizer.cs` | ✅ portado, 16 casos |
| `Models/MediaCategory.swift` + `Services/MediaCategoryClassifier.swift` | `MediaCategory.cs` | ✅ portado (heurísticas), 10 casos |
| `Models/CatalogSummary.swift` | `CatalogSummary.cs` | ✅ portado, 10 casos |
| `Services/SyncMarker.swift` | `SyncMarker.cs` | ✅ portado, 11 casos — clave JSON `"changes"` verificada contra contrato SS4.1 |
| `Services/InstallManifest.swift` (parcial: árbol/manifiesto) | `SyncManifest.cs` | ✅ portado, 2 casos |
| — (planificador de árbol del firmware, sin equivalente 1:1 en Swift) | `FirmwareTreePlanner.cs` | ✅ portado, 2 casos |
| `Models/FirmwareFamily.swift` | `FirmwareFamily.cs` | ✅ portado (sin tests propios — cubierto por consumidores) |
| — | `FirmwareArtifacts.cs` | ✅ portado (sin tests propios) |
| `Services/ThemePackager.swift` | `ThemePackager.cs` | ✅ portado, 6 casos |
| `Services/ThemeValidator.swift` | `ThemeValidator.cs` | ✅ portado, 7 casos |
| (`AuraThemeID` embebido en `ThemeInstaller.swift`) | `AuraThemeID.cs` | ✅ portado (cubierto por `ThemeValidatorTests`/`ThemePackagerTests`) |
| — | `AuraThemeManifest.cs`, `ThemeFormat.cs` | ✅ portado (cubiertos indirectamente) |
| `Services/RunningFirmware` (dentro de `AuraDevice.swift`) | `RunningFirmware.cs` | ✅ portado (sin tests propios) |
| `Models/AuraDevice.swift` (`Firmware`) + mitad de archivos de `Services/AuraDeviceProbe.swift` | `InstalledFirmware.cs` (`InstalledFirmwareKind`, `InstalledFirmware`, `FirmwareTreeFacts`, `FirmwareTreeProbe`) | ✅ portado en Fase 1, 12 casos — clasifica el árbol del volumen (Aura/Rockbox/stock/vacío) y su evidencia de arranque |
| `Models/LibraryPersistence.swift` | `Library/LibraryPersistence.cs` (`PersistedLibrary`, `PersistedLibraryItem`, `PersistedTrackMetadata`, `PersistedPlaylist`, `LibraryPersistenceMapper`, `LibraryCatalogStore`) | ✅ Fase 3, 15 casos — rutas relativas, portada fuera del JSON, estados transitorios y fallidos colapsados a `queued`, campos nuevos anulables, categorías de D-228 traducidas. **Reemplaza al `LibraryCatalog.cs` esqueleto de la Fase 0, que se eliminó** (ST-083) |
| — | `Library/LibraryStore.cs` | ✅ Fase 3, 11 casos — traduce entre el modelo vivo y el persistido; único punto que arma rutas dentro de la carpeta de biblioteca y lee/escribe `.portadas/<id>.jpg` |
| `Models/LibraryItem.swift` | `Library/LibraryItem.cs` | ✅ Fase 3, 6 casos — estados de proceso, categoría, serie/temporada/episodio, álbum de fotos, `MetadataEditedByUser`; `DisplayTitle` igual que `LibraryGrouping.displayTitle` |
| `Models/TrackMetadata.swift` | `Library/TrackMetadata.cs` | ✅ Fase 3, mismos campos |
| `Services/LocalTagReader.swift` (reglas) | `Library/TrackTagRules.cs` | ✅ Fase 3, 18 casos — **acá vive la equivalencia con macOS**, no en la librería |
| `Services/LocalTagReader.swift` (lectura) | `Library/LocalTagReader.cs` | ✅ Fase 3, 11 casos contra MP3 reales. macOS usa AVFoundation; acá **TagLib#** (LGPL, NuGet) porque no hay equivalente de plataforma — ver ST-082 |
| `Models/CoverArtAssets.swift` | `Library/CoverArtAssets.cs` | ✅ Fase 3, 26 casos — ST-012: las carátulas son assets de Música/Video, nunca entradas de Imágenes |
| `Services/ImageResizer.swift` (reglas) | `Library/ImageResizePlan.cs` + `Library/JpegMarkers.cs` (mismo archivo) | ✅ Fase 3, 15 casos — tamaño destino sin deformar ni agrandar, y lectura de marcadores SOF para exigir **baseline** (D-291) |
| `Services/ImageResizer.swift` (codificado) | `App/Platform/ImageResizer.cs` | ✅ Fase 3 — WIC en vez de ImageIO. macOS **pide** baseline a ImageIO; WIC no expone esa opción, así que acá se **verifica** la salida y se falla si no lo es (ST-083). Verificado con `tools/ImageResizerCheck` |
| `Services/CoverThumbnailCache.swift` (clave) | `Library/CoverThumbnailKey.cs` | ✅ Fase 3, 6 casos — clave por contenido para que un álbum entero comparta una miniatura |
| `Services/CoverThumbnailCache.swift` (caché) | `App/Platform/CoverThumbnailCache.cs` | ✅ Fase 3 — LRU de 600 como macOS; conserva el **aspecto real** (el bug de distorsión reportado en macOS). Verificado con `tools/ImageResizerCheck` |
| `Models/Playlist.swift` | `Library/Playlist.cs` (`Playlist`) | ✅ Fase 3 — la imagen es un archivo en `.portadas/`, no bytes embebidos |
| `Services/PlaylistExporter.swift` | `Library/Playlist.cs` (`PlaylistExporter`) | ✅ Fase 3, 6 casos — `.m3u8` con rutas UNIX absolutas y `\n`: lo lee `playlist_create()` de Rockbox, no Windows |
| `Services/PlaylistImporter.swift` | `Library/Playlist.cs` (`PlaylistImporter`) | ✅ Fase 3, 9 casos — tolera relativas, absolutas de Windows, UNC, `file://` y `\r\n` |
| `Services/PlaylistArtGenerator.swift` (geometría) | `Library/PlaylistArtLayout.cs` | ✅ Fase 3, 11 casos — cuadrantes, aspect-fill y las barras del tile |
| `Services/PlaylistArtGenerator.swift` (dibujado) | `App/Platform/PlaylistArtGenerator.cs` | ✅ Fase 3 — WIC en vez de CoreGraphics: el aspect-fill lo hace el decodificador (escala y **después** recorta) y las puntas redondeadas se suavizan muestreando 4×4, porque acá no hay el antialiasing de CG. Verificado con `tools/ImageResizerCheck` |
| `Services/SimilarItemsDetector.swift` (normalización) | `Library/SimilarityText.cs` | ✅ Fase 3, 31 casos — plegado, número de pista al frente, calificadores de versión, Levenshtein |
| `Services/SimilarItemsDetector.swift` (detección) | `Library/SimilarItemsDetector.cs` | ✅ Fase 3, 22 casos — ST-063. **Límite conocido heredado de macOS**: el bloqueo previo a comparar hace que la regla de "mismo episodio" casi nunca se aplique; documentado en ST-084, a coordinar con macOS |
| `Services/LibraryEnricher.swift` (`FilenameGuesser`) | `Library/LibraryEnricher.cs` (`FilenameGuesser`) | ✅ Fase 3, 13 casos — incluida la heurística deliberadamente imperfecta del número de pista |
| `Services/LibraryEnricher.swift` | `Library/LibraryEnricher.cs` | ✅ Fase 3, 18 casos con stub de HTTP propio — piso de puntaje 70, solo llena huecos, y "no encontré" ≠ "falló la red" (D-203) |
| `Models/AppPreferences.swift` (`CoverArtProvider`) | `Library/LibraryEnricher.cs` (`CoverArtProvider`) | ✅ Fase 3 — el orden lo elige el usuario (D-203) |
| `Models/MusicTableColumn.swift` | `Library/MusicTableColumn.cs` (`MusicTableColumn`, `MusicColumnGroup`, `MusicSortField`) | ✅ Fase 3, 13 casos — ST-030: grupos, anchos, migración del menú "+" viejo (D-199) y el criterio de orden persistible |
| `Views/MediaSectionView.swift` (`MediaTableRow` + comparadores) | `Library/MediaTableRow.cs` | ✅ Fase 3, 22 casos — **toda columna declara su comparador**; el tamaño del archivo se lee una vez por renglón y no en cada comparación |
| `Services/DeviceSyncIndex.swift` (`SyncItemState`) | `Library/MediaTableRow.cs` (`SyncItemState`) | ✅ Fase 3 — solo el enum, porque la columna "Estado" ordena por él; el índice que lo calcula sigue pendiente |
| `Models/LibraryGrouping.swift` | `Library/LibraryGrouping.cs` | ✅ Fase 3, 28 casos — álbumes, artistas, películas/series con temporadas y álbumes de fotos; artículo inicial ignorado al ordenar |
| `ViewModels/LibraryViewModel.swift` (`addDroppedFiles`) | `Library/LibraryIngest.cs` | ✅ Fase 3, 15 casos — cada sección ingiere **solo su tipo**, las carátulas nunca a Imágenes, y se reporta lo que NO entró |
| `Models/AuraDevice.swift` (propiedades derivadas) | `IPodDiskInfo.cs` | ✅ portado — Fase 1 agregó `SupportsAuraContract`, `IsAuraFirmware`, `RockboxFamilyVerified`, `IsDualBoot`, `ThemeFormatSupported` y retiró `IsAura` (era la trampa capacidad-vs-identidad de ST-046); 7 casos en `FirmwareTreeProbeTests` |
| `Services/MusicBrainzClient.swift` | `Networking/MusicBrainzClient.cs` | ✅ portado, 4 casos |
| `Services/MusicBrainzRateLimiter.swift` | `Networking/MusicBrainzRateLimiter.cs` | ✅ portado, 5 casos |
| `Services/TMDBClient.swift` | `Networking/TMDBClient.cs` | ✅ portado (sin tests propios) |
| `Services/FanartTVClient.swift` | `Networking/FanartTVClient.cs` | ✅ portado (sin tests propios) |
| `Services/DeezerClient.swift` | `Networking/DeezerClient.cs` | ✅ portado (sin tests propios) |
| `Services/LRCLIBClient.swift` | `Networking/LRCLIBClient.cs` | ✅ portado (sin tests propios) |
| `Services/CoverArtArchiveClient.swift` | `Networking/CoverArtArchiveClient.cs` | ✅ portado (sin tests propios) |
| `Services/GitHubReleaseChecker.swift` | `Networking/GitHubReleaseChecker.cs`, `GitHubRelease.cs`, `GitHubReleaseAsset.cs` | ✅ portado (sin tests propios) |
| — (SemVer es implícito en Swift vía comparación de strings) | `Networking/SemVer.cs` | ✅ nuevo, explícito |
| (parte de `TMDBClient`/`FanartTVClient` en Swift) | `Networking/VideoArtworkResolver.cs`, `VideoTitleParser.cs` | ✅ portado (sin tests propios) |
| `Services/APIKeyStore.swift` (protocolo) | `Networking/IApiKeyStore.cs` | ✅ interfaz portada — implementación real (Credential Manager) ya está |
| — | `Networking/NetworkingContracts.cs` | ✅ tipos de soporte compartidos |

### Instalador (`AuraStudio.Core/`, Fase 2)

| Swift (macOS) | C# (Windows) | Estado |
|---|---|---|
| `Services/InstallManifest.swift` | `InstallManifest.cs` | ✅ portado, 18 casos — formato de `install_manifest.cfg` byte a byte igual (es contrato v11). El CRC-32 sale de `ZipArchiveEntry.Crc32` del BCL, no de parsear la salida de `unzip -lv` como el Swift |
| `Services/InstallPlanner.swift` | `InstallPlanner.cs` | ✅ portado literal, 10 casos |
| `Services/BundledArtifacts.swift` | `FirmwareArtifacts.cs` (`FirmwareArtifacts`, `FirmwareArtifactVerifier`, `ToolOrigin`, `ArtifactScope`, `ToolProvenance`) | ✅ portado, 16 casos — incluye la comprobación D-297/D-298 del contenido real de `rockbox.zip` y la procedencia de `mks5lboot.exe`, que en Windows **no viene del Release** |
| `Services/AuraUpdateChecker.swift` (parte local) | `AuraUpdateChecker.cs` | ✅ portado, 13 casos — tag primero, hash del binario de la misma familia como respaldo (ST-046). La parte de red/caché llegó en R4 (`Installer/ReleaseCache.cs`, ST-132) |
| `MKS5LBootRunner.parseDFUState` | `Mks5lbootOutput.cs` | ✅ portado, 6 casos |
| *(no existe: macOS usa `diskutil eraseDisk FAT32`)* | `Installer/Fat32Formatter.cs` | ⚠️ escrito por la sesión paralela, **16 pruebas escritas en esta fase**; sin verificar contra hardware |
| `LibrarySync`/instalación del árbol | `Installer/FirmwareTreeWriter.cs` | ⚠️ portado (delta v11 + estacionamiento v10), sin tests propios todavía |
| `Models/InstallerStep.swift` | `Installer/InstallerStep.cs` | ✅ portado (lo consume el asistente, Fase 2 sesión 2) |
| `InstallerError` (disperso en Swift) | `Installer/InstallerError.cs` | ✅ portado |
| `Services/PrivilegedExecutor.swift` (criterio) | `Installer/PrivilegedOperation.cs` | ✅ lista cerrada de operaciones, validación y modo ensayo (`DryRun`) |
| *(no existe: macOS particiona con `diskutil`)* | `Installer/MasterBootRecord.cs` | ✅ Fase 2 sesión 2, 16 casos — la tabla con el tipo 0x0C que el bootloader espera leer (D-190) |
| *(no existe)* | `PhysicalDrivePath.cs` | ✅ Fase 2 sesión 2, 11 casos — el número de disco que recibe el formateo, parseado con rechazo estricto |
| `Services/FirmwareSwitcher.swift` | `Installer/FirmwareSwitcher.cs` | ✅ portado, **16 casos escritos en la sesión 2** (estacionar, despertar, no perder ajustes, no tocar la música) |

**Total Core: 1081/1081 tests verdes.** Los módulos "sin tests propios" están
cubiertos solo transitivamente o pendientes de tests dedicados — no es un
vacío deliberado, es deuda a cerrar en la fase que retome cada módulo.

## Pendiente en Core

| Swift (macOS) | Estado |
|---|---|
| `Services/ID3Writer.swift` | pendiente — hoy las etiquetas se reescriben al preparar el archivo, no con un escritor propio |
| `Services/DeviceSyncIndex.swift` | **parcial** — el enum de estado está (`Library/MediaTableRow.cs`); el índice que compara contra el iPod, no. Es lo que le falta a «Solo la selección» para poder decir cuántos hay pendientes de verdad (ST-129) |
| `Services/FirmwareReleaseDownloader.swift` | apartado en `docs/attic/st077-cadena-descarga/` — Extras ya resuelve **qué** versión se instalaría (ST-132); **bajarla** sigue pendiente |

Lo que esta tabla listaba como pendiente y **ya está**: `MusicTableColumn.cs`,
la sincronización real (`Library/SyncPlanner.cs`, `LibrarySyncEngine.cs`,
`LibrarySyncFinalizer.cs`), `ClockSyncWriter.cs`, `Library/ArtistImageStore.cs`,
`Networking/ArtistImageResolver.cs` y la conversión con ffmpeg
(`Media/Ffmpeg*.cs`).

## `AuraStudio.App/` — shell WinUI 3

### Platform (Grupo B — específico de Windows, sin tests unitarios directos)

| macOS (Swift) | Windows (`Platform/`) | Estado |
|---|---|---|
| `Services/DiskArbitrationMonitor.swift` + `Services/IPodMonitor.swift` | `WmiDiskEnumerator.cs` | ✅ implementado y **validado con iPod físico** (passthrough Parallels, `E:\`, 125 GB) |
| — (lectura de `aura.cfg`/`sync_summary.cfg` del volumen) | `VolumeProbe.cs` | ✅ implementado y validado |
| — (abrir/expulsar volumen; en macOS vía `NSWorkspace`/`DiskArbitration`) | `VolumeManager.cs` | ✅ implementado |
| `Services/MKS5LBootRunner.swift` | `DfuFlashRunner.cs` | ⚠️ real (dfuscan por estado, `--bl-inst [--single]`, `--bl-uninst`, esperas), verifica artefactos antes de cada escritura — **sin probar contra el iPod en DFU** |
| `Services/AMPAgentsGuard.swift` (equivalente) | `AppleDeviceSupport.cs` | ⚠️ detección de solo lectura (dispositivo Apple en USB, driver, servicio). Pausar el servicio necesita elevación: es la sesión 2 |
| `Services/PrivilegedExecutor.swift` | `PrivilegedRunner.cs` + `PrivilegedHost.cs` | ⚠️ implementado (relanza la app con `runas`, re-verifica el disco en el proceso elevado, `diskpart clean` + MBR + FAT32). **Ningún disco se ha formateado con esto todavía** — los guardas sí se ejercitaron (rechaza el disco de arranque) |
| `Services/PrivilegedOperationLog.swift` | `PrivilegedOperationLog` (en `PrivilegedRunner.cs`) | ✅ una línea por operación en `%LOCALAPPDATA%` |
| `Services/APIKeyStore.swift` (Keychain) | `App/Platform/CredentialStore.cs` | ✅ Fase 3 (ST-086) — ver la fila detallada más abajo; se adelantó de la Fase 6 |

### Services (`AuraStudio.App/Services/`)

| macOS (Swift) | Windows | Estado |
|---|---|---|
| `Services/ThemeInstaller.swift` | `ThemeService.cs` / `IThemeService.cs` | ⚠️ valida e instala copiando paquete; con su pantalla (`ThemesPage`), alcanzable desde la barra lateral y desde Extras |
| `Services/LibrarySync.swift` | `SyncService.cs` / `ISyncService.cs` | ✅ sincroniza de verdad: plan, copia, huérfanos, manifiesto y marcador. **Verificado contra el iPod real** (399 archivos). Acota por tipo y por selección (ST-129), y el avance cruza al hilo de la interfaz (ST-131) |
| — (seguridad de disco antes de operación destructiva) | `DeviceSafetyValidator.cs` / `IDeviceSafetyValidator.cs` | ✅ implementado |
| — | `FirmwareTreeInstaller.cs` / `IFirmwareTreeInstaller.cs` | ⚠️ esqueleto, Fase 2 lo completa |
| `Services/IPodMonitor.swift` (orquestación) | `UsbDeviceWatcher.cs` / `IUsbDeviceWatcher.cs` | ✅ implementado y validado — `GetConnectedIPods()` nunca expone candidatos de `Ambiguous` |
| `Services/IPodMonitor.swift` como `@StateObject` de `ContentView` (estado compartido) | `DeviceSessionService.cs` / `IDeviceSessionService.cs` | ✅ Fase 1 — única fuente del estado del dispositivo; publica `State` (Detecting/NotConnected/Connected/Ambiguous), `Device`, `StatusMessage`, `LibraryLocked` y el evento `Changed` |
| `Models/AppPreferences.swift` (`UserDefaults`) | `AppPreferences.cs` / `IAppPreferences.cs` | ✅ Fase 3 (ST-086) — inventario completo de macOS en un JSON bajo `%LOCALAPPDATA%`, con los mismos valores persistidos. **Nunca** guarda API keys: van al Administrador de credenciales |
| `Services/APIKeyStore.swift` (Llavero) + `GitHubToken.swift` | `App/Platform/CredentialStore.cs` (`ApiKeyService`) | ✅ Fase 3 (ST-086) — Administrador de credenciales de Windows, verificado contra `cmdkey`. Adelantado de la Fase 6 por encargo del dueño |
| — (las fechas de Swift son segundos desde 2001) | `Library/AppleEpochDateConverter.cs` | ✅ Fase 3, 8 casos — sin esto, un catálogo real de macOS se leía como biblioteca vacía (ST-086) |
| — (etiquetas con enteros imposibles) | `Library/TolerantInt32Converter.cs` | ✅ Fase 3, 10 casos — un `trackNumber` de 4294967295 costaba el catálogo entero (ST-086) |
| `Models/AppPreferences.swift` (enums de opciones) | `Library/LibraryOptions.cs` | ✅ Fase 3, 14 casos — carátula, organización, nombre de archivo, calidad y colecciones de fotos |
| `NSWorkspace`/`DiskArbitration` (abrir/expulsar) | `VolumeService.cs` / `IVolumeService.cs` | ✅ Fase 1 — interfaz sobre `Platform/VolumeManager` para que los ViewModels no llamen a `Platform/` |

### ViewModels y Views — paridad de pantallas

La app macOS tiene **~42 vistas** (`Sources/AuraStudio/Views/*.swift`); la
Windows tiene **8 páginas**, de completitud variable:

| Página Windows | Vista(s) macOS equivalentes | Estado |
|---|---|---|
| `ShellPage` | `ContentView.swift` + `SidebarView` | ✅ Fase 1 — `NavigationView` definitivo con los mismos grupos que la barra lateral de macOS (Música/Video/Fotos con subsecciones), encabezado de dispositivo, bloqueo de biblioteca con explicación, Instalador y Ajustes al pie |
| *(retirada en R4)* | *(no existe)* | `PlaceholderPage` fue la pantalla honesta de "sección todavía no construida". Con Extras ya no queda ninguna, así que se eliminó junto con su tipo: dejar colgando el camino que la usaba invitaba a volver a colgar algo ahí |
| `DeviceListPage` | `DeviceGeneralView.swift`, parte de `ContentView.swift` | ✅ vista "General" con identidad, firmware, almacenamiento, resumen de biblioteca, abrir en Explorador, expulsión. Fase 1 le agregó los estados vacío/ambiguo y la movió al `DeviceSessionService` |
| `InstallerPage` | `InstallerWizardView.swift` + `InstallerHomeView`, `DetectDeviceView`, `PermissionsView`, `EnterDFUView`, `AwaitBootloaderUSBView`, `InstallingView`, `DoneView` | ✅ Fase 2 sesión 2 — asistente completo sobre `InstallerStep`, con permisos antes del diálogo del sistema, confirmación del disco, ensayo obligatorio antes de formatear y aviso de cambio de familia. Falta `RestoreHandoffView`/`AutomaticUpdateView` (restaurar a Apple y actualización automática) |
| `SongsPage` | `MediaSectionView.swift` (tabla), `TableHeaderMenu` | ✅ Fase 3 — tabla de Canciones con columnas configurables, orden persistido, filtro de favoritos, arrastrar y soltar y menú contextual. **Sin DataGrid del Community Toolkit**, ver ST-085; falta redimensionar columnas arrastrando |
| `MediaGridPage` | `AlbumsView`, `ArtistsView`, `MoviesView`, `SeriesView`, `PhotoAlbumsView` | ✅ Fase 3 — una sola página para las seis cuadrículas; al abrir una tarjeta se navega a la tabla acotada a ese grupo |
| *(pendiente)* | `MediaInfoView`, `BatchMediaInfoView`, `SimilarItemsView`, `CoverContaminationSheet` | ❌ hojas de edición de metadatos y de revisión de similares — el detector ya está en Core (ST-084), falta su pantalla |
| *(retirada en R3-2)* | `SyncSheets.swift`, `DeviceActivityBar.swift` | `SyncPage` existió como sección propia hasta R3-2 y se eliminó: `SidebarSection` de macOS no tiene un caso para sincronizar. La sincronización vive en **General**, junto al estado del aparato (ST-125), y los huérfanos son una hoja aparte |
| `ThemesPage` | `ThemesView.swift` | ✅ en la barra lateral bajo Extras, y también desde la propia pantalla Extras — como en macOS. R3-2 corrigió dos enlaces que la tiraban al dibujarse (ST-126) |
| `ArtistsPage` | `ArtistsView.swift` | ✅ R2-6 — maestro-detalle, no cuadrícula: lista con avatares a la izquierda, ficha con álbumes y pistas a la derecha, selección nativa del `ListView`. Revoca la divergencia de ST-108 |
| `SettingsPage` | `SettingsSectionView`, `MusicSettingsView`, `PhotoSettingsView`, `VideoSettingsView`, `ServicesSettingsView`, `GitHubTokenSettingsView` | ✅ Fase 3 (ST-086) — las seis pestañas de macOS con paridad de opciones. Sin selector de idioma: esta app es de un solo idioma (ST-079), y se dice en pantalla |
| `PlaylistsPage` | `PlaylistsView.swift` | ✅ con su pantalla; el modelo y el M3U están en Core (ST-084) |
| `ExtrasPage` | `ExtrasView.swift` | ✅ R4 (ST-133) — selector de firmware con pastillas de versión y su procedencia, «Revisar de nuevo», Temas y Animaciones, "Todavía no", y Licencias. **Falta** el bloque de *cambiar* entre familias ya instaladas (ST-056): necesita saber qué familias hay dormidas en el aparato, y `IPodDiskInfo` no lo modela todavía |
| `SimilarItemsPage` | `SimilarItemsView.swift` | ✅ con su pantalla; el detector está en Core (ST-084) |
| `LicensesPage` | `LicensesView.swift` | ✅ Fase 2 — **restricción crítica GPL v2** (contrato §B), en Ajustes › Acerca de. Declara repositorio, tag exacto y documentos por familia, más la procedencia de `mks5lboot.exe`; nunca inventa un tag |

**No repetir esta auditoría pantalla-por-pantalla en cada fase** — la
versión exhaustiva y definitiva vive en `ESTADO-PORT.md` a partir de la
Fase 7 (Auditoría de paridad). Esta tabla es solo para orientar qué Swift
mirar al empezar cada fase.

## Patrones de portado (vigentes)

### Swift `enum` asociado → C# `abstract record` cerrado
```swift
enum DiskIdentificationResult {
    case found(DiskCandidateInfo)
    case notFound
    case ambiguous([DiskCandidateInfo])
}
```
```csharp
abstract record DiskIdentificationResult
{
    public sealed record Found(DiskCandidateInfo Candidate) : DiskIdentificationResult;
    public sealed record NotFound() : DiskIdentificationResult;
    public sealed record Ambiguous(IReadOnlyList<DiskCandidateInfo> Candidates) : DiskIdentificationResult;
}
```

### Swift `static func` → C# `static class`
```swift
struct IPodDiskIdentifier {
    static func identify(_ candidates: [DiskCandidateInfo]) -> DiskIdentificationResult { … }
}
```
```csharp
public static class IPodDiskIdentifier
{
    public static DiskIdentificationResult Identify(IReadOnlyList<DiskCandidateInfo> candidates) { … }
}
```

### Swift `init?(rawValue:)` → C# `TryParse`
```swift
extension RunningFirmware {
    init?(rawValue: String) { … }
}
```
```csharp
public static class RunningFirmware
{
    public static RunningFirmware? TryParse(string rawValue) { … }
}
```

### Modelo de deserialización JSON con propiedades no anulables
Cuando un tipo tiene un constructor de dominio (que siempre inicializa) y
otro vacío solo para `System.Text.Json` (deserialización), usar
`required` en las propiedades + `[SetsRequiredMembers]` en el constructor
de dominio — evita `CS8618` sin volver la propiedad anulable ni usar `!`.
Ver `SyncMarker.cs`.

### `[ObservableProperty]` de CommunityToolkit.Mvvm 8.4
Requiere **propiedades parciales**, no campos privados (`MVVMTK0045`), y
`<LangVersion>preview</LangVersion>` en el csproj (sin eso el generador no
emite la mitad de implementación → `CS9248`). Los valores por defecto van
en el constructor, no en el inicializador de la propiedad parcial.

## Riesgos de compilación conocidos (no volver a diagnosticar)

- **TFM y SDK de Windows**: el csproj de `AuraStudio.App` debe apuntar al
  SDK de Windows realmente instalado en la VM
  (`net10.0-windows10.0.26100.0`); un TFM que pida una carpeta de Union
  Metadata no instalada falla el XamlCompiler sin mensaje útil por consola
  (sí lo muestra Visual Studio). `TargetPlatformMinVersion` es aparte
  (mínimo runtime, D4 del plan) y no tiene que coincidir con el TFM.
- **`Window` de WinUI 3 ≠ `Window` de UWP**: no acepta `Width`/`Height` en
  XAML, ni `DataContext` (no es `FrameworkElement`); tampoco `AcrylicBrush`
  tiene `BackgroundSource`. Ver historial completo en `ESTADO-PORT.md`.
