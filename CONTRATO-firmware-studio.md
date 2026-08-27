# Contrato entre `Aura-Firmware` y Aura Studio

**Versión 16 — 2026-08-26.** Copia idéntica en ambos repositorios (`Aura-Firmware` es la fuente canónica; Aura Studio la referencia como "copia de la versión N de este contrato"). Cualquier cambio se hace en los dos repos en la misma unidad de trabajo y sube el número de versión.

**v16 (D-340/D-341 — caché MAESTRA de imágenes compartida entre las tres familias, bajo `/.aura/art/`) — contrato y firmware Aura en esta pasada; Studio y las hermanas reciben copia idéntica después.** v15 compartió la base tagcache y, solo entre Metro-Aura/moonlit.aura, las miniaturas (`.mth`, formato distinto al de Aura). Encargo del dueño (2026-08-26): que las TRES familias, Aura incluida, compartan también la imagen ya decodificada — hoy cada familia decodifica el mismo JPEG por separado la primera vez que lo necesita, aunque el disco (y por tanto el archivo fuente) sea el mismo. Desde v16:

- **`/.aura/art/{albums,artists,photos}/`** (nuevo, **propiedad del firmware activo, compartido entre familias**, Studio nunca lo borra): la caché MAESTRA — un solo decode por imagen fuente, cuadrado, sin tema/esquinas/reflejo, del que cada familia DERIVA su propio formato final (transposición, esquinas de su tema, reducción de tamaño). Formato y claves completos en la nueva **§D.5** abajo.
- **Constructor en segundo plano**: cada firmware activo recorre su biblioteca (álbumes → fotos de artista → fotos) sin pantalla, dejando la maestra o un marcador `.none` por cada elemento — nunca bloquea al usuario ni decodifica dentro del hilo de UI. Detalle de implementación (D-341) solo del lado Aura-Firmware; el contrato solo fija formato/claves/directorios, no cómo cada firmware los llena.
- **"Claves de caché de carátulas" (párrafo de v15) queda ampliado, no reemplazado**: la clave `crc32(ruta de la pista representativa) + mtime` sigue siendo la de la caché **privada** de cada familia (L2, derivada); la MAESTRA usa la misma pareja `(crc32, mtime)` como clave — así una caché privada y su maestra siempre coinciden o se invalidan juntas. Fotos de artista y fotos de `/Photos` ganan la misma clave estable (antes solo álbumes la tenían formalizada en el contrato).
- **GC**: cada firmware barre su propia `/.aura/art/<tipo>/` con la misma tabla de claves vivas que ya usa para su caché privada — un archivo cuya clave no está viva es huérfano (fuente borrada, o reescrita por un sync) y se recoge con presupuesto, igual que ya hacía D-338/D-339 para `cfcache`.

Lo que v16 **no** cambia: §A bis, `/.aura/tagcache/`, `/.aura/thumbs/` (M-096, Metro/moonlit siguen usándolo para SU propio formato de 80 px — la maestra de v16 es un nivel más abajo, previo a cualquier derivación por familia), el marcador v4, el `library-stamp` v12 ni el bootloader.

**v15 (D-336/D-337/D-338, M-095/M-096 de Metro-Aura — base tagcache y miniaturas compartidas entre familias; claves estables de carátula) — contrato y firmware Aura en esta pasada; Studio y las hermanas reciben copia idéntica después.** Encargo del dueño (2026-08-26): hasta v14 cada árbol `/.rockbox/` llevaba **su propia** base de datos de música (`database_*.tcd`) y sus miniaturas, así que cambiar de familia (v10) o reinstalar obligaba a reconstruir la base (~5 min con biblioteca real) y a re-decodificar todas las carátulas, aunque nadie hubiera tocado la música. `apps/tagcache.c`/`.h` son byte-idénticos en los tres repositorios (mismo `TAGCACHE_MAGIC`, mismo formato), y Metro-Aura y moonlit.aura comparten el mismo formato de miniatura `.mth` de 80 px — no hay motivo para tres copias. Desde v15:

- **Dos subdirectorios nuevos dentro de `/.aura/`** (hasta hoy solo buzón de Studio), **propiedad del firmware y compartidos entre familias**:
  - **`/.aura/tagcache/`** — todos los `database_*.tcd` de Rockbox (`database_idx.tcd`, `database_N.tcd`, el temporal `database_tmp.tcd`) más **`db_stamp.txt`**, el sello v12 que ahora es uno solo y compartido. Cada firmware apunta `global_settings.tagcache_db_path` aquí en cada arranque, antes de `tagcache_init()`, sin confiar en su `config.cfg`.
  - **`/.aura/thumbs/{albums,artists,photos}/`** — miniaturas `.mth` de 80 px, compartidas por Metro-Aura y moonlit.aura (mismo formato crudo). **Aura no las usa**: su caché de carátulas (`.rockbox/aura/cfcache/`, `.pfraw` de 130 px transpuesto) sigue siendo propia de su árbol, porque su formato no le sirve a nadie más.
- **Los árboles `/.rockbox/` y `/.firmware-*/` dejan de contener `database_*.tcd` ni `aura/db_stamp.txt`.** Un firmware v15 que arranca y los encuentra en su árbol los **migra por `rename`** (misma partición FAT: reescritura de la entrada de directorio, sin copiar datos) al compartido **si éste no existe todavía**; si el compartido ya tiene base (la construyó cualquier otra familia), la del árbol es peso muerto y se borra. El sello por árbol viaja con su base y solo entonces. Metro-Aura hace lo mismo con `metrocache/` → `/.aura/thumbs/` (M-096).
- **Studio nunca borra `/.aura/tagcache/` ni `/.aura/thumbs/`** — ni al instalar, ni al cambiar de familia, ni en un sync. La base solo se (re)construye cuando Studio sincroniza música (marcador v4 + sello v12). Única excepción: **`triggerFirmwareDBRebuild`** (forzar reconstrucción, y el respaldo para firmwares sin `sync_marker_supported`) ahora borra `database_*.tcd` y `db_stamp.txt` **en `/.aura/tagcache/`**, además de en los árboles (por compatibilidad con firmwares anteriores a v15). `install_manifest.cfg` (v11) no lista nada de `/.aura/`.
- **Nota v12 actualizada** (abajo): el sello `db_stamp.txt` vive en `/.aura/tagcache/`; el cambio de familia compara **ese** sello (no el del árbol entrante, que ya no existe) con `/.aura/library-stamp`; y los firmwares sellan también tras el rebuild de primer arranque (base ausente al arrancar) y cuando encuentran una base compartida usable sin sello (migrada de un firmware anterior a v15) — hasta v14 solo sellaban al terminar una reconstrucción por marcador o manual, así que la primera conmutación tras una instalación limpia reconstruía otra vez sin motivo.
- **Claves de caché de carátulas.** Las cachés de carátula de álbum de los tres firmwares se indexan por **`crc32(ruta de la pista representativa)` + `mtime` de esa pista** (la primera pista que tagcache devuelve para el álbum — la misma con la que se busca la carátula — y su `tag_mtime` tal como tagcache lo guardó), **nunca por `seek` de tagcache**, que cambia en cada reconstrucción. Así una reconstrucción de la base (cambio de familia, forzar reconstrucción, reinstalación) **no invalida ninguna carátula**; una pista reescrita por un sync (Studio nunca preserva fechas al copiar) sí renueva la suya, y las entradas huérfanas las recoge cada firmware con presupuesto en su propia pasada. Los formatos por familia siguen siendo propios: Aura `cfcache/a-<crc 8 hex>-<mtime>-<lado>.pfraw` (130 px transpuesto, tema como parte de la cabecera); moonlit `art/` 120 px; Metro/moonlit `.mth` 80 px compartidos en `/.aura/thumbs/`.

