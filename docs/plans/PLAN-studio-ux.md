# PLAN-studio-ux.md — Biblioteca, categorías y temas de Aura Studio

> **ESTADO: ACTIVO — en ejecución.** Aprobado con las 11 recomendaciones
> (P1–P11); la Fase 2 avanza en cuatro tandas (P11), en orden. **Tanda 1
> (§2, metadatos) hecha — ver `ST-007` en `DECISIONS.md`. Tanda 2, parte
> de vistas (§2.1–2.3: `LibraryGrouping`, Álbumes en cuadrícula, Artistas
> maestro-detalle, `MusicScope`, búsqueda) hecha como Artistas / Álbumes /
> Canciones — ver `ST-031` (y `ST-030`/`ST-032` relacionados).** Pendientes:
> tanda 2 §2.4 (`StudioStyle`, Listas plana), tanda 3 (§3/§4 — confianza +
> `CONTRATO-indice-medios.md` + `media_index.cfg`), tanda 4 (§4b — cola de
> temas sin iPod, §5 — constructor con tipografías). La fuente de verdad de
> lo ya decidido es `DECISIONS.md`, no este documento.

**Fase 1 — investigación y plan (solo lectura). 2026-08-17.** El texto original de este documento (abajo) describe el estado ANTES de aprobarse — se conserva sin editar como el entregable real de la Fase 1; el encabezado de arriba es lo que refleja el progreso actual. Todas las rutas de código son relativas a `studio/AuraStudio/Sources/AuraStudio/` salvo que se indique otra cosa; las del firmware, a `/Volumes/Ricolinos/Codigo/GitHub/Aura/Aura-Firmware/`.

Orden de trabajo respetado: **§2 primero** (la carga de metadatos condiciona a §1: no se puede agrupar por álbum si el campo álbum no se lee bien), luego §1, §3/§4, §4b y §5.

---

## 0. Resumen ejecutivo

| Sección | Veredicto en una línea |
|---|---|
| **§2 Metadatos** | **Bug real, causa raíz localizada, reproducido.** El único lector de tags locales de Studio es `ID3Writer.readTag` (`Services/ID3Writer.swift:126`), un parser que se autodefine como *"lectura mínima, para round-trip / revisión"* y solo entiende el subconjunto de ID3v2.3 que el propio escritor produce; además solo se invoca para `.mp3` (`Services/LibraryEnricher.swift:74-77`). Con archivos reales (ID3v2.4 UTF-8, `TRCK "3/12"`, FLAC, M4A) se pierden o corrompen álbum, año, número de pista y portada, y `prepareMusic` (`ViewModels/LibraryViewModel.swift:335-345`) **reescribe la tag del archivo que va al iPod con esos datos rotos**. El arreglo mínimo es un lector local nativo (AVFoundation) para todos los formatos, no un "script que absorba metadatos": ese script duplicaría el enriquecimiento remoto que sí funciona y taparía el bug. Lo único parecido a un script que sí hace falta es una **acción de relectura** para la biblioteca ya importada. |
| **§1 Álbum/Artista + Listas** | Confirmado contra el modelo: son **vistas/filtros** sobre `LibraryViewModel.items` (no hay directorios nuevos; la agrupación por álbum hoy solo existe implícita en las rutas de sync, `LibrarySync.swift:438-439`). El "efecto translúcido tipo Apple" de Listas **no es un `Material` explícito**: es `.listStyle(.sidebar)` dentro del panel de detalle (`Views/PlaylistsView.swift:104`) — AppKit pinta ahí el material vibrante de la barra lateral — más un `.frame(width: 600, height: 420)` fijo (`:64`) heredado de cuando era una hoja modal. Solo hay **un** `Material` en toda la app (`Views/ThemesView.swift:143`) y unas 18 superficies `Color.secondary.opacity(…)` con radios 8 y 10 mezclados. Se propone un módulo `StudioStyle` plano alineado a los tokens del firmware (`SHELL_BG`/`SELECTION_FILL`/`SHELL_RAIL`, radio 8) y homogeneizar todo, no solo Listas. |
| **§3/§4 Video y Fotos** | Ya existe `MediaCategory` (Videos/Series/Películas) + `photoCollections` (Imágenes/Fotos/IA) con heurísticas mínimas y **sin noción de confianza ni de "sugerida vs. confirmada"**. Se propone el modelo *detectar + corregir* con confianza explícita (alta/media/baja/ninguna), heurísticas nuevas honestas por categoría, y **un contrato versionado nuevo** (`CONTRATO-indice-medios.md`, copia idéntica en ambos repos): `sync_summary.cfg` sube a `contract_version: 2` con dos cubetas nuevas, y aparece `.rockbox/aura/media_index.cfg` con la categoría **por archivo** — el dato que le falta al firmware para volver reales sus filas inertes Películas / Programas de TV / Videoclips (`aura_screens.c:301-313`). El Estado 2 de "Acerca de" ya se desbloqueó con D-283 (6 conteos); esto lo extiende sin romperlo. |
| **§4b Temas sin iPod** | Viable con lo que hay: `ThemePackager`/`ThemeValidator` no necesitan dispositivo, solo `ThemeInstaller` sí. Se propone una **cola de temas preparados** en `~/Library/Application Support/AuraStudio/Temas/` con estado visible, aplicación al conectar (validando `theme_format_supported` del iPod antes de copiar), cancelación, y un único "se activará al conectar". |
| **§5 Constructor con tipografías** | **Dependencia verificada: VIABLE.** `PLAN-themes-impl.md` §1.0 del firmware confirma que las 14 fuentes se cargan en runtime desde disco (`font_load()`), y D-289/ST-003…ST-005 lo implementaron de punta a punta (`.rockbox/aura/themes/<id>/fonts/<rol>.fnt`). Hay a dónde instalar. Los roles vienen de `design-system/tokens.json` (`type_scale` + `type_scale_roles`), no se inventan aquí; el detalle de pipeline y las restricciones (`.fnt`, alfa/magenta, CoreText) está en §5. |

---

## 1. §2 — Diagnóstico: por qué "los metadatos no se cargan correctamente"

### 1.1 Qué hace hoy el pipeline (con archivo:línea)

1. Al procesar una canción, `LibraryViewModel.process(itemAt:)` (`ViewModels/LibraryViewModel.swift:213-235`) llama a `LibraryEnricher.enrich(item:…)`.
2. `enrich()` (`Services/LibraryEnricher.swift:71-121`) parte de las tags locales así:
   ```swift
   var existing = ID3Writer.Tag()
   if item.sourceURL.pathExtension.lowercased() == "mp3",
      let data = try? Data(contentsOf: item.sourceURL) {
       existing = ID3Writer.readTag(from: data) ?? ID3Writer.Tag()
   }
   ```
   (`:74-77`). Es decir: **solo MP3**, y con **el lector de `ID3Writer`**. Para FLAC/M4A/AIFF/WAV `existing` queda vacío y el título/artista salen de `FilenameGuesser` (`:7-16`); el álbum solo puede venir de MusicBrainz.
3. `ID3Writer.readTag` (`Services/ID3Writer.swift:126-163`) se define a sí mismo, textualmente, como *"Lectura mínima (para round-trip / revisión)"* y *"Parser de solo lectura, usado por los tests para verificar que lo que se escribió se puede leer de vuelta exactamente igual"* (`:112-125`). Fue diseñado para leer lo que el escritor produce (ID3v2.3, UTF-16 LE con BOM, `TRCK` entero, `TYER`) — nunca para leer archivos ajenos. Sus límites concretos:
   - `:140` — el tamaño de cada frame se lee como entero big-endian plano (correcto en v2.3). En **ID3v2.4 es synchsafe**: cualquier frame ≥ 128 bytes (la portada `APIC`, siempre) desincroniza el recorrido y **se pierden ese frame y todos los posteriores**.
   - `:165-177` (`decodeText`) — solo maneja el byte de codificación `0x01` asumiendo BOM little-endian; `0x02` (UTF-16BE) y **`0x03` (UTF-8, el default de ID3v2.4 que escriben ffmpeg, MusicBrainz Picard, foobar2000, yt-dlp…) caen en `default` y se decodifican como Latin-1** → *mojibake* en cualquier texto con acentos o ñ ("CanciÃ³n", "Ãlbum"). Un BOM big-endian en `0x01` da basura.
   - `:151` — solo `TYER`; ID3v2.4 usa **`TDRC`** → el año se pierde.
   - `:154` — `Int(decodeText(payload) ?? "")`: **`"3/12"` (pista/total, lo que escriben casi todos los etiquetadores) → `nil`** → número de pista perdido incluso en v2.3.
   - No maneja ID3v2.2 (frames de 3 letras, lo que escribía iTunes hasta ~2006: nada se lee), ni el *extended header* (flag `0x40`), ni *unsynchronisation* (`0x80`), ni el footer de v2.4, ni `TCON` numérico `(17)`.
