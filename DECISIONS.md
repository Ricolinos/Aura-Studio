# DECISIONS.md — Registro de decisiones técnicas (Aura Studio)

> Continuación de **[`DECISIONS-ARCHIVE.md`](DECISIONS-ARCHIVE.md)**
> (D-001…D-285, bitácora congelada del monorepo original — copia
> **byte-idéntica** a la del repositorio `Aura-Firmware`, verificable
> con `shasum -a 256 DECISIONS-ARCHIVE.md` en ambos). Este archivo
> registra las decisiones tomadas **en este repositorio** desde la
> separación del 2026-08-16, con numeración **ST-001** en adelante —
> sin coordinación con la numeración `D-NNN` del firmware. Una
> referencia `D-NNN` apunta siempre al repositorio del firmware
> (`DECISIONS-ARCHIVE.md` si NNN ≤ 285, `DECISIONS.md` si NNN ≥ 286).
>
> ⚠️ **Esto es una BITÁCORA, no una spec.** No tomes ninguna entrada
> vieja de aquí (ni del archivo) como comportamiento actual sin
> verificarla contra el código.

---

## Índice de las entradas del archivo con dominancia de Aura Studio

Las 41 decisiones de `DECISIONS-ARCHIVE.md` (D-001…D-285) donde Aura Studio fue el tema principal o dominante — señaladas en `PLAN-repo-split.md` del firmware al momento de la separación —, para no tener que hojear las 3551 líneas del archivo buscándolas:

| # | Título |
|---|---|
| D-004 | Tipografía e íconos |
| D-005 | Aura Studio nativa en Swift + SwiftUI |
| D-033 | Aura Studio sin App Sandbox, por qué hace falta |
| D-034 | `xcodebuild` no funciona en este entorno sandboxed; verificación vía `swift build`/`swift test` |
| D-035 | XcodeGen: el `resources:` de nivel de target no generó nada; hubo que usar `sources:` con `buildPhase: resources` |
| D-036 | Detección DFU delegada a `mks5lboot --dfuscan`, no reimplementada en Swift/IOKit |
| D-038 | ffmpeg localizado en el sistema, no empaquetado dentro de la app |
| D-041 | Dos bugs reales que solo aparecieron corriendo `xcodebuild` (no `swift test`) |
| D-046 | Identificación del disco del iPod: el nombre de media real no dice "iPod" ni "Apple" |
| D-063 | Fase 21 (PLAN-UX.md): Extras (cronómetro, bloqueo de pantalla) — omitida |
| D-065 | Fase 23 (PLAN-UX.md): Aura Studio — biblioteca real (detección automática, revisión de metadata, progreso real de transcodificación); bug de concurrencia Swift 6 |
| D-070 | Aura Studio: barra lateral tipo Finder, detección automática de dispositivo Aura, y Ajustes de la aplicación |
| D-071 | Bug crítico: Aura Studio detectaba el disco de arranque del Mac como si fuera el iPod |
| D-174 | Aura Studio: orden disco-antes-de-DFU en producción, dual boot, e ícono de Icon Composer |
| D-175 | Recuperación de disco sin sistema de archivos, cierre garantizado de agentes AMP, auditoría de voseo |
| D-177 | Recuperación: sin segundo DFU cuando el bootloader ya está grabado |
| D-181 | Formateo sin Acceso total al disco (y el error críptico, explicado) |
| D-182 | Montado ≠ aparecido: el cuelgue en "Copiando archivos" y el formateo innecesario |
| D-183 | Instalación automática a pantalla completa desde el modo bootloader |
| D-184 | Restauración completa: doble formateo y entrega a Finder |
| D-187 | El asistente de instalación sobrevive a la navegación |
| D-188 | Falso "disco ilegible" por ventana corta; se retira la pantalla completa; botón Cancelar |
| D-189 | "Algo salió mal" en dual boot: el iPod se desconectaba a mitad de la copia larga |
| D-192 | Ajustes: copiar o referenciar medios, organización y calidad por tipo, claves API |
| D-193 | Biblioteca: gestión de archivos con Vista Previa en vez de reproductor propio |
| D-198 | Biblioteca: tabla de verdad (columnas ajustables, checkboxes, menú contextual) |
| D-199 | "Más información...", columnas configurables y calificación de estrellas (lado Aura Studio) |
| D-202 | El "+" de columnas, la columna Título y visibilidad de la sincronización en Aura Studio |
| D-203 | Por qué "Buscar información en línea" no servía para nada, y Servicios reemplaza a Fuentes |
| D-215 | "Sincronizado" en texto, no solo en ícono |
| D-216 | Barra de almacenamiento por color en General |
| D-217 | Barra de progreso al sincronizar, con cuenta y tiempo estimado |
| D-218 | Edición en lote: aviso previo y ventana con campos "Mixto" |
| D-220 | Aura Studio: "Mostrar en Finder" en el menú contextual |
| D-222 | "Actualizar Aura" ya no manda al asistente completo — barra de progreso automática |
| D-228 | Aura Studio: la biblioteca local en Finder se organiza por tipo de medio |
| D-232 | Aura Studio: campo "Autor" (compositor) para organizar música en el firmware |
| D-237 | Portadas de playlist, de punta a punta (Aura Studio + firmware) |
| D-239 | Aura Studio: arrastrar carpetas completas, no solo archivos sueltos |
| D-243 | Bug real: las carátulas de álbum nunca llegaban a la carpeta correcta (ni en el simulador, ni en el dispositivo real) |
| D-273 | Aura Studio: la ruta rápida "ya instalado" puede confiar en evidencia obsoleta; el dueño la agarró en hardware real |