Lo que v15 **no** cambia: §A bis, el formato de ningún archivo de §D, el marcador v4, el `library-stamp` v12 ni el bootloader.

**v14 (D-333/D-335, M-093, D-047 de moonlit.aura — tres familias; registro de familias) — contrato y firmware Aura en esta pasada; Studio y las hermanas reciben copia idéntica después.** Hasta v13 el contrato hablaba de "dos familias" y de "la otra familia": Aura y Metro-Aura. Existe una tercera, **moonlit.aura** (`Ricolinos/moonlit-aura`, `firmware_family: moonlit`, primer Release `v0.1.0`), que habla §D completo igual que Metro. v14 no cambia el formato de ningún archivo de §D; generaliza lo que estaba escrito para dos:

- **Nuevo §A bis — Registro de familias**: una tabla con, por familia, su valor de `firmware_family`, repositorio, árbol dormido, centinela de árbol instalado, prefijo de `FIRMWARE_VERSION` y subdirectorio del bundle de Studio. Es la única lista autorizada: una familia nueva es una fila más ahí (y una versión nueva de este contrato), nunca un caso especial en el código de Studio.
- **Todo "la otra familia" pasa a "cualquier otra familia"** (v10 en particular): los renombres son `/.rockbox/ → /.firmware-<saliente>/` y `/.firmware-<entrante>/ → /.rockbox/`; puede haber hasta N−1 dormidos a la vez; el espejado de los archivos de Studio va a **todos** los dormidos; instalar una familia estaciona la activa y no toca los demás dormidos.
- **Ajustes › Cambiar sistema** en el firmware activo: una fila por cada familia hermana, inerte (texto informativo) si su dormido no existe. Implementado en las tres familias (D-333 / M-093 / D-047).
- **Recuperación con varios dormidos**: con `/.rockbox/` ausente y exactamente **un** dormido, Studio lo despierta solo; con dos o más, no adivina: pide elegir.
- **§B**: moonlit.aura versiona la frontera GPL (bootloader + `mks5lboot`) con una etiqueta `BOOT-N` en su `CONTRATO-moonlit-studio.md` §B; su ausencia en las otras familias no es un error.
- **§E**: `FIRMWARE_VERSION` lleva una sección por familia (sin prefijo / `metro.` / `moonlit.`); `fetch-firmware.sh --family aura|metro|moonlit`.
- **Assets exclusivos de Aura**: `AuraPalette.swift`, `theme-format-v1.json` y `aura-theme-default.zip` solo los publica Aura; una familia sin sistema de temas no los publica, Studio no se los pide, y no declara `theme_format_supported` (moonlit no lo hace).

**v13 (ST-062/D-331, nombres con acento: forma Unicode NFC en todo archivo del contrato) — regla transversal de §D; corrección solo del lado que escribe.** Bug real: "Avatar Aang el último maestro del aire.mpg" figuraba como `movie` en `video_categories.cfg` y aun así era invisible en Películas/Movie Flow, mientras su vecino 100 % ASCII sí aparecía. Causa: el driver `msdosfs` de macOS **guarda** los nombres largos de FAT32 precompuestos (NFC) pero se los **reporta descompuestos** (NFD) a las apps; Studio serializaba lo que le daba `FileManager` (NFD) y el firmware compara byte a byte contra el UTF-16 que lee del disco (NFC) — un nombre con acento no empareja jamás, y las dos formas son indistinguibles a simple vista. Regla desde v13: **todo nombre de archivo o ruta que viaje DENTRO de un archivo del contrato se serializa en NFC** (precompuesto): `video_categories.cfg`, `photo_categories.cfg`, `ratings.cfg` y las rutas dentro de los `.m3u8` de `Playlists/`. Los firmwares no cambian (siempre compararon contra lo que hay en el disco); los índices ya escritos en NFD se corrigen solos en el siguiente sync (todos esos archivos se reescriben completos). `artist_images.cfg` queda fuera a propósito: su valor de emparejamiento es el **tag** crudo del archivo de música (D-322), no un nombre de archivo en FAT.

**v12 (ST-059, el cambio de firmware deja de reconstruir la base de datos sin motivo) — las tres partes.** Con v10, cambiar de firmware dejaba `/.aura/sync-pending.json` con `music: true` **siempre**, y el firmware que despertaba reconstruía su base (~5 min con biblioteca real) aunque nadie hubiera tocado la música (reporte del dueño). v12 introduce el **sello de biblioteca**:

- **`/.aura/library-stamp`** — una sola línea opaca (marca de tiempo + sufijo aleatorio). **Solo cambia cuando cambia la biblioteca**: Studio lo renueva en cada sync que toca música (junto al marcador). Los firmwares no lo renuevan jamás por su cuenta; solo lo **crean** si falta al momento de un cambio de firmware (arranque en frío del mecanismo: el saliente, cuya base está al día, lo crea y lo anota como propio).
- **`db_stamp.txt`** — el sello contra el que se construyó la base por última vez. Hasta v14 vivía **por árbol** en `.rockbox/aura/db_stamp.txt`, junto a la base que describía y sin espejarse; **desde v15 vive en `/.aura/tagcache/db_stamp.txt`, junto a la base compartida, y es uno solo para todas las familias** (el de un árbol anterior a v15 migra con su base por `rename`). Cada firmware lo escribe al terminar bien una (re)construcción — la disparada por marcador, la manual de Ajustes y, desde v15, también el rebuild de primer arranque (base ausente) y el hallazgo de una base compartida usable sin sello — copiando el sello vigente. Studio no lo escribe nunca; sí lo borra en `triggerFirmwareDBRebuild` (v15).
- **El cambio de firmware (v10, paso 5) se vuelve condicional**: se compara el `db_stamp.txt` — hasta v14 el del árbol **entrante**; desde v15 el **compartido** de `/.aura/tagcache/`, ignorando cualquier resto en el árbol entrante — con `/.aura/library-stamp`; si coinciden, **no se escribe el marcador** y el entrante arranca directo con la base intacta. Si difieren, o no hay sello (primera vez, o base anterior a v12), el marcador se escribe como hasta ahora. Aplica igual cuando el cambio lo hace Studio o cualquiera de los firmwares.
- Resultado: una reconstrucción por árbol tras cada sync real, y **cero** en los cambios de ida y vuelta entre syncs.
- Salvedad documentada: archivos de música copiados a mano por el Finder no renuevan el sello — tampoco disparaban reconstrucción antes de v12; el disparo manual ("Reconstruir biblioteca" / "biblioteca") sigue existiendo y también anota el sello al terminar.

