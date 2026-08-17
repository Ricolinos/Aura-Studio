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

## ST-003 — Sistema de temas: modelo del manifiesto, validador y contrato de formato

**Encargo**: aterrizar el lado Studio del sistema de temas (D-289 en el firmware) — `PLAN-themes-impl.md` (repo del firmware) fija el alcance de esta pasada como **Fase 2A**: empaquetar desde una carpeta de assets ya generados + instalar/listar/activar/eliminar. El rasterizador nativo (fuentes/íconos del sistema del usuario, `convttf` embebido) queda para la Fase 2B, trabajo de seguimiento aparte.

**`CONTRATO-formato-tema.md`** nuevo (copia idéntica a la de `Aura-Firmware`, verificada byte a byte): define el paquete de tema (`theme.cfg` + `fonts/` + `icons/masks/` + opcionales), los 14 roles de fuente y las 801 máscaras obligatorias, el versionado (`theme_format`), y que `accent_default`/`accent_presets` del manifiesto están reservados en el formato pero **el firmware no los lee en v1** — Studio los acepta y los serializa, pero no hay ningún selector de acento en la app que los consulte todavía (documentado, no una implementación a medias). `CONTRATO-firmware-studio.md` sube a v2: dos assets nuevos del Release (`theme-format-v1.json`, `aura-theme-default.zip`, no verificados por checksum) y dos claves nuevas de `aura.cfg` (`theme_id`, que Studio también puede escribir; `theme_format_supported`, solo lectura del lado Studio).

**`Models/AuraTheme.swift`**: `ThemePaletteRole`/`ThemeCategoryKey` (mismos 8+4 roles que `AURA_STYLE_ROLE_*`/`aura_style_manifest.h` del firmware), `ThemeFormat` (constantes del formato v1 — **hardcodeadas en Swift, no leídas de `theme-format-v1.json` en runtime**: ese archivo no viaja embebido en el `.app` en esta pasada, aunque `scripts/fetch-firmware.sh` ya lo trae a `Vendor/firmware-dist/` para uso futuro/de desarrollo; si el contrato sube de versión, estas constantes y las del firmware suben juntas, en la misma unidad de trabajo — mismo criterio que el propio firmware, que también hardcodea sus 14 roles en `aura_style.c`), `AuraThemeID` (mismas reglas que `aura_style_id_is_valid()`: `[a-z0-9-]{1,32}`, nunca `"default"`), `AuraThemeManifest` (parser/serializador de `theme.cfg`, mismo formato `clave: valor` que `aura.cfg`, claves desconocidas ignoradas en silencio).

**`Services/ThemeValidator.swift`**: valida un paquete ya en el layout del contrato -- manifiesto parseable, `theme_id` válido, `theme_format` ≤ el que reportó el firmware conectado (o `ThemeFormat.current` si no hay dispositivo o es un firmware anterior a D-289), 14 fuentes presentes, ≥801 máscaras. **No** parsea la cabecera binaria del `.fnt` (`FC_HEADER_VAL` de `firmware/font.c`) -- documentado como alcance deliberado de esta pasada: el firmware sigue siendo la última palabra (un `.fnt` corrupto que pase esta validación falla en `font_load()` y `aura_style_activate()` revierte solo, D-289), así que un hueco aquí no deja el dispositivo sin UI legible.

**Verificación**: `swift build` limpio; tests nuevos (`AuraThemeTests.swift`, `ThemeValidatorTests.swift`) — parseo/serialización con ida y vuelta, claves desconocidas ignoradas, ids inválidos rechazados, paquetes incompletos (formato futuro, fuentes faltantes, máscaras faltantes) detectados uno por uno.

## ST-004 — Instalador/gestor de temas en el iPod montado

