# Contrato de estructura de biblioteca en el iPod — v1

**Versión 1.5 — 2026-09-04 (D-349 en `Aura-Firmware`, contrato v18 del firmware; recoge ST-142 de Aura Studio).** Copia idéntica en ambos repositorios: `Aura-Firmware/docs/contracts/library-layout-v1.md` es la fuente canónica; Aura Studio la copia a `docs/contracts/library-layout-v1.md`. Todo cambio futuro sube la versión de este documento **y**, solo cuando cambia el esquema del marcador en sí, el campo `version` de §4 (v1.1 no lo toca — ver §6) — misma convención que `CONTRATO-firmware-studio.md` (que lo referencia desde su §D).

Consolida en un solo lugar lo que antes estaba repartido entre código de los dos lados: **dónde** deja Aura Studio cada cosa en el disco del iPod y **cómo** la encuentra el firmware. Lo que no está aquí (categorías, nombre del dispositivo, formato de imágenes) vive en sus propios contratos y aquí solo se referencia (§5).

---

## 1 — Estructura de directorios en el dispositivo

Rutas absolutas desde la raíz del volumen FAT32 del iPod. Studio crea `Music/`, `Videos/`, `Photos/` y `Playlists/` al instalar; el firmware también los crea en cada arranque si faltan (`aura_main_ensure_media_dirs()`), así que ninguno de los dos depende del otro para que existan.

| Directorio | Contenido | Escribe | Lee |
|---|---|---|---|
| `/Music/` | Audio. **Tres layouts** posibles, elegidos por el usuario en Studio (`AppPreferences.MusicOrganization`): `Artista/Álbum/archivo` (por defecto), `Álbum/archivo`, `Artista/archivo`. Nombre del archivo según `MusicFilenameFormat` (`Título`, `NN Título`, `Título - Artista`, `Título - Álbum`). Artista/álbum desconocidos → carpeta `Desconocido`. Saneo FAT32 (`PathSanitizer`): `/ \ : * ? " < > \|` → `_`, sin `.`/espacio finales | Studio | Firmware (tagcache indexa **todo el disco**, `tagcache_scan_paths = "/"`; no depende del layout) |
| `/Videos/` | **Plano**, sin subcarpetas: `<archivo>.mpg`/`.mpeg` (MPEG-2, `mpegplayer`). Póster opcional `<archivo>.jpg` hermano (mismo nombre base) — **D-316: el firmware ahora sí lo lee**, como cartel de `CoverDrift` para Películas/Series. Nombre de archivo **≤ 95 bytes UTF-8 incluyendo la extensión** (D-298: `VIDEO_NAME_LEN` del firmware es 96 con el NUL). **D-318 — póster de TEMPORADA** (Movie Flow, sección de Video): `<Nombre del programa> S0N.jpg` (mismo patrón `SxxEyy` de dos dígitos que ya identifica episodios, sin `ExY`) — un archivo separado por temporada, no ligado a un episodio en particular; opcional (sin él, Movie Flow usa un color de relleno, igual que un episodio sin póster hoy) | Studio | Firmware (`aura_video.c`, `opendir("/Videos")`, filtro por extensión; `aura_screens.c` para el póster de película; `aura_movieflow.c` para el póster de temporada) |
| `/Photos/` | **Plano**, un JPEG por foto — formato exacto en `CONTRATO-firmware-studio.md` §D.1 (referencia, §5) | Studio | Firmware (`aura_photos.c`); miniaturas en `/.rockbox/aura/photocache/` (solo firmware) |
| `/Playlists/` | `<Nombre>.m3u8` (rutas absolutas del iPod, UTF-8) + portada opcional `<Nombre>.jpg` | Studio (y el firmware al crear listas en el aparato) | Firmware (`aura_music.c`, `catalog_get_directory()`) |
| `/.rockbox/aura/themes/<id>/` | Paquetes de tema — `CONTRATO-formato-tema.md` (referencia, §5) | Studio | Firmware |
| `/.rockbox/aura/*.cfg`, `sync_manifest.json` | Ajustes y estado — `CONTRATO-firmware-studio.md` §D (referencia, §5) | ambos, según clave | ambos |
| `/.aura/` | **Solo el marcador de §4.** Directorio nuevo en la raíz, separado de `/.rockbox/aura/` (ajustes/caches propios de Aura) a propósito: es "correo" de Studio hacia el firmware, no estado del aparato | Studio (y el firmware, ver §4) | Firmware |