4. **La pérdida se vuelve permanente**: `prepareMusic` (`ViewModels/LibraryViewModel.swift:335-345`) construye una `ID3Writer.Tag` con la metadata resuelta y llama a `ID3Writer.write(tag, toFileAt: destination)`, que **reemplaza la tag ID3v2 completa** del MP3 en `.preparados/` (`ID3Writer.swift:43-52`). El archivo que `LibrarySync` copia al iPod lleva el mojibake / los campos faltantes, y eso es lo que indexa el tagcache de Rockbox — el iPod muestra exactamente lo mismo roto que Studio. Para no-MP3, D-037 (`DECISIONS-ARCHIVE.md:250`) ya aclaraba que "si el archivo ya traía esas tags, tagcache las lee igual": el iPod ve el álbum correcto del FLAC mientras **Studio no lo ve nunca** — de ahí la inconsistencia entre lo que muestra la app y lo que muestra el aparato.
5. Además, cuando el álbum falta localmente, `enrich()` toma `recording.releases?.first` (`LibraryEnricher.swift:105`) — el **primer release arbitrario** de la grabación en MusicBrainz (recopilaciones, sencillos, reediciones), sin umbral mínimo de `score` (`MusicBrainzClient.swift:87` elige el máximo, aunque sea 30). Dos pistas del mismo álbum pueden terminar con álbumes distintos — precisamente lo que rompe una vista "por álbum".
6. `MediaTableRow` muestra `""` para álbum/artista `nil` (`Views/MediaSectionView.swift:613-614`) y `LibrarySync` los manda a `Music/Desconocido/Desconocido/` (`Services/LibrarySync.swift:438-439`).

### 1.2 Reproducción (evidencia, no hipótesis)

Se generaron fixtures con `ffmpeg 8.1.2` (mismo binario que Studio localiza, D-038) y se corrió el lector actual y AVFoundation sobre cada uno (paquete de prueba desechable en el scratchpad de la sesión, copia literal de `ID3Writer.swift`; no se tocó el repo):

| Fixture | `ID3Writer.readTag` (Studio hoy) | `AVURLAsset.load(.metadata)` |
|---|---|---|
| MP3 **ID3v2.4 UTF-8** (default de ffmpeg/Picard), título "Canción de práctica", `TRCK 3/12`, `TDRC 2020` | title=`"CanciÃ³n de prÃ¡ctica"`, artist=`"ÃandÃº y CompaÃ±Ã­a"`, album=`"Ãlbum NÃºmero Uno"`, **year=nil, track=nil** | todo correcto (`TDRC`, `TRCK "3/12"`, `TPE2` disponibles) |
| MP3 ID3v2.3 UTF-16 (BOM LE), `TRCK 3/12` | texto correcto, **track=nil** | correcto |
| MP3 ID3v2.4 con portada | album=`"Ãlbum con portada"`, **portada perdida (0 B)** | portada 17 593 B |
| MP3 ID3v2.3 con portada | correcto, portada 17 593 B | correcto |
| **FLAC** con Vorbis comments | **no se lee** (extensión ≠ mp3) | title/artist/album/`DATE`/`TRACKNUMBER` (vía `.metadata`; ojo: `.commonMetadata` viene vacío para Vorbis aunque `commonKey` sí está poblado); la portada `METADATA_BLOCK_PICTURE` **no** se expone |
| **M4A** (átomos iTunes) | **no se lee** | title/artist/album/`©day`/`trkn` (8 bytes binarios) + portada |
| **AIFF** con chunk ID3 | **no se lee** | correcto |
| WAV con `LIST/INFO` | **no se lee** | AVFoundation tampoco lo expone (formato marginal para etiquetas; se acepta) |

Conclusión: la falla es **lectura de tags locales** (formatos y codificaciones), no el enriquecimiento remoto (que funciona, D-203) ni la persistencia (`biblioteca.json` guarda fielmente lo que se leyó mal, `Models/LibraryPersistence.swift`) ni la vista.

### 1.3 Por qué NO un "script que absorba los metadatos"

Un script externo (o un paso batch nuevo) tendría que leer exactamente las mismas tags → duplicaría lógica dentro de Studio, dejaría el bug intacto en el camino "arrastrar y listo", y seguiría alimentando a `prepareMusic` con lo mismo. La infraestructura de metadata existente (MusicBrainz + CAA/fanart/Deezer + LRCLIB, con rate-limit y reintentos) es correcta; lo que está roto es la **entrada** local, que es un componente pequeño y aislable. Lo que el dueño intuye como "script" es en realidad la necesidad de **volver a leer** lo ya importado con el lector nuevo — eso se resuelve con una acción explícita, no con un script.

### 1.4 Arreglo mínimo propuesto

1. **`Services/LocalTagReader.swift` (nuevo)** — lector nativo de tags para `mp3/m4a/flac/aiff/aif/wav` basado en `AVURLAsset.load(.metadata)` (Foundation/AVFoundation, sin dependencias, sin leer el archivo entero a memoria como hace hoy `Data(contentsOf:)`). Itera **`.metadata`** (no `.commonMetadata`, por el hueco de Vorbis) y mapea:
   - por `commonKey`: `title`, `artist`, `albumName`, `creator`→composer, `type`→genre, `creationDate`→año (prefijo de 4 dígitos), `artwork`;
   - por identificador específico lo que `commonKey` no cubre: ID3 `TPE2`/`TDRC`/`TYER`/`TRCK`/`TCOM`/`TCON`, iTunes `aART`/`©day`/`trkn` (decodificar los 8 bytes: pista en bytes 2-3, total en 4-5)/`©wrt`/`©gen`, Vorbis `ALBUMARTIST`/`DATE`/`TRACKNUMBER`/`COMPOSER`/`GENRE`;
   - `TRCK`/`TRACKNUMBER` con forma `n/m` → `n`; género `(NN)` → nombre de la tabla ID3v1 (opcional, bajo costo).
   - Portada FLAC: parser mínimo del bloque `PICTURE` (tipo 6) del contenedor FLAC (cabecera `fLaC` + bloques `[tipo:1][len:3]`, ~40 líneas) — o dejarla al camino remoto/sidecar; recomendación: incluirla, es trivial y determinista.
   - Devuelve `TrackMetadata` parcial (misma estructura que hoy) — sin cambio de modelo.
2. **`LibraryEnricher.enrich()`** usa `LocalTagReader` para **todos** los formatos de música (`:74-77`), conservando la regla "lo local manda, lo remoto solo rellena huecos".
3. **`ID3Writer.readTag`** queda como lo que dice ser (verificador de round-trip para tests). Opcionalmente se endurece en 4 líneas (frames synchsafe en v2.4, `0x03` UTF-8, `TDRC`, `n/m`) para que también los tests lo cubran — barato, y evita que alguien lo vuelva a usar en producción sin darse cuenta. Recomendación: hacerlo.
4. **Umbral de MusicBrainz** — no aceptar una `Recording` con `score < 70` para *rellenar* álbum/año (`MusicBrainzClient.swift:87`): con tags locales completas ya no importa; sin ellas, es mejor "Sin álbum" (revisable) que un álbum inventado. Cambio de una línea, con test.
5. **Acción "Volver a leer etiquetas del archivo"** en el menú contextual de Música (y en lote): relee con `LocalTagReader` **el archivo original** (`sourceURL`, nunca el de `.preparados/`, que ya trae la tag reescrita), reemplaza los campos que vengan del archivo (título/artista/álbum/álbum-artista/año/género/compositor/pista/portada), conserva calificación y letra, vuelve a correr `prepareMusic` y persiste. Al arrancar con un catálogo importado antes de este cambio (sin marca `tagReaderVersion` en `biblioteca.json`), Studio ofrece **una sola vez** un banner: *"Aura Studio ahora lee mejor las etiquetas de tus archivos. ¿Quieres volver a leer las N canciones de tu biblioteca?"* — con opción de hacerlo luego desde el menú. Esto es lo que resuelve la biblioteca existente del dueño sin un script aparte.
6. **Sin cambios de contrato**: nada de esto toca `sync_manifest.json`, `sync_summary.cfg` ni layouts del iPod (`CONTRATO-firmware-studio.md` §D). El resultado es solo que la tag reescrita en `.preparados/` y las rutas `Music/<Artista>/<Álbum>/` salen correctas.

**Tests que cubren el bug (Fase 2)**: fixtures generados en el propio test con `ffmpeg` si está disponible (mismo patrón que `LibraryPipelineIntegrationTests`, `XCTSkip` si no) para v2.4-UTF-8, v2.3, portada v2.4, FLAC, M4A, AIFF; más fixtures binarios diminutos construidos a mano para v2.2 y BOM BE (no dependen de ffmpeg); y un test de `enrich(online: false)` que verifique que FLAC/M4A **sí** llegan con álbum al `TrackMetadata`.

**Impacto en §1**: con esto, "álbum" y "artista" son datos confiables por primera vez para todos los formatos, y las vistas de §1 tienen sobre qué agrupar.

---

## 2. §1 — Música: vistas "Por álbum" y "Por artista", y tratamiento plano de Listas

### 2.1 Confirmación del modelo