**`Services/ThemeInstaller.swift`**: lista/instala/activa/elimina paquetes de tema bajo `.rockbox/aura/themes/<id>/` del volumen montado. Mismas reglas de seguridad que el resto de Studio: `mountPath` se revalida en cada llamada (nunca una captura vieja de un `AuraDevice` guardado -- mismo criterio que `AuraDeviceProbe`, D-070), candado global compartido con el instalador del firmware (`InstallerFlowRegistry`, para no cruzarse con un sync o una instalación en curso), `<id>` siempre pasa por `AuraThemeID.isValid()` antes de construir cualquier ruta que lo contenga (instalar, eliminar) -- con un chequeo extra de "cinturón y tirantes" (`target.deletingLastPathComponent() == root`) como defensa en profundidad, no la validación real. Instalación por `ditto` sin privilegios (el volumen ya está montado como disco de usuario, igual que el instalador del firmware -- D-036). `activate(id:)` edita **solo la línea `theme_id`** de `aura.cfg` (la agrega si falta), preservando el resto -- es una edición transitoria (el firmware reescribe el archivo entero en su próximo `aura_settings_save()`) pero tiene que sobrevivir hasta el próximo arranque, que es exactamente cuando `aura_style_boot()` la lee. `activeThemeID()`/`supportedThemeFormat()` leen `aura.cfg` sin escribir nada -- primera vez que Studio lee (no solo escribe) contenido real de `aura.cfg`, antes solo comprobaba su existencia (`AuraDeviceProbe`).

**`Services/ThemePackager.swift`**: reempaqueta una carpeta con el layout de `design-system/out/` del firmware (`fonts/a26-<rol>-<px>.fnt`, `icons/masks/*.bmp`, y opcionalmente `icons/{light,dark}/`, `icons/aura/{backgrounds,tile-icons}/`) al formato del contrato -- renombra las 14 fuentes por rol, copia máscaras y opcionales, escribe `theme.cfg`. Es deliberadamente **solo un reempaquetador**: no rasteriza nada (Fase 2B).

**Verificación**: tests nuevos (`ThemePackagerTests.swift`, `ThemeInstallerTests.swift`, contra un "iPod falso" -- mismo patrón que `LibrarySyncTests`) -- instalar copia y lista el tema; un paquete con `theme_format` incompatible se rechaza antes de tocar el disco; `activate()` preserva otras líneas de `aura.cfg` y agrega la clave si falta; `delete()` rechaza `"default"` y cualquier id inválido; rutas de montaje vacías o relativas se rechazan en toda operación.

## ST-005 — UI de gestión de temas, verificación completa y el tema Apple real

**`Views/ThemesView.swift`**: hoja presentada desde `Extras → Temas` (la fila, antes solo informativa, ahora navega si hay un iPod con Aura conectado). Sin `NavigationStack`/`NavigationLink` en ningún otro lado de la app -- se mantiene esa convención (una hoja, no un patrón de navegación nuevo). Lista "Aura" (fijo, primero) + los instalados (`checkmark` en el activo, atenuados con el motivo si no cargan); tocar una fila cargable la activa; eliminar pide confirmación mostrando el nombre (nunca "Aura"). "Construir tema nuevo…" abre un formulario: carpeta de origen (`NSOpenPanel`, mismo patrón que `PlaylistsView`), nombre, autor opcional, y el toggle obligatorio de licencia restringida -- marcado, deshabilita la redistribución y muestra el aviso completo en español ("Aura Studio lo construye solo para tu propio iPod: no lo compartas ni lo distribuyas...").

**Verificación pedida**: `swift build` limpio; `swift test` -- **228 tests** (37 nuevos de esta pasada), 2 saltados (`LibraryPipelineIntegrationTests`, sin fixtures en esta corrida), la única falla es la excepción conocida de `LiveEnrichmentIntegrationTests` (ST-002) -- sin regresión.

**Verificación adicional, no pedida**: `xcodegen generate` + `xcodebuild … build` real con `Vendor/firmware-dist/` poblado desde el `firmware/dist/` recién generado en `Aura-Firmware` (D-288/D-289) → **BUILD SUCCEEDED**. `AuraStudio.xcodeproj` regenerado y commiteado (los archivos nuevos se recogen solos -- `project.yml` apunta a la carpeta `Sources/AuraStudio` completa, no lista archivos uno por uno).

