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

**Pendiente, documentado (Q9, hallazgo de D-290 en Aura-Firmware)**: `CONTRATO-firmware-studio.md` promete que esta app "cumple §3 mostrando una pantalla de Licencias" para el GPL v2 embebido — no existe tal vista en el código todavía. No bloqueaba el release del firmware (Studio sigue privado), pero hay que cerrarlo antes de que esta app se distribuya a terceros. **Cerrado en ST-047** (`LicensesView`, Extras › Licencias, contrato v9).

## ST-007 — Lector local de metadatos que sí funciona (`LocalTagReader`), y relectura de la biblioteca existente

**Encargo**: `PLAN-studio-ux.md` — Fase 1 aprobada por el dueño con las 11 recomendaciones (P1–P11); esta es la tanda 1 de la Fase 2 (P11: §2 primero, condiciona §1).

**Causa raíz de "los metadatos no se cargan correctamente"**: `LibraryEnricher.enrich()` leía tags locales solo con `ID3Writer.readTag` (`:74-77` antes de este cambio), un parser hecho para verificar el round-trip de lo que el propio `ID3Writer` escribe (ID3v2.3, encoding UTF-16 con BOM, `TYER`, tamaño de frame no-synchsafe, número de pista entero sin "/total") — y solo se llamaba para `.mp3`. Reproducido con fixtures generados con `ffmpeg 8.1.2` (Fase 1): ID3v2.4 UTF-8 (el default real de ffmpeg/MusicBrainz Picard/yt-dlp) daba mojibake ("CanciÃ³n") y perdía año/pista/portada; FLAC/M4A/AIFF nunca se leían. La tag rota se reescribía después al archivo que Studio manda al iPod (`LibraryViewModel.prepareMusic`), así que la pérdida quedaba permanente en la biblioteca del dueño.

**`Services/LocalTagReader.swift`** (nuevo): lee TODOS los formatos de música (mp3/m4a/flac/aiff/aif/wav) vía `AVURLAsset.load(.metadata)` — se itera `.metadata`, no `.commonMetadata`: para Vorbis comments (FLAC) los items individuales sí traen `commonKey` poblado aunque el metadata común del asset venga vacío (verificado contra archivos reales). Cubre `title/artist/album/albumArtist/year/genre/composer/trackNumber/coverArtData` por `commonKey` más los campos que ID3/Vorbis/iTunes no mapean a un `commonKey` (`TPE2`/`TDRC`/`TRCK` de ID3; `ALBUMARTIST`/`DATE`/`TRACKNUMBER` de Vorbis; `©day`/`©wrt`/`©gen`/`aART`/`trkn` de iTunes, decodificados a mano desde su FourCharCode en vez de depender de nombres exactos de constantes `AVMetadataIdentifier`). `METADATA_BLOCK_PICTURE` de FLAC (que AVFoundation no expone) vía un parser propio del bloque, ~40 líneas.

**`LibraryEnricher.enrich()`/`reenrich()`** usan `LocalTagReader` en vez de `ID3Writer.readTag`, y agregan `minimumMusicBrainzScore = 70`: antes se usaba el resultado de mayor `score` de MusicBrainz aunque fuera bajo (o `nil`, tratado como 0 en la comparación pero igual devuelto) — sin tags locales que lo desmintieran, un `score` bajo podía rellenar el álbum equivocado, exactamente lo que rompería una futura vista "por álbum" (§1). `ID3Writer.readTag` se conserva sin cambios de comportamiento (solo doc-comment actualizado): sigue siendo el verificador de round-trip de sus propios tests, ya no el lector de producción.

**Biblioteca existente del dueño (P1/P2)**: `LibraryItem.metadataEditedByUser` (nuevo, persistido como opcional en `biblioteca.json` para no romper catálogos viejos — un `Bool` no-opcional en el `Codable` sintetizado habría tirado el catálogo ENTERO con `try?` si la clave faltaba) se marca `true` en `applyReview`/`renameItem`/`clearCoverArt`/`applyBatchEdit` (nunca por `enrich`/`reenrich`, que solo llenan huecos). `LibraryViewModel.rereadLocalTags(ids:respectUserEdits:)` — nueva acción "Volver a leer etiquetas del archivo" en el menú contextual de Música — relee `sourceURL` (nunca `.preparados/`) y reemplaza los 9 campos que vienen del archivo SOLO donde el archivo trae un valor (nunca calificación ni letra sincronizada, que no son tags). `AppPreferences.legacyMetadataBannerShown` + `LibraryViewModel.legacyMetadataRereadOfferCount`/`evaluateLegacyMetadataRereadOffer()` ofrecen la relectura UNA sola vez, la primera vez que se carga una biblioteca con música después de este cambio — banner en `MediaSectionView` ("Aura Studio ahora lee mejor las etiquetas..."), "Ahora no" no vuelve a preguntar (la acción sigue disponible a mano), "Volver a leer" respeta ediciones manuales previas.

**Tests nuevos**: `LocalTagReaderTests.swift` (fixtures reales con ffmpeg, `XCTSkip` si no está instalado, mismo patrón que `LibraryPipelineIntegrationTests` — ID3v2.4 UTF-8 con acentos/año/pista/portada citando exactamente qué fallaba antes, ID3v2.3, FLAC con álbum y portada embebida, M4A, AIFF, archivo sin tags). `LibraryEnricherTests.swift` (umbral de score vía `MockURLProtocol`, y que `enrich()` lee FLAC sin depender de `.mp3`). `LibraryViewModelLocalTagRereadTests.swift` (merge que no borra lo que el archivo no trae, `respectUserEdits` protegiendo ediciones manuales salvo la acción explícita del menú, y el ciclo completo del banner — dos/tres instancias de `LibraryViewModel` sobre el mismo `libraryRoot`/`preferences` simulan reabrir la app).

**Verificación**: `swift build` limpio. `swift test` — **276 tests** (17 nuevos de esta pasada), 2 saltados (sin fixtures de `LibraryPipelineIntegrationTests`, igual que siempre), **0 fallas** — `LiveEnrichmentIntegrationTests` (incluido `testFullEnrichmentPipelineOnRealFilename`, que ejercita `enrich()` contra la API real) pasó completo, confirmando que el umbral de score no rompe el camino real. `xcodegen generate` + `xcodebuild … build` real → **BUILD SUCCEEDED**, con los 5 artefactos del firmware embebidos y firmados. `AuraStudio.xcodeproj` regenerado y commiteado.

**Siguiente tanda (P11)**: §1 — vistas "Por álbum"/"Por artista" (ahora con álbum/artista confiables) y tratamiento plano de Listas/`StudioStyle`.

## ST-008 — Sync transaccional con cancelación segura (motor de "Actualizar/Sincronizar")

**Encargo**: `PLAN-general-sync.md` — Fase 0+1 aprobada por el dueño con las recomendaciones P1–P13; esta es la tanda 1 de 4 (P11: el motor primero, antes que la UI que lo consume).

**El problema real**: `LibrarySync.sync()` copiaba con `FileManager.copyItem` directo al destino final, sin ninguna forma de cancelar, y guardaba el manifiesto una sola vez al terminar todo el lote. Una cancelación (o el iPod desconectándose a mitad de copia) podía dejar un archivo final truncado que el tagcache del firmware sí llega a indexar con metadata basura (`add_tagcache`/`probe_file_format` deciden por extensión, no validan integridad) — y perdía el progreso de todo lo ya copiado si el proceso no llegaba al `saveManifest` final.

**`LibrarySync.copyFileTransactionally`** (nuevo): copia por bloques de 4 MB a `<destino>.aura-tmp` (extensión que el firmware nunca indexa) y renombra al final — nunca existe un archivo final a medio escribir. `isCancelled` se consulta en la frontera de cada archivo del plan y dentro de cada bloque; al cancelar, borra el temporal y devuelve `.cancelled` en vez de lanzar una excepción, así `sync()` sigue con `finalize` (portadas, playlists, `sync_summary.cfg`, `ratings.cfg`, borrado del índice del firmware) para lo que sí se alcanzó a copiar — el iPod queda consistente, nunca a medias. El manifiesto se guarda **tras cada archivo** (antes solo al final): es lo que hace que cancelar o una desconexión real conserven lo ya copiado.

**Marcador `.rockbox/aura/sync_in_progress`** (§8.2): se escribe al empezar y se borra al cerrar limpio (fin normal o cancelación deliberada, que sí corre `finalize`) — una excepción real (desconexión) nunca llega a ese borrado, así que el marcador sobrevive para el próximo sync. `sweepOrphanedTempFiles()` barre cualquier `.aura-tmp` huérfano de una sesión interrumpida de golpe antes de empezar una nueva.

**`SyncManifest`/`SyncRecord` suben a v2** (`contractVersion`, `destinationSize`/`destinationModifiedAt` — la huella del archivo tal como quedó en el iPod, base para una tanda futura que distinga "sincronizado" de "modificado fuera de Aura Studio"; `writtenBy`/`syncedAt`): todos los campos nuevos son opcionales a propósito — un `Codable` sintetizado con un campo no-opcional exigiría la clave, y `try? decode` tiraría el manifiesto **entero** si un manifiesto v1 no la trajera. `AppPreferences.installationID` (nuevo, UUID generado una sola vez) es el `writtenBy` de esta Mac — P7 del plan, para que dos Macs sincronizando el mismo iPod no se pisen registros el día que exista esa UI.

**`LibraryViewModel.sync(toVolumeAt:scope:)`** gana `SyncScope` (`.all`/`.selection(Set<UUID>)`, P6/§6 del plan): con selección vacía, o con ids que no están `.ready`, es un no-op seguro que ni siquiera toca el dispositivo — nunca fallaba, ahora tampoco escribe nada. `cancelSync()` nuevo, respaldado por `SyncCancellationFlag` (`NSLock`, no un `actor`: `LibrarySync.sync()` no es `async`, no puede `await` en medio de un bloque de 4 MB sin reescribir el método entero). El sync ahora toma `InstallerFlowRegistry.beginWriting()/endWriting()` — antes no lo hacía, a diferencia del instalador y los temas, un hueco real de coordinación. `LibrarySync.sync()` gana `restrictCopyToSourcePaths` para soportar `.selection`: la biblioteca completa se sigue pasando (playlists/resumen/índice reflejan lo que de verdad hay en el dispositivo), solo se restringe qué se copia esta pasada — lo que queda afuera sigue `.copy` en el plan real para el próximo sync sin restricción, nunca se pierde.

**Tests nuevos**: `LibrarySyncCancellationTests.swift` — cancelación entre archivos (el primero sobrevive, cero temporales, marcador borrado), cancelación a mitad de archivo con un fixture mayor a `copyBlockSize` para forzar más de un bloque (ni destino ni temporal quedan), una falla real simulada a mitad de sync (un archivo regular bloqueando el directorio del segundo item — mismo camino de código que una desconexión física: el marcador **no** se borra, lo ya copiado sobrevive, un sync posterior retoma sin recopiar), barrido de temporal huérfano, y `restrictCopyToSourcePaths`. `LibraryViewModelSyncScopeTests.swift` — selección vacía/no lista nunca toca el dispositivo, `cancelSync()` sin sync activo no falla.

**Verificación**: `swift build` limpio. `swift test` — **284 tests** (8 nuevos), 2 saltados (sin `test-media/` en la corrida del set completo), 2 fallas — ambas la excepción conocida de `LiveEnrichmentIntegrationTests.testCoverArtArchiveFetchesRealCover` (502 real de Cover Art Archive) — sin regresión. Corrida aparte con `tools/gen_test_media.sh` generado: `LibraryPipelineIntegrationTests` (incluye el camino completo `LibraryViewModel.sync()` → `Task.detached` → `InstallerFlowRegistry` → `LibrarySync.sync()` real) — 2/2 limpias, confirma que el candado nuevo no rompe el flujo real. `xcodegen generate` + `xcodebuild … build` real → **BUILD SUCCEEDED**.

**Fuera de esta tanda, documentado**: `DeviceSyncIndex` (los 5 estados de sincronización por elemento, §4 del plan), pausar (solo cancelar por ahora), y todo cambio de UI (barra persistente, separación del botón "Actualizar", nombre editable del dispositivo, columna de estado con los 5 valores) — quedan para las tandas 2–4.

## ST-009 — Separación Actualizar/Sincronizar, `DeviceActivityBar`, alcance de sincronización

**Encargo**: `PLAN-general-sync.md` — tanda 2 de 4 (P11), pedida explícitamente por el dueño ("barra, Actualizar/Sincronizar, alcance") tras la tanda 1 (`ST-008`, el motor).

**"Actualizar" deja de sincronizar (§1.1)**: el botón de la barra de herramientas de `ContentView` (antes disparaba `LibraryViewModel.sync`) ahora es un refresco inofensivo — re-sondea el dispositivo montado (`deviceMonitor.refreshDevice()`) y consulta si hay firmware nuevo (`AuraUpdateChecker.checkForUpdate`), nunca escribe en el iPod. La sincronización real queda en tres accesos con verbos distintos, sin compartir palabra ni botón con el refresco ni con la instalación de firmware: **"Sincronizar"** (nuevo botón en General, junto a `DeviceActivityBar`), **"Sincronizar con el iPod"** (⇧⌘S, comando nuevo del menú Archivo — D-202 había puesto el sync en la barra de herramientas justamente para poder dispararlo sin ir a General; con esa barra ahora ocupada por "Actualizar", el acceso rápido pasa a un comando de menú real vía `FocusedValue`/`SyncCommandContext`, no a duplicar el botón), y **"Sincronizar la selección"** (nuevo ítem del menú contextual de la tabla de biblioteca). Del lado del firmware, "Actualizar Aura" se renombra **"Instalar actualización de Aura"** y gana un botón manual **"Buscar actualizaciones de Aura"** — instalar sigue siendo el único disparador (regla innegociable de ST-006, sin tocar).

**`Views/DeviceActivityBar.swift`** (nuevo): reemplaza `StorageBarView` (D-216) más toda la sección de progreso/pendientes que vivía dispersa en `DeviceGeneralView` — una sola barra SIEMPRE visible. En reposo muestra el uso de almacenamiento con los mismos 5 colores/orden que la barra de "Acerca de" del firmware (Música=acento, Video `#1E3A5F`, Fotos `#FF9500`, Otro `#FFCC00`, Libre=`progress_track` — verificado contra `aura_screens.c:1856-1930`) en vez de los 4 colores de sistema de SwiftUI que usaba la versión vieja — P6 del plan, coherencia visual entre productos. Mientras sincroniza, el mismo espacio se convierte en la barra de progreso con botón **Cancelar** (llama a `LibraryViewModel.cancelSync()`, ST-008). Estados cubiertos: sin dispositivo, en reposo, sincronizando, cancelando, error. **"Verificando" (depende de `DeviceSyncIndex`, no existe todavía) y "Pausado" (no hay mecanismo de pausa, solo cancelar) quedan documentados como pendientes de tandas futuras, no implementados a medias.**

**Simplificación deliberada frente al firmware**: la barra agrupa "Sistema" (peso de `.rockbox/`) dentro de "Otro" en un solo segmento, en vez de separarlos como hace el C. Separarlos de verdad exige que `LibrarySync` mida `.rockbox/` **una vez, al sincronizar**, y lo sume a `sync_summary.cfg` — no recorrer ese directorio en el hilo principal de la UI en cada render. Documentado como mejora de una tanda futura, no un hueco escondido.

**Alcance (§1.2/§6)**: control segmentado "Toda la biblioteca / Solo la selección (N)" dentro de la barra — con N=0 el segundo segmento se deshabilita solo y, si estaba elegido, la selección vuelve a "Toda la biblioteca" automáticamente (nunca hay un camino a "sincronizar nada" sin querer). `LibraryViewModel.selectionForSync` (nuevo `@Published`) la alimenta la vista de biblioteca **activa** — `MediaSectionView` la publica en `onAppear`/`onChange(of: selection)` y la limpia en `onDisappear`, así "Solo la selección" siempre refleja lo que el usuario ve en pantalla en ese instante, sin importar desde qué sección se dispare el sync.

**Verificación**: `swift build` limpio. `swift test` — 284 tests, 2 fallas (la misma excepción conocida de `LiveEnrichmentIntegrationTests`) — sin regresión ni tests nuevos (tanda puramente de UI/wiring sobre lógica ya cubierta en ST-008; este proyecto no tiene arnés de UI testing). `xcodegen generate` + `xcodebuild … build` real → **BUILD SUCCEEDED**. Verificación visual: la app compilada se lanzó y se capturó en el estado "sin dispositivo" — cápsula plana correcta, texto de estado correcto ("Conecta tu iPod para sincronizar."), botón "Actualizar" nuevo en la barra de herramientas. Sin iPod físico conectado durante esta sesión, los estados "en reposo"/"sincronizando"/"cancelando" no se verificaron contra hardware real — a cargo del dueño, mismo criterio que otras verificaciones de hardware de este proyecto (p. ej. ST-005).

**Siguiente tanda**: §4 — `DeviceSyncIndex` (los 5 estados de sincronización por elemento), columna de estado en la biblioteca, hoja "Solo en el iPod", hoja de conflictos previa a sincronizar.

## ST-010 — `DeviceSyncIndex`, columna de estado real, hoja de conflictos, "Solo en el iPod"

**Encargo**: `PLAN-general-sync.md` — tanda 3 de 4 (P11), pedida por el dueño tras la tanda 2 (`ST-009`).

**El problema que cierra esta tanda**: "Sincronizado" (D-202/D-215) solo comprobaba que hubiera un registro en el manifiesto y que el archivo de destino existiera — una canción editada después de sincronizar seguía diciendo "Sincronizado" (falso positivo, el hallazgo central de la Fase 0 de este plan), y un archivo modificado o borrado del iPod por fuera de Aura Studio no se distinguía de uno intacto.

**`Services/DeviceSyncIndex.swift`** (nuevo): `SyncItemState` con los 5 valores de §4.1 (`synced`/`pending`/`changedLocally`/`modifiedOnDevice`/`removedFromDevice`) — ahora compara **dos** huellas, no una: la del archivo **preparado** contra el registro (¿la biblioteca cambió desde el último sync?) y la del **destino real** en el iPod contra la huella que se guardó al copiarlo (los campos `destinationSize`/`destinationModifiedAt` de `SyncManifest` v2, ST-008 — sin esos campos, es decir un registro v1, se trata como `changedLocally` una vez, tal como documentaba §4.2). `DeviceSyncIndexBuilder.build` es lógica pura (testeable sin disco, mismo criterio que `SyncPlanner`); `.scan` hace la única I/O real — una enumeración de `Music/`/`Videos/`/`Photos/`/`Playlists/` fuera del hilo principal — y también produce `orphanedRecords` (registros cuyo origen ya no está en la biblioteca) y `foreignFiles` (archivos que Aura Studio nunca escribió), reconociendo como propias las convenciones sin registro individual (`cover.jpg` de álbum, poster de video, todo `Playlists/`) para no marcarlas "solo en el iPod" por error. `LibrarySync.destinationRelativePath` pasa a `static` para que este nuevo builder lo reuse sin reimplementar el switch de rutas por tipo — una sola fuente de verdad de "a dónde va cada archivo".

**`LibraryViewModel.verifyDevice(at:)`** (nuevo, `Task.detached`, publica `deviceSyncIndex`/`isVerifyingDevice`): se dispara al conectar un iPod Aura, al pulsar "Actualizar" (que ahora sí hace algo real más allá del device-probe de ST-009), y al terminar o cancelar un sync — nunca decide sobre un índice viejo (§4.2).

**Hoja de conflictos previa a sincronizar** (`Views/SyncSheets.swift`, `SyncConflictSheet`) — implementa la decisión más importante del plan (§0.1), no solo la muestra: aparece **solo** cuando `deviceSyncIndex.hasConflicts` es real; sin conflictos, "Sincronizar" sigue siendo un clic. "Conservar los del iPod" (default) **no necesitó ningún código nuevo** — `SyncPlanner` nunca mira el lado del dispositivo, así que "conservar" ya era el comportamiento de siempre; "Reemplazar con la biblioteca" fuerza la recopia vía el parámetro nuevo `LibrarySync.sync(forceRecopySourcePaths:)`. "Quitar del iPod los N huérfanos" es una casilla **desmarcada por defecto** que borra, vía `removeOrphanedSourcePaths`, solo los `sourcePath` que el usuario eligió explícitamente — nunca automático, ni siquiera cuando hay huérfanos y el usuario no toca la casilla.

**Hoja "Solo en el iPod"** (`ForeignContentSheet`, §1.6): lista los `foreignFiles` con su tamaño. "Importar a la biblioteca" reusa `LibraryViewModel.addDroppedFiles` sin código nuevo — el volumen del iPod montado es una ruta de Finder como cualquier otra para `FileManager`; el original se queda en el iPod hasta que el usuario también pida eliminarlo por separado. "Eliminar del iPod" pide confirmación explícita (acción destructiva real).

**`MediaSectionView.statusCell`** usa `deviceSyncIndex` para los 5 estados con símbolo + texto plano (sin fondo, sin translúcidez — mismo criterio que el resto de la tabla): `checkmark.circle` secundario / `arrow.up.circle` en acento / `arrow.triangle.2.circlepath` en acento / `exclamationmark.triangle` naranja (con tooltip) / `minus.circle` secundario (con tooltip). El mecanismo viejo (`syncedSourcePaths`/`refreshSyncedItems()`, D-202) se retiró por completo. `DeviceActivityBar` gana el estado "Verificando" (spinner) y un resumen real por estado en vez de solo un conteo aproximado de pendientes.

**Verificación**: `swift build` limpio. `swift test` — 297 tests (13 nuevos), 2 fallas (la misma excepción conocida de `LiveEnrichmentIntegrationTests`) — sin regresión. `LibraryPipelineIntegrationTests` (con fixtures reales, incluye el camino completo de sync) 2/2 limpias. `xcodegen generate` + `xcodebuild … build` real → **BUILD SUCCEEDED**. Verificación visual: build lanzado y capturado en estado "sin dispositivo", sin regresión frente a la tanda 2 — sin iPod físico en esta sesión, los estados conectado/verificando/con-conflictos no se probaron contra hardware real (a cargo del dueño, mismo criterio que otras verificaciones de hardware de este proyecto).

**Fuera de esta tanda, documentado**: "Pausado" (sin mecanismo de pausa, solo cancelar — desde ST-008). El nombre del dispositivo (`CONTRATO-dispositivo.md`, `.rockbox/aura/device.cfg`) queda para la tanda 4, la última del plan.

## ST-011 — Nombre editable del iPod: `CONTRATO-dispositivo.md`, `device.cfg`, edición in-place

**Encargo**: `PLAN-general-sync.md` — tanda 4 de 4, la última, cerrando el plan completo.

**Por qué no `aura.cfg`**: `aura_settings_save()` del firmware regenera ese archivo **entero** en cada guardado (`creat()` + un `fdprintf` por cada clave que el firmware conoce) — cualquier clave que Studio agregara ahí desaparecería en el primer ajuste que el usuario tocara en el propio iPod. `.rockbox/aura/device.cfg` es un archivo **propio** de este contrato: el firmware nunca lo reescribe.

**`CONTRATO-dispositivo.md`** (nuevo, mismo criterio de copia idéntica que `CONTRATO-formato-tema.md` — la copia en `Aura-Firmware` queda como coordinación pendiente con ese repo, no bloqueante): formato `clave: valor` (mismo parser que `aura.cfg`/`sync_summary.cfg`), 4 claves (`contract_version`/`device_id`/`device_name`/`device_name_updated_at`). Límite de `device_name`: **32 caracteres y ≤ 48 bytes UTF-8** — deriva del buffer real de 63 bytes que usan todos los lectores `.cfg` del firmware (`read_line`) y coincide con los precedentes ya existentes (`style_id[33]` de temas, D-289; `playername.txt` de IAP, 31 bytes útiles). `CONTRATO-firmware-studio.md` sube a **v3**: fila nueva en la tabla de §D, ítem nuevo en "qué queda pendiente" (el firmware podría mostrar `device_name` en el slot fijo "Mi iPod" de "Acerca de" algún día — documentado como consumo esperado, no un compromiso).

**`Services/DeviceNameStore.swift`** (nuevo): `DeviceIdentity` + lectura/escritura de `device.cfg` + `sanitize(_:)` — recorta y colapsa espacios, quita caracteres de control y saltos de línea, quita Unicode **fuera del BMP** (emoji: el iPod no tiene glifo, mostraría cajas) y avisa si quitó alguno, trunca a los límites de arriba. `defaultName()` = `"iPod de <NSFullUserName()>"`, con fallback a `NSUserName()` y después `"iPod"` a secas — nunca se queda sin nombre que ofrecer.

**`AuraDevice.deviceIdentity`/`displayName`** (nuevo): `AuraDeviceProbe.probe` lee `device.cfg` igual que ya lee `sync_summary.cfg`. `ContentView.ensureDeviceNameAssigned(for:)` le asigna el default a un iPod con Aura que todavía no tiene nombre la **primera vez que lo ve**, y lo guarda de inmediato en el dispositivo (para que otra Mac lo vea igual). `AppPreferences.knownDeviceNames` es solo el reflejo local por dispositivo — el iPod manda siempre que está conectado. La barra lateral usa `displayName` en vez de `volumeName`.

**`Views/DeviceNameField.swift`** (nuevo): edición in-place en `DeviceGeneralView.header` — clic para editar, Enter confirma, Esc cancela, perder el foco también confirma (no deja el campo "colgado" a medio editar). Editable **solo con Aura instalada** (`device.cfg` vive bajo `.rockbox/aura/`, que recién existe ahí); sin Aura, sigue mostrando la etiqueta de volumen de siempre, sin edición. El saneo corre síncrono en la vista (puede avisar de inmediato "El iPod no puede mostrar emoji; se guardó sin ellos.") antes de pasarle el nombre ya limpio al guardado asíncrono.

**Verificación**: `swift build` limpio. `swift test` — 311 tests (14 nuevos), sin fallas en esta corrida (la excepción conocida de `LiveEnrichmentIntegrationTests` es intermitente por red real, no aplica siempre). `xcodegen generate` + `xcodebuild … build` real → **BUILD SUCCEEDED**. Verificación visual: build lanzado y capturado en estado "sin dispositivo" — sin regresión (el campo editable solo aparece con Aura instalada, correctamente ausente en ese estado). Sin iPod físico en esta sesión, la edición in-place y la asignación del nombre por defecto no se probaron contra hardware real — a cargo del dueño.

**Cierra `PLAN-general-sync.md`** — las 4 tandas (`ST-008`, `ST-009`, `ST-010`, `ST-011`) quedan completas. El plan pasa a `docs/plans/archivo/` con encabezado `ESTADO: EJECUTADO`.

## ST-012 — Marcador de sincronización para el firmware, letras `.lrc` en el iPod, y las carátulas fuera de Imágenes

**Encargo** (2026-08-17, cross-repo con `Aura-Firmware` D-293, decisiones cerradas en el propio encargo; orden de despliegue: firmware primero, después Studio). Tres síntomas, tres causas — todas confirmadas con archivo:línea antes de tocar nada:

**§A — "las canciones están en el iPod pero no aparecen en Aura"**. Studio ya intentaba resolverlo a ciegas: `LibrarySync.triggerFirmwareDBRebuild()` borraba `database_*.tcd` al terminar cada sync con copias, para forzar al firmware a levantar la base desde cero (y mientras tanto el iPod quedaba sin base). El firmware, por su lado, nunca re-escaneaba solo (D-293 explica el porqué en `tagcache.c`). Ahora `LibrarySync.sync` marca qué secciones tocó **este** sync (copias, reubicaciones y borrados de huérfanos; también en un sync cancelado a medias, porque lo copiado ya está en el disco) y deja **`/.aura/sync-pending.json`** (`SyncPendingMarker`: `version: 1`, `timestamp` ISO-8601, `changes.{music,video,images}`, `attempts: 0` — el contador lo escribe el firmware) al final, **acumulando** las secciones de un marcador anterior que el firmware no alcanzó a procesar. `FirmwareCapabilities.supportedSyncMarkerVersion` lee `sync_marker_supported` de `aura.cfg` (clave de solo escritura del firmware, misma convención que `theme_format_supported`): con un firmware que la anuncia, **ya no se borra la base** — la vieja sigue usable mientras el firmware reconstruye, y "posponer" tiene sentido; sin la clave (firmware anterior a D-293) se conserva el borrado previo *además* del marcador, que un firmware viejo ignora y uno nuevo aplica en su primer arranque. Ninguna combinación de versiones rompe (contrato §4.4). `SyncResult.syncMarkerWritten` para los tests. Copia de Studio verificada de paso: `copyFileTransactionally` es streaming por bloques de 4 MB a un temporal + `moveItem` — completa por construcción — y **no preserva fechas**, lo que hace válida la detección por `mtime` de tagcache para todo lo que Studio escribe (documentado como la única premisa del contrato que depende de cómo copia Studio).

**§B — "las letras no llegan al iPod"**. Studio traía la letra de LRCLIB (`LRCLIBClient`, solo `syncedLyrics`), la guardaba en `biblioteca.json` (`TrackMetadata.syncedLyrics`) y la escribía como `.lrc` **solo en su `.preparados/` local** (`LibraryViewModel.prepareMusic`) — `LibrarySync` nunca la copiaba al iPod (grep de `lrc` en `Services/`: cero). El firmware busca **una sola ruta**: el hermano del audio con la extensión reemplazada por `.lrc` (`aura_nowplaying.c`, `derive_sibling_path()`), y `aura_lrc.c` descarta líneas sin `[mm:ss]` (letra plana = sin letra, ícono del Modo 4 al 50 %). `LibrarySync.writeLyricsSidecars` sincroniza el **estado** de las letras en cada pasada, no solo con lo recién copiado: escribe `<base>.lrc` UTF-8 si hay letra (sincronizada o plana — el firmware define qué hacer sin marcas de tiempo), la reescribe solo si cambió, la borra si la canción ya no tiene letra, y la borra/reubica junto con la canción (huérfanos elegidos por el usuario, reubicaciones por cambio de layout) — **nunca huérfanos**. Una letra que llega por enriquecimiento después de que la canción ya estaba en el iPod llega igual (el diferencial no recopia el audio; el `.lrc` sí). `DeviceSyncIndexBuilder.ownedDevicePaths` registra el `.lrc` como propio (si no, cada letra aparecería en "Solo en el iPod"). `LRCLIBClient` decodifica `plainLyrics` como respaldo cuando no hay `syncedLyrics`. Sin cambio de contrato para el firmware (D-293 §B: sin ajuste).

**§C — "carátulas contaminando la biblioteca de Imágenes"** (bug de Studio, no del firmware; el módulo de imágenes del firmware no se tocó). Causa: `LibraryViewModel.addDroppedFiles` clasificaba **solo por extensión** (`LibraryItemKind.classify`) — el `cover.jpg` de un álbum soltado entero entraba como entrada de Imágenes (`LibraryFolderDropTests` lo afirmaba como comportamiento esperado: "mp3 + flac + jpg = 3"), pasaba a `<biblioteca>/Imágenes/<Colección>/` y terminaba en `/Photos/cover.jpg` del iPod, pisándose entre álbumes (`Photos/` es plano). El enriquecimiento no contamina (las portadas descargadas van a `.portadas/`, carpeta con punto que el importador ignora); la única otra vía era reimportar `Photos/cover.jpg` desde el iPod (`ForeignContentSheet`). Ahora: **ingesta por módulo** — `addDroppedFiles(_:into:)` recibe la sección que recibió el drop y solo importa archivos de ese tipo (`MediaSectionView` pasa su `kind`); sin destino (reimportación desde el iPod) importa de todo salvo carátulas. `CoverArtAssets` (puro, testeable) decide qué imagen es carátula/póster: vive en un directorio que en el **mismo** drop trae **audio** (un álbum entero, se llame como se llame la imagen — solo audio define "carpeta de álbum": una carpeta de fotos de un viaje con clips `.mov` sigue siendo de fotos), es el póster de un video del drop (mismo nombre base), o tiene nombre de carátula (`cover`, `folder`, `front`, `album*`, `AlbumArt_*`, `artwork`… — los mismos que busca el firmware más sinónimos) y el drop no fue dirigido a Fotos (soltarla a propósito en Fotos gana, salvo que en disco conviva con audio). **Carátula como asset asociado** (contrato §2): `LocalTagReader.readTag` toma la carátula de carpeta como portada de la canción cuando no hay arte embebido — un álbum arrastrado con su `cover.jpg` conserva la portada aunque ya no cuente como foto. **Migración con confirmación**: `coverContaminationCandidates()` (entradas de Imágenes con nombre de carátula; **nunca** una "Fotografías" con EXIF de cámara; evidencia fuerte = convive con música de la biblioteca o con audio en disco, débil = solo el nombre) → banner en Fotos **una vez por instalación** (`coverContaminationReviewShown`, mismo patrón que `legacyMetadataBannerShown`) → `CoverContaminationSheet` con vista previa, preseleccionadas solo las de evidencia fuerte, "Quitar de Imágenes" = `deleteItems` (quita la entrada y la copia interna de la biblioteca; **nunca** el archivo original del usuario) — nada se borra solo. Colocación en el iPod **sin cambios**: `cover.jpg` en la carpeta del álbum (`writeAlbumCovers`) o embebida (`perTrack`), exactamente donde `find_albumart` del firmware la busca; Cover Flow verificado del lado firmware (D-293 captura `04`).

**§D — contrato**: `docs/contracts/library-layout-v1.md` copiado **byte-idéntico** del firmware (canónico allá): estructura de directorios en el iPod, carátulas, `.lrc`, marcador §4 (esquema, comportamiento del firmware, `sync_marker_supported`, tabla de combinaciones de versiones), referencias a los demás contratos. `CONTRATO-firmware-studio.md` sube a **v4** y **reconcilia las dos copias**, que habían divergido en direcciones opuestas: la del firmware tenía §D.1 (`Photos/`, D-291) y esta la fila `device.cfg` (v3, ST-011); desde v4 ambas traen todo — y `CONTRATO-dispositivo.md`, que ST-011 declaraba "copia idéntica en Aura-Firmware" pero solo existía aquí, quedó copiado allá. Los cuatro contratos hermanos verificados byte-idénticos con `cmp`. Regla nueva en `CLAUDE.md`.

**Verificación**: `swift build` limpio; **`xcodebuild` real → BUILD SUCCEEDED** — y atrapó un bug real que `swift build` no ve (D-041 otra vez): un `static let` con `ISO8601DateFormatter` no pasa el chequeo `Sendable` de Swift 6 del proyecto real; ahora es un formateador por llamada. `swift test` — **343 tests** (41 nuevos: `SyncMarkerTests` 9, `LyricsSidecarSyncTests` 9, `CoverArtAssetsTests` 14, más `LibraryFolderDropTests` actualizado a la conducta corregida), 2 saltados (sin fixtures), la única falla es la conocida `LiveEnrichmentIntegrationTests` (red real, ST-002) — sin regresión. **Extremo a extremo con el firmware real** (sin iPod físico en esta sesión): el `LibrarySync` de esta app, ejecutado desde su suite contra el `simdisk` del simulador del firmware como volumen montado, sincronizó 3 canciones + `cover.jpg` + un `.lrc` + el marcador (con `sync_marker_supported` → la base no se borró); el simulador arrancó, reconstruyó por el marcador y las 3 aparecen en Canciones; una segunda pasada "solo letras" (sin recopiar audio, sin marcador nuevo) dejó los 3 `.lrc` y el Modo 4 las muestra — capturas `08`/`09` en `Aura-Firmware/docs/screenshots/library-sync/`. La prueba en hardware (sincronizar desde la app → expulsar → arrancar el iPod) queda a cargo del dueño.

**Fuera de esta pasada, a propósito**: sin UI nueva por el marcador (no hace falta: el firmware muestra su propia pantalla); la migración de carátulas no reasigna la portada a las canciones existentes (para eso ya está "Volver a leer etiquetas", que ahora también toma la carátula de carpeta); el firmware sigue ignorando letra plana (documentado en el contrato como evolución del firmware sin cambio de contrato).

## ST-013 — Propiedad del nombre del iPod: solo la primera Mac que lo nombra puede cambiarlo (`device_owner`, contrato v2); el firmware ya lo muestra

**Encargo** (2026-08-17, cross-repo con `Aura-Firmware` D-294): "Aura Studio ya tiene el nombre del iPod; que el firmware lo adquiera. Aunque el iPod se sincronice con varias computadoras, solo adquiere el nombre de la primera y solo desde ahí se puede volver a cambiar." La regla de propiedad no cabía en `CONTRATO-dispositivo.md` v1 (ST-011: `device_id`, `device_name`, fecha — nada decía quién nombró): el contrato sube a **v2** (canónico en el firmware, copiado idéntico aquí) con la clave `device_owner` = `AppPreferences.installationID` de la instalación que nombró el iPod la primera vez — el mismo identificador de instalación que ya usa `SyncRecord.writtenBy`, así que "reinstalar Aura Studio pierde la propiedad" es el mismo criterio ya aceptado para los registros de sync, no una regla nueva. Sin "transferir propiedad" a propósito (la salida es borrar `device.cfg` del iPod o reinstalar Aura). Línea `device_owner: ` + UUID = 50 bytes, dentro del límite de 63 del `read_line()` del firmware — verificado por test.

**Studio**: `DeviceIdentity.ownerInstallationID` (+ `canRename(from:)`), `DeviceNameStore` parsea/serializa `device_owner` y escribe siempre `contract_version: 2` (un archivo v1 se lee igual, sin propietario, y se reescribe como v2 en el próximo guardado). `ContentView.ensureDeviceNameAssigned` (el primer nombrado, con el default `iPod de <usuario>`) escribe el propietario; `renameDevice` conserva el propietario existente o **reclama** un archivo v1 con el propio `installationID`, y rechaza el cambio si el propietario es otro (red de seguridad: la UI ya no ofrece el campo). `DeviceGeneralView` recibe `canRenameDevice`: para otra instalación el nombre se muestra en texto plano con la explicación *"El nombre de este iPod se puso desde otra Mac; solo desde ahí se puede cambiar."* — se ve, no se edita, y nunca se reescribe el archivo. Fila `device.cfg` de `CONTRATO-firmware-studio.md` actualizada (sin subir su versión: la semántica nueva vive en el contrato hermano). Regla nueva en `CLAUDE.md`.

**Firmware (D-294, para el registro cruzado)**: lee solo `device_name` al arrancar y al volver de USB y lo muestra en el slot "Mi iPod" de "Acerca de" — el consumo que el contrato v1 §E dejaba anotado como intención; el literal queda de respaldo. Ignora `device_owner`.

**Verificación**: `swift build` limpio, `xcodebuild` BUILD SUCCEEDED, `swift test` **348 tests** (5 nuevos en `DeviceNameOwnershipTests`: ida y vuelta del propietario y v2, archivo v1 sin propietario reclamable, solo el propietario renombra, `device_owner` vacío = ausente, la línea `device_name` sigue tal cual para el firmware; y el test v1 existente actualizado a la versión vigente), única falla la conocida de red. Sin iPod físico: la prueba real (dos Macs, o reinstalar Studio y ver el campo bloqueado) queda a cargo del dueño.

## ST-014 — Primer pin real de `FIRMWARE_VERSION` contra un Release público: `v0.2.0-beta`

**Encargo** (2026-08-17, cross-repo con `Aura-Firmware` D-296): "actualiza FIRMWARE_VERSION al nuevo release". Hasta ahora `FIRMWARE_VERSION` **no existía** como archivo real — solo su plantilla (`FIRMWARE_VERSION.example`), porque `Aura-Firmware` no había tenido ningún Release público hasta hoy (`v0.1.0-beta`, después `v0.2.0-beta`). Este es el primer pin real.

**Hecho**: `FIRMWARE_VERSION` nuevo, `tag=v0.2.0-beta` + los 4 hashes SHA-256 (`rockbox.ipod`/`rockbox.zip`/`mks5lboot`/`bootloader-ipod6g.ipod`), verificados dos veces por separado antes de escribirlos: contra el `checksums.txt` descargado directo del Release público (`gh release download --pattern checksums.txt`, no la copia local de la sesión que armó el release en `Aura-Firmware`) y de nuevo por `scripts/fetch-firmware.sh` (modo Release real, sin `--from-dir`) al poblar `Vendor/firmware-dist/` — los 4 `shasum -c` dieron `OK`. `Generated/AuraPalette.swift` comparado byte a byte contra el del Release nuevo (`diff`): **sin cambios** — ningún token de color cambió entre `v0.1.0-beta` y `v0.2.0-beta`, así que no hizo falta reemplazarlo (la regla del contrato de "nunca editarlo a mano" sigue aplicando; no hubo edición, solo verificación de que ya coincidía).

**`CONTRATO-firmware-studio.md` §E** (tabla de compatibilidad, no es la sección D protegida — el propio contrato documenta que esta tabla "se actualiza en cada release de cualquiera de los dos lados"): fila nueva `0.1.2 (Aura Studio) | v0.2.0-beta | v4`; la fila `0.1.x` anterior se marca `≤ 0.1.1 (histórico)` en vez de borrarse. `docs/guia-desarrollo.md` corregido de paso: seguía diciendo "mientras no exista un Release público (estado actual)" — ya no es cierto, `--from-dir` sigue documentado pero como modo de desarrollo explícito, no como el único camino disponible.

**Verificación**: `swift build` limpio (nada que recompilar — ningún `.swift` cambió). `swift test` **348/348** salvo la falla conocida de `LiveEnrichmentIntegrationTests` (red real, ST-002, intermitente, sin relación).

**Pendiente, fuera de esta pasada**: `AuraUpdateChecker`/`GitHubReleaseChecker` (ST-006) siguen comparando por hash SHA-256 del `rockbox.ipod` embebido vs. el instalado como fuente de verdad — no dependen de este pin para funcionar, así que no se tocaron; el pin es solo para `fetch-firmware.sh` y para que la UI muestre el tag como referencia legible.

## ST-015 — El botón "Sincronizar" se deshabilita sin firmware Aura, para no desgastar el disco escribiendo en un iPod que nunca va a leer esos archivos

**Encargo**: "Aura Studio al detectar que el iPod no tiene el firmware Aura, deberá desactivar el botón de sincronización para impedir desgastar el disco."

**Hallazgo**: de las cuatro vías que pueden disparar un sync real, tres ya estaban correctamente cerradas con `device.isAura` (el comando de menú ⇧⌘S vía `ContentView.canSync`, "Sincronizar la selección" del menú contextual en `MediaSectionView`, y el bloqueo de las secciones Música/Video/Fotos en la barra lateral). La única que quedaba abierta era el botón "Sincronizar" de `DeviceActivityBar` (dentro de General) — se mostraba habilitado con cualquier firmware (`.stock`, `.rockbox`, `.empty`), y `DeviceGeneralView.performSync` solo comprobaba `guard let device`, sin mirar `firmware`.

**Hecho**: `DeviceActivityBar` — el botón se deshabilita también cuando `device?.isAura != true` (además de verificando/selección vacía), y `statusText` ahora dice "Instala Aura en este iPod para poder sincronizar." en vez de caer al texto genérico de `deviceSyncIndex`. `DeviceGeneralView.performSync` gana el mismo `guard` (`device.isAura`) como segunda barrera, defensa en profundidad ante cualquier otra vía futura que llame a `performSync` sin pasar por el botón.

**Verificación**: `swift build` limpio; `xcodegen generate` + `xcodebuild … build` real → **BUILD SUCCEEDED**. `swift test` 348/348 salvo la falla conocida de `LiveEnrichmentIntegrationTests` (red real, ST-002) — sin regresión; sin tests nuevos (mismo criterio que ST-009: UI pura, condición de un solo booleano ya cubierta por el patrón `isAura` que sí tiene cobertura en otros call sites). Verificación visual: el iPod real del dueño estaba conectado en el momento de la prueba, con Aura instalado — el botón apareció correctamente habilitado (caso feliz confirmado contra hardware real); el caso deshabilitado (firmware original/Rockbox/vacío) se verificó por lectura de código, no contra hardware, porque no había a mano un iPod sin Aura para conectar.

## ST-016 — Detección precisa del firmware: lectura real por USB, evidencia de arranque, y el instalador ya no confía en un archivo copiable

**Encargo** (2026-08-17): "que Aura Studio detecte de manera precisa qué firmware tiene instalado el iPod. El hardware conectado solo tiene el firmware original de Apple, pero la app lo detecta como dual boot con Aura instalado, siendo que solo se le copió la carpeta `.rockbox` para probar. ¿Se puede hacer una lectura real?"

**Respuesta a "¿lectura real?"**, verificada contra el código del firmware y contra el iPod del dueño en vivo (`ioreg`, solo lectura):
- **Del bootloader en la NOR: no.** `mks5lboot --bl-inst` escribe solo la NOR por DFU (`utils/mks5lboot/dualboot/dualboot.c` no incluye código de disco/ATA), no deja rastro en el disco y no existe modo de consulta (`dfuapi_req_upload` existe y nunca se llama). Solo el propio iPod "sabe" (tonos del piezo).
- **Del firmware que está corriendo: sí, por los descriptores USB.** Modo disco de Apple: `Apple Inc.` / `iPod` / serial 16 hex. Rockbox/Aura (y su bootloader en modo USB): `Rockbox.org` / `Rockbox media player` (`usb_core.c:141-145`, Aura no lo cambia) / serial 40 hex derivado del ATA. VID/PID son los mismos en ambos (`0x05AC`/`0x1261`, `ipod6g.h:256-257`) — no distinguen firmware, pero identifican al aparato con exactitud. El INQUIRY SCSI **no** es firma: bajo Rockbox sale del IDENTIFY ATA del disco físico (`usb_storage.c:1460-1473`); bajo Apple dice `Apple`/`iPod`/`1.62`.
- Studio no leía **ninguna** propiedad USB (solo vendor/model/tamaño por DiskArbitration). `AuraDeviceProbe` decidía por existencia de archivos, y "dual boot" era un derivado (`.rockbox` + `iPod_Control/`), no una lectura. Y la decisión de más riesgo — el instalador **saltándose el flasheo del bootloader** — aceptaba `aura.cfg` (copiable) como prueba (`InstallerViewModel:332`).

**Hecho**:
- `Services/USBDeviceIdentity.swift` (nuevo): `USBDeviceIdentity` (vendor/product/serial/VID/PID), `RunningFirmware` (`.apple`/`.rockboxFamily`/`.unknown`, clasificación pura), `USBDeviceIdentityReader` (sube por IOKit desde el `IOMedia` del disco entero hasta el nodo de dispositivo USB — medido en hardware: el primer nodo con VID/PID es la *interfaz*, sin vendor ni serial; el de dispositivo, un nivel arriba, trae las tres cadenas; se sigue subiendo y se conserva lo mejor visto).
- `DiskModeInfo`/`DiskCandidateInfo` ganan `usb` (y `DiskModeInfo` `volumeUUID`); `DiskArbitrationMonitor.diskModeInfo` y `IPodDiskIdentifier.currentCandidates` los pueblan. **Criterio de identidad nuevo** en `matchesIPodCriteria`: VID/PID `0x05AC`/`0x1261` (removible+externo+tamaño plausible siguen siendo obligatorios) — es la única señal que sobrevive cuando el USB lo atiende Aura/Rockbox con un disco Toshiba/iFlash cuyo INQUIRY no dice "iPod" (antes: invisible). Regla actualizada en `CLAUDE.md`.
- `AuraDevice` separa dos hechos: `firmware` (archivos; `.rockbox(hasBooted:)` nuevo con `.resume.cfg`/`config.cfg` como rastro, `.aura(hasBooted:)` con `aura.cfg`) y `runningFirmware` (USB). `isAura` **exige evidencia de ejecución** (USB atendido por Rockbox/Aura, o `aura.cfg`); `hasAuraFiles` es "solo archivos". `isDualBoot` exige `rockboxFamilyVerified`. `canSkipBootloaderFlash(diskRecordedAsVerified:)` concentra la regla del instalador.
- `AppPreferences.bootloaderVerifiedDisks` (clave: UUID del volumen — estable entre modos porque vive en el disco — o serial USB): se anota cuando el flasheo termina bien (`--bl-inst` + salió de DFU) o cuando `IPodMonitor` ve ese disco con Rockbox/Aura atendiendo el USB; se borra al restaurar (`--bl-uninst`).
- **Instalador**: salta el DFU solo si el USB lo atiende Rockbox/Aura ahora, o si hay rastro de arranque **y** registro local de ese disco. Un archivo solo ya no basta. D-179 ("instalar sobre Rockbox no obliga a flashear") queda supeditado a esa evidencia; "Reintentar con flasheo" (D-273) sigue como red. Un usuario sin registro local (instalación previa a ST-016) puede saltarse el DFU conectando el iPod encendido con Aura.
- Textos de General/Instalador dicen lo que se sabe y lo que no ("Archivos de Aura en el disco, pero el iPod está corriendo el firmware de Apple y Aura nunca ha arrancado aquí — no hay evidencia de que esté instalado"; "Instalar Aura" en vez de "Reinstalar"; `installNote` anticipa si habrá DFU con la misma función que decide el instalador). Regla nueva en `CLAUDE.md`.

**Verificación**: `swift build`; `xcodegen generate` + `xcodebuild` → **BUILD SUCCEEDED**. `swift test` **368** (20 nuevos: `USBDeviceIdentityTests` 6, `BootloaderVerifiedDisksTests` 4, `IPodDiskIdentifierTests` +3, `AuraDeviceProbeTests` +7 incluido el caso exacto del dueño), única falla la conocida de red (ST-002). **En hardware real**: el lector, ejecutado con el código de la app contra el iPod conectado, devolvió `Apple Inc.` / `iPod` / `000A270013923F13` / `0x05AC:0x1261` → `.apple`; la app compilada mostró "Firmware original de Apple", biblioteca bloqueada, "Sincronizar" deshabilitado. No se probó en vivo el caso "USB atendido por Aura" (el iPod del dueño no tiene Aura hoy) ni el salto/no-salto de DFU del instalador — quedan a cargo del dueño.

**Fuera de esta pasada, documentado**: la rama de formateo del instalador (no-FAT32 / sin sistema de archivos) sigue pasando por DFU siempre, aunque `runningFirmware == .rockboxFamily` ya permitiría saltárselo — se dejó igual para no ampliar el radio en un camino no probado en hardware. Mejora firmware-side posible, no bloqueante: que `aura.cfg` incluya el serial de la NOR (`syscfg`) para poder cruzarlo con el serial USB y detectar un `aura.cfg` copiado de *otro* iPod.

## ST-017 — Instalación "Solo Aura": el flasheo va primero; los archivos se copian después, por el modo USB del bootloader

**Encargo** (2026-08-17): el flujo Solo Aura hacía Instalador → Modo de arranque → Solo Aura → conectar → *copiar archivos* → DFU → flashear → (error). "Instala ahora antes de siquiera flashear no instala el firmware, solo pega los archivos; sin el flasheo es una pérdida de tiempo. Lo correcto: formatear en FAT32 (aún con el firmware original) → DFU → flashear y cargar el bootloader → resetear el iPod → ahora sí, instalar Aura."

**Por qué el orden nuevo es realizable sin pasos frágiles** (verificado en `bootloader/ipod-s5l87xx.c` del firmware): cuando el bootloader no encuentra partición o `rockbox.ipod`, cae en `fatal_error(ERR_RB)`, que **entra solo a `usb_mode()`** ("Bootloader USB mode"): espera el cable (ya está), expone el disco por USB con los descriptores de Rockbox, y al desconectar queda en "Hold MENU+SELECT to reboot". No hay que apretar nada para entrar. El "diseño anterior" que `InstallerStep` documentaba como frágil (DFU primero, disco después via un reconecte a modo bootloader) dependía de detectar ese modo por el nombre de media — hoy `runningFirmware == .rockboxFamily` (ST-016) lo reconoce por USB, sin ambigüedad. `--single` no impone orden por sí mismo (`mks5lboot` README: escribe la NOR "sin comprobación previa").

**Hecho**:
- `InstallPlanner` (nuevo, puro): decide la primera acción al confirmar el dispositivo. **Solo Aura** con flasheo pendiente → `formatThenFlash` (siempre se formatea limpio: en este modo no hay partición de firmware de Apple que conservar; con Aura *verificada* en el disco → `enterDFU` directo, se conserva la biblioteca; disco ya preparado en esta corrida → `enterDFU`, sin volver a pedir contraseña). Dual boot → `copyFiles` primero (sin cambio) o `refuseDualBootRequiresWinpod` (D-185). Con evidencia de bootloader (ST-016) o flasheo ya hecho en la corrida → solo copiar.
- `InstallerViewModel`: `flashFirst`, `bootloaderFlashedThisFlow`, `diskPreparedThisFlow`. Tras formatear en Solo Aura → DFU directo. Tras el flasheo con éxito → paso nuevo **`.awaitingBootloaderUSB`**: espera el disco; si llega con `runningFirmware == .apple` (con `--single` Apple ya no debería arrancar) → error nuevo `bootloaderNotApplied`, y el reintento vuelve a DFU sin reformatear; si llega FAT32 → copia; si llega sin FAT32/sin sistema de archivos (se entró directo en DFU) → formatea y copia. Al terminar la copia → expulsar → `.done`. Confirmar ya en DFU también toma este orden (antes terminaba en "Listo" sin copiar nada). `retry()` conserva lo ya hecho en la corrida.
- Vistas: `AwaitBootloaderUSBView` (qué esperar, SELECT+MENU si no reaparece en ~30 s, estado en vivo); `InstallerWizardView` con el orden de pasos por modo y la barra de progreso coloreada **por posición** (los dos órdenes comparten el enum); `DoneView` avisa que en este camino el iPod queda en "Bootloader USB mode" y hay que reiniciarlo con SELECT+MENU (no reinicia solo), y no muestra la advertencia de "solo asumimos el bootloader" cuando se grabó en la corrida; `BootModeView` anuncia el orden.

**Verificación**: `swift build`; `xcodegen generate` + `xcodebuild` → **BUILD SUCCEEDED**; `swift test` **376/376** (8 nuevos en `InstallPlannerTests`, incluido el caso exacto del encargo). Visual: la app compilada con el iPod del dueño conectado (firmware de Apple + carpeta `.rockbox` copiada a mano) mostró la descripción de ST-016 en General. **El flujo completo Solo Aura no se ejecutó en esta sesión** (es destructivo: formatea y borra el arranque de Apple del iPod del dueño) — la prueba real queda a cargo del dueño, que además debe reportar el texto exacto del error que veía en el paso de flasheo si vuelve a aparecer: el reorden no cambia lo que hace `mks5lboot`, así que un error de DFU (D-191, `deviceStuckInDFU`, agentes AMP/`deviceinterfaced`) puede seguir necesitando su propia causa.

## ST-018 — Pin a `v0.2.1-beta` + centinela de contenido de `rockbox.zip`: un checksum correcto no basta

**Encargo** (F0.4 de `PLAN-sync-media-hardening.md`, carpeta padre, cross-repo con `Aura-Firmware` D-297/D-298/D-299). `Aura-Firmware` publicó `v0.2.1-beta`, un PATCH que corrige `rockbox.zip`: desde que los repos se separaron, `package_dist.sh` nunca corría `make zip`, así que los dos Releases públicos hasta ese momento (`v0.1.0-beta`, `v0.2.0-beta`) traían un `rockbox.zip` **sin códecs ni plugins** — el checksum del archivo era consistente (coincidía con lo que el propio Release publicaba), así que `BundledArtifacts.verifyAll()` nunca lo hubiera detectado: no es un problema de transferencia, es que lo publicado ya estaba incompleto.

**Pin actualizado**: `FIRMWARE_VERSION` → `tag=v0.2.1-beta` + los 4 hashes SHA-256, verificados **dos veces por separado** antes de escribirlos (mismo criterio que ST-014): contra `checksums.txt` descargado directo del Release público (`gh release download --pattern checksums.txt`, no una copia local de la sesión que armó el release en `Aura-Firmware`) y de nuevo por `scripts/fetch-firmware.sh` en modo Release real — los 4 `shasum -c` dieron `OK`. `Generated/AuraPalette.swift` comparado byte a byte contra el del Release nuevo: **sin cambios**, no hizo falta reemplazarlo.

**Centinela de contenido nuevo** (`BundledArtifacts.swift`): un checksum correcto certifica que el archivo llegó intacto, **no** que su contenido sea el esperado — el bug real de D-297 lo hubiera dejado pasar sin problema. `verifyRockboxTreeContents(at:)` lista `rockbox.zip` con `/usr/bin/unzip -l` (sin dependencias nuevas, siempre presente en macOS) y confirma que están `.rockbox/rocks/viewers/mpegplayer.rock` y `.rockbox/codecs/mpa.codec` — dos entradas representativas (un plugin real y un códec real): si estas dos están, el resto de `make zip` también corrió. `verifyAll()` lo llama justo después de que el checksum de `rockbox.zip` pasa. Error nuevo `InstallerError.incompleteRockboxTree(missing:)`, mensaje en español que aclara que no es un problema de la conexión del usuario. Un zip incompleto ya **no se instala**.

**`CONTRATO-firmware-studio.md` §E**: fila nueva `0.1.2 | v0.2.1-beta (PATCH, sin cambio de contrato) | v4`; la fila `v0.2.0-beta` anterior se marca `(histórico)` con la nota de que traía el `rockbox.zip` incompleto. De paso, la copia de `Aura-Firmware` (que desde D-296 se había quedado con el placeholder viejo `0.1.x` sin actualizar — nota pendiente documentada ahí mismo) se sincronizó completa con la de aquí (`cmp` limpio) en la misma pasada, ya que este es justamente el trabajo cross-repo que esa nota esperaba.

**Verificación**: `swift build` limpio (`InstallerStep.swift`, `BundledArtifacts.swift` recompilados). `swift test` **378 casos, 376/378** — únicas 2 fallas las conocidas de `LiveEnrichmentIntegrationTests` (red real, ST-002, intermitente, sin relación); los 2 tests nuevos de `BundledArtifactsTests` (zip fixture real armado con `/usr/bin/zip`: con las dos entradas requeridas pasa, sin ellas lanza `incompleteRockboxTree` con la lista exacta de lo que falta) pasan. No se corrió `xcodebuild`/`xcodegen` en esta pasada (sin cambios a `project.yml` ni archivos nuevos que requieran regenerar el `.xcodeproj` — `Package.swift` basta para verificar). Pendiente, a cargo del dueño: F0.5 del plan (protocolo de hardware con el iPod real, "Actualizar Aura" desde esta build hacia `v0.2.1-beta`).

## ST-019 — PARTE 1A del plan, adelantada por un reporte real: `LibrarySync.sync()` abortaba entero por UN archivo, arrastrando cinco síntomas más

**Encargo**: el dueño reportó en vivo, usando la build de esta sesión, una sincronización real que se cortó con `"The item couldn't be saved because the file name "Two, Three Karate Moves" is invalid"` — pese a que ya había copiado 700+ canciones (7.49 GB reales en el disco). Además: el panel "En el iPod" seguía diciendo "Todavía no sincronizaste este iPod con Aura Studio" y "Contenido solo en el iPod (9)"; el uso de disco se veía como "Otro" en vez de "Música"; el botón "Expulsar" no expulsaba de verdad; el firmware no se había actualizado; "Acerca de" en el iPod decía "Aún no te has sincronizado" pese a haber sincronizado; "Rehacer base de datos" no ayudó; y solo los álbumes de Gorillaz mostraban carátula. Se pidió entender la biblioteca real (`/Users/ricolinos/Documents/Aura Library`) para asegurar que la sincronización sea correcta.

**Diagnóstico** (tres investigaciones en paralelo, solo lectura, antes de tocar código): **una sola causa raíz explica cinco de los siete síntomas**. `LibrarySync.sync()` (`LibrarySync.swift:501`, dentro de `planLoop`): `let outcome = try copyFileTransactionally(...)` era un `try` crudo, sin `do/catch` — cualquier error de UN archivo propagaba fuera de `sync()` entero, saltándose TODO lo que corre después del loop: `writeAlbumCovers`, `writePlaylists`, `writeSummary` (que escribe `sync_summary.cfg`, la única fuente de `device.librarySummary`), `writeSyncMarkerIfNeeded` (el marcador `/.aura/sync-pending.json` que el firmware lee) y `removeInProgressMarker`. El manifiesto SÍ queda al día por archivo (`saveManifest` corre dentro del loop, después de cada copia) — por eso el uso de disco real subía aunque Studio no se enterara.

De ahí en cascada, **sin bugs adicionales**: `DeviceGeneralView.swift` muestra "Todavía no sincronizaste" cuando `device.librarySummary == nil` (nunca se escribió `sync_summary.cfg`); `DeviceActivityBar.swift` calcula `Otro = usedBytes - music - video - photo`, y con el resumen nulo, `music/video/photo` quedan en `0` — todo el uso real cae en "Otro"; en el firmware, `draw_about()` (`aura_screens.c:2972`) muestra `AURA_STR_ABOUT_NO_SYNC` cuando `aura_manifest_load()` no encuentra `sync_summary.cfg` — el mismo archivo, nunca escrito por el mismo motivo; "Rehacer base de datos" solo toca tagcache (música), nunca `sync_summary.cfg` — no podía arreglar ese mensaje bajo ninguna circunstancia. El botón "Expulsar" y la falta de actualización de firmware no se explican por este bug (llamadas reales a `DADiskUnmount`/`AuraUpdateChecker` verificadas correctas por separado) — lo segundo, con alta probabilidad, porque la instancia de Aura Studio abierta no se había recompilado/reabierto desde que esta sesión fijó `FIRMWARE_VERSION` a `v0.2.1-beta` en la misma corrida (ST-018).

**Qué era exactamente "Two, Three Karate Moves"** (confirmado en `biblioteca.json`): el nombre de un ÁLBUM cuya pista tiene el tag de artista `"Los Aguas Aguas, Luis Felipe Balderas López, José Edwin Bandala Mayoral, Osiel de Jesús Ro..."` (~90 caracteres, un crédito de composición completo en el campo de artista). Ni el álbum ni el artista tienen caracteres ilegales para FAT32 — la causa real es el LARGO acumulado: `PathSanitizer.sanitize()` nunca truncaba ningún componente, así que `Music/<artista de 90 caracteres>/Two, Three Karate Moves/63 - Aire.mp3.aura-tmp` (el sufijo `.aura-tmp` del archivo temporal de `copyFileTransactionally`) terminó excediendo lo que el driver msdosfs de macOS acepta — Cocoa lo reporta como "nombre inválido" sin mencionar que la causa real es el largo.

**Hallazgo aparte, investigado por pedido explícito** (inspección directa de `/Users/ricolinos/Documents/Aura Library/Música/`): la mayoría de las carpetas de artista de nivel superior son literalmente `"1"`, `"2"` ... `"20"` (número de pista), cada una con una subcarpeta `Desconocido` mezclando canciones de artistas distintos — patrón que coincide con las canciones de Gorillaz sin tags de artista (el único artista que sí se veía en el hardware, con carátula embebida en el archivo). Causa: `FilenameGuesser.guess()` (`LibraryEnricher.swift`) tomaba el primer segmento antes de `" - "` como artista sin validar que fuera texto plausible — con `"1 - Lil Dub Chefin' (radio edit).m4a"`, el "artista" quedaba literalmente `"1"`. **Importante**: al revisar `biblioteca.json` actual, esas carpetas numéricas en el Finder están **obsoletas** — la metadata real de hoy ya no tiene ese problema (solo 9 canciones con artista/albumArtist vacíos, correctamente cayendo en "Desconocido"; 0 con valores tipo número de pista salvo un falso positivo real, "40 Thieves feat. Qzen"). Son sobras de una corrida vieja que nunca se reorganizaron. Y — hallazgo clave que simplifica todo — `SyncPlanner.plan()` (`LibrarySync.swift:117`) YA compara `destinationRelativePath` contra el manifiesto anterior: si cambió, marca `.copy` con `staleDestinationRelativePath` (la ruta vieja, que el loop borra al copiar la nueva). Es decir: **el próximo sync que corra completo (sin abortar) va a autocorregir solas las carpetas mal armadas que quedaron en el iPod de una corrida vieja**, sin necesitar ninguna herramienta de reparación aparte — con tal de que la metadata de origen (ya sana) sea distinta de lo que el manifiesto tiene registrado del intento viejo.

**Hecho**:
- `LibrarySync.sync()`: el cuerpo del `planLoop` (desde el borrado del destino obsoleto hasta `saveManifest`) ahora vive dentro de un `do/catch` — un error de un solo archivo se registra en `result.failures` (`[SyncFailure]`, nuevo, con `sourcePath`/`destinationRelativePath`/`message`) y el loop sigue con el siguiente item. `finalize` (portadas, playlists, resumen, marcador, `removeInProgressMarker`) corre siempre que el loop termine su recorrido, con o sin fallos parciales.
- `PathSanitizer.sanitize(_:maxLength:)`: tope de 120 caracteres por componente (`defaultMaxLength`), truncando (y volviendo a recortar un `.`/espacio colgante si el corte cae ahí) antes de armar la ruta.
- `FilenameGuesser.guess()`: nuevo `looksLikeTrackNumberPrefix()` descarta como artista un primer segmento puramente numérico o que arranca con 1-3 dígitos seguidos de espacio (heurística deliberadamente imperfecta: un artista real como "21 Savage" cae a "Desconocido" en vez de a su nombre — preferible a mezclar artistas bajo una carpeta numérica).
- `LibraryViewModel.performSync`: además de `lastSyncSummary` (lo que sí se copió), si `result.failures` no está vacío arma un `lastError` en español listando hasta 5 archivos fallidos con su motivo (y cuántos más quedaron fuera de la lista) — antes, un fallo parcial no tenía ninguna forma de mostrarse (la función nunca llegaba viva hasta ahí).
- `LibrarySyncCancellationTests`: el test que documentaba el comportamiento VIEJO (`testUnexpectedFailureMidSyncPreservesAlreadyCopiedFilesAndMarker`, esperaba que una falla real dejara el marcador de "sync en curso" puesto) se reescribió como `testUnexpectedFailureMidSyncIsRecordedAsFailureAndRestOfSyncContinues`, afirmando el comportamiento correcto. Tests nuevos en `PathSanitizerTests` (tope de largo, truncamiento que cae en espacio/punto) y `FilenameGuesserTests` (prefijo numérico, número pegado al título, "2Pac" sigue siendo artista válido).

**No hecho, evaluado y descartado por ahora**: no se tocó `AuraUpdateChecker` ni el texto "Aura está al día" (bug de UX real y de baja confianza como causa del reporte -- el estado inicial `updateAvailable = false` es indistinguible de "ya revisé y sí está al día", `ContentView.swift:37`/`DeviceGeneralView.swift:238` -- pero la explicación más probable de "no se actualizó" es simplemente que la instancia de Studio abierta no se había recompilado desde el pin a `v0.2.1-beta` de ST-018 en esta misma sesión); no se tocó el botón "Expulsar" (la llamada a `DADiskUnmount` es real y el fallo SÍ se reporta al usuario, `DeviceGeneralView.swift:146-150` -- sin causa raíz confirmada, hipótesis más probable es un descriptor de archivo colgado de un sync interrumpido, que debería dejar de pasar con este arreglo); no se construyó ninguna herramienta de reparación para las carpetas numéricas obsoletas en el Finder -- el mecanismo de `SyncPlanner` ya descrito debería autocorregirlas en el próximo sync completo.

**Verificación**: `swift build` limpio. `swift test` **384/384** (los 8 tests nuevos/reescritos, más el flake de red que esta vez sí pasó). No se probó en vivo contra el iPod real del dueño en esta pasada -- pendiente que el dueño cierre y reabra Aura Studio (para tomar el pin a `v0.2.1-beta` y este código) y corra un sync completo, y reporte si los cinco síntomas en cascada desaparecen y si las carpetas numéricas del iPod se autocorrigen.

## ST-020 — La causa real de "no se actualizó el firmware": ninguna ruta de chequeo, ni siquiera la manual, saltaba la cache de 24h de Releases

**Encargo**: el dueño confirmó que todo lo de música (ST-019) ya funciona en hardware real, pero Aura Studio nunca le ofreció actualizar a `v0.2.1-beta` -- tuvo que descargarlo e instalarlo a mano desde el repositorio. Pidió, al cortar el siguiente release, asegurar que esta vez Aura Studio SÍ lo detecte.

**Causa real** (ST-019 había especulado, sin verificar, que la app simplemente no se había recompilado -- esta vez se revisó el código a fondo): `AuraUpdateChecker.checkForUpdate()` compara el `version.txt` del dispositivo contra el Release más nuevo de GitHub, con una cache de 24h en `UserDefaults` (`ReleaseCache`, pensada para no pegarle a la API en cada conexión del iPod -- diseño correcto para el chequeo AUTOMÁTICO). El problema: **ninguna ruta de código tenía forma de saltarse esa cache** -- ni siquiera el botón manual "Buscar actualizaciones de Aura" (`ContentView.swift`, `onCheckForUpdates`) ni el refresco de "Actualizar" (`refreshNow()`). Si la cache se llenó en cualquier momento ANTES de que `v0.2.1-beta` se publicara (muy probable: el dueño estuvo usando la app activamente el mismo día, con el iPod conectado, entre la publicación de `v0.2.0-beta` y la de `v0.2.1-beta`), el usuario podía cerrar la app, reabrirla, apretar el botón de chequeo manual las veces que quisiera, y seguir viendo "Aura está al día" hasta que el TTL venciera solo -- sin relación con si la app estaba recompilada o no.

**Hecho**: `checkForUpdate(...)` gana el parámetro `forceRefresh: Bool = false` -- en `true`, ignora `ReleaseCache.load()` y va directo a la red (`fetchAndCache`, que de todas formas vuelve a poblar la cache para el próximo chequeo automático). `false` por defecto: el chequeo automático (`.onChange(of: deviceMonitor.device)`) sigue respetando la cache, sin cambio de comportamiento ahí. Las dos rutas de chequeo EXPLÍCITO del usuario (`onCheckForUpdates` del botón, y `refreshNow()`) ahora pasan `forceRefresh: true` -- un chequeo que el usuario pide a propósito tiene que ser una consulta en vivo de verdad, no una que puede tener hasta 24h de retraso.

**Verificación**: test nuevo `testForceRefreshBypassesStaleCacheAndFetchesLive` (cache vigente pero desactualizada -- sin forzar, gana la cache; forzando, se consulta la red y aparece la actualización real). `swift build` limpio. `swift test` **385/385** salvo la falla conocida de red (`LiveEnrichmentIntegrationTests`, ST-002, sin relación).

## ST-021 — Pin a `v0.2.2-beta`

**Encargo**: cross-repo con `Aura-Firmware` D-300 (morph de Letras optimizado) y D-301 (versión visible sin scroll en Acerca de) — PATCH, sin cambio de contrato.

**Hecho**: `FIRMWARE_VERSION` → `tag=v0.2.2-beta` + los 4 hashes, verificados dos veces por separado (mismo criterio que ST-014/ST-018): `checksums.txt` descargado directo del Release público, y de nuevo por `scripts/fetch-firmware.sh` en modo Release real — los 4 `shasum -c` dieron `OK`. `Generated/AuraPalette.swift` comparado byte a byte: sin cambios. `CONTRATO-firmware-studio.md` §E: fila nueva, sincronizada con `Aura-Firmware` (`cmp` limpio).

**Verificación**: `swift build` limpio. `swift test` **385/385** salvo la falla conocida de red.

## ST-022 — PARTE 2A del plan: JPEG baseline garantizado, transparencia aplanada, colisión de nombres en `.preparados/`, nombres acotados a 95 bytes

**Encargo**: continuar `PLAN-sync-media-hardening.md` con Fotos, ahora que Música (ST-019/ST-020) ya funciona en hardware real.

**1. `ImageResizer`**: el codificador de JPEG de ImageIO no garantizaba baseline (el visor del firmware, `aura_photos.c:171-259`/D-291, rechaza JPEG progresivo con "Formato no soportado") -- se fuerza `kCGImagePropertyJFIFDictionary: [kCGImagePropertyJFIFIsProgressive: false]` explícito. Una fuente PNG/GIF con canal alfa quedaba a criterio del codificador de JPEG (que no tiene alfa) para el RGB debajo de los píxeles transparentes -- con frecuencia negro en vez del blanco esperado; ahora se aplana sobre blanco (`CGContext` opaco) ANTES de codificar, siempre (para una imagen ya opaca no cambia nada visible).

**2. Colisión de nombres en `.preparados/`**: es una única carpeta plana compartida por TODA la biblioteca -- dos fotos `IMG_1.jpg` de cámaras/carpetas distintas se pisaban en silencio (el segundo proceso sobrescribía el preparado del primero, ambas quedaban con el MISMO contenido en el iPod). `resolveNonCollidingStagingDestination` (nuevo, mismo esquema de sufijo `" 2"`, `" 3"`... que `resolveNonCollidingDestination` de la biblioteca local) resuelve esto para fotos y videos -- con una diferencia clave sobre el criterio de la biblioteca local: si el `preparedURL` que el ítem YA tenía de una pasada anterior sigue existiendo en disco, se reutiliza tal cual, para que reprocesar un ítem (cambiar la calidad de foto y volver a soltar) sobrescriba su propio preparado en vez de acumular sufijos nuevos cada vez.

**Gap conocido, no cerrado en esta pasada**: el póster de un video (`<video>.jpg`, generado por ffmpeg) deriva su nombre del `output` YA desambiguado del video, pero no pasa por su propio chequeo de colisión contra una FOTO real con el mismo nombre base -- el caso exacto que menciona el plan ("póster de video vs foto homónima") sigue abierto para esa combinación cruzada específica (video "X.mov" + foto separada "X.jpg" en el mismo lote). Se evaluó cerrarlo pero requeriría que el póster reconozca "esta colisión es conmigo mismo de una pasada anterior" sin la ayuda de un campo `preparedURL` propio (los pósters no se rastrean como ítems) -- sin eso, cada reproceso de video le agregaría un sufijo nuevo al póster, peor que el problema que se quiere resolver. Queda documentado, no bloqueante (mucho menos probable que la colisión foto-foto, que sí se cierra).

**3. Nombres ≤ 95 bytes UTF-8**: `destinationRelativePath` para `/Videos/`/`/Photos/` pasaba el nombre del archivo preparado tal cual, sin sanear ni acotar -- a diferencia de música, que ya pasaba por `PathSanitizer`. `PathSanitizer.sanitizeFilename(_:maxBytes:)` (nuevo): trunca por BYTES de UTF-8, no por caracteres -- un nombre con muchos acentos/ñ puede tener menos caracteres que bytes, así que capar por caracteres (como `sanitize(_:maxLength:)`, pensado para componentes de música) podía seguir excediendo el límite real. Nunca corta a mitad de una secuencia UTF-8 multibyte (recorta `Character` por `Character`, no `UInt8`). `LibrarySync.deviceFilenameMaxBytes = 95`, coincide con `VIDEO_NAME_LEN`/`PHOTO_NAME_LEN` del firmware (96 con el NUL).

**Verificación**: tests nuevos -- `ImageResizerTests` (el JPEG de salida siempre trae marcador SOF0/SOF1, nunca SOF2 progresivo, parseado byte a byte; transparencia total se lee cercana a blanco tras aplanar, no negro; una fuente opaca no cambia); `PathSanitizerTests` (`sanitizeFilename` con nombre corto sin tocar, con 60 "ñ" truncado por bytes no por caracteres, sin partir un carácter multibyte -- verificado re-decodificando los bytes resultantes, con caracteres ilegales reemplazados); `PhotoStagingCollisionTests` (dos `IMG_1.jpg` de carpetas distintas terminan en preparados DISTINTOS con contenido distinto, uno de los dos con el sufijo `" 2"`). `swift build` limpio. `swift test` **394/394** (esta vez incluso el flake de red pasó). `xcodegen generate` (2 archivos de test nuevos) + `xcodebuild -scheme AuraStudio build` → **BUILD SUCCEEDED**.

**Pendiente**: PARTE 2B del plan (firmware) es diagnóstico dirigido, sin código salvo evidencia de hardware -- el visor de Fotos (D-291) está completo pero nunca se probó en hardware real. PARTE 2C es protocolo de hardware, a cargo del dueño: sincronizar fotos reales (variedad de formatos/tamaños/nombres) y reportar qué se ve.

## ST-023 — General: "Eliminar contenido" por tipo de medio o todo, desde Aura Studio

**Encargo**: "desde Aura Studio, sería importante implementar una opción en la sección General, para Eliminar todos los archivos, o por tipos de medios".

**Hecho**:
- `LibrarySync.deleteAllDeviceContent(kinds:)` (nuevo): borra el CONTENIDO de `Music/`/`Videos/`/`Photos/` (según los tipos elegidos) directo del disco -- fuera del flujo normal de `sync()`, sin tocar la biblioteca local. Crítico y fácil de pasar por alto: también limpia los registros correspondientes del manifiesto (`manifest.records`, filtrado por prefijo de `destinationRelativePath`) -- sin esto, el próximo `sync()` vería el mismo `sourcePath`/tamaño/fecha del registro viejo (que no cambia solo porque el archivo del dispositivo desapareció) y decidiría `.skip`, dejando al usuario con "ya está sincronizado" pese a un iPod vacío. Deja el marcador `/.aura/sync-pending.json` (mismo mecanismo que un sync real, ST-012/D-293) para que el firmware reconstruya sus índices, y cae al borrado directo de tagcache en firmwares sin `sync_marker_supported` (misma regla de compatibilidad que `sync()`).
- `LibraryViewModel.deleteAllDeviceContent(toVolumeAt:kinds:)`: mismo guard de escritura concurrente que `sync()` (`InstallerFlowRegistry`, nunca borra mientras hay una instalación o sync en curso), corre en `Task.detached` (I/O real), y llama a `verifyDevice` al terminar para que el panel "En el iPod" refleje el vacío de inmediato.
- `DeviceGeneralView`: sección nueva "Eliminar contenido" dentro de "En el iPod" (solo visible con `librarySummary` ya cargado -- no tiene sentido ofrecer borrar antes del primer sync), con un botón por tipo (Música/Videos/Fotos) más "Eliminar todo" destacado. Mismo patrón de confirmación en dos pasos que `ForeignContentSheet` (ya establecido en el repo): el botón solo arma una `PendingDelete`, una `.alert(...)` con el conteo/etiqueta exacto y "esta acción no se puede deshacer" es la que de verdad ejecuta -- aclarando explícitamente que la biblioteca en la Mac no se toca (el borrado es solo del iPod).

**Verificación**: tests nuevos en `LibrarySyncDeleteAllContentTests` -- borrar un tipo deja los demás intactos (archivo Y registro de manifiesto); borrar todo limpia manifiesto entero; el sync SIGUIENTE a un borrado recopia en vez de saltear (la prueba directa de por qué había que limpiar el manifiesto); el marcador para el firmware queda escrito con la sección correcta en `true`; kinds vacío no hace nada. `swift test` **399/399**. `xcodegen generate` + `xcodebuild -scheme AuraStudio build` → **BUILD SUCCEEDED**.

## ST-024 — Pin a `v0.2.3-beta`

**Encargo**: cross-repo con `Aura-Firmware` D-302 (filtra sidecars AppleDouble de macOS) y D-303 (modo "cubrir" en el visor de fotos) — PATCH, sin cambio de contrato.

**Hecho**: `FIRMWARE_VERSION` → `tag=v0.2.3-beta` + los 4 hashes, verificados dos veces por separado (checksums.txt del Release público + `fetch-firmware.sh` en modo Release real, los 4 `shasum -c` dieron `OK`). `Generated/AuraPalette.swift` sin cambios. `CONTRATO-firmware-studio.md` §E: fila nueva, sincronizada con `Aura-Firmware` (`cmp` limpio).

**Verificación**: `swift build` limpio. `swift test` **399/399**.

## ST-025 — Pin a `v0.2.4-beta`

**Encargo**: cross-repo con `Aura-Firmware` D-303 (corrección: el modo "cubrir" ahora sí agranda más allá del tamaño de origen) — PATCH, sin cambio de contrato.

**Hecho**: `FIRMWARE_VERSION` → `tag=v0.2.4-beta` + los 4 hashes, verificados dos veces por separado. `Generated/AuraPalette.swift` sin cambios. `CONTRATO-firmware-studio.md` §E: fila nueva, sincronizada con `Aura-Firmware` (`cmp` limpio).

**Verificación**: `swift build` limpio. `swift test` **399/399**.

## ST-026 — PARTE 3A del plan: tope de fps para mpegplayer, sample rate de audio forzado, banner de ffmpeg faltante en vez de un mensaje por fila

**Encargo**: continuar `PLAN-sync-media-hardening.md` con Video, el otro "tampoco se han podido visualizar" del reporte original.

**1. Tope de fps**: `mpegplayer` en el S5L8702 del iPod Classic decodifica bien video de hasta ~24-25 fps -- 60 fps de un iPhone (el caso más común de "video que no se ve/no se reproduce bien") lo ahoga. `FFmpegTranscoder.arguments(sourceFrameRate:)` agrega `-r 24 -g 15` SOLO cuando la fuente excede 24 fps (forzarlo siempre duplicaría frames sin necesidad en una fuente ya lenta, como un timelapse). `probeVideoInfo(of:ffmpegURL:)` (nuevo) reemplaza a `probeDurationSeconds` en el caso `.video` de `process(itemAt:)` -- una sola pasada de ffmpeg da duración Y frame rate, en vez de dos procesos separados (`probeDurationSeconds` se queda intacta para música, que nunca necesitó fps).

**2. Sample rate de audio**: `-ar 44100` agregado siempre -- antes no se forzaba ningún sample rate, así que el audio quedaba a la frecuencia de origen (48kHz es común en video de teléfono). libmad (el decoder de audio de `mpegplayer`) solo entiende MPEG audio Layer I/II/III en frecuencias estándar; sin esto, un video con audio a 48kHz podía terminar sin audio o con audio corrupto en el iPod, sin que nada en el pipeline lo hubiera anticipado.

**3. Banner de ffmpeg faltante**: antes, con ffmpeg no instalado, CADA video en cola fallaba por separado y mostraba el mismo párrafo largo de "instala ffmpeg con Homebrew..." repetido una vez por fila. Ahora `process(itemAt:)` distingue `FFmpegTranscoder.TranscodeError.ffmpegNotFound` del resto de errores -- la fila muestra un mensaje corto ("Falta ffmpeg"), y `MediaSectionView` (sección Video) muestra un banner persistente único con la explicación completa y un botón "Volver a intentar" (`LibraryViewModel.retryVideosWaitingOnFFmpeg()`, reencola solo los videos que fallaron por ESTA causa, nunca otros `.failed` con una causa real distinta).

**4. Nombres saneados/acotados a 95 bytes**: ya cubierto de forma genérica desde ST-022 (`PathSanitizer.sanitizeFilename` en `destinationRelativePath` para `/Videos/`, no específico de esta pasada). Póster de video vs. foto homónima sigue como gap conocido, documentado en ST-022 -- no se cerró en esta pasada tampoco.

**No probado automatizado, documentado explícitamente**: el banner de ffmpeg faltante (`hasVideosWaitingOnFFmpeg`/`retryVideosWaitingOnFFmpeg`) no tiene test de integración -- `FFmpegLocator.locate()` revisa rutas absolutas fijas (`/opt/homebrew/bin/ffmpeg` primero) antes que cualquier variable de entorno, así que no hay forma determinista de simular "ffmpeg no instalado" en una máquina que sí lo tiene instalado (como la de desarrollo) sin agregar un punto de inyección de dependencias nuevo a `LibraryViewModel`/`FFmpegTranscoder` -- cambio que no se justificó para esta pasada. La lógica en sí (parseo de fps, armado de argumentos) sí tiene cobertura completa y determinista.

**Verificación**: tests nuevos en `FFmpegTranscoderTests` -- `parseFrameRate` con línea estándar de ffmpeg (entero y decimal), `nil` sin pista de video; `arguments(sourceFrameRate:)` omite `-r`/`-g` en 24fps exactos o sin dato, los agrega arriba de 24; `-ar 44100` siempre presente. `swift build` limpio. `swift test` **406/406** salvo la falla de red conocida (intermitente, confirmada sin relación). `xcodebuild -scheme AuraStudio build` → **BUILD SUCCEEDED** (relevante aquí en particular: la firma de `transcode(...)` cambió, y este repo solo chequea Swift 6 strict concurrency de verdad vía `xcodebuild`, no `swift build`, D-034).

**Pendiente**: PARTE 3B del plan (firmware) es diagnóstico dirigido -- ya hecho en F0.2 (D-298: retorno de `plugin_load`, mensaje propio, `VIDEO_NAME_LEN` 96, "…y N más"), falta verificar en hardware si `mpegplayer` muestra sus propios splashes en inglés. PARTE 3C es protocolo de hardware, a cargo del dueño.

## ST-027 — Ya no se hornean barras negras en el video: el firmware decide ajustar/cubrir

**Encargo**: cross-repo con `Aura-Firmware` D-304 -- el dueño pidió, para el reproductor de video, el mismo ajuste "ajustar/cubrir" del visor de fotos (D-303), alternable con Select durante la reproducción y desde el menú de ajustes del propio reproductor.

**Causa por la que hacía falta tocar Studio y no solo el firmware**: `FFmpegTranscoder.arguments()` escalaba el video Y lo rellenaba con `pad` a exactamente 320×240 -- el `.mpg` que llega al iPod SIEMPRE tenía las franjas horneadas como píxeles reales, sin importar el aspecto original del contenido. Con eso, `vo_setup()` del firmware (que en teoría ya sabía centrar/recortar según el tamaño real de la secuencia) nunca veía una secuencia distinta de 320×240 -- letra muerta. Sin corregir esto, un modo "cubrir" en el firmware solo habría recortado bandas negras ya rasterizadas, sin agrandar el contenido real -- mismo tipo de error de premisa que D-303 tuvo que corregir del lado de fotos.

**Hecho**: se quitó el filtro `pad` del `-vf` de `arguments()` -- ahora solo `scale=320:240:force_original_aspect_ratio=decrease:force_divisible_by=2` (preserva el ancho o alto real del contenido dentro de la caja de 320×240, sin rellenar; `force_divisible_by=2` asegura dimensiones pares, requisito del submuestreo de crominancia 4:2:0 que espera MPEG-2 -- antes lo garantizaba el propio `pad`). El resto del pipeline (fps, `-ar 44100`, bitrate) no cambió. El resto del trabajo (el toggle en sí, el recorte+escalado "cubrir pantalla" en tiempo real) es enteramente del lado del firmware -- ver D-304 en `Aura-Firmware/DECISIONS.md`.

**Verificación**: los tests existentes de `FFmpegTranscoderTests` no dependían del filtro `pad` (solo verifican `-r`/`-g`/`-ar`, no el contenido completo de `-vf`) -- sin cambios necesarios ahí. `swift build` limpio. `swift test` **406/406** salvo la falla de red conocida e intermitente (`testCoverArtArchiveFetchesRealCover`, sin relación). `xcodebuild -scheme AuraStudio build` → **BUILD SUCCEEDED**.

## ST-028 — Detecta y recorta franjas horneadas en el propio archivo de origen (rips de DVD/BluRay)

**Encargo**: el dueño probó "cubrir pantalla" (D-304 en `Aura-Firmware`) con una película real de su biblioteca (rip, archivo `.mkv`) y seguía sin ver ningún efecto -- sospechó que el video ya traía franjas negras horneadas desde el origen, antes incluso de que Studio lo tocara, y pidió confirmarlo y corregirlo si era el caso.

**Confirmado con evidencia real, sin tocar el `.mkv` pesado** (el dueño pidió explícitamente no leerlo/convertirlo): se inspeccionó el `.mpg` YA transcodificado (`~/Documents/Aura Library/Preparados/EL CALVO PIRATEADO 2.0.mpg`) con `ffprobe`/`cropdetect` en tres puntos distintos de la película (minuto 5, 15 y 25):
```
Stream declarado: 320x240, DAR 4:3
Contenido real detectado (cropdetect): crop=320:132:0:54 / crop=320:136:0:52 / crop=320:132:0:54
```
El stream se DECLARA 4:3, pero el contenido real visible ocupa solo ~132-136px de los 240px de alto (~2.35:1, aspecto cinematográfico clásico) -- el resto son franjas negras HORNEADAS como píxeles reales dentro del `.mkv` de origen (típico de rips de DVD/BluRay que preservan el letterbox del theatrical release). `scale=...` (ST-027) solo mira metadata del stream (SAR/DAR declarados), nunca el contenido real de los píxeles -- no tenía forma de detectar esto. Con el stream ya declarado en 4:3 y el `.mpg` resultante también en exactamente 320x240 (=pantalla completa), `vo_setup()` del firmware nunca encuentra nada que recortar/centrar: "ajustar" y "cubrir" se ven idénticos en este archivo específico, sin que sea ningún bug del firmware (D-304/D-308) -- el problema está enteramente en que Studio nunca miró el contenido real de los píxeles al transcodificar.

**Hecho** (`FFmpegTranscoder.swift`):
- `detectCropFilter(of:ffmpegURL:durationSeconds:)` (nueva): corre `-vf cropdetect=24:2:0` sobre 100 frames de muestra, arrancando al 20% de la duración (evita logos/intros negros de verdad que no son franja) y sin decodificar audio (`-an`). Devuelve el filtro `crop=W:H:X:Y` listo para anteponer al `scale`, o `nil` si no vale la pena aplicarlo.
- **Umbral de "vale la pena"**: `cropdetect` encontró un recorte del 2-3% hasta en un video de prueba sin ninguna franja real (`Back Clean.mp4`, 1920x1080 → `crop=1880:1048`) -- ruido de compresión/viñeteado en el borde, no franja de verdad. Aplicar ese recorte mínimo a TODOS los videos habría sido, irónicamente, lo opuesto de "respetar el AR original" (recortaría un poco siempre, aunque sea innecesario). `detectCropFilter` compara el recorte detectado contra la resolución real de origen (`parseResolution`, nuevo, mismo volcado de cabecera que ya usa `parseFrameRate`) y solo lo aplica si deja menos del 95% del ancho O alto original -- 2-3% de ruido queda ignorado; el 45% real de la película sí se aplica.
- `arguments(cropFilter:)`: nuevo parámetro opcional, antepuesto al `scale` existente cuando viene (`crop=...,scale=320:240:...`) -- el orden importa, recortar ANTES de escalar.
- `transcode(...)` calcula el crop automáticamente (vía `probeDurationSeconds` + `detectCropFilter`) antes de armar los argumentos -- **falla abierto a propósito**: si la detección falla por cualquier razón (`try?`), se transcodifica igual sin recorte, el comportamiento de antes de esta función. Ningún llamador (`LibraryViewModel`) necesitó cambios -- la detección es enteramente interna a `transcode()`.

**Verificado**: 7 tests nuevos en `FFmpegTranscoderTests` (`parseCropFilter` con línea válida/sin línea/dimensión cero, `arguments(cropFilter:)` antepone el crop al scale y lo omite si no viene, `parseResolution` con línea estándar/sin stream de video) -- todos pasan. Matemática del umbral verificada a mano contra los dos archivos reales: `Back Clean.mp4` (1880/1920=0.979, 1048/1080=0.970, ambos ≥0.95 → sin recorte, correcto) y la película (320/320=1.0, 132/240=0.55 <0.95 → recorte aplicado, correcto). `swift build` limpio. `swift test` **413/413** salvo la falla de red conocida (`testCoverArtArchiveFetchesRealCover`, sin relación). `xcodebuild -scheme AuraStudio build` → **BUILD SUCCEEDED**.

**No verificado end-to-end** (a propósito, por pedido explícito del dueño de no tocar el `.mkv` pesado): no se corrió un transcode real de la película completa con el nuevo `cropFilter` -- la lógica se verificó por partes (parseo unitario + matemática del umbral contra números reales medidos con `ffmpeg`/`cropdetect` a mano). El dueño tiene que volver a agregar la película a su biblioteca (quitarla y re-agregar el `.mkv` original) para que el pipeline nuevo la retranscodifique con el recorte real aplicado -- mismo caveat de siempre sobre la idempotencia del sync (D-308 en `Aura-Firmware`).

**Pendiente**: confirmación del dueño con la película real, tanto en Studio (que el `.mpg` resultante ya no traiga franjas horneadas -- se puede verificar con el mismo `ffprobe`/`cropdetect` usado acá) como en el iPod (que "ajustar" ahora sí muestre franjas del lado del firmware, y "cubrir" recorte y llene la pantalla de verdad).

## ST-029 — `mks5lboot` sin bit de ejecución: el instalador se quedaba en "Esperando modo DFU..." con el iPod ya en DFU

**Síntoma** (2026-08-17, reportado por el dueño con captura): iPod en DFU real (pantalla negra, sin sonido), la app en "Entra a modo DFU" con "Esperando modo DFU..." sin avanzar nunca — no trabada, solo sin ver nada. macOS sí lo veía: `ioreg` mostraba `USB DFU Device` de Apple, `0x05AC:0x1223`.

**Causa** (confirmada con archivo y permisos): `mks5lboot` dentro del bundle compilado estaba `-rw-r--r--`. `IPodMonitor` sondea DFU con `mks5lboot --dfuscan` cada segundo; `Process.run()` fallaba con "permission denied", `try? runner.scanDFU()` lo convertía en `nil` = "no hay iPod en DFU", y la vista esperaba para siempre. El origen (`Aura-Firmware/firmware/dist/mks5lboot`) sí tenía `+x`; se perdió al poblar `Vendor/firmware-dist/` — los assets de un Release de GitHub llegan sin bit de ejecución y `scripts/fetch-firmware.sh` no lo restauraba; Copy Bundle Resources conserva los permisos del origen, así que el bundle heredó el defecto. Ejecutado a mano con `+x`, el mismo binario del bundle encontró de inmediato `[05ac:1223] iPod Nano 3G / Classic, mode: DFU`.

**Hecho**, en tres capas para que no dependa de una sola:
- `scripts/fetch-firmware.sh`: `restore_exec_bit` (`chmod 755 mks5lboot`) tras verificar checksums, en los dos modos (Release y `--from-dir`).
- `project.yml`: fase `postBuildScripts` "mks5lboot: asegurar bit de ejecucion" — corre después de copiar recursos y antes de firmar; `chmod 755` dentro del bundle solo si falta. Verificado con un `Vendor/` cuyo `mks5lboot` era `644`: `xcodebuild` → BUILD SUCCEEDED, el bundle quedó `-rwxr-xr-x`, `codesign -v` limpio.
- Código: `MKS5LBootRunner.init` rechaza un binario inexistente (`binaryNotFound`) o sin permiso de ejecución (`binaryNotExecutable(path:)`, con `errorDescription` que dice qué hacer). `IPodMonitor` publica `dfuScannerProblem` — se llena si el runner no se pudo crear o si un escaneo tira (no cuando simplemente no hay iPod, que sigue siendo `nil` sano) y se limpia solo al primer escaneo bueno. `EnterDFUView` muestra "Aura Studio no puede detectar el modo DFU" + el motivo en vez de "Esperando modo DFU..." — la regla: nunca esperar en silencio algo que la app ya sabe que no puede llegar.

**Remedio inmediato aplicado en la máquina del dueño** (fuera del repo): `chmod 755` al `mks5lboot` de `Vendor/firmware-dist/` y del bundle en DerivedData; sin reiniciar la app, el siguiente sondeo detectó el DFU y la instalación siguió — minutos después el iPod apareció por USB como `Rockbox.org / Rockbox media player` con el volumen `IPOD` montado (bootloader ya grabado, modo USB del bootloader, ST-017).

**Verificación**: `swift build`; `xcodegen generate` + `xcodebuild` → **BUILD SUCCEEDED**; `swift test` — 4 tests nuevos en `MKS5LBootRunnerExecutableBitTests` (sin `+x` → `binaryNotExecutable`; con `+x` → OK y `scanDFU` con exit 1 = `nil` sin error; inexistente → `binaryNotFound`; el mensaje explica qué hacer). El caso de vista (`dfuScannerProblem` en pantalla) no tiene test de UI; se ejercitó el camino en hardware con el binario roto y luego reparado.

## ST-030 — Tabla de Canciones: "Estado" ordena, favoritos, columnas personalizables sin el tope de 10, menú de encabezado y "Opciones de visualización"

**Encargo** (2026-08-18, con capturas de Music.app como referencia): columnas más personalizables; el encabezado "Estado" no ordenaba al hacer clic; clic derecho sobre cualquier encabezado con "Todas las canciones / Solo favoritos / Opciones para ordenar ▸ (criterios + Ascendente/Descendente) / Mostrar opciones de visualización", y esa ventana para configurar todo.

**Bug de "Estado"** (confirmado en `MediaSectionView`): la columna se declaraba `TableColumn("Estado") { … }` sin `value:`/`sortUsing:` — `Table` la pinta como no ordenable y el clic no hace nada. Mismo defecto en Video/Fotos. Además el valor mostrado no era de la fila sino de `viewModel.deviceSyncIndex`. Ahora `MediaTableRow` recibe `syncState` al construirse y expone `statusRank` (sincronizado < listo < pendiente < con cambios < modificado en el iPod < quitado < en cola/procesando < revisar < falló); las tres tablas usan `value: \.statusRank`.

**Modelo**: `TrackMetadata.isFavorite` (marca binaria, independiente de `rating`; solo en el catálogo, no hay frame ID3 estándar), `discNumber` (TPOS/DISCNUMBER/`disk`, lo lee `LocalTagReader`), `LibraryItem.addedAt`. Los tres opcionales al decodificar (catálogos viejos siguen cargando; `false` no se escribe). `LibraryViewModel.setFavorite/toggleFavorite` persisten sin re-preparar el archivo. "Reproducciones" **no** se ofrece: Studio no tiene datos de reproducción (el que reproduce es el iPod) — se dice en vez de mostrar una columna en cero.

**Columnas** (`Models/MusicTableColumn.swift`): el deployment target ya es macOS 14.4, así que `TableColumnForEach` (14.4+) reemplaza el límite de 10 slots de `TableColumnBuilder` (D-199): "Título" es fija y primera; el resto (`album, albumArtist, artist, composer, discNumber, duration, genre, trackNumber, year, favorite, rating, dateAdded, fileFormat, fileSize, status`) se declara desde `AppPreferences.musicVisibleColumns` — visibilidad **y orden**, persistidos como lista separada por comas; migra lo que el usuario tuviera en el menú "+" viejo (`aura.visibleColumns.music`). Cada columna define su comparador (`comparator(order:)`, `localizedStandard` para textos) y `MusicSortField(keyPath:)` reconoce el criterio a partir del comparador que `Table` deja en `sortOrder` tras un clic — así el orden que se ve y el que se persiste (`musicSortField`/`musicSortAscending`) se mantienen iguales sin ciclos. `musicShowOnlyFavorites` = el filtro. Video/Fotos conservan el "+" de D-199 (`ExtraColumn` queda solo con Formato/Tamaño).

**Menú de encabezado** (`Views/TableHeaderMenu.swift`): `Table` de SwiftUI no expone la fila de encabezados; debajo hay un `NSTableView` real y su `NSTableHeaderView` muestra `menu` con el clic derecho (nativo de AppKit). `TableHeaderMenuInstaller` es un `NSViewRepresentable` vacío superpuesto a la tabla que localiza ese `NSTableView` en la jerarquía y le instala un `NSMenu` reconstruido en cada apertura (`menuNeedsUpdate`), con las marcas del estado actual; el clic izquierdo (ordenar, redimensionar) no se toca. Las entradas se declaran como dato (`TableHeaderMenuEntry`) y el **mismo** menú vive en el botón de la barra encima de la tabla (`Menu` de SwiftUI, ícono `line.3.horizontal.decrease` como en Music.app) — si en alguna versión de macOS el puente no encuentra la tabla, nada se pierde. `MusicViewOptionsView` (hoja): Ordenar por + sentido, "Mostrar solo favoritos", casillas por grupo (Música / Personal / Estadísticas / Archivo / Otros), lista arrastrable con el orden de las columnas, "Restablecer".

**Verificación**: `swift build`; `xcodegen generate` + `xcodebuild` → BUILD SUCCEEDED (Swift 6 estricto atrapó dos cosas que `swift build` no: `static let shared` sin `Sendable`, y closures nuevos que volvían no-`Sendable` a los clientes — resueltos con `@unchecked Sendable` justificado y `@Sendable`); `swift test` **438/438** en la última corrida (nuevos: `MediaTableRowTests` +2, `MusicTableColumnTests` 12, `LibraryPersistenceFavoriteTests` 4). Visual con la biblioteca real del dueño: la tabla de Canciones con Título · Artista · Álbum · Género · Duración · Favorito (estrellas) · Estado y el botón del menú. **No verificado por automatización**: el clic derecho sobre el encabezado (no se puede simular desde AppleScript) y la hoja de opciones — a cargo del dueño; el botón de la barra es el respaldo garantizado.

## ST-031 — Música → Artistas / Álbumes / Canciones / Listas; agrupación en memoria, cuadrícula de álbumes, ficha de artista, búsqueda contextual (tanda 2 de `PLAN-studio-ux.md` §1, parcial)

**Encargo** (2026-08-18, capturas de Music.app): organizar Música como Artistas / Álbumes / Canciones; álbumes en cuadrícula de portadas; artistas como lista con avatar a la izquierda y ficha a la derecha con sus álbumes y canciones; barra de búsqueda contextual (en Canciones busca canciones, en Álbumes álbumes, en Artistas artistas…).

**Se ejecuta la parte de vistas de la tanda 2** del plan aprobado (§2.1–2.3), con los nombres de las capturas en vez de "Por álbum/Por artista". **Fuera, a propósito y pendiente**: `StudioStyle` y "Listas plana" (§2.4) — no los pedía el encargo y son una pasada mecánica aparte.

**Hecho**:
- `Models/LibraryGrouping.swift` (puro, testeable): `AlbumGroup`/`ArtistGroup`. Clave de álbum = (`album`, `albumArtist ?? artist`) normalizados (sin mayúsculas/acentos/espacios sobrantes) — la misma precedencia que la ruta de sync (`LibrarySync`), para que lo que se ve coincida con las carpetas del iPod (P4). "Sin álbum" (uno por artista) y "Artista desconocido" siempre al final; dentro del álbum por disco (sin número = disco 1), pista y título; álbumes/artistas por nombre ignorando artículo inicial (El/La/Los/Las/The/Un/Una/A/An) y puntuación inicial ("…Little", "'Plastic"). La grafía mostrada es la de la primera pista que entró al grupo. **Nada crea carpetas.** `MusicScope` (`.all/.album/.artist`) acota la tabla de Canciones.
- Barra lateral: el grupo "Música" (`.musicGroup`, con identidad propia porque dentro de un `ForEach` la fila del grupo hereda la etiqueta implícita `.music` y resaltaba junto con "Canciones") con Artistas (`.musicArtists`, `music.mic`), Álbumes (`.musicAlbums`, `square.stack`), Canciones (`.music`), Listas. `S.songs/albums/artists` ES/EN. Bloqueo con `libraryLocked` para todo el grupo (`isMusicSection`).
- `Views/AlbumsView.swift`: `LazyVGrid` adaptativa (160–200 pt) de `AlbumCardView` (portada, título 2 líneas, artista, estrella si algún tema es favorito); orden Título / Artista / Año / Agregado recientemente (`@AppStorage`); búsqueda "Buscar en Álbumes"; clic → detalle con portada 180, título, artista, género · año, "N canciones, M min", acciones (favorito, buscar información) y **la misma `MediaSectionView`** acotada (`scope: .album`) — conserva columnas, menú contextual, arrastre y QuickLook sin reimplementar nada.
- `Views/ArtistsView.swift`: maestro (280 pt) con `ArtistAvatarView` (foto de artista → portada de un álbum → micrófono) y búsqueda "Buscar en Artistas"; detalle: cabecera (nombre, "N álbumes, M canciones", acciones) y una sección por álbum (portada 128, título, género · año, filas de pistas con número, título, artista si difiere del artista del álbum, duración, estrella; menú contextual). Fotos de artista: ST-032.
- `MediaSectionView`: `scope`, campo "Buscar en Canciones/Video/Fotos" (`LibrarySearch`: título, artista, álbum, artista del álbum, género, compositor, categoría; sin mayúsculas/acentos), estado vacío explicado cuando un filtro no deja nada; embebida no muestra zona de arrastre ni banners.
- `Services/CoverThumbnailCache.swift`: miniaturas por `CGImageSourceCreateThumbnailAtIndex` + `NSCache` (las carátulas se guardan a ~1000 px; decodificarlas enteras por celda hacía lentas las cuadrículas).

**Verificación**: `LibraryGroupingTests` 13 (vacíos, homónimos, normalización, "Sin álbum"/"Artista desconocido" al final, disco/pista/título, artículos y puntuación, portada, resumen); build/xcodebuild/suite como ST-030. Visual con la biblioteca real: cuadrícula de Álbumes con las portadas del dueño; Artistas con avatares desde portadas y "The 1975"/"Los Aguas Aguas" ordenados por la palabra significativa; Canciones con búsqueda.

**Encabezado del plan** actualizado: tanda 2 §2.1–2.3 hecha aquí; §2.4 pendiente.

## ST-032 — Fotos de artista: MusicBrainz → fanart.tv `artistthumb`, Deezer de respaldo; se guardan en la biblioteca, nunca en el iPod

**Pregunta del dueño**: "¿hay bases de datos donde podamos descargar la imagen del artista?" Sí, y la mejor ya estaba conectada: **fanart.tv** tiene `/v3/music/{MBID}` con `artistthumb` (cuadrada, ~1000 px), `artistbackground` y logos — pero **no busca por texto**, indexa por MusicBrainz artist ID. Alternativas sin clave: **Deezer** (`/search/artist`, `picture_xl`), TheAudioDB; Spotify exige OAuth; Last.fm ya no entrega fotos reales.

**Hecho**: `MusicBrainzClient.searchArtist(name:minimumScore: 85)` (nunca "el primero que salga": bajo ~85 son homónimos parciales; mejor sin foto que con la de otro). `FanartTVClient` gana `rootURL` `/v3`, `fetchArtistThumb(musicBrainzArtistID:)`, y `apiKeyProvider` inyectable (el llavero real no se toca en tests). `DeezerClient.fetchArtistPicture(name:)` exige coincidencia exacta del nombre normalizado ("Gorillaz" no se lleva la foto de "Gorillaz Sound System"). `ArtistImageResolver`: fanart.tv (si hay key) → Deezer (si está habilitado en Ajustes) → nil. `ArtistImageStore`: `<biblioteca>/.portadas/artistas/<clave>.jpg` (clave = la misma de `LibraryGrouping.artistKey`, codificada como nombre seguro), caché con `NSLock` (`@unchecked Sendable` honesto), no entra a `biblioteca.json` (el archivo es la verdad, como las carátulas) y **no viaja al iPod** (el firmware no muestra artistas con foto). `LibraryViewModel.fetchArtistImages(for:)` (secuencial: MusicBrainz 1 req/s; publica resumen en `lastEnrichmentSummary`); botón "Buscar fotos de los artistas" en la lista y "Buscar/Quitar foto del artista" en el menú de cada artista.

**Verificación**: `ArtistImageTests` 12 (almacén, nombre seguro, MusicBrainz con/sin umbral, fanart.tv artista/404/sin key, Deezer coincidencia exacta, resolvedor con respaldo y con fuentes apagadas). Sin descarga real en esta sesión (sin tocar el llavero del dueño); a verificar con su key.

## ST-033 — Pósters de películas y series: TMDB (clave nueva, opcional) resuelve el título; fanart.tv aporta el póster curado; el póster viaja al iPod como `<video>.jpg`

**Encargo** (2026-08-18): "acabo de configurar mi API key de fanart.tv, ayúdame a conectar la herramienta para la búsqueda de carátulas en la biblioteca de películas y series." fanart.tv ya estaba conectada para álbumes (D-203). Para video el obstáculo es el mismo que para artistas: **fanart.tv no busca por título** — películas por ID de TMDB/IMDb, series por ID de TheTVDB. No había nada de TMDB en el repo.

**Decisión**: **TMDB como segunda clave opcional** (`APIKeyService.tmdb`, gratuita, Keychain, fila nueva en Ajustes › Servicios con guía): resuelve título → ID de película, y título → ID de serie → `external_ids.tvdb_id`; además trae su propio `poster_path` como **respaldo** cuando fanart.tv no tiene el título o no hay key de fanart.tv. Sin key de TMDB no se puede buscar y se dice en `lastError` (no falla en silencio). `TMDBClient` (`/search/movie` con año, `/search/tv`, `/tv/{id}/external_ids`, `image.tmdb.org/t/p/w780`, `language=es-MX`). `VideoTitleParser`: limpia nombres reales (`The.Matrix.1999.1080p.BluRay.x264`, `Serie - S01E02 - …`, `1x02`, corchetes, tokens de calidad/códec/grupo), saca el último año y el nombre de la serie. `VideoArtworkResolver`: por categoría del video (Películas → película, Series → serie, Videos → ambas, series primero si trae `SxxEyy`): fanart.tv (`movieposter` por TMDB id / `tvposter` por TVDB id) → póster de TMDB; `Failure.missingTMDBKey/noMatch/noPoster` explícitos.

**Al iPod**: el póster descargado queda como `coverArtData` del item (persistido en `.portadas/` como las carátulas) y se escribe **reducido** (`ImageResizer.resizeToLCDOptimal(data:)`, JPEG, lado mayor ≤ 640 px = máximo del firmware) como `<preparado>.jpg` — exactamente el archivo que `LibrarySync` ya copiaba como hermano del `.mpg` (contrato §1, D-066); en `process(itemAt:)` el póster descargado manda sobre el fotograma de ffmpeg. "Buscar póster en línea" / "Quitar póster" (vuelve al fotograma) en el menú contextual de Video; el banner de progreso/resumen se muestra también en Video. Si el usuario no había editado el título, se toma el de TMDB (limpio) y el año.

**Verificación**: `VideoArtworkTests` 15 (parser: ruido, año único, último año, episodios `SxxEyy`/`1x02`; TMDB: query/año/idioma/key, sin key sin red, `external_ids`, descarga; resolvedor: fanart primero, respaldo TMDB, serie vía TVDB, `unknown` con episodio prueba serie primero, sin key TMDB, sin coincidencia). Sin descarga real en esta sesión — a cargo del dueño con sus keys (fanart.tv ya la tiene; falta la de TMDB).

## ST-034 — Contrato v6: fotos de artista (§D.3) — solo formato, sin código todavía

Ver **D-319** en `Aura-Firmware/DECISIONS.md` (la entrada canónica; esta es la contraparte del lado Studio, mismo contrato, mismo commit de docs). `CONTRATO-firmware-studio.md` → v6, copia idéntica a la del firmware (`cmp` limpio). Aprovechando la misma pasada de higiene de contratos: `docs/contracts/library-layout-v1.md` estaba desactualizado en v1.1 (canónico en el firmware: v1.3) — sincronizado por `cp` desde `Aura-Firmware`, `cmp` limpio. `docs/plans/PLAN-studio-ux.md` §3.4 marcado "Superado" (remitiendo a `PLAN-biblioteca-medios-v2.md`, carpeta padre) sin borrar el texto original — la propuesta de contrato versionado de esa sección quedó reemplazada por el diseño real que ya se implementó (v6 aquí mismo). Sin cambios de código en esta pasada.

## ST-035 — Hora y zona horaria automáticas hacia el iPod (contrato v7, §D.4)

Ver **D-321** en `Aura-Firmware/DECISIONS.md` (diseño completo, criterio de cuándo se reaplica el RTC). Contraparte del lado Studio: `ClockSyncWriter` (nuevo, `Services/`), puro y testeable — `upsertClockLines(_:date:timeZone:calendar:)` calcula las 7 líneas (`rtc_sync_year/month/day/hour/min/sec` desde `Calendar`/`TimeZone.current` en hora local, `tz_local_quarters` desde `secondsFromGMT() / 900`) y las upserta sobre las líneas existentes de `aura.cfg`, preservando el resto — mismo patrón que `ThemeInstaller.activate` para `theme_id`; `writeToDisk(mountPath:...)` hace la I/O real.

**Dos disparadores**, ambos ya existentes en el flujo, sin nueva UI:
- `IPodMonitor.handleDiskChange`: cada vez que el probe confirma `probed.isAura` (firmware Aura corriendo o con evidencia de haber arrancado), en el mismo bloque donde ya se anota `recordBootloaderVerified`. Toma el candado de `InstallerFlowRegistry` él mismo (`beginWriting()`/`endWriting()`) y cede en silencio si otro flujo ya está escribiendo — el próximo connect reintenta, no hace falta forzarlo.
- `InstallerViewModel.copyFirmwareFiles`: justo después de crear las carpetas de medios (`Music`/`Photos`/`Videos`/`Playlists`), para que el primerísimo arranque tras instalar/actualizar ya traiga hora y zona correctas sin esperar una reconexión posterior. Esta función ya sostiene el candado de `InstallerFlowRegistry` desde antes (no es reentrante) — no lo vuelve a tomar.

**Deliberadamente fuera de alcance**: idioma (el encargo decía "hora y region", no idioma).

**Verificación**: `ClockSyncWriterTests` 6 (upsert agrega las 7 claves a un archivo vacío; reemplaza en el mismo lugar preservando otras claves — `theme_id` no se mueve ni se duplica; offset positivo de zona horaria — Tokio +9h = 36 cuartos; escritura real crea el archivo si falta; preserva líneas no relacionadas; ignora rutas de montaje inválidas sin lanzar). `swift build`, `swift test` completa (481 pruebas, 2 fallos — el flake de red ya conocido de `testCoverArtArchiveFetchesRealCover`, sin relación), `xcodegen generate` + `xcodebuild` → BUILD SUCCEEDED.

## ST-036 — Pin a v0.2.10-beta (D-320/D-321 en Aura-Firmware)

Encargo del dueño: publicar los commits pendientes en ambos repos y cortar un release del firmware para poder probar en hardware real. `FIRMWARE_VERSION` → `tag=v0.2.10-beta`, hashes de `rockbox.ipod`/`rockbox.zip` actualizados (`mks5lboot`/`bootloader-ipod6g.ipod` sin cambios — ninguno de los dos se recompiló en esta pasada). `fetch-firmware.sh` verificó los 4 checksums contra el Release publicado, `AuraPalette.swift` sin diferencias (ningún token de diseño cambió). `swift build` limpio; sin cambios de código Swift en esta pasada.

## ST-037 — Índices de categoría, nombre ` SxxEyy` y póster de temporada (Tanda 1 de `PLAN-biblioteca-medios-v2.md`)

**Encargo**: Tanda 1 del plan aprobado — hace funcionar Películas/Series/Videoclips y Fotos/Imágenes/IA del firmware `v0.2.10-beta` (D-316, contrato v5 §D.2) alimentando por primera vez los dos índices por archivo que Studio nunca escribía, y prepara el terreno para que Movie Flow (D-318) agrupe episodios por temporada. Sin cambios de firmware en esta pasada.

**Diseño**: campos nuevos, todos opcionales (`LibraryItem.swift`, `PersistedLibraryItem` en `LibraryPersistence.swift`): `seriesName/season/episode` (solo `.video` en Series) y `photoAlbum` (adelantado de la Tanda 2, mismo patrón mecánico — sin UI todavía). `LibraryViewModel.process(itemAt:)` (caso `.video`): al importar, `VideoTitleParser.parse()` sobre el nombre del archivo; si el patrón `SxxEyy`/`1x02` aparece, decisión C del plan (**SÍ**) clasifica como Series sola (sin heurística de duración) y puebla los tres campos — D-228 solo había descartado la duración como señal, nunca un patrón explícito.

`LibrarySync.swift`: `destinationRelativePath(for:...)` usa `seriesEpisodeFilename(seriesName:season:episode:ext:maxBytes:)` para episodios de Series con los tres campos resueltos — a diferencia de `PathSanitizer.sanitizeFilename` (trunca desde el final del nombre COMPLETO, lo que mutilaría justo el sufijo ` SxxEyy` que `parse_sxxeyy()` del firmware necesita), el presupuesto de bytes se calcula ANTES y solo `seriesName` se recorta. `writeCategoryIndexes(items:destinationByItemID:)` (junto a `writeRatings`, mismo patrón: solo items realmente presentes tras el sync, sin entradas → borra el archivo): mapeo doble idioma para video (`MediaCategory.movies/series.displayNameSpanish/English`, D-283) y de tres nombres fijos para foto (`"Fotos"→photo`, `"IA"→ai`, cualquier otra cosa —incluida una colección personalizada, D-228— `→image`). `writeSeasonPosters(items:)`: por cada `(seriesName, season)` presente, toma la carátula del episodio de menor número y la escribe en `seasonPosterRelativePath(seriesName:season:)` ("Videos/\<seriesName\> S%02d.jpg", mismo prefijo saneado que sus episodios) solo si el contenido cambió. `DeviceSyncIndexBuilder.ownedDevicePaths` (`DeviceSyncIndex.swift`) reconoce el póster de temporada vía `seasonPosterRelativePath(fromEpisodeDestinationRelativePath:)` (regex inversa) para que no aparezca como "solo en el iPod" — igual que ya hacía con el póster por video. `deleteAllDeviceContent(kinds:)` borra los dos `.cfg` cuando se limpia video/foto (no tienen registro propio en el manifiesto).

**Hecho**: `Models/LibraryItem.swift`, `Models/LibraryPersistence.swift`, `ViewModels/LibraryViewModel.swift` (persistCatalog/loadCatalog/migrateLegacySourceFile/process), `Services/LibrarySync.swift`, `Services/DeviceSyncIndex.swift`.

**Verificado**: `CategoryIndexWriterTests` 4 (mapeo doble idioma video, colección personalizada→`image`, sin video→archivo borrado), `LibrarySyncSeriesNamingTests` 11 (nombre exacto, truncado por bytes no caracteres preservando el sufijo, `destinationRelativePath` integrado con/sin campos resueltos, póster de temporada vía `sync()` real con JPEG sintético, gana el episodio de menor número), `LibraryPersistenceSeriesAlbumFieldsTests` 4 (roundtrip, catálogo viejo sin los campos nuevos sigue decodificando), `LibrarySyncDeleteAllContentTests` +1 (borra el índice de video, no toca el de fotos). Suite completa **501/501** (2 fallos = el flake de red ya conocido, sin relación). `xcodegen generate` + `xcodebuild` → **BUILD SUCCEEDED**.

**Pendiente**: UI de series (Tanda 4, cuadrícula/temporadas — estos campos ya quedan poblados desde ahora para cuando esa UI los use); **BARRERA 1** del plan: el dueño sincroniza su biblioteca real y confirma en hardware que Videos → Películas/Series muestran los archivos correctos, Movie Flow agrupa temporadas con póster, y Fotos → Fotos/Imágenes/IA filtran.

## ST-038 — Subsecciones de Video/Fotos en la barra lateral, arrastrar-para-categorizar, álbumes de fotos (campo + carpeta espejo) (Tanda 2 de `PLAN-biblioteca-medios-v2.md`)

**Encargo**: el dueño reportó "no veo los ajustes que solicité en la interfaz de Aura Studio" — la Tanda 1 (ST-037) es puramente de backend/exportación, invisible en la app; esta es la tanda que entrega lo que realmente se pidió: Video dividido en Películas/Series/Videoclips, Fotos dividido en Fotos/Imágenes/IA, y que arrastrar archivos a una de esas secciones los categorice solo.

**Diseño**: `SidebarSection` (`ContentView.swift`) — Video y Fotos pasan a ser grupos desplegables (mismo patrón que Música/`.musicGroup`, D-228): `.videoGroup` con `.videoMovies/.videoSeries/.videoClips/.video` ("Todos los videos"); `.photosGroup` con `.photosPhotos/.photosImages/.photosAI/.photos` ("Todas las fotos"). `SidebarView.body` se refactorizó a un `groupRow(group:subsections:isExpanded:)` genérico (antes solo existía para Música) para no triplicar la vista. **"Videoclips" en la barra usa el mismo valor de categoría que ya escribe la heurística automática** (`MediaCategory.videos.displayName`, "Videos") — un item clasificado sin pasar por esta subsección (soltado en "Todos los videos") sigue contando ahí, en vez de partirse en dos categorías equivalentes. Las 3 colecciones de Fotos en la barra usan los nombres literales fijos ("Fotos"/"Imágenes"/"IA", los defaults de `AppPreferences.photoCollections`) — **nunca se traducen** (D-228: son editables por el usuario, no un concepto de idioma, igual que en el resto de la app); Películas/Series sí salen de `MediaCategory.displayName` (ya bilingüe).

`MediaSectionView` gana `presetCategory: String? = nil` — filtra `items` (ademas/en vez del filtro manual de chips, que se oculta cuando hay `presetCategory` por redundante) y es la categoría que recibe todo lo que se suelte ahí. **Deliberadamente independiente de `scope`/`isEmbedded`**: el plan sugería condicionar el DropZone a `!isEmbedded`, pero `presetCategory` no toca `scope` (que solo acota álbum/artista de Música) — el DropZone normal ya queda visible sin ninguna condición extra, ajuste de ubicación sin cambiar el diseño (regla §4.1.1 del plan). `LibraryViewModel.addDroppedFiles(_:into:category:photoAlbum:)` (antes sin esos dos parámetros) asigna ambos al `LibraryItem` recién creado — `process(itemAt:)` ya respetaba una categoría pre-asignada (D-228, sin tocar).

**Fotos, único caso con hoja modal** (el dueño no pidió diálogo para Video): `PhotoImportSheet` (tipo preseleccionado vía `MediaCategoryClassifier.classifyPhoto` del primer archivo + campo álbum) al soltar en "Todas las fotos" (sin categoría resuelta); `PhotoAlbumNameSheet` (solo nombre, categoría ya la dio la barra lateral) al soltar **más de un archivo, o una carpeta**, dentro de una subsección ya categorizada — un archivo suelto no amerita el diálogo. "Sin álbum" es una salida explícita (los archivos igual se importan, sin agrupar). Campo nuevo `photoAlbum: String?` en `LibraryItem`/`PersistedLibraryItem` (mismo patrón opcional que `seriesName` de ST-037). `LibrarySync.localLibraryRelativePath` gana un nivel más cuando hay álbum (`Imágenes/<Colección>/<Álbum>/…`) — solo carpeta LOCAL (Finder), el iPod nunca lo ve (D-192, `/Photos` sigue plano).

**Deliberadamente fuera de esta pasada** (ya existía / queda para Tandas 3-4, no bloquea lo que el dueño pidió ver): "Mover a ▸" en menú contextual — ya existía como "Cambiar categoría" (D-228, mismo patrón `Menu`/`Button` por categoría), funciona sin cambios con las subsecciones nuevas. Cuadrícula de álbumes (`PhotoAlbumsView`, mosaico 2×2, renombrar/disolver álbum) y pósters de Películas/Series (`MoviesView`/`SeriesView`, Tanda 4) — el campo `photoAlbum` ya queda capturado y exportado desde ahora, la vista de cuadrícula es una capa encima que no bloquea ver/usar las subsecciones nuevas (siguen como tabla filtrada, igual que Música antes de ST-031).

**Hecho**: `Views/ContentView.swift` (`SidebarSection`, `SidebarView`, routing de `detail`), `Views/MediaSectionView.swift` (`presetCategory`, `handleDrop`, `PhotoImportSheet`, `PhotoAlbumNameSheet`), `Models/AppStrings.swift` (`videoAll/videoClips/photosAll`), `Models/LibraryItem.swift`/`Models/LibraryPersistence.swift` (`photoAlbum`, ya venían de ST-037), `ViewModels/LibraryViewModel.swift` (`addDroppedFiles`), `Services/LibrarySync.swift` (`localLibraryRelativePath` con álbum).

**Verificado**: `LibraryFolderDropTests` +3 (categoría/álbum preasignados viajan al item; sin preset quedan `nil`; sobrevive `processAll()` sin que la heurística los pise — JPEG sintético, D-303), `LibrarySyncLocalLibraryPathTests` +2 (carpeta de álbum, se ignora con "organizar por categoría" apagado). Suite completa **506/506** (sin el flake de red esta corrida). `xcodegen generate` + `xcodebuild` → **BUILD SUCCEEDED**. **Verificación visual real** (`open` sobre el `.app` compilado, con la biblioteca real del dueño ya configurada en esta Mac, captura de pantalla): la barra lateral muestra Música/Video/Fotos como los tres grupos desplegables descritos, "Fotos" seleccionada filtra la tabla a los archivos de esa colección, DropZone visible y funcional.

**No verificado por automatización** (UI-only, sin test dedicado — mismo criterio que "MediaCardView no requiere test de UI" del propio plan, Tanda 4): que soltar una carpeta sugiera su nombre como álbum en `PhotoAlbumNameSheet` (`suggestedAlbumName(for:)` es privada a la vista, lógica trivial y de bajo riesgo — verificada leyendo el código, no con una prueba automatizada).

**Pendiente**: **BARRERA 2** del plan (dueño, en Studio): arrastrar 3 fotos a "IA" → aparece la hoja de álbum; arrastrar 1 foto a "Fotos" → sin hoja; arrastrar a "Todas las fotos" → hoja con selector de tipo; cambiar la categoría de una foto desde el menú; sincronizar y comprobar `photo_categories.cfg`.

## ST-039 — Pin a v0.3.0-beta (D-322 en Aura-Firmware)

Encargo del dueño: publicar los commits pendientes (Tandas 1/2 del plan, ST-037/ST-038) y cortar release del firmware con la Tanda 3 (fotos de artista circulares en Artistas, D-322) para probar en hardware. `FIRMWARE_VERSION` → `tag=v0.3.0-beta`, hashes de `rockbox.ipod`/`rockbox.zip` actualizados (`mks5lboot`/`bootloader-ipod6g.ipod` sin cambios). `fetch-firmware.sh` verificó los 4 checksums contra el Release publicado, `AuraPalette.swift` sin diferencias. `swift build` limpio; sin cambios de código Swift en esta pasada.

## ST-040 — Películas y Series como cuadrícula de pósters, con detalle por temporadas (Tanda 4 de `PLAN-biblioteca-medios-v2.md`)

**Encargo**: Tanda 4 del plan aprobado — Películas y Series dejan de ser la tabla plana (heredada de la Tanda 2) y pasan a la cuadrícula de pósters (proporción 2:3 real) que el dueño pidió, con el detalle de una serie agrupado por temporada.

**Diseño**: `LibraryGrouping.swift` gana `VideoCollectionGroup`/`SeasonGroup` (mismo patrón en memoria que `AlbumGroup`/`ArtistGroup` — nada crea carpetas) y `videoCollections(from:)`: agrupa por `seriesName` normalizado si es un episodio de Series, por título normalizado si es película (o por su propio id si no tiene título, para no agrupar nunca con otra cosa); dentro de cada serie, temporadas ordenadas con un cajón **"Sin temporada"** (`noSeasonNumber = -1`) siempre al final para los episodios sin ese campo poblado — nunca se pierden silenciosamente. `MusicScope` (no se renombró a `LibraryScope`: el plan permitía sumar casos sin tocar cada sitio que ya lo usa, §4.1.1) gana `.videoCollection(String)`/`.season(String, Int)`.

`LibraryBrowsingComponents.swift`: `CoverArtView` gana un init `width`/`height` independientes (antes solo `side` cuadrado) — la caché de miniaturas sigue pidiendo un thumbnail cuadrado del lado mayor, recortado por `aspectRatio(.fill)` al encajar en el marco rectangular, no valía la pena una variante de caché solo para esto. `AlbumCardView` se generaliza en `MediaCardView(imageData:title:subtitle:badge:aspect:placeholderSymbol:)` con `Aspect.square`/`Aspect.poster(width:)`; `AlbumCardView` queda como envoltorio delgado sin cambio visual (confirmado: `AlbumsView` no se tocó).

`MoviesView.swift`/`SeriesView.swift` (nuevos): mismo patrón cuadrícula+detalle de `AlbumsView` (orden/búsqueda arriba, `LazyVGrid` adaptativa, back button). `MoviesView` embebe `MediaSectionView(scope: .videoCollection)` en el detalle (tabla, por si hay más de un archivo bajo el mismo título); `SeriesView` en cambio arma sus propias filas de episodio por temporada (patrón `ArtistsView.albumSection`), porque una tabla plana no puede mostrar los encabezados "Temporada N".

**Inspector** (`MediaInfoView.swift`): video no tenía NINGÚN campo de metadata editable antes de esto (solo categoría) — gana título editable siempre, y nombre de serie/temporada/episodio cuando la categoría ya es Series. `onVideoInfoChanged` nuevo (opcional, `nil` = la vista que abre la hoja no lo soporta); `LibraryViewModel.updateVideoInfo(id:title:seriesName:season:episode:)` nuevo — a diferencia de `applyReview` (música) no vuelve a preparar el archivo: el nombre de destino en el iPod se recalcula solo en el próximo `sync()` (`LibrarySync.destinationRelativePath`, ST-037, ya lee estos campos).

**Hecho**: `Models/LibraryGrouping.swift`, `Views/LibraryBrowsingComponents.swift`, `Views/MoviesView.swift` (nuevo), `Views/SeriesView.swift` (nuevo), `Views/MediaInfoView.swift`, `Views/MediaSectionView.swift` (switch de `scope` ampliado), `ViewModels/LibraryViewModel.swift`, `Views/ContentView.swift` (`.videoMovies`/`.videoSeries` enrutan a las vistas nuevas; `.videoClips` sigue como tabla, sin cambios — ya lo hacía desde la Tanda 2).

**Verificado**: `LibraryGroupingTests` +7 (`videoCollections(from:)`: ignora categorías que no son Películas/Series; película suelta = su propio grupo; serie con 2 temporadas agrupa por `seriesName` normalizado sin distinguir mayúsculas; episodio sin número de temporada va al cajón "Sin temporada" al final SIN IMPORTAR el orden de entrada; títulos con artículo inicial ordenan igual que álbumes; `displayNameEnglish` de Series también agrupa, D-283; póster sale de `coverArtData`). Suite completa **513/513**. `xcodegen generate` + `xcodebuild` → **BUILD SUCCEEDED**. **Verificación visual real** (`open` sobre el `.app` compilado, UI scripting vía `System Events` sobre la biblioteca real del dueño, capturas de pantalla): "Películas" muestra la cuadrícula de pósters reales (2 películas reales del dueño, con año); "Series" muestra el estado vacío correcto (el dueño todavía no tiene ningún episodio clasificado como Series).

**Pendiente**: **BARRERA 4** del plan (dueño, en Studio): confirmar que Películas muestra los pósters descargados en cuadrícula con contenido real de series una vez que sincronice/clasifique episodios; abrir una serie y ver temporadas/episodios; renombrar temporada/episodio desde el inspector y comprobar que Movie Flow reagrupa al re-sincronizar.

## ST-041 — Fotos de artista reales al iPod (Tanda 5, cierre de `PLAN-biblioteca-medios-v2.md`)

**Encargo**: última tanda del plan — `ArtistImageStore` (ST-032) ya descarga fotos de artista y las guarda en la biblioteca local, pero nunca viajaban al iPod; el firmware ya sabe leerlas y mostrarlas en círculo desde la Tanda 3 (D-322, contrato v6 §D.3), solo mostraba placeholders porque nadie las escribía del lado Studio.

**Diseño**: `LibrarySync.writeArtistImages(items:libraryRoot:)` (junto a `writeAlbumCovers`, mismo patrón de no ser diferencial — se reescribe completo en cada sync): para cada `ArtistGroup` (`LibraryGrouping.artists(from:)`) con imagen en `ArtistImageStore(libraryRoot:)`, escribe `.rockbox/aura/artists/<ArtistImageStore.fileName(forArtistKey:)>` reducida a **128 px** (`ImageResizer.resizeToLCDOptimal`, el mismo nombre de archivo que ya usa la caché local — un solo archivo compartido entre ambos lados, nunca dos copias de la misma foto) y una línea de índice `archivo: artista` por cada valor **crudo** distinto de `metadata.artist` entre las pistas del grupo (solo trim de espacios extremos, sin folding — el firmware compara byte a byte contra el tag real, D-322). Sin ninguna foto en la biblioteca → el índice se borra, nunca queda uno viejo apuntando a nada. `deleteAllDeviceContent(kinds: [.music])` limpia ambos (no tienen registro propio en el manifiesto, igual que los `.cfg` de categoría de video/foto). `sync-pending.json`: `changes.music = true` cuando se escribió o borró algo acá, aunque ningún archivo de música se haya copiado en ese sync (p. ej. el usuario solo agregó una foto de artista) — sin esto el firmware no se enteraría de invalidar su caché hasta el próximo cambio real de música.

Doc-comment de `ArtistImageStore.swift:9` y la regla de `CLAUDE.md` de Studio actualizados: "nunca viajan al iPod" → viajan reducidas a `.rockbox/aura/artists/`.

**Hecho**: `Services/LibrarySync.swift` (`writeArtistImages`, dos constantes de ruta nuevas, hook en `sync()` y en `deleteAllDeviceContent`), `Services/ArtistImageStore.swift` (doc-comment), `CLAUDE.md`.

**Verificado**: `ArtistImageExportTests` 5 (dos variantes de tag crudo comparten un solo jpg con dos líneas de índice; sin fotos guardadas → sin archivo ni índice; un artista con `:` en el nombre lo conserva completo como valor — el parser del firmware corta en el PRIMER `:` de la línea; la foto exportada mide ≤128×128 px de verdad, no solo de nombre; `deleteAllDeviceContent(kinds: [.music])` borra ambos). Suite completa **518/518** (2 fallos = el flake de red ya conocido, sin relación). `xcodegen generate` + `xcodebuild` → **BUILD SUCCEEDED**.

**Pendiente**: **BARRERA 5** del plan, cierre completo de `PLAN-biblioteca-medios-v2.md` (dueño, hardware): sincronizar con fotos de artista ya descargadas → en el iPod, Artistas debería mostrar las fotos circulares reales; quitar la foto de un artista en Studio, re-sincronizar → el iPod debería mostrar el placeholder de ese artista (confirma que `aura_artist_images_invalidate()` del firmware, D-322, reacciona bien al `changes.music` de este sync).

## ST-042 — Cuadrícula de álbumes de fotos, uso "a la iPod Classic" (fuera de plan, encargo directo del dueño)

**Encargo** (2026-08-19, tras cerrar `PLAN-biblioteca-medios-v2.md`): "constrúyela, que sea muy similar en cuestión de uso a lo que ofrecía el iPod Classic original" -- la cuadrícula de álbumes de fotos que el plan había dejado fuera de alcance en la Tanda 2 (§3.3: "cuadrícula de álbumes... queda para después"). El iPod Classic mostraba los álbumes de fotos como carpetas con portada, y adentro una CUADRÍCULA de miniaturas -- a propósito distinto del resto de Aura Studio (D-193: interfaz de gestión tipo Finder, tabla + Vista Previa con espacio), porque así es como se navegaban fotos en el aparato real.

**Diseño**: `LibraryGrouping.swift` gana `PhotoAlbumGroup` (grupo en memoria, mismo patrón que `AlbumGroup`/`VideoCollectionGroup` -- nada crea carpetas por sí solo) y `photoAlbums(from:category:)`: agrupa por `(categoría, photoAlbum normalizado)` -- la categoría entra a la clave a propósito, dos colecciones distintas pueden tener cada una un álbum con el mismo nombre sin mezclarse; "Sin álbum" siempre al final. `MusicScope` gana `.photoAlbum(String)`.

`PhotoAlbumsView.swift` (nueva): cuadrícula de `PhotoAlbumCardView` (mosaico 2×2 de las primeras 4 fotos, o la primera sola si hay menos) reemplaza la tabla plana que tenían las subsecciones Fotos/Imágenes/IA desde la Tanda 2 (Videoclips/"Todas las fotos" no se tocaron, siguen como tabla). El **detalle SÍ es distinto al resto de la app a propósito**: en vez de embeber `MediaSectionView` (tabla), es una `LazyVGrid` de miniaturas reales -- clic selecciona (borde de acento), doble clic o espacio abre Vista Previa (mismo `QuickLookCoordinator` de siempre, mismo gesto). Menú contextual por foto: Vista previa, Quitar del álbum, Mostrar en Finder, Eliminar. Álbum completo: Renombrar (hoja mínima, dejarlo vacío disuelve), Disolver.

**Arrastrar sigue funcionando** (`DropZone`/`PhotoAlbumNameSheet` de `MediaSectionView.swift`, promovidas de `private` a internas para reusarlas aquí sin duplicar código): sobre la cuadrícula de álbumes, mismo criterio que ya tenía la Tanda 2 (≥2 archivos o una carpeta preguntan nombre, uno solo entra sin álbum); soltar DENTRO de un álbum ya abierto va directo a ESE álbum, sin preguntar nada -- ya se sabe cuál es.

Las fotos de un `LibraryItem` nunca completan `metadata` (a diferencia de música/video, confirmado leyendo `process(itemAt:)` caso `.photo`) -- `PhotoAlbumGroup.previewImages`/la miniatura del detalle leen el archivo preparado (o el original) directo del disco, no `metadata.coverArtData`.

**Hecho**: `Models/LibraryGrouping.swift`, `Views/LibraryBrowsingComponents.swift` (`PhotoAlbumCardView`), `Views/PhotoAlbumsView.swift` (nuevo), `Views/MediaSectionView.swift` (`DropZone`/`PhotoAlbumNameSheet` ya no privadas, switch de `scope` ampliado), `ViewModels/LibraryViewModel.swift` (`renamePhotoAlbum`/`dissolvePhotoAlbum`), `Views/ContentView.swift` (`.photosPhotos/.photosImages/.photosAI` enrutan a la vista nueva).

**Verificado**: `LibraryGroupingTests` +6 (`photoAlbums(from:category:)`: solo la categoría exacta; el mismo nombre de álbum en dos categorías distintas NO se mezcla; sin álbum va al cajón "Sin álbum" al final; normalización sin distinguir mayúsculas/espacios; una cadena de solo espacios cuenta como sin álbum; ignora items que no son foto). Suite completa **524/524** (2 fallos = el flake de red ya conocido). `xcodegen generate` + `xcodebuild` → **BUILD SUCCEEDED**. **Verificación visual real** (biblioteca real del dueño, UI scripting + capturas): "Fotos" → "Sin álbum" (47 fotos reales) con miniaturas correctas, zona de arrastre visible dentro del álbum, selección de una foto con borde de acento -- todo funcionando contra archivos reales, no fixtures.

**Pendiente**: sin verificar a mano por el dueño todavía (renombrar/disolver álbum, arrastrar para crear uno nuevo con el diálogo de nombre) -- código y tests cubren la lógica, falta el uso real en Studio.

## ST-043 — Bug real: miniaturas distorsionadas (aspecto forzado a cuadrado en el `NSImage` reportado)

**Encargo**: el dueño, tras usar la cuadrícula de álbumes de fotos (ST-042): "las imágenes se ven distorsionadas, ayúdame a arreglarlas, al menos que cubran el cuadrado (aunque se recorten)".

**Causa**: `CoverThumbnailCache.decodeThumbnail()` construía `NSImage(cgImage:size:)` con `size: NSSize(width: side, height: side)` **fijo**, sin importar el aspecto real del `cgImage` decodificado. `kCGImageSourceThumbnailMaxPixelSize` solo acota el LADO MAYOR (una foto 16:9 decodifica a, p. ej., 280×157 px reales, nunca 280×280) — pero el `NSImage` resultante quedaba reportando "280×280" de todos modos. SwiftUI calcula `.aspectRatio(contentMode: .fill)` (usado en `CoverArtView`, todas las cuadrículas de Álbumes/Artistas/Películas/Series/álbumes de fotos) contra ese tamaño REPORTADO, no contra los píxeles reales del buffer — así que estiraba la imagen real para "llenar" un cuadrado que su contenido nunca tuvo, distorsión visible en cualquier foto que no fuera ya cuadrada (la inmensa mayoría). Bug preexistente desde ST-031, recién visible/reportado ahora que ST-042 agregó miniaturas reales de fotos del usuario (los álbumes/artistas de música rara vez traen carátulas muy alejadas de 1:1, por eso no se había notado antes).

**Arreglo**: el `size` del `NSImage` ahora sale de las dimensiones REALES de `cgImage` (`cgImage.width`/`cgImage.height`, entre la escala de pantalla usada al pedir el thumbnail) — el aspecto reportado coincide con el contenido real, así que `.aspectRatio(contentMode: .fill)` recorta correctamente en vez de estirar. Cero cambios en `CoverArtView`/`MediaCardView`/`PhotoAlbumCardView`: ya pedían "cover" correctamente, solo recibían metadata de aspecto mentirosa.

**Hecho**: `Services/CoverThumbnailCache.swift`.

**Verificado**: `CoverThumbnailCacheTests` 4 (nuevo -- 16:9 sintético reporta 16:9, no 1:1; fuente cuadrada sigue cuadrada; fuente vertical reporta más alto que ancho; `nil`/`Data()` vacío → `nil`). Suite completa **528/528** (sin el flake de red esta corrida). `xcodegen generate` + `xcodebuild` → **BUILD SUCCEEDED**. **Verificación visual real**: mosaico de "Imágenes" → "Sin álbum" con fotos reales del dueño, sin distorsión visible tras el arreglo (comparado contra la captura de antes del fix, donde sí se notaba).

## ST-044 — Selección múltiple estilo Finder en todas las cuadrículas de biblioteca, con arrastre de la selección completa hacia la barra lateral

**Encargo** (2026-08-19): "implementar una función de selección múltiple en todas las vistas de todos los medios, que se pueda seleccionar múltiples álbumes de música, artistas, o películas, series, episodios... esto para poder organizar de una forma más cómoda la biblioteca". Aclarado con `AskUserQuestion` antes de implementar: alcance = "Todo lo anterior + arrastrar la selección completa" (reasignar categoría/álbum en bloque, favorito en bloque, eliminar en bloque, Mostrar en Finder en bloque, MÁS arrastrar toda la selección hacia otra fila de la barra lateral). La cuadrícula de álbumes de fotos (ST-042) se confirmó que se queda tal cual (opción "Mantener la cuadrícula de tarjetas"). El tercer punto del encargo original ("una interfaz a pantalla completa, cuadrícula sin nombres, para desplazarse rápido") resultó ser sobre el **Firmware** (dispositivo), no Aura Studio -- corrección del dueño en la misma respuesta -- y queda fuera de este ST, para una sesión de `Aura-Firmware`.

**Diseño**: `Models/GridSelection.swift` (nuevo) -- dos piezas reusables:
- `GridSelection<ID: Hashable>`: selección estilo Finder para las cuadrículas propias (`LazyVGrid`, sin equivalente nativo de multi-selección como sí tiene `List`/`Table`). Clic = solo este elemento; Cmd+clic = alterna dentro/fuera; Shift+clic = rango desde el último tocado (`NSEvent.modifierFlags` leído en el momento del tap -- SwiftUI no expone el modificador del propio gesto). `effectiveIDs(for:)` da el criterio de Finder para menús contextuales/arrastre: si el elemento clicado ya estaba en la selección, actúa sobre TODA la selección; si no, solo sobre él -- mismo criterio que ya usaba `MediaSectionView.rowContextMenu` con `Table` nativo (`targetIDs = ids.isEmpty ? selection : ids`), ahora nombrado explícitamente y reusado.
- `LibrarySelectionTransfer` (`Codable & Transferable`, envuelve `[UUID]`): la carga que viaja con `.draggable(_:)`/`.dropDestination(for:)` (macOS 13+, confirmado disponible -- `project.yml` fija `macOS: "14.4"`).

Aplicado con `GridSelection` en las cuadrículas propias -- Álbumes, Películas, Series (cuadrícula de shows Y filas de episodios dentro de un show abierto, cada una con su propio `GridSelection`), álbumes de fotos Y fotos dentro de un álbum abierto (reemplaza el `selectedPhotoID: UUID?` de ST-042; el espacio de Vista Previa ahora exige exactamente 1 foto seleccionada). Clic simple selecciona/alterna; doble clic sigue abriendo el detalle (antes lo hacía el clic único) -- mismo par de gestos que ya usaba `PhotoAlbumsView.photoThumb` desde ST-042, ahora generalizado. Borde de acento compartido: `View.librarySelectionBorder(_:cornerRadius:)` en `LibraryBrowsingComponents.swift`.

Artistas usa `List(selection: Binding<Set<String>>)` en vez de `GridSelection` -- `List` ya da Cmd/Shift-clic nativo gratis con un `Set` como tipo de selección, más simple que reimplementarlo a mano. El detalle muestra un solo artista si hay exactamente 1 seleccionado; con más de 1, un resumen ("N artistas seleccionados") con los mismos botones masivos que el menú contextual.

Menús contextuales masivos: cada vista reusa los métodos YA existentes de `LibraryViewModel` (`setFavorite(_:forItems:)`, `deleteItems(ids:)`, `dissolvePhotoAlbum(items:)`) aplicados al set completo -- `setCategory(_:forItem:)` ganó un hermano `setCategory(_:forItems:)` (el único método que faltaba en versión masiva). Ningún método nuevo de mutación: la única pieza nueva de lógica es "cuántos y cuáles items" arma cada vista a partir de `effectiveIDs`.

Arrastre a la barra lateral: `SidebarView` (dentro de `ContentView.swift`) gana `onDropSelection: (String, Set<UUID>) -> Void` y `.dropDestination(for: LibrarySelectionTransfer.self)` en cada fila de `groupRow` -- `dropCategory(for:)` mapea solo 6 filas (`.videoMovies`/`.videoSeries`/`.videoClips`/`.photosPhotos`/`.photosImages`/`.photosAI`) a su categoría; el resto (incluida toda Música) devuelve `nil` y el drop no hace nada. **Música queda fuera del arrastre a propósito**: organiza por metadata de tag (`artist`/`album`), no por el campo `category` que sí tienen video/foto -- no hay "categoría" razonable a la que arrastrar un álbum. `ContentView` conecta el closure a `library.setCategory(category, forItems: ids)`.

**Hecho**: `Models/GridSelection.swift` (nuevo), `Views/LibraryBrowsingComponents.swift` (`librarySelectionBorder`), `Views/AlbumsView.swift`, `Views/ArtistsView.swift`, `Views/MoviesView.swift`, `Views/SeriesView.swift`, `Views/PhotoAlbumsView.swift`, `Views/ContentView.swift` (`SidebarView`), `ViewModels/LibraryViewModel.swift` (`setCategory(_:forItems:)`).

**Verificado**: `xcodegen generate` + `swift build` → **BUILD SUCCEEDED** (solo warnings preexistentes de `onChange(of:perform:)`, ninguno nuevo). Suite completa **528/528**. Sin tests nuevos dedicados -- `GridSelection` es lógica de gestos/estado de UI (Cmd/Shift-clic, rango) difícil de testear sin un harness de eventos de `NSEvent`, y las acciones masivas en sí reusan métodos de `LibraryViewModel` ya cubiertos por sus propios tests unitarios; el riesgo real está en el cableado de las vistas, no en lógica nueva no probada.

**Pendiente**: sin verificar a mano por el dueño todavía -- sesión corrió en background sin poder abrir la app real (`AuraStudio.xcodeproj`) para hacer clic/Cmd-clic/arrastrar de verdad. Falta confirmar en uso real: selección con Cmd/Shift-clic en cada cuadrícula, menús contextuales masivos, y sobre todo el arrastre de una selección completa hacia una fila de la barra lateral (drag-and-drop entre `NSTableView`s es lo más propenso a sorpresas que no aparecen compilando). El modo de pantalla completa del Firmware (tercer punto original del encargo) sigue pendiente, en `Aura-Firmware`.

## ST-045 — Pin a v0.3.1-beta (D-323 en Aura-Firmware)

Encargo del dueño: cortar release del firmware con la cuadrícula de miniaturas en Fotos (D-323, "modo de pantalla completa" pedido junto con ST-044, tercer punto que resultó ser del firmware) para poder instalarla desde Aura Studio. `FIRMWARE_VERSION` → `tag=v0.3.1-beta`, hashes de `rockbox.ipod`/`rockbox.zip` actualizados (`mks5lboot`/`bootloader-ipod6g.ipod` sin cambios, coherente con que D-323 solo tocó `apps/aura/aura_photos.c`). `fetch-firmware.sh` verificó los 4 checksums contra el Release publicado; `AuraPalette.swift` sin diferencias (D-323 no toca el sistema de diseño). `swift build` limpio; sin cambios de código Swift en esta pasada.

## ST-046 — Identidad del firmware instalado: separar "es Aura" de "habla el contrato de Aura" (contrato v8)

**Encargo del dueño (2026-08-20):** *"Ayúdame a que Aura Studio pueda reconocer qué firmware está instalado, para que en la sección de General aparezca correctamente el nombre del firmware y salgan las actualizaciones correspondientes."*

### El problema, con el hardware enfrente

El iPod del dueño tenía **Metro-Aura v0.4.0** instalado. Aura Studio lo reportaba como *"Firmware Aura instalado"*, le ofrecía el botón *"Reinstalar Aura"* y le consultaba actualizaciones al repositorio de **Aura-Firmware**, comparando el `v0.4.0` de Metro contra los tags de Aura.

Eso no era un detalle cosmético: **si se aceptaba esa actualización, Metro se perdía.** No había explotado todavía por pura aritmética — `0.4.0 > 0.3.1-beta`, el último tag de Aura — así que Studio decía "al día". El primer Release de Aura por encima de 0.4.0 habría convertido ese "al día" en un botón que borraba el firmware del dueño.

Peor: el respaldo por hash (`isUpdateAvailable`) compara contra el `rockbox.ipod` **embebido en la app**, que es el de Aura. Contra cualquier otro firmware el hash **siempre** difiere, así que esa ruta contestaba "sí, hay actualización" de forma permanente.

### Por qué la detección no existía

Las dos fuentes que `AuraDeviceProbe` ya distinguía (ST-016) no pueden contestar la pregunta:

- **Archivos en el disco**: Metro escribe el mismo árbol `.rockbox/aura/`. A propósito — implementa §D completo del contrato, y por eso sincroniza perfecto.
- **Descriptores USB**: los dos son forks de Rockbox, se anuncian como `Rockbox.org` con el VID/PID de Apple (`USBDeviceIdentity.classify`).

### La decisión: un tercer hecho, no un tercer significado del mismo

Se agrega **`AuraDevice.declaredFamily`**, leído de `firmware_family` en `aura.cfg` (contrato **v8**). Va aparte de los otros dos por la misma razón que ellos van aparte entre sí: contesta otra pregunta.

Y el cambio central, que es de nombres pero no es cosmético: **`isAura` se llama ahora `supportsAuraContract`**. Esa propiedad hacía dos trabajos a la vez —"la identidad es Aura" y "el contrato de biblioteca funciona aquí"— y para Metro el segundo es verdadero y el primero falso. Quien quería preguntar lo primero obtenía la respuesta de lo segundo. Ahí vivía el bug.

- `supportsAuraContract` — **capacidad**. Sigue siendo `true` para Metro, y **debe** serlo: biblioteca, sync, contadores, nombre del iPod y reloj funcionan igual. El sync real con Metro ya estaba verificado en hardware.
- `isAuraFirmware` — **identidad**. `supportsAuraContract && declaredFamily == .aura`. Es lo que decide nombrar el firmware, ofrecer el Release de Aura e instalar.

Los temas no necesitaron nada: ya se decidían por `theme_format_supported`, que Metro no escribe. Es el precedente exacto de esta separación.

**Ausente = Aura.** No es un fallback defensivo, es el contrato: Aura-Firmware nunca escribió esta clave, así que su ausencia es su firma. El cambio es retrocompatible **sin tocar el firmware de Aura**. Metro ya la escribía desde antes (M-004), esperando esta lectura.

**Un valor desconocido NO es Aura.** Un firmware que se declara está diciendo que es otra cosa; tratarlo como Aura repetiría el bug con un firmware futuro. Sin repositorio conocido, Studio calla en vez de arriesgarse.

### Qué cambia en pantalla

- **General** nombra el firmware por lo que declara (`Firmware Metro instalado`), no por el árbol que encuentra.
- **La sección de actualizaciones** consulta el repositorio de la familia (`Ricolinos/Metro-Aura`) y nombra el tag. Para un firmware hermano **no aparece el botón de instalar** — aparece *"Ver el Release de Metro"*: Studio solo empaqueta el firmware de Aura, así que "Instalar actualización" no lo actualizaría, lo reemplazaría. Se dice eso con todas sus letras.
- **El Instalador** deja de decir *"Reinstalar Aura"* sobre un iPod con Metro, y su nota advierte que instalar Aura reemplaza Metro y que los ajustes de Metro se pierden (la música y las fotos no se tocan).
- **El cache de Releases es por familia.** Con una sola llave, conectar un iPod con Metro y luego uno con Aura le habría mostrado al segundo los tags del primero durante las 24h del TTL.

### Verificación

16 pruebas nuevas (`FirmwareFamilyTests`), 544 en total en verde. Además, corrido contra el iPod real montado: familia `metro`, `supportsAuraContract` `true`, `isAuraFirmware` `false`, repositorio `Ricolinos/Metro-Aura`.

Límite anotado en la propia prueba: en el arnés de SwiftPM no hay firmware embebido, así que `testHashFallbackNeverFiresForOtherFamilies` fija el contrato ("nunca `true` para otra familia") pero no puede distinguir por cuál de las dos guardas sale. La guarda de familia es la primera línea de `isUpdateAvailable` justamente para que el orden no dependa de si hay artefactos.

### Fuera de alcance, deliberadamente

Instalar Metro **desde** Aura Studio (el selector de firmware en Extras que pidió el dueño en el mismo encargo). Requiere un segundo juego de artefactos empaquetados y arrastra una obligación GPL §B que hoy está sin cumplir: la pantalla de Licencias que el contrato promete no existe (ver la nota de `DECISIONS.md` sobre §B). Se documenta aparte, no se implementa aquí.

## ST-047 — Aura Studio instala dos firmwares: selector en Extras, empaquetado por familia, y la pantalla de Licencias que faltaba (contrato v9)

**Encargo del dueño (2026-08-20):** *"Aura Studio le dé oportunidad al usuario de usar Metro-Aura o Aura como firmware personalizado para el iPod… en la sección de 'Extras' es donde vamos a poner la opción… recuerda que este proyecto es gratuito; si encuentras un tema con las licencias, confío en que sabrás resolverlo, ya que no quiero distribuir software que no es mío para hacer negocio. Ayúdame a implementarlo de una vez por todas."*

### Licencias primero
Las dos familias son GPL v2, derivadas de Rockbox. La GPL permite distribuirlas (incluso con fines comerciales, que aquí no los hay) con una condición concreta: ofrecer la fuente. El contrato (§B) fijaba desde v1 **cómo** la cumple Studio —una pantalla de Licencias con repositorio, tag exacto y `MODIFICATIONS.md`— y esa pantalla **no existía** (`DECISIONS.md`, nota de D-290). Con un solo firmware, propio, era deuda; con un segundo firmware GPL a bordo sería incumplimiento. Así que `LicensesView` va **antes** que el selector: Extras › Licencias lista cada familia embebida con su repositorio, la versión exacta incluida, la fuente de ese tag, y enlaces a `MODIFICATIONS.md` y `THIRD-PARTY-NOTICES.txt` del Release. El tag se lee de `firmware-version.txt`, que `fetch-firmware.sh` deja junto a los artefactos — nunca de una constante a mano que pueda envejecer respecto a lo que se empaquetó. La pantalla dice también, con todas sus letras, que Aura Studio es gratuita y sin fines comerciales.

### Empaquetado: Aura no se mueve, Metro va en `metro/`
Cuatro sitios asumían un solo firmware. La regla para tocarlos fue *cero riesgo para Aura*:
- `FIRMWARE_VERSION`: sección por familia; sin prefijo = Aura (idéntico a lo que había), `metro.` = Metro-Aura.
- `scripts/fetch-firmware.sh --family aura|metro` (por defecto las dos). Metro aterriza en `Vendor/firmware-dist/metro/`. La limpieza previa pasa de `rm -f dir/*` a `find -maxdepth 1 -type f -delete` para que limpiar una familia no borre la otra. Escribe `firmware-version.txt`.
- `project.yml`: la carpeta `metro` entra como **referencia de carpeta** con `buildPhase: resources` → `Resources/metro/`. Así los dos `rockbox.ipod`/`rockbox.zip`/`mks5lboot` conviven sin chocar. Verificado con `xcodebuild` real: el bundle trae `Resources/firmware-version.txt` (`v0.3.1-beta`) y `Resources/metro/…` completo (`v0.4.0`). La fase que restaura el bit de ejecución de `mks5lboot` cubre los dos.
- `BundledArtifacts(bundle:family:)` resuelve con `subdirectory:`; `.shared` sigue siendo Aura; `forFamily(_:)` da el otro. `releaseTag` lee el marcador.

### El instalador instala "la familia objetivo"
`InstallerViewModel.targetFamily`: la fija `start(mode:)` desde la preferencia de Extras; `startAutomaticUpdate()` la **sobreescribe con la familia detectada** en el iPod (`declaredFamily`, ST-046) — una actualización jamás cambia de firmware a nadie. De ahí salen artefactos, runner (`MKS5LBootRunner(artifacts:)`: mks5lboot y bootloader de esa familia), textos y el centinela del árbol, que ahora es por familia (`FirmwareFamily.installedTreeSentinel`): con el de Aura (`a26-title-20.fnt`), **toda instalación de Metro habría fallado como "incompleta"** tras extraerse bien.

Al cambiar de familia, el instalador borra `.rockbox/aura/aura.cfg` del firmware saliente: sus ajustes no le sirven al entrante y, peor, Aura habría encontrado un `firmware_family: metro` que no es suyo y Studio lo habría seguido llamando Metro hasta el primer arranque (Aura regenera el archivo entero al guardar, así que el transitorio duraría exactamente eso). Reinstalar la misma familia lo conserva, como siempre prometió.

### Dónde vive la elección
En **Extras**, como pidió el dueño: dos tarjetas-radio (`FirmwareChoiceCard`, misma forma que `BootModeCard` del instalador) con el tag embebido como insignia y una línea que dice qué pasa con lo que ya hay en el iPod. Es una **preferencia** (`AppPreferences.firmwareFamilyToInstall`, Aura por defecto; un valor guardado desconocido cae a Aura), no una acción: elegir no toca el iPod, el Instalador sigue siendo el único que escribe. El `ModePickerView` del Instalador muestra *"Firmware a instalar: Metro — se elige en Extras › Firmware"* y sus textos ("Instalar Metro", "Reinstalar Aura", las notas de DFU) salen de la familia elegida y de la detectada.

**Extras quedó fuera del candado de biblioteca** (`ContentView`, `section != .extras`): ese candado se puso para que nadie sincronizara contra un firmware que no habla el contrato, pero dejaba Extras inaccesible justo con un iPod de fábrica — el momento en que elegir firmware importa más. Las filas de Extras que escriben en el iPod (Temas) ya se deshabilitan solas.

### General
El botón *"Instalar actualización de …"* vuelve para **cualquier familia instalable** (ST-046 lo había quitado para todo lo que no fuera Aura porque no había otro firmware embebido); para una familia desconocida sigue el enlace a su Release. El respaldo por hash de `AuraUpdateChecker` compara cada familia contra **su** binario embebido.

### Verificación
`swift test` 544 en verde (6 nuevos: `FirmwareFamilyPackagingTests` — resolución por subdirectorio, familia sin carpeta = fallo explícito, centinela por familia, preferencia persistida y su caída a Aura). `xcodebuild` Debug compila y el bundle tiene la forma descrita. **Sin instalación real de Metro desde Studio contra el iPod en esta pasada** — queda como la prueba de hardware de la ronda.

## ST-048 — Pin de Metro-Aura a v0.5.0 (Ronda 5 del firmware)

Primer Release de Metro-Aura que Studio empaqueta (ST-047 se hizo con v0.4.0 como prueba de empaquetado). v0.5.0 trae M-081 (About ya no lee disco por cuadro — el cuelgue en hardware), M-082 (espaciado "ll"), M-083 (reproductor rediseñado, volumen 00–15, límite de volumen), M-084 (barra de estado) y M-085 (hub). Mismos assets y mismo `checksums.txt`; `fetch-firmware.sh --family metro` verificó los cuatro hashes. Instalado en el iPod del dueño por Terminal en la misma sesión (fuera de Studio — la instalación real de Metro *desde* Studio sigue pendiente como prueba de hardware de ST-047). Aura sigue en v0.3.1-beta (ST-045).

## ST-049 — `scripts/build-app.sh`: la build que se prueba es la que se empaqueta

**Reporte del dueño:** *"intenté probar instalar desde ahí el firmware y no me apareció la opción."* La app que abrió era la Debug que Xcode dejó en `DerivedData` el 19 de agosto al pulsar Run — anterior a ST-047. Ningún `AuraStudio.app` de la máquina tenía el código nuevo; no había nada que instalar "mal", solo una app vieja.

**Decisión.** Un script que hace la build real y la deja donde se abre: `scripts/build-app.sh` = `fetch-firmware.sh` (las dos familias) → `xcodegen generate` → `xcodebuild -configuration Release` (firma ad-hoc "Sign to Run Locally", la de `project.yml`) → verificación del bundle (`codesign -vv`, `Resources/{,metro/}rockbox.ipod` y `firmware-version.txt`, bit de ejecución de ambos `mks5lboot`) → `ditto` a `/Applications/AuraStudio.app`. Documentado en `docs/guia-desarrollo.md`. La primera corrida real dejó en `/Applications` una app con Aura v0.3.1-beta y Metro v0.5.0 embebidos.

## ST-050 — Se quita la opción de dual boot del instalador: siempre "Solo firmware"

**Reporte del dueño (2026-08-23):** *"acabo de descubrir que no es funcional el dualboot cuando se instala desde el mac, ayúdame a quitar la opción de Aura Studio."*

El paso "Modo de arranque" ofrecía *Dual boot* (recomendado) y *Solo Aura*. La propia tarjeta de dual boot ya advertía la condición: requiere un iPod en formato "winpod" (restaurado con iTunes en Windows); un iPod restaurado desde Mac usa particiones que Rockbox no lee. Ese es el caso de este proyecto, y el dueño lo confirmó en hardware: el arranque de Apple no funciona. Ofrecer como "recomendado" algo que no funciona en el único hardware real que tenemos es peor que no ofrecerlo.

**Decisión.** El paso desaparece del asistente (`InstallerStep.chooseBootMode` queda en el enum sin visitarse; `BootModeView.swift` se elimina). `destroyOriginalFirmware` es `true` por defecto y `advanceFromWelcome()` lo fija así en toda instalación nueva → `mks5lboot --bl-inst --single`, con el orden de ST-017 (formatear → DFU → copiar por el modo USB del bootloader). **La confirmación destructiva no se pierde, se muda**: la Bienvenida muestra la advertencia en rojo ("el firmware original de Apple se borra del arranque… para volver hay que restaurar con iTunes/Finder") y exige marcar *"Entiendo que el arranque de Apple se borra"* para poder continuar (`BackContinueRow.continueDisabled`). Y dice por qué ya no hay dual boot, para que nadie lo busque.

**Lo que NO cambia:** `startAutomaticUpdate()` sigue poniendo `destroyOriginalFirmware = !isDualBoot` — si un iPod YA está en dual boot funcional (instalado desde Windows), actualizar no destruye ese arranque de Apple. `DoneView` conserva su aviso de combinación de botones para ese caso. La detección y los textos de General que dicen "dual boot con Apple" describen lo que hay, no lo que se instala, y se quedan.

544 pruebas en verde. App reempaquetada con `scripts/build-app.sh`.

## ST-051 — La ventana en blanco de Release: nunca `@ObservedObject private var x = Singleton.shared`

**Reporte del dueño:** *"la aplicación se colgó, le di en instalar aura y se quedó así"* (captura: ventana entera en blanco, barra lateral incluida). Reproducido de forma determinista: en la build **Release**, seleccionar Instalador o Extras dejaba de pintarse toda la ventana. No era un cuelgue —el hilo principal estaba ocioso y el árbol de accesibilidad tenía todos los elementos—, era que nada se dibujaba. En **Debug** la misma fuente pintaba perfecto, y la bisección lo dejó en una sola línea: `@ObservedObject private var preferences = AppPreferences.shared` dentro de `ModePickerView` (y la misma en `ExtrasView`, ST-047). Quitarla arregla el pintado.

**Decisión.** Las vistas **reciben** `AppPreferences` inyectada (`@ObservedObject var preferences: AppPreferences`, desde el `@StateObject` de `ContentView`), que es el patrón que `MediaSectionView` ya usaba; `ModePickerView` lee `AppPreferences.shared` en una propiedad calculada (se reconstruye al volver a la sección). Regla para el repo: un `@ObservedObject` con valor por defecto al singleton no se vuelve a escribir. Verificado en Release con captura de ventana: General, Extras e Instalador pintan.

**Daño colateral del episodio, y qué se hizo.** La ventana se quedó en blanco *a mitad del asistente*, pero el asistente siguió corriendo: el iPod quedó con **Aura v0.3.1-beta** encima de Metro v0.5.1 (`rockbox.ipod` de Aura a las 03:15:52, `aura.cfg` regenerado sin `firmware_family` por la limpieza de cambio de familia de ST-047 + `ClockSyncWriter`). No fue un fallo del instalador: la preferencia de Extras estaba en su default (Aura) y el botón decía "Instalar Aura"; el dueño, que quería probar la instalación de Metro desde Studio, pulsó lo que había. Se restauró Metro v0.5.1 por Terminal en la misma sesión. Lección de UX anotada, sin implementar: la primera vez que Studio ve un iPod con una familia instalable distinta de la preferencia, convendría proponerla como default.

## ST-052 — El paso "Buscando tu iPod" no avanzaba con el iPod ya conectado; y las pantallas decían "Aura" instalando Metro

**Reporte del dueño:** *"ya probé instalar metro desde studio y tampoco funcionó."* Reproducido por accesibilidad con el iPod conectado en modo disco: Extras › Metro → Instalador → "Reinstalar Metro" → Bienvenida (casilla) → Permisos → **"Encontramos "IPOD". Preparando el siguiente paso..."** y ahí se quedaba indefinidamente. Pulsando "Ya lo conecté, continuar igual" la instalación corría completa en ~10 s y llegaba a Listo (verificado: `rockbox.ipod` v0.5.1 de Metro en raíz y en `.rockbox/`, `firmware_family: metro` conservado porque la familia no cambió).

**Causa.** `DetectDeviceView` solo llamaba `onDeviceReady()` desde `.onChange(of: monitor.state)`: si el iPod ya estaba en modo disco FAT32 al llegar al paso, el estado no cambia y nada dispara. El texto prometía "preparando" y el botón de escape estaba descrito solo para los casos de formateo. Preexistente — el camino automático de "Actualizar" (D-222) nunca pasa por esta vista.

**Arreglo.** `.onAppear` con el mismo criterio que `onChange` (solo `.diskMode` FAT32; los estados que implican formatear siguen pidiendo el clic explícito). Y las pantallas de progreso y de Listo (`SimpleProgressView`, `DoneView`, `AutomaticUpdateView`) reciben el nombre de la familia: instalar Metro ya no dice "Instalando Aura" ni "Aura instalado".

544 pruebas. Verificado en Release, de punta a punta por accesibilidad, con el iPod real.

## ST-053 — La Bienvenida "se quedaba pasmada": un botón deshabilitado no explica nada

**Reporte del dueño:** al instalar Aura, *"sigue con el mismo problema… se queda pasmado"*. La app estaba en la Bienvenida; en cuanto se marcó la casilla y se pulsó Continuar, todo corrió (Aura v0.3.1-beta instalada sobre Metro en ~4 min, con el cambio de familia limpiando `aura.cfg` como está previsto).

**Causa.** ST-050 dejó "Continuar" **deshabilitado** hasta marcar *"Entiendo que el arranque de Apple se borra"*. Correcto como bloqueo, pésimo como interfaz: un botón gris que no hace nada se lee como cuelgue, y la casilla, dentro de un recuadro de advertencia, no llama la atención como requisito.

**Arreglo.** El botón responde siempre. Sin la casilla, en vez de avanzar muestra en rojo *"Marca la casilla de arriba para continuar"* (desaparece al marcarla). La confirmación sigue siendo obligatoria; lo que cambia es que la app contesta.

## ST-054 — Segundo caso de ventana en blanco en Release: `.fixedSize(horizontal: false, vertical: true)`

**Reporte del dueño:** al instalar Metro, la app "se queda pasmada" otra vez. Diagnóstico en vivo, sin interrumpir: la ventana estaba en la **Bienvenida**, con el árbol de accesibilidad completo (casilla sin marcar, botones habilitados) y **nada pintado** — el mismo síntoma de ST-051, que esa vez se había verificado en General/Extras/Instalador pero no en la Bienvenida (la captura de ese paso existía y no se había mirado: 13 colores, en blanco).

**Causa.** `.fixedSize(horizontal: false, vertical: true)` sobre los `Text` largos de `WelcomeView` (ST-050) y `LicensesView` (ST-047). En Debug es inocuo; en Release deja la ventana entera sin pintar. Quitarlo basta: los textos siguen envolviendo bien dentro de su `frame(maxWidth:)`.

**Regla acumulada para este repo** (junto con ST-051): en Release, dos modificadores han dejado la ventana completa en blanco sin log ni crash — `@ObservedObject` con valor por defecto a un singleton, y `.fixedSize(horizontal: false, vertical: true)` en texto. Ninguno se vuelve a escribir, y **toda pantalla nueva se verifica en la build Release** (`scripts/build-app.sh`), no solo en Debug ni en `swift test`.

Verificado en Release: Bienvenida y Licencias pintan.

## ST-055 — Pin de Aura a v0.3.2-beta (D-325: listas sin tope de 300)

Mismo defecto que M-087 en Metro, corregido del lado de Aura en su propia sesión (D-325): Canciones ya no se corta en 300. Sin cambio de contrato ni de `AuraPalette.swift` (byte-idéntica a la de v0.3.1-beta). `FIRMWARE_VERSION` actualizado con los cuatro hashes verificados por `fetch-firmware.sh`; Metro sigue en v0.5.3.

## ST-056 — Dos firmwares instalados a la vez: cambio por renombre, sin borrar ni descargar (contrato v10)

**Encargo del dueño (2026-08-23):** *"si el usuario quiere cambiar de firmware, que no se elimine la instalación previa… que no se tenga que estar borrando y descargando la carpeta"*, y la pregunta de si `.rockbox` podría llamarse `.aura`/`.metro`.

**Decisión de diseño, conversada.** El árbol activo **sigue siendo `/.rockbox/`**: es la única ruta que el bootloader compartido (NOR, DFU) sabe arrancar y la que ambos firmwares y sus plugins llevan compilada; renombrarla obligaría a reflashear en cada cambio, justo lo que se quiere evitar, y además tocaría todo §D (v10) y chocaría con `/.aura/` (marcador de sync). Los árboles **dormidos** sí llevan nombre propio: `/.firmware-aura/`, `/.firmware-metro/` — un `.rockbox` completo, en reposo, **con sus propios ajustes** (bono respecto a antes: cambiar y volver ya no resetea nada). Un "archivo switch" que lea el bootloader sería un bootloader distinto; en FAT un renombre de directorio es instantáneo y logra lo mismo. Contrato **v10** escrito antes, copia idéntica en ambos repos.

**`FirmwareSwitcher`** (puro sobre `FileManager`, 9 pruebas): `switchActiveFirmware(to:currentlyActive:)` ejecuta la secuencia del contrato — saliente `/.rockbox/` → `/.firmware-<saliente>/` **primero** (el peor corte deja un dormido entero, nunca ninguno), entrante → `/.rockbox/`, `/rockbox.ipod` de raíz := el del entrante (el respaldo del bootloader debe ser siempre el activo), marcador `/.aura/sync-pending.json` con `music: true` (la base de música vive dentro de cada árbol). `repairIfNeeded` levanta un cambio a medias (sin activo y un solo dormido) y `IPodMonitor` lo llama al conectar, antes de sondear. `parkActiveTree` y `removeDormantTree` los usa el instalador. `mirrorContractFilesToDormantTrees` copia al final de cada sync los archivos del contrato (`sync_summary`, `sync_manifest`, `artist_images`+`artists/`, categorías, `ratings`, `device.cfg`) a cada dormido — `aura.cfg` y `themes/` no.

**Instalador.** Instalar la otra familia ya **no borra**: estaciona el activo como dormido (reemplazando un dormido anterior de esa familia) y extrae el nuevo en un `/.rockbox/` fresco; al terminar, quita un dormido de la familia recién instalada si lo hubiera (nunca un dormido de la activa) y rehace el respaldo de raíz. La limpieza de `aura.cfg` de ST-047 desaparece: ya no hace falta.

**Extras › Firmware.** La tarjeta elegida muestra el estado real: activa ("nada que hacer"), dormida ("Cambiar a … — un segundo, no descarga ni borra; después reinicia el iPod"), o no instalada ("Instalar …", al Instalador). El cambio corre bajo el candado de escritura del instalador y expulsa el volumen; el reinicio lo hace el usuario (SELECT + MENU). General menciona el dormido ("… — Metro también instalado, dormido").

**Detección:** `AuraDevice.dormantFamilies` por nombre de directorio; la activa sigue siendo `firmware_family` (v8).

**Orden acordado:** Studio (esto) → Metro-Aura (M-090: fila "Cambiar a Aura" en Ajustes, misma secuencia desde el firmware: guardar, renombrar, marcador, reinicio en seco) → Aura-Firmware (D-327).

## ST-057 — Pin a Aura v0.3.3-beta + Metro v0.5.4 (D-327 / M-090: cambio de firmware desde cada firmware)

Con esto las tres partes del contrato v10 están en producción: Studio (ST-056) estaciona, cambia, espeja y repara; cada firmware ofrece "Cambiar a …" en sus ajustes. `AuraPalette.swift` sin cambios. Hashes verificados por `fetch-firmware.sh` para las dos familias.

## ST-058 — Actualización selectiva por manifiesto: de 9 431 escrituras a ~5 (contrato v11)

**Encargo del dueño:** *"especificar qué archivos cambiaron… para que el actualizador pueda ser selectivo y no tener que eliminar todo el firmware viejo y descargar el nuevo completamente."*

**Dónde se iba el tiempo.** No en descargar (los binarios viajan embebidos): en **escribir**. Actualizar extraía el `rockbox.zip` completo — 9 431 archivos en Aura, 405 en Metro — y cada archivo chico paga su ida y vuelta USB+FAT en un disco de 1.8". Medido con los zips reales de dos releases consecutivos: **cambian 5 archivos (~1.9 MB) de 9 431** en Aura y 5 de 405 en Metro — las builds de Rockbox son reproducibles, así que todo lo demás es byte-idéntico.

**Diseño (contrato v11), sin tocar los firmwares ni el release.** El zip ya trae la lista de archivos con su CRC32 en el directorio central (`unzip -lv`, no se calcula nada). Al instalar, Studio deja en el iPod `.rockbox/aura/install_manifest.cfg` (cabecera + `tag:` + una línea `crc32 tamaño ruta` por archivo; los firmwares lo ignoran). Al actualizar **la misma familia**, compara el manifiesto del zip nuevo contra el instalado: extrae el zip a un temporal local (segundos en SSD), copia al iPod **solo lo nuevo/cambiado**, **borra lo que desapareció** (la extracción-merge dejaba huérfanos para siempre) y reescribe el manifiesto.

**Respaldo total, siempre**: sin manifiesto (instalación manual o pre-v11), cabecera de otra versión, delta mayor a un cuarto del zip, o cualquier error a mitad → extracción completa de siempre; nunca un firmware a medias. `delta()` además se niega a borrar fuera de `.rockbox/` pase lo que pase con un manifiesto corrupto. Es **por árbol** (v10): nunca se espeja a los dormidos (nota en `FirmwareSwitcher.mirroredContractEntries`). Salvedad documentada: un archivo tocado a mano que el manifiesto dé por idéntico no se repara en un delta — la reinstalación completa existe para eso.

`InstallManifest` (parseo del listado de unzip, serialización, diff) con 6 pruebas, una de ellas punta a punta con zips reales; 559 en total. La primera actualización tras esto sigue siendo completa (escribe el primer manifiesto); la ganancia empieza en la segunda.

## ST-059 — Sello de biblioteca: el cambio de firmware ya no reconstruye la base sin motivo (contrato v12)

**Reporte del dueño:** cada cambio de firmware costaba ~5 min de "optimización" en ambos sentidos, sin que la biblioteca hubiera cambiado. La causa era nuestra: el cambio (v10) dejaba el marcador con `music: true` incondicionalmente.

**v12**: `/.aura/library-stamp` — Studio lo **renueva en cada sync que toca música** (`writeSyncMarkerIfNeeded`, junto al marcador); es LA definición de "la biblioteca cambió". Cada firmware anota en su árbol (`.rockbox/aura/db_stamp.txt`, **nunca espejado**) contra qué sello construyó su base. `FirmwareSwitcher.switchActiveFirmware` compara el sello del árbol entrante con el compartido: iguales → sin marcador (cambio instantáneo); distintos o sin anotar → marcador como antes. Arranque en frío: si el sello no existe, se crea y se anota al saliente, cuya base está al día. Tres pruebas nuevas (arranque en frío, ida-y-vuelta sin marcador, sync de por medio sí marca); 562 en total. Mismo mecanismo en los firmwares (M-091 / D-329).

## ST-060 — Pin a Aura v0.3.4-beta + Metro v0.5.5 (contrato v12 en producción en las tres partes)

Ambos releases traen D-329/M-091 (sello de biblioteca). Con este pin, la actualización desde Studio de cada firmware será la última completa (deja el primer `install_manifest.cfg`, ST-058); las siguientes serán selectivas.

## ST-061 — Sembrar los archivos del contrato al árbol recién instalado (el "sin sincronizar todavía" de Metro)

**Reporte del dueño:** con Metro activo, canciones bien pero sin fotos de artista, videos/fotos sin categorías y "Acerca de" diciendo "sin sincronizar todavía" — mientras que en Aura todo bien.

**Causa estructural.** Los archivos del contrato (`sync_summary.cfg`, `artist_images.cfg` + `artists/`, `*_categories.cfg`, `ratings.cfg`, `device.cfg`) viven **dentro del árbol**. Una instalación fresca de la otra familia extrae un `.rockbox` nuevo **sin ellos**, y solo reaparecen en el siguiente sync completo con esa familia activa (el espejo de ST-056 corre en el sync, no en la instalación). Metro quedó instalado fresco y sin sus copias.

**Corrección:** `FirmwareSwitcher.seedContractFilesToActiveTree` — si el árbol activo **no tiene** `sync_summary.cfg` y un dormido sí, hereda de ahí el juego completo (los ajustes del activo no se tocan; con el activo ya poblado es no-op). Se llama al conectar el iPod (junto a la reparación de v10 — esto arregla el iPod del dueño con solo conectarlo) y al terminar una instalación (el recién estacionado es el donante). Dos pruebas nuevas; 564 en verde.

## ST-062 — Nombres con acento en NFC en todo archivo del contrato (contrato v13; "Avatar … el último …" invisible en Películas)

**Reporte del dueño (hardware real):** dos películas catalogadas desde Studio con su póster; solo la de nombre 100 % ASCII aparecía como película en el firmware. (El cartel ausente de la otra era un bug independiente del firmware, D-331.)

**Causa.** El driver `msdosfs` de macOS guarda los nombres largos de FAT32 **precompuestos (NFC)** pero se los reporta **descompuestos (NFD)** a las apps — las dos formas son indistinguibles a simple vista. `LibrarySync` serializaba lo que le daba `FileManager` (NFD) y el firmware compara byte a byte contra el UTF-16 que lee del disco (NFC): un nombre con acento no empareja jamás. Afectaba a `video_categories.cfg`, `photo_categories.cfg`, `ratings.cfg` (rutas de pistas con acento pierden su calificación) y a las rutas dentro de los `.m3u8` de `Playlists/` (el firmware ni siquiera puede ABRIR una pista con acento listada en NFD).

**Corrección (contrato v13, §D.2 y nota transversal):** `String.firmwareNFC` (`precomposedStringWithCanonicalMapping`) aplicado en los cuatro puntos de serialización de `LibrarySync`. `artist_images.cfg` queda fuera a propósito: su valor de emparejamiento es el tag crudo (D-322), no un nombre de archivo en FAT. Los índices ya escritos en NFD se corrigen solos en el siguiente sync (esos archivos se reescriben completos). Prueba nueva en `CategoryIndexWriterTests` con el nombre real del bug en NFD verificando que el cfg sale en NFC; suite completa en verde (571, dos flaky ajenas verdes al reintentar).

## ST-063 — Barra de estado contextual, barra de menús en español y detector de elementos similares

**Encargo del dueño (2026-08-23):** (1) una barra de estado al pie de cada sección "al estilo de la barra de estado del Finder", contextual — en Canciones, cantidad de canciones/artistas/álbumes y, con selección, cuántos elementos, artistas y álbumes están seleccionados; lo mismo, con sus propios conteos, en las 4 secciones de Música, 4 de Video y 4 de Fotos; visible por defecto y ocultable desde "Visualización". (2) La barra de menús de la app en español, con menús contextuales para las herramientas ya implementadas. (3) Detectar elementos "sospechosamente similares" (`"01 Amor"/"SodaStereo"` vs `"Amor"/"Soda-Stereo"`) en una ventana que permita decidir con cuál quedarse, eliminar o editar, con la sugerencia del programa según qué tan distintos sean.

**Barra de estado.** Un solo `LibraryStatusBar` en la raíz (`ContentView`, bajo el `detail` del `NavigationSplitView`); cada vista publica su resumen con `.libraryStatus(_:)` (un `PreferenceKey`), así ninguna vista sabe cómo se dibuja ni si está oculta. Los cálculos viven en `LibraryStats` (puro, testable): pluralización en español, duración ("8 h 12 min"), tamaño en disco (con caché por ruta, para no pagar miles de `stat` en cada cambio de selección) y un constructor por sección: `music`, `albums`, `artists`, `playlists`, `videos` (con desglose películas/episodios/videoclips en "Todos los videos"), `movies`, `series`, `episodes`, `photos` (desglose por colección), `photoAlbums`, `photoAlbum`. Con un álbum/película/serie/álbum de fotos abierto, la barra muestra ese grupo y lo seleccionado adentro (la tabla embebida ya publica `selectionForSync`, se reutiliza). `AppPreferences.showStatusBar` (default `true`) la alterna desde "Visualización › Mostrar barra de estado" (⌘/, como Finder).

**Menús.** El bundle declara español como ÚNICA localización (`Resources/es.lproj/InfoPlist.strings`, `CFBundleDevelopmentRegion = es`, `CFBundleLocalizations = [es]`, `developmentLanguage: es` en `project.yml`): así AppKit y SwiftUI arman los menús estándar (Aura Studio, Archivo, Edición, Visualización, Ventana, Ayuda y sus ítems: Salir, Ocultar, Copiar, Seleccionar todo, Ocultar barra lateral…) en español sin importar el idioma del sistema — no se reescriben a mano uno por uno. Lo propio (`AppMenuCommands.swift`, vía `FocusedValue` como `SyncCommandContext`): Archivo › "Agregar a la biblioteca…" (⌘O, `NSOpenPanel`, mismo camino que soltar archivos sobre la sección visible, con la categoría de la subsección) y "Sincronizar con el iPod" (⇧⌘S, ya existía); Visualización › barra de estado + "Ir a" cada sección (⌘0…⌘9); Biblioteca › "Buscar elementos similares…" (⌥⌘D) y "Mostrar carpeta de la biblioteca en Finder". Los menús contextuales de tabla y cuadrículas ya cubrían todas las herramientas (buscar info/letra/póster, releer etiquetas, favoritos, categoría, renombrar, lote, sincronizar selección, Finder, eliminar); se les suma "Buscar elementos similares…" en la tabla. El selector de idioma de Ajustes sigue aplicando solo a Ajustes/barra lateral (`AppStrings.swift`): la barra de menús queda fija en español, que es lo que pidió el dueño.

**Elementos similares.** `SimilarItemsDetector` (puro): huella por elemento (título sin número de pista ni paréntesis, calificadores de versión detectados — live/remix/acústico…, artista y álbum sin acentos ni puntuación, nombre de archivo sin " copia"/"(1)", duración, tamaño, extensión, clave de episodio), bloqueo por 2 primeras letras (3 000 canciones en fracciones de segundo, prueba de rendimiento incluida), comparación de a pares con Levenshtein normalizada y unión de pares en grupos (union-find). Tres confianzas: **Duplicado** (mismo tamaño exacto, o título+artista equivalentes con duración ±2 s), **Probable** (título+artista equivalentes, duración cercana o desconocida), **Posible** (parecidos con una diferencia legítima: otra versión, artista muy distinto pero mismo álbum). Cada grupo trae las razones en texto ("Artista escrito distinto: «SodaStereo» / «Soda-Stereo»", "Misma duración (3:20)"…), el elemento sugerido a conservar (`keepScore`: sin pérdida > con carátula/letra > corregido a mano > más metadata > más grande) y ediciones propuestas: unificar artista/álbum al nombre **más frecuente en toda la biblioteca** (`canonicalSpelling`) y quitar el número de pista del título. Video: mismo episodio (serie/temporada/episodio) o título+duración; fotos: nombre de archivo equivalente y/o mismo tamaño exacto. La hoja `SimilarItemsView` (menú Biblioteca, menú contextual de la tabla) lista los grupos con filtro por tipo y confianza, explica, deja cambiar cuál conservar, "Conservar el marcado y eliminar el resto" (con confirmación; la eliminación pasa por `deleteItems`, que jamás borra originales fuera de la carpeta de la biblioteca), "Aplicar la metadata sugerida" (`LibraryViewModel.applySimilarityEdits`, mismo camino que una corrección manual), "Editar…" por elemento (`MediaInfoView`), "Eliminar solo este", "Mostrar en Finder" e "Ignorar este grupo" (`AppPreferences.ignoredSimilarGroups`, id estable por conjunto de miembros, restablecible desde el pie). Nunca borra ni edita nada por su cuenta.

**Pruebas:** `SimilarItemsDetectorTests` (normalización, el ejemplo exacto del dueño, versión en vivo → posible, duraciones distintas → nada, canónico por frecuencia, sugerencia FLAC+carátula, ignorados, fotos copia, episodio repetido, rendimiento, resúmenes y formatos de la barra de estado).

## ST-064 — Eliminar un duplicado no debe borrar el preparado que comparte con el que se conserva

**Reporte del dueño (2026-08-23, recién instalada la build de ST-063):** al sincronizar, "No se pudo sincronizar en /Volumes/IPOD: El archivo "01 - Ain't No Sunshine.mp3" no ha podido abrirse porque no se encuentra". El catálogo tenía 4 canciones en "Listo" cuyo `.preparados/<nombre>.mp3` ya no existía; las 4 eran duplicados recién depurados desde "Elementos similares".

**Causa.** `.preparados/` es una carpeta PLANA nombrada por el nombre del archivo de origen (`prepareMusic`), así que dos elementos con el mismo nombre — exactamente el caso de un duplicado — comparten el mismo preparado. `deleteItems` borraba el preparado del eliminado sin mirar si otro elemento lo seguía usando, y el que se conservaba quedaba "Listo" apuntando a nada. El bug existía desde antes (también aplicaba a "Eliminar" del menú contextual sobre uno de dos duplicados); la hoja nueva solo lo hizo cotidiano. Al reiniciar la app, `loadCatalog` ya re-encolaba esos elementos ("Listo sin preparado no es listo"), por eso solo se veía dentro de la misma sesión.

**Corrección.** `deleteItems` calcula los preparados que siguen en uso por los sobrevivientes y solo borra un preparado (y su `.lrc`) cuando ninguno lo comparte. Prueba `LibraryViewModelSharedPreparedTests` con dos "01 - Ain't No Sunshine.mp3" de carpetas distintas. No se cambió el esquema de nombres de `.preparados/` (nombrarlo por id rompería los sidecars `.lrc` y los preparados existentes de todas las bibliotecas); queda como deuda documentada si vuelve a morder.

## ST-065 — Tercera familia moonlit.aura (contrato v14)

**Encargo del dueño (2026-08-26):** Studio distribuye e instala un tercer firmware, **moonlit.aura** (`Ricolinos/moonlit-aura`; lenguaje visual Waning Crescent, Material Design 3 adaptado al iPod), y debe convivir con tres árboles a la vez: uno activo en `/.rockbox/` y hasta dos dormidos (`/.firmware-aura/`, `/.firmware-metro/`, `/.firmware-moonlit/`).

**Qué se hizo.** `FirmwareFamily.moonlit` (`configValue "moonlit"`, `displayName "moonlit.aura"`, `bundleSubdirectory "moonlit"`, centinela `.rockbox/fonts/moonlit-body-18.fnt` — sin `/` inicial, como los otros dos, porque `InstallerViewModel` hace `appendingPathComponent`; `dormantTreeName ".firmware-moonlit"`). El selector de Extras tiene su tercera tarjeta; el icono de cada familia sale de la nueva `FirmwareFamily.symbolName` (`InstallerHomeView` dejó de decidir "si es Metro, tal icono"). Los textos de Extras y Licencias ya no enumeran "dos firmwares". `FirmwareSwitcher` y `dormantFamilies` no cambiaron: ya iteraban `installable`, y cuatro pruebas nuevas en `FirmwareSwitcherTests` lo fijan con tres árboles (lista de dormidos, cambio moonlit→Aura que no toca a Metro, espejo a los dos dormidos, reparación que no adivina entre dos dormidos).

**Temas por capacidad, no por familia.** moonlit no tiene sistema de temas y no publica `theme_format_supported` en `aura.cfg`. `AuraDevice.themeFormatSupported` (leído por `FirmwareCapabilities.supportedThemeFormat`) es lo que ahora habilita "Temas" en Extras junto a `supportsAuraContract`; deshabilitado, el botón dice "Este firmware no admite temas" (patrón ST-053). Es capacidad, no identidad: un Aura anterior a D-289 también cae en el caso deshabilitado, correctamente.

**Invariante:** `FirmwareFamily.installable` es la única lista de familias; añadir una es tocar el enum, `fetch-firmware.sh`, `project.yml`, `FIRMWARE_VERSION(.example)` y `build-app.sh` — nada más las enumera a mano; los iconos salen de `symbolName`.

**Pendientes del mismo lote:** el contrato v14 (`CONTRATO-firmware-studio.md`, copia idéntica de Aura-Firmware, que declara `firmware_family: moonlit` y la ausencia de `theme_format_supported` como válida) llega en este mismo lote; el pin `moonlit.tag=v0.1.0` en `FIRMWARE_VERSION` se registra en ST-066 al publicar el primer Release. Hasta entonces `Vendor/firmware-dist/moonlit/` está vacío y `build-app.sh` falla con mensaje claro (por diseño).


## ST-066 — Pin a Aura v0.4.0-beta + Metro v0.6.0 + moonlit.aura v0.1.0 (contrato v14)

**Releases (2026-08-26):** Aura-Firmware `v0.4.0-beta` (D-333/D-334/D-335), Metro-Aura `v0.6.0` (M-093/M-094) y el primer release de moonlit-aura, `v0.1.0` (D-046/D-047/D-048). Los tres traen el submenú "Cambiar sistema" con una fila por familia hermana, así que desde el dispositivo se puede ir de cualquier familia a cualquier otra que esté dormida; y los tres dejan de embeber `__TIME__`/`__DATE__` en los plugins SDL (quake/duke3d), que arrastraban ~2,2 MB de delta espurio en cada actualización selectiva.

**Pin:** `FIRMWARE_VERSION` con `tag=v0.4.0-beta`, `metro.tag=v0.6.0`, `moonlit.tag=v0.1.0` y los 12 hashes verificados por `scripts/fetch-firmware.sh` contra el `checksums.txt` de cada Release (los cuatro `OK` por familia). `CONTRATO-firmware-studio.md` v14 copiado idéntico desde Aura-Firmware (`diff` vacío). `scripts/build-app.sh` deja `/Applications/AuraStudio.app` con `Resources/moonlit/` (rockbox.ipod, rockbox.zip, mks5lboot, firmware-version.txt).

**Delta medido** (CRC32 por entrada del `rockbox.zip`, el mismo cálculo de `InstallManifest.delta`): Metro v0.5.6 → v0.6.0 = 7 archivos de 430; Aura v0.3.6-beta → v0.4.0-beta = 7 de 9 463. En ambos aparecen `quake.ovl`/`duke3d.ovl` **por última vez** (el parche mismo los cambió); a partir de aquí solo cambian los archivos que embeben `RBVERSION` (`rockbox.ipod`, `rockbox-info.txt`, `rockbox.map`, `lastfm_scrobbler.rock`, `version.txt`). Dos corridas consecutivas de `package_dist.sh` dan CRC idénticos en las 430/432/9 463 entradas; el SHA-256 del zip sí cambia (fechas de entrada), por eso el hash que fija el pin es el del Release publicado, no el de una recompilación local.

**Pendiente de hardware (usuario):** verificar en un iPod real el cambio entre las tres familias (C20 de cada firmware) y la medición de Marea (moonlit M12, D-043).

## ST-067 — Un árbol recién instalado que nunca arrancó se identificaba como Aura (y una instalación de Aura lo borraba)

**Reporte del dueño (2026-08-26, primer uso de las tres familias):** instaló moonlit.aura desde el Instalador, y sin desconectar cambió a Metro desde Extras. En el disco, el árbol de moonlit quedó estacionado como `/.firmware-aura` (verificado: `rockbox.ipod` con el SHA-256 de moonlit v0.1.0 y `fonts/moonlit-body-18.fnt` dentro). Al "actualizar los tres" después, la instalación de Aura borró ese "Aura viejo" — que era moonlit — y el iPod terminó solo con Metro v0.6.0 y sin dormidos; "Cambiar sistema" en el iPod decía "no instalado" en las dos filas, correctamente.

**Causa.** `FirmwareCapabilities.declaredFamily()` lee `firmware_family` de `aura.cfg` y, por contrato (ST-046), la ausencia es Aura. Su comentario asumía que un árbol sin arrancar no tiene `aura.cfg` y que en ese estado nadie usa la familia; pero el propio instalador crea `aura.cfg` con la hora del Mac (`ClockSyncWriter`, `InstallerViewModel`) antes del primer arranque. Un moonlit o Metro recién copiado tenía `aura.cfg` sin la clave → `.aura` → `switchActiveFirmware(currentlyActive: .aura)` lo estacionaba con el nombre de Aura, y `parkActiveTree`/`removeDormantTree` de una instalación posterior de Aura lo eliminaba. El bug existía desde ST-056 para Metro; con tres familias se volvió cotidiano.

**Corrección.** (1) `declaredFamily()`: cuando la clave no está, antes de concluir "Aura" mira el centinela de árbol instalado (`installedTreeSentinel`) de cada familia que declara la clave (`metro-list-20.fnt` → Metro, `moonlit-body-18.fnt` → moonlit). Un Aura real no trae esos archivos, así que "ausencia = Aura" sigue valiendo para todo árbol que ya arrancó; la clave escrita por el firmware manda sobre el centinela. (2) El instalador siembra `firmware_family: <valor>` en el `aura.cfg` que crea (`seedDeclaredFamily`, upsert que respeta la hora; nada para Aura), para que el árbol tenga identidad desde antes del primer arranque — el firmware reescribe el archivo entero al guardar con el mismo valor, sin conflicto. Pruebas en `FirmwareFamilyTests` con el caso exacto del iPod (solo `rtc_*` + centinela de moonlit), clave sobre centinela, Aura sin centinelas ajenos, siembra idempotente.

**Invariante:** ningún árbol de una familia que declara `firmware_family` existe en el iPod sin la clave, ni siquiera entre la instalación y el primer arranque; y Studio nunca deduce "Aura" de un árbol que trae el centinela de otra familia. Matiz al contrato v14 §D (`firmware_family`): Studio puede escribir la clave al instalar; el firmware la conserva.

**No corregido aquí (ST-068 pendiente):** el botón "Cambiar a …" de Extras se quedó girando porque la expulsión posterior al renombre (`unmountCurrentDisk`) no terminó a tiempo; se destrabó solo al reconectar. `ContentView.swift` tiene WIP ajeno (ST-063) y no se toca en esta pasada.

## ST-068 — Pin a moonlit.aura v0.1.1

**Release (2026-08-26):** moonlit-aura `v0.1.1` (D-045 cerrada, D-049 pantalla "preparando biblioteca", D-050 creciente de arranque, D-051 Marea primer pivote, D-052 Motion Waning). Motivo del release: en el iPod del dueño (1 083 álbumes) la precarga de carátulas de Marea congelaba el iPod 4 min 18 s al entrar a Música sin ninguna pantalla; ahora corre en una pantalla propia con progreso e interrumpible.

**Pin:** `moonlit.tag=v0.1.1` + 4 hashes verificados por `scripts/fetch-firmware.sh --family moonlit` (4 × OK). Delta v0.1.0 → v0.1.1 medido por CRC32: **5 archivos de 432** (`rockbox.ipod`, `rockbox-info.txt`, `rockbox.map`, `lastfm_scrobbler.rock`, `version.txt`) — el parche de `__TIME__` de ST-066 ya surte efecto: los `.ovl` de juegos no aparecen. Instalar sobre un v0.1.0 escribe esos 5 archivos, no 432.

## ST-069 — Contrato v15: base tagcache y miniaturas compartidas bajo /.aura

**Contexto (2026-08-26, contrato v15 redactado en paralelo en Aura-Firmware):** los tres firmwares pasan a compartir la base de tagcache en `/.aura/tagcache/` (`database_*.tcd` + `db_stamp.txt`, el sello v12 ahora es uno solo) y Metro/moonlit comparten miniaturas en `/.aura/thumbs/{albums,artists,photos}/`. Ambos subdirectorios son **propiedad del firmware** aunque vivan bajo `/.aura/`, que hasta hoy era solo el buzón de Studio. Al cambiar de familia ya no hace falta espejar ni comparar `db_stamp.txt` por árbol: el firmware compara el sello compartido con `/.aura/library-stamp`.

**Invariante:** Studio no posee `/.aura/tagcache/` ni `/.aura/thumbs/`: solo los borra al forzar reconstrucción; ningún flujo de árboles los toca.

**Revisión de cada flujo (evidencia):**
- `FirmwareSwitcher` (`parkActiveTree`, `removeDormantTree`, `switchActiveFirmware`, `repairIfNeeded`, `refreshRootBinary`, `seedContractFilesToActiveTree`, `mirrorContractFilesToDormantTrees`): todas las rutas nacen de `activeTreeName` (`.rockbox`), `dormantTreeName` (`.firmware-*`) o `rockbox.ipod`; lo único que escribe bajo `/.aura/` es `library-stamp` (crear/renovar) y `sync-pending.json`. Nunca `removeItem`/`moveItem` sobre `/.aura/`. Invariante documentada en la cabecera del enum.
- `InstallerViewModel.copyFirmwareFiles`: borra/reescribe `/rockbox.ipod`, estaciona con `parkActiveTree`, extrae `rockbox.zip` sobre `/.rockbox/`, borra el dormido de la familia recién instalada y, si no pudo listar el zip, `/.rockbox/aura/install_manifest.cfg`. Nada bajo `/.aura/`.
- `InstallManifest.delta.toDelete`: filtro `hasPrefix(".rockbox/")` — jamás borra fuera del árbol activo; los `.tcd` nunca han ido en `rockbox.zip`, así que el manifiesto no los lista.
- `LibrarySync`: escribe `/.aura/sync-pending.json` y renueva `/.aura/library-stamp` en cada sync con música (`writeSyncMarkerIfNeeded`, sin cambios); sus `removeItem` son sobre `Music/`, `Videos/`, `Photos/`, `Playlists/`, `.rockbox/aura/*` y `.aura/sync-in-progress`. `deleteAllDeviceContent` vacía solo `Music/Videos/Photos`. No existe ningún "reset" que borre `/.aura/` completo.
- `SyncSheets` (elementos huérfanos): borra solo rutas registradas en `sync_manifest.json` (contenido de medios).

**Cambio:** `triggerFirmwareDBRebuild` → `LibrarySync.clearFirmwareDatabases(volumeRoot:)` borra `database_*.tcd` + `db_stamp.txt` en `/.aura/tagcache/` **además** de en `/.rockbox/` (+ `aura/db_stamp.txt`) y en cada `/.firmware-*/` presente (compatibilidad con árboles anteriores a v15). `/.aura/thumbs/` no se toca ni se crea nada. Sigue disparándose solo cuando `aura.cfg` no anuncia `sync_marker_supported` (ST-012). `install_manifest.cfg` no cambia.

**Pruebas:** `FirmwareDBRebuildTests` (borra en los tres lugares y deja `thumbs/`, `library-stamp` y `sync-pending.json`; tolera que `/.aura/tagcache/` no exista sin crearlo; el camino real vía `sync()` con y sin `sync_marker_supported`) y `FirmwareSwitcherTests.testTreeFlowsNeverTouchSharedTagcacheOrThumbs` (cambio, estacionar, borrar dormido, sembrar, espejar y reparar con ambos directorios presentes → intactos, sello no reescrito). 129 pruebas verdes en el filtro `FirmwareSwitcher|InstallManifest|FirmwareFamily|LibrarySync|Rebuild|SyncMarker|LibraryPipeline`.

## ST-070 — Pin a Aura v0.4.1-beta + Metro v0.6.2 + moonlit.aura v0.1.2 (contrato v15)

**Releases (2026-08-26):** Aura-Firmware `v0.4.1-beta` (D-336/D-337/D-338), Metro-Aura `v0.6.1` → `v0.6.2` (M-095/M-096; v0.6.2 unifica la clave de miniaturas con moonlit: `a-<crc>.<mtime>.mth`, sin ello el GC de una familia borraba las de la otra en `/.aura/thumbs/`), moonlit-aura `v0.1.2` (D-053 Marea no bloqueante, D-054, D-055). Los tres implementan el contrato v15: base tagcache compartida en `/.aura/tagcache/` (migración por renombrado, sello compartido y sellado tras la primera construcción), claves de carátula estables por ruta+mtime, miniaturas Metro↔moonlit compartidas.

**Pin:** `FIRMWARE_VERSION` con `tag=v0.4.1-beta`, `metro.tag=v0.6.2`, `moonlit.tag=v0.1.2`; 12 hashes verificados por `scripts/fetch-firmware.sh` (4 × OK por familia). Deltas medidos por CRC32: Aura 5/9 463, Metro 5/430 (+4 en v0.6.2), moonlit 5/432.

**Nota de operación:** durante esta pasada se creó por error un Release `v0.1.2` en `Ricolinos/Metro-Aura` (comando lanzado desde el directorio equivocado); se eliminó junto con su tag remoto en el mismo minuto, antes de que Studio o un usuario pudieran consumirlo. Regla: `gh release create` siempre con `--repo` explícito.

## ST-071 — Pin a Aura v0.4.2-beta + moonlit.aura v0.1.3 (caché negativa de carátulas)

**Releases (2026-08-26):** Aura-Firmware `v0.4.2-beta` (D-339) y moonlit-aura `v0.1.3` (D-056, D-057). Metro-Aura sin cambios (sigue `v0.6.2`). Motivo: en el iPod del dueño, 57 álbumes sin carátula resoluble disparaban "preparando biblioteca/carátulas" en cada entrada a Música (sin haber reiniciado); ahora se marcan `.none` una sola vez. Además, en moonlit, Marea cargaba las portadas visibles con retraso perceptible tras D-053 (una lectura por vuelta ociosa a 100 ms); D-057 la lleva al mismo patrón que el Music Flow de Aura (lectura acotada dentro del cuadro + tick a HZ/20 + prefetch direccional).

**Pin:** `tag=v0.4.2-beta`, `moonlit.tag=v0.1.3` + 8 hashes verificados (2 × 4 OK). Deltas: Aura 5/9 463, moonlit 5/432.

## ST-072 — Pin a moonlit.aura v0.1.4 (corrección urgente: precarga congelada)

**Reporte del dueño (2026-08-26):** en un iPod con 1083 álbumes, "preparando biblioteca/carátulas" quedó congelado 10+ minutos sin responder a MENU, obligando a reinicio forzado (SELECT+MENU). Causa diagnosticada en el propio firmware (D-058): el barrido de carátulas pendientes se ejecutaba dos veces completas antes de mostrar progreso, y durante el conteo no se sondeaban botones — el usuario no tenía forma de salir sin apagar.

**Release:** moonlit-aura `v0.1.4` — un solo barrido, MENU responde en ≤1 s incluso durante el conteo, una sola consulta de tagcache por álbum en vez de dos. Verificado en simulador con abort real a mitad de barrido (16/312).

**Pin:** `moonlit.tag=v0.1.4` + 4 hashes (4×OK). Delta v0.1.3→v0.1.4: 5/432.

## ST-073 — Contrato v16: caché maestra compartida `/.aura/art` — Studio nunca la toca

**Contexto (2026-08-26, contrato v16 redactándose en Aura-Firmware):** los tres firmwares comparten ahora una caché maestra de imágenes en `/.aura/art/{albums,artists,photos}/` (archivos `.art` RGB565 + marcadores negativos `.none`), con claves independientes de la base tagcache (crc32 de ruta + mtime). Es propiedad del firmware, como `/.aura/tagcache/` y `/.aura/thumbs/` (ST-069), pero con una diferencia: **ni siquiera forzar la reconstrucción de la base la borra**, porque sus claves no dependen de la base y regenerarla en un iPod grande cuesta más que la propia base.

**Invariante:** Studio nunca borra, mueve ni estaciona `/.aura/art/` — ni en instalación, ni al cambiar de familia, ni al reparar, ni en sync, ni al forzar reconstrucción. `install_manifest.cfg` no la lista. El sync de música sigue escribiendo `/.aura/library-stamp` y `/.aura/sync-pending.json` como hoy; el firmware activo construye en segundo plano las maestras nuevas.

**Revisión de cada flujo (evidencia, sobre el código actual):**
- `LibrarySync.clearFirmwareDatabases` / `triggerFirmwareDBRebuild`: borra únicamente `tagcacheDatabaseFileNames` + `db_stamp.txt` dentro de `/.aura/tagcache/`, `/.rockbox/` y cada `/.firmware-*/`, más `aura/db_stamp.txt` por árbol. Ningún `removeItem` recibe una ruta bajo `/.aura/art/` (ni `thumbs/`). No enumera ni crea nada bajo `/.aura/`.
- `FirmwareSwitcher`: sus 10 `removeItem`/`moveItem` nacen de `activeTreeName` (`.rockbox`), `dormantTreeName` (`.firmware-*`) o `rockbox.ipod`; bajo `/.aura/` solo escribe `library-stamp` y `sync-pending.json`. Sin cambios de código; se amplió la invariante de la cabecera.
- `InstallerViewModel.copyFirmwareFiles`: `removeItem` sobre `/rockbox.ipod`, temporales de extracción, destinos dentro de `/.rockbox/` y `/.rockbox/aura/install_manifest.cfg`. Nada bajo `/.aura/`.
- `InstallManifest.delta.toDelete`: filtro `hasPrefix(".rockbox/")` — imposible que liste `/.aura/art/`; los `.art` nunca van en `rockbox.zip`.
- `LibrarySync` (sync, `deleteAllDeviceContent`, `sweepOrphanedTempFiles`, huérfanos): sus `removeItem` son sobre `Music/`, `Videos/`, `Photos/`, `Playlists/`, `.rockbox/aura/*` y `.aura/sync-in-progress`; `sweepOrphanedTempFiles` solo recorre `deviceContentDirectories` buscando `.aura-tmp`.
- `SyncSheets` (elementos huérfanos): borra solo rutas registradas en `sync_manifest.json` (medios).

**Cambio:** constante `LibrarySync.sharedArtDirRelativePath = ".aura/art"` junto a las de ST-069, documentación de la invariante en `LibrarySync` y `FirmwareSwitcher`. Sin cambios de comportamiento: el código ya cumplía.

**Vista de espacio / limpieza de cachés:** no existe. `DeviceActivityBar` muestra Música/Video/Fotos/Otro/Libre a partir de `sync_summary.cfg` y la capacidad del volumen; no enumera `metrocache`/`cfcache`/`moonlitcache` ni ninguna carpeta del firmware, así que no hay nada donde añadir `/.aura/art` ni `/.aura/thumbs`. Si algún día se construye, debe ser de solo lectura.

**Pruebas:** `FirmwareDBRebuildTests.testForcedRebuildKeepsSharedArtCache` (con `/.aura/art/albums/x.art`, `.none`, `artists/`, `photos/` presentes, la reconstrucción forzada borra las tres bases y deja `art/` byte a byte igual, con o sin `/.aura/tagcache/`); las pruebas ST-069 existentes ahora también siembran `art/` y lo verifican intacto en el camino real vía `sync()`; `FirmwareSwitcherTests.testTreeFlowsNeverTouchSharedTagcacheOrThumbs` siembra `/.aura/art/{albums,artists,photos}` y comprueba que cambio, estacionar, borrar dormido, sembrar, espejar y reparar lo dejan intacto y sin reescribir. 30 pruebas verdes en `Rebuild|FirmwareSwitcher|InstallManifest`.

## ST-074 — Repos privados: token de solo lectura en el Llavero para el aviso de versiones; la instalación sigue siendo desde los binarios embebidos

**Contexto (2026-08-26):** el dueño pasó a privados `Ricolinos/Aura-Firmware`, `Ricolinos/Metro-Aura` y `Ricolinos/moonlit-aura`. Instalar no se rompe: los binarios viajan embebidos (`Vendor/firmware-dist/`, que `scripts/fetch-firmware.sh` baja con la sesión `gh` del desarrollador al compilar). Lo que se rompía era el aviso de "hay una versión nueva": `GitHubReleaseChecker.fetchReleases` pegaba a `api.github.com/repos/<repo>/releases` sin autenticación y GitHub responde 404 en un repo privado, así que `AuraUpdateChecker` caía al respaldo por hash contra el binario embebido y nunca ofrecía nada más nuevo que la propia app.

**Decisión.** Un token personal de GitHub de **solo lectura** (fine-grained, Contents: Read-only, acotado a los tres repos), guardado únicamente en el **Llavero de macOS** (`GitHubToken`, `kSecClassGenericPassword`, servicio `com.ricolinos.aurastudio.github-token`, sin iCloud Keychain — mismo patrón que `APIKeyStore`, D-203/ST-032). Nunca `UserDefaults`, nunca logs, nunca el repo. Con token, `fetchReleases` añade `Authorization: Bearer`, `Accept: application/vnd.github+json` y `X-GitHub-Api-Version: 2022-11-28`; sin token, el comportamiento de siempre (404 → `badResponse` → respaldo por hash). Un rechazo con token (401/403, y también 404: GitHub esconde con 404 los repos privados a los que el token no tiene acceso) **no lanza**: devuelve `[]`, deja `GitHubReleaseChecker.lastAuthFailure = true` y `AuraUpdateChecker` no lo cachea (si no, arreglar el token no surtiría efecto hasta vencer el TTL de 24 h). El formato se valida antes de guardar (`validateFormat`: `github_pat_…`/`ghp_…`, sin espacios).

**UI.** Ajustes › General › "GitHub (repos privados)" (`GitHubTokenSettingsView`): `SecureField`, "Guardar" (formato → Llavero → limpia el campo → "Guardado en el Llavero"), "Quitar", "Probar" (consulta en vivo la familia Aura con el token del Llavero y muestra el tag más nuevo o el motivo del fallo) y el texto de cómo crear el token. ST-053: "Guardar" y "Probar" responden siempre y explican en pantalla; ST-054: sin `.fixedSize(horizontal:false, vertical:true)`, verificado en build Release. Extras › Licencias: nota "Los repositorios son privados: los enlaces requieren sesión de GitHub con acceso." bajo los enlaces, que se conservan tal cual.

**Nota GPL v2.** Que los repos sean privados no cambia la obligación: mientras la app sea de uso personal del dueño no hay distribución y §3 no exige nada. En el momento en que la app (con `rockbox.ipod`, `rockbox.zip`, el bootloader y `mks5lboot` embebidos) se entregue a un tercero, hay que ofrecerle el fuente completo correspondiente de esos binarios (§3): publicar el repo, o entregar el fuente del tag exacto junto con la app. Los enlaces de Licencias siguen siendo la oferta; hoy solo la puede ejercer quien tenga acceso.

**Pruebas** (`GitHubTokenTests`, con `MockURLProtocol`, sin tocar el Llavero real): formato aceptado/rechazado; sin token la petición no lleva `Authorization`; con token lleva las tres cabeceras y va al repo de la familia; 401 con token → `lastAuthFailure == true`, `[]` sin lanzar; 200 con token limpia el estado; 404 sin token sigue lanzando `badResponse` sin culpar al token. 32 pruebas verdes en `GitHub|UpdateChecker|Release`.

## ST-075 — Pin a Aura v0.4.3-beta + Metro v0.6.3 + moonlit.aura v0.1.5 (contrato v16: caché maestra compartida)

**Releases (2026-08-26):** las tres familias implementan el contrato v16 (D-340/D-341, M-097, D-059): caché maestra de imágenes compartida en `/.aura/art/{albums,artists,photos}/` (formato `.art`/`.none`, cabecera `MAST`, RGB565 fila-contigua, claves por ruta+mtime), construida en segundo plano por un hilo de baja prioridad en el firmware activo — cada imagen se decodifica una sola vez entre las tres familias. La cápsula "preparando carátulas" desaparece de los tres.

**Pin:** `tag=v0.4.3-beta`, `metro.tag=v0.6.3`, `moonlit.tag=v0.1.5` + 12 hashes (3×4 OK). Deltas: Aura 5/9463, Metro 5/430, moonlit 5/432.

**Nota de operación:** el release de Aura v0.4.3-beta se cortó por timeout subiendo `rockbox.ipod` (el asset más grande); se completó con `gh release upload` tras verificar que faltaba exactamente ese archivo. Verificar siempre `gh release view --json assets` tras un `gh release create` que tardó, antes de dar el release por completo.

**ST-073/ST-074 incluidas en esta build**: protección de `/.aura/art` contra cualquier flujo de Studio, y token de GitHub en el Llavero para que el aviso de versiones funcione con los repos ahora privados (Ajustes › General).

## ST-076 — Pin a Aura v0.4.4-beta + Metro v0.6.4 + moonlit.aura v0.1.6 (guarda de commit al cambiar de sistema)

**Diagnóstico del dueño (2026-08-27):** tras probar el contrato v15/v16, seguían apareciendo esperas al cambiar entre familias y la preparación de moonlit se sentía atada al menú Música. Investigación de solo lectura en los tres firmwares (`apps/tagcache.c` de Rockbox, compartido) confirmó dos causas reales, no relacionadas con el diseño de v15/v16 en sí:

1. **Metro nunca sondeaba `metro_music_db_ready()` desde el arranque** — solo se llamaba al entrar a Música (a diferencia de Aura y moonlit, que ya lo hacían). Corregido en M-098: se sondea desde el bucle principal, igual que sus hermanas.
2. **Los tres firmwares podían reiniciar con un commit de tagcache a mitad de escritura** al cambiar de familia (`tagcache_shutdown()` no lo espera). Eso deja la base **compartida** marcada `dirty=1`, y el siguiente arranque de CUALQUIER familia la ve como corrupta y reconstruye desde cero — la única causa real encontrada capaz de invalidar una base compartida sana. Corregido en los tres (D-342 Aura, M-099 Metro, D-060 moonlit): esperan (tope 8 s) a que `tagcache_get_commit_step() == 0` antes de renombrar árboles y reiniciar.

**Releases:** Aura v0.4.4-beta, Metro v0.6.4, moonlit v0.1.6. **Pin:** 12 hashes (3×4 OK). Deltas: 5 archivos cada uno.

**Límite documentado, no corregible sin riesgo alto:** este iPod no tiene el mecanismo de Rockbox para persistir la copia en RAM de la base entre reinicios (`HAVE_EEPROM_SETTINGS` no existe para `ipod6g`). Todo reinicio real —incluido cada cambio de familia— vuelve a leer el índice de disco a RAM desde cero; es rápido (segundos) si no hay que reconstruir nada, pero no es eliminable sin tocar capas profundas de Rockbox no diseñadas para este hardware.

## ST-077 — Instalar desde cero baja el Release más nuevo; el pin de `FIRMWARE_VERSION` pasa a ser el respaldo (contrato v17)

**Diagnóstico (reporte del dueño, 2026-08-27):** *"ya configuré mi token […] funciona, pero aunque sí actualiza, en la sección extras aparece un release anterior. Debería aparecer el actualizado (por si hay que instalar desde cero, que instale el más reciente)."* Son **dos** síntomas del mismo hecho, y solo uno se ve:

1. **Lo visible.** La pastilla de versión de cada tarjeta en Extras salía de `BundledArtifacts.forFamily(family).releaseTag` (`ExtrasView.swift`, `FirmwareChoiceCard`) — o sea, `firmware-version.txt` **empotrado en la app al compilar**, que refleja el pin de `FIRMWARE_VERSION` (`tag=v0.4.4-beta`, `metro.tag=v0.6.4`, `moonlit.tag=v0.1.6`). Nunca consultaba GitHub.
2. **Lo que de verdad importaba.** No existía **ningún** descargador: `InstallerViewModel` instalaba siempre desde `BundledArtifacts`. Studio podía saber por ST-074 que existía un Release más nuevo, avisarlo, y aun así **escribir en el iPod la versión del pin** en una instalación desde cero.

La contradicción quedaba a la vista: ST-074 ya consulta GitHub con el token del Llavero para el aviso de versiones, pero esa información no llegaba ni a la pastilla ni al instalador.

**Decisión.** `FirmwareReleaseDownloader` (nuevo) baja los cinco assets de la tabla §A del Release más nuevo de la familia elegida y los deja verificados en `~/Library/Application Support/AuraStudio/firmware-cache/<familia>/<tag>/`. `BundledArtifacts` gana un inicializador `init(directory:family:)`: el mismo tipo, la misma `verifyAll()`, el mismo `releaseTag` — pero leyendo de ese directorio. Así `InstallerViewModel.artifacts` es `downloadedArtifacts ?? BundledArtifacts.forFamily(targetFamily)` y **nada más abajo tuvo que enterarse** de dónde salieron los archivos.

Puntos que costaron y no son obvios:

- **La descarga se resuelve JUSTO ANTES de cada uso real de `artifacts`**, no en paralelo al flujo: `ensureLatestArtifacts()` se llama al entrar a `runInstallOrRestore()` y a `copyFirmwareFiles()` (los dos caminos que escriben; el de recuperación sin DFU solo pasa por el segundo). Un `Task` disparado al principio del asistente habría dejado una carrera entre la descarga y la primera escritura al iPod.
- **El bootloader y `mks5lboot` salen del mismo Release que el árbol.** `ensureLatestArtifacts()` rehace el `MKS5LBootRunner` con los artefactos descargados. Flashear el bootloader de una versión y copiar el árbol de otra sería una mezcla que ningún release probó.
- **Permisos POSIX.** `mks5lboot` descargado llega **sin bit de ejecución** (los permisos no viajan en el cuerpo HTTP) y `MKS5LBootRunner` lo rechaza con `binaryNotExecutable`. Se le pone `0o755` al escribirlo. En el bundle venía ejecutable porque lo empaqueta el build — el caso no existía antes.
- **Repos privados: la URL del API, no `browser_download_url`.** La segunda redirige a un host de almacenamiento que devuelve error si le llega la cabecera `Authorization` de GitHub. Se pide `/repos/:owner/:repo/releases/assets/:id` con `Accept: application/octet-stream`, y `RedirectAuthStripper` suelta `Authorization` cuando el 302 cambia de host — `URLSession` la reenviaría sola.
- **Publicación atómica.** Se baja a `.descarga-<tag>/` y solo se renombra al directorio final cuando los cinco assets pasaron `verifyAll()` (hashes contra el `checksums.txt` del propio Release **y** el contenido real de `rockbox.zip`, D-297/D-298 — un checksum correcto por sí solo nunca detectó un Release mal empaquetado). Un corte a la mitad no puede dejar un directorio que la próxima corrida dé por completo.
- **El tag nunca entra crudo a una ruta.** `isSafeTagComponent()` (alfanuméricos, `.`, `-`, `_`; sin `/`, sin `..`, ≤ 64) antes de componer el directorio de caché — mismo criterio que `AuraThemeID.isValid()` para los ids de tema.
- **Fallar nunca detiene la instalación.** Cualquier problema (sin red, token sin acceso, Release incompleto, checksum malo) deja `downloadedArtifacts` en nil, instala lo embebido y escribe el motivo en `releaseSourceNote`. `releaseDownloadFailed`/`releaseMissingAsset` existen **para poder decir por qué**, no para abortar.

**UI.** Extras consulta ahora las versiones disponibles (`AvailableFirmwareVersions`, con el caché de 24 h de `ReleaseCache` y un "Revisar de nuevo" que lo saltea — misma razón que `forceRefresh` en D-300). La pastilla muestra el tag **que se instalaría**; cuando ese tag es el embebido porque no se pudo consultar GitHub, se marca "incluida" y el pie lo explica remitiendo al token en Ajustes › General (ST-053: una pastilla que dice una versión tiene que decir de dónde salió).

**Compatibilidad del caché.** `GitHubRelease` gana `assets`, decodificado con `decodeIfPresent` → `[]`: la lista guardada en `UserDefaults` por una versión anterior de Studio no lo tiene, y sin eso el Release entero fallaría al decodificar y el usuario se quedaría sin aviso de versiones hasta vencer el TTL.

**Nota GPL v2.** No cambia nada de fondo, y de hecho mejora: lo que se instala ahora tiene siempre un tag exacto y su `firmware-version.txt` al lado, así que la pantalla de Licencias (§B) cita la versión realmente instalada y no la del pin. La obligación de §3 sigue siendo la de ST-074.

**Contrato v17** (`CONTRATO-firmware-studio.md`, copia idéntica en `Aura-Firmware`): §A intacta, §E pasa de "única vía" a "respaldo". **§D no se toca** — nada de lo que se escribe en el disco del iPod cambia. Los tres firmwares no tienen trabajo en esta versión.

**Verificado.**
- `swift build`: 0 errores (los avisos de `onChange(of:perform:)` son preexistentes, ajenos a esta pasada).
- **Dos cuelgues de la suite, uno corregido y otro reportado.** `swift test` completo no terminaba (47 min a 0 % de CPU). Causa encontrada: `GitHubReleaseCheckerFetchTests` llamaba `fetchReleases(session:)` **sin** `token:`, dejando el valor por defecto `GitHubToken.load()` — o sea el Llavero **real**; en una Mac con token guardado macOS puede pedir permiso y la prueba espera un diálogo para siempre. Corregido inyectando `token: nil` en los dos casos, la disciplina que `GitHubTokenTests` ya documentaba desde ST-074. De paso arregla un fallo latente: con un token presente, un 404 ya no lanza `badResponse` sino que devuelve `[]` (ST-074), así que `testThrowsOnNonOKStatus` habría fallado por el motivo equivocado. **Queda un segundo cuelgue, preexistente y ajeno a esta pasada**: `AuraDeviceProbeTests.testSummaryIsReadBackFromWhatLibrarySyncWrote` se queda colgado en `AuraDeviceProbe.probe(diskInfo:)` (toca IOKit/DiskArbitration reales). No se tocó — depende del hardware conectado a la Mac y arreglarlo a ciegas sería peor. Por eso la suite completa **no** se pudo correr de punta a punta en esta pasada; sí las suites vecinas, una por una.
- Suites vecinas verdes, corridas por separado: `SemVerTests` (9), `GitHubReleaseCheckerPickLatestTests` (5), `GitHubReleaseCheckerFetchTests` (2), `AuraUpdateCheckerVersionMarkerTests` (5), `ReleaseCacheTests` (3), más las que alcanzaron a correr antes del cuelgue de `AuraDeviceProbeTests`, todas con 0 fallos.
- `FirmwareReleaseDownloaderTests` (nuevo, **12/12 verdes**): tag inseguro rechazado (`..`, separadores, vacío, largo) y `cacheDirectory` que lo refleja; caché por familia y por tag; decodificación de `assets` y búsqueda por nombre; Release **sin** `assets` (caché viejo) que aun así decodifica; descarga que exige la URL del API + `Accept: application/octet-stream` + `Bearer`; asset truncado rechazado por tamaño; 404 propagado con su código en el motivo; Release al que le falta `mks5lboot` reportado nombrando el asset; rechazo del token explicado como tal; `BundledArtifacts` sobre directorio (incluye `releaseTag` desde `firmware-version.txt` y `nil` para lo que no está, sin caer al bundle); `isComplete` que exige los cinco.
- **Límite documentado de esta verificación:** no se ejecutó una instalación real contra un iPod ni una descarga contra GitHub en vivo. Todo lo de red está cubierto con `MockURLProtocol`; lo que **no** se puede probar así y queda a verificación del dueño en hardware: (a) que `mks5lboot` descargado a Application Support ejecute sin fricción de Gatekeeper — se escribe con `Data.write` y por eso **no** lleva el atributo `com.apple.quarantine` que sí pondría un navegador, que es la razón por la que debería correr, pero no se comprobó; (b) el salto de redirección real de GitHub hacia su host de almacenamiento con un asset grande (`rockbox.ipod`, ~1.3 MB; `rockbox.zip`, ~9 MB).

## ST-078 — Port a Windows: decisiones de facto de la sesión en la VM, formalizadas en la Fase 0 del port

**Contexto.** `studio/windows/` (Aura Studio para Windows, WinUI 3/Fluent 2) se venía construyendo en sesiones de Claude Code corriendo **dentro** de la VM Windows ARM64 (Parallels, `Y:` = carpeta de la Mac mapeada), sin commitear nada todavía. `PLAN-aura-studio-windows-v2.md` (carpeta padre `Aura/docs/plans/`) formaliza el trabajo por fases; su Fase 0 pide registrar aquí lo que ya se decidió de hecho en esa VM antes de este plan existir, más lo que la propia Fase 0 corrigió.

**Plataforma de compilación:**
- TFM de `AuraStudio.App`: `net10.0-windows10.0.26100.0` — coincide con el Windows SDK realmente instalado en la VM (10.0.26100). `TargetPlatformMinVersion` se mantiene en `10.0.19041.0` (Windows 10 2004), el mínimo real de runtime — TFM de compilación y mínimo de plataforma son ejes distintos, no tienen que coincidir.
- `Microsoft.WindowsAppSDK` 2.4.0 (no 1.7.x: sin paquete de `BuildTools` compatible con SDK 26100) + `Microsoft.Windows.SDK.BuildTools` 10.0.26100.4654.
- `CommunityToolkit.Mvvm` 8.4 con `<LangVersion>preview</LangVersion>` — el generador de `[ObservableProperty]` en 8.4 solo emite código para propiedades **parciales**, no campos privados; sin `preview` el build falla con `CS9248`.
- Enumeración de discos por **WMI** (`Win32_DiskDrive`/`Win32_PnPEntity`, paquete `System.Management`), no hay alternativa nativa a `IOKit`/`DiskArbitration` en este framework.
- `AuraStudio.Windows.slnx` como solución real (no `.sln` clásico).

**Bug corregido en esta misma Fase 0 (no una decisión, un defecto):** el mapeo de plataforma del `.slnx` tenía `<Platform Solution="*|ARM64" Project="x64" />` para `AuraStudio.App` — pedir `dotnet build -p:Platform=ARM64` a nivel solución compilaba silenciosamente un binario **x64**. Corregido a `Project="ARM64"`; verificado comparando el árbol de salida (`bin/x64/...` vs `bin/ARM64/...`) antes y después, y lanzando el `.exe` resultante. Cualquier verificación previa de "compila ARM64" hecha vía build de la solución (no del `.csproj` directo) debe darse por no confiable retroactivamente.

**Warnings latentes cerrados y `TreatWarningsAsErrors` activado** en los 3 csproj (`AuraStudio.Core`, `AuraStudio.App`, `tests/AuraStudio.Core.Tests`) — la compuerta "0 warnings" del plan de Windows pasa de revisión manual a mecánica. Detalle de los fixes (`SyncMarker.cs` con `required`/`[SetsRequiredMembers]`, `VideoArtworkResolver.cs` con `_ => throw`) en `studio/windows/docs/ESTADO-PORT.md`, entrada Fase 0.

**Herramientas descartadas:** `open-vm.command` + `scripts/OpenInVM.ps1` (control remoto de la VM y Visual Studio *desde macOS*) se eliminaron — eran del flujo pre-VM del plan v1 ("escribir a ciegas en la Mac"), invalidado por la premisa del plan v2 de que las sesiones ya corren dentro de la VM.

**Alcance de este ST.** No toca nada de `studio/AuraStudio/` (macOS) ni ningún contrato con el firmware — es puramente infraestructura del port de Windows, documentado aquí porque `DECISIONS.md` es la fuente de verdad única del repo (regla del `CLAUDE.md`), no porque cambie el comportamiento de la app macOS o del firmware.

## ST-079 — Port a Windows, Fase 1: cimientos de la app (sesión compartida, ventana, tokens Fluent, navegación, strings)

**Contexto.** Fase 1 de `PLAN-aura-studio-windows-v2.md` (carpeta padre `Aura/docs/plans/`). Cierra lo que las notas del port marcaban como pendiente estructural y deja decidido lo que las fases siguientes dan por sentado. Nada de esto toca `studio/AuraStudio/` (macOS) ni ningún contrato con el firmware.

**Estado de sesión compartido.** `IDeviceSessionService`/`DeviceSessionService` (singleton) pasa a ser la única fuente de "qué iPod hay conectado": publica `State` (`Detecting`/`NotConnected`/`Connected`/`Ambiguous`), `Device`, `Identification`, `StatusMessage`, `LibraryLocked` y un evento `Changed`. Antes, cada ViewModel consultaba `IUsbDeviceWatcher` por su cuenta y guardaba su propia copia — dos pantallas podían discrepar sobre qué iPod está conectado, y cada una re-enumeraba WMI. `MainViewModel`, que hacía de sesión improvisada, se eliminó. **Excepción deliberada que no debe "arreglarse":** `DeviceSafetyValidator` sigue yendo directo al watcher — la re-verificación previa a una operación destructiva no puede confiar en estado cacheado, por reciente que sea.

**ViewModels suscritos a la sesión son singleton** (`ShellViewModel`, `DeviceListViewModel`, `SettingsViewModel`, `InstallerViewModel`, `SyncViewModel`). Las páginas se reconstruyen en cada navegación: un ViewModel transitorio suscrito a `Changed` deja una suscripción viva por visita. Es el mismo motivo por el que macOS sube el ViewModel del instalador al contenedor raíz (D-187).

**Hecho que faltaba en Core: qué firmware hay EN EL DISCO.** `InstalledFirmware.cs` (`InstalledFirmwareKind`, `InstalledFirmware`, `FirmwareTreeFacts`, `FirmwareTreeProbe`) porta la mitad de `AuraDeviceProbe.probe` que clasifica archivos: mismas rutas y mismo orden de decisión que el Swift. Con eso, `IPodDiskInfo` gana `SupportsAuraContract`, `IsAuraFirmware`, `RockboxFamilyVerified`, `IsDualBoot` y `ThemeFormatSupported`, y **se retira `IsAura`** — que era exactamente la trampa capacidad-vs-identidad que ST-046 nombró: definida como `RunningFirmware == RockboxFamily && HasAuraConfig`, negaba el contrato a un iPod con Aura instalada conectado en modo disco de Apple (evidencia de arranque en disco, USB atendido por Apple), donde macOS sí lo habilita. 19 casos nuevos (`FirmwareTreeProbeTests`), Core 129/129.

**Acento del sistema, no acento de marca.** `Resources/AuraPalette.xaml` transcribe `Generated/AuraPalette.swift` (canal 0…1 × 255) con los tres temas (`Light`/`Dark`/`HighContrast`; en contraste alto la marca se retira y manda el tema del usuario), pero **los controles usan el acento que el usuario eligió en Windows** (`AccentFillColorDefaultBrush`, `AccentButtonStyle`). La app de macOS tiñe todo con el acento de marca porque en macOS ese es el idioma de la plataforma; en Windows lo idiomático — y lo que el principio 6 del plan pide como criterio de aceptación ("acento del sistema funcionando") — es respetarlo. El acento de marca queda como `AuraBrandAccentBrush` para momentos de identidad. Al mover `FIRMWARE_VERSION` se re-transcribe el archivo completo, igual que en macOS se reemplaza entero el `.swift`; lo limpio sería una salida XAML en el generador del firmware, que vive en el otro repositorio y no se toca desde acá.

**Navegación: misma estructura que la barra lateral de macOS, en idioma de Windows.** `ShellPage` con `NavigationView`: encabezado de dispositivo, General, los tres grupos con subsecciones (Música: Artistas/Álbumes/Canciones/Listas; Video: Películas/Series/Videoclips/Todos los videos; Fotos: Fotos/Imágenes/IA/Todas las fotos), Extras, y al pie Instalador + Ajustes. La biblioteca **se deshabilita, no se oculta**, cuando hay un iPod conectado que no habla el contrato (con la explicación en una `InfoBar`, ST-053) y queda abierta sin dispositivo — armarla offline es un caso de uso real; General y Extras nunca se bloquean (ST-047). Si la sección abierta se bloquea, la selección salta a General, igual que macOS. Las subsecciones no llevan icono: en Fluent la sangría ya expresa la jerarquía. "Sincronizar" **no** es una sección: macOS tampoco la tiene (la sincronización se dispara desde General), así que `SyncPage` y `LibraryPage` quedan fuera de la navegación como borradores de las fases 3 y 4.

**Strings: clase estática, no `.resw`.** `Resources/AppStrings.cs`, equivalente de `AppStrings.swift`. La app tiene un solo idioma por regla del repo, así que lo que aporta MRT (resolución por idioma, `x:Uid` por elemento) no se usa, y a cambio cuesta verificación en tiempo de compilación: un `x:Uid` mal escrito no falla, deja el texto vacío en pantalla. Con una clase estática cada cadena es una propiedad que el compilador verifica, se compone con interpolación y se lee junto al código. Es lo mismo que decidió macOS frente a los `.strings` de Apple (y el firmware en `aura_lang.c`, D-013). Si algún día hace falta un segundo idioma se agrega el patrón del Swift, sin migrar a `.resw`.

**Ventana y preferencias.** `MainWindow` se queda solo con lo propio de una ventana (la UI vive en `ShellPage`, porque `Window` de WinUI 3 no es `FrameworkElement`): Mica con degradación a acrílico y a sólido — Mica es de Windows 11 y el mínimo del proyecto es 10.0.19041 —, tema claro/oscuro/sistema con anulación desde Ajustes (incluida la barra de título vía `AppWindow.TitleBar.PreferredTheme`, que no es parte del árbol XAML), y geometría persistida que solo se restaura si sigue cayendo sobre una pantalla que exista hoy. `IAppPreferences` guarda un JSON en `%LOCALAPPDATA%\Aura Studio\preferences.json` — la app corre sin empaquetar (`WindowsPackageType None`), así que `Windows.Storage.ApplicationData` no está disponible — y nunca deja caer una excepción de disco a la UI. **Las API keys no van ahí**: Credential Manager vía `IApiKeyStore` (D-203/ST-032), Fase 6.

**Los glifos de Segoe Fluent Icons se verifican, no se recuerdan.** `E94A`, heredado del código previo como icono de "Dispositivos", **es el signo de división**: el rango de uso privado no falla ni en compilación ni en runtime, simplemente dibuja otra cosa. Se comprobaron renderizando la fuente a una imagen y mirándola (método en `ESTADO-PORT.md`); quedan `E955` (reproductor portátil) para el encabezado de dispositivo y `E8A9` (cuadrícula 2×2, equivalente del `square.grid.2x2` de macOS) para Extras.

**Verificado.** `dotnet build studio/windows -p:Platform=ARM64` → 0 errores / 0 warnings; `dotnet test tests/AuraStudio.Core.Tests` → 129/129; app lanzada en la VM y **verificada en pantalla** (capturas en `ESTADO-PORT.md`): Mica, claro y oscuro, cambio de tema en vivo, navegación completa, persistencia de geometría entre corridas. **No verificado con hardware:** los estados "conectado" y "ambiguo" de General — necesitan el iPod (y dos discos que califiquen) y quedan anotados para la sesión con el dueño.

## ST-080 — Port a Windows, Fase 2 (primera sesión): instalador — núcleo verificable, artefactos, DFU y Licencias GPL

**Contexto.** Primera de las sesiones de la Fase 2 de `PLAN-aura-studio-windows-v2.md`. Cubre los puntos 1, 2, 6 completos, y la parte de 3 y 4 que no necesita elevación ni el iPod. El asistente completo (punto 5), el `PrivilegedRunner` real y el formateo ejecutado quedan para la sesión siguiente. **Ninguna operación destructiva se ejecutó ni se puede ejecutar sin confirmación explícita del usuario.**

**Colisión de sesiones, y qué quedó.** Una segunda sesión ejecutora arrancó la misma fase en paralelo por error y se retiró; sobreescribió con `git checkout --` un archivo en curso de esta sesión (restaurado) y dejó 13 archivos en `AuraStudio.Core/Installer/`. Se reconcilió a **un solo modelo por concepto**: sobreviven de ese trabajo `Fat32Formatter`, `FirmwareTreeWriter`, `FirmwareSwitcher`, `InstallerError`, `InstallerStep` y `PrivilegedOperation`; se descartaron sus duplicados de `InstallPlanner`/`InstallManifest`/`AuraUpdateChecker`/`BundledArtifacts` (los de esta sesión ya tenían pruebas y estaban integrados) y la cadena de descarga ST-077 (`FirmwareReleaseDownloader`/`ReleaseCache`/`FirmwareVersionResolver`), que colgaba del `BundledArtifacts` duplicado, no tenía pruebas ni cableado y no se puede ejercitar acá — sin `gh` instalado, con repos privados y sin almacén de credenciales (Fase 6). `FirmwareArtifacts.Load(directorio, familia)` ya acepta artefactos de cualquier directorio, que es lo único que esa cadena necesita del modelo.

**Núcleo portado, con pruebas (Core 216/216).** `InstallManifest` (contrato v11/ST-058: entradas del zip por ruta/tamaño/CRC-32, `install_manifest.cfg` **byte a byte igual al de macOS** porque es contrato compartido, y el delta que evita reescribir 9,431 archivos para cambiar cinco); `InstallPlanner` (ST-017, port literal); `FirmwareArtifacts`/`FirmwareArtifactVerifier` (equivalente de `BundledArtifacts`, incluida la comprobación de D-297/D-298 de que `rockbox.zip` trae de verdad codecs y plugins — un checksum correcto nunca detectó ese bug); `AuraUpdateChecker` (tag primero, hash del binario de **la misma familia** como respaldo, ST-046); `Mks5lbootOutput`.

**Mejora sobre macOS, no capricho:** el Swift lee el directorio central del zip invocando `/usr/bin/unzip -lv` y parseando su tabla de texto con una expresión regular de columnas. Acá `ZipArchiveEntry.Crc32` del BCL lo da directo: sin subproceso y sin parser. Lo que **no** cambia es el formato del archivo en el iPod.

**Bug real corregido en el sondeo DFU.** `DfuFlashRunner.ScanAsync` decidía "hay un iPod en DFU" con `Output.Contains("DFU")`. Cuando NO hay dispositivo, `mks5lboot` imprime `no DFU devices found`, que también contiene "DFU"; solo el código de salida evitaba el falso positivo. Ahora se lee el estado (`DFU device state: N`) como hace macOS, con el parser en Core y probado contra las cadenas reales del binario. El runner además soporta `--single` y `--bl-uninst`, que faltaban: sin `--single` no existe el modo Solo firmware, que es el único que instala macOS desde ST-050.

**`FirmwareTreeInstaller` reescrito.** Extraía el zip completo a `/.aura/install-staging` **dentro del iPod** y después copiaba archivo por archivo: el doble de escrituras sobre el medio más lento, sin delta, y dentro de `/.aura/`, que por contrato v16 es territorio del firmware. Ahora delega en `FirmwareTreeWriter`.

**`mks5lboot.exe` no viene del Release — decisión ABIERTA, no cerrada.** El contrato §A publica `mks5lboot` (binario de Unix) y su hash en `checksums.txt`; Windows necesita un `.exe`. El que hay en `artifacts/` se cross-compiló en una sesión anterior y **no tenía ninguna procedencia registrada**. Mientras el dueño decide, esta sesión implementó el lado Studio de forma neutral, sin tocar el contrato: `FirmwareArtifactVerifier` reporta tres niveles (`ReleaseChecksums` > `LocalPin` > `Unverified`) y se agregó `artifacts/mks5lboot.exe.origin` con el SHA-256 del binario y el `tag` que el propio binario reporta al ejecutarlo (`fdf5be4e8fM-260831`). **Ese tag lleva `M`: se compiló de un árbol del firmware con cambios sin commitear**, así que no corresponde a ningún tag publicado — un hash fijado localmente detecta corrupción o reemplazo, pero no acredita origen, y eso es exactamente lo que la pantalla de Licencias dice. Las dos salidas posibles (que el Release publique `mks5lboot.exe`, cambio de §A coordinado con el firmware; o que Studio-Windows versione el suyo con procedencia real desde un árbol limpio) son del dueño, y la segunda además necesita rehacer el binario desde un checkout sin modificar para que la oferta de fuente de la GPL §3 sea verdadera.

**FAT32 de más de 32 GB: el plan no podía funcionar.** El punto 3 de la Fase 2 daba por hecho `Format-Volume`/`diskpart`. Ninguno de los dos sirve para el iPod del dueño, y hay **dos límites distintos que conviene no fundir**: `FormatEx` (el motor de ambos) se niega a crear FAT32 de más de 32 GB, y por separado `format /?` en esta VM documenta un límite por cuenta de clústeres (65 526 < N < 4 177 918) que con la unidad máxima de 32 KB da un techo de ~127 GB. Ninguno de los dos está verificado en hardware acá. Por eso sobrevive `Installer/Fat32Formatter`: escribe las estructuras FAT32 (sector de arranque, respaldo, FSInfo, dos FAT y clúster raíz) según la especificación pública de Microsoft, sobre un `Stream` — lo que lo hace comprobable entero en memoria. Llegó sin una sola prueba y esta sesión le escribió 16, incluido el caso de sectores de 4096 que D-190 volvió obligatorio.

**Pantalla de Licencias (contrato §B) — la restricción crítica, ya en pantalla.** Ajustes › Acerca de › Ver licencias, verificada en ejecución (`docs/capturas/fase2-licencias.png`). Declara, por cada familia embebida, repositorio, tag exacto y presencia de `MODIFICATIONS.md`/`THIRD-PARTY-NOTICES.txt`, más la procedencia de `mks5lboot.exe`. **Nunca inventa un tag**: sin `firmware-version.txt` dice "No se conoce" y explica cómo dejarlo registrado — citar una versión equivocada sería peor que no citar ninguna, porque la obligación del §3 es señalar la fuente exacta de lo que se distribuyó. Hoy dice justamente eso, porque `artifacts/` todavía no tiene ningún Release (ver abajo).

**Driver de DFU: la vía WinUSB del plan no aplica.** El punto 4 planteaba "Apple Mobile Device Support si hay iTunes; si no, guía WinUSB". El `mks5lboot.exe` de este port no usa libusb ni WinUSB: importa `setupapi.dll` y abre el dispositivo por la interfaz `GUID_AAPLDFU` (visible entre sus símbolos), o sea la que publica el driver de Apple. Con este binario no hay alternativa WinUSB. `AppleDeviceSupport` (solo lectura, sin privilegios) reporta si hay un dispositivo Apple en el USB, si tiene driver (`ConfigManagerErrorCode` 28 = sin driver), si está el paquete de drivers y si el servicio de Apple corre. Dato aparte para la validación con el dueño: **el binario es x86 de 32 bits** y corre por emulación en ARM64.

**Alcance de este ST.** No toca `studio/AuraStudio/` (macOS) ni ningún contrato. La única frontera rozada es §A (`mks5lboot.exe`) y queda **documentada como decisión abierta, sin implementar** ningún cambio de contrato, como manda el `CLAUDE.md` del repo.

## ST-081 — Port a Windows, Fase 2 (segunda sesión): ejecución privilegiada, formateo FAT32 y asistente de instalación

**Contexto.** Cierra los puntos 3, 4 y 5 de la Fase 2 de `PLAN-aura-studio-windows-v2.md`. Sigue sin ejecutarse ninguna operación destructiva: lo que esta sesión agrega es la maquinaria y el modo de validarla sin riesgo.

**Elevación: se relanza la propia app, no un script.** `PrivilegedRunner` escribe la petición (`PrivilegedOperation` serializada) y relanza **el mismo ejecutable** con el verbo `runas` y un argumento (`--aura-privileged`); `PrivilegedHost` la intercepta en un `Program.cs` propio (`DISABLE_XAML_GENERATED_MAIN`) **antes de abrir ninguna ventana**, la vuelve a validar, re-verifica el disco y ejecuta. Un script en disco que se va a ejecutar como administrador es un blanco: entre que se escribe y que corre, cualquier proceso con acceso a esa carpeta podría cambiarlo, y lo que se elevaría sería el cambio. Relanzando el propio binario no hay nada nuevo que proteger. La petición viaja por archivo porque `runas` exige `UseShellExecute` y con eso no se pueden redirigir tuberías. Cancelar el diálogo de UAC (`ERROR_CANCELLED`, 1223) se distingue de un fallo, igual que el `-128` de AppleScript en macOS.

**Re-verificación dentro del contexto privilegiado, no antes.** `PrivilegedHost.ReverifyDisk` consulta WMI **en el proceso elevado** y exige: que el disco exista, que el bus siga siendo USB, que tenga medio montado, que el tamaño coincida dentro de la tolerancia y que el modelo no haya cambiado. Entre la confirmación del usuario y el arranque de ese proceso hubo un diálogo de UAC de por medio: el disco pudo desconectarse, reconectarse con otro número, o ser otro. Es la misma regla que en macOS hace que el script re-verifique identidad dentro del script en vez de fiarse del identificador que le pasaron. Tras `clean` se re-verifica **otra vez** antes de escribir el sistema de archivos.

**Formateo: `clean` del sistema, tabla y FAT32 propios.** `diskpart` solo hace `select disk` + `clean`. Sin particiones no hay volumen montado, así que las escrituras directas a `\.\PhysicalDriveN` no quedan bloqueadas por Windows y todo el formateo entra en un solo handle, sin bloquear ni desmontar nada. La tabla la escribe `MasterBootRecord` (Core, puro, 16 casos) con el tipo **0x0C** que el bootloader del iPod espera leer con su propio driver — `create partition primary` deja 0x07 (IFS), que no sirve — y con el primer sector alineado a 1 MiB calculado sobre el **tamaño de sector real del disco** (D-190: un valor fijo produce una tabla que Windows escribe sin error y que el bootloader interpreta mal). Encima va `Fat32Formatter`.

**Modo ensayo (`DryRun`), y el asistente lo exige.** El proceso elevado hace todas las comprobaciones y devuelve el plan real —partición, clústeres, sectores por FAT, etiqueta— **sin escribir un byte**. El asistente no ofrece el formateo de verdad hasta que un ensayo haya salido bien. No es una comodidad: nada de esta cadena se pudo probar contra un iPod, y el ensayo es cómo se valida la elevación, el paso de la petición, la re-verificación y la geometría sin arriesgar un disco.

**Verificado sin elevación y sin tocar discos.** Se invocó el ejecutable con el argumento del modo elevado y tres peticiones. Los tres guardas dispararon: disco inexistente → aborto por seguridad; petición sin tamaño esperado → aborto (no se puede re-verificar); y **el SSD del sistema → aborto por bus IDE**, con la bitácora del disco real. Ninguna ventana, códigos de salida correctos, resultado JSON escrito. Que el camino de formateo se niegue a tocar el disco de arranque es la prueba que más importaba.

**Asistente (punto 5).** Sigue `InstallerStep`: bienvenida con el aviso de que borra todo, **pantalla de permisos antes de cualquier diálogo del sistema** —la promesa textual que `PermissionsView` hace en macOS: nunca abrir una consola ni escribir un comando—, confirmación del disco con nombre, unidad, capacidad, bus y firmware detectado, preparación, DFU con guía del controlador, grabado y cierre. El grabado exige una confirmación aparte (`FlashConfirmedByUser`): es irreversible y en Solo firmware destruye el arranque de Apple.

**Aviso de cambio de familia.** Si el iPod tiene instalada una familia distinta de la elegida, se dice en pantalla que la saliente se guarda entera y se puede volver a ella. ST-046 nació justamente de ofrecerle a un iPod con Metro una actualización de Aura que lo habría sobrescrito; el cambio de familia es legítimo (contrato v10/ST-056) pero no puede pasar en silencio. Se escribieron **16 casos para `FirmwareSwitcher`**, que llegó sin ninguno: es el código que sostiene esa promesa.

**Servicio de Apple durante el grabado.** Se pausa si está corriendo y se reanuda pase lo que pase — equivalente Windows del pausado de agentes AMP (D-191). Reanudar es best-effort: que falle no puede tapar el resultado real del grabado, pero queda en la bitácora.

**Lo que esta sesión resolvió de la anterior.** El "bloqueo de biblioteca que no aparecía" con el iPod conectado **no era un defecto**: ese aparato tiene moonlit.aura instalado, así que `SupportsAuraContract` es `true` — habla el contrato aunque el USB lo atienda el firmware de Apple — y la biblioteca debe quedar abierta. Es el caso exacto que introdujo la corrección de ST-079, ahora confirmado contra hardware real.

**Lo que sigue sin verificarse, y hay que decirlo claro.** Ningún disco se ha formateado con este código y ningún bootloader se ha grabado. `Fat32Formatter`, `MasterBootRecord` y `PrivilegedHost` están probados en todo lo que se puede probar sin hardware (estructuras en memoria, guardas de seguridad, serialización), pero el primer formateo real es una validación con el dueño, y el ensayo es el paso previo obligatorio.

**Alcance de este ST.** No toca `studio/AuraStudio/` (macOS) ni ningún contrato.

## ST-082 — Port a Windows, Fase 3: cómo se leen etiquetas e imágenes, y de dónde sale ffmpeg

**Contexto.** Las tres decisiones que la Fase 3 de `PLAN-aura-studio-windows-v2.md` pide cerrar con el dueño antes de escribir código.

**Lo que pidió el dueño, y cómo se interpretó.** Para etiquetas e imágenes respondió *"igual que lo hace Aura Studio para Mac, para no generar inconsistencias"*. Literalmente no es posible: el lector de macOS se apoya en **AVFoundation** y el redimensionador en **ImageIO/CoreGraphics**, frameworks de Apple que no existen en Windows. Así que "igual que macOS" se toma como lo que evidentemente quiso decir — **mismos resultados**, no misma API — y esa lectura decide las dos opciones:

- **Etiquetas: TagLib#.** Es lo único que cubre lo mismo que AVFoundation (ID3v2.3/2.4, comentarios Vorbis de FLAC, átomos MP4/M4A, carátulas embebidas) con una sola API. Escribir los parsers a mano —que en Windows no sería *portar* el Swift sino escribirlos desde cero, porque allá ese trabajo lo hace el sistema— habría divergido en los casos raros, es decir, habría producido **más** inconsistencia, que es justo lo contrario de lo pedido.
- **Imágenes: `Windows.Graphics.Imaging`.** El equivalente de plataforma a ImageIO, sin dependencias nuevas.

**Lo que de verdad garantiza la equivalencia no es la librería, son las reglas.** Por eso el mapeo de campos se portó aparte, como funciones puras en `Core/Library/TrackTagRules`, con pruebas: el año como prefijo de 4 caracteres (y una cadena más corta se conserva tal cual, no se descarta), `"3/12"` → pista 3 (el bug concreto que perdía el número de pista en macOS incluso en ID3v2.3), los átomos `trkn`/`disk` de iTunes con el número en los bytes 2–3 big-endian y cero como "sin número", y el "primero que llega gana" del `??` de Swift —sin el cual el orden en que la librería entrega las etiquetas cambiaría el resultado—. Más el respaldo de ST-012: sin carátula embebida se toma la de carpeta (`cover.jpg`, `folder.jpg`…), que es lo que hace que un álbum arrastrado con su portada la conserve.

**Obligación de licencia que esto agrega.** TagLib# es **LGPL** y se enlaza dinámicamente (paquete NuGet), lo que es compatible con una app cerrada. Pero hay que declararlo: la pantalla de Licencias (contrato §B) hoy solo habla de los derivados de Rockbox, y **le falta TagLib#**. Queda anotado como pendiente de la propia Fase 3, no de la 7 — una dependencia LGPL sin declarar es exactamente el tipo de deuda que este proyecto no deja correr.

**ffmpeg: se busca en el sistema**, igual que macOS (D-038). Se localiza en el `PATH` y en las rutas típicas, y si no está se explica cómo instalarlo (`winget install Gyan.FFmpeg`) en vez de fallar en silencio. Sin binarios de terceros en el repositorio ni dudas de licencia. Hay una diferencia a favor de Windows que conviene anotar: allá el motivo de no empaquetarlo era el árbol de `.dylib` enlazadas dinámicamente; acá `ffmpeg.exe` es estático, un solo archivo, así que si algún día se decide empaquetarlo el obstáculo técnico no existe — lo que quedaría es la decisión de licencia (las builds habituales son GPL por incluir x264), que es del dueño. **Media Foundation se descartó a conciencia**: el iPod necesita MPEG-1/2 en contenedor MPEG-PS y Media Foundation no muxea MPEG-PS.

**Entregado en esta sesión** (Core, 350/350 tests): `TrackMetadata`, `TrackTagRules` (+18), `CoverArtAssets` (+26, incluida la regla de que soltar una imagen a propósito en Fotos gana sobre el nombre de carátula), y `LocalTagReader` (+11) probado de punta a punta contra MP3 reales construidos en el momento —tramas MPEG-1 Layer III válidas— en vez de solo contra las reglas puras.

**Alcance de este ST.** No toca `studio/AuraStudio/` (macOS) ni ningún contrato.

## ST-083 — Port a Windows, Fase 3 (segunda sesión): catálogo de la biblioteca, imágenes y miniaturas

**Se retiró el catálogo provisional de la Fase 0.** `Core/LibraryCatalog.cs` traía sus propios `LibraryItem`/`LibraryItemKind`/`LibraryItemStatus` —un esqueleto de cinco campos con `Status` = `Ready|Missing|Unsupported`— que ya no describía nada real: el `LibraryItem` portado de macOS tiene estados de proceso (en cola, enriqueciendo, transcodificando, listo, necesita revisión, falló), categoría, serie/temporada/episodio, álbum de fotos y la marca de metadata editada a mano. Dos tipos con el mismo nombre para el mismo concepto es exactamente cómo se termina con dos comportamientos distintos según quién importe cuál, así que se eliminó el esqueleto y sus dos consumidores (`LibraryViewModel`, `SyncService`) pasaron al modelo real. **Un efecto concreto:** `SyncService` copiaba siempre `SourcePath`; ahora manda al iPod lo **preparado** cuando existe (lo transcodificado o redimensionado) y el original solo si ya era apto — con el esqueleto eso era imposible de expresar, porque no había dónde guardar el resultado preparado.

**El catálogo persistido (`biblioteca.json`) conserva las cuatro decisiones de macOS que importan**, y cada una está cubierta por pruebas porque cada una protege algo que duele perder:

- **Todas las rutas son relativas** a la carpeta de biblioteca — mover esa carpeta a otro disco y volver a apuntarla la conserva entera. Con una excepción explícita: un archivo **fuera** de la biblioteca (con "copiar medios" apagado el archivo vive donde el usuario lo tiene) guarda su ruta absoluta, porque una relativa hacia afuera no significa nada.
- **La carátula no viaja dentro del JSON.** Una imagen por pista lo inflaría a decenas de megabytes y cada guardado sería una reescritura completa; vive en `.portadas/<id>.jpg` y `LibraryStore` la lee y la escribe.
- **Solo se persisten estados estables.** Lo transitorio y lo fallido se guardan como `queued`: al reabrir la app se reintenta, en vez de quedar congelado en un estado que ya no tiene proceso detrás.
- **Todo campo agregado después es anulable.** Un catálogo escrito por una versión anterior no trae `metadataEditedByUser` ni `addedAt`, y exigirlos descartaría el catálogo **entero** por un campo. Misma razón detrás de traducir las categorías viejas (`images`→`Imágenes`, `homeVideos`→`Series`…, D-228) dejando pasar cualquier otro valor tal cual: puede ser una colección que creó el usuario.

**JPEG baseline: macOS lo fuerza, Windows lo verifica.** D-291 del firmware es que el visor solo decodifica JPEG **baseline** — un progresivo sale en el iPod como "Formato no soportado". macOS se lo pide explícitamente a ImageIO (`kCGImagePropertyJFIFIsProgressive: false`); **el codificador JPEG de WIC no expone esa opción**. En vez de confiar en que haga lo correcto, la garantía se consigue del otro lado: `JpegMarkers.IsBaseline` lee los marcadores SOF de la salida y `ImageResizer` falla si no es baseline. Si algún día WIC cambiara, se sabe acá y no en la pantalla del iPod. Se comprobó de hecho, no de memoria: la salida real de WIC es baseline.

**Las miniaturas respetan el aspecto real, y ese es el punto.** Se portó el bug que el dueño reportó en macOS ("las imágenes se ven distorsionadas"): acotar el lado mayor deja una carátula 16:9 en 96×54, no en 96×96, y **declarar 96×96 es lo que hacía que se estirara** para llenar un cuadrado que el contenido nunca tuvo. La clave de la caché es por **contenido** (SHA-256 de los bytes) y no por canción, para que las 14 pistas de un álbum compartan una sola miniatura; el resumen se calcula una vez por arreglo y queda atado a esa instancia, porque volver a resumir un megabyte en cada celda al hacer scroll es justo el costo que la caché existe para evitar.

**Deuda de licencia de ST-082, pagada.** La pantalla de Licencias ya declara **TagLib# 2.3.0 (LGPL v2.1)**: qué hace, que se enlaza como archivo aparte —se verificó que `TagLibSharp.dll` efectivamente queda junto al ejecutable, que es lo que hace compatible su uso con una app cerrada— y dónde está su código.

**Una herramienta de verificación fuera de las pruebas**, `tools/ImageResizerCheck` (no está en la solución; se corre a mano). Lo que hay que comprobar del redimensionado —salida baseline, transparencia aplanada sobre **blanco** y no sobre negro, orientación EXIF respetada— depende de WIC, que solo existe bajo un TFM de Windows, y `AuraStudio.Core.Tests` apunta a `net10.0` puro a propósito. Compila el mismo archivo fuente del resizer sin arrastrar WinUI y genera sus propias imágenes. Las partes puras (tamaño destino, lectura de marcadores, clave de miniatura) sí están en las pruebas normales.

**Entregado en esta sesión** (Core, 408/408 tests; app ARM64 0 errores / 0 advertencias; 14/14 en el verificador de imágenes): `LibraryItem`, `LibraryPersistence` + `LibraryStore` (+26), `ImageResizePlan` y `JpegMarkers` (+15), `CoverThumbnailKey` (+6), `ImageResizer` y `CoverThumbnailCache` sobre WIC.

**Alcance de este ST.** No toca `studio/AuraStudio/` (macOS) ni ningún contrato.

## ST-084 — Port a Windows, Fase 3 (tercera sesión): listas, detector de similares y enriquecimiento

**Listas M3U8: el formato no es una preferencia de Studio.** Lo lee el firmware con `playlist_create()` de Rockbox, que acepta rutas UNIX **absolutas** sin tocarlas — por eso las entradas son `/Music/…` y no rutas relativas al archivo de lista, que dejarían la resolución ambigua. Termina en salto de línea y usa `\n`, no `\r\n`: se escribe para el iPod, no para Windows. Y la portada lleva el **mismo nombre base** que el `.m3u8`, porque el firmware la encuentra pelándole la extensión y probando ese nombre con `.jpg` (`aura_playlist_art_load`); los dos comparten la misma llamada a `PathSanitizer` para que no puedan divergir. Al importar, en cambio, la tolerancia es amplia a propósito: rutas relativas resueltas contra la carpeta del propio archivo (como hace cualquier reproductor), rutas absolutas de Windows y UNC, `file://`, y `\r\n` recortado — sin eso, cada ruta de una lista exportada en Windows terminaría en `\r` y ninguna coincidiría con el catálogo.

**El colage de la lista, con la geometría separada del dibujado.** `PlaylistArtLayout` (Core, con pruebas) decide cuadrantes, aspect-fill y las barras del tile; `PlaylistArtGenerator` (plataforma) dibuja con WIC. Con menos de cuatro carátulas se **reciclan desde el principio** en vez de dejar cuadrantes en blanco, y sin ninguna se dibuja el glifo de "lista" en los mismos grises que usa `aura_albumart_default_tile()` en el firmware, para que los dos casos no desentonen si el usuario los ve juntos. Dos diferencias de mecanismo con macOS, ambas verificadas contra WIC de verdad y no de memoria: el aspect-fill lo hace el propio decodificador (escala y **después** recorta, que es el orden que había que confirmar), y las puntas redondeadas se suavizan muestreando 4×4 por píxel porque acá no hay el antialiasing de CoreGraphics.

**Un límite conocido del detector de similares, que NO se corrigió acá.** El detector no compara todos contra todos: agrupa por las 3 primeras letras del título y del nombre de archivo, y por tamaño exacto. La consecuencia es que la regla de "mismo episodio de la misma serie" —pensada justamente para el caso en que los títulos no se parecen— **casi nunca alcanza a aplicarse**: dos copias del mismo episodio llamadas `cap1.mkv` y `S01E01.mp4`, con tamaños distintos, nunca llegan a compararse. macOS tiene exactamente la misma limitación, y arreglarla solo en Windows haría que las dos apps mostraran duplicados distintos sobre la misma biblioteca — justo lo que ST-082 se propuso evitar. Queda documentado con una prueba que fija la conducta real (`TwoCopiesOfAnEpisodeWithUnrelatedNamesAndSizesAreNotCompared`) y **corresponde coordinarlo con la app de macOS**, no resolverlo por un lado.

**Lo que el detector nunca debe hacer también está probado.** Un vivo contra su versión de estudio no puede salir como "Duplicado" —la sugerencia sería borrar uno de los dos—, dos canciones llamadas "Amor" de artistas distintos no se agrupan, e `IMG_0001` e `IMG_0002` son tomas consecutivas, no copias. Las propuestas de edición **nunca se aplican solas**: el detector devuelve evidencia, una confianza y una sugerencia, y quien ejecuta es la hoja de revisión con lo que el usuario elija.

**Una prueba estaba saliendo a internet de verdad.** Al armar el enriquecedor con clientes de prueba se inyectaron MusicBrainz, Cover Art Archive y LRCLIB, pero fanart.tv y Deezer se quedaron con su cliente por omisión: la prueba de "un proveedor caído no detiene a los de atrás" falló porque Deezer devolvió una **carátula real** descargada de la red. Corregido inyectando los cinco. Vale anotarlo porque el modo de falla es traicionero: la prueba habría "pasado" en cuanto la carátula existiera, dependiendo de la conexión y del catálogo de un tercero.

**"No encontré nada" y "falló la conexión" siguen siendo distintos** (D-203). `ReenrichAsync` reporta el error de red en su `EnrichmentOutcome`; `EnrichAsync` —el camino de importación en lote— se lo traga a propósito, porque una canción no puede quedar fuera de la biblioteca porque se cayó la red. El piso de puntaje de MusicBrainz (70, con un puntaje ausente contando como 0) se conservó tal cual: sin él, dos canciones del mismo álbum real terminaban con álbumes distintos, y "Sin álbum" se puede revisar mientras que un álbum inventado pasa desapercibido.

**Entregado en esta sesión** (Core, 536/536 tests; app ARM64 0 errores / 0 advertencias; 26/26 en el verificador de imágenes): `Playlist` + `PlaylistExporter`/`PlaylistImporter` (+15), `PlaylistArtLayout` (+11) y `PlaylistArtGenerator` sobre WIC, `SimilarityText` (+31) y `SimilarItemsDetector` (+22), `FilenameGuesser` (+13) y `LibraryEnricher` (+18) con un stub de HTTP propio.

**Alcance de este ST.** No toca `studio/AuraStudio/` (macOS) ni ningún contrato.

## ST-085 — Port a Windows, Fase 3 (cuarta sesión): la interfaz de la biblioteca

**La tabla de Canciones NO usa el DataGrid del Community Toolkit** — el plan pedía evaluarlo. Traería una dependencia nueva, con su propia licencia que declarar, para conseguir lo que acá hace falta: un conjunto de columnas **dinámico**. Un `ListView` con encabezado propio, armando encabezado y celdas desde la lista de columnas visibles, no tiene tope de columnas, que es justamente el punto de ST-030 frente a las 10 fijas de antes. **Lo que se cede es redimensionar columnas arrastrando**; queda anotado como pendiente, no como decisión tomada.

**Una sola página para las seis cuadrículas** (Álbumes, Artistas, Películas, Series, colecciones de fotos, listados sin agrupar). Lo único que cambia entre ellas es de dónde salen las tarjetas y qué tipo aceptan al soltar; seis páginas casi idénticas se desincronizan solas.

**El ordenamiento de la tabla es estable, y eso importa más de lo que parece.** El primer intento desempataba por título, y una prueba lo cazó: dos renglones que empatan tenían que quedar en el orden en que venían, como hace la tabla de macOS. Se cambió a un ordenamiento estable (`OrderBy`, no `List.Sort`) sin desempate artificial. Con uno inestable, las tres canciones de un mismo álbum se barajan entre sí cada vez que se reordena la tabla.

**Los glifos se verificaron renderizándolos, otra vez.** Se agregó `Resources/Glyphs.cs` con los códigos de `Segoe Fluent Icons` que usa la app, **escritos por su número y no como el carácter suelto**: el carácter cae en el Área de Uso Privado, así que pegado en el fuente se ve como un cuadrito vacío y cualquier conversión de codificación lo corrompe en silencio. El precedente es concreto: en la Fase 1 se usó `E94A` de "Dispositivos" y resultó ser el signo de división. Los nueve de esta tanda se dibujaron a un PNG y se miraron antes de usarlos.

**Se agregó el paso que faltaba entre importar y ver.** `LibraryProcessor` lee las etiquetas, adivina lo que falte del nombre del archivo y clasifica la imagen por su EXIF (`PhotoExifReader`, WIC en lugar de ImageIO). Corre al soltar **y al abrir la app sobre lo que quedó en cola**: el catálogo guarda como "en cola" lo transitorio y lo fallido justamente para que se reintente (ST-083), y hasta ahora nada lo reintentaba — se quedaba así para siempre. Una canción sin artista o sin álbum queda en "Necesita revisión", no escondida: en el iPod caería en "Desconocido" y el usuario tiene que poder verlo.

**Dos límites que quedan a la vista, no tapados.** La duración de un video hoy no se puede leer —la daría ffmpeg, Fase 4—, así que la heurística devuelve "Videos", que es el valor correcto para "todavía no sé"; Series nunca se asigna sola (D-228). Y **quitar de la biblioteca no borra el archivo**: se dice en el propio menú, porque confundirlo con "eliminar" es caro y silencioso.

**Verificado en pantalla, no solo compilado.** Se generó una biblioteca de prueba con MP3 reales etiquetados y se sembró **por el mismo camino de ingesta que usa la interfaz**: 12 canciones adentro y el `cover.jpg` del álbum reconocido como carátula y no como foto (ST-012, sobre archivos de verdad). Con eso a la vista se corrigieron dos cosas que solo se ven mirando: el encabezado de la tabla se desplazaba aparte de las filas —se despegaba de sus columnas en cuanto uno movía la tabla— y la tabla quedaba flotando en el centro al sobrar espacio. Capturas en `docs/capturas/fase3-*.png`.

**Lo que sigue faltando de la interfaz**, dicho de frente: la hoja de edición de metadatos, la de revisión de similares (el detector ya está, sin pantalla), y las listas de reproducción (el modelo ya está, la sección sigue mostrando su aviso de pendiente).

**Entregado en esta sesión** (Core, 625/625 tests; app ARM64 0 errores / 0 advertencias): `MusicTableColumn` + `MusicSortField` (+13), `MediaTableRow` con comparadores por columna (+22), `LibraryGrouping` (+28), `LibraryIngest` (+15), y en la app `LibraryViewModel`, `SongsViewModel`, `MediaGridViewModel`, `SongsPage`, `MediaGridPage`, `Glyphs`, `FilePickers`, `LibraryProcessor` y `PhotoExifReader`.

**Alcance de este ST.** No toca `studio/AuraStudio/` (macOS) ni ningún contrato.

## ST-086 — Ajustes con paridad de macOS, Credential Manager, y dos bugs que impedían leer una biblioteca hecha en la Mac

**Encargo del dueño (2026-09-01)**, adelantado de la Fase 6 a la 3: que Ajustes tenga paridad con la app de Mac, empezando por la carpeta de la biblioteca configurable "y todo lo demás".

**Las seis pestañas de macOS, con su inventario completo de preferencias**: General (tema, idioma, Acerca de con Licencias), Biblioteca (carpeta, copiar medios, carpetas vinculadas, política de carátula, enriquecimiento y letras al importar), Música (organización de carpetas, formato del nombre de archivo con ejemplo en vivo, calidad de audio), Fotos (calidad, organizar por colección, colecciones editables), Video (organizar por categoría, y por qué el formato **no** es una preferencia) y Servicios (orden de búsqueda de carátula, Deezer, claves).

**Cambiar la carpeta de la biblioteca hace exactamente lo que hace macOS: nada más que cambiarla.** Se leyó `switchLibraryFolder` antes de escribir: no migra, no copia, no mueve — apunta a la carpeta nueva, crea su estructura y lee el catálogo que haya ahí, o empieza vacía. Acá se replica igual y **se dice antes**, en un aviso permanente arriba del control, en vez de que el usuario lo descubra después.

**Las claves van al Administrador de credenciales de Windows** (`Platform/CredentialStore`, el equivalente del Llavero, D-203/ST-032/ST-033): nunca a `preferences.json`, nunca al repositorio. Se verificó contra el almacén real —guardar, leer con acentos, reemplazar, borrar, y que aparezca en `cmdkey`— y se limpió la credencial de prueba. Se implementó de verdad en vez de mostrarla deshabilitada porque era directo, que era la condición.

**Sin selector de idioma, y dicho en pantalla.** macOS tiene español/inglés; esta app es de un solo idioma por regla del repo (ST-079). En vez de dejar la sección ausente sin explicación, Ajustes › General lo dice.

### Dos bugs reales, encontrados con el catálogo del dueño

Al verificar la pantalla, un clic mío apuntó la biblioteca a `V:\Mac Externo\Documents\Aura Library` — la biblioteca **real** hecha en la Mac, con 2809 elementos. La app la mostró como **"esta carpeta todavía no tiene una biblioteca: empieza vacía"**. No era cierto, y ahí estaban dos fallas encadenadas:

1. **Las fechas de Swift.** `Codable` codifica un `Date` como segundos desde el 1 de enero de **2001**, no de 1970: `"addedAt" : 808784218.004062`. Un `DateTimeOffset?` no lo puede leer, la lectura fallaba y **se descartaba el catálogo entero**. `AppleEpochDateConverter` ahora entiende las dos formas —número de Apple y texto ISO— y sigue escribiendo ISO.
2. **Un número de pista imposible.** Una canción tenía `"trackNumber" : 4294967295` (el máximo sin signo de 32 bits, lo que devuelve una etiqueta rota leída sin signo). No cabe en un `int`, y los 2809 elementos se perdían por esa sola canción. `TolerantInt32Converter` lo trata como "sin número" y aplica el mismo criterio al disco, la calificación, la temporada y el episodio.

**Lo que dejó pasar los dos: no distinguir "vacía" de "no la pude leer".** `LibraryCatalogStore.Load` se tragaba la excepción y devolvía una biblioteca vacía, así que en pantalla los dos casos se veían idénticos. Ahora hay `TryLoad`, que dice **por qué** falló, y la pantalla distingue tres situaciones: vacía, ilegible, y catálogo bien leído pero con los archivos faltantes (lo que pasa al apuntar a la biblioteca de otra computadora).

Es la misma regla que ST-083 ya había escrito —*"un campo no puede tirar el catálogo entero"*— incumplida por el propio código que la enunciaba. Con las dos correcciones, el catálogo real se lee completo: **2809 elementos, 1082 álbumes, 634 artistas**. A esa altura no se le había escrito nada a la biblioteca del dueño (verificado por fechas). **Eso cambió después**: ver ST-087.

**Entregado en esta sesión** (Core, 659/659 tests; app ARM64 0 errores / 0 advertencias): `Library/LibraryOptions` (+14), `AppleEpochDateConverter` (+8), `TolerantInt32Converter` (+10), `Platform/CredentialStore` con `ApiKeyService`, y la reescritura de `SettingsPage`/`SettingsViewModel`/`AppPreferences`.

**Alcance de este ST.** No toca `studio/AuraStudio/` (macOS) ni ningún contrato. Los dos bugs son **solo de Windows**: macOS escribe esos archivos, no los mal-lee.

## ST-087 — Pérdida de datos en la biblioteca compartida: se guardó una lista filtrada como si fuera el catálogo entero

**Qué pasó.** El dueño usa **la misma carpeta de biblioteca desde la Mac y desde Windows** (`V:\Mac Externo\Documents\Aura Library`) — es un requisito del producto, no una prueba accidental. Al abrir la app de Windows apuntada ahí, `biblioteca.json` pasó de **2809 elementos (3,456,595 bytes)** a **401 elementos (446,642 bytes)**. Se perdieron 2408 entradas del catálogo: sus títulos, artistas, álbumes, letras sincronizadas, enlaces de MusicBrainz, calificaciones, favoritos, categorías y álbumes de fotos. **Los archivos de medios no se tocaron**; lo perdido es la metadata que solo vivía en el catálogo.

**La causa, en una frase**: la app descartaba al leer los elementos cuyo archivo no alcanzaba, y después guardaba esa lista recortada como si fuera el catálogo completo.

`LibraryViewModel.Reload` filtraba con `File.Exists` —igual que hace macOS en `loadCatalog`— y `Save` escribía esa misma lista. En macOS la combinación es inofensiva porque es su propia biblioteca y los archivos siempre están. En Windows, con 2408 rutas que no se resuelven a través de la red, el filtro se convirtió en un borrado. Bastó que el proceso de reintento de elementos "en cola" disparara un guardado.

**La regla que queda, y que no estaba escrita:** *lo que se guarda es siempre el catálogo completo; filtrar es cosa de la vista, y una lista filtrada no puede llegar jamás a una ruta de escritura.* Ahora `Items` es el catálogo entero —lo que se guarda—, `AvailableItems` es lo que se muestra, y las dos se recalculan juntas en un solo lugar. Los elementos cuyo archivo no está **se conservan intactos** y vuelven solos si el archivo reaparece. Cubierto por `CatalogPreservationTests`, que falla si el almacén vuelve a descartar algo por su cuenta.

**Dos daños colaterales del mismo error, también corregidos.** Un elemento sin metadata cargada borraba su carátula en `.portadas/` al guardarse; ahora la carátula solo se toca cuando el elemento la trae. Y `CoverPath` usaba el identificador sin guiones y en minúsculas, mientras macOS escribe `<ID EN MAYÚSCULAS CON GUIONES>.jpg`: cada app escribía su propia carátula para la misma canción y ninguna veía la de la otra.

**Escritura compatible con macOS** (requisito nuevo del producto, encargo del dueño). La app de macOS decodifica con `try? JSONDecoder().decode(...)` y un decodificador por omisión: **lo que no puede leer no da error, deja la biblioteca vacía en silencio** — el espejo exacto del bug de lectura de ST-086. Por eso ahora Windows escribe la forma que Swift decodifica: fechas como segundos desde 2001, identificadores en mayúsculas con guiones, y los nombres de campo exactos (`musicBrainzRecordingID`, `musicBrainzReleaseID`, `trackItemIDs` — los tres que la conversión automática a camelCase escribía distinto, y que Swift, que sí distingue mayúsculas, habría ignorado en silencio). `SwiftInteropTests` fija la lista completa de campos y sus tipos.

**Lo que NO se pudo recuperar.** No hay copia previa al alcance: la escritura es atómica (sin archivo parcial), el recurso es de red (sin instantáneas de Windows) y la `.Trash` del recurso no tiene nada. **La vía de recuperación es Time Machine o el respaldo de la Mac**, y es del dueño.

**Trabajo futuro anotado** (encargo del dueño): evaluar un aviso o un candado suave para cuando las dos apps abran la misma carpeta a la vez. Hoy la concurrencia es responsabilidad suya.

**Entregado** (Core, 672/672 tests; app ARM64 0 errores / 0 advertencias): `CatalogPreservationTests` (+5), `SwiftInteropTests` (+8), `SwiftUuidConverter`, y las correcciones en `LibraryStore` y `LibraryViewModel`.

## ST-088 — La app se cerraba sin decir nada: no había ningún manejador de excepciones, y el estado del dispositivo se actualizaba fuera del hilo de interfaz

**Punto de partida: la evidencia, no la sospecha.** El plan pedía empezar por el crash dump y el Visor de eventos. Hay dos registros de `AuraStudio.App.exe`, ambos con excepción **`0xC000027B`** (excepción "guardada" no controlada) en `Microsoft.UI.Xaml.dll`, con el fallo real dentro de `combase.dll`: `0x80004005` (E_FAIL) el 31/08 a las 23:27 y `0x80004003` (E_POINTER) a las 16:13. **Del lado de Aura Studio no quedó absolutamente nada**: ni mensaje, ni archivo, ni pista.

**Ese "nada" era el problema más grave, y era propio.** La app no tenía **ningún** manejador global de excepciones — ni `Application.UnhandledException`, ni `AppDomain`, ni `TaskScheduler`. En WinUI 3, una excepción que escapa de un manejador de interfaz **mata el proceso sin diálogo**; sin nada que la anote, lo único que queda es un código COM en el Visor de eventos. Ahora está `CrashReporter`: escribe tipo, mensaje y pila en `%LOCALAPPDATA%\Aura Studio\errores.log` y avisa en pantalla cuando puede. Se marca la excepción de interfaz como controlada — decisión con costo, porque la app sigue viva y quizá en un estado raro, pero morir en silencio es peor: el usuario no sabe si su iPod quedó a medias y no queda nada que mirar después.

**El defecto concreto que sí se encontró y se corrigió**: el estado del dispositivo podía actualizarse **fuera del hilo de interfaz**. `UsbDeviceWatcher.Scan()` corre en `Task.Run`, y `DevicesChanged` termina llegando a `DeviceSessionService.Reevaluate()`, que muta propiedades observables leídas por los enlaces XAML. Desde un hilo del grupo eso revienta dentro de `combase.dll` — exactamente la firma registrada. Aparecería justo en el cambio de familia porque instalar Metro después de Aura hace que el iPod se re-enumere varias veces por USB (DFU, bootloader, modo disco), y cada una dispara otro sondeo. Ahora `Reevaluate` vuelve siempre al hilo de interfaz (`App.UiDispatcher`, capturado en `OnLaunched`), y un `Debug.Assert` avisa si algún camino nuevo se salta ese paso.

**Lo que NO se puede afirmar.** Sin el iPod no hay forma de reproducir el crash, así que **no se puede decir que esté arreglado**: se corrigió un defecto real y compatible con la firma, y se eliminó la ceguera que impidió diagnosticarlo. La próxima vez que ocurra habrá un archivo legible con el tipo, el mensaje y la pila, en vez de arqueología sobre un código COM. Queda pendiente reproducirlo con el aparato.

**Punto 2 de la lista de correcciones, verificado y cerrado**: el P0 de arranque ya no está. `UsbDeviceWatcher` no consulta WMI en su constructor, `DeviceSessionService` tampoco, y el primer sondeo lo pide la ventana en `Activated` con tope de 12 s.

**`.preparados` y `.portadas` nunca se limpian** (instrucción del dueño tras ST-087). Hoy ningún código los borra; para que siga siendo cierto, `LibraryStore.NeverCleaned`/`IsProtected` lo declaran de forma consultable y `CatalogPreservationTests` lo fija. Son la reconstrucción latente de las 2408 entradas perdidas: audios ya convertidos con sus etiquetas y sus letras al lado.

**Entregado** (Core, 674/674 tests; app ARM64 0 errores / 0 advertencias): `Services/CrashReporter`, `App.UiDispatcher`, el marshalling en `DeviceSessionService`, y `LibraryStore.NeverCleaned`/`IsProtected` con 2 casos.

## ST-089 — Fase 3 cerrada: hoja de información, listas de reproducción y revisión de similares

**Hoja "Más información"** (port de `MediaInfoView.swift`). La lógica va a Core (`MediaInfoEdit`, +19 casos) y la vista solo dibuja campos: qué cuenta como completo —**título, artista y álbum son obligatorios**, con el motivo dicho en pantalla y no un botón gris—, que un campo vacío se guarde como **ausente** y no como cadena vacía, que la letra conserve su formato pero una en blanco no se guarde, que cero estrellas signifique "sin calificar", y que la carátula y los identificadores de MusicBrainz **sobrevivan** a una edición que no los toca. La hoja se arma en código porque los campos dependen del tipo y de la categoría: en XAML serían tres plantillas casi iguales que se desincronizan solas.

Editar a mano enciende `MetadataEditedByUser` — **la única vía que lo enciende**: leer etiquetas o completar en línea jamás lo hacen, que es lo que protege la corrección del usuario de una relectura masiva.

**Listas de reproducción.** Crear, renombrar, eliminar, importar M3U/M3U8 y exportar. Al importar, las pistas se resuelven contra la biblioteca por ruta y **las que no están se cuentan y se dicen** ("faltan 12 que no están en tu biblioteca"), en vez de desaparecer y que la importación parezca a medias. Eliminar una lista no borra sus canciones, y se dice. `LibraryStore.SavePlaylists` relee el catálogo y solo reemplaza las listas: guardar una parte de la biblioteca nunca puede borrar la otra (ST-087).

**Revisión de elementos parecidos** (ST-063). Cada grupo muestra **la evidencia** —por qué se juntó—, la confianza, cuál se sugiere conservar y qué correcciones propone. Nada se aplica solo. "Conservar solo este" quita de la biblioteca, **no borra archivos**, y lo dice después. "No son lo mismo" recuerda el grupo y no vuelve a mostrarlo, con un botón para restablecer. El detector corre fuera del hilo de interfaz: en una biblioteca grande compara miles de pares.

**Glifos nuevos verificados renderizándolos**: `E735` estrella llena, `E734` contorno, `E70F` editar.

**Entregado** (Core, 693/693 tests; app ARM64 0 errores / 0 advertencias): `Library/MediaInfoEdit` (+19), `LibraryStore.LoadPlaylists`/`SavePlaylists`, y en la app `MediaInfoDialog`, `PlaylistsPage`/`PlaylistsViewModel`, `SimilarItemsPage`/`SimilarItemsViewModel`.

**Con esto la Fase 3 queda completa.** Las tres decisiones que la fase pedía cerrar con el dueño ya estaban tomadas en ST-082 (TagLib#, Windows.Graphics.Imaging, ffmpeg localizado en el sistema).

## ST-090 — Port a Windows, Fase 4 (motor de sincronización): el manifiesto es el mismo archivo que lee la Mac

El dueño sincroniza **el mismo iPod desde las dos apps**. El manifiesto (`/.rockbox/aura/sync_manifest.json`) es el único archivo que las dos escriben y leen, y el `SyncManifest` provisional que había en el port tenía otra forma por completo: una lista de entradas indexada por ruta de destino, sin autor ni huella del destino. macOS no lo habría podido decodificar, y `try? JSONDecoder()` del otro lado devuelve vacío en silencio: **la Mac habría vuelto a copiar la biblioteca entera** en el siguiente sync, y al revés.

Se reemplazó por `DeviceSyncManifest`, port exacto del `SyncManifest`/`SyncRecord` de Swift: diccionario `records` indexado por ruta de origen, `contractVersion: 2`, y por registro `sourcePath`, `sourceSize`, `sourceModifiedAt`, `destinationRelativePath`, más los opcionales de v2 (`destinationSize`, `destinationModifiedAt`, `writtenBy`, `syncedAt`). Los detalles que parecen menores son justo los que rompen la compatibilidad, así que cada uno tiene su prueba: la fecha es un **número de segundos desde 1970** (el `TimeInterval` de Swift), no una fecha ISO ni los segundos desde 2001 que usa `Date` de `Codable`; un opcional ausente **no se escribe como `null`**, se omite, igual que hace Swift; un manifiesto v1 —sin las claves nuevas— decodifica igual, porque exigirlas tiraría el archivo entero por una clave que falta; y un manifiesto ilegible devuelve uno vacío en vez de una excepción, porque copiar de más solo tarda y no poder sincronizar es mucho peor.

**Tolerancia de dos segundos al comparar fechas.** macOS compara igualdad exacta porque siempre lee la misma fecha del mismo disco. Acá la biblioteca vive en una carpeta compartida de Parallels, donde la fecha que ve Windows y la que vio la Mac difieren por el redondeo del transporte: sin tolerancia, **alternar entre las dos apps recopiaría la biblioteca completa cada vez**. Dos segundos es la granularidad de FAT32, el piso de todo lo que hay en juego; el tamaño se sigue comparando exacto, y el destino también (cambiar el layout o el formato de nombre no cambia el archivo pero sí dónde va).

`writtenBy` va con el `InstallationId` de esta instalación: dos equipos sincronizando el mismo iPod no se pisan los registros.

## ST-091 — Nada sale del iPod sin que el usuario lo pida

El servicio provisional del port borraba del iPod, sin preguntar, todo lo que ya no estuviera en la biblioteca. Es exactamente lo que macOS decidió no hacer: sacar una canción de la biblioteca para reorganizarla no puede hacerla desaparecer del aparato.

Ahora el plan distingue dos cosas que antes eran una sola. Lo que **se movió** (`ToSweep`) se barre solo: el archivo no desaparece, se está escribiendo ahora mismo en su lugar nuevo, y dejarlo sería tener la canción dos veces. Lo que **ya no está en la biblioteca** (`Orphans`) se reporta y se queda donde está; solo se borra lo que llegue en `ApprovedOrphanSourcePaths`, que va vacío por omisión. La pantalla lo dice con todas las letras y muestra el conteo.

**El motor** (`LibrarySyncEngine`) es el port de la parte ejecutora de `LibrarySync.swift`, con las mismas defensas: se copia por bloques de 4 MB a un `<destino>.aura-tmp` —extensión desconocida para el firmware a propósito, para que un archivo a medio escribir **nunca** se indexe, a diferencia de un `.mp3` truncado, que sí se indexaría con metadata basura— y recién al final se renombra; los temporales que dejó un corte anterior se barren al empezar (los de las dos apps, que usan la misma extensión); hay un `sync_in_progress` mientras dura; **el manifiesto se guarda después de cada archivo**, que es lo que hace que desconectar el iPod a mitad conserve lo ya copiado; y un archivo que falla —nombre imposible para FAT32, corrupto, permisos— se anota y el resto sigue, porque el usuario prefiere 900 canciones y un aviso a nada y un aviso.

**Cancelar no es abortar**: lo copiado queda completo en el disco, y el manifiesto y el marcador se escriben igual. Un iPod con menos archivos de los pedidos pero consistente, no uno a medias que el firmware no sabe que tiene que reindexar.

**La base de música solo se borra si el firmware no anuncia `sync_marker_supported`** (contrato §4.4). Con un firmware que sí lo anuncia, borrarla le quitaría al usuario su música vieja mientras el firmware decide cuándo reconstruir. Y ni en ese caso se tocan `/.aura/thumbs/` ni `/.aura/art/`: son del firmware, sus claves no dependen de la base, y rehacerlas cuesta minutos de espera para nada.

**Un defecto que macOS no tiene y el port sí necesitaba**: dos elementos distintos pueden caer en la misma ruta de destino (mismo título en el mismo álbum, dos fotos `IMG_0001.jpg` de carpetas distintas). Sin desambiguar, una pisa a la otra en silencio y el usuario termina con menos archivos de los que mandó, sin ningún aviso; ahora la segunda recibe un sufijo `(2)`.

**Entregado** (Core, 789/789 tests; app ARM64 0 errores / 0 advertencias): `Library/SyncLayout`, `SyncPlanner`, `DeviceSyncManifest`, `LibrarySyncEngine`, `LibrarySyncFinalizer`, `ArtistImageStore`; en la app, `SyncService` reescrito sobre ellos y el `SyncManifest` provisional eliminado.

## ST-092 — Lo que se escribe al final del sync: estado completo, y sin nada que decir el archivo se borra

Después de copiar, el firmware lee media docena de archivos para armar sus pantallas. `LibrarySyncFinalizer` los escribe todos con la misma regla, que vale para cada uno: **se escribe el estado completo en cada pasada, no un diferencial**, y **sin nada que escribir el archivo se borra**. Lo primero es porque una letra que llegó por enriquecimiento después de que la canción ya estaba en el iPod tiene que llegar igual; lo segundo, porque un índice viejo apuntando a archivos que ya no están le hace mostrar al firmware entradas que no se pueden abrir.

- **Letras** (contrato §3): junto al audio, mismo nombre base, `.lrc` — la única ruta que el firmware intenta. Sin la canción en el iPod no se escribe (sería el huérfano que el contrato prohíbe), una letra borrada en Studio se va del iPod, y una que no cambió no se reescribe: sobre USB 2.0, rehacer miles de archivos idénticos cuesta minutos.
- **Carátulas**: `cover.jpg` una vez por carpeta de álbum, solo con la política `albumOnly`.
- **Listas**: `.m3u8` con las rutas del dispositivo en **NFC** (ST-062: el firmware las abre byte a byte contra los nombres largos del FAT, y Windows y macOS no normalizan igual los acentos), más su portada con el mismo nombre base — la del usuario si eligió una, si no un mosaico con las carátulas de sus pistas.
- **Pósters de temporada** (D-318): `Videos/<Serie> S0N.jpg`, del primer episodio que tenga carátula, con el mismo saneo que usaron los episodios porque el firmware concatena el nombre de programa que ya parseó con `" S%02d.jpg"`. Solo se reescribe si cambió.
- **`sync_summary.cfg`**, **`ratings.cfg`** (la calificación no vive en ninguna etiqueta: es un dato de tagcache que se pierde en cada reconstrucción, y este sidecar es lo único que la conserva — de una vía, gana la de Studio), **`video_categories.cfg`**/**`photo_categories.cfg`**, y **`artist_images.cfg`** con las fotos reducidas a 128 px.

`ArtistImageStore` porta el algoritmo de nombre de archivo **carácter por carácter** desde Swift: las dos apps escriben en la misma biblioteca y un artista tiene que quedarse con una sola foto, no con una por sistema operativo.

## ST-093 — Transcodificación en Windows: el perfil es contrato con el aparato, y ffmpeg puede estar en cualquier carpeta

El iPod Classic reproduce video con el plugin `mpegplayer` de Rockbox: MPEG-1/2 dentro de 320x240 con audio MPEG Layer II. Un archivo fuera de ese perfil **se copia perfecto y no se ve**, así que los argumentos de ffmpeg no son una preferencia sino contrato con el hardware. Por eso viven en Core, puros (`Media/FfmpegArguments`), y se prueban uno por uno sin ffmpeg instalado y sin un video de verdad: el códec, el contenedor, los 44100 Hz que libmad necesita —sin eso, un video de teléfono a 48 kHz queda mudo—, el escalado que **conserva la relación de aspecto y no rellena con barras negras** (rellenarlas dejaba todo en 320x240 exactos y el firmware no podía distinguir "video angosto" de "video con barras", volviendo inútil su lógica de ajustar/cubrir), el `-r 24` que solo se aplica cuando la fuente lo excede, y el recorte de franjas horneadas antes del escalado.

Lo que se le lee a ffmpeg también es puro y probado con texto suelto (`Media/FfmpegOutput`): duración, cuadros por segundo, resolución —recorriendo carácter por carácter, porque el nombre del formato de píxel trae comas propias que partirían la línea en pedazos equivocados— y el recorte de `cropdetect` con su umbral: un recorte de 2-3% aparece hasta en fuentes sin ninguna franja, y aplicarlo recortaría un poco de **todos** los videos sin necesidad.

**Un ajuste que macOS no tiene: dónde está ffmpeg.** Allá Homebrew lo deja siempre en uno de tres lugares y alcanza con buscarlo. En Windows puede estar en cualquier carpeta, y un usuario con ffmpeg en `D:\herramientas\` se quedaría sin recurso y sin explicación. Se busca solo en winget, Program Files, Chocolatey, Scoop y el PATH; si no aparece, la pantalla dice el comando exacto (`winget install Gyan.FFmpeg`) y ofrece elegir el ejecutable a mano. Lo elegido gana sobre la búsqueda, pero si esa ruta ya no existe se vuelve a buscar solo: desinstalar y reinstalar no puede dejar la app trabada.

**Las fotos también viajan preparadas**: el LCD es de 320x240 y una foto de teléfono ocupa cien veces lo que hace falta para verse igual. Antes del port, `LibraryProcessor` dejaba las fotos sin preparar y el original entero se habría copiado al iPod.

Un `.mpg` a medio escribir se borra si la conversión falla o se cancela: copiado al iPod se indexaría como si estuviera completo y no se podría reproducir.

## ST-094 — La pantalla de sincronizar: lo que se va a borrar se ve antes, marcado por el usuario

`SyncPage` existía y **no estaba en la navegación**: no había forma de llegar a ella. Ahora está en el pie, junto a Instalador, siempre a la vista.

La pantalla muestra tres números —por copiar, ya al día, reubicados— y, aparte y siempre que existan, **los archivos del iPod que ya no están en la biblioteca**, cada uno con su casilla sin marcar. Se explican con todas las letras: se quedan donde están hasta que el usuario marque cuáles quitar. Borrar es lo único que no se puede deshacer, así que es lo único que exige una acción deliberada.

El progreso es por archivo, con cancelación; cancelar deja lo copiado completo y anunciado al firmware, y así lo dice el mensaje final. "Expulsar el iPod" aparece recién al cerrar la sincronización — expulsar antes de escribir el marcador dejaría al firmware sin saber que tiene que reconstruir sus índices.

**Verificado en pantalla**, no solo compilado: `docs/capturas/fase4-sincronizar.png` y `fase4-ajustes-video.png`. Las dos primeras versiones de la página tenían defectos que solo se veían mirando —la tarjeta de estado quedaba alta y vacía con renglones en blanco, y quitar la alineación izquierda mandó el contenido fuera del borde derecho—; el glifo `E895` se renderizó antes de usarlo, como manda el precedente.

## ST-095 — Temas: la regla de licencia no depende de que la pantalla se acuerde

La UI de temas no existía (había una `ThemeEditorPage` vacía de 22 líneas, sin navegación) y el servicio no sabía activar ni exportar. Ahora está completo, y **la lógica vive en Core** (`ThemeInstaller`) en vez de en la capa de la app: así el ciclo que pide el plan —construir, validar, instalar, activar, eliminar— se prueba entero contra un volumen de mentira, sin un iPod conectado. La clase de la app quedó como una costura de ocho líneas.

**Un tema de uso personal nunca se exporta.** La pantalla deshabilita "Compartir…" con la explicación al lado —nunca lo esconde, ST-003— pero la regla se vuelve a verificar dentro de `Export`: si dependiera solo de la pantalla, cualquier camino nuevo la saltaría. Lo mismo con las otras dos reglas del repo: **se valida antes de instalar, nunca después** (un tema inválido no llega a tocar el iPod, y el que ya estaba sigue intacto), y **el id pasa por `AuraThemeID.IsValid` antes de tocar cualquier ruta que lo contenga** — probado con `..`, `../../..` y `con/barra`, que sin esa comprobación escribirían o borrarían fuera de la carpeta de temas.

**Activar es editar `aura.cfg`, que son los ajustes del usuario.** `ThemeActivation` (puro, en Core) cambia solamente la línea `theme_id:` y deja el resto del archivo igual; perder de paso el volumen o el color de acento sería mucho peor que no cambiar el tema. Se escribe a un temporal y se reemplaza. Es una edición transitoria —el firmware reescribe el archivo entero la próxima vez que guarda— pero tiene que sobrevivir hasta el próximo arranque, que es justo cuando la lee.

**Un tema que no carga se muestra igual, con el motivo**, y los motivos están en español y dicen qué hacer: "le faltan 3 fuentes: title, body, caption", "está hecho para la versión 2 del formato y este firmware entiende hasta la 1. Actualiza el firmware del iPod". Esconderlo dejaría al usuario sin entender por qué el tema que copió a mano no aparece. Eliminar el tema activo vuelve primero al integrado: borrar la carpeta que el firmware busca lo dejaría cargando el fallback sin explicación.

**Entregado** (Core, 866/866 tests; app ARM64 0 errores / 0 advertencias): `ThemeActivation` (+13 casos), `ThemeInstaller` (+17), y en la app `ThemesPage`/`ThemesViewModel` colgando de Extras › Temas. Lo que **no** se pudo ver en pantalla es la lista con temas de verdad: eso necesita el iPod, y queda anotado para la sesión con el dueño.

## ST-096 — Fase 6: el nombre del iPod, la hora, y completar en línea

**El nombre del iPod** (`CONTRATO-dispositivo.md` v2). `DeviceNameStore` porta el contrato entero: el archivo es `device.cfg` y **no** `aura.cfg` porque el firmware reescribe ese último completo cada vez que guarda un ajuste, y cualquier clave que no conozca se perdería en el primer cambio de volumen. Lo que más se prueba es la propiedad del nombre: **solo la instalación que nombró el iPod la primera vez lo puede cambiar**; otra lo muestra con la explicación en pantalla y el campo en solo lectura —nunca escondido, que parecería un error de la app— y jamás pisa `device_owner`. Un archivo v1 sin dueño se reclama recién en el próximo guardado real, nunca reescribiendo el archivo solo para reclamarlo.

El saneo del nombre sigue al de macOS carácter por carácter, incluido lo que parece raro: **los caracteres de control se descartan enteros**, así que un tabulador entre dos palabras las pega. Los emoji también se descartan en vez de recortarse, porque el iPod no tiene glifo fuera del BMP y mostraría cajas. Y los dos topes son a la vez: 32 caracteres **y** 48 bytes UTF-8, con una prueba que verifica que ninguna línea del archivo pase de 63 bytes — el techo real del lector de `.cfg` del firmware.

**La hora**, al conectar (`ClockSyncWriter`, contrato §D.4). El iPod no tiene forma de saberla solo y ponerla a mano en una rueda de clic es de lo más molesto que tiene. Se escribe en `aura.cfg` con el mismo cuidado que la activación de temas: solo las líneas propias, el resto del archivo intacto, y sin duplicar nada al sincronizar dos veces. El huso va en cuartos de hora porque hay husos de media hora y de 45 minutos. **Silencioso de punta a punta**: es una cortesía en segundo plano y no puede interrumpir nada; un iPod donde el firmware nunca arrancó no tiene `aura.cfg` y simplemente no se toca.

**Completar en línea**, que estaba escrito en Core desde hace tres fases y **no lo llamaba nadie**. Ahora hay un `EnrichmentService` que arma los clientes con las claves reales del Credential Manager, un botón en Canciones que trabaja sobre la selección —o sobre lo que esté incompleto si no hay selección, que es lo que uno quiere al apretarlo sin elegir nada— y otro en Artistas para las fotos.

**Las fotos de artista** (`ArtistImageResolver`, ST-032) son dos llamadas encadenadas: fanart.tv **no busca por nombre**, así que MusicBrainz tiene que resolver el identificador primero. Lo que más importa no es la foto sino el motivo cuando no hay: "te falta la clave de fanart.tv" y "no se encontró a este artista" son cosas distintas, y confundirlas manda al usuario a buscar donde no es. Un artista que ya tiene foto no se vuelve a pedir: son dos llamadas por artista y una biblioteca real tiene cientos.

**Verificado de verdad, no solo compilado**: se corrió "Completar en línea" contra una biblioteca de fixtures y la red real. La canción sin etiquetas pasó de "Necesita revisión" a "Listo" con artista y álbum resueltos, y la barra de estado reportó el conteo (`docs/capturas/fase6-completar-en-linea.png`).

**Entregado** (Core, 901/901 tests; app ARM64 0 errores / 0 advertencias): `DeviceConfig`/`DeviceNameStore` (+18), `ClockSyncWriter` (+10), `ArtistImageResolver` (+6); en la app, el campo de nombre en General, la sincronización de hora al conectar, `EnrichmentService` y los dos botones.

**Un descuido propio, corregido**: escribí un `VideoTitleParser` nuevo en `Media/` sin ver que ya existía uno idéntico en `Networking/`, portado en una fase anterior. Se eliminó el duplicado y las pruebas nuevas quedaron cubriendo al que ya estaba —que hasta ahora no tenía ninguna.

## ST-097 — Fase 7: auditoría de paridad, y lo que queda para el dueño

**Las 43 vistas de macOS, una por una**, contra lo que hay en Windows: la tabla está en `ESTADO-PORT.md`. Treinta y cuatro son equivalentes, cuatro resuelven el mismo trabajo con otro patrón (la barra de menú de la app, que Windows no lleva; la barra de actividad del dispositivo, repartida entre Sincronizar y el encabezado de la navegación; los componentes de listado y la botonera del instalador) y **tres están pendientes, a conciencia**:

- **Volver al firmware de Apple** (`RestoreHandoffView`): en macOS lo termina Finder; en Windows sería iTunes o Dispositivos de Apple. **No se puede diseñar sin probarlo con el iPod**.
- **Editar metadata por lote**: la de un elemento está completa; la de varios es comodidad, no contrato.
- **Hoja de revisión de carátulas contaminadas**: `CoverArtAssets` ya decide en Core qué imagen es carátula, pero falta la hoja con vista previa que ST-012 exige antes de quitar nada de Imágenes. **Mientras no exista, ningún camino de la app borra imágenes**, así que la regla se cumple por ausencia y no por implementación — que es una diferencia que conviene tener escrita.

**Fluent 2**: claro y oscuro verificados en pantalla con la tabla de Canciones (el caso más denso) y con Sincronizar; a 900×640 nada se corta ni se sale del borde; los botones primarios siguen el color de acento del sistema; los botones de solo ícono llevan nombre accesible. Dos cosas quedaron anotadas y **no** se arreglaron en caliente: los íconos decorativos de encabezado se anuncian como contenido, y el ajuste "barra de estado" existe sin que ninguna pantalla lo lea.

**Lo que no se pudo hacer sin el dueño ni sin el aparato** quedó consolidado en `ESTADO-PORT.md` § "Sesión de cierre con el dueño": el empaquetado (decisión suya y bloqueante), el sync real al iPod, ffmpeg instalado, las claves de fanart.tv y TMDB, la vuelta al firmware de Apple, y la revisión visual con su biblioteca.

## ST-098 — Rendimiento medido, no supuesto: 12 000 canciones y dónde está el único riesgo

El port se escribió contra bibliotecas de fixtures de doce canciones y el dueño tiene ~1000 álbumes. `tools/LibraryPerfCheck` —fuera de la solución, como `ImageResizerCheck`, porque mide y no afirma— genera 12 000 canciones y cronometra lo que la app hace en cada arranque y en cada cambio de sección.

Los números están en `ESTADO-PORT.md` y no piden ninguna optimización: leer el catálogo entero, 179 ms; agrupar los mil álbumes, 25 ms; armar y ordenar la tabla completa, 31 ms; planificar una sincronización de todo, 20 ms.

**El único punto que puede doler no es ninguno de esos**: la app comprueba que el archivo de cada elemento exista en cada recarga —54 ms en disco local— y la biblioteca del dueño vive en una carpeta compartida de Parallels, donde cada una de esas 12 000 consultas se va por la red. Medirlo contra `V:` es parte de la sesión de cierre. Si duele, la salida es **cachear e invalidar al cambiar de carpeta**, nunca quitar la comprobación: es lo que distingue "el archivo no está" de "no está en la biblioteca", y confundir esas dos cosas es exactamente lo que costó 2408 entradas en ST-087.

## ST-099 — Actualizar el firmware es un botón y una barra, no cinco pasos

Port de D-222. El aviso de versión nueva vive en General, y **el botón que la instala está ahí mismo**: no manda al asistente, no pide elegir modo, no hace navegar. Lo único que se ve es el avance y el resultado.

Por dentro es **exactamente el mismo camino de copia del asistente** —`CopyFilesAsync`, con sus mismas defensas: revalidar el disco antes de tocarlo y tomar el candado de escritura— y no hay nada nuevo que pueda romper: **no formatea y no entra a DFU**. Un árbol que ya arrancó una vez tiene su bootloader puesto, así que actualizar es reemplazar archivos y nada más.

**Siempre la familia que ya está en el iPod** (ST-047), diga lo que diga la preferencia de Extras: actualizar nunca puede convertirse en cambiar de familia sin que nadie lo haya pedido.

**No se pudo probar contra el aparato** — como todo el instalador. Lo que sí se puede afirmar es que no agrega ningún camino destructivo nuevo: si la copia del asistente es correcta, esta lo es, porque es la misma.

## ST-100 — Cierre del port: el riesgo #6 se cierra en "no, todavía no"

El plan v1 dejó abierto evaluar si `studio/windows/` debía salir a repositorio propio "si crece". Creció: **38 075 líneas de C# y XAML contra 25 246 de Swift** — el port ya es más grande que la app que porta.

**Aun así se queda acá, y el tamaño no es el criterio.** Lo que haría falta para justificar la separación es un ciclo de release propio o gente distinta trabajando en cada lado, y no hay ninguna de las dos cosas. Lo que sí hay son tres razones para no separarlo:

- **Los contratos viven en este repo** (`CONTRATO-firmware-studio.md`, `CONTRATO-formato-tema.md`, `CONTRATO-dispositivo.md`, `docs/contracts/library-layout-v1.md`) y el port los lee constantemente. Separarlo obliga a una cuarta copia sincronizada de cada uno — exactamente el modo de falla contra el que el repo ya se cuida.
- **La numeración `ST-NNN` es compartida y se cruza todo el tiempo**: ST-046, ST-062, ST-087, ST-012 se citan desde el código de Windows porque describen decisiones que valen para las dos apps. Partirla en dos diarios haría que la mitad de las referencias apunten afuera.
- **La paridad se audita comparando los dos árboles**, y esta misma noche eso se hizo media docena de veces leyendo el Swift al lado del C#. Con dos repositorios, cada una de esas lecturas es un checkout más.

Se revisa de nuevo **cuando la app de Windows tenga su propio ciclo de publicación**, no antes.

Con esto quedan corridas las fases 4 a 7 del plan hasta donde alcanza sin el iPod y sin el dueño. Lo que falta está consolidado en `ESTADO-PORT.md` § "Sesión de cierre con el dueño" (lo que lo necesita a él) y § "Post-plan" (lo no bloqueante que se encontró y se dejó anotado a propósito).

## ST-101 — Pósters de video: el último punto de la Fase 6, y el motivo dicho cuando no hay

`VideoArtworkResolver` estaba en Core desde ST-033 y **no lo llamaba nadie** — el mismo caso que `LibraryEnricher`. Peor: su `ResolveAsync` devolvía `null` para todo, y el `enum Failure` que declaraba no se usaba en ningún lado, así que quien lo llamara no podía distinguir "te falta la clave de TMDB" de "no se encontró". Esas dos cosas mandan al usuario a lugares distintos.

Ahora hay `ResolveWithReasonAsync`, que **siempre trae el motivo**, y `KindOf(category)`, que traduce la categoría de Studio a lo que se busca — reconociendo también el nombre en inglés, porque un catálogo escrito por la app de macOS dice "Movies" y tratarlo como desconocido buscaría dos veces por nada.

En la app, "Buscar pósters" aparece **solo en las cuadrículas de video** (Películas, Series, Videoclips, Todos los videos): en Fotos o en Álbumes el botón no diría nada. El póster se guarda como `<preparado>.jpg`, que es exactamente el archivo que la sincronización copia al lado del video, y también en la metadata, de donde salen la vista de la biblioteca y el póster de temporada. Uno que ya está **no se vuelve a pedir**, y si falta la clave de TMDB se corta en el primer video en vez de dar cientos de vueltas para repetir el mismo mensaje.

**Sin clave de TMDB no hay póster por ningún camino**: fanart.tv no busca por título, necesita el identificador, y el único que lo resuelve es TMDB. Eso está probado por el lado que sí se puede probar sin claves reales — el del mensaje.

**Entregado** (Core, 910/910 tests; app ARM64 0 errores / 0 advertencias): `VideoArtworkOutcome` + `ResolveWithReasonAsync` + `KindOf` (+9 casos), `EnrichmentService.FetchVideoPostersAsync`, y el botón en las cuatro cuadrículas de video (`docs/capturas/fase6-buscar-posters.png`).

Con esto la Fase 6 queda completa salvo su criterio de aceptación, que **exige las claves reales del dueño**.

## ST-102 — La biblioteca compartida se lee tolerante, y se sigue escribiendo igual

El dueño apunta la MISMA carpeta de biblioteca desde Aura Studio en la Mac y desde Aura Studio en Windows. Con el catálogo real —401 elementos escritos del lado de Windows— **la app de macOS mostraba la biblioteca vacía. Sin un solo error.**

El JSON decodificaba perfecto: los nombres de campo, los tipos y la fecha ya estaban acordados y probados del lado de Windows (`SwiftInteropTests`). Lo que fallaba era la **resolución de las rutas**, y ahí el modo de falla es silencioso por diseño: `loadCatalog()` omite todo elemento cuyo archivo no exista —criterio correcto, de un archivo ausente no hay nada que preparar ni sincronizar— así que 401 rutas irresolubles se ven **idénticas** a "todavía no agregaste nada". Es el mismo par de estados indistinguibles que costó 2408 entradas en ST-087.

Dos causas, las dos medidas contra el archivo real:

1. **Separadores `\`.** Windows arma sus rutas con `Path.Combine`, y en el JSON quedan `Música\Fatboy Slim\...`. Pegado con `appendingPathComponent` eso es UN componente con barras invertidas adentro. **401 de 401 rutas no existían; cambiando `\` por `/`, 401 de 401 existen.** Igual para las 401 `preparedRelativePath` y las 13 `coverRelativePath`.
2. **Las dos apps nombran distinto el mismo archivo de carátula.** macOS usa `UUID.uuidString` (mayúsculas con guiones, `F26DBF19-0C21-…jpg`); Windows, el hexadecimal pelado del `Guid` (`f26dbf190c21…jpg`). Las 13 carátulas del catálogo apuntaban a nombres que no existen, con la imagen ahí al lado.

**La corrección es solo de lectura.** `SharedCatalogPath` prueba candidatos en orden y se queda con el primero que exista: la ruta **literal primero** —en macOS `\` es un carácter válido en un nombre de archivo, y una biblioteca hecha acá con un archivo así tiene que seguir resolviendo a ESE archivo—, después la de separadores traducidos, y las dos normalizaciones Unicode (APFS y HFS+ no distinguen NFC de NFD, pero exFAT y un recurso de red sí). La carátula, además, cae al nombre canónico `.portadas/<UUID>.jpg` cuando la anotada no resuelve.

**El formato de escritura no se toca**: esta app sigue guardando rutas relativas con `/`, que es lo que Windows lee sin problema. El efecto secundario es deseable: al primer guardado el catálogo compartido queda canonizado solo.

Lo que la tolerancia **no** hace es inventar: una ruta absoluta de Windows (`C:\...`, `V:/...`, `\\servidor\...`) devuelve nil sin tocar disco —pegarla debajo de la raíz de la biblioteca daría una ruta absurda que además podría existir por casualidad— y un archivo que de verdad ya no está se sigue omitiendo.

**Entregado:** `Models/SharedCatalogPath.swift`, `loadCatalog()`, la migración legacy de D-228 (que comparaba los prefijos `Originales/` contra rutas que podían venir con `\`) y 11 pruebas nuevas, entre ellas un `biblioteca.json` con la forma exacta que escribe Windows.

**Para el Paquete B (Windows):** el separador canónico del catálogo compartido es `/`, y el nombre canónico de una carátula es `<UUID en mayúsculas con guiones>.jpg`. Windows lee bien las dos formas, así que **el arreglo de fondo es que escriba esas** — lo de acá es tolerancia de lectura, no la solución al problema de origen.

## ST-103 — Casillas de selección: el gesto que no se ve no existe

Las cuadrículas (Álbumes, Películas, Series, álbumes de Fotos, fotos) tenían selección múltiple desde el encargo del dueño de 2026-08-19, pero **solo se podía armar con Cmd+clic o Shift+clic**: un gesto que no aparece en ninguna parte de la pantalla y que hay que saber de antes. Las tablas, en cambio, siempre tuvieron su columna de casillas. La mitad de la app pedía conocimiento previo y la otra mitad no.

Ahora cada tarjeta de cuadrícula lleva su casilla en la esquina superior izquierda, y cada fila de episodio al principio de la fila. **Se dibuja siempre**, no al pasar el mouse ni solo cuando ya hay algo seleccionado: una casilla que aparece únicamente cuando ya sabías que estaba no resuelve el problema que vino a resolver.

La casilla **alterna** ese elemento sin tocar el resto (`GridSelection.toggle`, equivalente a Cmd+clic); el clic sobre la tarjeta sigue **reemplazando** la selección, como antes. Son dos cosas distintas a propósito: la casilla es acumulativa porque para eso existe.

Va encima de portadas cualquiera —claras, oscuras, con detalle— así que no puede depender del contraste con la imagen: disco propio (acento si está marcada, negro translúcido si no) y aro blanco.

**Artistas queda afuera** y no es un olvido: esa vista es una `List(selection:)` nativa, con la selección múltiple del sistema; agregarle casillas propias sería una segunda forma de hacer lo mismo, con otro comportamiento.

## ST-104 — Buscar carátulas del álbum: elegir, no aceptar

"Buscar información en línea" baja UNA carátula y la aplica sin preguntar. Está bien para enriquecer cientos de canciones de un tirón, pero cuando el usuario está mirando un álbum concreto y la tapa está mal, **no tenía forma de pedir otra**: la única salida era "Eliminar carátula" y quedarse sin ninguna.

"Buscar carátulas del álbum..." busca varias y las muestra para que elija. La diferencia con "Buscar póster en línea" de Películas y Series es deliberada: TMDB identifica una película con bastante certeza, mientras que dos ediciones de un mismo disco tienen tapas distintas y **las dos son correctas**. Ahí elegir no es un lujo, es la única forma de acertar — por eso esta pantalla nunca aplica nada por su cuenta, ni siquiera cuando encuentra una sola.

**Sin fuentes nuevas.** `AlbumCoverSearch` usa los clientes que ya estaban: MusicBrainz para buscar varias EDICIONES del álbum (`searchReleases`, nuevo) y Cover Art Archive para la tapa de cada una —ediciones distintas suelen tener arte distinto, y ahí está la variedad real que se le ofrece—, más Deezer (D-203, solo si está habilitado en Ajustes). Mejor esfuerzo de punta a punta: MusicBrainz caído no puede dejar sin resultados una búsqueda que Deezer sí podía contestar. Dos ediciones que comparten la misma imagen se muestran **una sola vez**: ofrecer dos veces lo mismo solo obliga a comparar dos imágenes idénticas.

Se aplica a **todas las canciones del álbum** y marca `metadataEditedByUser`: una tapa elegida a mano es una decisión del usuario y ningún enriquecimiento posterior la puede pisar. Se vuelve a preparar cada canción para que la imagen quede embebida en el archivo que viaja al iPod; si eso falla se conserva el archivo preparado que ya había —mejor una canción sincronizable con la tapa vieja que una que se quedó sin nada listo—.

**Exige UN álbum de destino.** Con una selección que mezcla discos no hay nada que buscar (¿la tapa de cuál?) y aplicar una sola imagen a todos sería justo lo contrario de lo pedido: el ítem no aparece. Tampoco para el grupo "Sin álbum", que no es un disco sino el cajón de lo que no tiene uno.

Sin resultados **se dice en pantalla**, con qué revisar (título y artista) y que Deezer se puede activar en Ajustes › Servicios — nunca se cierra sola ni deja la tapa vieja sin explicación.

**Entregado:** `Services/AlbumCoverSearch.swift`, `Views/AlbumCoverPickerView.swift`, `MusicBrainzClient.searchReleases`, `DeezerClient.searchAlbumCovers`/`fetchImage`, `LibraryViewModel.applyAlbumCover`, el ítem en el menú contextual de Álbumes y en el de la tabla de Canciones, el botón en la cabecera del detalle de álbum, y 11 pruebas con la red simulada.

## ST-105 — El inventario de menús contextuales es un documento, no una lectura del código

El Paquete B tiene que igualar en Windows los menús contextuales de macOS. Hacerlo leyendo el Swift al lado del C# **ya se probó y no escala**: los menús son diez, con condiciones que no están en ningún texto visible (el criterio Finder de qué alcanza la acción, los plurales, qué se deshabilita en vez de esconderse, dónde va cada separador). Lo que se pierde en esa lectura no da error: da un menú parecido.

`docs/paridad-menus-contextuales.md` fija los diez menús ítem por ítem, en orden, con separadores y condiciones, más las cinco reglas transversales y —esto es lo que más fácil se agrega de más— **la lista de elementos que HOY no tienen menú contextual**. La paridad también es no inventar uno donde macOS no lo tiene.

Se anotan las dos únicas divergencias legítimas: «Mostrar en Finder» es «Mostrar en el Explorador» en Windows (la excepción, escrita para que no se vuelva licencia para reescribir el resto de los textos), y el menú de un tema por omisión queda **vacío** —macOS no muestra nada— en vez de mostrar un ítem deshabilitado.

**Se actualiza en el mismo cambio que toque un menú en macOS.** Un inventario que se atrasa es peor que no tenerlo: se sigue confiando en él.

## ST-106 — Dos pruebas que con `xcodebuild` no podían pasar

La compuerta de esta ronda es `xcodebuild` de verdad, no solo `swift test` (que es el camino rápido, ver `Package.swift`). Correrla destapó dos pruebas que estaban rotas desde antes y que `swift test` nunca iba a mostrar.

**`LibrarySyncTests.testSyncWritesAlbumCoverInsideAlbumFolder`** armaba "la ruta mala" concatenando el **directorio de trabajo del proceso**. Con `swift test` el cwd es la carpeta del paquete y la prueba pasaba; con `xcodebuild` el cwd es `/`, la ruta mala se reducía a `<volumeRoot>/Music` —que el propio sync crea siempre— y **fallaba pasara lo que pasara**. Ahora enumera el volumen entero y exige que `cover.jpg` exista en la carpeta del álbum y en ninguna otra ruta: comprueba lo mismo, más fuerte, y sin depender del entorno.

**`LiveEnrichmentIntegrationTests.testCoverArtArchiveFetchesRealCover`** se quedaba con la PRIMERA edición que devuelve MusicBrainz y exigía que tuviera tapa. MusicBrainz no devuelve siempre las mismas ediciones ni en el mismo orden, y no todas tienen arte en Cover Art Archive: **medido, fallaba 1 de cada 3 corridas** sin que el código cambiara. Ahora prueba hasta cinco ediciones y se saltea si ninguna tiene tapa. Lo que la prueba existe para verificar no se toca —el parseo contra la respuesta real y que un thumbnail `http://` se pida por `https` (ATS)—: un error de red o de decodificación sigue haciéndola fallar, solo "esta edición no tiene tapa" pasa a la siguiente.

Ninguna de las dos es un cambio de comportamiento de la app. Se anotan porque **una prueba que falla sola enseña a ignorar las fallas**, y porque explican por qué el conteo verde de esta ronda (648/648 con `xcodebuild`) no se podía obtener antes.

## ST-107 — La causa raíz era de Windows: el catálogo compartido se escribe canónico

ST-102 le puso a macOS tolerancia de lectura y dejó dicho lo que faltaba de este lado. Eran **tres** cosas, no dos.

**Los separadores.** `Path.GetRelativePath` produce `Música\Artista\a.mp3` en Windows, y del otro lado eso es **un solo componente con barras adentro**: el archivo no existe, el elemento se omite al leer, y 401 elementos omitidos se ven exactamente igual que una biblioteca vacía. Ahora todo lo que va al catálogo pasa por `CatalogPath` —una sola puerta— y sale con `/`. Leer sigue aceptando las dos formas: un catálogo escrito ayer por esta misma app tiene que seguir abriendo, y al primer guardado queda canonizado solo.

**El nombre de la carátula, que ST-087 arregló a medias.** Aquel cambio corrigió el archivo que se **escribe en disco** (`<UUID en mayúsculas>.jpg`) pero no el nombre que se **anota en el catálogo**, que seguía siendo el hexadecimal pelado. Windows nunca lo notó porque lee la carátula por el id, no por ese campo; macOS sí, y vio 13 carátulas apuntando a un archivo inexistente con la imagen ahí al lado. Ahora el nombre sale del mismo lugar en los dos casos, y hay una prueba que compara justamente eso.

**Y una tercera, que apareció al verificar lo anterior**: las carátulas guardadas por versiones de Windows **anteriores** a ST-087 quedaron con el nombre viejo, invisibles para las dos apps —con el archivo intacto al lado— y la siguiente pasada las habría dado por inexistentes. `ReadCover` ahora prueba el nombre canónico y, si no está, el viejo; al guardar quedan con el nuevo, sin que nadie tenga que migrar nada.

Una ruta **absoluta** no se toca: traducirle los separadores no la haría portable —una ruta de Windows no significa nada en la Mac— y sí podría romperla acá.

## ST-108 — Casillas de selección en Windows, y por qué Artistas sí las lleva

La cuadrícula de Windows estaba en `SelectionMode="Single"` y **sin casillas**: no era una divergencia a corregir sino algo que faltaba entero. Ahora cada tarjeta lleva la suya, siempre visible, y la semántica es la de ST-103: la casilla **alterna** sin tocar el resto, el clic en la tarjeta **reemplaza** la selección.

Eso obligó a mover **abrir** al doble clic, que es lo que hace macOS y lo que hace cualquier cuadrícula del sistema. Antes un clic abría; si se hubiera dejado así, el clic no habría podido seleccionar y la mitad de la regla se perdía.

**Artistas sí lleva casillas acá, y en macOS no.** No es un descuido: allá la exclusión es por el control —`List(selection:)` trae la selección múltiple del sistema— y ese control no existe en Windows, donde Artistas es la misma cuadrícula que Álbumes. Reproducir la exclusión dejaría a Artistas como la única cuadrícula sin la forma visible de seleccionar, que es exactamente el problema que ST-103 vino a resolver. Queda como **tercera divergencia legítima**, anotada acá y en el documento de paridad.

La casilla está enlazada en dos sentidos, no atada al clic: así también funciona con el teclado y con un lector de pantalla. Verificado por esa vía —dos casillas alternadas por automatización, la barra de estado diciendo "2 seleccionados"—, que es justo la que un `Tapped` habría dejado muerta.

## ST-109 — El 503 de MusicBrainz es saturación, y el lote sigue

El hallazgo del dueño quedó registrado en el propio `errores.log`: un `EnrichmentError (HTTP 503)` escapó del lote de fotos de artista, llegó al manejador global y se comió la operación entera con un diálogo.

Ahora: el reintento **hace caso al servidor** si manda `Retry-After`, y si no espera 2 s, 5 s y 10 s —paciente de verdad, no tres intentos seguidos que fallan igual—; un artista que falla **no tumba a los que siguen**; y al terminar hay un resumen en la barra de estado, nunca un diálogo. El resumen distingue "no se encontró ninguna" de "el servicio está saturado, vuelve en un rato": confundirlas manda al usuario a creer que su biblioteca no tiene artistas reconocibles.

Con el servicio caído de verdad **se deja de insistir a las tres saturaciones seguidas**: seguir pidiendo por cada uno de cientos de artistas son veinte minutos de espera para terminar sin nada.

**Las esperas son inyectables** — no por elegancia: probar la saturación de verdad convirtió un suite de 5 s en uno de 52 s, y un suite lento se deja de correr.

## ST-110 — Buscar carátulas del álbum: el núcleo, con la semántica de ST-104

`AlbumCoverSearch` en Core con las fuentes que ya estaban: MusicBrainz para varias **ediciones** (`SearchReleasesAsync`, nuevo) y Cover Art Archive para la tapa de cada una, más Deezer (`SearchAlbumCoversAsync`, nuevo) solo si está habilitado. Dos ediciones que comparten la misma imagen se ofrecen **una sola vez**. Mejor esfuerzo de punta a punta: MusicBrainz caído no deja sin resultados una búsqueda que Deezer sí podía contestar.

**Nunca aplica nada solo**, ni con un único resultado: dos ediciones de un disco tienen tapas distintas y las dos son correctas, así que elegir no es un lujo. Exige **un** álbum con título propio —"Sin álbum" es el cajón de lo que no tiene uno, no un disco— y sin resultados lo dice en pantalla, con qué revisar.

En Windows la tapa elegida se aplica a todas las canciones del álbum y marca `MetadataEditedByUser`. **No se vuelven a preparar los archivos**, a diferencia de macOS: acá la música no se re-etiqueta, y al iPod la tapa llega como el `cover.jpg` que escribe la sincronización en la carpeta del álbum. Es otro mecanismo para el mismo resultado, y conviene tenerlo escrito.

## ST-111 — Los menús contextuales se deciden en Core, no en la pantalla

El documento de paridad es vinculante y tiene diez menús con condiciones que no están en ningún texto visible. Cablearlas en el código de las pantallas es exactamente lo que ST-105 dice que no escala: lo que se pierde no da error, da un menú parecido.

Así que los menús los arma **Core** (`LibraryContextMenus`, `MediaTableContextMenu`) y la pantalla solo dibuja. Eso permite compararlos con el documento renglón por renglón: 30 pruebas nuevas verifican el orden, los separadores, los plurales, qué se deshabilita en vez de esconderse, el criterio de Finder para el alcance, y que **ningún menú empiece o termine con un separador ni tenga dos seguidos** — que es lo primero que se rompe cuando un bloque no aplica.

Tres defectos míos los encontró esa comparación antes que cualquier persona: el submenú de categoría aparecía sobre música, y con alcance vacío el menú quedaba con un separador suelto arriba de "Eliminar".

**Y uno que solo apareció mirando**: el menú de la tabla de Canciones **no abría** salvo justo sobre la columna del título. El manejador miraba el `DataContext` del origen, y dentro de cada renglón las celdas tienen el suyo propio; había que subir por el árbol. Estaba así desde antes de esta ronda.

Cableados: el menú §4 (tablas, el más grande — 13 ítems verificados en pantalla uno por uno) y los de cuadrícula §1/§2/§5/§6/§8. **Falta cablear** §9 (fotos dentro de un álbum), §10 (temas) y §11 (encabezados de la tabla), y "Obtener información..." se filtra del §4 porque la edición en lote todavía no tiene pantalla — queda anotado en ESTADO-PORT, no escondido.

## ST-112 — Paquete B cerrado: los diez menús, y un mapeo mío que estaba mal

Quedaban por cablear §9 (fotos), §10 (temas) y §11 (encabezados). Al hacerlo apareció un error propio del turno anterior: **había mapeado "Todas las fotos" al menú §8**, el de álbumes de fotos. Una colección muestra álbumes; "Todas las fotos" muestra fotos sueltas. Son dos menús distintos y confundirlos ofrecía **"Disolver álbum" sobre una foto**. Ahora cada cuadrícula recibe el suyo, y los listados planos de video —que en macOS son tablas— reciben el menú §4 con su bloque de video, que es la equivalencia real.

**§11 es el caso donde más valía tener el menú en Core**: el documento pide que el mismo contenido salga del clic derecho en el encabezado y del botón de la barra. Antes eran dos cosas distintas —un `MenuFlyout` declarado en XAML para ordenar y nada en el encabezado—; ahora las dos entradas llaman a `SongsHeaderMenu.Build`. Dos listas armadas por separado se desincronizan en cuanto alguien agregue una opción a una sola, y eso no da error: da un menú que dice cosas distintas según por dónde se abra.

**§10 mantiene el menú vacío** para el tema por omisión: macOS no muestra ninguno, y un menú con un solo ítem deshabilitado no es lo mismo. La confirmación de eliminar es ahora una sola, compartida por el botón y por el menú.

**Verificado en pantalla, menú por menú**: §4 (13 ítems), §1 (6), §11 (4) y §9 (5), leídos por automatización de accesibilidad — que además comprueba que un lector de pantalla los ve. **§10 no se pudo ver**: la lista de temas está vacía sin un iPod conectado, así que queda para la sesión con el dueño.

Con esto el Paquete B queda cerrado: las cinco tareas completas, con las tres divergencias legítimas documentadas y "Obtener información..." filtrado a conciencia mientras no exista su pantalla.

## ST-113 — R2-1: la casilla aparece cuando sirve, no siempre

ST-103 puso las casillas **siempre visibles** con un argumento razonable: la selección múltiple solo se armaba con Cmd+clic, un gesto que no se ve en ningún lado. El dueño lo probó y el argumento no sobrevivió al uso: una retícula de círculos encima de TODAS las portadas, todo el tiempo, compite con lo único que la cuadrícula existe para mostrar.

La regla nueva —**la misma en las dos apps**, ver `docs/paridad-menus-contextuales.md` §0.7— separa los dos problemas que ST-103 había mezclado:

- **Sin nada seleccionado, cero casillas.** La cuadrícula se ve limpia.
- **Al pasar el cursor, la casilla de ESA tarjeta.** Eso resuelve la descubribilidad —que era el problema real— sin costo visual permanente.
- **Con selección ≥ 1, todas.** Ahí el usuario ya está en modo selección y necesita ver dónde sumar o quitar sin ir tanteando.

La semántica no se tocó: la casilla **alterna**, el clic en la tarjeta **reemplaza**. Y se oculta con opacidad, no quitándola del árbol: si apareciera y desapareciera del layout, la cuadrícula daría un salto cada vez que el mouse cruza una tarjeta.

**Lo de la primera fila.** El dueño reportó que la primera fila no pintaba los círculos y las demás sí. La causa es de layout, no de la casilla: Álbumes, Películas y Series ponían su cuadrícula **sin margen superior** (Fotos sí lo tenía, y por eso ahí no pasaba), así que la primera fila arranca pegada al borde del `ScrollView` y la casilla —que va a 6 pt del borde de la tarjeta— queda cortada apenas se desplaza un poco. Se unificó el margen de las cuatro cuadrículas. Es la explicación que encaja con que Fotos fuera la excepción; **no se pudo reproducir a ojo con el catálogo actual**, así que queda anotado para que el dueño lo confirme.

Los episodios son filas y no tarjetas: ahí la casilla ocupa su lugar SIEMPRE aunque esté invisible, porque si entrara y saliera del layout el texto de todas las filas se correría al pasar el mouse. Y el hover lo detecta la fila, no la casilla: una casilla invisible no recibe eventos y no podría descubrirse sola.

## ST-114 — R2-2: un ítem se ofrece si la acción tiene sentido, no si hay un solo elemento

«Buscar carátulas del álbum...» desaparecía al seleccionar más de una canción **del mismo disco**. El ítem preguntaba lo que no era: cuántos elementos hay, en vez de a qué objeto resuelven.

Ahora quien decide es `AlbumCoverRequest.forAlbum`, y decide con el **mismo agrupador que pinta la vista Álbumes** (`LibraryGrouping.albums`). Así "un álbum" significa exactamente lo que el usuario ve como un álbum —con la homologación de artistas de ST-116 incluida—, y no dos definiciones parecidas que se separan con el tiempo.

Dos correcciones de fondo que salieron con esto:

- **La tapa se aplica al álbum COMPLETO**, no solo a lo seleccionado. Elegir carátula con 2 de 12 canciones seleccionadas y que 10 se queden con la vieja no es "aplicar la carátula del álbum", es dejar el disco a medias.
- **«Quitar foto del artista» ahora es plural** cuando varios artistas alcanzados tienen foto. Estaba restringido a uno sin más razón que no haberlo pensado.

Lo que **sigue siendo singular a propósito**, revisado uno por uno: «Abrir» (abrir N detalles a la vez no significa nada), «Cambiar nombre...» y «Renombrar álbum...» (N cosas no comparten un nombre), «Más información...» (para música con varias ya existe «Obtener información...», la edición en lote) y «Vista previa» de una foto. **Video y fotos siguen sin edición en lote**: `BatchMediaInfoView` edita campos de música (artista, álbum, año, género, compositor) y no hay equivalente para los otros dos tipos — se anota como pendiente, no se disfraza.

La regla quedó escrita como regla transversal en `docs/paridad-menus-contextuales.md` (§0.3), actualizado en este mismo cambio como manda ST-105.

## ST-115 — R2-3: la carátula recomendada, y por qué el umbral es alto

El picker de ST-104 resolvió "no puedo pedir otra tapa", pero dejó al usuario comparando ocho imágenes sin ninguna pista de cuál corresponde a SU disco. Ahora cada candidata se puntúa contra lo que la biblioteca sabe del álbum y la mejor se marca **"Recomendada"**, con botón «Usar recomendada».

**`docs/caratula-recomendada.md` es la especificación vinculante** — puntaje, desempates y umbral — y la app de Windows la calca. La razón de que sea un documento y no "lo que diga el código" es concreta: si las dos apps recomiendan distinto para el mismo disco, el dueño ve la biblioteca cambiar sola según desde qué máquina la abrió.

Los pesos (título 50 > año 25 > pistas 15 > oficial 6 + país 4 > tapa frontal 10, máximo 110) están elegidos para que el orden de importancia se respete **siempre**: todo lo que está debajo del título suma 62, menos que título + año, así que una edición con título distinto nunca le gana a una con título y año iguales.

**El umbral automático es 85 de 110**, y es alto a propósito. Las dos combinaciones mínimas que llegan exigen el título MÁS una corroboración fuerte (año o número de pistas) MÁS una tapa frontal de verdad. Lo que deliberadamente NO alcanza es un título que coincide y nada más (50): es justo el caso peligroso, porque "Greatest Hits" coincide con el "Greatest Hits" de cualquiera. Deezer, que solo puede puntuar el título, **nunca llega solo al umbral**: aplicar sin preguntar exige que MusicBrainz lo respalde.

Los desempates se agotan hasta el orden de descubrimiento, que no aporta nada semántico pero garantiza un orden **total y determinista**: sin él, dos candidatas empatadas quedarían en orden indefinido y las dos apps podrían elegir distinto.

La acción automática aplica **solo** lo que supera el umbral; lo que no, **no se toca** y se cuenta en el resumen. Con exactamente un álbum pendiente se abre su picker ("si no lo supera, cae al picker"); con varios no, porque una fila de veinte pickers encadenados no es una función que alguien pueda usar.

**`metadataEditedByUser` solo lo marca la elección manual.** La automática no: esa marca significa "el usuario lo decidió", no "algo lo escribió", y blindar una tapa que nadie miró dejaría al álbum con ella para siempre, incluso cuando después aparezca una mejor.

## ST-116 — R2-4: homologar artistas agrupa, y no toca nada más

Cada colaboración inventaba un artista nuevo: "Gorillaz" y "Gorillaz feat. De La Soul" eran dos filas en la vista Artistas, dos búsquedas de foto y dos imágenes distintas en el iPod para el mismo artista.

La regla —lista **cerrada** de ocho separadores buscados como palabra completa, sin distinguir mayúsculas ni acentos— está en **`docs/normalizacion-artistas.md`**, vinculante para las dos apps. Comparar tokens completos y no subcadenas es lo que evita partir "Daft Punk" por el "ft" de adentro o "Confeti de Odio" por el "con".

**`vs.` y `versus` no homologan**, por decisión explícita del dueño: "Spacemonkeyz vs. Gorillaz" es un proyecto con nombre y discografía propios, no Gorillaz con invitados. Se documentan como lista aparte para que se lean como decisión y no como olvido.

**El alcance es la agrupación y nada más.** El `artist` de la pista no se toca nunca: los créditos completos siguen en la metadata, viajan en el archivo y se ven en la tabla y en «Más información». Y **las rutas en disco tampoco cambian** —ni la carpeta local ni la del iPod—: las dos siguen armándose con el `albumArtist ?? artist` crudo. R2-4 pidió agrupación, no reorganización, y mover carpetas en el iPod es una operación destructiva sobre archivos ya sincronizados. La consecuencia conocida (una carpeta `Gorillaz feat. De La Soul` en el iPod para un álbum que Studio muestra bajo "Gorillaz") queda anotada en el documento; unificarlas es una decisión aparte que toca el contrato de layout.

**Las fotos de artista salen bien sin tocar el contrato**, y eso no fue suerte: el índice `artist_images.cfg` (§D.3) ya escribe una línea por cada valor CRUDO de `metadata.artist` del grupo, todas apuntando al mismo archivo. Al agrupar por principal, las dos grafías caen en el mismo grupo y sus dos líneas apuntan a `gorillaz.jpg`; el firmware sigue buscando por el tag real de la pista y la encuentra.

Las opciones viajan **por parámetro** (`ArtistGroupingOptions`, `Sendable`), como `musicOrganization` y compañía, en vez de vivir en un global: así una prueba fija las suyas sin tocar las preferencias reales y `LibrarySync` —que corre fuera del hilo principal— las recibe como valor.

**Riesgo asumido y anotado:** `con` y `with` son los separadores más agresivos; en español e inglés aparecen dentro de nombres de grupo reales ("Café con Leche"). No hay forma automática de distinguirlos, así que hay **lista de excepciones editable** y el ajuste completo se puede **apagar** — y apagarlo devuelve la agrupación exacta de antes, sin migrar nada, porque la homologación nunca escribió nada.

## ST-117 — R2-4 en Windows: la homologación entra por la agrupación, no por las rutas

Port de la regla de ST-116 contra `docs/normalizacion-artistas.md`, que es la fuente. `ArtistNameNormalizer.PrincipalArtist` recorre el crédito **por tokens delimitados por espacios** y corta en el primer separador de la lista cerrada; comparar tokens completos —y no subcadenas— es lo que evita partir "Daft Punk" por el "ft" de adentro, "Confeti de Odio" por el "con" y "Blink+182" por el "+" pegado.

Los casos de prueba son **los mismos** que los de `ArtistNameNormalizerTests.swift`, a propósito: una diferencia entre las dos apps no se ve como un bug, se ve como que la biblioteca cambió sola según desde qué máquina se abrió — y le manda al iPod dos fotos para el mismo artista.

**Dónde entra, exactamente.** `LibraryGrouping` gana `GroupingArtistOf`, que es el principal, y la deja al lado de `AlbumArtistOf`, que sigue siendo el crédito **crudo**. Las claves de agrupación (`AlbumKeyOf`, `ArtistKeyOf`) y el nombre que muestran los grupos usan la primera; las rutas en disco y en el iPod siguen usando la segunda. Son dos funciones con nombres distintos justamente para que nadie las confunda al leer.

**Las opciones viajan por parámetro** (`ArtistGroupingOptions`), igual que en macOS: `LibraryGrouping`, `ArtistImageResolver.FetchMissingAsync` y `SyncFinalizeInput` las reciben. El riesgo real de esto no es el olvido de un parámetro sino el **desacuerdo**: si las pantallas agrupan con un criterio y el finalizador de sync con otro, el iPod recibe dos fotos para el artista que en Studio se ve como uno. Por eso las tres entradas salen de la misma propiedad (`IAppPreferences.ArtistGrouping`) y ninguna arma la suya.

Cambiar el ajuste **reagrupa en el momento**: `LibraryViewModel` escucha `Changed` de preferencias y avisa. Sin eso el ajuste solo surtiría efecto al reiniciar, que es la clase de cosa que el usuario lee como un bug.

## ST-118 — R2-3 en Windows: la recomendación se calca, no se reinterpreta

`AlbumCoverScoring` es un port literal de `docs/caratula-recomendada.md`: los siete criterios con sus puntos, el máximo de 110, el umbral de 85 y los seis desempates en orden. Las pruebas comprueban **cada número contra el documento**, incluidas las dos combinaciones mínimas que llegan a 85 y las tres que deliberadamente no (solo el título = 50; título + señales menores = 70; cualquier candidata de Deezer, cuyo techo es 50).

Para poder puntuar hubo que dejar de tirar datos que las fuentes ya devolvían: `MusicBrainzClient.Release` ahora deserializa `status`, `country` y `track-count`, y `CoverArtArchiveClient` gana `FetchCoverAsync`, que además de los bytes dice **si la imagen venía marcada como frontal**. Sin ese último dato, una contratapa puntuaba igual que una tapa.

**El orden de descubrimiento como último desempate no es un detalle.** Sin él, dos candidatas empatadas hasta ahí quedan en orden indefinido, y entonces la misma app puede recomendar distinto en dos corridas — que es exactamente el síntoma que R2-3 vino a evitar.

`AlbumCoverSearch.CandidatesAsync` devuelve la lista **ya ordenada por ese criterio**, así que "la recomendada" y "la primera de la lista" son la misma por construcción y no dos cálculos que se pueden separar.

**Un hueco que apareció al hacerlo:** la cuadrícula de Álbumes **ofrecía** «Buscar carátulas del álbum...» y el ítem no hacía nada — el menú lo incluía desde la Ronda 1, pero el despachador de esa pantalla no tenía el caso. La hoja vivía dentro de la pantalla de Canciones; se extrajo a `AlbumCoverPicker` y ahora la comparten las tres entradas que pide §13.2 del documento de paridad.

## ST-119 — R2-2 en Windows: dos ítems cambian de condición, y uno gana plural

«Quitar foto del artista» se ofrecía **solo con un artista seleccionado**, así que quitar cinco fotos obligaba a cinco pasadas. Ahora se ofrece si **alguno** de los alcanzados tiene foto, y el plural lo decide **cuántos la tienen** —no cuántos se alcanzaron—: con tres artistas y una sola foto, se quita una sola foto y el texto lo dice.

«Buscar carátulas del álbum...» ya usaba la condición correcta (`SingleAlbumWithTitle`, que resuelve el alcance a un álbum aunque sean varias canciones), así que ahí no hubo cambio de regla; lo que faltaba era el despachador, y eso está en ST-118.

`MenuScope` gana `ArtistsWithPhotoCount` y `ApplyingRecommendedCover`. La prueba de paridad que fijaba la regla vieja se **actualizó**, no se borró: sigue comprobando que sin nadie con foto el ítem no aparece.

## ST-120 — R2-1 en Windows: la casilla se oculta con opacidad, no saliéndose del layout

Port de la regla de ST-113. `MediaCard` gana `IsHovered` y `AnySelection`, y de las tres sale `ShowsSelectionBox`; la cuadrícula empuja `AnySelection` a todas las tarjetas cuando cambia la selección, en vez de que cada tarjeta consulte hacia arriba.

Se oculta con **opacidad** y no con `Visibility` por lo mismo que en macOS: quitarla del layout haría saltar la tarjeta cada vez que el mouse la cruza. La consecuencia es que lo invisible **sigue estando ahí para el mouse**, así que la casilla apaga también `IsHitTestVisible` — una casilla invisible que igual se puede marcar es peor que una visible.

**Y hubo que agregar cómo volver a cero.** Verificando en pantalla apareció que, una vez seleccionado algo, **no había ningún gesto para vaciar la selección**: el clic en una tarjeta *reemplaza*, así que siempre deja uno marcado. Antes daba igual —las casillas se veían siempre—, pero con la regla nueva "sin nada seleccionado" es el estado normal de la cuadrícula, y el usuario no podía regresar a él. Ahora un clic en el espacio vacío la vacía, como en el Explorador y en el Finder, y Escape hace lo mismo para quien no usa el mouse.

## ST-121 — R2-6: Artistas deja de ser una cuadrícula (se revoca ST-108)

ST-108 había documentado como **divergencia legítima** que en Windows Artistas fuera la misma cuadrícula de tarjetas que Álbumes, con casillas, porque "acá no existe el control de lista nativo de macOS". El dueño la vio y dictaminó que no se parece en nada a la de macOS. **La divergencia queda revocada**: el argumento era cómodo, no cierto.

La vista nueva calca `ArtistsView.swift`: **maestro-detalle**. A la izquierda, campo de búsqueda, botón de fotos de artista y la lista con avatar de 40 px y nombre; a la derecha, la ficha del artista — avatar de 96, nombre, resumen, «Buscar información en línea» y «⋯» — y debajo cada álbum con su portada de 128, título, "género · año", el conteo de canciones, su propio menú y sus pistas. La fila de pista lleva número, título, el **artista de la pista solo cuando difiere** del artista del grupo, duración y estrella.

**La selección la lleva el control, no el modelo.** Un `ListView` en `SelectionMode="Extended"` da Ctrl y Mayús sin escribir lógica de selección, que es exactamente lo que hace la `List(selection:)` de macOS. Con eso, esta vista **queda fuera** de la regla de casillas de R2-1 —igual que en macOS— y §13.3 del documento de paridad vuelve a ser cierto en las dos apps.

**Se borró el camino viejo, no se dejó apagado.** `MediaGridKind.Artists` y todo lo que colgaba de él salieron del modelo y de la pantalla de cuadrículas. Dejarlo habría significado tener dos vistas de Artistas, una inalcanzable, que es como se desincronizan las cosas sin que nadie lo note.

Es además la vista donde se **ve** la homologación de ST-117: los tres "Gorillaz" de una biblioteca real tienen que ser una sola fila, y las canciones acreditadas a la colaboración dicen a quién más tienen en el renglón de abajo.

## ST-122 — La app corría sin conciencia de DPI, y por eso no le llegaba la rueda del mouse

El `app.manifest` estaba en el repo declarando `PerMonitorV2`, pero el `.csproj` nunca lo nombraba con `<ApplicationManifest>`, así que **no se embebía en el `.exe`**. El SDK de .NET no lo toma por convención; hay que nombrarlo.

En un monitor al 200% eso significa que Windows le virtualiza las coordenadas a la app (medido: con el cursor en 2792,1400 el hilo recibía 1396,700), le escala el mapa de bits —de ahí que todo se viera un poco suave— y **deja de entregarle los mensajes de rueda por completo**. Con un espía de mensajes en el hilo de la interfaz no llegaba ni un `WM_MOUSEWHEEL`, mientras los `WM_MOUSEMOVE` sí. Por eso la rueda no movía nada en ninguna parte: ni cuadrículas, ni tablas, ni el panel lateral. Confirmado por el dueño en pantalla tras el arreglo.

Se corrigió además `dpiAware` de `PerMonitorV2` a `true/pm`: ese elemento viejo no acepta ese valor y Windows lo ignoraba en silencio.

**Lo que NO era:** el subclaseo Win32 de la ventana de WinUI que atiende `WM_DEVICECHANGE`. Se sospechó de él y se llegó a medir "sin subclaseo la rueda anda", pero esa medición era falsa: corría un binario viejo, porque `dotnet build -r win-arm64` deja la salida en `bin/Debug/<tfm>/win-arm64/` y la app se lanzaba desde `bin/arm64/Debug/<tfm>/`. Con el binario correcto, quitar el subclaseo no cambia nada. Quedó como estaba. El detalle de las tres trampas de medición está en `docs/ESTADO-PORT.md`.

## ST-123 — R3-1: qué firmware corre se lee del bus USB, no de las cadenas SCSI del disco

**El síntoma era "no me deja sincronizar".** Con Aura corriendo, el iPod del dueño quedaba con `RunningFirmware = Unknown`, y con eso `SupportsAuraContract` en falso: sin biblioteca, sin sync, sin temas — teniendo `aura.cfg` y `.rockbox` en el disco.

**La causa.** ST-016 dice que qué firmware atiende el USB sale de los **descriptores USB**, y el comentario del enumerador afirmaba que eso hacía. No lo hacía: `USBDeviceIdentity` se rellenaba con el vendor/producto **SCSI** parseados del `PNPDeviceID` de USBSTOR. En un iPod de fábrica esas cadenas dicen "Apple"/"iPod" y todo parecía andar. Con el adaptador **iFlash** del dueño de por medio, las reporta el adaptador: `iFlash-P` / `latform iPod Ada` (el nombre partido por los 8 y 16 caracteres del formato SCSI). Ninguna de las dos es "rockbox", y el vendor no es Apple → desconocido.

Peor: esa cadena **contiene "ipod"**, así que estaba a un carácter de clasificar mal en la otra dirección y afirmar "modo disco de Apple" sobre un iPod corriendo Aura.

**La fuente correcta, verificada contra el aparato conectado.** El nodo USB del dispositivo (`USB\VID_05AC&PID_1261\…`) expone `DEVPKEY_Device_BusReportedDeviceDesc`, que es **lo que el aparato reporta por el bus** — el equivalente exacto del descriptor USB que lee macOS. Medido en el iPod del dueño con Aura corriendo:

```
BusReportedDeviceDesc = Rockbox media player
DeviceDesc            = Apple iPod        ← el nombre del INF, no del aparato
Manufacturer          = Apple             ← también del INF
```

`DeviceDesc` y `FriendlyName` dicen "Apple iPod" **siempre**, porque los pone el driver: por eso no sirven. Y el nodo de **interfaz** (`&MI_00`) se reporta como "USB Mass Storage Device", así que se salta explícitamente; el que habla es el nodo del aparato.

Se lee con `GetDeviceProperties` de `Win32_PnPEntity` — el mismo camino que usa `Get-PnpDeviceProperty`—, así que no entra interop nuevo: sigue siendo la dependencia de WMI que ya estaba.

**Se quitó la invención.** El código anterior, cuando no lograba parsear las cadenas SCSI, rellenaba con `"Apple Inc."`/`"iPod"`. Eso es afirmar sin evidencia justo lo que ST-016 prohíbe. Ahora: descriptor del bus si se pudo leer; si no, las cadenas SCSI; si tampoco, **desconocido**. Es un cambio de comportamiento para un iPod cuyo USBSTOR no parsee — antes decía "Apple" sin saberlo, ahora dice que no sabe.

**Verificado contra el hardware, no contra una prueba.** Con el iPod conectado: General muestra "Firmware que atiende el USB: **RockboxFamily**" y "Familia declarada: **Aura**", la biblioteca se habilita, y la pantalla de Sincronizar calcula el plan real: **399 archivos por copiar**. La transferencia en sí no se ejecutó: escribir en el iPod del dueño es decisión suya.

## ST-124 — Una etiqueta no puede tumbar una copia de firmware

`FamilyChangeWarning` lanzó `NullReferenceException` dos veces en el `errores.log` del dueño: una desde `CopyFilesAsync` y otra desde `RunFormatAsync`. El camino es el mismo en las dos: `DeviceSafetyValidator.Validate` refresca la sesión —lo hace **a propósito**, revalidar el disco antes de cada operación destructiva es la regla— y ese refresco dispara `NotifyDeviceChanged`, que hace que el enlace de XAML lea la propiedad **en medio de la operación**, con el volumen yendo y viniendo.

La propiedad dereferenciaba `TargetFamily` sin guardia, confiando en que el tipo lo declara no nulo. Ahora ni ese ni ningún otro valor se toca sin comprobar, y `InstalledFamily` traga lo que pueda fallar al leer un disco que se está formateando: sin familia conocida no hay aviso, que es la respuesta correcta.

**No se aisló cuál de los dos valores estaba en nulo** — el `errores.log` da la línea, no el estado. Se dice acá en vez de afirmar una causa que no se comprobó. Lo que sí se corrigió es la consecuencia, que era la grave: una propiedad de **presentación** no puede lanzar, porque no rompe una etiqueta — mata el flujo del usuario a mitad de escribir en su iPod.

## ST-125 — R3-2: sincronizar no es una sección, es lo que se hace en General

La barra lateral de macOS (`ContentView.swift` → `SidebarSection`) **no tiene un caso para sincronizar**: están General, Música, Video, Fotos, Extras, Instalador y Ajustes, y nada más. La sincronización real vive en General, junto a `DeviceActivityBar`; la barra de herramientas solo trae "Actualizar", que es un refresco inofensivo y nunca escribe en el iPod.

Windows tenía una sección «Sincronizar» propia, con su pantalla. Se quitó: obligaba a **irse de la vista del dispositivo justo para actuar sobre el dispositivo**, cuando lo que uno mira para decidir —qué firmware corre, cuánto espacio queda, qué hay adentro— está todo en General.

Ahora General tiene su bloque de sincronización con el mismo contenido que la barra de macOS: qué se copia, los botones, el avance, el archivo en curso, los fallos y los tres conteos. Disparar la sync desde Música/Video/Fotos sigue siendo posible con «Sincronizar la selección» del menú contextual (§4.5).

**Los huérfanos pasaron a una hoja.** Lo que quedó en el iPod y ya no está en la biblioteca es lo único que Studio podría **borrar**, y borrar es lo único que no se deshace. En la pantalla vieja era un bloque más, al final, entre otros ocho. Ahora es un diálogo aparte al que se entra a propósito, con una casilla por archivo y ninguna marcada de entrada — el mismo tratamiento que la hoja de macOS.

**Divergencia conocida que se conserva:** las casillas de Música/Videos/Fotos. macOS no las tiene —allá la sync es siempre de todo—, así que son una invención del port. Se quedan porque son capacidad del usuario, no adorno; se anotan acá para que se lean como decisión.

**Lo que NO se hizo, y se dice:** «Sincronizar la selección» lleva a General pero **todavía no acota a la selección**. `SyncViewModel` sabe filtrar por tipo, no por elemento. Prometer un alcance que no se aplica es peor que llevar al lugar donde se decide, así que por ahora navega y queda anotado.

## ST-126 — Dos enlaces de Temas convertían un booleano a Visibility y tiraban la pantalla

En el `errores.log` del dueño, `InvalidCastException: Unable to cast object of type 'System.Boolean' to type 'Microsoft.UI.Xaml.Visibility'` al dibujar la lista de temas.

Eran dos enlaces de `ThemesPage.xaml`: uno ataba un `bool` a `Visibility` **sin convertidor**, y el otro usaba `InvertBoolConverter`, que devuelve un `bool` — o sea, tampoco convierte a `Visibility`. Los dos revientan al primer tema que se dibuja.

Es una clase de error que **no se ve hasta que la pantalla se dibuja con datos**: compila, y la plantilla solo se instancia cuando hay filas. Por eso, además de arreglar los dos, se barrió el resto de la app buscando lo mismo —`Visibility` atado sin convertidor, `Visibility` atado con `InvertBool`, y el convertidor de visibilidad usado en propiedades que no son `Visibility`—: no había más.

## ST-127 — R3-3 (a): la interfaz estaba imprimiendo el nombre de un enum

El dueño comparó las dos Generales y encontró **"RockboxFamily"** en pantalla: en el título de la ficha, en la barra de estado y en el destino de la sincronización. No es una etiqueta mal redactada — es el identificador interno de uno de los tres hechos de ST-016, y no significa nada para quien solo quiere saber si su iPod está listo.

Entraba por dos puertas:

- `IPodDiskInfo.DisplayName` terminaba en `- {RunningFirmware}`, y ese nombre lo usan la ficha, la barra de estado y el encabezado de Sincronizar. Ahora es solo el nombre: "iPod Classic (IPOD)".
- `DeviceListViewModel.FirmwareUsbDisplay` era literalmente `RunningFirmware.ToString()`, mostrado como el valor de una fila "Firmware que atiende el USB". Esa fila y su pareja ("Familia declarada") **desaparecen**: las reemplaza una frase.

`DeviceFirmwareLabel` (Core) arma esa frase, port del `firmwareLabel` de macOS. Los tres hechos siguen separados por dentro; lo que cambia es que afuera se dicen con palabras: *"Firmware Aura instalado — conectado desde Aura"*.

**Lo que la frase NO hace es redondear.** Las combinaciones que no son evidencia de instalación lo dicen enteras: archivos en el disco con el firmware de Apple atendiendo el USB y sin rastro de arranque se leen como *"no hay evidencia de que esté instalado"*, no como "instalado". Hay una prueba por combinación, y una que recorre las 24 y falla si cualquiera imprime `RockboxFamily`, `Unknown` o el nombre de un tipo.

## ST-128 — R3-3 (b,d,f): General es una ficha de dispositivo, no una pila de tarjetas

Era una columna de tarjetas con pares etiqueta/valor —el patrón de una pantalla de ajustes—, cuando lo que describe es **un aparato**. Ahora:

- **Encabezado**: icono, nombre editable, de dónde viene ese nombre, la frase del firmware y la ruta del volumen. Sin tarjeta: es la identidad de la ficha, no un bloque más.
- **Estado del firmware** sobre la lógica que ya existía (ST-099). Lo que se agregó es el caso normal: antes, "no hay actualización" era **silencio**, y el silencio obliga a adivinar. Ahora dice "Aura está al día con esta versión de Aura Studio", y hay un "Buscar actualizaciones" manual — antes solo se consultaba solo al conectar, así que quien deja el iPod conectado no tenía forma de volver a preguntar.
- **Barra de capacidad segmentada**, con leyenda y "X usados de Y — Z libres", en lugar de cuatro filas de números que había que leer y restar. Es el ancla de la ficha.

`StorageBreakdown` (Core) hace la aritmética con sus reglas: "Otro" es lo usado que no es biblioteca y **nunca es negativo** —si el resumen del último sync quedó viejo y suma más que lo usado, se recorta a cero en vez de dibujar una barra imposible—, y "Libre" no lleva entrada en la leyenda porque es el resto implícito (mismo criterio que la barra del firmware, D-282). Los colores se quedan en la vista: Core dice cuánto ocupa cada cosa, con qué se pinta es del tema.

Los anchos se arman en código y no con enlaces: son **proporcionales a los bytes**, y eso no se expresa en XAML.

**Lo que quedó pendiente de (e), y se dice:** el selector "Toda la biblioteca / Solo la selección" y el "N pendiente(s)" **no** se pusieron. `SyncViewModel` no tiene alcance por elemento ni conteo de pendientes previo a revisar; poner el control sin eso sería un adorno que no hace nada. Es el mismo hueco que ya estaba anotado en ST-125 para «Sincronizar la selección», y se cierra junto con él.

## ST-129 — R3-4: alcance real de sincronización, y el huérfano que casi se inventa

Cierra el hueco que ST-125 y ST-128 dejaron anotado: «Sincronizar la selección» navegaba sin acotar, y la ficha no podía ofrecer "Solo la selección" ni decir cuántos archivos había listos.

**La regla vive en Core** (`SyncScopeResolver`), no en la pantalla, porque son tres negativas parecidas con tres textos distintos y un **orden** que cambia lo que el usuario entiende: primero las del alcance —son las que explican qué le falta a SU selección— y recién después la global. Al revés, quien selecciona tres canciones en una biblioteca sin nada listo leería "no hay nada listo para sincronizar" y no sabría si el problema es lo que eligió. Los tres mensajes son los mismos que los de macOS.

Solo viaja lo que está **listo**: algo a medio convertir o esperando una decisión del usuario no es un archivo que se pueda copiar, y se queda fuera aunque esté seleccionado.

**El defecto que apareció al conectarlo, y que es el motivo de contarlo aparte.** Acotar la copia acota el plan, y los **huérfanos salen del plan**: con "Solo la selección", todo lo demás del iPod habría aparecido como "ya no está en tu biblioteca" — una lista de cientos de archivos ofrecidos para borrar que en realidad sí están. Nada se borra sin que el usuario marque la casilla, pero ofrecerlo ya es el error: es la clase de cosa que se paga con archivos del usuario. Ahora los huérfanos **siempre** se calculan contra la biblioteca entera, aunque la copia esté acotada.

**En la interfaz**: el selector "Toda la biblioteca / Solo la selección" con su conteo, la línea de cuántos hay listos, y el botón deshabilitado cuando el alcance apunta a una selección vacía — el botón nunca lleva a un camino que falla. Si la selección se vacía, el alcance vuelve solo a "toda la biblioteca": un alcance que apunta a nada no es un estado en el que dejar a alguien.

**La selección la publica la vista activa** (tabla de Canciones, cuadrículas, Artistas) y se **limpia al salir**. Sin esa limpieza, "solo la selección" seguiría apuntando a lo que había seleccionado dos pantallas atrás, que es exactamente cómo se copia lo que no era. En las cuadrículas, una tarjeta es un álbum o un artista: lo que viaja son sus canciones, no la tarjeta.

**El conteo de pendientes es una aproximación y se redacta como tal**: dice "N archivos listos para sincronizar", no "se van a copiar N" — eso lo dice «Revisar cambios», que sí compara contra el aparato. Alguno de esos N puede estar ya sincronizado con ESE iPod.

## ST-130 — Un selector de la interfaz ponía en nulo la familia de destino

`FirmwareArtifacts.DirectoryFor` lanzó `NullReferenceException` en el camino de copia de firmware. El nulo no era la ruta de la app —`AppContext.BaseDirectory` nunca lo es— sino **la familia**.

**Y con eso quedó identificada la causa que ST-124 no pudo aislar.** Es la misma: `InstallerViewModel.TargetFamily` se queda en nulo. El culpable son **dos** enlaces `SelectedItem="{x:Bind ViewModel.TargetFamily, Mode=TwoWay}"` en la pantalla del instalador: cuando a un selector se le reemplaza la lista de opciones —cosa que pasa cada vez que se recalculan las familias disponibles—, el control vacía su selección y **escribe nulo de vuelta en la propiedad**. Nadie lo pidió, y nada lo delataba hasta que alguien la leía: el aviso de cambio de familia reventaba al pintarse, y la copia reventaba al resolver los artefactos, las dos con el iPod a medio escribir.

El arreglo restaura el valor **anterior**, no "Aura": volver a Aura por omisión convertiría un destino Metro en un destino Aura sin que nadie lo eligiera, que es exactamente la trampa de ST-046.

`DirectoryFor` además se endurece de dos maneras distintas a propósito: sin raíz cae a la del ejecutable —es lo que quería decir quien llamó—, pero **sin familia lanza**. Elegir una por omisión resolvería el directorio de un firmware que el usuario no pidió, y el que llama está a punto de copiarlo al iPod. Una excepción con nombre es mucho mejor que un `NullReferenceException`: dice qué faltaba.

## ST-131 — La sincronización moría porque el avance se escribía desde otro hilo

Verificando en pantalla apareció, en el camino de sincronización: *"No se pudo completar la sincronización: La aplicación llamó a una interfaz que se aplanó para un diferente subproceso."* Es `RPC_E_WRONG_THREAD`.

`SyncViewModel.OnProgressChanged` escribía las propiedades enlazadas —archivo en curso, avance, mensaje— **desde el hilo del servicio**: el evento `ProgressChanged` se dispara dentro del `Task.Run` que hace la copia. Cada escritura notificaba a los enlaces de XAML, que tocaban el árbol visual fuera del hilo de la interfaz, y Windows abortaba la operación **a media copia**.

Se cruza al hilo de la interfaz con el `DispatcherQueue` capturado al construirse. Vale anotar por qué el instalador nunca tuvo este problema: usa `IProgress<T>`, que **captura el contexto de sincronización al construirse** y marshalea solo. Un `event` no captura nada: corre donde lo disparen.

**Verificado con el aparato**: con el arreglo puesto, una copia completa de 399 archivos terminó bien —"El iPod ya está al día con tu biblioteca", 0 por copiar, 399 al día— y `errores.log` no creció ni un byte. Sin el arreglo, esa misma copia moría en el camino.

## ST-132 — Dos tercios del ático de ST-077 vuelven al build

`ReleaseCache` y `FirmwareVersionResolver` estaban apartados en
`docs/attic/st077-cadena-descarga/` desde la Fase 2, colgando de un modelo de
artefactos (`BundledArtifacts`) que se descartó al reconciliar el árbol. La
pantalla Extras los necesitaba —las pastillas de versión son justamente lo que
resuelven—, así que se remontaron contra `FirmwareArtifacts`, que es el modelo
que sobrevivió. La conversión fue la que el propio README del ático anticipaba:
un parámetro.

**Lo que las pruebas cuidan es la llave por familia.** Con una sola, la lista de
Releases de Metro quedaría guardada bajo la de Aura: conectar un iPod con Metro
y después uno con Aura le mostraría al segundo los tags del primero durante 24
horas, comparados contra su propio `version.txt` (ST-046). Aura conserva las
llaves históricas —sin sufijo— para que nadie pierda su caché al actualizar
Studio.

Un caché ilegible se trata como ausente, nunca como error de cara al usuario: la
consulta en vivo lo reemplaza en la misma pasada.

**El descargador se queda en el ático**, y no por olvido: Extras necesitaba
saber *qué versión se instalaría*, no bajarla. Bajarla es otra tarea, con sus
cinco trampas ya documentadas (la URL del API y no `browser_download_url`, el
`Authorization` que se suelta en el 302, la publicación atómica, el tag validado
antes de componer una ruta, y fallar sin detener la instalación). El README del
ático quedó actualizado diciendo exactamente qué se remontó y qué no.

## ST-133 — R4: Extras deja de ser un marcador de posición

Port de `ExtrasView.swift`. Cuatro bloques, en el mismo orden que macOS y con
sus textos: el selector de firmware, lo que hay en el dispositivo, lo que
todavía no existe, y las licencias.

**El selector es una preferencia, no una acción.** Elegir ahí no toca el iPod: el
Instalador —con su flasheo y sus confirmaciones— es el único que escribe, y una
actualización desde General lo ignora y reinstala la familia que el aparato ya
tiene (ST-046). Se guarda por su `ConfigValue`, la misma cadena que escribe
macOS, así que agregar una familia en medio de la lista no cambia lo que el
usuario eligió; y **Aura se guarda como ausencia de clave**, igual que en
`aura.cfg`.

**Y el Instalador ahora la lee.** Esto no era un detalle de cableado: la
preferencia existía en la pantalla y el asistente seguía fijando Aura en su
constructor, así que elegir Metro en Extras no cambiaba nada de lo que se iba a
instalar. Verificado de punta a punta con la app: elegir Metro → el archivo de
preferencias dice `metro` → el Instalador abre con Metro.

**Las pastillas dicen de dónde salió la versión.** "v0.6.4 (incluida)" no es lo
mismo que "v0.6.4": la primera es la que trae esta copia de Studio, la segunda
es la más nueva publicada. Sin esa distinción, un Release publicado después de
poblar `artifacts/` era invisible ahí aunque el aviso de actualizaciones ya lo
conociera. El pie lo dice entero y ofrece «Revisar de nuevo», que **salta el
caché de 24 h**: una revisión manual tiene que ser una consulta en vivo (D-300).

**Temas se deshabilita explicando qué falta** (ST-053), con las dos razones
separadas: sin iPod con el contrato, o con un firmware que no tiene sistema de
temas —moonlit.aura no publica la clave—.

**Lo que NO se portó, y por qué.** El bloque de macOS para *cambiar* entre
familias ya instaladas (ST-056: "Cambiar a Metro" cuando está dormido en el
disco) se queda fuera: depende de saber qué familias hay **dormidas** en el
aparato, y `IPodDiskInfo` no lo modela todavía en Windows. Poner el botón sin
ese dato sería ofrecer un cambio que no se puede decidir. Queda como tarea con
nombre, no como hueco silencioso.

De paso se retiró `PlaceholderPage`: con Extras ya no queda ninguna sección sin
pantalla propia, y dejar colgando el camino que la usaba invitaba a volver a
colgar algo ahí.

## ST-134 — Un publish completo que no arrancaba: falta el índice de recursos

El primer `dotnet publish` autocontenido de la app Windows salió perfecto —437
archivos, 289 MB, sin un solo error— y al abrirlo moría de inmediato con
`STATUS_STOWED_EXCEPTION` (0xC000027B). El manejador global alcanzó a escribir
el motivo: *«Cannot locate resource from `ms-appx:///MainWindow.xaml`»*.

Faltaba **`AuraStudio.App.pri`**, el índice de recursos que resuelve las URIs
`ms-appx:`. El SDK lo genera y lo copia al directorio de salida, pero **no lo
marca para publicar**. Lo traicionero es que los `.pri` de los frameworks sí
vienen —los traen sus paquetes NuGet— así que el publish aparenta tener índices
de recursos y le falta justo el único que es suyo: 2 MB dentro de 289.

Se arregla en `AuraStudio.App.csproj` con un target que lo agrega a
`ResolvedFileToPublish`. Y junto a él va **un segundo target que falla el
publish si el archivo no quedó**: un instalador que empaqueta una app que no
abre es peor que un build roto, porque el error aparece en la máquina de quien
la instaló y no acá. `scripts\Make-Installer.ps1` lo vuelve a comprobar antes
de empaquetar, con la misma idea.

## ST-135 — R5: el instalable de Windows es Inno Setup, por usuario y sin UAC

Instalador clásico con publicación autocontenida (`WindowsAppSDKSelfContained`),
**no MSIX**. La razón es la cadena privilegiada: Aura Studio se relanza a sí
misma elevada (`PrivilegedRunner` → `PrivilegedHost`) para formatear el disco
del iPod, y el contenedor de MSIX rompe justo ese patrón. Además espeja la
decisión macOS de distribuir fuera de la tienda (D-033).

**Instalar no pide permisos de administrador** (`PrivilegesRequired=lowest`,
a `%LOCALAPPDATA%\Programs\Aura Studio`). Esto no es comodidad: la app le
promete al usuario que la elevación llega **por operación**, explicada antes en
pantalla y solo cuando de verdad va a tocar el disco. Un instalador que pide
UAC de entrada enseña lo contrario en el primer segundo.

**El riesgo real de empaquetar así era que la elevación dejara de funcionar
desde la ruta instalada**, porque `PrivilegedRunner` relanza
`Environment.ProcessPath`. Verificado desde la ruta instalada con una petición
de ensayo (`DryRun`) contra un disco que no existe: el proceso arranca sin
abrir ventana, revalida, vuelve a consultar el hardware y aborta con
«el disco 42 ya no existe». Lo único que no se pudo probar sin el dueño
presente es el diálogo de UAC en sí — está anotado en ESTADO-PORT.md con el
comando exacto para hacerlo en un minuto.

**El aviso GPL v2 se muestra antes de instalar**, no enterrado en una carpeta
(`installer\AVISO-LICENCIAS.txt`): qué componentes son derivados de Rockbox,
las tres familias con su versión, y las URLs de los tres repositorios de
fuentes. Los `MODIFICATIONS.md` y `THIRD-PARTY-NOTICES.txt` de cada familia
viajan junto a sus binarios, y `Make-Installer.ps1` **rehúsa empaquetar** si
falta cualquiera de los seis.

**Desinstalar no borra los datos del usuario.** `%LOCALAPPDATA%\Aura Studio`
—preferencias, caché de Releases, registro de errores— sobrevive; el aviso de
licencias dice dónde queda. Verificado desinstalando y reinstalando.

Dos pendientes conscientes, no descuidos: **sin firma de código** (SmartScreen
va a advertir la primera vez) y **solo ARM64**, que es lo único que esta ronda
construyó y probó. Un x64 sin probar no se ofrece.

## ST-136 — `mks5lboot.exe` se comparte desde la raíz: Metro y moonlit no se instalaban

El dueño instaló Aura sin problema desde el instalable y las otras dos familias
se negaron con «Los archivos del firmware no se pudieron verificar, así que no
se instala nada».

**No era la lógica, eran los datos.** Los Releases publican `mks5lboot`
—binario POSIX— por familia, con tres hashes distintos; el `.exe` de Windows es
nuestro cross-compile y vive **solo en la raíz** de `artifacts/`, con su
`.origin` al lado (ST-080). La verificación lo exigía dentro de la carpeta de
cada familia, así que Aura —que vive en la raíz— pasaba, y sus hermanas fallaban
por faltarles un archivo que en Windows **nunca** van a traer.

Ahora `FirmwareArtifacts.ResolveTool()` busca primero en la carpeta de la
familia y, si no está, usa el de la raíz. **Se puede compartir porque la
herramienta es independiente de la familia**: habla DFU con el hardware del iPod
y recibe como argumento el bootloader que va a grabar. Ese bootloader sí es de
cada familia, sí viene de su Release y se sigue verificando contra su propio
`checksums.txt` — se comparte el martillo, no el clavo. El `.origin` que manda
es el que está junto al binario que se va a ejecutar, no uno de la carpeta de la
familia; y un `.exe` reemplazado en la raíz rompe a las tres, que es lo correcto.

Si algún día un Release publica el `.exe` por familia, el suyo gana sin cambiar
nada: el respaldo solo entra cuando no está.

**Las pruebas de fixtures no podían encontrar esto**, porque escribían siempre
un juego completo de archivos. Por eso se agregó `RealArtifactsTests`, que
verifica las **tres** familias contra el `artifacts/` real del árbol. Se
comprobó que muerde: quitando el `.exe` de la raíz, las tres fallan nombrando su
propia ruta.

## ST-137 — Un error que no dice cuál archivo ni por qué no es un error, es un ruido

La misma falla dejó ver un patrón peor que el bug: la tarjeta de fallo del
Instalador mostraba **solo** `StatusMessage` —«Los archivos del firmware no se
pudieron verificar»— y descartaba el `DetailMessage`, que ya traía el detalle.
Dos fallas muy distintas —falta un archivo, o un hash no cuadra— se veían
idénticas, y la información existía: solo no estaba en pantalla.

Tres cambios:

- **La tarjeta de fallo muestra el detalle**, seleccionable, para poder copiar
  el nombre del archivo e ir a verlo.
- **Los mensajes nombran archivo y motivo.** «Falta `artifacts\metro\
  mks5lboot.exe` (tampoco está en `artifacts\mks5lboot.exe`)», «El checksum de
  `artifacts\metro\rockbox.ipod` no coincide (esperado a1b2c3d4…, calculado
  9f8e7d6c…): el archivo está dañado o no es el que publicó el Release». Las
  rutas se muestran desde `artifacts\` —la ruta de instalación completa es
  ruido— y de los hashes se enseñan ocho caracteres, no sesenta y cuatro.
  Un problema por renglón: pegados con espacios, tres archivos faltantes se
  leían como una sola frase.
- **`Fail()` fija el detalle siempre, aunque sea vacío.** Antes no lo tocaba, así
  que un fallo sin detalle propio se quedaba con el de la operación anterior.
  Mientras el detalle no se mostraba daba igual; ahora que se muestra, un
  detalle viejo junto a un error nuevo sería peor que ninguno.

## ST-138 — Elegir en Extras no producía ningún efecto visible

«Desde Extras no ocurre nada», reportó el dueño. Verificado en la app instalada:
la selección **sí** funciona —la tarjeta entera responde y la preferencia
persiste, Aura como ausencia de clave— pero lo único que pasaba al elegir era
que se movía el punto del radio.

Lo que faltaba era el bloque que macOS sí tiene (`switchControls` de
`ExtrasView.swift`): decir qué implica la elección y ofrecer la acción. Ahora,
debajo del selector: «Se instalará Metro la próxima vez que uses el Instalador»
—o, con el iPod conectado, «Tu iPod tiene Aura. Instalar Metro lo agrega: Aura
se guarda dormido con sus ajustes y no se borra nada»— y un botón «Instalar
Metro» que lleva al Instalador. **No instala desde ahí**: el flasheo y sus
confirmaciones siguen siendo del asistente.

**Lo que sigue faltando, dicho aquí para que no se pierda:** macOS distingue un
tercer caso —la familia elegida está *dormida* en el disco, y entonces ofrece
«Cambiar a …», que no reinstala nada (ST-056)—. Windows no puede todavía:
`IPodDiskInfo` no modela las familias dormidas. Por eso los textos de acá **no
prometen** poder volver desde esta pantalla, que es justo lo que sí promete el
texto de macOS. Prometer un botón que no existe sería peor que no decir nada.

De paso: navegar a otra sección desde Extras usaba `Frame.Navigate`, que cambia
la página pero deja la barra lateral marcando «Extras» — el usuario terminaba en
el Instalador sin que nada dijera dónde estaba. Ahora pasa por la barra
(`ShellPage.GoToSection`), así que selección y contenido se mueven juntos.
Licencias no está en la barra y por eso sigue abriéndose como subpágina.

## ST-139 — La variante x64, probada bajo emulación en el propio aparato ARM64

Hasta ST-135 solo se ofrecía ARM64, con el argumento de que «un x64 sin probar
no se ofrece». Ese argumento **caducó**: Windows 11 en ARM64 ejecuta binarios
x64 emulados, así que el instalable x64 se puede armar, instalar y usar en la
misma máquina del dueño. No es fe, es una prueba — con el precedente de que
`mks5lboot.exe` es x86-32 y lleva todo el proyecto corriendo emulado.

`installer\AuraStudio.iss` recibe la arquitectura por `/DArch=`, y
`Make-Installer.ps1 -Architecture arm64|x64|both` produce
`dist\AuraStudioSetup-0.1.0-<arch>.exe`.

**`ArchitecturesAllowed=x64compatible` para el x64, no `x64os`**: la primera
incluye a ARM64 y es justo lo que permite instalarlo ahí. En una máquina ARM64
el Setup x64 **avisa que existe la versión nativa y deja continuar** — informar,
no prohibir: quien lo instale a propósito puede tener su razón (probar,
reproducir un problema). El aviso calla en modo silencioso, donde no hay quien
lo lea y un diálogo colgaría una instalación desatendida.

**Un solo `AppId` para las dos.** Son el mismo programa; la arquitectura es un
detalle del empaquetado. La consecuencia buscada es que **no convivan**:
instalar una reemplaza a la otra en el mismo lugar. Dos entradas con el mismo
nombre y el mismo icono serían ~600 MB y ninguna forma de saber cuál abre el
acceso directo — y el caso que de verdad ocurre, alguien en ARM64 que bajó el
x64 por error y después instala el nativo, se arregla solo. Lo que sí cambia
por arquitectura es `UninstallDisplayName`, para que la entrada diga cuál está
instalada.

**El precio de compartir carpeta, y cómo se paga.** Casi todo el árbol tiene
los mismos nombres en las dos y se sobrescribe solo; lo que no —dos DLL con la
arquitectura en el nombre, y unos `workloads.*.json` del Windows App SDK—
quedaba tirado, y el desinstalador de la otra arquitectura no lo conoce: basura
que sobrevive a la desinstalación. Lo limpia `[InstallDelete]`.

Esa lista se pudre en cuanto el SDK agregue otro archivo así — de hecho el
primer intento se quedó corto y los `workloads.*.json` aparecieron después. Por
eso **`Make-Installer.ps1 -Architecture both` compara los dos árboles
publicados archivo por archivo y avisa** si aparece uno que ningún patrón
cubra. Avisa y sigue: un huérfano no justifica no entregar el instalador.

Y una verificación más, contra el error silencioso y caro de empaquetar el
árbol de una arquitectura dentro del Setup de la otra: se lee la cabecera PE
del ejecutable publicado y se compara con la arquitectura pedida.

### Qué quedó probado bajo emulación, y qué no

Todo esto **en el x64 instalado y corriendo en esta VM ARM64**, con
`xtajit64se.dll` —el emulador— cargado en el proceso, y con la máquina nativa
reportando `0xAA64`:

- Instala, arranca y pinta la interfaz completa; lee la biblioteca.
- La **cadena privilegiada** funciona: el proceso arranca sin ventana, revalida
  la petición, vuelve a consultar el hardware por WMI y aborta con «el disco 42
  ya no existe». Es decir, `System.Management` y las llamadas nativas funcionan
  emuladas.
- **`mks5lboot.exe` (x86-32) corre desde el proceso x64 emulado** —emulación
  anidada— y hace su `--dfuscan`.
- Cambiar de arquitectura en los dos sentidos deja una sola entrada, un solo
  ejecutable y **ningún archivo huérfano**.

**Lo que NO se pudo probar, y hay que decirlo:** no había ningún iPod conectado
—`Win32_DiskDrive` reporta un solo disco fijo—, así que la detección real del
aparato, el formateo y el flasheo **no se ejercitaron en el x64**. Y una VM
ARM64 emulando x64 no es lo mismo que una máquina x64 física: comparten el
binario, no el hardware ni el controlador USB de Apple. Lo que falta es una
prueba con iPod, preferentemente en una máquina x64 de verdad.

## ST-140 — El recorte cuadrado es una primitiva, no un efecto del reescalado

Hasta hoy Aura Studio **nunca** recortó una imagen. `ImageResizer` (macOS) y su
port de Windows hacen una sola cosa —meter el lado mayor dentro de un máximo
conservando la proporción—, y de ahí salían dos incumplimientos del contrato:
`cover.jpg` viajaba **cruda**, con la proporción que tuviera la fuente
(~1000 px, 4:3, 16:9, lo que fuera), y las fotos de artista iban a 128 px de
lado **mayor** con su proporción original, cuando §D.3 las exige **cuadradas**
desde v6 (`LibrarySync.swift:1069`, `LibrarySyncFinalizer.cs:448`).

Que el firmware lo tolere no lo vuelve inocuo. Su caché maestra sí rellena y
recorta (§D.5), pero los caminos que **no** pasan por la maestra —"Ahora suena"
a 135 px y el decode de CoverDrift a 320 px en Aura, el fondo sin mtime de
Metro— decodifican con ajuste dentro de una caja cuadrada y después aplican
esquinas, reflejo y transposición **asumiendo que el bitmap es cuadrado**: con
una carátula 4:3 el stride no coincide y la imagen se rompe en pantalla. Eso es
exactamente el glitch que reportó el dueño. El arreglo tiene dos mitades —la
del firmware (ronda de los tres firmwares) y la de acá— y esta es la de acá:
que lo que Studio escribe sea cuadrado de origen.

**La aritmética se separa del codificador.** `SquareCropPlan` (macOS:
`Sources/AuraStudio/Services/SquareCropPlan.swift`; Windows:
`AuraStudio.Core/Library/SquareCropPlan.cs`) responde, sin tocar ImageIO ni
WIC: qué cuadrado se conserva y de qué lado sale. Es la misma decisión de
diseño que `ImageResizePlan` en el port —lo verificable sin plataforma se
prueba sin plataforma—, y acá vale doble: los dos archivos de prueba
(`SquareCropPlanTests.swift` / `.cs`) tienen los **mismos casos con los mismos
números**, así que el día que una plataforma cambie de criterio se ve en el
diff, no en el iPod.

Lo que el plan fija:

- **Rellenar y recortar al centro**, nunca estirar ni poner bandas. Se conserva
  el cuadrado central del lado corto; se tira la mitad sobrante del lado largo
  repartida en los dos extremos.
- **El píxel sobrante de un margen impar se descarta del lado derecho (o
  inferior)**, por división entera. Da igual cuál se elija, pero tiene que ser
  el mismo en las dos plataformas y siempre el mismo: si no, dos apps producen
  `cover.jpg` distintas para la misma carátula y el sync las reescribe en
  ping-pong.
- **Nunca se agranda.** Una fuente con lado corto de 200 px sale de 200, no de
  320 — el mismo criterio que ya tenía `resizeToLCDOptimal`.
- **El plan se calcula sobre las medidas ya orientadas.** Una foto vertical de
  cámara viene guardada horizontal con la rotación en EXIF; se recorta lo que
  se ve, no cómo está guardado.

Y lo que fija el codificador:

- **Se fija el lado CORTO, no el mayor.** ImageIO y WIC escalan por el lado
  mayor; pedirles 320 daría un lado corto de 240 y el recorte tendría que
  agrandar. Se les pide el mayor proporcional redondeado **hacia arriba**, y el
  recorte sale sin inventar píxeles.
- **El lado final es el del plan sobre la fuente, siempre.** Si el redondeo de
  la miniatura deja 319, se reescala a 320: el contrato v18 fija medidas
  exactas (320×320, 128×128) y un píxel de menos es un incumplimiento, no un
  detalle.
- Sigue valiendo todo lo de antes: aplanado sobre **blanco** (no negro) para
  las fuentes con transparencia, y **JPEG baseline** garantizado —macOS se lo
  pide a ImageIO, Windows verifica la salida con `JpegMarkers.IsBaseline`
  porque WIC no expone la opción (D-291).

**Nadie llama todavía a la primitiva.** Esta entrada agrega la herramienta y su
verificación; los puntos de ingreso de la biblioteca (ST-141) y la escritura al
iPod (ST-142) son las dos fases siguientes, y hasta entonces el comportamiento
observable de la app no cambia. Se hizo así a propósito: una primitiva de
imagen que se estrena directo en el camino que escribe al iPod es la clase de
cambio que se descubre con el iPod en la mano.

**Verificación.** macOS: 705 pruebas en verde (21 nuevas), y las de recorte no
comprueban solo el tamaño —pintan franjas de color en los márgenes que el
recorte debe tirar y verifican en las cuatro esquinas del resultado que ya no
están, que es lo que delata un recorte descentrado o un "ajuste" con bandas.
Windows: `AuraStudio.Core` con 1 112 pruebas (13 nuevas); las 32 que fallan en
una Mac son las de siempre —rutas con `\`, `C:\`, ffmpeg de winget— y no
cambiaron de número.

**Lo que queda para la VM de Windows**: `EncodeSquareAsync`/`SquareCropAsync`
viven en `AuraStudio.App/Platform/ImageResizer.cs`, que depende de WIC y **no
compila en macOS**; acá solo se verificó que el archivo parsea y que su uso de
`SquareCropPlan` type-checkea contra `AuraStudio.Core`. Las comprobaciones
20-27 nuevas de `tools\ImageResizerCheck` (`dotnet run --project
tools\ImageResizerCheck -c Release`) son las que cierran esa mitad: mismos
casos que macOS, mismos números. Ojo con una diferencia real de la plataforma:
en WIC el recorte se pide con `BitmapTransform.Bounds`, que se aplica sobre la
imagen ya escalada; un cuadrado centrado es el mismo antes y después de la
orientación EXIF, así que lo único que puede cambiar de lado es el píxel
sobrante de un margen impar.

Evidencia: `docs/capturas/ronda-caratulas/fase1-recorte-cuadrado.png` (origen
con la franja descartada en rojo → resultado, para 4:3, 16:9 y 1:4) y los tres
JPEG que produjo el código de producción, junto a ella.

## ST-141 — La carátula se guarda cuadrada desde que entra, no al salir

ST-140 dejó la herramienta; esta entrada la enchufa. **Todo** lo que hace que
una carátula exista en la biblioteca pasa ahora por la misma normalización —
cuadrada, lado = min(lado corto, 1000), JPEG q0.92:

- la que baja de la red (Cover Art Archive, fanart.tv, Deezer) y la que trae la
  etiqueta del archivo (o el `cover.jpg` de su carpeta): las dos salen de
  `LibraryEnricher.enrich`/`reenrich`, que es donde se normaliza (Windows:
  `EnrichmentService.EnrichAsync` y `LibraryProcessor.ProcessMusic`);
- la que el usuario elige en la hoja de candidatas, la que arrastra y la que
  aplica la recomendación automática: `applyAlbumCover` / `ApplyAlbumCover`,
  una sola vez por álbum y no una por canción;
- la que aparece al "volver a leer etiquetas del archivo": `mergingLocalTags` /
  `RetagFromFile`;
- las fotos de artista: `ArtistImageStore.save` / `.Save`.

**Por qué desde el origen y no al sincronizar.** Lo que viaja al iPod se deriva
de la copia local, así que una copia 4:3 obliga a recortar en cada sync y deja
la vista previa de la app mostrando una imagen distinta a la del aparato.
Guardándola cuadrada una sola vez, la app, el iPod y la carátula embebida
muestran lo mismo. Y el decode caro (una imagen de 1000 px) ocurre una vez por
carátula, no una por sincronización.

**Lo que se pierde, dicho de frente: la franja recortada no se recupera.** Es lo
pedido —cuadrado siempre—, y por eso el recorte solo toca la copia de
`.portadas/`: **el archivo original del usuario no se toca nunca**, ni en la
migración ni al ingresar.

**Los pósters de video NO se tocan.** Son 3:4 por diseño (contrato §A.1) y viven
en la misma carpeta, con el mismo formato de nombre (`<id>.jpg`) que una
carátula de álbum, porque comparten el campo `coverArtData`. Por eso la lista de
archivos a migrar se arma **desde los items del catálogo, mirando su `kind`**, y
no listando el directorio: recortar un póster cuadrado sería el bug, no el
arreglo. Hay una prueba que lo fija (`VideoPostersAreNeverInTheList`).

### La migración de una biblioteca que ya existe

`biblioteca.json` gana `coversNormalized` (ausente = biblioteca vieja; `2` =
carátulas cuadradas). Al abrir una biblioteca sin la marca, una pasada en
segundo plano recorre las carátulas de las canciones y todas las fotos de
artista. Tres propiedades, y las tres tienen prueba:

- **No reescribe lo que ya cumple.** Cuadrada y ≤ 1000 px se salta leyendo solo
  la cabecera. Recomprimir de gratis pierde calidad y no arregla nada.
- **Se puede cancelar** (botón en la barra de progreso, al pie de la ventana),
  y se consulta antes de cada archivo. La escritura es atómica: cancelar nunca
  deja un archivo a medias.
- **Se retoma sola, sin archivo de progreso.** Saltarse lo ya hecho ES el
  mecanismo: la siguiente apertura vuelve a recorrer (leer cabeceras es barato)
  y termina lo que falte. Por eso la marca se escribe **solo** cuando la pasada
  llega al final; una cancelada no marca nada.

Al terminar, lo que quedó en memoria es la versión vieja, así que se relee de
disco (macOS `reloadCoversFromDisk` + `artistImages.invalidate()`; Windows
`Reload()`): sin eso, la app seguiría mostrando la rectangular hasta el próximo
arranque.

La barra de progreso **no la esconde** "Visualización › Mostrar barra de
estado", a diferencia de la barra de estado normal: mientras corre hay archivos
reescribiéndose y un botón para detenerlos; ocultarlo dejaría al usuario sin la
única forma de cancelar.

### Dos cosas que NO cambiaron, a propósito

- **`CoverThumbnailCache` y el `aspectFill` de las cuadrículas se quedan como
  están.** Con carátulas cuadradas el "llenar" no recorta nada, pero el mismo
  componente dibuja los pósters de video (3:4): quitarlo los deformaría. El
  arreglo de ST-113 —que el `NSImage` reporte el aspecto REAL del bitmap para
  que `.fill` recorte en vez de estirar— sigue siendo lo correcto.
- **El puntaje de la carátula recomendada no cambia.** Un bonus para las
  candidatas ya cuadradas no cambiaría ningún resultado (todas terminan
  cuadradas), la proporción no dice nada sobre si la tapa es la correcta, y
  mover el máximo (110) obligaría a recalibrar el umbral automático (85) en los
  tres lugares a la vez. Queda escrito en `docs/caratula-recomendada.md` §8.

### Verificación

macOS: `swift build` + **717 pruebas en verde** (12 nuevas), y además
`scripts/build-app.sh` completo —`xcodegen` + `xcodebuild` Release, que compila
en **modo Swift 6 estricto** (D-034), donde el primer intento de publicar el
avance desde el hilo de la migración era un error de captura concurrente y no
un aviso—. Windows: `AuraStudio.Core` con **1 131 pruebas** (19 nuevas); las 32
que fallan en una Mac son las de siempre (rutas con `\`, `C:\`, ffmpeg de
winget) y no cambiaron de número.

**Lo que queda para la VM de Windows**: `WicSquareImageEncoder` (el puente a
WIC) y el cableado en `LibraryViewModel`/`EnrichmentService`/`LibraryProcessor`
no compilan en macOS; acá solo se verificó que parsean y que su uso de Core
type-checkea. Y falta **el botón de cancelar en la interfaz**: el modelo ya
expone `IsNormalizingCovers` y `CancelCoverNormalization()`, y el avance se
publica por `StatusMessage` (que las páginas ya muestran), pero el botón en sí
es XAML y se agrega allá — mientras tanto, en Windows la migración se puede
detener cerrando la app, y se retoma igual.

Evidencia: `docs/capturas/ronda-caratulas/fase2-biblioteca-cuadrada.png` (antes
y después de una migración real, con la barra de progreso renderizada de la
vista de verdad).

## ST-142 — Lo que llega al iPod: 320×320, y solo cuando cambia

Tercera pata de la ronda: ST-140 hizo la herramienta, ST-141 dejó cuadrada la
biblioteca local, y esto es lo que de verdad ve el firmware.

**`cover.jpg` pasa a ser 320×320** y **`.rockbox/aura/artists/*.jpg` a 128×128**,
las dos recortadas al centro desde la copia local — que desde ST-141 ya es
cuadrada, así que acá es un reescalado y nada más. La carátula **embebida**
(política "una por canción") es el mismo JPEG de 320: hasta hoy se embebía la
copia de biblioteca (~1000 px), casi un megabyte por canción para que el aparato
la reescalara a 130 de todos modos.

**320 no es un número al azar** (maestro §A.1): es el consumidor más exigente
que existe — CoverDrift decodifica el JPEG directo a 320. Con 120 se veía
borroso; con los ~1000 px de la biblioteca, la fase de fotos del constructor del
firmware se hacía lenta para nada.

### El hallazgo que cambió el alcance: reescribir de más rompe la caché del firmware

`writeAlbumCovers` reescribía **todas** las carátulas en **cada** sincronización,
y `writeArtistImages` lo mismo con las fotos de artista. Hasta v17 eso era solo
desperdicio de USB 2.0. Con v18 es un bug: la clave de la caché maestra del
firmware incluye ahora el `mtime` de `cover.jpg`, así que reescribirla idéntica
en cada sync le tira **toda** su caché de carátulas cada vez que el iPod se
conecta — justo lo contrario de lo que la ronda vino a arreglar. Desde acá, las
dos escrituras comparan contra lo que ya está en el disco y **solo escriben si
los bytes cambiaron** (mismo criterio que ya tenían las letras `.lrc`).

Y su consecuencia en el marcador: un sync que no copió ni una canción pero sí
cambió una carátula **sí tocó la sección Música**, porque el firmware tiene que
rehacer esa maestra. `writeAlbumCovers` ahora informa si escribió algo y eso
alimenta `sync-pending.json` (en Windows, `SyncFinalizeResult.AlbumCoversChanged`
+ `SyncPendingMarker.Merge`, que **une** secciones en vez de reemplazarlas: el
motor escribe el marcador antes de que corra el finalizador, y el segundo no
puede borrar lo que anunció el primero).

### Cuánto cuesta el primer sync

Con **N** álbumes y **A** artistas con foto, el primer sync tras esta versión
reescribe **N + A** imágenes — una vez. Todas cambian de bytes (antes iban
crudas o con la proporción original), así que no hay forma de evitarlo, y es
exactamente lo que hace falta para que el firmware v18 regenere su maestra con
la clave nueva. **A partir del segundo sync son 0** mientras el usuario no
cambie una carátula. Está probado en las dos plataformas: dos pasadas seguidas
dejan el mismo `mtime`.

**El conteo de "pendientes" no las cuenta, y nunca las contó**: ese número sale
de `SyncPlanner`, que planea archivos de medios (audio, video, fotos); las
carátulas, las letras y los índices se escriben en `finalize`, después de
copiar. No es algo que esta ronda cambie — se deja anotado porque el plan pedía
verificarlo: lo que el usuario ve como "N pendientes" seguirá siendo el número
de canciones, aunque además se reescriban N carátulas la primera vez.

### Con firmwares anteriores a v18

Las carátulas nuevas **no se ven hasta que ese firmware purgue su caché**: sin
`/.aura/art/format.txt` ni la clave con `mtime` de `cover.jpg`, un tile mal
derivado sobrevive para siempre. No hay nada que Studio pueda hacer desde este
lado — es la razón por la que los tres firmwares y este Studio salen en el
**mismo ciclo de release**.

### El contrato

`CONTRATO-firmware-studio.md` sube a **v18** con el texto del maestro §A.2:
nota de v18 en §D.3 (fotos de artista), párrafo nuevo "Versión de formato y
purga" y la clave de álbum con `mtime` de `cover.jpg` en §D.5, fila nueva
`/.aura/art/format.txt` en la tabla de §D, y sale de "pendientes" el
`--family moonlit` de `fetch-firmware.sh` (ya implementado). Verificado
byte-idéntico contra la copia canónica de `Aura-Firmware`.

**`docs/contracts/library-layout-v1.md` destapó un problema real: la copia de
Studio llevaba desactualizada desde el 2026-08-26.** El plan maestro pedía
numerar el párrafo nuevo como "v1.3", pero acá la v1.3 ya existía (D-318,
2026-08-18) — y al mirar el archivo del hermano apareció que allá ya iba una
**v1.4** (D-341: `cfcache` con clave estable, GC con presupuesto, la caché
maestra compartida) que **nunca se copió a Studio**. La versión canónica quedó
en **v1.5** (D-349), con el contenido de D-341 más el párrafo de las carátulas
cuadradas, y este repo la tiene ahora byte a byte (`cmp` limpio).

**La regla que sale de esto, y que vale para cualquier contrato compartido:
antes de copiar, `diff` del archivo ENTERO contra el hermano.** Copiar en la
dirección equivocada no da un conflicto que alguien note — da una reversión
silenciosa, y el archivo se queda meses diciendo algo que ya no es cierto.

### Verificación

macOS: `swift build`, **726 pruebas en verde** (9 nuevas de sync sobre un
volumen de prueba: 320×320, 128×128, sin agrandar una carátula chica, no
reescribir lo idéntico, sí reescribir lo que cambió, no mandar nada si la
imagen no se puede decodificar, y el marcador con Música) y
`scripts/build-app.sh` completo (xcodebuild Release, Swift 6 estricto).
Windows: `AuraStudio.Core` con **1 139 pruebas** (8 nuevas); las 32 que fallan
en una Mac son las de siempre (rutas Windows).

**Lo que queda para la VM de Windows**: `EncodeSquareAsync` y el puente
`SquareCrop` de `SyncService` no compilan en macOS (WIC). Y un hallazgo que
**no** es de esta ronda pero conviene no perder: Windows fija
`CoverArtPolicy.AlbumOnly` al sincronizar, ignorando la preferencia del
usuario — allá no existe la escritura de etiquetas, así que "una por canción"
dejaría al iPod sin ninguna carátula. Es coherente, pero no está dicho en
ninguna parte del código.

Evidencia: `docs/capturas/ronda-caratulas/fase3-sync-contrato-v18.png` — una
sincronización real contra un volumen de prueba, con los tamaños medidos sobre
los archivos escritos, la segunda pasada sin reescrituras y el
`sync-pending.json` que quedó.

## ST-143 — "Actualizar el arranque": lo único que la NOR no deja verificar

El bootloader de esta ronda cambia (pantalla de arranque nueva, plan maestro
§B). El problema es que **la NOR del iPod no se puede leer desde la Mac**: la
única forma de saber qué arranque tiene grabado un aparato es acordarse de
haberlo grabado. Ese registro existe desde ST-016
(`AppPreferences.bootloaderVerifiedDisks`), pero guardaba **la fecha**, que no
sirve para responder la pregunta que ahora importa: *¿el arranque que tiene es
el que traigo yo?*

**El valor pasa a ser el SHA-256 del `bootloader-ipod6g.ipod` que se flasheó.**
Los registros anteriores se migran a `"unknown"` — que **no** es lo mismo que
"no verificado": hay un arranque nuestro, solo que no se sabe cuál. Tirarlos
habría forzado un DFU innecesario en cada iPod ya instalado.

Y el hash de comparación sale del **artefacto real que usaría este flujo**
(`InstallerViewModel.embeddedBootloaderHash`), no de leer `FIRMWARE_VERSION` a
mano: ese archivo describe lo embebido y dejaría de ser cierto en cuanto ST-077
instale un Release más nuevo que el pin. Se compara además contra **la familia
que el iPod tiene instalada** (`device.declaredFamily`), no contra la elegida en
Extras: a un iPod con Metro se le ofrece el arranque de Metro.

### La regla, y por qué es un tipo aparte

`BootloaderUpdate` (macOS y `AuraStudio.Core`, con los mismos casos en los dos
archivos de prueba) decide con tres datos y nada más:

- **hash registrado ≠ hash embebido** → hay algo que ofrecer;
- **y hay rastro de firmware nuestro en el disco** → si no, lo que corresponde
  es *instalar*, no "actualizar el arranque";
- **sin bootloader embebido** (una build sin `fetch-firmware.sh`) no se ofrece
  nada: flashear algo que no existe es peor que no ofrecer.

Devuelve además el **motivo**, porque la pantalla no dice lo mismo en los dos
casos: "esta versión trae un arranque más nuevo" cuando se sabe, y "no sabemos
cuál tienes — lo instaló otra computadora, o una versión anterior de la app"
cuando el registro es `unknown` o no existe.

### El flujo

Modo nuevo del asistente (`InstallerMode.updateBootloader`) con **cuatro pasos y
ninguno toca el disco**: pantalla propia → DFU → grabar → listo. Sin Permisos
(no hay nada privilegiado que pedir: `mks5lboot` corre sin contraseña, D-043),
sin Preparar el disco y sin Copiar archivos. **Cero diálogos de contraseña**, a
diferencia de una instalación desde cero, que llega a tres.

**Se flashea con `single: false`, a propósito.** `--single` borra el arranque de
Apple de la NOR; actualizar no puede destruir más de lo que ya estaba destruido
—en un iPod instalado con "Solo firmware" el de Apple ya no está, y en uno con
dual boot no hay ninguna razón para quitárselo ahora—. Al terminar se registra
el hash nuevo, que es lo que evita volver a ofrecerlo.

La pantalla responde las tres preguntas que cualquiera se haría antes de apretar
un botón que pide modo DFU: **qué es el arranque** (el programa que corre antes
del firmware, en un chip aparte), **por qué hace falta DFU** (ese chip no se
puede escribir de otra forma) y **qué NO se toca** (nada del disco: música,
fotos, listas y ajustes se quedan igual). Y una cuarta que evita una llamada de
soporte: **no es obligatorio** — el firmware nuevo funciona con el arranque
viejo; lo único que cambia es la pantalla de encendido. La oferta en el
Instalador va debajo de los botones y con estilo discreto por la misma razón.

`docs/guia-instalacion.md` gana la sección "4 bis. Actualizar el arranque" con
lo mismo, incluido el "no te pide tu contraseña ni una sola vez".

### Verificación

macOS: `swift build` + **735 pruebas en verde** (9 nuevas: la migración del
registro viejo, el hash como valor, y los seis casos de la regla) y
`scripts/build-app.sh` completo. Windows: `AuraStudio.Core` con **1 147
pruebas** (8 nuevas, los mismos casos).

Armar la captura encontró dos cosas que las pruebas no podían ver: la pantalla
final decía **"iPod restaurado"** (heredado del `switch` de dos ramas de
`DoneView`) y "Instalando Aura…" mientras se grababa el arranque. Las dos
corregidas — por eso la evidencia son las pantallas reales renderizadas, y no
una descripción de ellas.

**Lo que queda para la VM de Windows**: allá el registro de discos verificados
**no existe todavía** (ST-016 es solo de macOS), así que la regla está portada y
probada en Core pero nadie la llama: falta el almacén de hashes por disco, el
modo del asistente y la pantalla en WinUI.

Evidencia: `docs/capturas/ronda-caratulas/fase4-actualizar-arranque.png` — las
cuatro pantallas reales del flujo, renderizadas de las vistas de verdad.

### Addendum — la salida cuando el DFU no se detecta

Al escribir la lista de verificación en hardware apareció el agujero: el
instalador completo ofrece pausar los agentes AMP (D-041/D-044) **antes** de la
guía de DFU, y este flujo no lo hace, justamente porque eso pediría la
contraseña que la pantalla promete no pedir. En una Mac donde esos agentes
estorben, el usuario vería su iPod en DFU y la app esperando para siempre, y su
única salida sería cancelar y usar el instalador completo — que además formatea
o copia cosas que acá no hacen falta.

La respuesta no es elegir entre las dos: **el flujo arranca con cero
contraseñas, y solo si tras 20 segundos en la pantalla de DFU el iPod sigue sin
aparecer, esa misma pantalla ofrece "¿No aparece? Pausar los servicios de macOS
que pueden interferir (pedirá tu contraseña)"**. Reutiliza tal cual lo que ya
existe: `PendingAuthorization.pauseAMPAgents()` con su explicación previa,
`PrivilegedExecutor.pauseAMPAgents` y `AMPAgentsGuard`, que garantiza la
reactivación al salir del asistente y al cerrar la app.

Veinte segundos y no menos: la combinación de botones tarda doce, así que un
plazo más corto ofrecería la ayuda mientras el usuario todavía está apretando.
La regla es pura y tiene prueba (`BootloaderUpdate.shouldOfferServicePause`):
**antes del plazo la opción no existe**, con el iPod ya detectado tampoco, si ya
se pausaron una vez tampoco, y en el instalador completo nunca — ahí se ofrece
antes, y pedir la contraseña dos veces por lo mismo sería peor que no ofrecerla.

## Ronda de carátulas cuadradas — lista de verificación con el iPod real

Todo lo de ST-140…ST-143 está probado contra volúmenes y bibliotecas de prueba.
Lo que sigue **solo se puede comprobar con el aparato en la mano**, y es del
dueño. Está escrita para hacerse en este orden, porque cada punto deja al iPod
en el estado que necesita el siguiente.

### 1. Sincronizar una biblioteca migrada

1. Abrir Aura Studio con la biblioteca de siempre. **Al abrir** debe aparecer al
   pie la franja "Normalizando carátulas… N de M" con su botón **Cancelar**.
   Vale cancelarla y volver a abrir: tiene que retomar donde iba, sin repetir lo
   hecho (ST-141). Cuando termina, el resumen dice cuántas normalizó.
2. Mirar la sección Álbumes: las carátulas que eran 4:3 o 16:9 ahora se ven
   cuadradas y **sin deformar** (recortadas al centro, no estiradas). Los
   **pósters de video siguen siendo 3:4** — si alguno salió cuadrado, es un bug.
3. Conectar el iPod y sincronizar. Al terminar, con el volumen montado:

   ```
   sips -g pixelWidth -g pixelHeight "/Volumes/<iPod>/Music/<Artista>/<Álbum>/cover.jpg"
   sips -g pixelWidth -g pixelHeight "/Volumes/<iPod>/.rockbox/aura/artists/"*.jpg
   ```

   Esperado: **320×320** y **128×128**. (Una carátula cuyo lado corto ya era
   menor a 320 sale más chica: eso es correcto, nunca se agranda.)
4. **Sincronizar otra vez sin cambiar nada.** Ninguna de esas imágenes debe
   cambiar de fecha:

   ```
   ls -l "/Volumes/<iPod>/Music/<Artista>/<Álbum>/cover.jpg"
   ```

   Es el punto más importante de los cuatro: desde v18 el `mtime` de
   `cover.jpg` forma parte de la clave de caché del firmware, y reescribirla de
   más le tira su caché de carátulas en cada conexión (ST-142).
5. Desconectar y arrancar el iPod: las carátulas 4:3 y 16:9 deben verse bien
   **en lista, en cuadrícula, en Music Flow / Marea, en "Ahora suena" y de
   fondo** — que es donde estaba el glitch original.

### 2. Actualizar el arranque

Orden exacto de pantallas, y **cuántas veces pide la contraseña: 0**.

1. Instalador → debajo de los dos botones aparece **"Actualizar el arranque"**
   con la explicación de por qué (arranque más nuevo, o "no sabemos cuál
   tienes").
2. Pantalla **"Actualizar el arranque"**: qué es, por qué DFU, qué no se toca,
   y que no es obligatorio. Botón "Actualizar el arranque".
3. **"Entra a modo DFU"** (SELECT + MENU ~12 s). La app lo detecta sola.
4. **"Actualizando el arranque…"** → "Arranque enviado. Esperando a que el iPod
   confirme y reinicie…".
5. **"Arranque actualizado"**.

**Ningún diálogo de contraseña en ningún punto** — no se formatea, no se copia y
`mks5lboot` corre sin privilegios (D-043). Si aparece uno sin que lo hayas
pedido, es un bug.

La única excepción es voluntaria y hay que probarla también: **con el iPod en
DFU y la app sin detectarlo, a los ~20 segundos la pantalla ofrece "¿No aparece?
Pausar los servicios de macOS que pueden interferir"**. Antes de ese plazo la
opción NO debe existir. Si se usa, pide la contraseña una vez (con su
explicación previa, como todo lo privilegiado) y los servicios se reactivan
solos al salir del asistente.

Lo que hay que mirar además: que la **música y los ajustes sigan intactos**
(este flujo no escribe nada en el disco), que al reiniciar aparezca la
**pantalla de arranque nueva**, y que la oferta **ya no vuelva a aparecer** al
reconectar (el hash quedó registrado).

**Si el iPod entra a DFU y la app no lo detecta**: esperar los ~20 segundos y
usar la opción de pausar los servicios de macOS que aparece ahí mismo. Vale la
pena reportarlo si pasa: es la única causa conocida de que un iPod que sí está
en DFU no aparezca (D-041/D-044).

### 3. Instalación desde cero

Hasta **3 diálogos de contraseña**, y cada uno **con su pantalla explicativa
antes** (nunca un diálogo de macOS a secas):

1. **Formatear el disco** — solo si el disco no está en FAT32.
2. **Pausar los servicios de macOS** (AMPDevicesAgent / AMPDeviceDiscoveryAgent),
   justo antes de la guía de DFU.
3. **Reanudar esos servicios** al terminar el asistente.

La caché de autorización de macOS puede hacer que el segundo y el tercero no
vuelvan a preguntar. Lo que hay que verificar es el **orden** y que **ninguno
llegue sin su explicación previa** (`PrivilegedActionSheet`), que es la promesa
que hace `PermissionsView`.

### 4. Con un firmware anterior a v18

Si se sincroniza contra un firmware viejo, las carátulas nuevas **no se ven
hasta que ese firmware purgue su caché**: no tiene `/.aura/art/format.txt` ni la
clave con `mtime`. No es un bug de Studio — es la razón por la que los tres
firmwares y este Studio salen en el mismo ciclo de release (ST-142).

## Procedimiento del pin de firmwares (Fase 5 — NO ejecutado)

Escrito para que el día que el dueño lo indique sea mecánico. **Nada de esto
está hecho todavía**: `FIRMWARE_VERSION` sigue apuntando a Aura v0.4.4-beta,
Metro v0.6.4 y moonlit v0.1.6.

1. **Esperar los tres Releases** publicados y verificados en hardware. Sin los
   tres no se pinea ninguno: las carátulas cuadradas necesitan el firmware v18
   del otro lado para verse (§4 de arriba).
2. **`FIRMWARE_VERSION`**: subir `tag=`, `metro.tag=` y `moonlit.tag=`. Los 12
   hashes (4 por familia) **no se escriben a mano**: los produce
   `scripts/fetch-firmware.sh` verificando contra el `checksums.txt` del propio
   Release.
3. **`scripts/fetch-firmware.sh`** (las tres familias) y confirmar que
   `Vendor/firmware-dist/` queda con los artefactos de los tres tags nuevos.
4. **`Generated/AuraPalette.swift`**: se reemplaza **entero** con el que trae el
   Release nuevo (`design-system/generate.py --swift-out`, ejecutado en el repo
   del firmware). Esta ronda agrega el token `tile_placeholder` — si la paleta
   nueva no lo trae, el pin está incompleto. **Nunca se edita a mano.**
5. **`scripts/build-app.sh`** completo, y revisar que la pantalla de
   **Licencias** cite los tres tags nuevos y el `MODIFICATIONS.md` correcto
   (cumplimiento GPL §3, contrato §B).
6. **Verificar el hash del arranque**: con el pin nuevo, un iPod instalado con
   el pin anterior debe empezar a ver la oferta de "Actualizar el arranque"
   (ST-143). Si no aparece, el `bootloader-ipod6g.ipod` del Release no cambió y
   hay que confirmar por qué.
7. **ST-144** con la tabla de pins (familia → tag → 4 hashes) y el resultado de
   la verificación en hardware.

## ST-144 — Pin de los tres firmwares: v0.4.4→v0.4.5-beta, v0.6.4→v0.7.0, v0.1.6→v0.2.0

Fase 5 de `PLAN-studio-caratulas-cuadradas.md`, ejecutada tras confirmación
directa del dueño (no solo de la sesión supervisora) de que los tres Releases
existen. Es la primera vez que este Studio distribuye el contrato v18: carátulas
cuadradas de punta a punta (ST-140…ST-142) y "Actualizar el arranque" (ST-143).

### Tabla de pins

| Familia | Tag anterior | Tag nuevo | Repositorio |
|---|---|---|---|
| Aura | `v0.4.4-beta` | `v0.4.5-beta` | `Ricolinos/Aura-Firmware` |
| Metro | `v0.6.4` | `v0.7.0` | `Ricolinos/Metro-Aura` |
| moonlit | `v0.1.6` | `v0.2.0` | `Ricolinos/moonlit-aura` |

Los 12 hashes (4 por familia: `rockbox.ipod`, `rockbox.zip`, `mks5lboot`,
`bootloader-ipod6g.ipod`) están en `FIRMWARE_VERSION`, y **no se escribieron a
mano**: se leyeron del `checksums.txt` real que trajo cada `gh release
download` de `scripts/fetch-firmware.sh` — el mismo mecanismo que el script usa
para verificar antes de dejar los archivos utilizables. (Nota de proceso: el
primer intento sí los copió a mano desde el JSON de `gh release view`; se
descartó y se rehizo desde `checksums.txt` para no romper la regla, aunque el
valor final resultó ser byte a byte el mismo — es lo esperable, ambos son el
mismo hash calculado por GitHub.)

### `AuraPalette.swift`

Reemplazado **entero** con el que trae el Release de Aura (nunca editado a
mano). Trae el token nuevo de esta ronda:

```swift
let tilePlaceholder: Color
```

presente en las dos paletas (clara: `(0.8196, 0.8196, 0.8392)`; oscura:
`(0.2275, 0.2275, 0.2353)`). **Sin cablear todavía en la UI** — ningún código
de `Sources/AuraStudio` lo referencia fuera de `Generated/`. No era parte del
encargo de esta ronda (carátulas cuadradas + arranque); queda anotado para que
no se pierda como trabajo pendiente, no como un defecto de este pin.

### Instalación y verificación

`scripts/build-app.sh` completo: `fetch-firmware.sh` (las tres familias, los
tres `checksums.txt` verificados) → `xcodegen generate` (sin diff en
`project.pbxproj`: no se tocó `project.yml`) → `xcodebuild Release` → bundle
verificado (firma ad-hoc válida, `mks5lboot` con bit de ejecución en las tres
familias) → **instalado en `/Applications/AuraStudio.app`**, reemplazando lo
que hubiera (no había nada — primera instalación de esta Mac en esta sesión).
Los tres `firmware-version.txt` dentro del bundle instalado se verificaron por
archivo: `v0.4.5-beta` / `v0.7.0` / `v0.2.0`.

**La app se abrió con un iPod real conectado** ("iPod de ricolinos"), lo que
dio una confirmación que ninguna prueba automatizada podía dar: la pantalla de
Instalador mostró **"Actualizar el arranque"** (ST-143) para ese disco —
prueba en vivo de que la regla `BootloaderUpdate` compara correctamente el hash
nuevo contra el registro anterior. No se llegó a la pantalla de Licencias por
esta vía: con un dispositivo real conectado, seguir haciendo clics
automatizados (Accessibility/`osascript`) cerca de botones reales como
"Reinstalar Aura" / "Restaurar iPod original" / "Actualizar el arranque" es un
riesgo que no vale la pena correr por una captura — **ninguno de esos tres se
tocó**. La pantalla de Licencias se verificó por el camino que no puede fallar
en silencio: `BundledArtifacts.releaseTag` lee exactamente los tres
`firmware-version.txt` que ya se comprobaron archivo por archivo, y el código
que los muestra (`LicensesView.swift:75-96`) no tiene ninguna lógica extra que
pudiera desviarse de eso.

### DMG

`scripts/package-dmg.sh` (WIP ajeno, sin commitear — sigue sin trackear a
propósito) funcionó de punta a punta sin modificarlo: usa `build-app.sh --dest`
a una carpeta temporal, así que no tocó la instalación real en `/Applications`.

- **Archivo**: `dist/AuraStudio-0.1.2-20260904.dmg`
- **Tamaño**: 41 MB
- **SHA-256**: `a4c65ebfeeda390f40d2d0b2798f3d6c9d335ec0d6a9ebf6941af82670607517`
- **Arquitectura**: universal (`x86_64 arm64`)
- **macOS mínimo**: 14.4
- **Firmware embebido**: `v0.4.5-beta`

Verificado montando el DMG (`hdiutil attach -nobrowse`), confirmando la firma
del bundle adentro (`codesign -vv`, válida) y **abriendo la app directo desde
el volumen montado** — abrió, se cerró limpio, se desmontó sin error. No se
navegó su UI por la misma razón que arriba (dispositivo real conectado).

`dist/` sigue gitignorado; el DMG no se commitea, solo se reporta su ruta.

### Verificación en hardware pendiente (dueño)

Esta entrada deja el pin y la instalación hechos; la lista de verificación
completa con el iPod real —sync con biblioteca migrada, "Actualizar el
arranque" de punta a punta, instalación desde cero— es la que ya quedó escrita
más arriba en "Ronda de carátulas cuadradas — lista de verificación con el
iPod real". Lo único que esta sesión pudo confirmar en vivo fue que la oferta
de "Actualizar el arranque" aparece correctamente; el resto de esa lista sigue
pendiente de que el dueño la corra con el iPod en la mano.

**Verificado en hardware por el dueño el 2026-09-04: instalación,
actualización del arranque y sync correctos.**

## ST-146 — La hora se sincroniza en cada conexión, cada sync y cada cambio de familia — para CUALQUIER familia

Ronda "ajustes 2" (plan maestro §B). Hasta hoy `ClockSyncWriter` corría en dos
momentos (conectar con evidencia de arranque, e instalar/actualizar); el
encargo amplía a un tercero — **terminar cada sincronización de biblioteca,
incluida una que no copió ni un archivo** — y, más importante, aclara que
"cualquier familia corriendo" ya no era una aspiración: **ya lo era**.

### Lo que ya estaba bien, y lo que faltaba de verdad

`IPodMonitor.syncClockIfNeeded` (macOS) y `DeviceSessionService.SyncClockIfConnected`
(Windows) disparan con `supportsAuraContract`/`SupportsAuraContract` — una
propiedad que, pese a su nombre histórico (`Firmware.aura`/`InstalledFirmwareKind.Aura`
en el enum que clasifica archivos), es **de capacidad, no de identidad**
(ST-046): da `true` para Metro y moonlit exactamente igual que para Aura,
porque las tres escriben `.rockbox/aura/aura.cfg` y hablan el mismo §D del
contrato. El comentario de `IPodMonitor` decía "en cada conexión con Aura
corriendo" — texto viejo, código ya correcto desde ST-046. Se corrigió el
comentario y se agregó la prueba que faltaba (`Metro y moonlit también
satisfacen supportsAuraContract`, en las dos plataformas) para que ese hecho
quede fijado, no solo inferido.

Lo que sí faltaba, en las dos plataformas:

1. **Al terminar cada sincronización de biblioteca.** `LibrarySync.sync()`
   (macOS) y `LibrarySyncEngine.Apply` (Windows) nunca llamaban a
   `ClockSyncWriter`. Se agrega justo antes de escribir el marcador de
   `sync-pending.json` — a propósito: si algo de lo que sigue fallara, la hora
   ya quedó puesta — y **sin condicionarlo a que el sync haya copiado algo**:
   un sync vacío también sincroniza la hora, que es exactamente el caso que
   el maestro pedía cubrir explícitamente.
2. **Al cambiar de familia.** `FirmwareSwitcher.switchActiveFirmware`
   (macOS) / `FirmwareSwitcher.SwitchActiveFirmware` (Windows) tampoco lo
   hacían. Un árbol dormido puede llevar semanas dormido — su reloj queda tan
   atrasado como el último apagado de esa familia —, así que el cambio deja
   la hora puesta en el árbol **entrante** (ya renombrado a `/.rockbox/`
   cuando corre la escritura), sin esperar a que el usuario desconecte y
   reconecte el iPod.

### Verificación

macOS: `swift build` + **745 pruebas en verde** (10 nuevas: Metro/moonlit
satisfacen `supportsAuraContract`; el cambio de familia deja la hora en el
árbol entrante conservando sus demás claves; un sync sin cambios de medios,
uno con cambios, y que la hora escrita coincide con el reloj real de la
máquina) y `scripts/build-app.sh` completo. Windows: `AuraStudio.Core` con
**1 152 pruebas** (5 nuevas, mismos casos); las 32 que fallan en una Mac son
las de siempre.

**Verificación real pedida por el plan** (no solo con datos sintéticos): una
sincronización de verdad (`LibrarySync.sync`) contra un volumen de prueba cuyo
`aura.cfg` declara `firmware_family: metro` — no Aura —, primero sin ningún
cambio de medios que copiar. El archivo quedó con `rtc_sync_year/month/day/hour/min/sec`
y `tz_local_quarters` puestos, coincidiendo con la hora real del Mac en el
momento de correrlo, y conservando `firmware_family`/`accent` tal como
estaban. Evidencia: `docs/capturas/ajustes-2/fase2-hora-en-cada-sync.png`.

**Lo que queda para la VM de Windows**: el punto (3) del maestro —"al
instalar/actualizar"— vive del lado de `AuraStudio.App` (el `InstallerViewModel`
de WinUI), que no compila en macOS. La llamada de conexión
(`DeviceSessionService.SyncClockIfConnected`) ya estaba desde antes de esta
ronda; falta agregar la de instalación/actualización, simétrica a como
`InstallerViewModel.swift:1214` ya lo hace en macOS.

## ST-147 — `/.aura/settings.cfg` (contrato v19): protegido por construcción, ahora también por prueba

Ronda "ajustes 2". El contrato v19 agrega `/.aura/settings.cfg` (ajustes
compartidos entre Aura, Metro y moonlit — bloqueo, brillo, idioma, etc.,
§A del maestro) como cuarto archivo/directorio de propiedad exclusiva del
firmware bajo `/.aura/`, junto a `tagcache/`, `thumbs/` y `art/`
(ST-069/ST-073).

### El hallazgo: no había nada que arreglar, y eso también hay que probarlo

Igual que con la hora en ST-146, la primera pregunta fue si algún flujo de
Studio ya lo tocaba sin darse cuenta. Búsqueda exhaustiva de toda referencia
a `.aura/` en el código de Studio (macOS: tres archivos en total —
`FirmwareSwitcher.swift`, `LibrarySync.swift`, `SyncMarker.swift`; Windows:
la misma huella en `Installer/FirmwareSwitcher.cs` y
`Library/LibrarySyncEngine.cs`): **ningún camino enumera `/.aura/` de forma
amplia**. Cada operación que borra o mueve algo nombra explícitamente sus
archivos:

- `clearFirmwareDatabases`/`ClearFirmwareDatabases` solo borra los nombres
  fijos de `tagcacheDatabaseFileNames`/`DatabaseFileNames` (`database_*.tcd`,
  `db_stamp.txt`) en directorios concretos — nunca un `.none`/`.art` de
  `/.aura/art/`, nunca `settings.cfg`.
- `mirroredContractEntries`/`MirroredContractEntries` (lo que viaja al
  espejar/sembrar entre árboles dormidos) son todas rutas bajo
  `<árbol>/aura/` (por familia), nunca bajo el `/.aura/` compartido de la
  raíz del volumen.
- La actualización selectiva del instalador (`applySelectiveUpdate` /
  `InstallManifestDelta`) ya traía, desde ST-058, un guardia explícito:
  `Delta()` solo propone borrar rutas que empiecen con `.rockbox/`
  (`toDelete.filter { $0.hasPrefix(".rockbox/") }` / `path.StartsWith(TreePrefix)`)
  — un manifiesto corrupto o ajeno no puede proponer borrar nada fuera del
  árbol del firmware, y eso incluye cualquier cosa bajo `/.aura/` por
  definición.
- `install_manifest.cfg` describe únicamente el contenido de `rockbox.zip`
  (`entriesFromZip`/`ReadsPathSizeAndCrcFromTheZip`), que nunca empaqueta
  nada de `/.aura/` — así que no hay forma de que lo liste.

**La protección real no es una excepción añadida a mano para
`settings.cfg` — es que el código nunca tuvo la clase de operación que
pudiera amenazarlo.** Lo que agrega esta entrada es la constante
(`LibrarySync.sharedSettingsRelativePath` / `FirmwareSwitcher.SharedSettingsRelativePath`)
para que quede nombrado igual que sus tres hermanos, y las pruebas que
fijan el hecho contra cada flujo real: cambiar de familia, reparar un
arranque en frío, sembrar y espejar archivos del contrato, sincronizar
(incluido un sync vacío) y forzar la reconstrucción de la base — más dos
pruebas dedicadas a `InstallManifest.Delta`/`Delta()` con el nombre real
del archivo, sumadas a la genérica que ya existía desde ST-058.

**Restaurar queda fuera a propósito**: el flujo de "Restaurar iPod
original" termina en un formateo real de la partición (`RestoreHandoffView`,
D-184) — eso borra `/.aura/` entero junto con todo lo demás, y es
exactamente lo que el usuario pidió al elegir esa opción. La protección de
esta entrada es sobre las operaciones que dejan el volumen montado e
intacto; un formateo deliberado no es un bug que evitar.

### Verificación

macOS: `swift build` + **753 pruebas en verde** (8 nuevas: seis flujos
reales protegidos, una prueba de que `settings.cfg` no aparece en ninguna
lista de limpieza conocida, y una de `InstallManifest.delta` nombrada) y
`scripts/build-app.sh` completo. Windows: `AuraStudio.Core` con **1 160
pruebas** (8 nuevas, los mismos siete casos más el de `Delta`); las 32 que
fallan en una Mac son las de siempre — confirmado diff línea por línea
contra la lista base de la ronda anterior, sin ninguna nueva.

## ST-145 — Contrato v19 copiado byte a byte

Fase 1 de la ronda "ajustes 2". `CONTRATO-firmware-studio.md` reemplazado
entero por la copia canónica de `Aura-Firmware` (commit `f95a5fff`, ya en su
`main`), verificado con `cmp` (sin diferencias) y hash SHA-256 idéntico en
los dos repos.

Se ejecutó al final a propósito, no al principio: el plan hijo lo pedía así
("si aún no existe al empezar, arrancar por la Fase 2 y volver") — al
arrancar esta sesión el commit del contrato todavía no existía en
`Aura-Firmware`, así que las Fases 2 y 3 se hicieron primero, contra la
especificación del plan maestro (que sí estaba disponible desde el
principio), y esta entrada solo confirma que el texto que la sesión de
`Aura-Firmware` terminó escribiendo coincide con lo que ST-146/ST-147 ya
implementaban: hora en cualquier familia corriendo (no solo Aura), al
terminar cada sync, y `/.aura/settings.cfg` con el mismo trato que
`/.aura/art`.

Lo nuevo que trae la v19 y que no tocaba ningún código de esta ronda: la fila
de `THIRD-PARTY-NOTICES.txt` en §A (documentación de una fila que faltaba en
la tabla, sin asset nuevo — todo Release real ya lo publicaba) y la tabla de
compatibilidad de §E, que no cambia comportamiento del lado Studio.

## Ronda "ajustes 2" — lista de verificación con el iPod real

Lo de ST-146/ST-147 está probado contra volúmenes de prueba. Lo que sigue es
del dueño, con el aparato en la mano.

### 1. Hora tras sincronizar, con cada familia

Repetir con Aura, Metro y moonlit instalados (uno a la vez, o vía "Cambiar
sistema" entre sincronizaciones):

1. Desconfigurar la hora del iPod a propósito (Ajustes › Fecha y hora, o
   dejarlo apagado varios días).
2. Conectar y sincronizar desde Aura Studio — **sin que la biblioteca tenga
   nada nuevo que copiar** (repetir el mismo sync dos veces si hace falta,
   para probar justo el caso "sync vacío").
3. Desconectar y entrar a Ajustes › Fecha y hora (o Acerca de) en el iPod:
   la hora debe coincidir con la del Mac, sin haber tocado nada a mano.
4. Repetir cambiando de familia (Ajustes › Cambiar sistema) sin sincronizar
   de por medio: el árbol que despierta también debe traer la hora puesta,
   no la de la última vez que corrió.

### 2. `/.aura/settings.cfg` sobrevive a todo menos a Restaurar

1. Con el archivo ya escrito por el firmware (cualquier ajuste compartido
   cambiado desde el propio iPod), hacer un ciclo completo desde Studio:
   sincronizar, cambiar de familia y volver, forzar "Actualizar biblioteca"
   (reconstrucción de la base). En cada paso, verificar en el volumen
   montado que `/.aura/settings.cfg` sigue teniendo el mismo contenido
   (`cat` antes y después).
2. Confirmar que "Restaurar iPod original" SÍ se lleva el archivo por
   delante (formatea la partición) — es el comportamiento esperado, no un
   bug: si sobreviviera a un restaurar, algo estaría mal.

## ST-148 — Pin de la ronda "ajustes 2": v0.4.5-beta→v0.4.6-beta, v0.7.0→v0.7.1, v0.2.0→v0.2.1

Segundo pin de los tres firmwares, mismo procedimiento que ST-144, tras los
releases de la ronda "ajustes 2" (ajustes compartidos, hora en cada sync,
visor de fotos, idiomas).

### Tabla de pins

| Familia | Tag anterior | Tag nuevo | Publicado |
|---|---|---|---|
| Aura | `v0.4.5-beta` | `v0.4.6-beta` | 2026-09-05T02:59Z |
| Metro | `v0.7.0` | `v0.7.1` | 2026-09-05T02:54Z |
| moonlit | `v0.2.0` | `v0.2.1` | 2026-09-05T02:58Z |

Los 12 hashes de `FIRMWARE_VERSION` se regeneraron leyendo el `checksums.txt`
real que trajo cada `gh release download` — **nunca a mano** (la regla que
ST-144 dejó escrita tras equivocarse en el primer intento; esta vez se siguió
desde el principio).

### Dos cosas que este pin NO cambió, y que conviene no confundir con un error

1. **`AuraPalette.swift` es byte-idéntico al anterior.** El Release de Aura lo
   sigue publicando, se reemplazó entero como manda la regla (nunca se edita a
   mano), y el `diff` dio vacío: v0.4.6-beta no tocó ningún token de diseño.
   `git status` no lo reporta como modificado y eso es correcto, no un fetch
   incompleto.
2. **El `bootloader-ipod6g.ipod` de Aura tampoco cambió** (`e4b8b922…`, el
   mismo de v0.4.5-beta), ni `mks5lboot` de ninguna de las tres. Los que **sí**
   cambiaron son los bootloaders de Metro (`a1f47beb…`) y moonlit
   (`252e90c0…`). Consecuencia directa en ST-143: a un iPod con **Aura** no se
   le va a ofrecer "Actualizar el arranque" con este pin —su hash registrado
   sigue coincidiendo—, y a uno con Metro o moonlit **sí**. Es el
   comportamiento correcto de la regla, no un fallo de detección.

### Instalación y verificación

`scripts/build-app.sh` corrió dos veces a propósito: primero contra una carpeta
temporal, para validar que todo compilaba y que el bundle traía los tres tags
**antes** de tocar la app instalada; y recién después, con el visto bueno
explícito del dueño, sin `--dest`, para reemplazar `/Applications/AuraStudio.app`.
Los tres marcadores del bundle instalado, leídos archivo por archivo:
`v0.4.6-beta` / `v0.7.1` / `v0.2.1`, con firma ad-hoc válida y los tres
`mks5lboot` con bit de ejecución. La app se abrió y se cerró limpio; **no se
navegó su interfaz**, por la misma razón que en ST-144 (con un iPod real
conectado, un clic automatizado cerca de "Reinstalar"/"Restaurar" no vale el
riesgo por una captura).

`swift test`: 753 pruebas en verde tras el pin.

### DMG

`scripts/package-dmg.sh` sin modificar:

- **Archivo**: `dist/AuraStudio-0.1.2-20260904.dmg`
- **Tamaño**: 41 MB (43 206 207 bytes)
- **SHA-256**: `5934b7a6746b2dc8e2abac6dbfff7f33d41224f4e9b246fae55d423fa16f417b`
- **Arquitectura**: universal (`x86_64 arm64`) · **macOS mínimo**: 14.4
- **Firmware embebido**: `v0.4.6-beta`

Verificado montándolo: el `AuraStudio.app` de adentro trae `v0.4.6-beta`, tiene
firma válida, abre y cierra bien, y el volumen desmonta sin error.

**El DMG de ST-144 ya no existe.** El script nombra el archivo con la fecha
local (`AuraStudio-<versión>-<AAAAMMDD>.dmg`) y hace `rm -f` antes de crear:
como los dos pins cayeron el mismo día local (2026-09-04, el segundo a las
21:06), el segundo sobrescribió al primero. El SHA-256 que ST-144 anotó
(`a4c65ebf…`) ya no corresponde a ningún archivo en `dist/`. No se perdió nada
reproducible —ese DMG se vuelve a generar con `git checkout` del pin anterior y
`package-dmg.sh`—, pero queda dicho para que nadie lo busque.

## ST-150 — Publicación en repos públicos: verificación de actualizaciones sin token, texto obsoleto de "repo privado", y dos User-Agent que seguían apuntando al monorepo archivado

Primer bloque de `PLAN-publicacion-repos-publicos.md` §C que no depende del
pin corregido (ST-149): §C.2 (verificar actualizaciones desde los repos
públicos) y la mitad de §C.1 (versión 0.2.0, sin commitear todavía — ver
más abajo por qué).

### Los tres repos del firmware ya funcionan sin token

`GitHubReleaseChecker.fetchReleases`/`FetchReleasesAsync` nunca necesitaron
cambiar: desde ST-074 arman la petición con o sin `Authorization` según
haya token guardado, y GitHub responde igual a un repo público con o sin
esa cabecera. Confirmado con dos pruebas nuevas por plataforma
(`testWithoutATokenNoAuthorizationHeaderTravelsForAnyFamily` /
`testEachFamilyQueriesItsOwnPublicRepository` en Swift,
`WithoutATokenNoAuthorizationHeaderTravels` / `EachFamilyQueriesItsOwnPublicRepository`
en `GitHubReleaseCheckerTests.cs`, nuevo) y, del lado macOS, una prueba
**en vivo** contra la API real de GitHub sin ningún token
(`GitHubReleaseCheckerLiveTests.testAllThreePublicReposAnswerWithoutAToken`,
`XCTSkip` si no hay red) — pasó contra los tres repos reales en 1.041 s.
Del lado Windows no se agregó el equivalente en vivo: xUnit v2 puro no trae
mecanismo de "saltar sin red" (no hay `Xunit.SkippableFact` en el proyecto)
y agregar una dependencia nueva para una sola prueba no valía la pena —el
código es casi idéntico al de Swift, ya probado en vivo ahí, y las dos
pruebas mockeadas ya fijan la forma exacta de la petición. Queda dicho en un
comentario en el propio archivo de pruebas, no es un hueco silencioso.

### Texto de UI y comentarios que seguían diciendo "repositorio privado"

Encontrados por búsqueda exhaustiva de "privad" en ambas plataformas, seis
archivos: `GitHubTokenSettingsView.swift` (encabezado y las tres cadenas de
cara al usuario, más el mensaje de error que tenía una rama entera para
"repositorio privado"), `LicensesView.swift` (una línea que ya no aplicaba),
`GitHubToken.swift` y `GitHubReleaseChecker.swift` (comentarios de
documentación) del lado macOS; `CredentialStore.cs`
(`ApiKeyService.GitHub`: título, descripción e instrucciones) y
`GitHubReleaseChecker.cs` (comentario) del lado Windows. Mensaje nuevo en
los dos: el token es opcional, solo sube el límite de la API de GitHub
(60/hora sin token → 5000/hora con uno), e instalar el firmware nunca
depende de esto porque los binarios viajan embebidos en la app.

### `AuraUpdateChecker` no revisa la propia app — el plan asumía que sí

§C.2 pedía verificar que `AuraUpdateChecker` "apunta al repo público
`Ricolinos/Aura-Studio` para la propia app". Búsqueda exhaustiva de
`AuraUpdateChecker` en las dos plataformas: **no existe ningún mecanismo que
revise actualizaciones de Aura Studio misma** — todo lo que hay son avisos
de firmware nuevo (Aura/Metro/moonlit), nunca de la app. Es una
inexactitud del plan, no un bug: no se construyó nada nuevo para cerrar
esta brecha porque un auto-chequeo de la app (nueva llamada a GitHub, nueva
UI, nueva lógica de "hay una versión más reciente de Aura Studio, bájala
tú mismo") es una funcionalidad completa que el plan no pidió explícitamente
y que amplía el alcance de esta ronda — queda para que el dueño decida si
la quiere y cuándo.

### Dos User-Agent que seguían citando el monorepo archivado

Al revisar todo lo que sale hacia servicios externos, cuatro constantes
(`MusicBrainzClient.userAgent` y `LRCLIBClient.clientIdentifier`/
`clientIdentifier` en las dos plataformas) traían
`AuraStudio/0.1.0 (https://github.com/Ricolinos/Aura-Proyect)` — el
monorepo que se archivó al separar este repo (ver encabezado de
`MEMORY.md`). No es cosmético: es el identificador que estas dos APIs
externas reciben en cada petición, y apuntaba a un repo que ya no es el
lugar correcto para que alguien reporte un problema. Las cuatro se
actualizaron a `AuraStudio/0.2.0 (https://github.com/Ricolinos/Aura-Studio)`
en el mismo cambio que el bump de versión, para no dejar la versión vieja
citada en un identificador de red.

### Versión 0.2.0 — bump hecho, **sin commitear**

`project.yml` (`CFBundleShortVersionString`, `MARKETING_VERSION`),
`AuraStudio.iss` (`AppVersion`, que estaba en `0.1.0` — desalineado incluso
antes de este bump) y, nuevo, `<Version>0.2.0</Version>` agregado a
`AuraStudio.App.csproj`: no existía ninguna declaración de versión ahí, así
que `SettingsViewModel.AppVersion` (que lee
`Assembly.GetExecutingAssembly().GetName().Version`) mostraba el default del
SDK (`1.0.0.0`), sin relación con la versión real del producto. `swift build`
y `dotnet build` de `AuraStudio.Core` en verde tras el cambio; `swift test`
756/756 (1 skip, la prueba en vivo por falta de red en este entorno);
`dotnet test` de `AuraStudio.Core` 1134/1166 (las mismas 32 fallas
preexistentes de `LibraryIngestTests`, sin relación con este cambio).

Todo esto queda **sin commitear a propósito**: la instrucción confirmada del
dueño es que el bump de versión y el README en inglés se commitean juntos,
en un solo commit, junto con ST-149 (el pin con los tags corregidos de
Metro/moonlit) — para que el release v0.2.0 salga de un commit limpio en
vez de dos.

## ST-149 — Pin corregido: v0.7.1→v0.7.2 (Metro), v0.2.1→v0.2.2 (moonlit); Aura sin cambio

Reemplaza el pin de ST-148, que nunca se llegó a empujar (`git reset --soft
HEAD~1` sobre `cb9799f`, sus cambios volvieron al índice) por el bug de
truncado de oraciones largas en ruso, reportado antes de hacer push — ver
la entrada de ST-148 arriba, que documenta el build/instalación/DMG de esa
versión con el bug **ya corregidos por este pin**, no vigentes.

| Firmware | Antes | Ahora |
|---|---|---|
| Aura | `v0.4.6-beta` | `v0.4.6-beta` (sin cambio — Aura no republicó) |
| Metro | `v0.7.1` | `v0.7.2` |
| moonlit | `v0.2.1` | `v0.2.2` |

Los 12 hashes se regeneraron de la forma de siempre: `scripts/fetch-firmware.sh`
descargó las tres familias y verificó cada `checksums.txt` contra el propio
Release antes de que el hash tocara `FIRMWARE_VERSION` (nunca a mano). Los
cuatro de Aura quedaron idénticos a ST-148 (tag sin cambio, esperado).
`AuraPalette.swift`: `diff` vacío contra el ya presente, también esperado.

**Lo que sí cambió, y confirma el aviso de la sesión de `Aura-Firmware`**:
en Metro y moonlit cambiaron `rockbox.ipod`, `rockbox.zip` y
`bootloader-ipod6g.ipod` — el nuevo bootloader de arranque, con
`BOOT_VERSION` fijo de ahora en más según el aviso recibido — pero **no**
`mks5lboot` en ninguna de las dos (la herramienta de DFU no cambió).
Consecuencia en ST-143: a un iPod con Metro o moonlit instalado con el pin
anterior se le va a volver a ofrecer "Actualizar el arranque" con este pin
(el hash registrado ya no coincide); es el comportamiento correcto, no un
efecto secundario.

### Instalación y verificación

`scripts/build-app.sh` corrió dos veces: primero contra `--dest` temporal
para confirmar que compilaba y traía los tres tags correctos antes de
tocar nada instalado, y después sin `--dest`, reemplazando
`/Applications/AuraStudio.app` de ST-148. Verificado archivo por archivo en
el bundle instalado: `CFBundleShortVersionString` = `0.2.0` (ST-150), firma
ad-hoc válida (`codesign -dv`), los tres `mks5lboot` (raíz, `metro/`,
`moonlit/`) con bit de ejecución. **No se navegó la interfaz** — la app se
verificó por inspección de archivos y `codesign`, nunca haciendo clic cerca
de "Reinstalar"/"Restaurar"/"Actualizar el arranque", misma razón que
ST-144/ST-148.

`swift build` y `swift test`: 756/756 en verde (esta vez sin ningún test
saltado — había red disponible para la prueba en vivo de ST-150).

### DMG

`scripts/package-dmg.sh` sin modificar, corrido después del build de
`/Applications` (recompila Release aparte para el propio DMG, mismo
código fuente):

- **Archivo**: `dist/AuraStudio-0.2.0-20260904.dmg`
- **Tamaño**: 41 MB
- **SHA-256**: `d64b89a6443797b588f615d0ff877a8cf7170a0bcd86d6a59869741a2760b745`
  (verificado de forma independiente con `shasum -a 256`, coincide con lo
  que reportó el script)
- **Arquitectura**: universal (`x86_64 arm64`) · **macOS mínimo**: 14.4
- **Firmware embebido**: Aura `v0.4.6-beta` / Metro `v0.7.2` / moonlit `v0.2.2`

El nombre del asset del release `v0.2.0` (§C.4 del plan de publicación) es
`AuraStudio-0.2.0.dmg`, sin el sufijo de fecha que pone el script — se
renombra una copia al momento de crear el release en GitHub, no este
archivo en `dist/` (que sigue el patrón de siempre, `git status` no lo ve:
`dist/` está en `.gitignore`).

### Qué falta para el release v0.2.0

Este commit deja listos el pin, la versión y el README. Según el orden de
§C.5 del plan de publicación, faltan: (b) ya hecho por este mismo commit;
(c) push a `origin/main`; (d) la VM de Windows compila
`AuraStudioSetup-0.2.0-x64.exe` / `-arm64.exe` desde este commit exacto
(prompt ya redactado en el plan); (e) el DMG de arriba, ya generado desde
este mismo commit; (f) `gh release create v0.2.0` con los tres archivos.
El release `v0.1.2` existente no se toca — decisión del dueño, no de esta
sesión.

Este commit reúne, a propósito, tres unidades de trabajo que el dueño pidió
como una sola entrega: este pin (ST-149), la verificación de actualizaciones
sin token y el README en inglés (ST-150), y el bump de versión a 0.2.0 que
ST-150 ya dejó hecho. Un solo commit, para que el release `v0.2.0` en
`Ricolinos/Aura-Studio` salga de un punto limpio del historial.

## ST-151 — La app se congelaba sin ventana si el iPod ya estaba conectado al abrirla

Encontrado con un iPod real conectado, tratando de tomar capturas para el
README (ST-150) sobre la build recién instalada de ST-149. Reproducido
**3 de 3 veces**: al abrir Aura Studio con el iPod ya conectado, la app
nunca mostraba ninguna ventana — quedaba corriendo (0% CPU, sin colgarse
de forma visible) pero completamente inerte, sin ningún indicio en pantalla
de qué pasaba ni por qué.

### Diagnóstico

`sample <pid>` (lee la pila de un proceso en ejecución, sin tocar nada) lo
dejó exacto las tres veces:

```
DispatchQueue_1: com.apple.main-thread
  IPodMonitor.handleDiskChange(_:)
    AuraDeviceProbe.probe(diskInfo:fileManager:)
      FirmwareCapabilities.declaredFamily(volumeRoot:fileManager:)
        String.init(contentsOf:encoding:) → ... → open() [bloqueado]
```

El hilo principal quedaba esperando indefinidamente una syscall `open()`
sobre un archivo del iPod (`.rockbox/aura/aura.cfg`). Leer el mismo archivo
desde la Terminal, al mismo tiempo, respondía instantáneo — el disco no
estaba colgado. Confirmado con el dueño presente frente a la pantalla:
**había un diálogo nativo de macOS pendiente, pidiendo el permiso de
"volumen removible"**, que la app nunca llegó a mostrar en pantalla —no
tenía ninguna ventana propia donde adjuntarlo, porque esa ventana nunca
termina de aparecer mientras el hilo principal esté bloqueado esperando
justo esa respuesta. Un candado circular: sin ventana no hay dónde mostrar
el diálogo, y sin que alguien apruebe el diálogo a ciegas (sin verlo) el
hilo principal nunca se libera para crear la ventana.

**Por qué apareció justo ahora y no antes**: la app está firmada ad-hoc
(`CODE_SIGN_IDENTITY "-"`, sin certificado Developer ID — ver
`scripts/package-dmg.sh`), y macOS liga el permiso de TCC a un hash de esa
firma. Cada `build-app.sh` produce una firma ad-hoc distinta, así que
**cada reinstalación pierde el permiso ya concedido** y macOS vuelve a
pedirlo — con el iPod ya conectado en ese momento (como pasa siempre en
esta ronda de pines: se reinstala y se verifica con el mismo iPod), el
primer sondeo del disco dispara el permiso exactamente en el peor momento
posible, antes de que exista ninguna ventana.

### Corrección — `IPodMonitor.swift`

`handleDiskChange` pasa de síncrono a `async`. Todo lo que toca archivos
del iPod (`FirmwareSwitcher.repairIfNeeded`, `seedContractFilesToActiveTree`
y `AuraDeviceProbe.probe`, en ese orden, sin cambiarlo) se movió dentro de
un `Task.detached(priority: .userInitiated)`, `await`ado desde el actor
principal — el hilo principal queda libre mientras esa lectura corre (y
mientras macOS, si hace falta, muestra su diálogo de permiso con una
ventana real ya en pantalla donde adjuntarlo). `InstallerFlowRegistry.shared.flowActive`
se lee ANTES de entrar al `Task.detached` (es `@MainActor`, no se puede
leer desde ahí) y se pasa capturado. El orden relativo de las operaciones
no cambió, solo el hilo donde corren; `recordBootloaderVerified` y
`syncClockIfNeeded` (los dos pasos posteriores al `probe`) se quedaron en
el actor principal sin cambios, porque no fueron el punto donde se
reprodujo el cuelgue.

**Confirmado que el patrón correcto ya existía del lado Windows** —
`DeviceSessionService.cs` (`Reevaluate()`) documenta exactamente el
problema inverso que llevó a la misma solución: el sondeo pesado corre en
`Task.Run` y solo el resultado ya calculado se consume de vuelta en el
hilo de interfaz. No hizo falta ningún cambio ahí.

### Verificación

`swift build` y `xcodebuild` (Debug, Swift 6 estricto — la build de SPM no
detecta errores de `Sendable`, la de `xcodebuild` sí) en verde, sin ningún
error de concurrencia por cruzar `DiskModeInfo`/`AuraDevice` al
`Task.detached`. `swift test`: 756/756. `scripts/build-app.sh` reinstaló
`/Applications/AuraStudio.app` (Release) con el fix; relanzado con el mismo
iPod real todavía conectado: abre su ventana de inmediato, sin ningún
cuelgue.

Nada de esto tocó ningún archivo de Windows: el bug y su causa (TCC de
macOS) no existen ahí.

Commit `8e3fc10`, empujado a `origin/main` a continuación de `84e26b1`
(ST-149/ST-150) — separado a propósito, no una enmienda: es un hallazgo
posterior, con su propio diagnóstico y verificación. De paso viaja la
primera captura real para el README (`docs/readme/01-general.png`, pantalla
General con el iPod real conectado).

### DMG regenerado

El DMG de ST-149 (`dist/AuraStudio-0.2.0-20260904.dmg`,
`d64b89a6...`) tenía el bug de este ST-151 — se borró y se generó de nuevo
desde el binario ya corregido, mismo nombre de archivo (mismo día):

- **SHA-256 nuevo**: `12f81606db7a47a06001280d2cec23cfb5f3bbdfeac02ffefa5a3169affb1c5f`
  (verificado independiente con `shasum -a 256`)
- Resto de los datos sin cambio: 41 MB, universal (`x86_64 arm64`), macOS
  mínimo 14.4, firmware Aura `v0.4.6-beta` / Metro `v0.7.2` / moonlit `v0.2.2`.

El hash de ST-149 (`d64b89a6...`) queda obsoleto — si alguien lo tiene
anotado en otro lado, es el DMG con el bug del cuelgue.

## ST-160 — `Make-Installer.ps1` nombraba el instalador con un "0.1.0" hardcodeado, no con el `AppVersion` real del `.iss`

### Qué pasó

`Build-Installer`, en `studio\windows\scripts\Make-Installer.ps1`, construía
el nombre del `.exe` esperado tras compilar con Inno Setup así:

```powershell
$setup = Join-Path $dist "AuraStudioSetup-0.1.0-$arch.exe"
```

mientras `installer\AuraStudio.iss` define `#define AppVersion "0.2.0"` y
`OutputBaseFilename=AuraStudioSetup-{#AppVersion}-{#Arch}` — Inno Setup
llevaba tiempo generando `AuraStudioSetup-0.2.0-$arch.exe`, un nombre que
el script nunca iba a encontrar.

El síntoma fue silencioso: en el `dist\` de la máquina donde se detectó
esto sobrevivían `AuraStudioSetup-0.1.0-arm64.exe` y
`AuraStudioSetup-0.1.0-x64.exe` del 2026-09-01, así que
`Test-Path $setup` los encontraba a ELLOS — archivos viejos, no los que
la corrida actual acababa de generar — y el resumen final "Listo: ..."
los nombraba como si fueran el resultado de esa compilación. En un
`dist\` limpio (o en cualquier máquina que nunca hubiera tenido un 0.1.0),
el script habría lanzado la excepción "Inno Setup terminó bien pero no
dejó $setup" después de una compilación que en realidad sí había
funcionado.

### Por qué pasó

El nombre del instalador lo decide una sola fuente: `OutputBaseFilename`
en el `.iss`, resuelto con el `AppVersion` que el propio `.iss` define.
El `Version` de `AuraStudio.App.csproj` es una fuente distinta y no
sincronizada automáticamente con el `.iss` — las dos quedaron en 0.2.0
por coincidencia de mantenimiento manual, no por ningún mecanismo que
las ate. El script de empaquetado tenía el número copiado a mano una
tercera vez, congelado en el valor que tenía el `.iss` el día que se
escribió el script.

### Corrección

`Make-Installer.ps1` lee `AppVersion` del `.iss` una sola vez, al
principio del script (junto a `$iss`), con un regex sobre la línea
`#define AppVersion "x.y.z"`, y falla con un mensaje explícito si no la
encuentra. `Build-Installer` arma `$setup` con esa variable
(`$appVersion`) en vez del literal. No se tocó `AuraStudio.iss`, el
`.csproj` ni el resto del script — el `.iss` sigue siendo la única
fuente del número de versión que aparece en el nombre del archivo.

### Verificación

Antes de correr nada, se respaldaron fuera del repo (y se les sacó
SHA-256) los dos instaladores 0.2.0 ya comprometidos para el release:

- `AuraStudioSetup-0.2.0-arm64.exe`:
  `3256297bad5a81694f11457f5ea03b2a85e0b193ae241c2755d4780c050537ab`
- `AuraStudioSetup-0.2.0-x64.exe`:
  `e0162946f7a5b412d46394efafbc03242b5886e46421855b1f31514353216fbb`

`.\scripts\Make-Installer.ps1 -Architecture arm64 -SkipPublish` (empaqueta
el publish ARM64 ya presente en el árbol, sin recompilar) terminó con
`Listo: ...\dist\AuraStudioSetup-0.2.0-arm64.exe` / `94.4 MB` — el nombre
correcto, sin rastro de "0.1.0". El `.exe` arm64 generado por esa corrida
se descartó y se restauró la copia de respaldo; `Get-FileHash` sobre los
dos `.exe` en `dist\` después de restaurar dio, byte a byte, los mismos
dos SHA-256 de arriba. Los `AuraStudioSetup-0.1.0-*.exe` del 2026-09-01
no se tocaron.

## Release v0.2.0 publicado

Tag `v0.2.0` sobre `33e5f4f` (ST-149/ST-150/ST-151, el pin corregido con
el fix del cuelgue ya adentro), release en `Ricolinos/Aura-Studio` con
EXACTAMENTE tres assets — `AuraStudio-0.2.0.dmg`
(`12f81606db7a47a06001280d2cec23cfb5f3bbdfeac02ffefa5a3169affb1c5f`),
`AuraStudioSetup-0.2.0-x64.exe`
(`e0162946f7a5b412d46394efafbc03242b5886e46421855b1f31514353216fbb`),
`AuraStudioSetup-0.2.0-arm64.exe`
(`3256297bad5a81694f11457f5ea03b2a85e0b193ae241c2755d4780c050537ab`) —
verificados los tres de forma independiente con `shasum -a 256`/
`Get-FileHash` antes de subir, coincidieron con lo reportado por la sesión
de la VM. Notas en inglés, `v0.1.2` marcado como superseded en el texto,
sin tocar ese release. Confirmado con el dueño antes del tag y antes del
`gh release create`, siguiendo la misma disciplina de todo el resto de
esta sesión con acciones públicas/irreversibles.

https://github.com/Ricolinos/Aura-Studio/releases/tag/v0.2.0

## ST-152 — PLAN-studio-rendimiento.md, Fase 0: línea base medida antes de tocar nada

Primera decisión de la ronda de rendimiento (sesión D de la supervisora,
`aura-studio-43`). Antes de escribir una sola línea de la Fase 1, el plan
mismo pide verificar su propio diagnóstico (§0) contra el código actual
— se hizo con un fork de exploración dedicado, comparando cada una de las
9 causas raíz línea por línea contra el código de hoy.

### Verificación del diagnóstico — 8 de 9 exactas, 1 con una precisión

Las 9 causas de §0 se confirmaron todas en sustancia. Ocho, con las
mismas líneas citadas (o un corrimiento de pocas líneas por cambios
posteriores del archivo, sin alterar la causa). La única corrección real:
el punto 4 (`persistCatalog()` llamado "una vez por ítem" en acciones
sobre selección múltiple) cita dos ejemplos —
`MediaSectionView.swift:838` y `:953`—, pero solo el primero
(`clearCoverArt`, vía un loop que persiste en cada iteración) hace
exactamente eso. El segundo (`:953`, `deleteItems(ids:)`) ya recibe el
lote completo y persiste **una sola vez** al final — no ilustra el
problema que dice ilustrar, aunque el problema en sí (con `clearCoverArt`
y otras 28 llamadas a `persistCatalog()`) sigue siendo real y es exactamente
lo que la Fase 3 va a coalescer.

### Infraestructura de medición nueva

1. **Biblioteca sintética** (`LibraryPerformanceBaselineTests.
   makeSyntheticItems`, dentro del propio archivo de pruebas en vez de un
   target aparte — más simple para `@testable import` y no necesita
   ningún paso de build adicional): 12 000 canciones / 900 álbumes / 300
   artistas (3 álbumes por artista, 13-14 pistas por álbum para llegar
   exacto a 12 000), archivos "diminutos" (256 bytes, contenido
   irrelevante) en vez de audio real vía `ffmpeg` — lo que se mide es el
   número de syscalls de `stat()`/E/S por ítem, no el tamaño real, y
   spawnear `ffmpeg` 12 000 veces habría sido más lento que la cosa que
   se está midiendo.
2. **Dos seams de prueba, sin cambiar comportamiento de producción**:
   `LibraryViewModel.persistCatalog()` pasa de `private` a visibilidad de
   módulo (`internal`) para poder medirla aislada; `LibraryViewModel.
   replaceItemsForPerformanceTesting(_:)` (nuevo) inyecta un catálogo ya
   armado sin pasar por `addDroppedFiles`/`process(itemAt:)` (que copia,
   corre `ffmpeg` y espera POR ÍTEM -- exactamente el costo que NO hay que
   medir acá); `GridSelection.handleTap(_:orderedIDs:modifierFlags:)`
   (nuevo overload) separa la lectura de `NSEvent.modifierFlags` para
   poder simular Shift+clic sin depender del teclado real -- el camino de
   producción (`handleTap(_:orderedIDs:)`) sigue leyendo el estado global
   exactamente igual que antes, delegando a este.
3. **`MainThreadWatchdog`** (`Services/MainThreadWatchdog.swift`, nuevo):
   vigilante de hilo principal, solo `DEBUG` + `AURA_WATCHDOG=1`. Late un
   corazón en el hilo principal cada 50 ms desde un hilo aparte; más de
   250 ms sin uno = bloqueo. La pila se captura en dos tiempos a
   propósito -- el manejador de la señal (`SIGUSR2`, enviada al hilo
   principal con `pthread_kill`) solo llama `backtrace()` sobre un buffer
   ya reservado (sin `malloc`), y `backtrace_symbols` (que sí reserva
   memoria) corre después, ya en el hilo vigilante -- symbolizar DENTRO
   del manejador podría colgar algo de verdad si el hilo principal tenía
   el lock de `malloc` tomado justo cuando lo interrumpió la señal, que es
   precisamente el escenario que existe para detectar. Probado con un
   bloqueo deliberado de 500 ms en una prueba temporal (borrada después de
   confirmar): detectó el bloqueo real (~543 ms) y capturó la pila
   symbolizada de verdad, con los frames de `XCTestCore` incluidos.

### Línea base (12 000 ítems, Mac del dueño, Debug, `swift test`, promedio de 10 corridas de `measure`)

| Medición | Promedio | Nota |
|---|---|---|
| (a) Recomputar `rows`, orden por título | 367 ms | PROXY -- ver abajo |
| (a) Recomputar `rows`, orden por tamaño | 1 182 ms | PROXY; `stat()` sin caché por fila explica la diferencia de 815 ms contra ordenar por título |
| (b) Cambiar la selección 100 veces | 1 ms | Ver nota "lo que esto NO mide" |
| (c) `persistCatalog()` | 976 ms | Código real, sin proxy |
| (d) Shift+clic de 1 a 1 000 (`GridSelection`) | 37 ms | Código real, sin proxy |
| (e) `loadCatalog` en frío | 1 372 ms | Código real, sin proxy |

**Las dos mediciones de "(a)" son un PROXY, no código de producción
medido directo.** `MediaSectionView.rows`/`items`
(Views/MediaSectionView.swift:94-140) es un computed var de una `View` de
SwiftUI -- exactamente el problema #2 del diagnóstico, que todavía no
está extraído a una función aislada (eso es lo que la Fase 1 va a hacer
con `RowsModel`). Estas dos pruebas reproducen la MISMA operación
(`items.map { MediaTableRow(item:) }.sorted(using:)`) para el caso "sin
filtros activos" (scope `.all`, sin categoría/búsqueda/favoritos), que es
exactamente lo que `items` devuelve en ese caso. Cuando la Fase 1 extraiga
`RowsModel`, la PARADA 1 reengancha esta prueba a la extracción real en
vez de reproducir la expresión -- se documenta ahora para que nadie lea
"367 ms"/"1 182 ms" como si vinieran de llamar código real.

**Lo que "(b) cambiar la selección 100 veces" NO mide, y por qué el
número (1 ms) no contradice el síntoma del dueño.** Esta prueba solo
mide el costo de asignar `LibraryViewModel.selectionForSync` (un
`@Published`) 100 veces, SIN ninguna vista de SwiftUI observándolo --
ese costo es, en efecto, despreciable. La medición **confirma** la causa
#1 del diagnóstico en vez de contradecirla: el congelamiento no viene de
publicar la selección, viene de cuánto vuelve a renderizar SwiftUI
cuando `ContentView` entero (que observa el `LibraryViewModel` global,
`ContentView.swift:25,64,262`) reacciona a ese cambio. Falta un
`XCTOSSignpostMetric`/`Self._printChanges()` contra una jerarquía de
vistas real para medir ESE costo -- queda pendiente, anotado para la
Fase 1 (que además ataca la causa moviendo la selección a un
`SelectionStore` acotado).

### Costo de mantener esto

`swift test` completo pasó de ~15-25 s a **~76-90 s** con estas 6 pruebas
nuevas (`persistCatalog`/`loadCatalog`/orden-por-tamaño rondan 1 s cada
una, ×10 corridas de `measure`, ×2-3 con la generación de la biblioteca
sintética en `setUp`). Es el costo aceptado de "nada se da por resuelto
sin medirlo" -- si en una fase futura esto empieza a estorbar el ciclo de
desarrollo, ahí se decide bajar el número de corridas de `measure`
(`XCTMeasureOptions.iterationCount`) o mover estas pruebas a un esquema
aparte, pero no antes: la Fase 0 completa depende de tener el número real,
no uno recortado.

### Verificación

`swift build`, `xcodebuild` (Debug, Swift 6 estricto) y `swift test`:
762/762 en verde (1 saltada, la prueba de red en vivo de ST-150 -- sin
relación con esta ronda). Una corrida previa reportó 1 falla aislada que
no se repitió en la corrida siguiente (762/762 limpio) ni en ninguna
posterior -- no se pudo reproducir, tratada como fluctuación puntual del
entorno y no como regresión de este cambio; si vuelve a aparecer con un
nombre de prueba consistente, se investiga entonces. `scripts/build-app.sh`
pendiente de correr una vez más antes de cerrar esta PARADA (ver abajo).

## ST-153 — PLAN-studio-rendimiento.md, Fase 1: selección y render (el congelamiento al seleccionar)

Ataca las dos causas raíz que la línea base de ST-152 midió directo:
publicar la selección en el ViewModel gigante (§0.1) y recalcular `rows`
en el `body` (§0.2). Completos los puntos 1 y 2 del plan; 3, 4 y 5 quedan
deliberadamente recortados de esta PARADA -- ver "Qué queda afuera" al
final, con el motivo de cada uno.

### 1. `SelectionStore` reemplaza `LibraryViewModel.selectionForSync`

`Models/SelectionStore.swift` (nuevo): `@MainActor ObservableObject`
chico, un solo `@Published private(set) var selected: Set<UUID>`. Un
único `SelectionStore` compartido (no uno por tipo de medio) **a
propósito**: así ya funciona hoy `selectionForSync` -- `AlbumsView`/
`MoviesView` leen la selección que publica la tabla de canciones/video
EMBEBIDA dentro de un álbum/película expandido (comentario ya existente
en esos archivos: "la selección de la tabla embebida llega por..."), y
partirlo por tipo de medio habría sido un cambio de comportamiento
disfrazado de cambio de rendimiento. `MediaSectionView` (tabla de nivel
superior y cada instancia embebida) sigue publicando en
`.onAppear`/`.onChange(of: selection)`/`.onDisappear` exactamente igual
que antes -- cambia únicamente A DÓNDE publica.

`selectionForSync` se borró de `LibraryViewModel` (era observado por
`ContentView` entero). Los tres consumidores reales, confirmados por
lectura de código (coinciden exacto con lo que dice el plan):
`DeviceGeneralView` (cuenta para el botón + arma `.selection(...)` al
disparar el sync, ahora leído de `selectionStore.selected` EN ESE
MOMENTO, no publicado continuamente), `AlbumsView`, `MoviesView`. Los
tres reciben `selectionStore: SelectionStore` nuevo; `ContentView` crea
UNO (`@StateObject`) y lo reparte a los 4 sitios de `MediaSectionView`,
`AlbumsView` y `MoviesView`.

### 2. `RowsModel` -- filas memoizadas, nunca recalculadas por selección

`Models/RowsModel.swift` (nuevo): `@MainActor ObservableObject` con
`rows: [MediaTableRow]` publicado. `recompute(items:deviceSyncIndex:sortOrder:)`
hace exactamente lo que hacía el `rows` computed var de
`MediaSectionView` (`map` + `sorted(using:)`), pero con más de 2000
ítems (`asyncThreshold`, el tamaño de la línea base de ST-152) lo corre
en un `Task.detached(priority: .userInitiated)` y publica el resultado
de una sola vez -- un contador de generación (`generation`) descarta el
resultado de una recomputación vieja si otra más nueva ya arrancó
mientras la anterior corría.

`MediaSectionView` dispara `recomputeRowsIfNeeded()` desde
`.onChange(of: items)` (el ítems YA FILTRADO -- barato, un puñado de
`filter`), `.onChange(of: sortOrder)` y `.onChange(of: viewModel.
deviceSyncIndex)`, y una vez en `.onAppear`. **Nunca desde
`.onChange(of: selection)`**: `items` no depende de la selección, así
que marcar/desmarcar una fila no cambia ese valor y ningún `onChange`
dispara el recálculo -- exactamente el objetivo del plan ("recalculadas
solo cuando cambian items... nunca por selección").

Un seam nuevo, sin cambiar el camino de producción:
`GridSelection.handleTap(_:orderedIDs:modifierFlags:)` (overload) separa
la lectura de `NSEvent.modifierFlags` -- ya estaba desde ST-152, se
reutiliza igual acá.

### Verificación

`swift build`, `xcodebuild` (Debug, Swift 6 estricto) y `swift test`
762/762 (1 saltada, red) en verde. `xcodebuild` encontró algo que
`swift build` no: dos problemas de concurrencia estricta nuevos --

1. Una expresión en `MediaSectionView.swift` (el `Binding(get:set:)` de
   `batchEditingIDs`, sin relación directa con esta Fase) que el
   type-checker ya no lograba resolver en tiempo razonable después de
   agregar los `.onChange` nuevos al `body` -- se resolvió anotando los
   tipos explícitos (`Binding<Bool>`, closure con `(newValue: Bool) in`).
   Cambio cosmético, mismo comportamiento.
2. `MainThreadWatchdog` (ST-152): sus variables estáticas venían sin
   anotar para concurrencia estricta -- funcionaban porque `swift build`
   no lo exige. Se marcaron `nonisolated(unsafe)` con el motivo exacto de
   por qué cada una es segura igual (sincronización manual con un
   manejador de señal de C, que no entiende `Sendable`), no un silencio
   ciego del chequeo.

Pruebas de rendimiento re-corridas contra el código real (ya no el proxy
de ST-152 -- `RowsModel` existe):

| Medición | ST-152 (proxy) | ST-153 (real) |
|---|---|---|
| Recomputar rows, por título | 367 ms | 365 ms |
| Recomputar rows, por tamaño | 1 182 ms | 1 157 ms |
| Cambiar selección ×100 | 1 ms | 1 ms |

**Los números de "recomputar rows" no bajaron, y es lo esperado.** Fase 1
no hace que el `sorted(using:)` en sí sea más rápido (eso es la caché de
`fileSizeBytes`, punto 4, recortado de esta PARADA) -- lo que arregla es
que ese cálculo YA NO SE DISPARA en cada cambio de selección. Una prueba
que SIEMPRE dispara el recálculo (como esta) no puede ver esa mejora; la
prueba (b) tampoco la ve por la misma razón de siempre (ST-152: mide el
costo de escribir el `@Published`, no el de qué re-renderiza SwiftUI
alrededor). La mejora real -- que un clic ya no re-renderiza toda la
ventana -- se verificó por lectura de código (`selection`/`rows` ya no
tocan nada que `ContentView` observe) y queda pendiente de confirmar con
`Self._printChanges()` contra una jerarquía de vistas real, con el iPod
del dueño, en la Fase 7.

### Qué queda afuera de esta PARADA, y por qué

- **Punto 1 (parcial): no se quitó el `onPreferenceChange` de
  `ContentView.swift`.** Es un mecanismo YA desacoplado a propósito (la
  vista hija no sabe cómo se dibuja la barra de estado ni si el usuario
  la ocultó) -- reemplazarlo exige que cada sección exponga sus totales
  de otra forma sin ese desacople, un cambio estructural aparte que no es
  lo que miden las pruebas (a)/(b) de esta PARADA. Con `statusSummary`
  cacheado (punto 3) el costo de lo que viaja por ese canal baja aunque
  el canal en sí siga igual.
- **Punto 3: `statusSummary` sigue en el `body`, sin cachear ni debounce.**
  Con la selección ya fuera de `LibraryViewModel`, el impacto directo del
  síntoma reportado (congelarse al seleccionar) ya está resuelto por los
  puntos 1-2; cachear los conteos totales del catálogo y debouncear los
  de la selección es una optimización real pero incremental, no la causa
  del congelamiento.
- **Punto 4: `fileSizeBytes` sin caché persistida.** Es un cambio de
  esquema de `PersistedLibraryItem` con migración (`Int64?` nuevo,
  siguiendo la regla ya documentada en el propio archivo: todo campo
  nuevo es opcional o una `try?` decode tira el catálogo entero) -- more
  aislado y de menor riesgo que 1-2, pero también el que explica la
  brecha completa entre ordenar por título (365 ms) y por tamaño
  (1157 ms) en la línea base.
- **Punto 5: `ContentView` sigue pasando `library` entero a cada vista.**
  `MediaSectionView`/`AlbumsView`/`MoviesView`/`DeviceGeneralView` ya
  reciben `selectionStore`/`rowsModel` acotados además de `library` (un
  primer paso real hacia lo que pide el punto), pero la verificación con
  `Self._printChanges()` contra una jerarquía real queda pendiente.

Los tres quedan anotados para una PARADA 1b o para plegarse a las Fases
2/3 (que ya tocan `GridSelection`/`persistCatalog` de todos modos) --
decisión de la supervisora, no tomada acá.

## Addendum a ST-153 — punto 3 (statusSummary cacheado) y evidencia real del punto 5

La supervisora marcó la PARADA 1 como aprobada en lo hecho pero incompleta
en dos cosas: el punto 3 sí es causa raíz (no se podía diferir), y la
prueba (b) no mide lo que de verdad importa. Las dos, atendidas.

### Punto 3: `statusSummary` deja de recalcular el catálogo entero por clic

`StatusSummaryModel` (nuevo, mismo patrón que `RowsModel`): cachea
`total`/`trailing` de `LibraryStatusSummary` -- lo que NO depende de la
selección (artistas/álbumes/duración/tamaño de TODOS los `items`) --
recalculado solo cuando cambian `items` (mismo disparador que
`recomputeRowsIfNeeded`, ahora hace las dos cosas). Tres funciones nuevas
en `LibraryStatusSummary.swift` (`musicSelectionText`/`videoSelectionText`/
`photoSelectionText`) repiten SOLO la parte de `.selection` -- proporcional
a lo seleccionado, no al catálogo. `MediaSectionView.statusSummary` ahora
combina: total cacheado + `.selection` recalculado en el sitio.

**Medido, antes y después, con 50 ítems seleccionados sobre 12 000:**

| | Antes (`LibraryStats.music` completo) | Después (total cacheado + `musicSelectionText`) |
|---|---|---|
| Tiempo | 272 ms | 2 ms |

No hizo falta el debounce de 100 ms que sugería el plan: una vez que el
total deja de recalcularse, lo que queda (`.selection`) ya es
proporcional a lo seleccionado, no al catálogo -- 2 ms para 50
seleccionados no justifica la complejidad extra de debouncear en
background. Si una selección de varios miles de ítems (Cmd+A en Fase 2)
resulta pesada en la práctica, se revisita ahí, con el número real en
mano.

### Punto 5: por qué un clic ya no puede re-renderizar `ContentView`

En vez de (o adenmás de) contar evaluaciones de `body` en tiempo de
ejecución, esto se puede probar por lectura de código de forma
concluyente: `ContentView` jamás lee `selectionStore.selected` en
ningún lado -- `grep -n "selectionStore\." ContentView.swift` no
devuelve nada; el `@StateObject` se crea ahí y se REPARTE a los hijos
como argumento, pero `ContentView` nunca se suscribe a sus cambios.
SwiftUI solo invalida el `body` de una vista cuando ESA vista lee una
propiedad `@Published` que cambió -- sin ninguna lectura, no hay
invalidación posible, sin importar cuántas veces cambie
`selectionStore.selected`. Mismo argumento para `rowsModel`/
`statusSummaryModel`: son `@StateObject` DENTRO de `MediaSectionView`,
ni siquiera existen fuera de ella.

Esto es una garantía estructural, no una medición probabilística -- más
fuerte que un contador de `_printChanges()` para esta pregunta puntual
("¿puede un clic invalidar `ContentView`?"), aunque no reemplaza medir
cuántas veces se re-evalúa `MediaSectionView` misma (que SÍ observa
`selection` vía `@State`, y debe seguir re-evaluándose -- es lo que
pinta la fila marcada). Esa medición con `Self._printChanges()` contra
una jerarquía de vistas real, con el iPod del dueño, sigue pendiente
para la Fase 7 tal como quedó anotado.

### Verificación

`swift build`, `swift test`: 762/762 en verde (esta vez sin ninguna
saltada -- había red). `xcodebuild` corrido junto con la Fase 2, ver
ST-154.

## ST-154 — PLAN-studio-rendimiento.md, Fase 2: selección tipo Finder y teclado

Confirmado con el dueño explícitamente antes de empezar: agrega
comportamiento nuevo de verdad (Cmd+A no existía), así que se implementa
completo ahora pero la **verificación interactiva queda pendiente, junto
al dueño** -- nada de esto se probó haciendo clic en la app real. Esta
entrada documenta qué se hizo y qué falta confirmar a mano.

### Punto 2: `GridOrder`, O(1) en vez de `firstIndex(of:)` ×2 por clic

`GridOrder<ID>` (nuevo, en `GridSelection.swift`): envuelve `[ID]` +
`[ID: Int]` (diccionario id→índice, construido una vez en el `init`).
`GridSelection.handleTap` pasa de recibir `orderedIDs: [ID]` (dos
`firstIndex(of:)` O(N) por Shift+clic, con el arreglo armado fresco por
el llamador en cada clic vía `.map(\.id)`) a recibir `order: GridOrder<ID>`
(rango de Shift+clic en O(1)). `GridSelection.selectAll(_:)` (nuevo):
Cmd+A.

Aplicado en las cuatro cuadrículas (`AlbumsView`, `MoviesView`,
`SeriesView` -- dos selecciones, series y episodios --, `PhotoAlbumsView`
-- dos selecciones, álbumes y fotos): cada una guarda su `GridOrder` en
un `@State`, reconstruido solo con `.onAppear`/`.onChange(of: ...map(\.id))`
sobre la lista visible -- nunca en el gesto de tap. Sin pruebas
correctivas antes de esta ronda (`GridSelection` no tenía ningún test);
`GridSelectionTests.swift` (nuevo) cubre clic simple, Cmd+clic, Shift+clic
(adelante y atrás), Cmd+A, `clear()`, y `GridOrder` en sí (búsqueda,
igualdad, vacío) -- 11 pruebas.

**Lo que NO se tocó, a propósito**: la lectura de `NSEvent.modifierFlags`
global en el camino de producción (`handleTap(_:order:)` sin el parámetro
explícito). El plan pide reemplazarla por `EventModifiers` tomados del
propio gesto -- en SwiftUI/macOS eso exige componer varios
`TapGesture().modifiers(...)` exclusivos entre sí, un patrón frágil que
no se puede verificar sin hacer clic en la app real. `NSEvent.
modifierFlags` sigue siendo lo que ya funcionaba (el comentario original
del archivo ya lo llamaba "el mismo truco que usa el resto del
ecosistema SwiftUI en macOS para esto") -- cambiarlo a ciegas arriesgaba
romper Cmd+clic/Shift+clic por evitar una lectura de estado global que
en la práctica no ha dado problemas. Queda para cuando haya verificación
interactiva.

### Punto 1: Cmd+A / Escape

**Cuadrículas** (custom, sin soporte nativo): `.onKeyPress(keys: ["a"])`
que revisa `press.modifiers.contains(.command)` antes de actuar (así
"a" sin Cmd sigue sin hacer nada, no se roba la tecla) llama
`selection.selectAll(order)`; `.onKeyPress(.escape)` llama
`selection.clear()`. Mismo patrón ya establecido en el repo
(`MediaSectionView` ya usaba `.onKeyPress(.space)` para Vista previa).

**Tablas** (`MediaSectionView`, `Table` nativo): **Cmd+A NO se
implementó a propósito**. `Table` con `selection:` ya lo resuelve nativo
en macOS (es textualmente lo que dice el plan: "en Table/List es nativo,
solo verificar") -- agregar un manejador propio arriesgaba competir con
o duplicar ese comportamiento sin poder probarlo en vivo. Sí se agregó
Escape (`.onKeyPress(.escape)` → `selection.removeAll()`), que no es un
atajo nativo de `Table`.

**Flechas moviendo el ancla**: no implementado en esta pasada. El plan
no especifica si la navegación debe ser 2D (según columnas de la
cuadrícula) o lineal sobre `order.ids`; implementar navegación espacial
sin poder ver la cuadrícula real es más riesgo del que vale sin
verificación en mano. Queda pendiente, a decidir con el dueño presente.

**Menú Edición** (punto 3 del plan, "Seleccionar todo"/"Deseleccionar"
con estado habilitado según la sección): no implementado. Requiere un
mecanismo de enrutamiento por foco (`@FocusedValue`, el mismo patrón que
`auraLibraryCommand`/`auraSyncCommand` ya usan en `ContentView.swift`,
pero publicado por cada vista de cuadrícula/tabla en vez de solo por la
raíz) que toca de verdad la app en ejecución para confirmar que el foco
se resuelve como se espera entre una cuadrícula y su tabla embebida
(álbum/película expandidos) -- el mismo motivo de todo lo demás que
queda pendiente. El atajo de teclado (Cmd+A/Escape) ya funciona sin el
ítem de menú; el menú es la superficie descubrible, no el mecanismo.

### Casilla vs. clic de fila (`MediaSectionView` checkbox)

Revisado, no tocado: la casilla (`checkboxCell`, `Toggle` dentro de una
`TableColumn`) es un control interactivo propio dentro de la fila de
`Table`; en teoría AppKit le da prioridad al control sobre el clic de
selección de fila, pero confirmar que no compiten de verdad exige
clickear la tabla real. Anotado para la verificación interactiva, sin
cambio de código especulativo.

### Verificación

`swift build`, `xcodebuild` (Debug, Swift 6 estricto) y `swift test`:
775/775 en verde (11 pruebas nuevas de `GridSelectionTests`, ninguna
saltada). `scripts/build-app.sh` verificado contra un directorio
temporal (Release). Un test de `GridSelectionTests` falló en el primer
intento (`testShiftTapAfterSelectAllExtendsFromTheEnd`) por una
expectativa mal pensada de la prueba misma -- Shift+clic siempre UNE al
conjunto existente (`formUnion`), nunca lo reemplaza, así que
Cmd+A→Shift+clic no "recorta" la selección a un rango; es el
comportamiento correcto y ya existía antes de esta Fase. Se corrigió la
prueba, no el código.

### Lo que falta antes de dar la Fase 2 por cerrada

Todo lo de arriba compila y pasa sus pruebas de unidad, pero **nada se
verificó haciendo clic/tecleando en la app real**: Cmd+A y Escape en las
7 vistas (4 cuadrículas + 3 tablas), que la casilla no dispare también
la selección de fila de `Table`, y que Shift+clic/Cmd+clic sigan
sintiéndose iguales que antes. Sesión conjunta con el dueño pendiente
antes de la PARADA 2 formal (que además pide, textualmente, "prueba de
UI -- XCUITest o guion").

## ST-161 — La cuadrícula de Álbumes se llamaba a sí misma sin fin: la app se congelaba con un núcleo al 100%

Encontrado sobre la build 0.2.0 instalada (`33e5f4f`), con la biblioteca real
del dueño (`V:\Mac Externo\Documents\Aura Library` — 2576 canciones, 1092
álbumes, 225 fotos) y sin iPod. Reproducido **2 de 2 veces**: la ventana
aparecía al segundo, la app respondía un rato en General, y de golpe dejaba de
responder con un núcleo al 100% hasta que Windows la mataba (`AppHangB1` en el
Visor de eventos). Sin excepción y sin nada en `errores.log` — para el proceso
no había pasado nada malo.

### Diagnóstico

La pila del hilo principal (`dotnet-stack report`, completa en
`studio/windows/docs/capturas/v0.2.0-cuelgue-pila.txt`; la pantalla del momento,
en `v0.2.0-cuelgue-general-117s.png`) dice todo en cinco renglones que se
repiten cientos de veces:

```
System.Collections.Generic.Dictionary`2.Resize(int32,bool)
AuraStudio.Core.Library.LibraryGrouping.Bucket(...)
AuraStudio.Core.Library.LibraryGrouping.Albums(...)
AuraStudio.App.ViewModels.MediaGridViewModel.Refresh()
AuraStudio.App.ViewModels.MediaGridViewModel.NotifySelectionChanged()
AuraStudio.App.ViewModels.MediaGridViewModel.Refresh()
AuraStudio.App.ViewModels.MediaGridViewModel.NotifySelectionChanged()
...
```

Recursión infinita, cerrada por tres piezas que por separado son razonables:

1. `MediaGridViewModel` (constructor) se suscribía a **cualquier** aviso de la
   biblioteca: `_library.PropertyChanged += (_, _) => Refresh();`
2. `Refresh()` rearma las tarjetas —agrupando la biblioteca entera con
   `LibraryGrouping`— y termina llamando a `NotifySelectionChanged()`, que
   publica la selección con `_library.PublishSelectionForSync(...)`.
3. `PublishSelectionForSync` asignaba y **avisaba siempre**, hubiera cambiado
   algo o no. Y nunca cambiaba nada: una cuadrícula recién refrescada no tiene
   nada seleccionado, así que publicaba una lista vacía **nueva** cada vez.

Aviso → refresco → publicación → aviso. Cada vuelta reagrupa 2576 elementos, así
que el desbordamiento de pila tarda minutos en llegar; mientras tanto el hilo de
interfaz está muerto y Windows ve una app colgada.

`ArtistsViewModel` tenía **el mismo ciclo por el mismo camino**: constructor
idéntico, y su `Refresh()` termina en `SetSelection(...)`, que también publica.

**Qué NO era, aunque lo parecía.** Se sospechaba un `PropertyChanged` tardío de
la biblioteca a los ~110 s (el fin de la comprobación de archivos de ST-098, o
la normalización de carátulas de ST-141). No es eso. Medido en esta VM con la
build **sin** el arreglo, con la biblioteca real y sin iPod:

- **200 s en General sin tocar nada**: `Responding=True` todo el tiempo, CPU
  total plana en 1.9 s. Repetido con la ventana visible en pantalla, 170 s:
  igual, plana en 1.4 s, incluido el minuto 110. No hay ningún evento tardío.
- **Basta una sola navegación a Álbumes.** El `MediaGridViewModel` es singleton,
  pero **nadie lo construye hasta que se abre una cuadrícula**: `MediaGridPage`
  es el único que lo pide del contenedor (`App.xaml.cs:107`), y el armazón
  arranca en General → `DeviceListPage`. En cuanto existe, su primer `Refresh()`
  —el de su propio `OnNavigatedTo`— entra al ciclo: CPU 1.6 s → 47.8 s, la
  interfaz muerta desde el clic, y el proceso murió con `0xC00000FD`
  (`STATUS_STACK_OVERFLOW`) a los ~50 s.

O sea: los ~110 s del reporte no son un temporizador de la biblioteca, son el
momento en que esa corrida abrió una cuadrícula por primera vez. Queda escrito
porque buscar el evento tardío —que no existe— cuesta bastante más que el
arreglo.

### Arreglo

**(a) Publicar la selección solo avisa si de verdad cambió.**
`SelectionPublication.SameSelection` (nuevo, `AuraStudio.Core/Library/`, al lado
de `GridSelection`, que es donde ya vive la política de selección) compara **por
contenido y como conjunto**, nunca por referencia: cada refresco arma una lista
nueva con los mismos ids, y comparar instancias diría "cambió" siempre — esa
lectura era justo la que cerraba el ciclo. `LibraryViewModel.PublishSelectionForSync`
se sale antes de tocar nada si el conjunto es igual al ya publicado.

**(b) Las vistas se refrescan por cambios de contenido, no por cualquier aviso.**
`MediaGridViewModel` y `ArtistsViewModel` filtran `e.PropertyName`: rehacen ante
`Items`, `AvailableItems` o un nombre vacío/`null` (que en
`INotifyPropertyChanged` significa "cambió todo"), y ante nada más. Todo cambio
de contenido pasa por alguno de esos dos avisos, incluido el reagrupamiento por
`GroupCollaborations` (que ya publicaba `Items` a propósito) y el cambio de
carpeta de biblioteca (que pasa por `Reload()`).

Las dos son suficientes **por separado**, y esa es la idea: (a) rompe el ciclo
aunque alguien vuelva a suscribirse a todo, y (b) hace que el ciclo ni siquiera
empiece. (b) además quita trabajo que nunca tuvo sentido: cada renglón de
"Normalizando carátulas… N de M" —que se escribe decenas de veces— reagrupaba la
biblioteca entera.

**Lo que no se hizo, y por qué.** No se agregó una guardia de reentrada en
`Refresh()`. Una guardia no impide el ciclo: lo trunca. Y truncarlo tiene su
propio costo — un `Refresh` anidado que se descarta deja la cuadrícula mostrando
tarjetas viejas, que es un bug bastante más difícil de ver que un cuelgue. Con
(a) el ciclo no puede formarse aunque alguien vuelva a escuchar todo, así que la
guardia solo serviría para esconder el siguiente ciclo distinto en vez de
dejarlo salir.

**Lo que se dejó igual, a propósito.** `SongsViewModel` y `PlaylistsViewModel`
siguen escuchando cualquier aviso de la biblioteca. Ninguno publica selección
desde su `Refresh()` —la de la tabla de Canciones la publica la página, no el
modelo—, así que ninguno cierra el ciclo. Y en el caso de Canciones el filtro
sería **incorrecto**: su `Refresh()` depende de `VisibleColumns`, `SortField`,
`SortAscending` y `FavoritesOnly`, que son propiedades observables de
`LibraryViewModel` y no cambian el contenido; filtrarlas dejaría la tabla sin
reordenarse al tocar un encabezado.

### Pruebas

`studio/windows/tests/AuraStudio.Core.Tests/SelectionPublicationTests.cs` — 9
pruebas nuevas. La central reproduce el ciclo en miniatura: una biblioteca y una
cuadrícula de juguete conectadas como las de verdad (refrescar publica, publicar
avisa, el aviso refresca). Con la regla vieja —avisar siempre— la recursión no
termina, y la prueba lo demuestra con un tope de 500 vueltas
(`StackOverflowException` no se puede atrapar en .NET: el ciclo se demuestra
contando, no dejándolo desbordar); con la regla de ahora se detiene en un solo
refresco y cero avisos. Las demás fijan la comparación por contenido: dos listas
nuevas con los mismos ids son la misma selección, el orden y las repeticiones no
cuentan, agregar o vaciar sí.

- `dotnet test tests/AuraStudio.Core.Tests`: **1175/1175** (1166 antes + 9).
- Con la regla vieja puesta a la fuerza (`SameSelection` devolviendo `false`
  siempre), **6 de las 9 nuevas fallan** — incluida la del ciclo. Las pruebas
  distinguen el arreglo, no solo lo acompañan.
- `dotnet build AuraStudio.App -c Release -p:Platform=ARM64`: en verde,
  0 advertencias, 0 errores.

Lo que las pruebas **no** alcanzan: el filtro por `e.PropertyName` vive en los
ViewModels de `AuraStudio.App` (WinUI), y el único proyecto de pruebas
referencia solo `AuraStudio.Core`. Queda cubierto por la verificación en vivo.

### Verificación en vivo

Build del árbol (Release ARM64) corrida contra la biblioteca real y sin iPod,
con `Process.Responding` y CPU muestreados cada segundo: **11 min 49 s de vida
del proceso y 0 segundos sin responder**, CPU total 7.5 s y memoria estable en
~313 MB. El recorrido cabe en los primeros 106 s: Álbumes (1092 tarjetas) a los
17 s, tres tarjetas seleccionadas a los 38 s, Artistas a los 51 s, Películas a
los 72 s con dos seleccionadas a los 90 s, y vuelta a General a los 95 s — cada
paso con la app respondiendo. Los ~10 minutos restantes, quieta en General, con
la CPU sin moverse de 7.5 s.

Con la build **sin** el arreglo, ese mismo recorrido mataba el proceso a los
~50 s del primer clic en Álbumes.

### Evidencia

- `studio/windows/docs/capturas/v0.2.0-cuelgue-pila.txt` — la pila completa del
  hilo principal, con la recursión.
- `v0.2.0-cuelgue-general-117s.png` — la pantalla colgada en General, a los
  117 s.
- `st161-albumes-seleccion.png` — Álbumes con selección, ya con el arreglo.
- `v0.2.0-licencias.png` y `v0.2.0-extras-github.png` — verificación del 0.2.0
  instalado: la pantalla de Licencias y la consulta de versiones a GitHub, las
  dos funcionando.

## ST-155 — PLAN-studio-rendimiento.md, Fase 3: persistencia coalescida

Continuación de trabajo aceptada como decisión de orden (no una acción
externa que necesite confirmación directa) mientras la verificación
interactiva de la Fase 2 queda pendiente para la mañana.

### Punto 1 (`CatalogPersister` con guardado programado ≤ 500 ms): NO implementado, por qué

El plan pide un guardado programado que coalesce llamadas rápidas
seguidas. Antes de escribirlo, se revisó si alguna prueba existente
depende de que `persistCatalog()` escriba SINCRÓNICAMENTE -- y varias sí
lo hacen, con el patrón "mutar con el ViewModel A, crear un ViewModel B
sobre el mismo `libraryRoot`, verificar que B cargó lo que A guardó"
(`LibraryLegacyMigrationTests`, `SharedCatalogInteropTests`,
`CoverArtAssetsTests` y otras). Agregar una demora real de 500 ms
rompería ese patrón salvo que cada prueba fuera actualizada para forzar
un `flush()`, un rediseño más grande y más riesgoso de lo que esta
PARADA necesita. En su lugar, se atacó el MISMO problema (reescrituras
redundantes) por el lado que sí es seguro: que ninguna acción sobre
selección múltiple llame a `persistCatalog()` más de una vez (punto 4,
abajo) -- el efecto práctico (menos guardados redundantes) es el mismo
sin cambiar el contrato síncrono de `persistCatalog()` que ya asumen
las pruebas y, potencialmente, otro código no auditado en esta pasada.

### Punto 2: las carátulas sin cambios ya no se reescriben

`LibraryViewModel.lastWrittenCoverHash: [UUID: Int]` (nuevo): el hash de
la última carátula EFECTIVAMENTE escrita por ítem. `persistCatalog()`
compara el hash actual contra el guardado; si coincide, no reescribe el
archivo pero SÍ sigue declarando su ruta en el catálogo persistido (el
archivo ya está en disco) -- la propiedad crítica que
`PersistCatalogCoalescedTests.testUnchangedCoverKeepsItsRecordedPathAcrossSaves`
fija: "no reescribir" nunca puede significar "olvidarse de que existe".
El caché se limpia por completo al cambiar de carpeta de biblioteca
(`switchLibraryFolder`) y se poda de ítems borrados/sin carátula en cada
guardado.

**Medido** (línea base de ST-152, biblioteca sintética ahora CON
carátula real de ~15 KB por álbum, compartida por sus pistas -- antes no
tenía ninguna, así que el punto 2 no era medible):

| | Primer guardado (todas las carátulas nuevas) | Guardados siguientes sin cambios |
|---|---|---|
| `persistCatalog()`, 12 000 ítems | ~3.48 s | ~1.06 s promedio |

El promedio que reporta `measure` por sí solo (10 corridas mezclando la
primera, cara, con las 9 baratas) sale engañoso (~1.31 s) -- se reportan
los dos números por separado porque es la comparación que de verdad
importa: el caso común (guardar de nuevo sin haber tocado ninguna
carátula) es el que se optimizó.

### Punto 3: JSON compacto

`JSONEncoder.outputFormatting` pasa de `[.prettyPrinted, .sortedKeys]` a
`[.sortedKeys]` (`.sortedKeys` se conserva a propósito, por
reproducibilidad del diff). Aporta poco al tiempo medido en esta
biblioteca sintética (`.prettyPrinted` no era el costo dominante -- el
mapeo de 12 000 `PersistedLibraryItem` y el propio `encode` sí), pero sí
reduce el tamaño real del archivo en disco.

### Punto 4: selección múltiple, una sola persistencia

Auditados los cuatro mencionados por el plan: `deleteItems(ids:)` y
`applyBatchEdit(ids:changes:)` ya mutaban en lote y persistían una sola
vez (confirmado en ST-152, sin cambios acá). `setCategory(_:forItems:)`
también. El que sí llamaba a `persistCatalog()` una vez POR ÍTEM era
`clearCoverArt(id:)`, invocado en bucle desde el menú contextual de
selección múltiple (`MediaSectionView`, "Eliminar carátula"). Se agregó
`clearCoverArt(ids: Set<UUID>)` (mismo patrón que `setCategory`:
`clearCoverArt(id:)` ahora delega a la versión de lote con un solo id) y
se actualizó el único llamador.

### Verificación

`swift build`, `xcodebuild` (Debug, Swift 6 estricto) y `swift test`:
779/779 (1 saltada, red -- fluctuación de entorno, no relacionada).
`PersistCatalogCoalescedTests.swift` (nuevo, 4 pruebas: carátula sin
cambios conserva su ruta, carátula que sí cambia se reescribe,
`clearCoverArt(ids:)` en lote limpia todos los ítems, `clearCoverArt(id:)`
sigue funcionando igual) -- no existía ninguna prueba de `clearCoverArt`
antes de esta ronda. `scripts/build-app.sh` verificado contra un
directorio temporal (Release).

Commit local, sin push -- misma razón que las Fases 0-2: push/release
esperan confirmación directa del dueño.

## ST-162 — El recorte cuadrado de una foto con orientación EXIF salía rectangular: escalar y recortar no viven en el mismo espacio

Encontrado por la comprobación 25 de `studio/windows/tools/ImageResizerCheck`
("EXIF orientación 6 → cuadrada de 200"): devolvía **100×200**. 38 PASS / 1
FALLA con `dotnet run --project studio/windows/tools/ImageResizerCheck -c Release`.

No es un caso de laboratorio: cualquier foto vertical de cámara viene guardada
horizontal con la rotación en EXIF, y esta es la primitiva con la que se
generan `cover.jpg` (320), las fotos de artista (128) y la copia local de
`.portadas/` (contrato v18, ST-140/ST-141). Una carátula elegida desde una foto
así llegaba al iPod deformada — o, más exacto, no cuadrada.

### Diagnóstico

`ImageResizer.EncodeSquareAsync` le da al decodificador de WIC dos cosas a la
vez: `ScaledWidth`/`ScaledHeight` y un `Bounds` de recorte. **No viven en el
mismo espacio de coordenadas**, y el código las calculaba como si sí:

- `ScaledWidth`/`ScaledHeight` se interpretan en las medidas **crudas** (las del
  archivo). El escalado ocurre **antes** de aplicar la orientación EXIF.
- `Bounds` cae sobre la imagen **ya orientada**, o sea después.

Con la foto de la prueba —400×200 en el archivo, 200×400 a la vista— el plan
salía así: lado corto 200, sin escalado (400×200 se queda igual), y el recorte
se calculaba sobre esas medidas crudas: `x=100, y=0, 200×200`. Pero WIC lo
aplica sobre la imagen orientada, que ahí mide **200 de ancho**: desde x=100
solo quedan 100 píxeles. WIC recorta lo que hay y sale 100×200.

El comentario del código afirmaba justamente lo contrario —"un cuadrado centrado
es el mismo antes y después de la orientación EXIF […] da igual en qué espacio
lo aplique WIC"—. Es cierto que el centro no se mueve al girar; lo que no es
cierto es que las coordenadas del cuadrado sean las mismas: al intercambiarse
los lados se intercambian también el margen horizontal y el vertical. `x=100,
y=0` tenía que ser `x=0, y=100`.

La comprobación 9 (el camino **no** cuadrado, con la misma foto) pasaba y sirvió
de referencia: ahí `EncodeAsync` solo escala, y como el factor de escala es el
mismo en los dos espacios, nunca se nota la diferencia. El bug necesita las dos
operaciones juntas.

### Arreglo

`SquareCropTransform` (nuevo, `AuraStudio.Core/Library/`) toma las medidas
crudas, las orientadas y el lado pedido, y devuelve **cada número en su
espacio**: `ScaledWidth`/`ScaledHeight` en crudas, `CropX`/`CropY`/`CropSide` en
orientadas. La aritmética del cuadrado sigue siendo la de `SquareCropPlan` —lado
corto, recorte al centro, nunca agrandar—; lo único que se agrega es en qué
espacio va cada cosa:

```
bool swapsSides = orientedWidth != rawWidth || orientedHeight != rawHeight;
(cropSpaceWidth, cropSpaceHeight) = swapsSides ? (scaledHeight, scaledWidth)
                                               : (scaledWidth, scaledHeight);
```

`EncodeSquareAsync` quedó como traductor: pide el plan y lo copia a
`BitmapTransform`. Las 20 líneas de aritmética que tenía adentro —que era donde
estaba el error y donde nadie podía probarlas— ya no están ahí.

Las cuatro orientaciones que giran (EXIF 5 a 8) se tratan igual, y es correcto:
al recorte solo le importa **si los lados se intercambian**, no hacia dónde
quedó la foto. Detectarlo comparando medidas orientadas contra crudas cubre las
cuatro sin leer la etiqueta, y para una fuente ya cuadrada da `false`, que es lo
que corresponde (no hay nada que intercambiar).

### Pruebas

`tests/AuraStudio.Core.Tests/SquareCropTransformTests.cs` — 13 pruebas (8 casos
más 6 de tamaños inutilizables). La que resume el bug es
`TheCropAlwaysFitsInsideTheOrientedImage`: el cuadrado tiene que caber entero
dentro de la imagen sobre la que cae (`CropX + CropSide <= ancho`,
`CropY + CropSide <= alto`) — eso era exactamente lo que ST-162 violaba, y por
eso WIC entregaba un rectángulo. `TheSameImageRotatedGivesTheSameCropOnTheOtherAxis`
fija el par simétrico: 300×1200 sin rotación y 1200×300 con ella dan el **mismo**
recorte, con el escalado invertido.

- Con la regla vieja puesta a la fuerza (`swapsSides` fijo en `false`), **fallan
  3 de las 13**, incluidas esas dos. Distinguen el arreglo, no solo lo acompañan.
- Suite completa: **1188/1188** (1175 antes + 13).
- `ImageResizerCheck`: **40/40** (39 antes + 1 nueva).
- `dotnet build AuraStudio.App -c Release -p:Platform=ARM64`: verde, 0
  advertencias, 0 errores.

**Comprobación 25b, nueva**: la misma foto con orientación **8** (gira para el
otro lado, también intercambia los lados) tiene que dar 200×200. Va de punta a
punta y no como prueba unitaria a propósito: en `SquareCropTransform` la 6 y la
8 son literalmente la misma entrada —las mismas medidas orientadas—, así que una
prueba unitaria que las comparara compararía dos llamadas idénticas y no
afirmaría nada. Lo que sí podía tratarlas distinto es el decodificador, y eso
solo se ve ejecutándolo. No las trata distinto: pasa.

De paso, esa comprobación confirma el orden que WIC no documenta con claridad y
que este arreglo asume: **escala, orienta, recorta**. Si algún día cambiara, las
dos comprobaciones de orientación lo dicen en la primera corrida.

## Addendum a ST-155 — punto 1: `CatalogPersister`, guardado programado ≤ 500 ms

La supervisora no aceptó diferir el punto 1: el guardado de ~1 s en el
hilo principal por cada edición individual (una estrella, una
categoría) es una causa directa del congelamiento, separada de la de
selección múltiple que ST-155 ya había resuelto. Implementado con el
patrón exacto que pidió, evitando romper las pruebas que asumían
`persistCatalog()` síncrono.

### `CatalogPersister` (nuevo, `Services/CatalogPersister.swift`)

`@MainActor`, con un `Snapshot` `Sendable` (copiar `items`/`playlists`
es barato -- son arreglos de valor con copy-on-write, no arrastran el
costo de sus 12 000 elementos solo por asignarse). Tres formas de
guardar:

- **`schedule(_:apply:)`**: programa un guardado ≤ 500 ms después de la
  última llamada -- una llamada nueva reemplaza la pendiente y reinicia
  el reloj, así que varias ediciones rápidas seguidas terminan en UN
  guardado real. Cuando el debounce expira, `flush(_:)` hace la
  escritura en un `Task.detached(priority: .utility)`.
- **`flush(_:)`**: guardado inmediato de lo pendiente, sin esperar el
  debounce, pero la escritura sigue fuera del hilo principal.
- **`flushSynchronously(_:)`** / **`writeNow(_:)`**: escritura
  inmediata Y bloqueante, en el actor que llama -- para salir de la app
  o pasar a segundo plano (un `Task.detached` que sigue corriendo
  cuando el proceso ya murió no sirve ahí) y para
  `isSynchronousForTesting`.

### `LibraryViewModel`: qué cambió y qué NO

`persistCatalog()` **sigue siendo exactamente el mismo guardado
inmediato y síncrono de siempre** -- ahora delega en
`catalogPersister.writeNow(_:)`, mismo código de escritura, mismo
comportamiento observable. Ningún llamador existente (los ~27 que no
son `setRating`/`setCategory`) se tocó ni necesita cambios.

`schedulePersistCatalog()` (nuevo) es lo que usan ahora **solo dos
sitios**, los que la supervisora señaló textualmente como el ejemplo
del congelamiento por edición individual: `setRating(_:forItem:)` y
`setCategory(_:forItems:)` (de la que `setCategory(_:forItem:)` ya
delegaba, así que también quedó cubierto). El resto de los ~27
llamadores de `persistCatalog()` (`addDroppedFiles`,
`clearCoverArt(ids:)`, `deleteItems`, `applyBatchEdit`, `applyReview`,
etc.) se dejaron sin tocar a propósito: son o bien acciones en lote
(ya arregladas en ST-155) o ediciones donde una garantía inmediata de
"ya quedó en disco" importa más que el ahorro de un guardado
(`applyReview` viene de una hoja modal que se cierra al guardar, por
ejemplo).

`flushPendingPersistence()` (nuevo): guardado inmediato y síncrono,
para cuando la app sale o pasa a segundo plano -- pendiente de
conectar a `NSApplication`/`AppDelegate` en un paso siguiente (no se
hizo en esta pasada; el mecanismo ya existe, falta el enganche a los
eventos del ciclo de vida de la app).

`makePersistenceSynchronousForTesting()` (nuevo, solo pruebas): pone a
`catalogPersister.isSynchronousForTesting = true`. **Auditoría
completa antes de escribir una sola línea**: un fork de investigación
buscó en TODO `Tests/AuraStudioTests/` qué pruebas dependen de que
`persistCatalog()` complete sincrónicamente (patrón "mutar con un
ViewModel A, construir un ViewModel B sobre el mismo `libraryRoot`,
verificar sin esperar nada"). La lista que había pasado la supervisora
(`LibraryLegacyMigrationTests`, `SharedCatalogInteropTests`,
`CoverArtAssetsTests`) resultó ser **incorrecta** -- ninguna de esas
tres llama a un método mutador; solo escriben `biblioteca.json` a mano
como fixture antes de probar la CARGA. Las que sí dependen del patrón
son dos pruebas de `LibraryViewModelLocalTagRereadTests.swift`
(`testOfferAppearsOnceForExistingLibraryWithMusic`,
`testAcceptingOfferRereadsAllMusicRespectingManualEditsAndDismisses`),
pero ninguna de las dos necesitó cambios: mutan vía `addDroppedFiles`/
`applyReview`, que siguen llamando al `persistCatalog()` síncrono de
siempre, nunca al nuevo `schedulePersistCatalog()`. **779/779 en verde
sin tocar ningún archivo de prueba** -- la auditoría confirmó que la
elección conservadora de solo migrar dos llamadores (en vez de los ~27)
evitó toda la superficie de riesgo que preocupaba.

### Medido

`testSetRatingMainThreadCost` (nuevo, sin `isSynchronousForTesting` --
mide el camino de producción real): **~3 ms promedio** (2.3-7.8 ms) en
el hilo que llama, contra el objetivo pedido de <10 ms. Antes de este
addendum, `setRating` bloqueaba el hilo principal por el mismo ~1 s que
medía la prueba (c) de ST-152/155, en cada estrella.

### Verificación

`swift build`, `xcodebuild` (Debug, Swift 6 estricto) y `swift test`:
780/780 en verde. `scripts/build-app.sh` verificado contra un
directorio temporal (Release).

## ST-164 — Windows sin botón para cancelar la normalización de carátulas (paridad con ST-141 de macOS)

### Qué faltaba

`LibraryViewModel` (ST-141) ya traía todo lo necesario para cancelar la
migración que deja cuadradas las carátulas de una biblioteca vieja:
`IsNormalizingCovers` (observable), `CancelCoverNormalization()`, y el
mensaje de cierre "Se detuvo la normalización de carátulas. Lo que
falte sigue la próxima vez." en `StatusMessage`. Lo único que faltaba
era el XAML: las cuatro páginas de biblioteca (Artistas, Álbumes/
cuadrículas, Canciones, Listas) mostraban `Library.StatusMessage` en un
`TextBlock` suelto, sin ningún control para detener la pasada en curso
— macOS sí lo tiene desde ST-141.

### Por qué un control compartido

Las cuatro páginas ya repetían el mismo `TextBlock` bindeado a
`Library.StatusMessage`, cada una en un `Grid` de columnas distinto
(`ArtistsPage`: `*,Auto`; `MediaGridPage`: `Auto,Auto,*`; `SongsPage`:
`Auto,*`; `PlaylistsPage`: sin columnas, un solo `TextBlock` en un
`Border`). En vez de repetir el mismo par TextBlock+Button cuatro
veces, `Controls\LibraryStatusStrip.xaml(.cs)` es un `UserControl` con
una única `DependencyProperty Library` (tipo `LibraryViewModel`) y, por
dentro, el `TextBlock` de siempre más un `Button` "Cancelar" cuya
`Visibility` sigue a `Library.IsNormalizingCovers` (con
`BoolToVisibilityConverter`, el mismo que ya usan las páginas) y cuyo
`Click` llama `Library.CancelCoverNormalization()`. Ninguna de las
cuatro sustituciones resultó invasiva: en las tres primeras
`StatusMessage` ya vivía en su propia celda de `Grid`, y en
`PlaylistsPage` el control reemplaza el `TextBlock` suelto sin tocar el
resto del layout. El botón queda `Collapsed` (ancho cero) fuera de una
normalización, así que el caso normal — sin nada que cancelar — se ve
exactamente igual que antes.

`AutomationProperties.Name` del botón: "Cancelar la normalización de
carátulas".

Sin tocar `AuraStudio.Core` ni `LibraryViewModel`: todo lo que hacía
falta ya estaba expuesto desde ST-141.

### Verificación

- `dotnet build AuraStudio.App -c Release -p:Platform=ARM64`: **0
  advertencias, 0 errores** (el proyecto tiene
  `TreatWarningsAsErrors`).
- `dotnet test studio\windows\tests\AuraStudio.Core.Tests -c Release`:
  **1188/1188** (no cambia con esto; se corrió para confirmar que
  seguía en verde).
- **En vivo, contra una biblioteca de fixtures** (nunca la real del
  dueño en `V:\Mac Externo\Documents\Aura Library`): se generó una
  biblioteca sintética de 8000 canciones con carátulas 4:3 sin marcar
  `coversNormalized`, apuntando `Ajustes › Biblioteca` ahí solo durante
  la prueba. Con la app abierta en Canciones, la franja mostró
  "Normalizando carátulas… N de 8000" con el botón "Cancelar" visible y
  habilitado; al invocarlo, el mensaje cambió de inmediato a "Se detuvo
  la normalización de carátulas. Lo que falte sigue la próxima vez." y
  el botón desapareció (`docs/capturas/st164-normalizacion-cancelar.png`
  y `st164-normalizacion-cancelada.png`, tomadas contra la ventana real
  con `PrintWindow`). Se revisaron también Álbumes, Artistas y Listas
  tras la cancelación: la franja se ve igual en las cuatro, sin huecos
  ni corrimientos.
- Antes de tocar `Ajustes › Biblioteca`, se respaldó
  `%LOCALAPPDATA%\Aura Studio\preferences.json`; al terminar se
  devolvió `LibraryPath` a `V:\Mac Externo\Documents\Aura Library` y se
  comprobó **byte a byte** contra el respaldo que quedó idéntico. La
  biblioteca de fixtures y la herramienta que la generó vivieron fuera
  del repo (carpeta de trabajo de la sesión) y se borraron al cerrar la
  fase.

## ST-159 — Fotos de artista al iPod: 128×128 → 320×320 (contrato v20)

Encargo del dueño, confirmado directamente: mismo formato exacto que ya
usa `cover.jpg` desde v1.5 del contrato de biblioteca (D-349) —
`aura_master_art.c` sigue derivando su caché maestra a 130×130 sin
cambios (§D.5 del contrato no se toca), esto solo le da a Studio más
resolución de origen para escribir.

`CONTRATO-firmware-studio.md` reemplazado entero por la copia canónica
de `Aura-Firmware` (commit `f4ec59af`, v20), verificado con `cmp` y
SHA-256 idéntico en los dos repos.

`LibrarySync.deviceArtistSide` pasa de `128` a `320`
(`Services/LibrarySync.swift`) — la única constante que hacía falta
tocar; `writeArtistImages` ya llama `ImageResizer.squareCrop(data:side:)`
con ella, y la comparación por bytes contra lo que ya hay en el iPod
(`existing != square`) hace sola la migración: la primera sincronización
tras esta versión encuentra que la foto vieja de 128 nunca es igual a la
nueva de 320, así que la reescribe; no hizo falta ningún código de
migración aparte.

Dos pruebas actualizadas para seguir la constante en vez de un número
suelto (así no quedan desactualizadas la próxima vez que cambie el
contrato): `ArtistImageExportTests.testExportedImageIsResizedToAtMost128px`
→ `testExportedImageIsResizedToDeviceArtistSide` (medía `<=128`, ahora
`== LibrarySync.deviceArtistSide`) y
`LibrarySyncSquareCoversTests.testTheArtistPhotoArrivesSquareAtOneHundredAndTwentyEight`
→ `testTheArtistPhotoArrivesSquareAtDeviceArtistSide` (el cuerpo ya
usaba la constante; solo el nombre había quedado desactualizado).

### Verificación EXIF-6, en macOS

Windows encontró y corrigió (ST-162) un bug real en su `EncodeSquareAsync`
de WIC: mezclaba el espacio de coordenadas crudo (antes de aplicar la
orientación EXIF) con el orientado (después), y una foto vertical
guardada horizontal con rotación EXIF salía rectangular en vez de
cuadrada. En macOS, `ImageResizer.squareCrop` usa
`CGImageSourceCreateThumbnailWithTransform`, que orienta ANTES de que el
código de Studio calcule el recorte -- **ya no era un bug por corregir,
era una propiedad por confirmar con una prueba real**, y ya existía:
`ImageResizerSquareCropTests.testAPhotoWithExifOrientationIsCroppedOnWhatIsSeen`
(400×200 crudo con orientación EXIF 6, se ve 200×400, se recorta a
200×200 -- el lado corto de lo que se VE, no de lo crudo). Corrida de
nuevo para esta ronda: pasa. No hizo falta escribir ninguna prueba
nueva, solo confirmar que la que ya había cubre exactamente el
escenario que preocupaba.

### Verificación

`swift build`, `xcodebuild` (Debug, Swift 6 estricto) y `swift test`:
780/780 (1 saltada, red -- fluctuación de entorno). `scripts/build-app.sh`
verificado contra un directorio temporal (Release).

No se tocó ningún archivo de `studio/windows/` (ST-163, la paridad en
Core, es trabajo de la sesión de Windows). No se subió la versión —
ST-159 sale como parche `0.2.1` en una unidad de trabajo aparte, cuando
el dueño autorice ese release; este commit es solo el cambio de código
y contrato.

## ST-165 — Windows: la hora del iPod no se sembraba al terminar de instalar o actualizar el firmware (tercera pata de ST-146)

### Qué faltaba

El contrato §D.4 (sembrar `aura.cfg` con la hora/zona de la computadora
para que el primer arranque ya la traiga en hora) tenía dos de sus tres
patas en Windows: `DeviceSessionService.SyncClockIfConnected` (al
conectar el iPod) y `FirmwareSwitcher.SwitchActiveFirmware` (al cambiar
de familia) ya llamaban `ClockSyncWriter.WriteToDisk(volumeRoot)`, las
dos probadas. Faltaba la tercera: justo después de copiar los archivos
del firmware al iPod (instalación por primera vez o actualización
directa), simétrico a `InstallerViewModel.swift:1214` de macOS —ahí la
llamada vive justo después de crear las carpetas de medios y antes de
decidir si toca DFU o el flujo ya terminó, con el mismo candado de
escritura tomado—.

### Dónde, y por qué ahí y no en el ViewModel

macOS hace la llamada directo en el `ViewModel`. En Windows el camino
real de copia (`InstallerViewModel.CopyFilesAsync`, usado tanto por el
asistente como por `UpdateInPlaceAsync` para la actualización directa)
delega **todo** el trabajo de escribir el árbol —binario raíz, extracción
selectiva o completa del zip, manifiesto v11, carpetas de medios,
identidad de familia (ST-067)— en `FirmwareTreeWriter.WriteAsync`
(`AuraStudio.Core.Installer`), que ya es la pieza **decidible y
probada** que hace ese trabajo sin ninguna API de Windows. Ahí es donde
vive la llamada nueva a `ClockSyncWriter.WriteToDisk(volumeRoot)`, justo
antes de reportar "Listo." — al lado de los otros pasos que ST-067/v11
ya trataban como mejoras que no invalidan un firmware ya escrito y
verificado por centinela (el resto de esos pasos van envueltos en
`TryIgnoringIo`; este no hace falta porque `ClockSyncWriter.WriteToDisk`
ya captura sus propias excepciones de E/S y devuelve `false`).

Poner la llamada en `FirmwareTreeWriter` en vez de en
`InstallerViewModel.cs` cubre **las dos** rutas (asistente y
actualización directa) con una sola línea, y la deja alcanzable por una
prueba unitaria real —cosa que `InstallerViewModel.cs`, atado a WinUI,
`IDfuFlashRunner` y al resto de la sesión del dispositivo, no ofrece sin
inventar mocks para todo el instalador—.

### Por qué es silencioso si `aura.cfg` no existe todavía

Una instalación **de verdad la primera vez**, antes de que el firmware
haya arrancado una sola vez, no tiene `aura.cfg` en el disco —lo crea el
propio firmware al primer arranque, no el zip—. `ClockSyncWriter.WriteToDisk`
ya estaba diseñado para ese caso: no crea el archivo a medias, devuelve
`false` y no hace ruido. La hora queda sembrada de todos modos en la
próxima conexión (`DeviceSessionService`), que es el camino que sí
puede ver el firmware ya corrido. Donde esta pata sí actúa siempre es en
`UpdateInPlaceAsync` (actualizar sin formatear ni entrar a DFU): ahí el
árbol "ya arrancó una vez" por definición, así que `aura.cfg` ya existe
y la hora se refresca en el mismo momento en que se termina de escribir
el firmware nuevo — sin esperar una reconexión.

### Verificación

- `FirmwareTreeWriterTests.cs` (nuevo, `AuraStudio.Core.Tests`): dos
  pruebas contra un volumen de mentira (una carpeta temporal, no un
  iPod) y un juego mínimo de artefactos que pasa
  `ArtifactVerificationResult` de `ArtifactScope.FirmwareTree`. Con
  `aura.cfg` sembrado de antemano (el caso real de `UpdateInPlaceAsync`),
  `FirmwareTreeWriter.WriteAsync` deja `rtc_sync_year:` en el archivo sin
  tocar el resto de sus líneas; sin `aura.cfg` de antemano (primera
  instalación), termina igual de bien y no crea el archivo.
- `dotnet test tests\AuraStudio.Core.Tests -c Release` → **1190/1190**
  (1188 + las 2 nuevas).
- `dotnet build AuraStudio.App -c Release -p:Platform=ARM64` → 0
  advertencias, 0 errores.
- No se verificó contra un iPod real ni contra DFU: esta sesión no tiene
  uno conectado. La pieza que cambió es exclusivamente de Core
  (`FirmwareTreeWriter`, sin ninguna API de Windows) y la prueba nueva
  ya la ejercita con exactamente el mismo código que corre en la
  instalación real, contra un volumen de mentira — es la verificación
  equivalente a un volumen simulado que pedía el encargo, hecha con
  xUnit en vez de a mano. Falta, y queda para el dueño con hardware
  real: confirmar que un iPod recién flasheado por DFU (instalación
  desde cero, sin `aura.cfg` previo) trae la hora correcta en su
  **segunda** conexión, y que una actualización directa sobre un iPod
  ya corriendo Aura la trae correcta de inmediato, en la primera.

## ST-156 — PLAN-studio-rendimiento.md, Fase 4: centro de tareas en segundo plano (parcial)

La supervisora la señaló como "el encargo central del dueño: nada largo
sin indicador". El alcance completo del plan (actor `LibraryFileWorker`
fuera de main, migrar ~12 operaciones, `setRating` sin reescribir el
archivo en el acto) es la unidad de trabajo más grande de toda esta
ronda -- tocar `prepareMusic`/ID3 de punta a punta sin poder verificarlo
interactivo es un riesgo real de dejar algo roto en un flujo que
escribe archivos del usuario. Esta PARADA entrega la base, sólida y
probada, más UNA integración real de punta a punta -- el resto queda
listado al final, explícito, para otra pasada.

### Hecho

**`BackgroundTaskCenter`** (nuevo, `Services/BackgroundTaskCenter.swift`):
`@MainActor ObservableObject` con una cola de `TaskHandle` (título en
español, progreso `.determinate(completed:total:)`/`.indeterminate`,
texto de estado, error, cancelar opcional). Cada `TaskHandle` es su
propio `ObservableObject` -- actualizar el progreso de una tarea
publica `objectWillChange` de ESA fila, no del centro entero ni de la
ventana. `aggregateFraction` promedia solo las tareas determinadas,
para el anillo agregado de la barra de herramientas. 9 pruebas nuevas
(`BackgroundTaskCenterTests.swift`).

**UI** (`BackgroundTaskCenterIndicator.swift`, nuevo): botón en la barra
de herramientas, invisible sin ninguna tarea corriendo (nunca ocupa
espacio de más); con tareas, anillo de progreso + "N tareas", y un
popover que lista cada una con su progreso y Cancelar -- mismo patrón
que la ventana de copia del Finder / la actividad de Xcode, como pedía
el plan.

**Primera integración real**: `reenrichOnline` (buscar información en
línea / letra) ahora reporta "N de M" al centro en vez de solo dejar un
resumen al final. Elegida a propósito como primer caso: ya era `async`,
ya iteraba con un contador (`attempted`), y no toca `prepareMusic`/ID3
-- el camino de menor riesgo para probar el centro contra código real
antes de migrar algo más delicado.

### Qué queda explícitamente afuera de esta PARADA

- **`LibraryFileWorker`** (actor fuera de main para copiar/transcodificar/
  recortar carátula/escribir ID3/leer etiquetas/borrar): no escrito.
  Es el cambio que de verdad saca `prepareMusic` del hilo principal
  (diagnóstico §0.5) -- requiere convertir sus ~6 llamadores
  (`setRating`, `clearCoverArt`, `applyAlbumCover`, `applyBatchEdit`,
  `applySimilarityEdits`, `reenrichOnline`) a un patrón async con
  resultados por lote, no uno por ítem.
- **Las otras ~11 operaciones del punto 3** (edición en lote, aplicar
  carátula, similares, releer etiquetas, fotos de artista, pósters,
  carátulas recomendadas, eliminar, verificar dispositivo, carga
  inicial) siguen con sus booleanos sueltos de siempre
  (`isProcessing`, `isFetchingArtistImages`, `isVerifyingDevice`,
  `isFetchingVideoPosters`, `isApplyingRecommendedCovers`, el
  `@State isEnriching` de `MediaSectionView`) -- no se tocó ninguna.
- **`setRating` sin reescribir el archivo en el acto**: sigue llamando
  `prepareMusic` sincrónico en cada estrella (el guardado del catálogo
  ya no bloquea, desde el addendum de ST-155, pero el re-etiquetado
  ID3 sí sigue ahí). Depende de que exista `LibraryFileWorker` primero.
- **Límites de concurrencia por tipo** (disco: 1; red: limitador de
  MusicBrainz; CPU: núcleos disponibles): `BackgroundTaskCenter` por
  ahora es solo visibilidad/cancelación, no gatekeeping -- no hay
  ninguna operación real routeada por un worker común todavía contra
  la cual aplicar un límite con sentido.

### Verificación

`swift build`, `xcodebuild` (Debug, Swift 6 estricto) y `swift test`:
789/789 en verde (9 pruebas nuevas de `BackgroundTaskCenterTests`).
`scripts/build-app.sh` verificado contra un directorio temporal
(Release). El vigilante de hilo principal contra una edición en lote de
500 ítems y una importación de 1000 archivos (el criterio de cierre que
pide el plan) queda pendiente hasta que exista `LibraryFileWorker` --
sin él, esas dos operaciones siguen bloqueando el hilo principal
exactamente igual que antes de esta PARADA, así que medirlas ahora no
diría nada nuevo.