- La biblioteca es `LibraryViewModel.items: [LibraryItem]` en memoria + `biblioteca.json` (`Models/LibraryPersistence.swift`); álbum/artista viven en `TrackMetadata` (`Models/TrackMetadata.swift`). **No hay ninguna agrupación en memoria hoy** (`grep Dictionary(grouping:` → 0 resultados). Las únicas nociones de "mismo álbum" son (a) la ruta de sync `Music/<Artista>/<Álbum>/` (`LibrarySync.swift:431-467`, con `"Desconocido"` para faltantes en `:438-439`) y (b) las acciones "Seleccionar canciones del mismo álbum/artista" del menú contextual (`Views/MediaSectionView.swift:486-495`, comparación cruda de strings).
- Por lo tanto: **"Por álbum" y "Por artista" son vistas sobre la misma colección. No se crea ningún directorio** — ni local ni en el iPod. La organización en disco sigue siendo la que decide `musicOrganization` (`AppPreferences.swift:113-125`) y no cambia con esta pasada.

### 2.2 Navegación

`SidebarSection` (`Views/ContentView.swift:189-244`) gana dos casos: `.musicAlbums` ("Por álbum", símbolo `square.stack`) y `.musicArtists` ("Por artista", `person.2`), anidados en el `DisclosureGroup` de Música junto a `.musicPlaylists` (`:265-273`) — mismo mecanismo, misma regla de bloqueo `libraryLocked`. Orden: Música (canciones) → Por álbum → Por artista → Listas.

### 2.3 Qué muestra cada vista

**Modelo puro y testeable** — `Models/LibraryGrouping.swift` (nuevo):

```swift
struct AlbumGroup: Identifiable { let id: String; let title: String; let artist: String; let items: [LibraryItem]; let coverArtData: Data?; let year: String?; let isUnknown: Bool }
struct ArtistGroup: Identifiable { let id: String; let name: String; let albums: [AlbumGroup]; let trackCount: Int; let isUnknown: Bool }
enum LibraryGrouping {
    static func albums(from items: [LibraryItem]) -> [AlbumGroup]
    static func artists(from items: [LibraryItem]) -> [ArtistGroup]
}
```

Reglas:
- **Clave de álbum** = (`album` normalizado, artista de álbum normalizado) donde artista de álbum = `albumArtist ?? artist` — la misma precedencia que ya usa la ruta de sync (`LibrarySync.swift:438`), para que lo que se ve en Studio coincida con las carpetas del iPod. Normalización: recortar espacios y comparar sin distinguir mayúsculas/diacríticos (`folding(options: [.caseInsensitive, .diacriticInsensitive])`); se muestra la grafía de la primera pista.
- **Sin álbum** (`album == nil` o vacío) → grupo especial **"Sin álbum"** (por artista, si lo hay), siempre **al final**, con `isUnknown = true`. Sin artista → **"Artista desconocido"**, al final. En pantalla se usan esos rótulos; en disco se sigue usando `"Desconocido"` (no se toca la ruta de sync ni las bibliotecas ya organizadas).
- **Orden**: álbumes por título (`localizedStandardCompare`, ignora artículo inicial "El/La/Los/Las/The"), luego por año; dentro del álbum por número de pista y luego título; artistas por nombre. Selector de orden en la barra superior de la vista: "Título · Artista · Año · Agregado recientemente" (persistido en `UserDefaults` como ya hacen las columnas, `MediaSectionView.swift:205`).

**Vista "Por álbum"** (`Views/AlbumsView.swift`, nuevo): cuadrícula (`LazyVGrid`, celdas 160 pt) de tarjetas planas: portada 128×128 con radio 8 (`corner_radius_card` del design system) o placeholder sólido `SELECTION_FILL` con `music.note` (mismo criterio que `PlaylistArtGenerator`), título (1 línea), artista secundario, "N canciones · año". Clic → **la misma tabla de canciones** (`MediaSectionView(kind: .music)`) filtrada por ese álbum, con una barra de migas "Por álbum › Nombre del álbum" y botón "‹ Álbumes"; conserva columnas, selección, menú contextual, arrastre y QuickLook sin reimplementar nada (se agrega un parámetro `scope: MusicScope = .all | .album(key) | .artist(key)` a `MediaSectionView`, que hoy ya filtra por categoría en `:72-75`). Buscador local (título/artista) arriba a la derecha.

**Vista "Por artista"** (`Views/ArtistsView.swift`, nuevo): maestro-detalle: lista de artistas a la izquierda (nombre + "N álbumes · M canciones"), detalle a la derecha con los álbumes del artista en la misma cuadrícula (reutiliza la celda de álbum) y debajo un botón "Todas las canciones" → tabla filtrada por artista. Clic en un álbum → tabla filtrada por álbum. Un artista sin álbum conocido muestra su grupo "Sin álbum".

**Acciones sobre un grupo** (menú contextual de tarjeta de álbum / fila de artista): "Agregar a lista…", "Obtener información…" (abre `BatchMediaInfoView` con las canciones del grupo — ya existe, D-218), "Buscar información en línea", "Seleccionar en Música", "Mostrar en Finder", "Eliminar" (con confirmación, misma `deleteItems`).

**Casos vacíos** (obligatorios en tests): biblioteca vacía → mismo `DropZone` grande de hoy con el texto "Suelta música aquí para verla por álbum"; todo sin álbum → un solo grupo "Sin álbum"; álbumes homónimos de artistas distintos → grupos distintos; misma canción con "Álbum" y "álbum " → un solo grupo.

### 2.4 Estilo plano y homogéneo (Listas y todo lo demás)

**Diagnóstico** (agente de barrido sobre `Views/*.swift`):
- `Views/PlaylistsView.swift:104` — `.listStyle(.sidebar)` en un `List` que vive en el panel de **detalle**: en macOS eso pinta el material vibrante/translúcido de barra lateral (blur de lo que hay detrás de la ventana). **Es el efecto que el dueño ve.** Sumado a `.frame(width: 600, height: 420)` (`:64`), la vista queda como un panel flotante chico y translúcido en medio del detalle.
- `Views/ThemesView.swift:143` — único `Material` explícito de la app (`.regularMaterial` en el overlay "Construyendo e instalando…").
- 18 superficies con `Color.secondary.opacity(0.05…0.25)` y radios `8` y `10` mezclados para el mismo rol de tarjeta (`SettingsSectionView.swift:93,185`, `ServicesSettingsView.swift:98`, `DoneView.swift:47,63`, `RestoreHandoffView.swift:30`, `DeviceGeneralView.swift:122,369`, `BootModeView.swift:82,96-98`, `MediaSectionView.swift:565`, `PlaylistsView.swift:169`, `MediaInfoView.swift:102,168`, `BatchMediaInfoView.swift:161`, …). Ningún `.shadow`. `Generated/AuraPalette.swift` (tokens del firmware) tiene **un solo consumidor**: `ContentView.swift:64` (`.tint`).

**Decisión del firmware que se adopta**: `docs/design/Reglas de diseño Apple2026 (v2).md` §2.1 (línea 55): *"**Resuelto: plano, sin transparencia.** … relleno sólido (`SELECTION_FILL`, `SHELL_BG`) y sin ningún halo ni alfa parcial. La referencia a Liquid Glass queda solo como principio de jerarquía"*; Principio 1 (*"nada de marcos, biseles ni cajas"*), Principio 6 (*"el vidrio es un privilegio de los controles"*), anti-patrón §8:165, y D-072 (retiró `surface`/`border` como tokens: una superficie es `SHELL_BG` con raya de 1 px `SHELL_RAIL`, o un relleno `SELECTION_FILL` sólido). Radios: `corner_radius_card` = **8 px**, chips 6 px, concéntricos.

**Propuesta — `Views/StudioStyle.swift` (nuevo)**:
- `StudioPalette` resuelve `AuraColors.light`/`.dark` según `colorScheme` (los tokens **ya están generados**, solo no se usan): `background` = `shellBg`, `surface` = `selectionFill`, `rail` = `shellRail`, `textSecondary`, `accent`.
- Modificadores: `.studioCard()` (relleno `surface` sólido, radio 8, sin borde), `.studioOutlinedCard()` (fondo `background` + trazo 1 px `rail`, radio 8), `.studioChip(selected:)` (cápsula 6 px, sólida `surface`; seleccionada = texto e ícono en acento, no fondo de acento — Principio 2), `.studioBanner(kind:)`.
- **Listas**: `List` de playlists pasa a `.listStyle(.plain)` con fondo `background`, se quita el `.frame` fijo (ocupa el detalle completo con maestro de 220 pt como las demás vistas), la cabecera "Playlists" → "Listas" (mismo nombre que la barra lateral), el botón "Listo" desaparece (ya no es hoja) y el placeholder de portada usa `surface` sólido. Mismo tratamiento maestro-detalle que "Por artista", así las tres subvistas de Música se ven iguales.
- **Todos los sitios de la tabla anterior** migran a los modificadores (una pasada mecánica; sin cambios de comportamiento). El `.regularMaterial` de `ThemesView` pasa a tarjeta sólida.
- **La barra lateral real** de la ventana (`ContentView.swift:289`, `.listStyle(.sidebar)`) **se conserva nativa**: es la capa de navegación de macOS — coincide con el Principio 6 (vidrio solo en la capa de controles/navegación) y con lo que hace toda app de macOS; quitarlo se vería ajeno al sistema. Ver pregunta abierta P3.