**v11 (ST-058, actualizaciones selectivas por manifiesto) — solo lado Studio; los firmwares lo ignoran.** Actualizar extraía el `rockbox.zip` completo — 9 431 archivos en Aura, y cada archivo chico paga su ida y vuelta USB+FAT: minutos. Medido entre releases consecutivos reales, cambian ~5 archivos (~2 MB). v11 agrega **una** fila a §D: `.rockbox/aura/install_manifest.cfg`, escrito y leído **solo por Studio**:

- **Formato**: primera línea `# aura-install-manifest v1`; luego `tag: <tag del Release instalado>`; luego una línea por archivo del zip instalado: `<crc32 en hex, 8 dígitos> <tamaño en bytes> <ruta>` (la ruta al final, puede llevar espacios). El CRC32 es el del directorio central del propio zip — no se calcula nada.
- **Al instalar** (completo), Studio lo escribe. **Al actualizar la misma familia**, Studio compara el manifiesto del zip nuevo contra el instalado: extrae solo lo nuevo/cambiado, **borra** lo que desapareció (la extracción-merge de antes dejaba huérfanos para siempre) y reescribe el manifiesto. Umbral de sensatez: si el delta es enorme, extracción completa de siempre.
- **Respaldo total**: sin manifiesto (instalación manual, o anterior a v11), manifiesto ilegible, o cualquier error a mitad del delta → extracción completa. Nunca un firmware a medias.
- **Es por árbol** (v10): viaja dentro de `.rockbox/aura/` con su árbol al dormir/despertar y **nunca se espeja** a los árboles dormidos (cada uno describe lo suyo).
- Salvedad documentada: un archivo tocado a mano en el iPod que el manifiesto dé por idéntico no se repara en un delta; la reinstalación completa sigue existiendo para eso.

**v10 (ST-056, dos firmwares instalados a la vez y conmutación entre ellos) — contrato primero; implementación en orden Studio → Metro-Aura → Aura-Firmware.** Hasta v9, instalar una familia sobre la otra **reemplazaba** el árbol `.rockbox/` (y con él los ajustes, temas y calificaciones del firmware saliente). v10 define cómo conviven los dos y cómo se cambia de uno a otro sin borrar ni volver a descargar nada:

- **El árbol activo sigue siendo `/.rockbox/`.** No se renombra: es la única ruta que el bootloader (NOR, compartido por ambas familias) sabe arrancar, y la que ambos firmwares y sus plugins llevan compilada. Cambiarla obligaría a reflashear por DFU en cada cambio — justo lo que v10 evita.
- **Árboles dormidos con nombre propio:** `/.firmware-<familia>/` (`/.firmware-aura/`, `/.firmware-metro/`, `/.firmware-moonlit/` — §A bis, v14) — un árbol `.rockbox` completo de esa familia, en reposo (con su `rockbox.ipod`, fuentes, códecs, y **su propio `aura/aura.cfg`**, es decir sus ajustes). Puede haber hasta N−1 dormidos a la vez (v14). Nunca hay dos árboles dormidos de la misma familia; nunca un árbol dormido de la familia que está activa.
- **Cambiar de firmware = dos renombres** (en FAT, instantáneos) **más reiniciar**, en este orden y sin nada en medio: (1) el firmware saliente guarda todo lo suyo (`aura.cfg`, cola de tagcache); (2) `/.rockbox/` → `/.firmware-<saliente>/`; (3) `/.firmware-<entrante>/` → `/.rockbox/` (los demás dormidos, si los hay, no se tocan — v14); (4) se copia `/.rockbox/rockbox.ipod` del entrante sobre `/rockbox.ipod` en la raíz (el respaldo que el bootloader usa si el árbol está incompleto debe apuntar **siempre** al firmware activo); (5) se deja `/.aura/sync-pending.json` con `music: true` solo si el sello lo pide (v12; hasta v14 la base de datos de música vivía **dentro** de cada árbol y la del entrante estaba desactualizada — desde v15 es una sola, compartida en `/.aura/tagcache/`, y el marcador solo hace falta si hubo un sync de por medio); (6) reinicio en seco, sin pasar por el apagado que guarda ajustes (escribiría los del saliente en el árbol del entrante). Lo hace **Studio** (Extras › Firmware) o **el propio firmware activo**, que ofrece en Ajustes › Cambiar sistema **una fila por cada familia hermana**, inerte si su dormido no existe (v14; hasta v13 era una sola fila "Cambiar a …"), con la misma secuencia.
- **Recuperación:** un disco con `/.rockbox/` ausente y un árbol dormido presente es un cambio que quedó a medias (batería, cable). Studio lo repara al conectar: con **exactamente un** dormido, lo renombra de vuelta a `/.rockbox/`; con **dos o más** (v14) no adivina cuál era el activo y pide elegir. Por eso el orden (2)→(3): el peor caso deja un árbol dormido entero, nunca ninguno.
- **Los archivos del contrato que escribe Studio** en `.rockbox/aura/` (`sync_summary.cfg`, `artist_images.cfg` + `artists/`, `video_categories.cfg`, `photo_categories.cfg`, `ratings.cfg`, `device.cfg`) **se escriben también en todos los árboles dormidos presentes** (v14: no solo "el otro"), en cada sync — son chicos, y así el firmware que despierta no despierta desactualizado. `aura.cfg` **no**: es de cada firmware (las claves de reloj de v7 las escribe Studio solo en el activo; el dormido las recibe al despertar en su siguiente conexión). Los temas (`aura/themes/`) quedan en el árbol de Aura, activo o dormido.
- **Instalar cualquier otra familia** ya no borra: Studio **estaciona** el árbol activo como dormido (reemplazando un dormido anterior de esa misma familia, si lo hubiera) e instala la nueva en `/.rockbox/`; los demás dormidos no se tocan (v14). Si la familia pedida ya existe dormida, instalar es cambiar.
- **Detección:** la familia activa se sigue leyendo de `/.rockbox/aura/aura.cfg` (v8); la de un árbol dormido la dice su nombre de directorio. `version.txt` va por árbol.

Lo que v10 **no** cambia: §D para todo lo demás, el formato de ningún archivo, ni el bootloader.

**v9 (ST-047, Aura Studio distribuye e instala DOS familias) — implementado del lado Studio en esta pasada; sin trabajo del lado de ningún firmware.** Tres cambios, todos en lo que Studio hace con los Releases, ninguno en el disco del iPod:

- **§A generaliza el canal.** Ya no es "un GitHub Release de `Aura-Firmware`" sino *el Release de la familia que corresponda*: `Ricolinos/Aura-Firmware` para Aura y `Ricolinos/Metro-Aura` para Metro-Aura, con la **misma** lista de assets (`rockbox.ipod`, `rockbox.zip`, `bootloader-ipod6g.ipod`, `mks5lboot`, `checksums.txt`, más `MODIFICATIONS.md` y `THIRD-PARTY-NOTICES.txt`) y la misma verificación por checksum. Los extras que solo Aura publica (`AuraPalette.swift`, `theme-format-v1.json`, `aura-theme-default.zip`) siguen siendo de Aura; Metro no los publica y Studio no los espera de él.
- **§B se cumple por fin.** La pantalla de "Licencias" que el contrato prometía desde v1 (y que `DECISIONS.md` de Studio registraba como deuda) existe: Extras › Licencias, y lista **cada familia embebida** con su repositorio, el tag exacto incluido (leído de `firmware-version.txt`, que `fetch-firmware.sh` deja junto a los artefactos) y los enlaces a su `MODIFICATIONS.md` y `THIRD-PARTY-NOTICES.txt` del Release. Con un segundo firmware GPL a bordo esto dejó de ser opcional.
- **§E: `FIRMWARE_VERSION` lleva una sección por familia.** Sin prefijo = Aura (compatibilidad total con lo que había); prefijo `metro.` = Metro-Aura. `fetch-firmware.sh` acepta `--family aura|metro` (por defecto las dos) y guarda Metro en `Vendor/firmware-dist/metro/`, que `project.yml` empaqueta como referencia de carpeta para que los dos `rockbox.ipod` no choquen en el bundle.

**Qué NO cambia:** §D entero. Los dos firmwares hablan el mismo contrato de disco, que es justamente lo que hace posible que la biblioteca de Studio se sincronice igual con cualquiera; v8 ya dio la clave (`firmware_family`) para distinguirlos. Al **cambiar** de familia (instalar una sobre la otra) Studio borra `.rockbox/aura/aura.cfg` del firmware saliente — sus ajustes no le sirven al entrante y dejarlo engañaría la detección de v8 hasta el primer arranque; reinstalar la misma familia lo conserva, como siempre.

**v8 (ST-046, identidad del firmware instalado) — documentado antes de implementar el lado Studio, y sin lado firmware que implementar.** Agrega **una** clave a §D: `firmware_family` en `aura.cfg`. Resuelve un problema que el contrato tenía abierto desde que existe un segundo firmware que lo habla: **§D no dice quién lo está hablando.**

Hasta v7 el contrato asumía tácitamente un solo firmware. Eso dejó de ser cierto: **Metro-Aura** (`Ricolinos/Metro-Aura`, fork hermano de Rockbox con otro lenguaje visual) implementa §D completo a propósito — escribe `aura.cfg`, lee `sync_summary.cfg`, consume `artist_images.cfg` y `*_categories.cfg`, respeta `/.aura/sync-pending.json` — y sincroniza con Aura Studio sin un solo cambio. Esa compatibilidad es deseada y se conserva. Lo que **no** existía era forma de distinguirlos:

- Los archivos no sirven: Metro escribe el mismo árbol `.rockbox/aura/`.
- El USB tampoco: los dos son forks de Rockbox y se anuncian como `Rockbox.org` con el mismo VID/PID de Apple.

Consecuencia real observada en hardware (iPod del dueño, 2026-08-20, Metro v0.4.0 instalado): Aura Studio lo clasificaba como Aura, le consultaba actualizaciones al repositorio de **Aura** y comparaba el `version.txt` de Metro contra los tags de Aura. No había roto nada solo porque `0.4.0 > 0.3.1-beta`; en cuanto Aura publicara una versión mayor, Studio habría ofrecido "actualizar" y eso habría **sobrescrito Metro con Aura**.

**La ausencia de la clave significa `aura`**, y eso es lo que hace el cambio retrocompatible sin tocar `Aura-Firmware`: ese firmware nunca escribió esta clave ni la escribirá, así que "no está" es precisamente su firma. Todo iPod con Aura instalada — incluidos los instalados antes de v8 — se sigue reportando como Aura. **No hay trabajo del lado `Aura-Firmware` en este contrato**; el único firmware que escribe la clave hoy es Metro-Aura, que ya lo hacía desde antes de v8 (`metro_settings.c`, M-004) precisamente esperando esta lectura.

Regla de interpretación, obligatoria para quien lea la clave: **un valor desconocido NO es Aura.** Un firmware que se molestó en declararse está diciendo justamente que es otra cosa; tratarlo como Aura repetiría el mismo error con un firmware futuro.

Lo que v8 **no** hace: no le da a Studio la capacidad de instalar otro firmware que no sea Aura. Studio empaqueta un solo juego de artefactos (el de Aura), así que ante un firmware hermano informa de su Release nuevo — del repositorio correcto — y **no** ofrece el botón de instalar. Poder instalarlos es trabajo aparte, con su propio contrato de empaquetado y su obligación GPL §B correspondiente.

**v7 (D-321/ST-035, hora y zona horaria automáticas) — implementado en ambos repos en esta pasada.** Agrega §D.4 y siete claves nuevas de `aura.cfg`: `rtc_sync_year/month/day/hour/min/sec` (transitorias, un solo uso) y `tz_local_quarters` (persistente, ya existía como ajuste interno de Aura desde D-293 — v7 es la primera vez que Studio también la escribe). Studio escribe las siete cada vez que detecta firmware Aura corriendo (conexión) y al terminar de instalar/actualizar; el firmware las aplica al RTC real y descarta las transitorias en el mismo momento en que ya recupera el disco tras un posible USB de Studio (`aura_main_sync_after_disk_handoff()`, D-293) — nunca hace falta un reinicio completo aparte.

**v6 (`PLAN-biblioteca-medios-v2.md`, fotos de artista) — SOLO contrato en esta pasada, sin código todavía.** Agrega §D.3 y dos filas nuevas a §D: `.rockbox/aura/artists/<archivo>.jpg` (foto de artista, JPEG baseline cuadrada ≤128px) y `.rockbox/aura/artist_images.cfg` (índice `archivo: artista`, formato en **D.3**) — ambos OPCIONALES, mismo criterio de degradación soportada que v5. A diferencia de v5, este contrato se escribe **antes** de implementar cualquiera de los dos lados — la Tanda 3/5 de `PLAN-biblioteca-medios-v2.md` lo implementa después.

