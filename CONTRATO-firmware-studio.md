# Contrato entre `Aura-Firmware` y Aura Studio

**Versión 7 — 2026-08-18.** Copia idéntica en ambos repositorios (`Aura-Firmware` es la fuente canónica; Aura Studio la referencia como "copia de la versión N de este contrato"). Cualquier cambio se hace en los dos repos en la misma unidad de trabajo y sube el número de versión.

**v7 (D-321/ST-035, hora y zona horaria automáticas) — implementado en ambos repos en esta pasada.** Agrega §D.4 y siete claves nuevas de `aura.cfg`: `rtc_sync_year/month/day/hour/min/sec` (transitorias, un solo uso) y `tz_local_quarters` (persistente, ya existía como ajuste interno de Aura desde D-293 — v7 es la primera vez que Studio también la escribe). Studio escribe las siete cada vez que detecta firmware Aura corriendo (conexión) y al terminar de instalar/actualizar; el firmware las aplica al RTC real y descarta las transitorias en el mismo momento en que ya recupera el disco tras un posible USB de Studio (`aura_main_sync_after_disk_handoff()`, D-293) — nunca hace falta un reinicio completo aparte.

**v6 (`PLAN-biblioteca-medios-v2.md`, fotos de artista) — SOLO contrato en esta pasada, sin código todavía.** Agrega §D.3 y dos filas nuevas a §D: `.rockbox/aura/artists/<archivo>.jpg` (foto de artista, JPEG baseline cuadrada ≤128px) y `.rockbox/aura/artist_images.cfg` (índice `archivo: artista`, formato en **D.3**) — ambos OPCIONALES, mismo criterio de degradación soportada que v5. A diferencia de v5, este contrato se escribe **antes** de implementar cualquiera de los dos lados — la Tanda 3/5 de `PLAN-biblioteca-medios-v2.md` lo implementa después.

**v5 (D-316, índice de categoría por archivo — Video/Fotos) — SOLO el lado firmware implementado en esta pasada.** Agrega dos archivos OPCIONALES nuevos a §D (`video_categories.cfg`/`photo_categories.cfg`) y el §D.2 con su formato exacto: le dan al firmware, por primera vez, la categoría (Película/Serie/Videoclip; Foto/Imagen/IA) de cada archivo individual de `/Videos`/`/Photos` — Aura Studio ya calcula esta categoría para su catálogo local (`biblioteca.json`, campo `category`) pero hasta ahora nunca la exportaba al dispositivo, solo 3 contadores agregados por sección (`sync_summary.cfg`, D-283). **Ausencia total de estos archivos es un caso soportado** (Studio todavía no los escribe): el firmware degrada a "sin categoría" en cada consulta, sin romper nada — ver `aura_media_categories.h`. **Pendiente**: el lado Studio (escribir estos dos archivos a partir de `category` en `biblioteca.json`) es trabajo aparte, en el repositorio de Aura Studio, no incluido en esta pasada.

**v4 (D-293 / ST-012, estructura de biblioteca)** agrega el contrato de estructura de biblioteca como documento hermano — **`docs/contracts/library-layout-v1.md`** (misma convención de copia idéntica): estructura de directorios, colocación de carátulas y letras `.lrc`, y el **marcador de sincronización pendiente** `/.aura/sync-pending.json` con el que Studio le pide al firmware reconstruir los índices; este documento solo agrega esas filas a §D y la clave `sync_marker_supported` de `aura.cfg`. **v4 también reconcilia las dos copias**, que habían divergido: la de `Aura-Firmware` tenía §D.1 (`Photos/`, D-291) y la de Studio la fila `device.cfg` (v3, ST-011) — desde v4 las dos traen ambas cosas.

**v3 (ST-011, nombre del dispositivo)** agrega `.rockbox/aura/device.cfg` a la tabla de §D — ver `CONTRATO-dispositivo.md` (contrato hermano, misma convención de copia idéntica) para el formato exacto.