**Textos**: todos los nuevos en español de México, sin voseo, y por `S` (`Models/AppStrings.swift`) al menos los de la barra lateral (los de tablas hoy están fijos en español, como documenta `AppStrings.swift:8-12`; se sigue esa práctica sin ampliar alcance).

---

## 3. §3/§4 — Categorías de Video y Fotos con detección automática honesta

### 3.1 Estado actual (verificado)

- `Models/MediaCategory.swift:16-51`: enum `videos/series/movies` (rótulos "Videos", "Series", "Películas"; **se persiste el `displayName` localizado**, `LibraryItem.swift:50-58`). Heurísticas en el mismo archivo (`:58-98`): `classifyVideo` = `> 2400 s → Películas`, todo lo demás "Videos"; Series solo a mano; `classifyPhoto` = tag Software con nombre de generador (`:64-67`) → "IA"; EXIF de cámara (`LensModel/FNumber/Make`, `Services/MediaCategoryClassifier.swift:17-19`) → "Fotos"; resto → "Imágenes". Colecciones de foto libres en `AppPreferences.photoCollections` (default `["Imágenes","Fotos","IA"]`, `:233`).
- UI: chips de filtro (`MediaSectionView.swift:544-552`), columna "Categoría" (`:393`), menú "Cambiar categoría" en lote (`:501-508`), `Picker` en `MediaInfoView.swift:175-189`. **No hay ninguna señal de "sugerida" ni de confianza**: la única marca es `if items[index].category == nil` (`LibraryViewModel.swift:241/275`).
- Contrato actual con el firmware: `sync_summary.cfg` (`Models/CatalogSummary.swift:76-94`, 13 claves; escrito en `LibrarySync.swift:259/373-377`; mapeo por rótulo en `:167-196` — **todo lo desconocido cae en `video_clips_count`/`photo_images_count`**). El firmware lo lee en `aura_manifest.c:51-98` (mismo `settings_parseline` de `aura.cfg`, `char line[64]`) y lo pinta en `aura_screens.c:2780-2824` ("Películas / Series / Videoclips", "Imágenes / Fotografías / IA", `aura_lang.c:86-94`). D-283 ya desbloqueó el Estado 2 con estas 6 cubetas. `CONTRATO-firmware-studio.md` §D no enumera las claves y `contract_version` sigue pendiente (`:64`, `:88`).
- El firmware ya tiene el submenú Videos → **Todos los videos · Películas · Programas de TV · Videoclips** (`aura_screens.c:301-313`) pero las tres últimas filas están **inertes/atenuadas** (`:2079-2084`, `:4670-4676`): *"sin desglose real por subcarpeta (esa clasificación es trabajo aparte)"* (`:1692-1714`). `/Videos` y `/Photos` son planas por diseño (`aura_video.c:51,83-105`, sin recursión, solo `.mpg/.mpeg`, `MAX_VIDEOS 100`; D-062/D-228). Precedente de índice **por archivo** ya consumido por el firmware: `ratings.cfg` (`"/<ruta>: n"`, `aura_music.c:145-157`, `char line[MAX_PATH + 16]`).
- Vocabulario divergente entre repos, a resolver en el contrato: Studio "Series" ↔ menú del firmware "Programas de TV" (`aura_lang.c:181-185`; su "Acerca de" y su string de vacío sí dicen "Series"); "Videoclips" del menú (EN "Music Videos") ≠ `video_clips_count` (que hoy significa "sin clasificar").

### 3.2 Modelo: detectar + corregir, con confianza explícita

Cambios de modelo (persisten en `biblioteca.json`; migración: como hoy no se registra si el usuario tocó la categoría, todo lo existente entra como `suggested`/`medium` — sin banner intrusivo, solo el chip discreto de "sugerida"):

```swift
enum CategoryConfidence: String, Codable { case high, medium, low, none }
enum CategorySource: String, Codable { case suggested, confirmed }   // confirmed = lo tocó el usuario
// LibraryItem: var category: String?; var categoryConfidence: CategoryConfidence?; var categorySource: CategorySource?
```

`MediaCategory` (video) pasa a 4 casos con `rawValue` **estable en inglés** (lo que se persiste y lo que viaja al iPod) y `displayName` solo para pantalla: `clip` "Videoclips", `home` "Videos caseros", `series` "Series", `movie` "Películas". Fotos: se conservan las colecciones libres del usuario, pero las **cuatro cubetas del contrato** tienen id estable: `photo` "Fotografías", `image` "Imágenes", `ai` "Creadas con IA", `wallpaper` "Fondos de pantalla"; una colección personalizada del usuario se mapea a `image` en el índice (como hoy) salvo que él la asocie a una cubeta al crearla (selector "Cuenta como: Fotografías / Imágenes / IA / Fondos"). Esto corrige de paso el mapeo por rótulo localizado de `LibrarySync.swift:176-194`.

**Heurísticas y su confianza (honestas)** — `MediaCategoryHeuristics` (pura, testeable) + `MediaCategoryClassifier` (lee disco):

| Categoría | Señal | Confianza asignada | Notas |
|---|---|---|---|
| Series | Nombre de archivo o carpeta padre con `S01E02`, `1x02`, `T01E02`, `Temporada 1`/`Season 1`, `Cap(ítulo) 12`, `Episodio 3` (regex, sin distinguir mayúsculas) | **alta** | Se extrae también `series_title`, temporada y episodio para el índice (opcional). |
| Películas | Duración ≥ 65 min **y** sin patrón de serie | **media** | Hoy el corte es 40 min (`:95`): un capítulo de 45 min sin patrón hoy se vuelve "Película"; se sube a 65. |
| Videos caseros | Metadata de cámara en el contenedor (QuickTime `com.apple.quicktime.make/model/location`, `creationdate` con GPS; `AVURLAsset` los expone; también `Make/Model` en MP4 de cámaras) | **media-alta** si hay make/model o GPS; **baja** si solo el nombre `IMG_1234`/`MOV_`/`VID_` | Única señal real; se documenta como tal. |
| Videoclips | Corto (≤ 10 min) sin señal de cámara; título/artista/comentario con URL de YouTube (`©cmt`/`comment` de yt-dlp) refuerza | **media** con metadata de artista o URL; **baja** solo por duración | |
| Sin categoría | 10–65 min sin ninguna señal, o señales contradictorias | **ninguna** | Se deja `nil` y se pide al usuario. |
| Fotografías | EXIF de cámara (Make/Model/LensModel/FNumber/ExposureTime) | **alta** (Make+Model+exposición), **media** (solo uno) | Como hoy, más campos. |
| Creadas con IA | (a) tag Software/UserComment con generador conocido (hoy); (b) chunk PNG `tEXt` `parameters` (Automatic1111), `prompt`/`workflow` (ComfyUI), `Software: NovelAI`; (c) manifiesto **C2PA** presente (JUMBF `c2pa` en JPEG APP11 / `caBX` en PNG — DALL·E 3, Firefly, Imagen 3 lo escriben) | **alta** para (b)/(c); **media** para (a); **ninguna** en el caso general (Midjourney vía Discord, capturas, redes sociales borran todo) | Se declara explícitamente en la UI que "IA" **no se puede detectar en general**; la categoría existe sobre todo para asignarla a mano. |
| Fondos de pantalla | Sin EXIF de cámara **y** proporción de pantalla (16:9, 16:10, 21:9, 9:16/19.5:9 vertical, 4:3/3:2 sin cámara) **y** lado mayor ≥ 1920 px; nombre con `wallpaper`/`fondo` refuerza | **baja** (a lo sumo **media** con nombre) | Capturas de pantalla (`Captura de pantalla…`, `Screenshot`) se excluyen → "Imágenes". |
| Imágenes | Todo lo demás | (default) | |

Regla dura: **con confianza `low` o `none` nunca se clasifica en silencio** — el ítem se marca "Revisar" y la categoría se muestra como propuesta.

### 3.3 Cómo se comunica la confianza en la UI

- **Columna "Categoría"** de la tabla (foto/video): chip plano con el rótulo; si `source == .suggested` lleva un punto/`questionmark.circle` a la izquierda y tooltip *"Sugerida por Aura Studio (confianza media). Haz clic para confirmar o cambiar."*; con `low/none` el chip va con trazo discontinuo y texto "Revisar: ¿Videoclip?" / "Sin categoría". Un clic abre el mismo `Picker` (menú) para confirmar; confirmar = `source = .confirmed`, `confidence = high`.
- **Chip de filtro nuevo "Por revisar (N)"** junto a los de categoría (`MediaSectionView.swift:544-552`) y acción de lote **"Confirmar categorías sugeridas"** en el menú contextual (todo lo `suggested` con `high/medium` pasa a `confirmed`).
- **Al soltar archivos** (`addDroppedFiles`): no aparece un diálogo modal (rompe "arrastrar y listo"); en cambio, al terminar el procesamiento, un banner sobre la tabla — el mismo `enrichmentBanner` de música (`:121`) generalizado — dice *"3 videos clasificados como Series, 1 como Película. 2 necesitan que elijas la categoría."* con botón "Revisar".
- **`MediaInfoView`**: bajo el `Picker` de categoría, una línea secundaria *"Sugerencia automática: Serie (patrón S02E05 en el nombre)"* — la **razón** de la detección, texto generado por la heurística (`reason: String`).
- Ajustes de Video/Fotos: el texto explicativo (`VideoSettingsView.swift:9-13`, `PhotoSettingsView.swift:29-33`) se actualiza para decir qué se detecta y con qué límites ("Las imágenes creadas con IA no se pueden reconocer de forma general — asígnalas a mano.").

