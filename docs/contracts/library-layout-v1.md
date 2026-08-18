# Contrato de estructura de biblioteca en el iPod — v1

**Versión 1.1 — 2026-08-18 (D-293/D-298 en `Aura-Firmware`, ST-012 en Aura Studio).** Copia idéntica en ambos repositorios: `Aura-Firmware/docs/contracts/library-layout-v1.md` es la fuente canónica; Aura Studio la copia a `docs/contracts/library-layout-v1.md`. Todo cambio futuro sube la versión de este documento **y**, solo cuando cambia el esquema del marcador en sí, el campo `version` de §4 (v1.1 no lo toca — ver §6) — misma convención que `CONTRATO-firmware-studio.md` (que lo referencia desde su §D).

Consolida en un solo lugar lo que antes estaba repartido entre código de los dos lados: **dónde** deja Aura Studio cada cosa en el disco del iPod y **cómo** la encuentra el firmware. Lo que no está aquí (categorías, nombre del dispositivo, formato de imágenes) vive en sus propios contratos y aquí solo se referencia (§5).

---

## 1 — Estructura de directorios en el dispositivo

Rutas absolutas desde la raíz del volumen FAT32 del iPod. Studio crea `Music/`, `Videos/`, `Photos/` y `Playlists/` al instalar; el firmware también los crea en cada arranque si faltan (`aura_main_ensure_media_dirs()`), así que ninguno de los dos depende del otro para que existan.

| Directorio | Contenido | Escribe | Lee |
|---|---|---|---|
| `/Music/` | Audio. **Tres layouts** posibles, elegidos por el usuario en Studio (`AppPreferences.MusicOrganization`): `Artista/Álbum/archivo` (por defecto), `Álbum/archivo`, `Artista/archivo`. Nombre del archivo según `MusicFilenameFormat` (`Título`, `NN Título`, `Título - Artista`, `Título - Álbum`). Artista/álbum desconocidos → carpeta `Desconocido`. Saneo FAT32 (`PathSanitizer`): `/ \ : * ? " < > \|` → `_`, sin `.`/espacio finales | Studio | Firmware (tagcache indexa **todo el disco**, `tagcache_scan_paths = "/"`; no depende del layout) |
| `/Videos/` | **Plano**, sin subcarpetas: `<archivo>.mpg`/`.mpeg` (MPEG-2, `mpegplayer`). Póster opcional `<archivo>.jpg` hermano (mismo nombre base). Nombre de archivo **≤ 95 bytes UTF-8 incluyendo la extensión** (D-298: `VIDEO_NAME_LEN` del firmware es 96 con el NUL) | Studio | Firmware (`aura_video.c`, `opendir("/Videos")`, filtro por extensión) |
| `/Photos/` | **Plano**, un JPEG por foto — formato exacto en `CONTRATO-firmware-studio.md` §D.1 (referencia, §5) | Studio | Firmware (`aura_photos.c`); miniaturas en `/.rockbox/aura/photocache/` (solo firmware) |
| `/Playlists/` | `<Nombre>.m3u8` (rutas absolutas del iPod, UTF-8) + portada opcional `<Nombre>.jpg` | Studio (y el firmware al crear listas en el aparato) | Firmware (`aura_music.c`, `catalog_get_directory()`) |
| `/.rockbox/aura/themes/<id>/` | Paquetes de tema — `CONTRATO-formato-tema.md` (referencia, §5) | Studio | Firmware |
| `/.rockbox/aura/*.cfg`, `sync_manifest.json` | Ajustes y estado — `CONTRATO-firmware-studio.md` §D (referencia, §5) | ambos, según clave | ambos |
| `/.aura/` | **Solo el marcador de §4.** Directorio nuevo en la raíz, separado de `/.rockbox/aura/` (ajustes/caches propios de Aura) a propósito: es "correo" de Studio hacia el firmware, no estado del aparato | Studio (y el firmware, ver §4) | Firmware |

Regla: **ningún archivo de Studio fuera de estas rutas.** Un archivo que aparezca fuera de ellas (o dentro sin estar en `sync_manifest.json`) es "Solo en el iPod" para Studio y nunca se borra solo.

## 2 — Colocación de carátulas

Studio guarda las carátulas **en su biblioteca**, como asset asociado a la canción/álbum (`<biblioteca>/.portadas/<id>.jpg`, referenciado desde `biblioteca.json`) — nunca como entrada del módulo de Imágenes (ver ST-012 / `PLAN`: la contaminación de Imágenes con `cover.jpg` era un bug del importador). En el dispositivo van **donde el firmware las busca hoy**, sin cambio:

| Política de Studio (`AppPreferences.coverArtPolicy`) | Qué escribe en el iPod | Cómo la encuentra el firmware |
|---|---|---|
| `albumOnly` (por defecto) | Un solo `cover.jpg` en la carpeta del álbum (`LibrarySync.writeAlbumCovers`) | `find_albumart()` (`apps/recorder/albumart.c`, orden real): `./<pista>.{jpeg,jpg,bmp}`, `./<álbum>.*`, **`./cover.*`**, `./folder.jpg`, `/.rockbox/albumart/<artista>-<álbum>.*`, y una segunda pasada en `../`. Cover Flow y Ahora Suena usan esta misma búsqueda; el resultado se cachea en `/.rockbox/aura/cfcache/` |
| `perTrack` | Carátula **embebida** en el archivo de audio (frame `APIC` en MP3, `ID3Writer`) — sin archivos sueltos | Fallback de `aura_albumart.c`/`aura_nowplaying.c`: `get_metadata()` → `has_embedded_albumart` **solo JPEG** (`AA_TYPE_JPG`); una carátula embebida PNG cae al tile por defecto |

Criterio de aceptación permanente: **Cover Flow debe seguir encontrando portadas** después de cualquier cambio en cualquiera de los dos lados. Nota del firmware (D-293): `cfcache/` se indexa por `album_seek` de tagcache, que cambia con cada reconstrucción de la base — el firmware la vacía él mismo al terminar una reconstrucción; Studio no toca ese directorio.

## 3 — Letras (`.lrc`)

| Regla | Detalle |
|---|---|
| Ruta | **Junto al archivo de audio, mismo nombre base**, extensión `.lrc`: `/Music/A/B/01 Canción.mp3` → `/Music/A/B/01 Canción.lrc`. Es la **única** ruta que el firmware intenta (`aura_nowplaying.c`, `derive_sibling_path()`): no busca en `/Lyrics/`, ni por tags, ni `.txt` |
| Codificación | UTF-8, sin BOM. Saltos `\n` (se tolera `\r\n`) |
| Contenido | Formato LRC estándar: líneas `[mm:ss.xx]texto`. Varias marcas por línea permitidas. Tamaño leído por el firmware: **8 KB** (`LRC_FILE_BUF_SIZE`); más allá se trunca. Máximo 600 líneas / 128 bytes por línea (`aura_lrc.h`) |
| Sin marcas de tiempo | El parser del firmware (`aura_lrc.c`) **descarta** las líneas sin `[mm:ss]` (también las de metadatos `[ar:]`, `[ti:]`). Un `.lrc` de letra plana (sin ninguna marca) equivale a no tener letra: el Modo 4 (Letras) queda con el ícono al 50 % y se salta. Studio escribe la letra plana igualmente (contrato del encargo: el firmware define ese comportamiento y puede evolucionar sin tocar a Studio) |
| Sin letra en Studio | **No se escribe archivo** |
| Borrado / reemplazo | Al borrar o reemplazar una canción, su `.lrc` se borra o reemplaza con ella — nunca huérfanos. Studio registra el `.lrc` como archivo propio (`DeviceSyncIndexBuilder.ownedDevicePaths`) para que no aparezca como "Solo en el iPod" |
| Base de datos | Las letras **no** pasan por tagcache: se leen del archivo al reproducir. El marcador de §4 no las indexa |

## 4 — Marcador de sincronización pendiente (`/.aura/sync-pending.json`)

El firmware no corre mientras el iPod está montado por USB, así que Studio no puede invocarlo — solo dejar un archivo. Studio lo escribe **al terminar cada sincronización que tocó archivos**; el firmware lo revisa **al arrancar** y **al volver de la pantalla USB** (los dos únicos momentos en que recupera el disco), reconstruye los índices de las secciones marcadas y lo borra solo al terminar bien.

### 4.1 — Esquema (v1)

```json
{
  "version": 1,
  "timestamp": "2026-08-17T20:15:00Z",
  "changes": { "music": true, "video": false, "images": true },
  "attempts": 0
}
```

| Clave | Quién la escribe | Regla |
|---|---|---|
| `version` | Studio | **Obligatoria.** Entero. Esta versión: `1`. El firmware ignora un marcador de versión **mayor** a la que conoce (no reconstruye nada con reglas que no entiende) y lo dice en pantalla; el marcador se queda hasta que un firmware más nuevo lo procese |
| `timestamp` | Studio | ISO-8601. Informativo (para diagnóstico); el firmware no lo interpreta |
| `changes.music` / `.video` / `.images` | Studio | `true` solo en las secciones donde **esta** sincronización agregó, reemplazó o borró archivos. Reconstrucción **incremental por sección** (solo las `true`); dentro de una sección, pasada completa |
| `attempts` | **Firmware** | Contador de intentos consecutivos. Studio escribe `0` (o lo omite). El firmware lo sube a `n+1` **antes** de empezar (así un corte de batería a mitad ya lo deja subido) y borra el archivo al terminar bien. Al llegar a `3` deja de reintentar solo, muestra el error en español y ofrece el disparo manual (Ajustes → Reconstruir biblioteca), que escribe un marcador nuevo con las tres secciones y `attempts: 0` |

Parser del firmware (`aura_sync_marker.c`, puro C99, testeado en host): busca cada clave conocida por nombre e **ignora todo lo demás** — una clave nueva de un Studio futuro no rompe un firmware viejo (mismo criterio que `aura.cfg`). Un marcador ilegible (no es un objeto JSON, o sin `version` numérica) se borra sin actuar. Un marcador legible **sin ninguna sección en `true`** también se borra sin actuar.