**v2 (D-289, sistema de temas)** agrega el formato de tema como interfaz entre ambos repos — ver `CONTRATO-formato-tema.md` (contrato hermano, misma convención de copia idéntica) para el formato exacto; este documento solo agrega los dos assets nuevos del Release (§A) y las dos claves nuevas de `aura.cfg` (§D).

Contexto: hasta el 2026-08-16 ambos proyectos vivían en un monorepo (`Aura-Proyect`, hoy archivado). Este documento fija cómo se relacionan como repositorios separados, sin volver a acoplarlos por ruta de archivo.

---

## A — Artefactos y canal de distribución

Aura Studio **no lee el árbol de fuentes de `Aura-Firmware`**. La única vía es un **GitHub Release** de `Aura-Firmware`, con tag `vMAJOR.MINOR.PATCH` y estos assets, producidos por `firmware/tools/package_dist.sh` (más el bootloader, compilado a mano — ver `firmware/dist/README.md`):

| Asset | Verificado por checksum |
|---|---|
| `rockbox.ipod` | Sí |
| `rockbox.zip` | Sí |
| `bootloader-ipod6g.ipod` | Sí (si está presente en el release) |
| `mks5lboot` | Sí |
| `checksums.txt` | — (es el propio archivo de hashes, SHA-256, formato `shasum -a 256`) |
| `AuraPalette.swift` | No (Studio lo reemplaza directo; no hay verificación en runtime, solo en el momento de actualizar la dependencia) |
| `MODIFICATIONS.md` | No (documentación, para la pantalla de licencias) |
| `theme-format-v1.json` | No (Studio lo lee para saber roles/tamaños/nombres del formato de tema, ver `CONTRATO-formato-tema.md`) |
| `aura-theme-default.zip` | No (el default reempaquetado como tema instalable, id `aura`, libre — ejemplo canónico del formato, no necesario para instalar/usar el firmware) |

En Aura Studio: `Vendor/firmware-dist/` (gitignorado) recibe estos archivos vía `scripts/fetch-firmware.sh`, que descarga el Release fijado en `FIRMWARE_VERSION` (versionado, contiene el tag + los hashes esperados) y verifica cada checksum antes de dejarlo utilizable; falla con un mensaje claro si algo no coincide o si el Release no tiene un asset esperado. Mientras `Aura-Firmware` no tenga ningún Release público, `fetch-firmware.sh --from-dir <ruta>` copia desde un `firmware/dist/` local (generado con `package_dist.sh` en un checkout del firmware) — uso de desarrollo, documentado como tal, nunca como ruta por defecto de `project.yml`.

`project.yml` de Aura Studio apunta a `Vendor/firmware-dist/`, nunca a `../../firmware/dist/` ni a ninguna ruta que asuma un checkout hermano.

## B — Cumplimiento GPL v2

`mks5lboot`, `bootloader-ipod6g.ipod`, `rockbox.ipod` y `rockbox.zip` son derivados de Rockbox, GPL v2 (`rockbox.zip` además contiene Inter — SIL OFL — y Lucide/Phosphor — ISC/MIT — como fuentes/íconos del tema por defecto). Aura Studio (software cerrado) los distribuye embebidos como **agregación**, y cumple §3 (ofrecer la fuente) mostrando en una pantalla de "Licencias":

- La URL de `Aura-Firmware`.
- El tag exacto de `FIRMWARE_VERSION` que trae embebido.
- Un enlace a `MODIFICATIONS.md` del release correspondiente.

Las notas de cada release de Aura Studio repiten esos tres datos. Aura Studio no modifica esos binarios de ninguna forma.

## C — `tokens.json` / paleta de colores

Aura Studio no consume `tokens.json` ni corre `design-system/generate.py`. Consume `AuraPalette.swift`, generado **en** `Aura-Firmware` (`generate.py --swift-out`, invocado por `package_dist.sh`) y publicado como asset del Release. Cuando cambian los tokens del firmware, sale un Release nuevo; Aura Studio actualiza `FIRMWARE_VERSION` y reemplaza `Generated/AuraPalette.swift` con el del Release — nunca lo edita a mano, nunca lo regenera localmente contra un checkout del firmware salvo en desarrollo explícito.