### 3.4 Contrato versionado: qué escribe Studio al iPod para el firmware

> **Superado (2026-08-18, `PLAN-biblioteca-medios-v2.md`, carpeta padre).** El firmware implementó su propio formato en D-316/D-318 **antes** de que esta sección se ejecutara: dos archivos `.rockbox/aura/video_categories.cfg`/`photo_categories.cfg`, clave = nombre de archivo SIN ruta, códigos `movie|series|clip` / `photo|image|ai`, sin `contract_version`, sin sub-claves `#season`/`#episode` — formato exacto en `CONTRATO-firmware-studio.md` §D.2 (v5). Lo que sigue (un único `media_index.cfg` con rutas absolutas y cubetas `home`/`wallpaper`) **no se implementa** — manda el contrato ya publicado, no este plan. La implementación real del lado Studio está en `PLAN-biblioteca-medios-v2.md` Tanda 1.

Se crea **`CONTRATO-indice-medios.md`** (raíz de este repo; copia idéntica en `Aura-Firmware`, que es la fuente canónica — exactamente el modelo de `CONTRATO-formato-tema.md`), y `CONTRATO-firmware-studio.md` §D lo referencia y por fin enumera las claves. Contenido propuesto (v1 de ese contrato = `contract_version: 2` del canal de datos, porque `sync_summary.cfg` ya existe sin versión):

**A. `/.rockbox/aura/sync_summary.cfg` (existente, extendido, compatible hacia atrás)**
```
contract_version: 2
music_count: N
music_bytes: N
video_count: N
video_bytes: N
photo_count: N
photo_bytes: N
playlist_count: N
video_movies_count: N
video_series_count: N
video_clips_count: N          # v2: SOLO los clasificados como videoclip (ya no "todo lo demás")
video_home_count: N           # nuevo
photo_images_count: N
photo_photos_count: N
photo_ai_count: N
photo_wallpapers_count: N     # nuevo
```
Reglas: mismo formato `clave: valor` (`settings_parseline`), líneas ≤ 63 caracteres (techo real del lector, `aura_manifest.c:54`); claves desconocidas se ignoran; un firmware v1 sigue leyendo sus 13 claves sin cambios (solo cambia el **significado** de `video_clips_count`, por eso sube la versión); las cubetas pueden sumar menos que `video_count`/`photo_count` (los ítems sin categoría no se cuentan en ninguna). Sin `contract_version` = v1.

**B. `/.rockbox/aura/media_index.cfg` (nuevo, por archivo)** — lo que el firmware necesita para volver reales Películas / Series / Videoclips (y en el futuro categorías de fotos), sin recorrer subcarpetas ni parsear EXIF en el aparato:
```
contract_version: 2
/Videos/Casa 2019.mpg: home
/Videos/Breaking Bad S01E01.mpg: series
/Videos/Breaking Bad S01E01.mpg#series_title: Breaking Bad     # opcional
/Videos/Breaking Bad S01E01.mpg#season: 1                       # opcional
/Videos/Breaking Bad S01E01.mpg#episode: 1                      # opcional
/Videos/Amélie.mpg: movie
/Videos/Daft Punk - Around the World.mpg: clip
/Photos/IMG_4021.jpg: photo
/Photos/wall-01.jpg: wallpaper
/Photos/dalle-perro.png: ai
```
Reglas: una línea por archivo sincronizado, clave = **ruta absoluta en el dispositivo** (mismo criterio que `ratings.cfg`, que el firmware ya parsea con `char line[MAX_PATH+16]`), valor = id estable en inglés del conjunto cerrado `{clip, home, series, movie}` / `{photo, image, ai, wallpaper}`; sub-claves opcionales con `#` (el `:` de `settings_parseline` es el primero, y `PathSanitizer` garantiza que ni `:` ni `#` aparecen en las rutas que Studio escribe); solo se escriben ítems con categoría (`suggested` o `confirmed` — la confianza **no** viaja: el iPod muestra lo que Studio muestra; el lugar para corregir es Studio); el archivo se reescribe entero en cada sync (`LibrarySync`, junto a `sync_summary.cfg`), en UTF-8, atómico; el firmware lo ignora si falta (comportamiento actual) y **nunca re-clasifica**. Orden: alfabético por ruta, para diffs estables.

**Independencia de rutas de Studio**: el contrato no menciona ninguna ruta de este repo; el firmware lo consume solo desde el disco montado y desde el documento. Compatibilidad: firmware v1 + Studio v2 → firmware ignora `media_index.cfg` y las 2 claves nuevas; Studio v2 + firmware v1 → Studio sigue escribiendo todo (nada que negociar). Un cambio futuro de ids o de conjunto sube `contract_version`.

**Del lado del firmware (fuera de este repo, para coordinar, no para implementar aquí)**: leer `media_index.cfg` en `aura_manifest.c`, hacer navegables las 3 filas inertes filtrando `/Videos` por categoría, y unificar el rótulo "Programas de TV" → "Series" (su propio "Acerca de" ya dice "Series"). Se documenta en `CONTRATO-indice-medios.md` como "consumo esperado", sin obligar fecha.

---

## 4. §4b — Temas preparados sin iPod conectado

### 4.1 Estado actual (verificado)

- `Views/ExtrasView.swift:20-23` — `canManageThemes` exige `device.isAura`; sin iPod la fila "Temas" está deshabilitada con el texto *"Conecta tu iPod con Aura instalado para instalar, activar o construir temas."* (`:47-56`), y la hoja solo se presenta con dispositivo (`:37-41`).
- `Views/ThemesView.swift:17-22` — `ThemesViewModel(mountPath:)` obligatorio; `buildAndInstall` (`:51-81`) empaqueta en `FileManager.default.temporaryDirectory/AuraThemeBuild-<UUID>`, instala y **borra el paquete en el `defer`** (`:71-72`): hoy no queda nada persistido de un tema construido. Cero ocurrencias de "pendiente" en `Theme*.swift`.
- Lo que **no** necesita iPod: `ThemePackager.package` y `ThemeValidator.validate(packageRoot:firmwareSupportedFormat:)` (con `nil` valida contra `ThemeFormat.current`). Lo que sí: `ThemeInstaller.install/activate/delete/listInstalled` (`Services/ThemeInstaller.swift:55-200`), que además toma el candado `InstallerFlowRegistry` (`:84,124,149`).
- Punto de enganche para "al conectar": `Views/ContentView.swift:125-127` `.onChange(of: deviceMonitor.device)` — precedente idéntico ya implementado (`refreshUpdateAvailability`, `:129-140`: `guard let device, device.isAura` + `Task`). El publisher es `IPodMonitor.device` (`Services/IPodMonitor.swift:16`), alimentado por `AuraDeviceProbe.probe` (`:80`).
- Lectura de compatibilidad: `ThemeInstaller.supportedThemeFormat(mountPath:)` (`:192-200`) lee `theme_format_supported` de `aura.cfg`; `nil` = firmware anterior a D-289 (sin temas).
- Precedente de almacenamiento local: `~/Library/Application Support/AuraStudio/` (`Services/PrivilegedOperationLog.swift:5-19`).

### 4.2 Diseño

**Dónde se guarda**: `~/Library/Application Support/AuraStudio/Temas/<id>/` — el paquete **ya validado** en el layout del contrato (lo mismo que se copiaría con `ditto`), más `~/Library/Application Support/AuraStudio/Temas/temas.json` con el estado:

```json
{ "version": 1,
  "themes": [ { "id": "apple-personal", "name": "Apple (uso personal)", "preparedAt": "2026-08-17T18:02:11Z",
                "format": 1, "license": "personal", "redistributable": false,
                "pendingInstall": true, "activateOnInstall": true,
                "lastInstalledOn": null } ] }
```

Razones: no es media (no va a `~/Documents/Aura Library`), sobrevive a limpiezas de `/tmp`, no se sincroniza a iCloud, y ~11 MB por tema es razonable ahí. Un tema construido con assets restringidos **queda solo en esta Mac** — coherente con el principio rector; la carpeta no se expone en Finder salvo "Mostrar en Finder" explícito.

**Servicio nuevo `Services/PreparedThemeStore.swift`** (puro, con `FileManager` inyectable): `list()`, `add(packageRoot:manifest:)` (mueve el paquete ya validado a su carpeta), `setPendingInstall(id:Bool)`, `setActivateOnInstall(id:)` (excluyente: solo uno), `remove(id:)`, `markInstalled(id:on:)`. Y `Services/PendingThemeApplier.swift` (`@MainActor`): `applyIfNeeded(device:)` que (1) ignora si `!device.isAura` o `InstallerFlowRegistry.shared.flowActive`; (2) lee `supportedThemeFormat`; (3) por cada pendiente: revalida con `ThemeValidator.validate(packageRoot:firmwareSupportedFormat:)` **contra el iPod real** (nunca contra la validación de cuando se preparó), instala con `ThemeInstaller.install`, y si es el marcado, `activate`; (4) publica un resultado para el banner.