**El tema Apple, primer caso de uso real**: `~/Aura-local/theme-apple-source/design-system-out/` (extraído el 2026-08-16 al separar los repos, `AUDIT-pre-split.md`) ya contiene los 14 `.fnt` de SF Pro/Compact y las 801 máscaras horneadas por el pipeline del firmware el mismo día -- exactamente el layout que `ThemePackager` espera como `sourceRoot`. Con el flujo de esta pasada (Construir tema nuevo → elegir esa carpeta → marcar "licencia restringida") se puede construir e instalar el tema Apple real sin escribir un rasterizador nuevo, cumpliendo el principio rector (Studio nunca incluye ni descarga esos assets, solo usa los que ya están en la Mac del dueño). **No se ejecutó en esta pasada** contra un iPod físico -- queda como verificación en hardware real a cargo del dueño, documentada aquí como el paso siguiente natural, no como parte de esta unidad de trabajo (sin dispositivo conectado durante esta sesión).

## ST-006 — Detección de actualizaciones contra el primer Release público (`v0.1.0-beta`)

**Encargo**: `PLAN-release-updates.md` (carpeta padre, cubre ambos repos) — Fase 1 aprobada con las 9 recomendaciones. `Services/AuraUpdateChecker.swift` traía, desde el 2026-08-13, un comentario que anticipaba textualmente esta tarea: *"cuando existan releases públicos, este es el punto único donde se agregaría esa consulta"*. Ese día llegó — `Aura-Firmware` ya es público y publicó `v0.1.0-beta` como Release borrador (D-290, ver ese repositorio).

**`Services/GitHubReleaseChecker.swift`** (nuevo): `SemVer` (parser propio `vMAJOR.MINOR.PATCH[-prerelease]`, comparable — no hay nada así en Foundation; la comparación entre dos sufijos de prerelease distintos usa orden lexicográfico simple, no la regla completa de precedencia de SemVer punto 11 — alcance reducido a propósito, el único mantenedor de este repo nunca usa más de un sufijo por release real). `GitHubRelease` (`Codable`, solo `tag_name`/`draft`/`prerelease`). `GitHubReleaseChecker.fetchReleases()` consume `GET /repos/Ricolinos/Aura-Firmware/releases` (la lista, no `/releases/latest` — ese endpoint excluye prereleases y drafts por definición de GitHub, y mientras el firmware siga en beta nunca devolvería nada; acá es Studio quien decide con `pickLatest(includePrereleases:)`). Sin token — el repo es público.

**`Services/AuraUpdateChecker.swift`** (extendido, no reemplazado): `installedVersionTag(deviceMountPath:)` lee `.rockbox/aura/version.txt` del dispositivo montado (D-290 en Aura-Firmware — el firmware nunca lo lee de vuelta). `checkForUpdate(deviceMountPath:session:defaults:includePrereleases:)` es el nuevo punto de entrada: si hay `version.txt` legible, compara contra el Release más nuevo de GitHub (con `ReleaseCache`, ver abajo); si falta el marcador, el tag es ilegible, o no hay red y no hay caché, **cae** a `isUpdateAvailable(deviceMountPath:)` -- el chequeo por hash SHA-256 que ya existía, que sigue intacto y sin cambios de comportamiento. `includePrereleases: true` por defecto (Q6): mientras el único canal publicado sea beta, pedir opt-in no tendría sentido — queda la estructura lista para un ajuste "Recibir versiones beta" el día que exista un release estable, sin agregarlo todavía.

**`ReleaseCache`** (nuevo, mismo archivo): cachea la lista de Releases en `UserDefaults` con TTL de 24h (Q7) — evita depender de la red en cada conexión de dispositivo para algo que casi nunca cambia. Vencido el TTL, la próxima consulta reemplaza el caché.

**Regla innegociable, sin tocar**: el único disparador de instalación sigue siendo el botón "Actualizar Aura" en `DeviceGeneralView.swift`, que sigue llamando a `InstallerViewModel.startAutomaticUpdate()` sin cambios — esta pasada solo cambia **cómo** se calcula la señal `updateAvailable` (`ContentView.swift`, un único `await AuraUpdateChecker.checkForUpdate(...)` en vez de `isUpdateAvailable(...)`), nunca qué pasa después. Cero riesgo nuevo de escritura automática.