## D — Contrato de datos en el disco del iPod

Esto **sí** es un acoplamiento permanente por diseño: ambos lados leen/escriben el mismo disco montado. Toda esta tabla vive bajo la raíz del volumen del iPod.

| Ruta | Escribe | Lee | Formato / notas |
|---|---|---|---|
| `.rockbox/rockbox.ipod` | Studio (instalador) | Firmware (bootloader), Studio (`AuraUpdateChecker`, sentinela de versión instalada) | Binario |
| `.rockbox/aura/aura.cfg` | Firmware | Studio (`AuraDeviceProbe`, decide si "ya arrancó") | — |
| `.rockbox/aura/aura.cfg` → clave `theme_id` | Firmware (`aura_style.c`); Studio también puede escribirla al instalar/activar un tema | Firmware, al arrancar (`aura_style_boot()`) | D-289. Vacío o `default` = el tema compilado. Studio escribe editando la línea, nunca reescribe el archivo entero (lo owns el firmware, que lo regenera completo en cada `aura_settings_save()`) |
| `.rockbox/aura/aura.cfg` → clave `theme_format_supported` | Firmware (siempre, en cada `aura_settings_save()`) | Studio (antes de instalar un tema, para saber si el firmware instalado lo soporta) | D-289. Solo escritura del lado firmware — nunca la relee |
| `.rockbox/aura/aura.cfg` → clave `sync_marker_supported` | Firmware (siempre, en cada `aura_settings_save()`) | Studio (al terminar un sync: si está, escribe el marcador y **no** borra la base de datos; si falta, conserva su mecanismo previo de borrar `database_*.tcd`) | D-293. Solo escritura del lado firmware — nunca la relee. Valor = versión de esquema del marcador que entiende (`1`) |
| `.rockbox/aura/themes/<id>/` | Studio (instala/reempaqueta), o el propio usuario a mano | Firmware (`aura_style.c`, `aura_style_scan()`/`aura_style_activate()`) | D-289. Formato completo en `CONTRATO-formato-tema.md`. `<id>` nunca `default` (reservado) |
| `.rockbox/aura/device.cfg` | Studio (solo la instalación `device_owner` edita el nombre) | Studio (nombre del iPod, barra lateral/General); firmware (`device_name`, slot "Mi iPod" de Acerca de — D-294) | ST-011 / ST-013 / D-294. Formato completo en `CONTRATO-dispositivo.md` (v2). El firmware **nunca** lo escribe — a diferencia de `theme_id`, no hay una clave que ambos lados toquen |
| `/.aura/sync-pending.json` | Studio (al terminar cada sync que tocó archivos); Firmware (sube `attempts`, y lo **borra** al terminar bien) | Firmware (al arrancar y al volver de la pantalla USB) | D-293 / ST-012. Esquema y comportamiento completos en **`docs/contracts/library-layout-v1.md` §4**. Directorio propio en la raíz, separado de `.rockbox/aura/` a propósito |
| `.rockbox/database_*.tcd` | Firmware (tagcache); Studio **solo los borra**, y solo con un firmware sin `sync_marker_supported` | Firmware | Índice de música. Comportamiento previo a D-293 de Studio (`triggerFirmwareDBRebuild`) — se conserva únicamente como compatibilidad con firmwares viejos |
| `.rockbox/aura/sync_manifest.json` | Studio (`LibrarySync`) | Studio (estado del último sync) | JSON |
| `.rockbox/aura/sync_summary.cfg` | Studio | Firmware (pantalla "Acerca de") | Contrato inverso — el firmware depende de un archivo que solo Studio escribe |
| `.rockbox/aura/ratings.cfg` | Studio | Studio | — |
| `.rockbox/icons/aura/` | Instalador (parte de `rockbox.zip`) | Firmware | — |
| `.rockbox/fonts/a26-title-20.fnt` | Instalador (parte de `rockbox.zip`) | Studio (`InstallerViewModel`, sentinela frágil de "árbol instalado") | Candidato a reemplazo por `.rockbox/aura/VERSION` explícito — no implementado en esta pasada |
| `Playlists/` | Studio (`PlaylistExporter`) | Firmware | — |
| `Music/`, `Videos/` | Studio (sync) | Firmware | 3 layouts posibles para `Music/` (Artista/Álbum, Álbum, Artista) — configurable en Studio. Estructura exacta, carátulas (`cover.jpg` en la carpeta del álbum o embebida) y letras `.lrc` (junto al audio, mismo nombre base) en `docs/contracts/library-layout-v1.md` §1–§3 |
| `Photos/` | Studio (sync) | Firmware (`aura_photos.c`) | D-291. Contrato detallado en **D.1** abajo — formato, resolución, nombres |
| `Videos/<archivo sin extensión>.jpg` | Studio (sync, opcional) | Firmware (`aura_screens.c`, cartel de CoverDrift) | Póster opcional hermano de cada video, mismo nombre base (`library-layout-v1.md` §2) — **el firmware ya listaba este campo del contrato, pero nunca lo leía hasta D-316**; ahora es la imagen que CoverDrift usa para Películas/Series |
| `.rockbox/aura/video_categories.cfg` | Studio (sync, **OPCIONAL** — D-316) | Firmware (`aura_media_categories.c`) | D-316. Contrato detallado en **D.2** abajo. Ausente = "sin categoría" para todo archivo, degradación soportada, no un error |
| `.rockbox/aura/photo_categories.cfg` | Studio (sync, **OPCIONAL** — D-316) | Firmware (`aura_media_categories.c`) | D-316. Ídem, formato en **D.2** |
| `.rockbox/aura/artists/<archivo>.jpg` | Studio (sync, **OPCIONAL**) | Firmware (`aura_artist_images.c`) | v6, `PLAN-biblioteca-medios-v2.md`. Foto de artista. Contrato detallado en **D.3** abajo. Ausente = placeholder circular con ícono, degradación soportada |
| `.rockbox/aura/artist_images.cfg` | Studio (sync, **OPCIONAL**) | Firmware (`aura_artist_images.c`) | v6. Índice `archivo: artista`, formato en **D.3** |
| `.rockbox/aura/aura.cfg` → claves `rtc_sync_year/month/day/hour/min/sec` | Studio (`ClockSyncWriter`, en cada conexión con Aura corriendo y al instalar/actualizar) | Firmware (`aura_settings_apply_pending_clock()`, en el mismo handoff de disco que D-293) | v7, D-321/ST-035. Transitorias — el firmware las aplica al RTC real y las descarta solas en su siguiente `aura_settings_save()`. Formato en **D.4** |
| `.rockbox/aura/aura.cfg` → clave `tz_local_quarters` | Firmware (UI de Ajustes › Huso horario, D-293); Studio también la escribe ahora (`ClockSyncWriter`) | Firmware (reloj mundial, D-293) | v7. Cuartos de hora respecto a UTC. Ya existía como ajuste interno — v7 es la primera vez que Studio también la escribe |