**Cómo se muestra el estado**: `ThemesView` deja de exigir `mountPath` (`ThemesViewModel(mountPath: String?)`) y `ExtrasView` habilita "Temas" siempre; el texto de la fila cambia según haya iPod. La hoja tiene dos secciones:
- **"En esta Mac"** — cada tema preparado con una etiqueta de estado, en español: *"Preparado — esperando dispositivo"* (pendiente), *"Se activará al conectar"* (el marcado, con `checkmark.circle`), *"Instalado en «<nombre del iPod>»"* (ya copiado), *"Requiere una versión más nueva de Aura (formato 2 > 1)"* (incompatible con el iPod conectado, atenuado). Acciones por fila: "Instalar al conectar" (toggle), "Activar al conectar" (radio, uno solo), "Instalar ahora" (solo con iPod compatible), "Cancelar" (quita el pendiente, conserva el paquete), "Eliminar de esta Mac" (confirmación), "Mostrar en Finder".
- **"En el iPod"** — la lista actual (Aura + instalados), solo con dispositivo; sin él, una fila informativa *"Conecta tu iPod para ver los temas instalados."*
- Con pendientes y sin iPod, la fila "Temas" de Extras muestra un contador ("2 preparados") para que no se olvide.

**Varios preparados**: se permite una cola; al conectar se instalan **todos** los marcados "Instalar al conectar" y se activa **solo** el marcado "Activar al conectar" (el último elegido gana; la UI lo dice: *"Solo un tema puede activarse al conectar."*). Si ninguno está marcado para activar, solo se instalan (aparecen en Ajustes → Estilo del iPod).

**Cancelación**: "Cancelar" desmarca el pendiente sin borrar el paquete; "Eliminar de esta Mac" borra la carpeta; si la aplicación automática está en curso, el banner ofrece "Detener" (se completa el tema actual — `ditto` es atómico por paquete — y no se sigue con los demás).

**Firmware incompatible al conectar**: si `theme_format_supported` del iPod < `theme_format` del tema, o si es `nil` (firmware sin soporte de temas), **no se copia nada**; el tema queda pendiente y atenuado con la razón, y el banner dice *"«Apple» necesita una versión más nueva de Aura en tu iPod. Actualiza Aura y vuelve a conectarlo."* con el botón "Ir a General" (donde ya vive "Actualizar Aura", ST-006 — no se dispara ninguna instalación de firmware desde aquí). Con firmware **más nuevo** que el tema (formato menor), se instala normalmente (§F del contrato: carga lo que entienda).

**Aplicación automática al conectar** — se implementa como pide el encargo, con estas salvaguardas: solo escritura no destructiva (crear `.rockbox/aura/themes/<id>/` + editar la línea `theme_id` de `aura.cfg`), nunca durante un sync o una instalación (`flowActive`), banner visible con lo que se hizo y "Deshacer" (elimina el tema recién instalado y restaura `theme_id` anterior), y registro en `PrivilegedOperationLog`-estilo (`temas.json` guarda `lastInstalledOn`). Ver P5 por si el dueño prefiere confirmar con un clic.

**Tests**: `PreparedThemeStoreTests` (alta/baja/estado/exclusividad de "activar"), `PendingThemeApplierTests` contra un "iPod falso" (mismo patrón que `ThemeInstallerTests`): instala pendientes, activa solo uno, rechaza formato mayor sin tocar disco, no hace nada con `flowActive`, y no re-instala lo ya instalado.

---

## 5. §5 — Constructor de temas con selección de tipografías

### 5.1 Veredicto de la dependencia bloqueante — **VIABLE, e implementado**

`PLAN-theme-system.md` no está en ningún disco accesible (solo en el repo archivado `Aura-Proyect`, según `PLAN-themes-impl.md:5` y `docs/aura-design-system/sistema/05-temas.md:3-5` del firmware); su sucesor `PLAN-themes-impl.md` es el que fija el veredicto:

> §1.0 (línea 13): **"✅ VIABLE. Modelo híbrido confirmado: estructura en compilación, apariencia (paleta + fuentes + íconos + fondos) en tiempo de ejecución. Sin recompilar el firmware para instalar o cambiar un tema."**
> Fila "Fuentes" (línea 19): *"Ya se cargan en runtime desde disco por ruta: `font_load(paths[i])` … `font_load()` acepta cualquier `const char*` (`font.c:611` → `font_load_ex` → `open(path)`)."*

Y ya no es plan: D-289 (`Aura-Firmware/DECISIONS.md:62-80`) lo implementó — `aura_style.{c,h}` carga/descarga las 14 fuentes desde `.rockbox/aura/themes/<id>/fonts/<rol>.fnt` (unload-y-reload; incluye el bug arreglado del slot 0 con `font_unload_all()`, `:74`), y del lado Studio ST-003…ST-005 empaquetan/instalan/activan contra ese layout. **Hay a dónde instalar.** Límites que condicionan el diseño: `MAXUSERFONTS = 14` exactamente (`firmware/export/font.h:64`) — un tema sustituye la **cara** de cada rol, nunca agrega roles ni cambia px (`CONTRATO-formato-tema.md` §C); cada `.fnt` va en modo *cached* (`MAX_FONT_SIZE 60000`, `font.c:61-71`), así que el tamaño del archivo no es un límite práctico (los de Aura pesan 233–631 KB).

### 5.2 Roles: vienen de los tokens, no se inventan

Fuente de verdad: `design-system/tokens.json` del firmware — `type_scale` (14 roles con px) y `aura_ds.type_scale_roles` (rol semántico → estilo). Studio ya los tiene hardcodeados en `ThemeFormat.fontRoles` (`Models/AuraTheme.swift:41-47`) y el Release trae `theme-format-v1.json` con `font_roles` (aún no leído en runtime, `:29-36`, ni bundleado: `project.yml:50-58` no lo incluye — Fase 2 lo agrega como recurso junto con `aura-theme-default.zip`, ambos ya en `Vendor/firmware-dist/`).

Los **tres roles del encargo** son una agrupación **sobre** los 14 archivos, y así se documenta y se muestra en la UI (con el detalle desplegable de los 14 para que nada quede oculto):

| Grupo en la UI | Archivos `.fnt` (px · peso del token) | Dónde se ve en el iPod |
|---|---|---|
| **Títulos** | `title` 20·semibold, `header` 13·semibold, `ds_bold_18` 18·bold, `ds_bold_14` 14·bold, `ds_bold_10` 10·bold | títulos de pantalla, panel derecho (arriba), línea activa de letras, contador |
| **Texto** | `body` 13·regular, `caption` 13·regular, `micro` 7·regular, `ds_reg_8` 8·regular, `ds_reg_10` 10·regular, `ds_semibold_15` 15·semibold (filas de menú), `ds_medium_16` 16·medium (panel derecho, abajo) | listas, menús, riel A-Z, panel derecho |
| **Barra de estado** | `ds_bold_12` 12·bold (`statusbar_title`), `ds_reg_12` 12·regular (`statusbar_time`) | barra de estado — **y también** título/álbum/artista/letras de "Ahora suena" (`np_title`/`np_album`/`np_artist`/`lyrics` comparten esos dos archivos, `tokens.json` → `type_scale_roles`, comentario "reusando estilos YA cargados por np_title/np_album") |

⚠️ Hallazgo honesto: con el formato v1 **no se puede** dar a la barra de estado una cara distinta de la de "Ahora suena" — comparten archivo. La UI lo dice bajo ese selector (*"También cambia el texto de Ahora suena."*). Separarlos exige `theme_format` 2 con roles nuevos **y** subir `MAXUSERFONTS` en el firmware (14/14 sin hueco; ~60 KB de RAM por fuente extra en modo *cached*) — es un cambio de contrato: se registra como decisión abierta (P7), no se implementa aquí.

Los **pesos por rol se conservan del token** (regular/medium/semibold/bold): el usuario elige la **familia** de cada grupo y, opcionalmente, un desplazamiento de peso ("más ligero / normal / más pesado") que se aplica a los 14 respetando la jerarquía; Studio resuelve cada peso al más cercano disponible en esa familia vía CoreText (`kCTFontWeightTrait`), y muestra en el detalle qué cara concreta usó cada archivo. Los px **no son editables** (métricas del sistema de diseño, `CONTRATO-formato-tema.md:69`).

### 5.3 Fuentes de la Mac del usuario, y nada más (principio rector)