**v5 (D-316, índice de categoría por archivo — Video/Fotos) — SOLO el lado firmware implementado en esta pasada.** Agrega dos archivos OPCIONALES nuevos a §D (`video_categories.cfg`/`photo_categories.cfg`) y el §D.2 con su formato exacto: le dan al firmware, por primera vez, la categoría (Película/Serie/Videoclip; Foto/Imagen/IA) de cada archivo individual de `/Videos`/`/Photos` — Aura Studio ya calcula esta categoría para su catálogo local (`biblioteca.json`, campo `category`) pero hasta ahora nunca la exportaba al dispositivo, solo 3 contadores agregados por sección (`sync_summary.cfg`, D-283). **Ausencia total de estos archivos es un caso soportado** (Studio todavía no los escribe): el firmware degrada a "sin categoría" en cada consulta, sin romper nada — ver `aura_media_categories.h`. **Pendiente**: el lado Studio (escribir estos dos archivos a partir de `category` en `biblioteca.json`) es trabajo aparte, en el repositorio de Aura Studio, no incluido en esta pasada.

**v4 (D-293 / ST-012, estructura de biblioteca)** agrega el contrato de estructura de biblioteca como documento hermano — **`docs/contracts/library-layout-v1.md`** (misma convención de copia idéntica): estructura de directorios, colocación de carátulas y letras `.lrc`, y el **marcador de sincronización pendiente** `/.aura/sync-pending.json` con el que Studio le pide al firmware reconstruir los índices; este documento solo agrega esas filas a §D y la clave `sync_marker_supported` de `aura.cfg`. **v4 también reconcilia las dos copias**, que habían divergido: la de `Aura-Firmware` tenía §D.1 (`Photos/`, D-291) y la de Studio la fila `device.cfg` (v3, ST-011) — desde v4 las dos traen ambas cosas.

**v3 (ST-011, nombre del dispositivo)** agrega `.rockbox/aura/device.cfg` a la tabla de §D — ver `CONTRATO-dispositivo.md` (contrato hermano, misma convención de copia idéntica) para el formato exacto.

**v2 (D-289, sistema de temas)** agrega el formato de tema como interfaz entre ambos repos — ver `CONTRATO-formato-tema.md` (contrato hermano, misma convención de copia idéntica) para el formato exacto; este documento solo agrega los dos assets nuevos del Release (§A) y las dos claves nuevas de `aura.cfg` (§D).

Contexto: hasta el 2026-08-16 ambos proyectos vivían en un monorepo (`Aura-Proyect`, hoy archivado). Este documento fija cómo se relacionan como repositorios separados, sin volver a acoplarlos por ruta de archivo.

---

## A — Artefactos y canal de distribución

Aura Studio **no lee el árbol de fuentes de ningún firmware**. La única vía es un **GitHub Release** del repositorio de la familia según el registro de **§A bis** (`Ricolinos/Aura-Firmware` para Aura, `Ricolinos/Metro-Aura` para Metro-Aura, `Ricolinos/moonlit-aura` para moonlit.aura — v9/v14), con tag `vMAJOR.MINOR.PATCH` y estos assets, producidos por `firmware/tools/package_dist.sh` (más el bootloader, compilado a mano — ver `firmware/dist/README.md`):

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

`AuraPalette.swift`, `theme-format-v1.json` y `aura-theme-default.zip` son **exclusivos de Aura** (v9/v14): una familia sin sistema de temas no los publica y Studio no los espera de ella. Los demás assets son los mismos para toda familia.

En Aura Studio: `Vendor/firmware-dist/` (gitignorado) recibe estos archivos vía `scripts/fetch-firmware.sh`, que descarga el Release fijado en `FIRMWARE_VERSION` (versionado, contiene el tag + los hashes esperados) y verifica cada checksum antes de dejarlo utilizable; falla con un mensaje claro si algo no coincide o si el Release no tiene un asset esperado. Mientras `Aura-Firmware` no tenga ningún Release público, `fetch-firmware.sh --from-dir <ruta>` copia desde un `firmware/dist/` local (generado con `package_dist.sh` en un checkout del firmware) — uso de desarrollo, documentado como tal, nunca como ruta por defecto de `project.yml`.

`project.yml` de Aura Studio apunta a `Vendor/firmware-dist/`, nunca a `../../firmware/dist/` ni a ninguna ruta que asuma un checkout hermano.

## A bis — Registro de familias (v14)

La lista completa de familias que hablan este contrato. Todo lo que en este documento dependa de "qué familia" se resuelve **solo** con esta tabla — nunca con un caso especial en código. Una familia nueva = una fila nueva + una versión nueva de este contrato.

| Familia | `firmware_family` | Repositorio | Árbol dormido | Centinela de árbol instalado | Prefijo en `FIRMWARE_VERSION` | Subdirectorio del bundle |
|---|---|---|---|---|---|---|
| Aura | (ausente — es su firma, v8) | `Ricolinos/Aura-Firmware` | `/.firmware-aura/` | `.rockbox/fonts/a26-title-20.fnt` | (sin prefijo) | (raíz de `Vendor/firmware-dist/`) |
| Metro-Aura | `metro` | `Ricolinos/Metro-Aura` | `/.firmware-metro/` | `.rockbox/fonts/metro-list-20.fnt` | `metro.` | `metro/` |
| moonlit.aura | `moonlit` | `Ricolinos/moonlit-aura` | `/.firmware-moonlit/` | `.rockbox/fonts/moonlit-body-18.fnt` | `moonlit.` | `moonlit/` |

Notas:

- El **centinela** es el archivo cuya presencia en un árbol (activo o dormido) le dice a Studio "aquí hay un árbol de esta familia instalado" — cada familia lo elige entre sus propias fuentes, que ninguna otra trae.
- `AuraPalette.swift`, `theme-format-v1.json` y `aura-theme-default.zip` son exclusivos de Aura (§A). moonlit.aura no tiene sistema de temas: no publica esos tres assets y **no declara `theme_format_supported`** en `aura.cfg`; Studio no le ofrece instalar temas.
- Cada familia tiene su propio diario (`D-NNN` Aura, `M-NNN` Metro, `D-NNN` de moonlit citado como "D-NNN de moonlit") y, si le hace falta, su contrato hermano que **referencia** este (Metro: el suyo; moonlit: `CONTRATO-moonlit-studio.md`, §G).

## B — Cumplimiento GPL v2

`mks5lboot`, `bootloader-ipod6g.ipod`, `rockbox.ipod` y `rockbox.zip` son derivados de Rockbox, GPL v2 (`rockbox.zip` además contiene Inter — SIL OFL — y Lucide/Phosphor — ISC/MIT — como fuentes/íconos del tema por defecto). Aura Studio (software cerrado, gratuito, sin fines comerciales) los distribuye embebidos como **agregación**, y cumple §3 (ofrecer la fuente) mostrando en una pantalla de "Licencias" (Extras › Licencias, existe desde v9/ST-047), **por cada familia embebida**:

- La URL de su repositorio (el de §A bis: `Aura-Firmware`, `Metro-Aura` o `moonlit-aura`).
- El tag exacto de `FIRMWARE_VERSION` que trae embebido.
- Un enlace a `MODIFICATIONS.md` y a `THIRD-PARTY-NOTICES.txt` del release correspondiente.

Las notas de cada release de Aura Studio repiten esos tres datos. Aura Studio no modifica esos binarios de ninguna forma.