Cualquier cambio de ruta o de formato en esta tabla sube un `contract_version` (clave nueva a introducir en `sync_summary.cfg` y `aura.cfg` — no implementada todavía) y se registra en el diario de ambos repos (`D-NNN` en el firmware, `ST-NNN` en Studio), citándose cruzado.

### D.1 — `Photos/` en detalle (D-291)

Plano (sin subcarpetas — el firmware no recorre subdirectorios de `/Photos/`), un archivo por foto, nombre único dentro del directorio.

| Campo | Regla |
|---|---|
| Formato | JPEG baseline (SOF0/SOF1), Huffman, 8 bits, 3 componentes YCbCr (4:2:0 o 4:4:4) o 1 componente gris. Extensión `.jpg` (`.jpeg` también se acepta). **Nunca**: progresivo/aritmético, PNG, GIF, HEIC/HEIF, WebP, TIFF, BMP — Studio convierte todo a JPEG antes de copiar (`ImageResizer`, ya lo hace hoy) |
| Resolución | Lado mayor ≤ 640px ("Versión HD") o ≤ 320px ("Optimizar espacio"). Nunca escalar hacia arriba una fuente más chica. 640px es el valor recomendado: decodifica a 320×240 sin remuestreo posterior (IDCT a 1/2 exacto) |
| Orientación | Horneada en los píxeles al exportar (EXIF Orientation no se lee) |
| Espacio de color | sRGB; sin perfil ICC (el dispositivo muestra RGB565, 16 bits) |
| Nombre de archivo | UTF-8, ≤ 95 bytes incluyendo `.jpg` (recomendado ≤ 60 caracteres). **Único dentro de `/Photos/`** — dos fuentes homónimas de carpetas distintas no pueden colisionar en el mismo nombre de destino (ver hallazgo lateral en `PLAN-image-viewer.md` §9, pendiente del lado Studio) |
| Cantidad | El firmware lista hasta 500, ordenadas por nombre (natural, insensible a mayúsculas); con más, la fila final dice "…y N más". Studio no necesita limitar la copia |
| Miniaturas | Las genera y cachea el firmware (`.rockbox/aura/photocache/`) — Studio no genera ni escribe nada ahí |
| `sync_summary.cfg` | Sin cambio de formato por esto — `photo_count`/`photo_bytes` se siguen escribiendo igual (los lee "Acerca de"); el estado vacío de la lista de Fotos ya no depende de este archivo, lee `/Photos/` directo |