- El selector lista `CTFontManagerCopyAvailableFontFamilyNames()` (familias instaladas) precedido de **"Fuente del sistema (SF Pro / SF Compact)"** — las caras `.SFNS-*`/`.SFCompact-*` no aparecen en la lista de familias por su nombre con punto inicial, pero son accesibles con `NSFont.systemFont(ofSize:weight:)`/`CTFontCreateUIFontForLanguage`, y son las que el dueño ya quiere (tema Apple).
- Studio **no incluye, descarga ni empaqueta** ninguna fuente: el `.fnt` resultante es un derivado bitmap generado localmente. Un tema con SF Pro/SF Compact (o cualquier familia que el usuario marque como restringida) se marca automáticamente `theme_license: personal` / `theme_redistributable: no`; el toggle existente de licencia restringida (`ThemesView.swift:245-247`) pasa a estar **prellenado y bloqueado en "sí"** cuando la familia elegida es de Apple (`SF*`, `Helvetica Neue`, `New York`… lista corta declarada en código, ampliable), con el aviso actual en español (*"Este tema se construye solo para tu propio iPod: no lo compartas ni lo distribuyas…"*). Para familias libres (Inter, Roboto, etc.) el toggle queda editable, con la advertencia de que la licencia es responsabilidad del usuario. Ninguna opción de "compartir/exportar" se habilita para `redistributable: no` (regla de `CLAUDE.md`).

### 5.4 Pipeline: fuente del sistema → `.fnt` (4-bit, suavizado, hinting por px)

**Formato destino, verificado**: `.fnt` de Rockbox `RB12` (`firmware/export/font.h:73-95`): cabecera de 36 bytes LE (`maxwidth`, `height`, `ascent`, **`depth` 0=1-bit / 1=4-bit**, `firstchar`, `defaultchar`, `size`, `nbits`, `noffset`, `nwidth`), luego bits de glifos, offsets (`uint16` si `nbits < 0xFFDB`, si no `uint32`) y anchos. **El formato admite antialiasing de 16 niveles (4 bpp)** y el firmware lo dibuja con blending real (`lcd_alpha_bitmap_part`, `LCD_DEPTH 16` en el 6G, `font.c:443-447` solo rechaza `depth` en LCD < 16 bits). Las 14 fuentes actuales de Aura **ya son 4-bit** (`a26-*.fnt` traen `depth=1` en la cabecera, verificado en `design-system/out/fonts/`), y `convttf` siempre produce 4-bit (`convttf.c:102,629-631,682` — no existe opción para apagarlo).

**Sobre la restricción ya pagada (umbral de alfa / magenta)**: se verificó su origen — D-010, D-075, D-082, D-111 (`DECISIONS-ARCHIVE.md:88,660,790,1333`) — y **aplica a íconos BMP horneados con clave magenta y `lcd_bitmap_transparent()`, no a fuentes**: las fuentes siempre fueron por otro camino (D-075 lo cita textualmente: *"blending real con alfa parcial … ya usado para fuentes con `pf->depth`"*). Traducido a reglas del pipeline de Studio, que las respeta las dos:
1. **Fuentes**: rasterizar con cobertura real y cuantizar a 16 niveles (4-bit). **Nunca binarizar** (ni umbral 128 ni 1-bit): sería reintroducir la escalera por otra puerta.
2. **Íconos**: el constructor genera o copia **solo máscaras** (`icons/masks/`, R=G=B=cobertura, sin transparencia — inmunes por construcción, `CONTRATO-formato-tema.md:85`); jamás horneados con magenta. Y si un día rasteriza símbolos, a 16× con reducción por filtro de caja y verificación mecánica de ≥ 4 tonos (`MIN_INK_TONES`, `generate.py:473`).

**Rasterizador**: dos caminos posibles; **recomendación: nativo con CoreText**, no `convttf` embebido.

| | `convttf` embebido (propuesta original de `PLAN-themes-impl.md:126`) | **Rasterizador nativo CoreText → `.fnt` (recomendado)** |
|---|---|---|
| Acceso a fuentes del sistema | Necesita la **ruta al archivo** (`kCTFontURLAttribute`). `SFNS.ttf`/`SFCompact.ttf` son **fuentes variables** (7.9 MB, todos los pesos en un archivo): FreeType las abre, pero `convttf` no selecciona instancias nombradas → solo el peso por defecto (Regular). Para Semibold habría que exigir los OTF estáticos de Apple instalados aparte. `.ttc` (colecciones): sin flag de índice de cara en `convttf`. | Renderiza con `CTFont` directamente (`CTFontCreateWithFontDescriptor` + trait de peso, o `NSFont.systemFont(ofSize:weight:)`); no toca archivos, no importa si es variable, `.ttc` u OTF. |
| Licencias / empaquetado | GPL v2 (oferta de fuente como `mks5lboot`) + `libfreetype` (FreeType License) + `install_name_tool` de sus dylibs — el mismo trabajo que D-038 descartó para ffmpeg. | Solo Foundation/CoreText/CoreGraphics. Nada que redistribuir. |
| Fidelidad con las fuentes actuales de Aura | Idéntica (mismo motor). | Distinto motor de hinting; se compara **mecánicamente** en tests contra las cabeceras/anchos de las 14 fuentes de `aura-theme-default.zip` (Inter, que sí está instalable) — tolerancia de ±1 px en `height`/`ascent`/anchos. Se acepta una diferencia sub-pixel de suavizado, no de métrica. |
| Detalles a implementar | Solo la invocación. | Escritor `RB12` (~150 líneas): por rol, `CTFontGetBoundingRectsForGlyphs`/`CTFontGetAdvancesForGlyphs` redondeados; render de cada glifo en un `CGContext` gris de 8 bits **sin subpíxel** (`setShouldSmoothFonts(false)`, `setAllowsFontSubpixelPositioning(false)`, `setShouldSubpixelQuantizeFonts(true)`, `setShouldAntialias(true)`), cuantización a 16 niveles, empaquetado 2 px/byte con filas alineadas a 16 bits; rango contiguo `firstchar…` (las fuentes de Aura cubren U+0020–U+FFFD según AUDITORIA-01 A-02): los códigos sin glifo en la familia apuntan al `defaultchar` (mismo truco que `convttf`, por eso 233–631 KB y no MB). |

Ambos producen exactamente lo que el firmware ya carga; el nativo elimina las dos fragilidades reales (fuente variable del sistema y GPL embebida). Ver P6.

### 5.5 Máscaras e íconos: de dónde salen en el constructor v1

Un paquete válido exige 801 máscaras (§G) y el rasterizador de símbolos (2B-íconos) no existe. Sin inventar alcance: el constructor **v1 con tipografías** toma las máscaras de una de tres fuentes, a elección en el formulario: (a) **el tema por defecto** del Release (`aura-theme-default.zip`, licencia libre, ya en `Vendor/firmware-dist/`; se bundlea) — opción por defecto, sin nada que rasterizar; (b) un tema ya preparado/instalado (p. ej. las máscaras SF de `~/Aura-local/theme-apple-source/design-system-out/`, como hoy); (c) una carpeta con `icons/masks/` (el flujo actual, que **no desaparece**: queda como "Avanzado — usar una carpeta de assets ya generados"). El rasterizador de SF Symbols → máscaras queda como unidad de trabajo posterior, documentada, no a medias.

### 5.6 UI del constructor (`BuildThemeView` rediseñada)

1. **Nombre** y **Autor** (como hoy).
2. **Tipografías** — tres filas: *Títulos*, *Texto*, *Barra de estado*, cada una con un `Picker` de familia (primero "Fuente del sistema (SF Pro)", luego las familias instaladas, con búsqueda), un `Picker` de ajuste de peso (Normal / Más ligero / Más pesado) y una muestra viva ("Aura · Ahora suena · 12:34") dibujada con la `NSFont` real a los px del contrato. Botón "Usar la misma familia para todo" (lo que `PLAN-themes-impl.md:126` sugiere como default). Debajo, desplegable "Detalle de los 14 archivos" (rol · px · cara resuelta).
3. **Íconos** — origen de las máscaras (§5.5), por defecto "Tema Aura (libre)".
4. **Licencia** — el toggle actual, prellenado según la familia; aviso completo en español.
5. **Vista previa** (§5.7) y botones "Compilar y preparar" (guarda en la cola de §4b) / "Compilar e instalar" (solo con iPod). Progreso por rol ("Rasterizando ds_bold_12…") en la barra sólida (`StudioStyle`, sin `Material`).
Compilar = rasterizar 14 `.fnt` → copiar máscaras → `theme.cfg` (paleta heredada del default salvo que el usuario la edite — la paleta no está en este encargo) → `ThemeValidator.validate` **antes** de guardar/instalar (regla de `CLAUDE.md`), ahora **sí** con la cabecera `RB12` verificada (`ThemeValidator.swift:61-71` lo dejaba para cuando existiera el rasterizador: existe).

### 5.7 Vista previa antes de compilar — viable, en dos niveles