**Frontera GPL versionada (v14).** moonlit.aura versiona explícitamente el par `bootloader-ipod6g.ipod` + `mks5lboot` con una etiqueta `BOOT-N` en su `CONTRATO-moonlit-studio.md` §B (sube solo cuando cambia alguna de las dos fuentes; el SHA-256 cambia en cada recompilación y por eso no sirve como versión de fuente). Las otras familias no llevan esa etiqueta y **su ausencia no es un error**: el bootloader es el mismo NOR compartido, y la obligación de §3 se cumple igual con repositorio + tag + `MODIFICATIONS.md`.

## C — `tokens.json` / paleta de colores

Aura Studio no consume `tokens.json` ni corre `design-system/generate.py`. Consume `AuraPalette.swift`, generado **en** `Aura-Firmware` (`generate.py --swift-out`, invocado por `package_dist.sh`) y publicado como asset del Release. Cuando cambian los tokens del firmware, sale un Release nuevo; Aura Studio actualiza `FIRMWARE_VERSION` y reemplaza `Generated/AuraPalette.swift` con el del Release — nunca lo edita a mano, nunca lo regenera localmente contra un checkout del firmware salvo en desarrollo explícito.

## D — Contrato de datos en el disco del iPod

Esto **sí** es un acoplamiento permanente por diseño: ambos lados leen/escriben el mismo disco montado. Toda esta tabla vive bajo la raíz del volumen del iPod.

| Ruta | Escribe | Lee | Formato / notas |
|---|---|---|---|
| `/.aura/library-stamp` | Studio (en cada sync que toca música); Firmware (solo lo CREA si falta al cambiar de firmware) | Studio y Firmware (al cambiar de firmware) | v12, ST-059. Una línea opaca; se compara por igualdad exacta, nunca se interpreta |
| `/.aura/tagcache/` (`database_*.tcd`) | Firmware (tagcache, **cualquier familia**); Studio **solo los borra**, y solo en `triggerFirmwareDBRebuild` | Firmware (las tres familias, `apps/tagcache.c` byte-idéntico) | v15, D-337. Base de datos de música **compartida entre familias**; un firmware que la encuentra en su árbol (`.rockbox/database_*.tcd`, anterior a v15) la migra aquí por `rename`. Studio no la toca al instalar, cambiar de familia ni sincronizar; `install_manifest.cfg` no la lista |
| `/.aura/tagcache/db_stamp.txt` | Firmware (al terminar bien una (re)construcción de la base compartida, tras el rebuild de primer arranque, o al hallar la base usable sin sello) | Studio y Firmware (al cambiar de firmware) | v12 → v15. Uno solo, compartido; migra por `rename` desde `.rockbox/aura/db_stamp.txt`. Studio no lo escribe; lo borra en `triggerFirmwareDBRebuild` |
| `/.aura/thumbs/{albums,artists,photos}/` (`*.mth`) | Firmware (Metro-Aura y moonlit.aura) | Firmware (Metro-Aura y moonlit.aura; **Aura no**) | v15, M-096. Miniaturas de 80 px compartidas; Studio nunca las borra. Aura conserva su `cfcache/` propio (formato distinto) |
| `/.aura/art/albums/` (`<a-crc32 8 hex>.<mtime>.art`/`.none`) | Firmware (**las tres familias**) | Firmware (las tres familias, cada una deriva su propio formato final) | v16, D-340/D-341. Caché MAESTRA de carátula de álbum, 130×130, sin tema. Formato completo en **D.5** |
| `/.aura/art/artists/` (`<r-crc32 8 hex>.<mtime>.art`/`.none`) | Firmware (**las tres familias**) | Firmware (las tres familias) | v16, D-340/D-341. Caché MAESTRA de foto de artista, 130×130, sin tema. Formato en **D.5** |
| `/.aura/art/photos/` (`<p-crc32 8 hex>.<mtime>.art`/`.none`) | Firmware (**las tres familias**) | Firmware (las tres familias) | v16, D-340/D-341. Caché MAESTRA de foto de `/Photos`, 80×80, sin tema. Formato en **D.5** |
| `.rockbox/aura/db_stamp.txt` | — (retirado en v15) | Firmware (solo como origen de migración) | v12–v14. **Por árbol**: nunca se espejaba; hoy un firmware v15 lo mueve a `/.aura/tagcache/` y no lo vuelve a escribir |
| `.rockbox/aura/install_manifest.cfg` | Studio (al instalar/actualizar) | Studio (para la actualización selectiva) | v11, ST-058. Formato en la nota de v11. Los firmwares lo ignoran. **Por árbol** (v10): nunca se espeja a los dormidos |
| `/.firmware-<familia>/` (§A bis: `/.firmware-aura/`, `/.firmware-metro/`, `/.firmware-moonlit/`) | Studio (estaciona / instala / repara); Firmware (al cambiar desde Ajustes) | Studio (detecta qué familias hay; a cuáles se puede cambiar); Firmware (Ajustes › Cambiar sistema: una fila por hermana, inerte si su dormido no existe) | v10, ST-056; v14. Árbol `.rockbox` completo de esa familia, en reposo, con sus propios ajustes. Hasta N−1 dormidos a la vez; nunca dos de la misma familia; nunca el de la familia activa. El activo es siempre `/.rockbox/` (bootloader) |
| `/rockbox.ipod` (raíz) | Studio (al instalar y al cambiar); Firmware (al cambiar) | Bootloader (solo si `/.rockbox/rockbox.ipod` no existe) | v10: es el respaldo del bootloader y debe ser **siempre** el binario del árbol activo — se copia del `/.rockbox/rockbox.ipod` entrante en cada cambio |
| `.rockbox/rockbox.ipod` | Studio (instalador) | Firmware (bootloader), Studio (`AuraUpdateChecker`, sentinela de versión instalada) | Binario |
| `.rockbox/aura/aura.cfg` | Firmware | Studio (`AuraDeviceProbe`, decide si "ya arrancó") | — |
| `.rockbox/aura/aura.cfg` → clave `theme_id` | Firmware (`aura_style.c`); Studio también puede escribirla al instalar/activar un tema | Firmware, al arrancar (`aura_style_boot()`) | D-289. Vacío o `default` = el tema compilado. Studio escribe editando la línea, nunca reescribe el archivo entero (lo owns el firmware, que lo regenera completo en cada `aura_settings_save()`) |
| `.rockbox/aura/aura.cfg` → clave `theme_format_supported` | Firmware (siempre, en cada `aura_settings_save()`) | Studio (antes de instalar un tema, para saber si el firmware instalado lo soporta) | D-289. Solo escritura del lado firmware — nunca la relee |
| `.rockbox/aura/aura.cfg` → clave `sync_marker_supported` | Firmware (siempre, en cada `aura_settings_save()`) | Studio (al terminar un sync: si está, escribe el marcador y **no** borra la base de datos; si falta, conserva su mecanismo previo de borrar `database_*.tcd`) | D-293. Solo escritura del lado firmware — nunca la relee. Valor = versión de esquema del marcador que entiende (`1`) |
| `.rockbox/aura/aura.cfg` → clave `firmware_family` | Firmware (los que no son Aura; Aura **nunca** la escribe) | Studio (`FirmwareCapabilities.declaredFamily`, para nombrar el firmware y decidir a qué repositorio consultar actualizaciones) | v8, ST-046; v14. Valor: identificador corto en minúsculas de la familia, **registrado en §A bis** (`metro`, `moonlit`). **Ausente = `aura`** — es la firma de Aura, no un fallback. Un valor desconocido NO se trata como Aura: sin repositorio conocido, Studio no ofrece actualizaciones en vez de arriesgar una sobrescritura. Solo lectura del lado Studio — nunca la escribe |
| `.rockbox/aura/themes/<id>/` | Studio (instala/reempaqueta), o el propio usuario a mano | Firmware (`aura_style.c`, `aura_style_scan()`/`aura_style_activate()`) | D-289. Formato completo en `CONTRATO-formato-tema.md`. `<id>` nunca `default` (reservado) |
| `.rockbox/aura/device.cfg` | Studio (solo la instalación `device_owner` edita el nombre) | Studio (nombre del iPod, barra lateral/General); firmware (`device_name`, slot "Mi iPod" de Acerca de — D-294) | ST-011 / ST-013 / D-294. Formato completo en `CONTRATO-dispositivo.md` (v2). El firmware **nunca** lo escribe — a diferencia de `theme_id`, no hay una clave que ambos lados toquen |
| `/.aura/sync-pending.json` | Studio (al terminar cada sync que tocó archivos); Firmware (sube `attempts`, y lo **borra** al terminar bien) | Firmware (al arrancar y al volver de la pantalla USB) | D-293 / ST-012. Esquema y comportamiento completos en **`docs/contracts/library-layout-v1.md` §4**. Directorio propio en la raíz, separado de `.rockbox/aura/` a propósito |
| `.rockbox/database_*.tcd` | — (retirado en v15: la base vive en `/.aura/tagcache/`) | Firmware (solo como origen de migración) | Hasta v14, índice de música por árbol. Studio los sigue borrando en `triggerFirmwareDBRebuild` y con un firmware sin `sync_marker_supported` — únicamente como compatibilidad con firmwares anteriores a v15 |
| `.rockbox/aura/sync_manifest.json` | Studio (`LibrarySync`) | Studio (estado del último sync) | JSON |
| `.rockbox/aura/sync_summary.cfg` | Studio | Firmware (pantalla "Acerca de") | Contrato inverso — el firmware depende de un archivo que solo Studio escribe |
| `.rockbox/aura/ratings.cfg` | Studio | Studio | — |
| `.rockbox/icons/aura/` | Instalador (parte de `rockbox.zip`) | Firmware | — |
| `.rockbox/fonts/<centinela de la familia>` (§A bis: `a26-title-20.fnt` Aura, `metro-list-20.fnt` Metro, `moonlit-body-18.fnt` moonlit) | Instalador (parte de `rockbox.zip`) | Studio (`InstallerViewModel`, sentinela frágil de "árbol instalado", por familia — v14) | Candidato a reemplazo por `.rockbox/aura/VERSION` explícito — no implementado en esta pasada |
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