Detalle completo, hallazgos y justificación en `docs/plans/archivo/PLAN-image-viewer.md` (plan ya ejecutado, en `Aura-Firmware`).

### D.2 — Índice de categoría por archivo, Video/Fotos (D-316)

Dos archivos **OPCIONALES**, uno por sección, en `.rockbox/aura/` (junto a `sync_summary.cfg`, no en `/.aura/` — no son un marcador de "hay trabajo pendiente", son datos que el firmware consulta bajo demanda). `/Videos/` y `/Photos/` en el volumen **siguen siendo planos** (D-192, sin cambios) — este índice no reorganiza nada, solo asocia cada nombre de archivo ya existente con una categoría.

**Formato**: texto plano, una entrada por línea, `nombre_de_archivo: código` — mismo parser que `sync_summary.cfg` (`settings_parseline()`: separa en el primer `:`, una línea que empieza con `#` se descarta entera). `nombre_de_archivo` es el nombre EXACTO tal como aparece en `/Videos` o `/Photos` (con extensión, sin ruta). Líneas con un `código` desconocido se ignoran (compatibilidad hacia adelante).

`.rockbox/aura/video_categories.cfg`:

| Código | Significado |
|---|---|
| `movie` | Película |
| `series` | Serie / programa de TV |
| `clip` | Videoclip / video sin clasificar |

```
# aura-video-categories v1
Avatar Aang el último maestro del aire.mpg: movie
Little.Amelie.or.the.Character.of.Rain.2025.1080p.BDRIP.x264.DTS-AOC.mpg: movie
```

`.rockbox/aura/photo_categories.cfg`:

| Código | Significado |
|---|---|
| `photo` | Fotografía real (cámara, EXIF con datos de cámara) |
| `image` | Imagen (sin datos de cámara, capturas/diseños/reprocesadas) |
| `ai` | Generada por inteligencia artificial |

```
# aura-photo-categories v1
IMG_1814.JPG: photo
96c8c13a-cf32-40b9-b323-06e226260fa9.jpg: image
Gemini_Generated_Image_9epees9epees9epe.png: ai
```

Un archivo sin entrada en el índice correspondiente (o el índice ausente por completo) queda sin categoría — no aparece en ninguna de las filas filtradas (Películas/Series/Videoclips; Fotos/Imágenes/IA) pero sigue apareciendo en "Todos los videos"/"Todas las fotos", que nunca filtran. El firmware no vuelve a leer el disco por esto en cada cuadro: carga bajo demanda, cachea hasta que `aura_video_invalidate()`/`aura_photos_invalidate()` lo invaliden (mismos dos momentos que el resto de las listas de contenido: al entrar a la sección y al volver de la pantalla USB).