Regla: **ningún archivo de Studio fuera de estas rutas.** Un archivo que aparezca fuera de ellas (o dentro sin estar en `sync_manifest.json`) es "Solo en el iPod" para Studio y nunca se borra solo.

**D-318 — agrupamiento de episodios por temporada.** Movie Flow (sección Video) agrupa los archivos de la categoría `series` (`video_categories.cfg`, §5) por temporada leyendo el patrón `SxxEyy` (dos dígitos cada uno, sin distinguir mayúsculas) del nombre visible del archivo — mismo patrón que Aura Studio ya usa internamente para ordenar series (ST-033). Ejemplo: `Mi Serie S01E02.mpg` → temporada 1, episodio 2; todo lo anterior al patrón (`Mi Serie`) es el nombre del programa. Un archivo de la categoría `series` **sin** ese patrón no se descarta: se vuelve su propia "temporada" de un solo episodio (título = nombre completo del archivo). No es un requisito para Studio — es lectura pura del firmware sobre nombres que Studio ya produce hoy.

## 2 — Colocación de carátulas

Studio guarda las carátulas **en su biblioteca**, como asset asociado a la canción/álbum (`<biblioteca>/.portadas/<id>.jpg`, referenciado desde `biblioteca.json`) — nunca como entrada del módulo de Imágenes (ver ST-012 / `PLAN`: la contaminación de Imágenes con `cover.jpg` era un bug del importador). En el dispositivo van **donde el firmware las busca hoy**, sin cambio:

| Política de Studio (`AppPreferences.coverArtPolicy`) | Qué escribe en el iPod | Cómo la encuentra el firmware |
|---|---|---|
| `albumOnly` (por defecto) | Un solo `cover.jpg` en la carpeta del álbum (`LibrarySync.writeAlbumCovers`) | `find_albumart()` (`apps/recorder/albumart.c`, orden real): `./<pista>.{jpeg,jpg,bmp}`, `./<álbum>.*`, **`./cover.*`**, `./folder.jpg`, `/.rockbox/albumart/<artista>-<álbum>.*`, y una segunda pasada en `../`. Music Flow y Ahora Suena usan esta misma búsqueda; el resultado se cachea en `/.rockbox/aura/cfcache/` |
| `perTrack` | Carátula **embebida** en el archivo de audio (frame `APIC` en MP3, `ID3Writer`) — sin archivos sueltos | Fallback de `aura_albumart.c`/`aura_nowplaying.c`: `get_metadata()` → `has_embedded_albumart` **solo JPEG** (`AA_TYPE_JPG`); una carátula embebida PNG cae al tile por defecto |

**v1.5: `cover.jpg` y la carátula embebida (`perTrack`) son JPEG baseline cuadradas de 320×320 px**, sRGB, sin ICC, sin progresivo, calidad 0.85 (mismas reglas de formato que §D.1 del contrato). Studio recorta al centro desde su copia local cuadrada (`.portadas/`). El firmware **no** exige el cuadrado — lo tolera con fill-crop (§D.5) — pero cualquier otra proporción se considera error de Studio.

Criterio de aceptación permanente: **Music Flow debe seguir encontrando portadas** después de cualquier cambio en cualquiera de los dos lados. Nota del firmware, actualizada en D-338/D-341 (reemplaza la de D-293, que ya no aplica): `cfcache/` se indexa por `crc32(ruta de la pista representativa) + mtime` — clave **estable**, no por `album_seek` de tagcache (eso cambiaba con cada reconstrucción y obligaba a vaciar el directorio entero). El firmware ya no lo vacía: al terminar una reconstrucción conserva las entradas de álbum (`a-*.pfraw`/`a-*.none`) y solo tira las de artista/playlist (`ar-*`, `pl-*`, que sí dependen de un sync reciente); las huérfanas de álbum (fuente borrada, o pista reescrita con `mtime` nuevo) se recogen con un recolector con presupuesto, no con un vaciado completo. **Desde v16 del contrato del firmware** (`CONTRATO-firmware-studio.md` §D.5), el decode real es compartido entre las tres familias: `cfcache/` (y el equivalente de Metro-Aura/moonlit.aura) es una caché privada de segundo nivel derivada de la maestra en `/.aura/art/albums/` — Studio no toca ninguno de los dos directorios.

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
| `music` | tagcache. Con base usable y sin un temporal huérfano: **actualización completa** (`Q_UPDATE`: recorre todo el árbol, re-lee los archivos cuyo `mtime` cambió, agrega los nuevos, elimina los que ya no existen) — la base vieja sigue usable mientras tanto. Sin base (o temporal huérfano de una pasada abortada, o desde el disparo manual): **reconstrucción desde cero** (`Q_REBUILD`). Al terminar bien limpia de `/.rockbox/aura/cfcache/` (§2) solo las entradas de artista/playlist (`ar-*`, `pl-*` — las de álbum sobreviven, clave estable desde D-338), arranca el constructor en segundo plano de la caché maestra (`/.aura/art/`, D-341) y vuelve a importar `ratings.cfg` |
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
| Índice de categoría POR ARCHIVO de Video/Fotos (`video_categories.cfg`/`photo_categories.cfg`, opcional, D-316) — distinto de los conteos agregados de la fila anterior | `CONTRATO-firmware-studio.md` §D.2 |
| Nombre del dispositivo (`device.cfg`) | `CONTRATO-dispositivo.md` |
| Formato de imágenes de `/Photos/` (JPEG baseline, ≤ 640 px, nombres) | `CONTRATO-firmware-studio.md` §D.1 |
| Caché MAESTRA de imágenes compartida entre familias (`/.aura/art/{albums,artists,photos}/`, D-340/D-341) | `CONTRATO-firmware-studio.md` §D.5 |
| Formato del paquete de tema | `CONTRATO-formato-tema.md` |
| Artefactos del Release, GPL, paleta | `CONTRATO-firmware-studio.md` §A–§C |