**Formato**: texto plano, una entrada por línea, `nombre_de_archivo: código` — mismo parser que `sync_summary.cfg` (`settings_parseline()`: separa en el primer `:`, una línea que empieza con `#` se descarta entera). `nombre_de_archivo` es el nombre EXACTO tal como aparece en `/Videos` o `/Photos` (con extensión, sin ruta), **en forma NFC** (v13: la forma en que FAT32 guarda el nombre, no la NFD que reporta `FileManager` en macOS). Líneas con un `código` desconocido se ignoran (compatibilidad hacia adelante).

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

### D.5 — Caché maestra compartida de imágenes (v16, D-340/D-341)

Hasta v15 cada familia decodificaba por su cuenta el mismo JPEG/BMP fuente (carátula de álbum, foto de artista, foto de `/Photos`) para producir su propio formato final (Aura: `.pfraw` 130 px transpuesto con esquinas del tema; Metro-Aura/moonlit.aura: `.mth` 80 px) — un decode por familia instalada, del mismo archivo, con el mismo resultado visual de fondo. v16 agrega un nivel intermedio **entre el archivo fuente y la caché privada de cada familia**: la maestra, decodificada UNA sola vez (por el firmware que llegue primero) y reusada por las demás.

**Directorios** (bajo la raíz del volumen, no dentro de ningún `.rockbox/`): `/.aura/art/albums/`, `/.aura/art/artists/`, `/.aura/art/photos/` — uno por tipo, nunca mezclados.

**Nombre de archivo**: `<k>-<crc32 8 hex>.<mtime>.art` (maestra resuelta) o `.none` (marcador negativo, 0 bytes: la fuente no tiene imagen resoluble — JPEG rechazado por el decodificador, o ninguna imagen encontrada). `<k>` es `a` (álbum), `r` (foto de artista, "retrato") o `p` (foto de `/Photos`). Ejemplo: `a-53cc14bc.1787505971.art`.

**Clave** = `(crc32(ruta del archivo fuente), mtime de ese archivo)` — el mismo par que ya usa la caché privada de álbum de Aura desde D-338/v15, generalizado a los tres tipos:
- Álbum: ruta de la pista representativa (la primera que la búsqueda por álbum devuelve) y su `mtime` según la base de datos de música.
- Foto de artista: ruta del archivo en `.rockbox/aura/artists/` y su `mtime` de directorio.
- Foto: ruta del archivo en `Photos/` y su `mtime` de directorio.

Una pista/foto reescrita por un sync (Studio no preserva fechas) cambia el `mtime` y por tanto la clave: la maestra vieja queda huérfana (la recoge el GC de cada firmware) y se genera una nueva sola.

**Formato del `.art`**: cabecera de 16 bytes little-endian — `magic` (4 bytes, `"MAST"` = `0x5453414D` leído LE), `width` (uint16), `height` (uint16), `flags` (uint32, siempre 0), `reservado` (uint32, siempre 0) — seguida de `width × height` píxeles **RGB565 little-endian, fila-contigua** (sin padding de fila). Un archivo cuya cabecera no cuadra con el tipo, o cuyo tamaño total no es exactamente `16 + width×height×2` bytes (corte de energía a mitad de escritura), se trata como ausente — el constructor lo reescribe, ningún lector intenta repararlo.

**Tamaños canónicos** (cuadrados siempre, sin importar la proporción de la fuente): álbum y foto de artista **130×130**; foto **80×80**. Estos son los lados MÁS GRANDES que cualquier familia necesita para su propio uso más exigente (Aura: Music Flow 130 px) — cada familia reduce por su cuenta al tamaño final que necesite (p. ej. Metro-Aura/moonlit.aura reducen a sus 80 px de `.mth`), nunca al revés.