**Pendiente del lado Studio**: generar estos dos archivos a partir del campo `category` que `biblioteca.json` ya calcula por ítem (`MediaCategoryClassifier`, D-192/D-228) — no implementado en esta pasada, es trabajo del repositorio de Aura Studio.

### D.3 — Fotos de artista (v6, `PLAN-biblioteca-medios-v2.md`)

Dos elementos **OPCIONALES**, ambos en `.rockbox/aura/` (no en `/Music/` — la foto de artista no es contenido reproducible, es metadata de presentación).

**`.rockbox/aura/artists/<archivo>.jpg`** — la foto en sí. JPEG baseline, **cuadrada**, lado ≤ 128px (mismas reglas de formato que D.1: sRGB, sin progresivo, sin ICC). Nombre = el mismo algoritmo que ya usa Studio para su caché local (`ArtistImageStore.fileName(forArtistKey:)`: alfanuméricos ASCII y `-` tal cual, espacio → `-`, resto → `_%02x`, recortado a 120 caracteres + `.jpg`) — determinístico, no hace falta que el firmware lo calcule, solo lo busca por el nombre que dice el índice.

**`.rockbox/aura/artist_images.cfg`** — el índice. Texto plano, mismo parser que D.2 (`settings_parseline()`, separa en el primer `:`, líneas `#` se descartan). **Formato invertido respecto a D.2 a propósito**: `nombre_de_archivo.jpg: <tag artist crudo>` — el nombre de archivo va PRIMERO porque es FAT-seguro (nunca contiene `:`); el nombre de artista, que sí puede traer `:` (p. ej. `"Panic! At The Disco: Live"`), va como valor. El firmware compara el tag `artist` de cada pista (`tag_artist` de tagcache, nunca `tag_albumartist`) contra el valor **byte a byte, sin normalizar acentos** (`strcmp`) — la clave debe ser el string UTF-8 exacto tal como está en el archivo de audio. Varias líneas pueden apuntar al mismo archivo (un grupo de artista de Studio agrupado por `albumArtist` puede tener pistas con `artist` ligeramente distinto, p. ej. "The 1975" y "The 1975 feat. Phoebe Bridgers" — ambas líneas apuntan a la misma foto).

```
# aura-artist-images v1
the-1975.jpg: The 1975
the-1975.jpg: The 1975 feat. Phoebe Bridgers
gorillaz.jpg: Gorillaz
```

Reglas: valor duplicado (mismo artista dos veces) → gana la primera línea; archivo referenciado que no existe en `artists/` → placeholder, no error; artista sin ninguna línea → placeholder. Topes del firmware: hasta 300 entradas, nombre de artista hasta 64 bytes, nombre de archivo hasta 128 bytes — exceder cualquiera de los dos, la línea se ignora (compatibilidad hacia adelante, mismo criterio que D.2). Ausencia total de `artists/` y/o del índice es un caso soportado: toda la sección Artistas muestra el placeholder circular, sin romper nada.

**Pendiente de implementar en ambos repos** (esta pasada del contrato es solo el formato): firmware en `PLAN-biblioteca-medios-v2.md` Tanda 3 (`aura_artist_images.c`, layout circular en la lista de Artistas); Studio en la Tanda 5 (`writeArtistImages` en `LibrarySync`).

### D.4 — Hora y zona horaria automáticas (v7, D-321/ST-035)

Encargo del dueño: "cada que el ipod se conecte a Aura Studio, deberá actualizar su hora y region local para no tenerlo que configurar manualmente, igual al instalar o actualizar el firmware." El S5L8702 tiene RTC real (`CONFIG_RTC RTC_NANO2G`), pero solo se ajustaba a mano desde las pantallas de Ajustes › Fecha/Hora de Aura — nunca desde un archivo que Studio pudiera dejar.

Siete claves en `.rockbox/aura/aura.cfg`, mismo parser `settings_parseline()` que el resto del archivo:

```
rtc_sync_year: 2026
rtc_sync_month: 8
rtc_sync_day: 18
rtc_sync_hour: 14
rtc_sync_min: 32
rtc_sync_sec: 7
tz_local_quarters: -24
```