**Fuera de esta pasada, a propósito**: no se agregó ningún ajuste nuevo de UI (ni toggle "Recibir betas" ni botón manual "Buscar actualizaciones") — el encargo pedía implementar la detección y sus tests, no superficie nueva; la caché de 24h ya evita el problema que un botón manual resolvería, y se puede agregar sin fricción el día que haga falta.

**Tests nuevos**: `GitHubReleaseCheckerTests.swift` (parser SemVer -- válidos, malformados, ordenamiento incluido prerelease-vs-estable; `pickLatest` -- drafts siempre fuera, prereleases según flag, tags ilegibles ignorados sin romper; `fetchReleases` con `MockURLProtocol` -- decodificación real y error en status no-200). `AuraUpdateCheckerTests.swift` (`installedVersionTag` -- lectura/recorte/ausencia/ruta relativa; `ReleaseCache` -- ida y vuelta, vencimiento de TTL simulado sin esperar 24h reales; `checkForUpdate` -- actualización disponible, al día, usa caché sin pegarle a la red, y los tres casos de caída al hash -- sin `version.txt`, tag malformado, sin conexión -- comparados contra `isUpdateAvailable` directo en vez de fijar el resultado a mano, para no depender de que `BundledArtifacts.shared` resuelva en el bundle de test). `MockURLProtocol.swift` nuevo (primer cliente de red del proyecto que necesita simular una respuesta real; el resto de los clientes de metadata solo testean su lógica pura sin red).

**Verificación**: `swift build` limpio. `swift test` — **259 tests** (31 nuevos de esta pasada), 2 saltados (sin fixtures, igual que siempre), **0 fallas** — el propio `LiveEnrichmentIntegrationTests` (histórico flaky por red real) pasó esta corrida completo.

**Pendiente, documentado (Q9, hallazgo de D-290 en Aura-Firmware)**: `CONTRATO-firmware-studio.md` promete que esta app "cumple §3 mostrando una pantalla de Licencias" para el GPL v2 embebido — no existe tal vista en el código todavía. No bloqueaba el release del firmware (Studio sigue privado), pero hay que cerrarlo antes de que esta app se distribuya a terceros.

## ST-007 — Lector local de metadatos que sí funciona (`LocalTagReader`), y relectura de la biblioteca existente

**Encargo**: `PLAN-studio-ux.md` — Fase 1 aprobada por el dueño con las 11 recomendaciones (P1–P11); esta es la tanda 1 de la Fase 2 (P11: §2 primero, condiciona §1).

**Causa raíz de "los metadatos no se cargan correctamente"**: `LibraryEnricher.enrich()` leía tags locales solo con `ID3Writer.readTag` (`:74-77` antes de este cambio), un parser hecho para verificar el round-trip de lo que el propio `ID3Writer` escribe (ID3v2.3, encoding UTF-16 con BOM, `TYER`, tamaño de frame no-synchsafe, número de pista entero sin "/total") — y solo se llamaba para `.mp3`. Reproducido con fixtures generados con `ffmpeg 8.1.2` (Fase 1): ID3v2.4 UTF-8 (el default real de ffmpeg/MusicBrainz Picard/yt-dlp) daba mojibake ("CanciÃ³n") y perdía año/pista/portada; FLAC/M4A/AIFF nunca se leían. La tag rota se reescribía después al archivo que Studio manda al iPod (`LibraryViewModel.prepareMusic`), así que la pérdida quedaba permanente en la biblioteca del dueño.

**`Services/LocalTagReader.swift`** (nuevo): lee TODOS los formatos de música (mp3/m4a/flac/aiff/aif/wav) vía `AVURLAsset.load(.metadata)` — se itera `.metadata`, no `.commonMetadata`: para Vorbis comments (FLAC) los items individuales sí traen `commonKey` poblado aunque el metadata común del asset venga vacío (verificado contra archivos reales). Cubre `title/artist/album/albumArtist/year/genre/composer/trackNumber/coverArtData` por `commonKey` más los campos que ID3/Vorbis/iTunes no mapean a un `commonKey` (`TPE2`/`TDRC`/`TRCK` de ID3; `ALBUMARTIST`/`DATE`/`TRACKNUMBER` de Vorbis; `©day`/`©wrt`/`©gen`/`aART`/`trkn` de iTunes, decodificados a mano desde su FourCharCode en vez de depender de nombres exactos de constantes `AVMetadataIdentifier`). `METADATA_BLOCK_PICTURE` de FLAC (que AVFoundation no expone) vía un parser propio del bloque, ~40 líneas.