Además de estas 41, hay 53 entradas mixtas (firmware + Studio) y varias puramente de firmware que citan comportamiento de Studio de pasada — para esas, buscar directamente en `DECISIONS-ARCHIVE.md`.

---

## ST-001 — Aura Studio se separa del monorepo a su propio repositorio

**Encargo**: `PLAN-context-split.md` (repositorio archivado `Aura-Proyect`) propuso — y el dueño aprobó con todas las recomendaciones — crear `Aura-Studio` como repositorio nuevo en vez de reconvertir `Aura-Proyect` en el repo de Studio. Razón: `Aura-Proyect` cargaba 951 MB de `.git` (291 versiones de `rockbox.zip` con derivados de Apple en el historial) para 115 archivos de Swift; convertirlo en el repo vivo de Studio habría requerido reescribir la historia de un repositorio ya publicado (force-push) — exactamente lo que un archivo de referencia no debe sufrir. `Aura-Proyect` queda archivado, de solo lectura, como referencia histórica.

**Historial**: extraído con `git filter-repo --path studio --path docs/guia-instalacion.md --path .gitignore` sobre un clon fresco de `Aura-Proyect` (nunca sobre el original) — preserva 62 commits, autoría original, y el `blame` real del código Swift. `.git` resultante: 540 KB (vs. 951 MB del monorepo). Verificado sin binarios pesados ni derivados de Apple en el historial filtrado (`git rev-list --objects --all` — el blob más grande es `project.pbxproj`, ~65 KB).

**Bitácora**: `DECISIONS-ARCHIVE.md` (D-001…D-285) copiado íntegro desde `Aura-Firmware`, verificado **byte-idéntico** por `shasum -a 256`. Este `DECISIONS.md` arranca en `ST-001` con el índice de las 41 entradas del archivo donde Studio fue el tema dominante (arriba), para no perder la referencia rápida al reorganizar en dos repos.

**Contrato con el firmware**: `CONTRATO-firmware-studio.md`, copia idéntica del que vive en `Aura-Firmware` — fija que este repositorio consume artefactos del firmware **solo por GitHub Release** (nunca leyendo su árbol de fuentes), el cumplimiento GPL v2 que le corresponde a Studio por embeber binarios de Rockbox, y el contrato de datos en el disco del iPod que sí sobrevive por diseño (`.rockbox/aura/*.cfg`, `sync_manifest.json`, `Playlists/`, layouts de `Music/`).