- **Nivel 1 (antes de compilar, instantáneo)**: mock 320×240 en SwiftUI con los tokens reales de `AuraColors` (claro/oscuro): barra de estado (título 12 bold · hora 12 regular), una lista de menú (`ds_semibold_15`, pastilla `SELECTION_FILL`, fila activa en acento — Principio 2), y el bloque de "Ahora suena" (título/álbum/artista) — dibujado con las `NSFont` elegidas a los px del contrato. Honesto: se rotula *"Aproximación: la Mac suaviza el texto distinto que el iPod."* No hay nada reutilizable del firmware para esto (no existe `preview.py` ni mock alguno; `apple2026_sim_shot.sh` exige el simulador compilado) — es UI nueva; se apoya en el precedente de composición de `PlaylistArtGenerator` y en los tokens ya generados.
- **Nivel 2 (después de compilar, pixel-exacto)**: Studio ya tiene en memoria los bitmaps de 4 bits de cada `.fnt` que acaba de escribir — renderiza la misma tira con **esos** glifos (escala 2×, `interpolation: .none`). Eso sí es lo que verá el iPod. Costo bajo (el escritor `RB12` ya tiene la matriz de cobertura).
La decisión del firmware de no tener vista previa (`PLAN-themes-impl.md:69`) está razonada para el aparato (14/14 fuentes); en la Mac no aplica.

**Tests**: escritor `RB12` (cabecera, `glyph_bytes` par, offsets 16/32 bits, `defaultchar`), rasterización de "Ñandú 12:34" en 4-bit con ≥ 4 tonos por glifo no vacío (misma filosofía que `MIN_INK_TONES`), comparación de métricas contra las 14 fuentes del tema por defecto (Inter instalada en el runner o `XCTSkip`), mapeo grupo→14 roles, y validación completa del paquete construido con `ThemeValidator`.

---

## 6. Preguntas abiertas (con recomendación razonada)

| # | Pregunta | Recomendación |
|---|---|---|
| **P1** | §2: ¿ofrecer la relectura de etiquetas de la biblioteca existente como banner de una sola vez, o solo como acción del menú? | **Banner una vez + acción en menú.** Es la biblioteca real del dueño la que hoy tiene mojibake/álbumes vacíos; sin un empujón visible, el bug "sigue" para él aunque esté arreglado. No se relee sola: reescribe `.preparados/` y puede tardar (portadas). |
| **P2** | §2: al releer, ¿la metadata **local** debe pisar correcciones hechas a mano en Studio? | **No por defecto**: el banner relee solo ítems que **nunca** fueron editados a mano (marcar `metadataEditedByUser` al guardar desde `MediaInfoView`/lote/renombrar — hoy no existe esa marca; se agrega). La acción del menú, en cambio, sí pisa (es explícita), con confirmación si hay ediciones. |
| **P3** | §1: ¿aplanar también la barra lateral nativa de la ventana (`ContentView.swift:289`)? | **No.** Es la capa de navegación del sistema (Principio 6 lo permite ahí) y todas las apps de macOS la tienen así; lo que se veía mal era ese material **dentro del detalle** (Listas). Aplanar la barra lateral la haría ajena a macOS sin ganar coherencia con el iPod. |
| **P4** | §1: ¿agrupar "Por artista" por `albumArtist ?? artist` (carpetas del iPod) o por `artist` de cada pista (como el tagcache "Artistas" del firmware)? | **`albumArtist ?? artist`**, y en la ficha del artista listar también las canciones donde aparece solo como `artist` (sección "Aparece en"). Coincide con las carpetas que el usuario ve en el iPod y evita partir recopilaciones en 20 artistas. |
| **P5** | §4b: ¿aplicar el tema pendiente **automáticamente** al conectar (como pide el encargo) o pedir un clic de confirmación? | **Automático, con banner y "Deshacer"** (como se pide): la escritura es aditiva y reversible (carpeta nueva + una línea de `aura.cfg`), muy distinta de flashear firmware, y nunca corre durante sync/instalación. Si el dueño prefiere confirmar, es un `if` y un botón — se implementa igual salvo indicación. |
| **P6** | §5: ¿rasterizador nativo CoreText (recomendado) o `convttf` embebido? | **Nativo.** Resuelve la fuente variable del sistema (`SFNS.ttf` — con `convttf` solo saldría el peso Regular), `.ttc`, y evita empaquetar GPL + FreeType (mismo criterio que D-038 con ffmpeg). Se paga con un escritor `RB12` de ~150 líneas verificado por tests contra las fuentes reales del tema por defecto. |
| **P7** | §5: la barra de estado comparte `ds_bold_12`/`ds_reg_12` con "Ahora suena". ¿Aceptar la limitación en v1 (con aviso en la UI) o proponer `theme_format: 2` con roles `statusbar_title`/`statusbar_time` propios? | **Aceptar en v1 y anotar la propuesta como decisión abierta hacia el firmware** (D-NNN futura): exige subir `MAXUSERFONTS` a 16 y el formato a v2 en ambos repos a la vez (`CONTRATO-formato-tema.md` §F). No bloquea nada del encargo. |
| **P8** | §3/§4: nombres de las 4 categorías de video. Studio "Series" vs. menú del firmware "Programas de TV"; "Videoclips" del firmware significa hoy "sin clasificar". | Contrato con ids en inglés (`clip/home/series/movie`) y rótulos en español propuestos: **Videoclips · Videos caseros · Series · Películas**; se pide al firmware unificar "Programas de TV" → "Series" (su "Acerca de" ya dice "Series"). El cambio de significado de `video_clips_count` es exactamente por lo que sube `contract_version`. |
| **P9** | §3/§4: ¿mantener "Fondos de pantalla" y "Creadas con IA" como categorías de foto sabiendo que la detección es baja/nula? | **Sí, como categorías manuales con detección oportunista** (C2PA / chunks PNG de Stable Diffusion sí son señales reales; proporción de pantalla es débil). Lo importante es que la UI diga la verdad: chip "Revisar" y texto en Ajustes. El firmware las descartó en D-283 solo porque no había fuente; ahora la habría (con `photo_wallpapers_count` nueva). |
| **P10** | §3/§4: `media_index.cfg` — ¿un archivo (video + foto) o dos (`video_index.cfg`, `photo_index.cfg`)? | **Uno**, con rutas absolutas como clave (`/Videos/…`, `/Photos/…`): un solo lector en el firmware, y el prefijo ya distingue el tipo. |
| **P11** | Alcance de la Fase 2: ¿todo junto o por tandas? | **Cuatro tandas, en este orden, cada una con `swift build`/`swift test` limpios y su ST-NNN**: (1) §2 lector local + relectura + tests; (2) §1 agrupación + vistas + `StudioStyle` + Listas plana; (3) §3/§4 confianza + heurísticas + `CONTRATO-indice-medios.md` + `media_index.cfg`; (4) §4b cola de temas y §5 constructor (rasterizador nativo + preview). Los contratos (3) se redactan y se marcan como **abiertos** hasta que el firmware los adopte; Studio puede empezar a escribirlos porque el firmware los ignora sin daño. |

---

## 7. Fase 2 (solo tras aprobación) — resumen de ejecución

- **Verificación**: `swift build` y `swift test` limpios tras cada cambio; la falla conocida de `LiveEnrichmentIntegrationTests` (red real) no cuenta como regresión; ninguna regresión nueva. `xcodegen generate` + `xcodebuild … build` al final de cada tanda si hay archivos nuevos (el `.xcodeproj` se regenera, nunca se edita a mano).
- **Tests obligatorios**: lectura de metadatos (fixtures v2.4-UTF-8, v2.3, portada v2.4, v2.2 y BOM BE a mano, FLAC, M4A, AIFF; `enrich(online:false)` con álbum para FLAC/M4A); agrupación por álbum/artista con vacíos, homónimos, normalización y orden de "Sin álbum"/"Artista desconocido"; heurísticas de clasificación (patrones de serie, umbral 65 min con borde, señales de cámara, C2PA/PNG, proporciones) con su confianza; escritor/lector de `sync_summary.cfg` v2 y `media_index.cfg`; cola de temas y aplicador; escritor `RB12` y validador con cabecera.
- **Textos de UI** en español de México, sin voseo (Principio 7 del sistema de diseño: "Español impecable"), con acentos correctos ("Álbum", "Sin álbum", "Fotografías", "Creadas con IA").
- **Documentos**: `CONTRATO-indice-medios.md` nuevo (versionado, consumible desde el repo del firmware sin rutas de Studio; copia idéntica en ambos repos, canónica en el firmware); `CONTRATO-firmware-studio.md` §D actualizado (enumera claves, referencia el índice, `contract_version`); `README.md`/`CLAUDE.md` en lo que toque (regla nueva: "el lector de tags locales es `LocalTagReader`; `ID3Writer.readTag` es solo de verificación").
- **Decisiones**: `DECISIONS.md` con `ST-007+` (una por tanda, más una por contrato abierto), referencias cruzadas `D-NNN` al firmware donde aplique (D-037, D-062, D-072, D-203, D-228, D-283, D-289).
- **Commits atómicos, sin push**: uno por unidad lógica (modelo/servicio, vista, tests, docs), regenerando el `.xcodeproj` en su propio commit cuando cambie el conjunto de archivos.

---

## BARRERA

**Aquí se detiene la Fase 1.** No se ha modificado ningún archivo de código ni de tests; este documento es el único cambio en el árbol de trabajo (sin commit). La Fase 2 arranca únicamente con la aprobación explícita del dueño sobre este plan y sus recomendaciones (P1–P11), o con las correcciones que indique.