### 4.2 — Qué hace el firmware con cada sección

| Sección | Trabajo |
|---|---|
| `music` | tagcache. Con base usable y sin un temporal huérfano: **actualización completa** (`Q_UPDATE`: recorre todo el árbol, re-lee los archivos cuyo `mtime` cambió, agrega los nuevos, elimina los que ya no existen) — la base vieja sigue usable mientras tanto. Sin base (o temporal huérfano de una pasada abortada, o desde el disparo manual): **reconstrucción desde cero** (`Q_REBUILD`). Al terminar bien vacía `/.rockbox/aura/cfcache/` (§2) y vuelve a importar `ratings.cfg` |
| `video` | Invalida el listado de `/Videos/` (se relee al entrar) |
| `images` | Invalida el listado de `/Photos/` (se relee al entrar). Las miniaturas se renuevan solas: su caché se lleva por `mtime` del original |

**Nota sobre `mtime`**: tagcache decide "archivo ya indexado, sin cambios" comparando el `mtime` guardado con el del disco. Studio **no** preserva fechas al copiar (`copyFileTransactionally` crea el destino nuevo, streaming), así que todo archivo que Studio escribió o reemplazó tiene `mtime` nuevo y se re-lee. Si en el futuro Studio preservara fechas, tendría que marcar la sección para reconstrucción completa o el firmware forzar re-lectura de tags — esta es la única premisa del contrato que depende de cómo copia Studio.

### 4.3 — UX en el firmware

Pantalla completa "Actualizando biblioteca…" (StatusBar + una fila por sección con su estado + barra de progreso de Música + conteo). **No cancelable** (una base a medias es peor que esperar), **posponible**: Menú cierra la pantalla, el marcador queda intacto y el trabajo ya encolado se cierra en fondo (si tagcache lo aborta, el temporal a medias se descarta y el intento no cuenta; el próximo arranque lo retoma). Si tagcache pospone el guardado del índice "hasta el próximo arranque" (sin buffer temporal suficiente), la pantalla lo dice tal cual y el intento tampoco cuenta.

### 4.4 — Capacidad anunciada en `aura.cfg` (para que ninguna combinación de versiones rompa)

El firmware escribe en `/.rockbox/aura/aura.cfg` la clave **de solo escritura** `sync_marker_supported: 1` (la versión de esquema que entiende — misma convención que `theme_format_supported`). Studio la lee al sincronizar:

| Firmware | Studio | Resultado |
|---|---|---|
| Sin la clave (anterior a D-293) | Nuevo | Studio conserva su mecanismo previo: **borra `database_*.tcd`** al terminar el sync (`triggerFirmwareDBRebuild`) para forzar la reconstrucción al arrancar — comportamiento de siempre. Escribe el marcador igualmente (inofensivo: nadie lo lee) |
| Con la clave | Nuevo | Studio **no borra** la base: solo escribe el marcador. Así, si el usuario pospone, sigue teniendo su música vieja mientras tanto |
| Con la clave | Viejo (sin marcador) | Studio viejo borra la base como siempre → el firmware reconstruye al arrancar (su camino de "sin base"), sin marcador ni pantalla nueva — comportamiento actual |

**Orden de despliegue** (decisión cerrada): primero el firmware (tolera que el marcador no exista), después Studio.

## 5 — Contratos referenciados (no se definen aquí)

| Tema | Dónde vive |
|---|---|
| Índice de categorías / conteos para "Acerca de" (`sync_summary.cfg`), `ratings.cfg`, `sync_manifest.json`, `aura.cfg` (claves) | `CONTRATO-firmware-studio.md` §D |
| Nombre del dispositivo (`device.cfg`) | `CONTRATO-dispositivo.md` |
| Formato de imágenes de `/Photos/` (JPEG baseline, ≤ 640 px, nombres) | `CONTRATO-firmware-studio.md` §D.1 |
| Formato del paquete de tema | `CONTRATO-formato-tema.md` |
| Artefactos del Release, GPL, paleta | `CONTRATO-firmware-studio.md` §A–§C |

## 6 — Historial

- **v1.1 (2026-08-18, D-298)** — §1, fila `/Videos/`: se documenta el límite de nombre de archivo (≤ 95 bytes UTF-8 con extensión), que ya regía de facto por `PHOTO_NAME_LEN` en Fotos pero no estaba escrito para Videos (`VIDEO_NAME_LEN` era 64, truncaba nombres largos en silencio). No cambia el esquema del marcador de §4: el campo `version` se queda en `1` — esto es una aclaración de un límite ya existente en la práctica, no un cambio de formato del marcador.
- **v1 (2026-08-17)** — Primera versión: estructura de directorios, colocación de carátulas y letras, marcador de sincronización (`/.aura/sync-pending.json`, `version: 1`, `sync_marker_supported: 1`).