## 6 — Historial

- **v1.5 (2026-09-04, D-349, contrato v18 del firmware)** — §2: `cover.jpg` y la carátula embebida pasan a ser cuadradas de 320×320 (texto literal del plan maestro de la ronda; el trabajo del lado Studio es ST-142). Sube sobre la base de v1.4, **no** sobre v1.3: la copia que Aura Studio tenía de este documento había quedado desactualizada el 2026-08-26 y describía todavía el `cfcache/` indexado por `album_seek` que el firmware vacía en cada reconstrucción — falso desde D-338. Al reconciliar se conservó la v1.4 entera (§2, §4.2 y §5) y solo se añadió el párrafo nuevo, para que el contrato no volviera a describir un comportamiento que el firmware dejó atrás hace dos semanas. `Aura-Firmware` es la fuente canónica de este documento y Aura Studio copia **este** archivo. No cambia el esquema del marcador de §4.
- **v1.4 (2026-08-26, D-341, contrato v16 del firmware)** — §2: la nota sobre `cfcache/` (D-293) quedaba desactualizada desde D-338 (clave estable, ya no se vacía) y ahora también desde D-341 (caché privada de segundo nivel derivada de la maestra compartida) — corregida. §4.2: la fila `music` ya no dice "vacía `cfcache/`" (dejó de ser cierto en D-338) y ahora arranca el constructor de la maestra. §5: nueva referencia a `CONTRATO-firmware-studio.md` §D.5 (caché maestra compartida bajo `/.aura/art/`). No cambia el esquema del marcador de §4.
- **v1.3 (2026-08-18, D-318)** — §1: nueva convención de póster de TEMPORADA para Movie Flow (`<Nombre del programa> S0N.jpg`, sin `ExY`, archivo aparte del póster de episodio) y nota sobre el agrupamiento por `SxxEyy` que el firmware ya hace al leer la categoría `series`. No cambia el esquema del marcador de §4.
- **v1.2 (2026-08-18, D-316)** — §1, fila `/Videos/`: el firmware ahora lee el póster `<archivo>.jpg` (contract ya lo contemplaba desde v1, nunca se consumía) para el cartel de `CoverDrift`. §5: nueva referencia a `CONTRATO-firmware-studio.md` §D.2, el índice OPCIONAL de categoría por archivo de Video/Fotos (`video_categories.cfg`/`photo_categories.cfg`) — distinto de los conteos agregados que ya existían. No cambia el esquema del marcador de §4.
- **v1.1 (2026-08-18, D-298)** — §1, fila `/Videos/`: se documenta el límite de nombre de archivo (≤ 95 bytes UTF-8 con extensión), que ya regía de facto por `PHOTO_NAME_LEN` en Fotos pero no estaba escrito para Videos (`VIDEO_NAME_LEN` era 64, truncaba nombres largos en silencio). No cambia el esquema del marcador de §4: el campo `version` se queda en `1` — esto es una aclaración de un límite ya existente en la práctica, no un cambio de formato del marcador.
- **v1 (2026-08-17)** — Primera versión: estructura de directorios, colocación de carátulas y letras, marcador de sincronización (`/.aura/sync-pending.json`, `version: 1`, `sync_marker_supported: 1`).