**Derivación** (lo que hace cada familia al LEER la maestra, nunca al escribirla): la maestra no lleva tema, esquinas, reflejo ni transposición — es la imagen "plana", cuadrada, tal cual salió del decodificador con fill-and-center-crop. Cada familia, al cargar una maestra a RAM: (1) reduce por caja entera si su tamaño final es menor (p. ej. 130→48 para una lista); (2) aplica su propia transposición/orientación de pantalla si la necesita; (3) hornea esquinas/tema/reflejo si su diseño los usa. Ninguno de esos tres pasos se cachea en la maestra — viven en la caché privada (L2) de cada familia, que sigue existiendo exactamente como antes de v16 (`cfcache/*.pfraw` en Aura, `.mth` en Metro/moonlit) y se invalida con su propia clave de siempre.

**Fill-and-center-crop** (cómo se llena el cuadrado cuando la fuente no es cuadrada): se decodifica ajustando la imagen DENTRO del cuadrado (keep-aspect) y, si con eso no queda ya cuadrada, se decodifica una SEGUNDA vez a una caja mayor calculada para que el lado menor llegue al tamaño canónico, y se recorta centrado — dos decodes, nunca deformación. Una proporción más extrema que 4:1 no vale la pena "llenar": se centra la versión ajustada sobre el color promedio de la propia imagen (sin tema, sin color de marca de ninguna familia).

**Constructor en segundo plano** (solo se documenta el comportamiento observable; la implementación es de cada firmware, no parte del contrato): cada firmware activo, al confirmar que su base de datos de música es usable, recorre álbumes → fotos de artista → fotos de `/Photos` y deja resuelta (`.art` o `.none`) la maestra de cada elemento que no la tenga ya — sin pantalla, sin bloquear al usuario, a ritmo bajo (cede CPU/disco frente a reproducción y frente a la interfaz activa). Aura-Firmware lo implementa como un hilo de baja prioridad (D-341); otra familia podría implementarlo distinto (un paso por vuelta del bucle principal, por ejemplo) sin romper el contrato, siempre que el resultado en disco sea el mismo formato.

**GC**: cada firmware barre su propia `/.aura/art/<tipo>/` con la misma tabla de claves vivas que usa para el GC de su caché privada (D-338/D-339) — una maestra o un `.none` cuya clave no está en esa tabla es huérfano (fuente borrada, o reescrita por un sync) y se borra con presupuesto. Studio **nunca** toca `/.aura/art/` — ni al instalar, ni al cambiar de familia, ni al sincronizar; es exclusivamente del firmware, igual que `/.aura/tagcache/`.

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

`FIRMWARE_VERSION` lleva **una sección por familia** (v9/v14, §A bis): sin prefijo = Aura, `metro.` = Metro-Aura, `moonlit.` = moonlit.aura (`tag=` + hashes cada una). `fetch-firmware.sh` acepta `--family aura|metro|moonlit` (por defecto todas) y guarda cada familia en su subdirectorio del bundle según §A bis.

Regla: un cambio a la sección D (contrato de datos) exige MINOR nuevo en ambos; un cambio de artefactos sin cambio de contrato es PATCH en el firmware y Studio solo actualiza el pin. `AuraUpdateChecker` (Studio) compara por hash SHA-256 del `rockbox.ipod` embebido vs. el instalado — sigue siendo la fuente de verdad para "hay actualización"; la UI puede mostrar además el tag de `FIRMWARE_VERSION` como referencia legible.

## F — Fixtures de prueba

`firmware/tools/gen_test_media.sh` (Rockbox) y el test de integración de Studio (`LibraryPipelineIntegrationTests`) generan datos de prueba **cada uno por su cuenta**, sin compartir fixtures entre repos — Studio tiene su propia copia recortada del generador de audio sintético, con salida en un directorio local a su propio repo (gitignorado). No es un acoplamiento — es duplicación intencional de ~60 líneas de script para no depender de una ruta relativa a un checkout ajeno.

## G — Documentación

- `docs/guia-instalacion.md` (guía de usuario final: instalar Aura Studio y sincronizar) vive **solo** en Aura Studio.
- `docs/guia-flasheo-restauracion.md` (protocolo del dispositivo: bootloader dual, DFU, checksums) vive **solo** en `Aura-Firmware`, como referencia técnica; Aura Studio la enlaza por URL, no la copia.
- `docs/guia-desarrollo.md` — cada repo tiene la suya, sin sección del otro proyecto.
- Contratos hermanos, **copia idéntica en ambos repos**, canónicos en `Aura-Firmware`: `CONTRATO-formato-tema.md`, `CONTRATO-dispositivo.md`, `docs/contracts/library-layout-v1.md`.
- `CONTRATO-moonlit-studio.md` vive **solo** en `moonlit-aura` y referencia este contrato (misma relación que el contrato propio de Metro-Aura): lo que ahí se define (frontera GPL `BOOT-N`, particularidades de esa familia) no se copia aquí; este documento solo lo cita (§A bis, §B).

## Qué queda pendiente de implementar (documentado aquí, no bloqueante)

- `contract_version` explícito en `sync_summary.cfg`/`aura.cfg` (sección D).
- Reemplazo del sentinela `.rockbox/fonts/a26-title-20.fnt` por un `.rockbox/aura/VERSION` explícito.
- (v15) Lado firmware Aura implementado (D-337/D-338); Metro-Aura en M-095/M-096. Pendiente: copia idéntica de este contrato en Studio y las hermanas; lado Studio de v15 (`triggerFirmwareDBRebuild` borrando en `/.aura/tagcache/`; no tocar `/.aura/tagcache/` ni `/.aura/thumbs/` al instalar/cambiar); moonlit.aura (`art/` y `.mth` a clave estable + `/.aura/thumbs/`).
- (v14) El cambio entre **cualquier par** de familias desde el dispositivo (Ajustes › Cambiar sistema) queda implementado en las tres: Aura D-333, Metro-Aura M-093, moonlit.aura D-047. Lo que sigue pendiente es solo del lado Studio: recuperación con dos o más dormidos (pedir elegir) y `--family moonlit` en `fetch-firmware.sh`.
- `accent_default`/`accent_presets` del formato de tema: aceptados y validables, pero el firmware no los lee todavía (ver `CONTRATO-formato-tema.md` §H y `sistema/05-temas.md`).
- El lado "constructor pleno" de Aura Studio (rasterizar fuentes/íconos del sistema del usuario) es Fase 2B, posterior — Fase 2 (2A) entrega reempaquetar desde una carpeta de assets ya generados + instalar/listar/activar/eliminar.
- Letras sin marcas de tiempo (D-293 / ST-012): Studio ya escribe el `.lrc` aunque solo tenga letra plana; el firmware la descarta (Modo 4 solo muestra líneas con `[mm:ss]`). Mostrar letra plana estática es trabajo del firmware, sin cambio de contrato.