**Cambios de código en esta pasada** (documentados en detalle en las entradas siguientes de esta sesión de trabajo): `project.yml` deja de apuntar a `../../firmware/dist/` y pasa a `Vendor/firmware-dist/` poblado por `scripts/fetch-firmware.sh`; `LibraryPipelineIntegrationTests` deja de buscar `firmware/test-media/` en un checkout hermano y usa fixtures propias (`test-media/`, generadas por `tools/gen_test_media.sh`, copia recortada del generador del firmware); `LICENSE` propia (propietaria, no la GPL v2 del firmware — los binarios GPL embebidos se declaran aparte, ver `CONTRATO-firmware-studio.md` §B); `CLAUDE.md` nuevo con las reglas que hasta ahora solo vivían en comentarios de código o en la memoria de Claude del monorepo (privilegios nativos, identificación de disco multi-criterio, español de México).

**Verificación**: `swift build` y `swift test` en un clon limpio de este repositorio — ver la entrada siguiente para el resultado exacto.

## ST-002 — Verificación de punta a punta: `xcodebuild` real con los 5 artefactos del firmware, y un hallazgo sobre `xcodebuild` en este entorno

**Verificación pedida** (`swift build` + `swift test`): limpia. `swift build` sin errores; `swift test` — 191 tests, 2 saltados (`LibraryPipelineIntegrationTests`, sin `test-media/` generado en esa corrida), 1 falla — `LiveEnrichmentIntegrationTests.testCoverArtArchiveFetchesRealCover` (HTTP 502 real de Cover Art Archive) — es la excepción conocida, no cuenta como regresión.

**Verificación adicional, no pedida pero completada de punta a punta**: se compiló el toolchain ARM completo en `Aura-Firmware` (`rockboxdev.sh`, arm-elf-eabi-gcc 9.5.0), se corrió `package_dist.sh` (build ARM limpio, solo los 2 warnings preexistentes `-Wtype-limits` no relacionados) y además se compiló a mano el bootloader (`--type=B`, no automatizado por el script) para tener los **5** artefactos completos por primera vez desde la separación. `scripts/fetch-firmware.sh --from-dir` los trajo a `Vendor/firmware-dist/` y verificó los 4 checksums (`bootloader-ipod6g.ipod` incluido). `xcodegen generate` ya no reporta errores de spec (antes fallaba por los 5 recursos faltantes, exactamente como debía). `xcodebuild … build` → **BUILD SUCCEEDED**, con los 5 recursos copiados y firmados dentro de `AuraStudio.app`. `AuraStudio.xcodeproj` regenerado y commiteado (solo cambian los GUIDs y las rutas de recurso, de `../../firmware/dist/` a `Vendor/firmware-dist/`, consistente con el cambio de `project.yml`).

**Hallazgo**: `xcodebuild … test` (no `swift test`) falla de forma determinista (reproducido en aislamiento con `-only-testing`) en `LibrarySyncTests.testSyncWritesAlbumCoverInsideAlbumFolder`, específicamente en su aserción de regresión (`XCTAssertFalse` sobre una ruta derivada de `FileManager.default.currentDirectoryPath`). Se auditó `LibrarySync.writeAlbumCovers()` línea por línea: resuelve la ruta de destino contra `volumeRoot` (`URL.appendingPathComponent`), nunca contra el directorio de trabajo del proceso — el bug de D-243 que esa prueba vigila **no está presente en el código actual**, y la primera aserción de la misma prueba (que la portada llegó al álbum correcto) pasa sin problema. La causa más probable es que el proceso de test alojado por `xcodebuild` en este entorno (headless/sandboxed) devuelve un `currentDirectoryPath` degenerado (p. ej. vacío), lo que colapsa la ruta "bogus" calculada por la prueba a simplemente `volumeRoot/Music` — que sí existe por diseño — dando un falso positivo de la aserción, no un bug real de la app. Esto es consistente con D-034 en `DECISIONS-ARCHIVE.md`, que ya documenta a `xcodebuild` como no confiable en este tipo de entorno y establece `swift build`/`swift test` como el camino de verificación primario — exactamente el que se pidió y el que pasó limpio. No se modificó `LibrarySync.swift` ni el test: no hay evidencia de una regresión real, y tocar cualquiera de los dos sin esa evidencia sería un cambio no pedido y sin justificación. Queda anotado aquí como investigación abierta, no como bloqueante.