`rtc_sync_year/month/day/hour/min/sec` son **transitorias, de un solo uso**: Studio las escribe con la hora/fecha actual del Mac (hora local, no UTC) cada vez que detecta firmware Aura corriendo, y también al terminar de copiar los archivos en una instalación/actualización. El firmware las lee en `aura_settings_apply_pending_clock()`, llamada en el mismo punto donde ya recupera el disco tras un posible USB de Studio (`aura_main_sync_after_disk_handoff()`, D-293 — arranque y vuelta de la pantalla USB): si las **seis** están presentes, ajusta el RTC real (`rtc_write_datetime()`) y llama a `aura_settings_save()`, que reescribe `aura.cfg` entero solo con las claves que `aura_settings_t` conoce — las `rtc_sync_*` desaparecen solas, sin que el firmware tenga que borrarlas a mano. Si falta cualquiera de las seis, no se toca el RTC (evita aplicar una hora a medias).

`tz_local_quarters` es la clave que **ya existía** desde D-293 (ajuste interno de "Huso horario" en Ajustes, usado por el reloj mundial) — v7 es la primera vez que Studio también la escribe, calculada como `TimeZone.current.secondsFromGMT() / 900`. Es persistente, no transitoria: `aura_settings_load()` la lee normalmente en cada arranque, igual que cualquier otro ajuste.

**Deliberadamente fuera de alcance**: idioma (`language`) — el encargo pedía "hora y region", no idioma; el dueño puede haber elegido a propósito un idioma distinto al de macOS. Formato de fecha (DD/MM vs MM/DD), 12h/24h y primer día de la semana tampoco se tocan — no forman parte del RTC ni de este encargo.

## E — Compatibilidad de versiones

Aura Studio fija **una** versión exacta de firmware por build propio, en `FIRMWARE_VERSION`. Tabla de compatibilidad (se actualiza en cada release de cualquiera de los dos lados):

| Aura Studio | Firmware requerido | Versión de este contrato |
|---|---|---|
| ≤ 0.1.1 (histórico) | (sin Release público todavía — desarrollo con `--from-dir` sobre un checkout local de `Aura-Firmware` @ `main`) | v1 |
| 0.1.2 (histórico) | `v0.2.0-beta` (primer pin real contra un Release público — `rockbox.zip` incompleto, D-297 en `Aura-Firmware`) | v4 |
| 0.1.2 (histórico) | `v0.2.1-beta` (`FIRMWARE_VERSION`, PATCH: corrige el `rockbox.zip` de v0.2.0-beta, sin cambio de contrato — D-297/D-298/D-299 en `Aura-Firmware`, ST-018 aquí) | v4 |
| 0.1.2 (histórico) | `v0.2.2-beta` (`FIRMWARE_VERSION`, PATCH: morph de Letras optimizado + versión visible sin scroll en Acerca de, sin cambio de contrato — D-300/D-301 en `Aura-Firmware`) | v4 |
| 0.1.2 (histórico) | `v0.2.3-beta` (`FIRMWARE_VERSION`, PATCH: filtra sidecars AppleDouble de macOS + modo "cubrir" en el visor de fotos, sin cambio de contrato — D-302/D-303 en `Aura-Firmware`) | v4 |
| 0.1.2 (histórico) | `v0.2.4-beta` (`FIRMWARE_VERSION`, PATCH: corrige el modo "cubrir" para que sí agrande más allá del tamaño de origen, sin cambio de contrato — D-303 en `Aura-Firmware`) | v4 |
| 0.1.2 (histórico) | `v0.2.5-beta` (`FIRMWARE_VERSION`, PATCH: reproductor de video en español + modo "cubrir pantalla" con Select, sin cambio de contrato — D-304 en `Aura-Firmware`, ST-027 aquí) | v4 |
| 0.1.2 (histórico) | `v0.2.6-beta` (`FIRMWARE_VERSION`, PATCH: corrige parpadeo del OSD en "cubrir" + barra de progreso en píldora + el reproductor respeta modo/tema/acento, sin cambio de contrato — D-305/D-306 en `Aura-Firmware`) | v4 |
| 0.1.2 (histórico) | `v0.2.7-beta` (`FIRMWARE_VERSION`, PATCH: menú de ajustes del reproductor ya no es Rockbox nativo + corrige que "cubrir pantalla" se revirtiera solo, sin cambio de contrato — D-307/D-308 en `Aura-Firmware`) | v4 |
| 0.1.2 (histórico) | `v0.2.8-beta` (`FIRMWARE_VERSION`, PATCH: corrige recuadro blanco del menú de ajustes + calca la geometría/colores reales de las listas de Aura, sin cambio de contrato — D-309 en `Aura-Firmware`) | v4 |
| 0.1.2 | `v0.2.9-beta` (`FIRMWARE_VERSION`, PATCH: niveles de Animaciones/Gráficos, CoverDrift en Video/Fotos, Music Flow/Movie Flow — contrato sube a v5 (D-316, índice de categoría opcional `video_categories.cfg`/`photo_categories.cfg`, solo lado firmware; el lado Studio que los escriba queda pendiente) — D-310..D-318 en `Aura-Firmware`) | v5 |

