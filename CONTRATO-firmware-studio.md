# Contrato entre `Aura-Firmware` y Aura Studio

**Versión 4 — 2026-08-17.** Copia idéntica en ambos repositorios (`Aura-Firmware` es la fuente canónica; Aura Studio la referencia como "copia de la versión N de este contrato"). Cualquier cambio se hace en los dos repos en la misma unidad de trabajo y sube el número de versión.

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
| `.rockbox/aura/device.cfg` | Studio | Studio (nombre editable del iPod, barra lateral/General); firmware, opcional, no implementado | ST-011. Formato completo en `CONTRATO-dispositivo.md`. El firmware **nunca** lo escribe — a diferencia de `theme_id`, no hay una clave que ambos lados toquen |
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

## E — Compatibilidad de versiones

Aura Studio fija **una** versión exacta de firmware por build propio, en `FIRMWARE_VERSION`. Tabla de compatibilidad (se actualiza en cada release de cualquiera de los dos lados):

| Aura Studio | Firmware requerido | Versión de este contrato |
|---|---|---|
| 0.1.x | (sin Release público todavía — desarrollo con `--from-dir` sobre un checkout local de `Aura-Firmware` @ `main`) | v1 |

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
- `device.cfg` (nombre del iPod, ST-011): Studio ya lo escribe y lo lee; el firmware no lo lee todavía (mostrarlo en el slot "Mi iPod" de "Acerca de" es el consumo natural, ver `CONTRATO-dispositivo.md` §E).
- Letras sin marcas de tiempo (D-293 / ST-012): Studio ya escribe el `.lrc` aunque solo tenga letra plana; el firmware la descarta (Modo 4 solo muestra líneas con `[mm:ss]`). Mostrar letra plana estática es trabajo del firmware, sin cambio de contrato.