**`LibraryEnricher.enrich()`/`reenrich()`** usan `LocalTagReader` en vez de `ID3Writer.readTag`, y agregan `minimumMusicBrainzScore = 70`: antes se usaba el resultado de mayor `score` de MusicBrainz aunque fuera bajo (o `nil`, tratado como 0 en la comparación pero igual devuelto) — sin tags locales que lo desmintieran, un `score` bajo podía rellenar el álbum equivocado, exactamente lo que rompería una futura vista "por álbum" (§1). `ID3Writer.readTag` se conserva sin cambios de comportamiento (solo doc-comment actualizado): sigue siendo el verificador de round-trip de sus propios tests, ya no el lector de producción.

**Biblioteca existente del dueño (P1/P2)**: `LibraryItem.metadataEditedByUser` (nuevo, persistido como opcional en `biblioteca.json` para no romper catálogos viejos — un `Bool` no-opcional en el `Codable` sintetizado habría tirado el catálogo ENTERO con `try?` si la clave faltaba) se marca `true` en `applyReview`/`renameItem`/`clearCoverArt`/`applyBatchEdit` (nunca por `enrich`/`reenrich`, que solo llenan huecos). `LibraryViewModel.rereadLocalTags(ids:respectUserEdits:)` — nueva acción "Volver a leer etiquetas del archivo" en el menú contextual de Música — relee `sourceURL` (nunca `.preparados/`) y reemplaza los 9 campos que vienen del archivo SOLO donde el archivo trae un valor (nunca calificación ni letra sincronizada, que no son tags). `AppPreferences.legacyMetadataBannerShown` + `LibraryViewModel.legacyMetadataRereadOfferCount`/`evaluateLegacyMetadataRereadOffer()` ofrecen la relectura UNA sola vez, la primera vez que se carga una biblioteca con música después de este cambio — banner en `MediaSectionView` ("Aura Studio ahora lee mejor las etiquetas..."), "Ahora no" no vuelve a preguntar (la acción sigue disponible a mano), "Volver a leer" respeta ediciones manuales previas.

**Tests nuevos**: `LocalTagReaderTests.swift` (fixtures reales con ffmpeg, `XCTSkip` si no está instalado, mismo patrón que `LibraryPipelineIntegrationTests` — ID3v2.4 UTF-8 con acentos/año/pista/portada citando exactamente qué fallaba antes, ID3v2.3, FLAC con álbum y portada embebida, M4A, AIFF, archivo sin tags). `LibraryEnricherTests.swift` (umbral de score vía `MockURLProtocol`, y que `enrich()` lee FLAC sin depender de `.mp3`). `LibraryViewModelLocalTagRereadTests.swift` (merge que no borra lo que el archivo no trae, `respectUserEdits` protegiendo ediciones manuales salvo la acción explícita del menú, y el ciclo completo del banner — dos/tres instancias de `LibraryViewModel` sobre el mismo `libraryRoot`/`preferences` simulan reabrir la app).

**Verificación**: `swift build` limpio. `swift test` — **276 tests** (17 nuevos de esta pasada), 2 saltados (sin fixtures de `LibraryPipelineIntegrationTests`, igual que siempre), **0 fallas** — `LiveEnrichmentIntegrationTests` (incluido `testFullEnrichmentPipelineOnRealFilename`, que ejercita `enrich()` contra la API real) pasó completo, confirmando que el umbral de score no rompe el camino real. `xcodegen generate` + `xcodebuild … build` real → **BUILD SUCCEEDED**, con los 5 artefactos del firmware embebidos y firmados. `AuraStudio.xcodeproj` regenerado y commiteado.

**Siguiente tanda (P11)**: §1 — vistas "Por álbum"/"Por artista" (ahora con álbum/artista confiables) y tratamiento plano de Listas/`StudioStyle`.