Regla: un cambio a la sección D (contrato de datos) exige MINOR nuevo en ambos; un cambio de artefactos sin cambio de contrato es PATCH en el firmware y Studio solo actualiza el pin. `AuraUpdateChecker` (Studio) compara por hash SHA-256 del `rockbox.ipod` embebido vs. el instalado — sigue siendo la fuente de verdad para "hay actualización"; la UI puede mostrar además el tag de `FIRMWARE_VERSION` como referencia legible.

## F — Fixtures de prueba

`firmware/tools/gen_test_media.sh` (Rockbox) y el test de integración de Studio (`LibraryPipelineIntegrationTests`) generan datos de prueba **cada uno por su cuenta**, sin compartir fixtures entre repos — Studio tiene su propia copia recortada del generador de audio sintético, con salida en un directorio local a su propio repo (gitignorado). No es un acoplamiento — es duplicación intencional de ~60 líneas de script para no depender de una ruta relativa a un checkout ajeno.

## G — Documentación

- `docs/guia-instalacion.md` (guía de usuario final: instalar Aura Studio y sincronizar) vive **solo** en Aura Studio.
- `docs/guia-flasheo-restauracion.md` (protocolo del dispositivo: bootloader dual, DFU, checksums) vive **solo** en `Aura-Firmware`, como referencia técnica; Aura Studio la enlaza por URL, no la copia.
- `docs/guia-desarrollo.md` — cada repo tiene la suya, sin sección del otro proyecto.
- Contratos hermanos, **copia idéntica en ambos repos**, canónicos en `Aura-Firmware`: `CONTRATO-formato-tema.md`, `CONTRATO-dispositivo.md`, `docs/contracts/library-layout-v1.md`.

## Qué queda pendiente de implementar (documentado aquí, no bloqueante)

- `contract_version` explícito en `sync_summary.cfg`/`aura.cfg` (sección D).
- Reemplazo del sentinela `.rockbox/fonts/a26-title-20.fnt` por un `.rockbox/aura/VERSION` explícito.
- Primer Release público de `Aura-Firmware` con los 5+2+2 assets — hoy Studio se desarrolla contra un `firmware/dist/` local vía `fetch-firmware.sh --from-dir`.
- `accent_default`/`accent_presets` del formato de tema: aceptados y validables, pero el firmware no los lee todavía (ver `CONTRATO-formato-tema.md` §H y `sistema/05-temas.md`).
- El lado "constructor pleno" de Aura Studio (rasterizar fuentes/íconos del sistema del usuario) es Fase 2B, posterior — Fase 2 (2A) entrega reempaquetar desde una carpeta de assets ya generados + instalar/listar/activar/eliminar.
- Letras sin marcas de tiempo (D-293 / ST-012): Studio ya escribe el `.lrc` aunque solo tenga letra plana; el firmware la descarta (Modo 4 solo muestra líneas con `[mm:ss]`). Mostrar letra plana estática es trabajo del firmware, sin cambio de contrato.
