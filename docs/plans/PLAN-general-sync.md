# PLAN-general-sync.md — "Actualizar" vs. "Sincronizar", barra persistente, cancelación segura, nombre del iPod

> **ESTADO: ACTIVO — en ejecución.** Aprobado por el dueño (2026-08-17) con las recomendaciones P1–P13. La Fase 2 avanza en cuatro tandas (§12): **tanda 1 (motor: sync transaccional, cancelación, manifiesto v2) hecha — ver `ST-008` en `DECISIONS.md`.** Pendientes: tanda 2 (UI — `DeviceActivityBar`, separación de "Actualizar"/"Sincronizar", alcance segmentado, hoja de conflictos), tanda 3 (`DeviceSyncIndex` — los 5 estados por elemento, columna de estado, hoja "Solo en el iPod"), tanda 4 (nombre del dispositivo — `CONTRATO-dispositivo.md`, `device.cfg`, edición in-place). La fuente de verdad de lo ya decidido es `DECISIONS.md`, no este documento.

Rutas de código relativas a `studio/AuraStudio/Sources/AuraStudio/` salvo indicación; las del firmware, a `/Volumes/Ricolinos/Codigo/GitHub/Aura/Aura-Firmware/`.

---

## 0. Resumen ejecutivo

| Tema | Veredicto en una línea |
|---|---|
| **0.1 Semántica** | **Modelo aditivo con propiedad**: Studio solo crea/actualiza/borra lo que él mismo escribió (lo que consta en `sync_manifest.json`); jamás toca lo ajeno; **nunca borra sin confirmación**. Los cambios externos se **detectan y se muestran**, y sincronizar los resuelve con la biblioteca como autoridad **solo previa confirmación por lote**. Un borrado hecho a mano en el iPod se **respeta** (no se vuelve a copiar en silencio). |
| **0.2 Metadatos** | El bug está **cerrado** (ST-007, tanda 1 de `PLAN-studio-ux.md`): `LocalTagReader` lee todos los formatos y existe "Volver a leer etiquetas del archivo". Este plan **no depende de nada abierto**; solo hereda una precaución (§2). |
| **0.3 Código** | Botón único "Sincronizar" en la barra de la ventana (`Views/ContentView.swift:70-85`) → `LibraryViewModel.sync(toVolumeAt:)` (`:638-679`, `Task.detached` sin cancelación) → `LibrarySync.sync()` (`Services/LibrarySync.swift:147-266`: diferencial por manifiesto, copia **directa al destino final**, manifiesto guardado **solo al final** `:250`, `.tcd` borrados al final `:263`). Estado del dispositivo: `IPodMonitor.device/state` + `AuraDeviceProbe`. "Sincronizado" ya existe pero es **incompleto**: `MediaSectionView.refreshSyncedItems()` (`:339-350`) = registro en manifiesto + destino existe, **sin comparar tamaño/fecha** — una canción editada después de sincronizar sigue diciendo "Sincronizado". |
| **0.4 Detección** | Índice por dispositivo = el `sync_manifest.json` que ya vive en el iPod, **extendido** con la huella del destino (`destinationSize`/`destinationModifiedAt`) y un `contract_version`. Estado por elemento en 5 valores; verificación = 1 `stat` por registro + 1 recorrido de `Music/`/`Videos/`/`Photos/` (para "solo en el iPod"), fuera del hilo principal, cacheado en memoria (`DeviceSyncIndex`) e invalidado por: conexión, fin de sync/cancelación, "Actualizar", y (solo el lado local) cualquier edición que reescriba `.preparados/`. |
| **1.1 "Actualizar"** | Se separa en tres cosas con tres nombres: **"Actualizar"** (barra de la ventana; refresco inofensivo, nunca escribe), **"Buscar actualizaciones de Aura"** (General → sección Aura; consulta) e **"Instalar actualización de Aura"** (el único disparador de instalación, ST-006, hoy "Actualizar Aura"). "Sincronizar" vive en General junto a la barra, más un comando de menú `Archivo → Sincronizar con el iPod` (⇧⌘S) para no perder el acceso desde Música/Video/Fotos que D-202 había resuelto con el botón global. |
| **1.2 Alcance** | Control segmentado (radio) "Toda la biblioteca / Solo la selección (N)"; con N = 0 la segunda opción y el botón quedan deshabilitados con explicación. La selección se comparte entre vistas vía `LibraryViewModel.selectionForSync`. |
| **1.3 Barra** | Una sola `DeviceActivityBar` siempre visible en General con 6 estados; en reposo **muestra el uso de almacenamiento** (reutiliza `StorageBarView`, D-216) — se adopta la idea: informativa en vez de "0 % atascado", y coherente con la barra de "Acerca de" del firmware. |
| **1.4 Cancelación** | Copia por bloques a `.aura-tmp-<archivo>` + `rename` atómico; cancelación en frontera de bloque/archivo; **manifiesto guardado tras cada archivo** (hoy solo al final); marcador `.rockbox/aura/sync_in_progress`; barrido de temporales huérfanos al iniciar; el índice del firmware (`.tcd`) solo se invalida al cerrar limpio (también al cancelar, para lo ya copiado). Desconexión física = cancelación no solicitada por el mismo camino. Pausar conserva progreso y estado; cancelar cierra limpio. |
| **1.5 Nombre** | Default `iPod de <NSFullUserName()>` (fallback `NSUserName()`, luego `iPod`). Vive **en el dispositivo**, en un archivo propio de Studio `.rockbox/aura/device.cfg` (contrato nuevo `CONTRATO-dispositivo.md`, versionado, formato `clave: valor` que el firmware ya parsea), no en `aura.cfg` (que el firmware regenera entero) ni en la etiqueta FAT32 (11 caracteres). 32 caracteres / 48 bytes, derivados de la fuente y el buffer reales del firmware (§9). El firmware hoy muestra el literal "Mi iPod" en "Acerca de" — ese es el slot que consumiría el nombre. |
| **1.6 Columna** | La columna "Estado" **no aparece ni desaparece**: siempre está; con iPod conectado sus valores cambian de "Listo" a los 5 estados de sincronización. Estilo plano, símbolo + texto, sin fondos ni translucidez. |

---

## 1. Fase 0.1 — Semántica de la sincronización (decisión bloqueante)

### 1.1 Lo que hace hoy el código (verificado)

- **Aditivo de facto, sin decirlo**: `LibrarySync.sync()` copia lo que `SyncPlanner` marca `.copy` (`Services/LibrarySync.swift:201-248`); **nunca borra** en el iPod salvo un caso: el archivo viejo cuando el destino de un mismo origen cambió de ruta (`staleDestinationRelativePath`, `:213-215`, D-066 — reorganización `Music/` plana → `Artista/Álbum`). Elementos que el usuario **quitó de la biblioteca** siguen en el iPod y en el manifiesto para siempre (`manifest.records` nunca se poda). Archivos que el usuario copió a mano al iPod son invisibles para Studio.
- **Cambios externos**: no se detectan. El manifiesto guarda tamaño/fecha del archivo **preparado** (`SyncRecord.sourceSize/sourceModifiedAt`, `:9-14`) y nada del destino; si el usuario reemplaza o re-etiqueta un archivo en el iPod con otra herramienta, Studio no lo sabe y en el próximo sync **no lo toca** (el diferencial solo mira el lado local) — el cambio externo sobrevive por accidente, no por diseño.
- **Borrado externo**: si el usuario borra una canción del iPod a mano, `refreshSyncedItems()` deja de marcarla "Sincronizado" (`:346-349`) y la columna vuelve a decir "Listo"; pero `SyncPlanner` solo compara el lado local con el manifiesto (`:54-60`), donde el registro sigue intacto → `.skip`: el siguiente sync **no la vuelve a copiar y tampoco lo reporta**. Queda como "Listo" para siempre sin estar en el iPod — la ambigüedad exacta que el encargo pide resolver.
- **Índice del firmware**: Studio no escribe tagcache; borra `.rockbox/database_*.tcd` (`:527-538`) y el firmware reconstruye al arrancar (D-021/D-023).
- **Calificaciones**: una vía Studio → iPod (`writeRatings`, `:379-415`, D-199); la del aparato se pierde en el rebuild si difiere. Limitación conocida, no cambia aquí.

### 1.2 Modelo propuesto: **aditivo con propiedad** ("Studio manda sobre lo suyo, no toca lo ajeno, y no borra sin preguntar")

Regla de oro: **Studio solo escribe, sobrescribe o borra rutas que constan en `sync_manifest.json` como escritas por él**. Todo lo demás en el iPod es del usuario (o de otra Mac) y se respeta.

| Situación | Qué pasa al **Actualizar** (solo lectura) | Qué pasa al **Sincronizar** | ¿Confirmación? |
|---|---|---|---|
| Elemento nuevo en la biblioteca | "Pendiente" | Se copia | No |
| Elemento ya sincronizado y **sin cambios** | "Sincronizado" | Nada | — |
| Elemento **editado en Studio** después de sincronizar (metadata → `.preparados/` reescrito, o archivo de origen cambiado) | "Con cambios por sincronizar" | Se **reemplaza** en el iPod (es archivo de Studio; la biblioteca es autoritativa sobre lo suyo) | No |
| Archivo de Studio **modificado en el iPod** fuera de Studio (huella del destino ≠ la registrada) | "Modificado en el iPod" (indicador "cambios fuera de Aura Studio: N") | **No se toca por defecto.** El resumen previo al sync lo lista y ofrece **Reemplazar con la versión de la biblioteca** (autoritativa) o **Conservar los del iPod** (esta vez) | **Sí, por lote**, con la lista |
| Archivo de Studio **borrado en el iPod** a mano | "Quitado del iPod" | **No se vuelve a copiar** (se respeta la acción explícita del usuario en su aparato); el estado ofrece "Volver a copiar" por elemento, y el resumen previo "Volver a copiar los N quitados" | Sí (opt-in) |
| Elemento **quitado de la biblioteca** (o su origen ya no existe) que sigue en el iPod | "En el iPod, ya no en la biblioteca: N" (indicador) | **No se borra por defecto.** El resumen previo ofrece "Quitar del iPod los N elementos que ya no están en tu biblioteca" (**desmarcado** por defecto) | **Sí, explícita, destructiva** — lista visible, botón rojo |
| Archivo en `Music/`/`Videos/`/`Photos/` **que Studio nunca escribió** (Finder, otra Mac) | "Solo en el iPod: N" (indicador; hoja "Contenido solo en el iPod") | **Jamás se toca.** Acciones a demanda: "Importar a la biblioteca" (copia al Mac; lo vuelve elemento propio) o "Eliminar del iPod" (destructiva) | Eliminar: **sí**, siempre |
| Reorganización de rutas (cambio de `musicOrganization`) | "Con cambios por sincronizar (se moverá)" | Mueve (borra la ruta vieja **propia**, copia a la nueva) — como hoy (D-066) | No: mismo contenido, mismo dueño |
| Índice `.tcd` del firmware | — | Se borra al cerrar limpio para que Aura reconstruya (como hoy) | No: no es dato del usuario |

**Por qué este modelo y no espejo**: el espejo (iTunes clásico: "el iPod refleja la biblioteca, lo demás se borra") es el que destruye datos cuando el usuario cargó algo por otra vía o usa dos Macs; y la spec pide explícitamente *detectar* cambios externos, lo que solo tiene sentido si esos cambios importan. Aditivo con propiedad cumple las dos frases de la spec sin contradicción: la biblioteca es autoritativa **sobre los elementos existentes de la biblioteca**, y lo externo se detecta, se muestra y se resuelve **con el usuario**. Cabe en un iPod compartido entre dos Macs (cada Studio conoce sus propios registros — el manifiesto se hace por-máquina, ver §4) y no cambia nada de lo que ya funciona (D-066, D-199, D-202/D-215).

**Operaciones destructivas y su confirmación** (todas con `InstallerFlowRegistry.beginWriting()`, hoy `sync()` no lo toma — se agrega; y todas revalidando el punto de montaje justo antes, regla de `CLAUDE.md`):
1. **Reemplazar archivos modificados en el iPod** — hoja "Antes de sincronizar" con la lista (nombre, qué cambió: tamaño/fecha), radio "Reemplazar con la biblioteca / Conservar en el iPod", default **Conservar**.
2. **Quitar del iPod elementos que ya no están en la biblioteca** — misma hoja, casilla **desmarcada** por defecto, lista visible, texto: "Se eliminarán del iPod. Tu biblioteca en la Mac no cambia."
3. **Eliminar del iPod contenido que Studio nunca escribió** — solo desde la hoja "Solo en el iPod", con confirmación por elemento/lote y botón destructivo rojo.
4. **Nunca**: formatear, tocar `.rockbox/` fuera de `aura/`, borrar algo sin registro propio, o borrar durante "Actualizar".

Sin ninguna de esas tres condiciones, "Sincronizar" **no muestra hoja previa**: arrastrar y listo sigue siendo un clic.

---

## 2. Fase 0.2 — Dependencia del arreglo de metadatos

**Estado: cerrado.** ST-007 (`DECISIONS.md`) reemplazó `ID3Writer.readTag` por `Services/LocalTagReader.swift` en `LibraryEnricher.enrich()/reenrich()` (todos los formatos), agregó el umbral de MusicBrainz, `LibraryItem.metadataEditedByUser`, `LibraryViewModel.rereadLocalTags(ids:respectUserEdits:)` (acción "Volver a leer etiquetas del archivo") y el banner de biblioteca existente. 276 tests, 0 fallas.

Qué de este plan se apoyaba en eso y cómo queda:
- **"Actualizar metadatos"** de la spec = ya existe como acción explícita (`rereadLocalTags`). "Actualizar" (refresco) **no** relee etiquetas de todos los archivos automáticamente — sería lento y pisaría ediciones (P2 de aquel plan); en cambio detecta **archivos de origen cambiados** (tamaño/fecha del `sourceURL` ≠ los del último procesamiento) y los marca "Origen modificado — volver a leer" con un botón que sí llama a `rereadLocalTags`. Requiere guardar la huella del origen al procesar (`LibraryItem.sourceFingerprint`, nuevo, persistido).
- **Columna de estado**: depende de que `.preparados/` refleje la metadata correcta — hoy sí (`prepareMusic` corre tras cada edición y tras la relectura).
- **Precaución heredada**: la tanda 2 de `PLAN-studio-ux.md` (§1, `StudioStyle` plano) todavía no corrió; la columna y la barra de este plan se diseñan **con el mismo criterio plano** (§8) para que, cuando exista `StudioStyle`, sean una migración mecánica y no un rediseño. **Orden propuesto**: este plan puede ejecutarse **antes** de la tanda 2 de aquel (no comparte archivos con §1 salvo `MediaSectionView.statusCell`, y ambos convergen en el estilo plano) — ver P10.

---

## 3. Fase 0.3 — Estado actual del código (inventario)

| Pieza | Dónde | Qué hace hoy |
|---|---|---|
| Botón superior | `Views/ContentView.swift:70-85` — `ToolbarItem(placement: .primaryAction)`, etiqueta "Sincronizar" / `"\(copied)/\(total)"` durante el sync; deshabilitado sin iPod Aura, con `isProcessing` o con `syncProgress != nil` | Llama `syncNow()` (`:180-186`) → `library.sync(toVolumeAt:)` y `deviceMonitor.refreshDevice()`. Está en la raíz por D-202 (3): "que se pueda disparar desde Música/Video/Fotos". |
| Motor | `Services/LibrarySync.swift` — `SyncRecord/SyncManifest` (`:9-20`, clave `sourcePath`, huella del **preparado**), `SyncPlanner.plan` (`:49-71`, `.copy/.skip` + `stale`), `sync()` (`:147-266`): huellas + `CatalogSummary` (`:158-199`), plan (`:201`), copia **directa** con `removeItem` + `copyItem` al destino final (`:217-222`), poster (`:230-239`), manifiesto en memoria por archivo (`:242-247`) y **guardado una sola vez al final** (`:250`), portadas (`:252-254`), playlists (`:256`), `sync_summary.cfg` (`:259`), `ratings.cfg` (`:260`), `.tcd` (`:262-264`). Rutas: `musicDestinationRelativePath` (`:431-467`), `destinationRelativePath` (`:513-526`). | Diferencial por tamaño+fecha del preparado. Sin cancelación, sin candado, sin transacción por archivo. |
| Orquestación | `ViewModels/LibraryViewModel.swift:638-679` — `sync(toVolumeAt:)`: `Task.detached`, `onProgress` → `syncProgress` (`SyncProgress` `:88-94` de LibrarySync), `lastSyncSummary`/`lastError`. `SyncProgress` cuenta **archivos**, no bytes. | No toma `InstallerFlowRegistry.beginWriting()` (`Services/InstallerFlowRegistry.swift:34`), a diferencia de instalador y temas. |
| Estado del dispositivo | `Services/IPodMonitor.swift` — `@Published state: DeviceState`, `device: AuraDevice?`; `handleDiskChange` (`:76-89`), `refreshDevice()` (`:94-97`, re-sondea sin evento de DiskArbitration). `Models/DeviceState.swift` (`notConnected/detecting/diskMode/diskModeNoFilesystem/dfuMode/unknown`). `Models/AuraDevice.swift` (`volumeName`, `mountPath`, `firmware`, `capacityBytes/freeBytes`, `librarySummary`). `Services/AuraDeviceProbe.probe` (`:40-81`). | `volumeName` = etiqueta del volumen que reporta DiskArbitration (`DiskModeInfo.volumeName`) — es lo que `DeviceGeneralView.header` muestra en grande (`Views/DeviceGeneralView.swift:83`) y la barra lateral (`ContentView.swift:297`). No hay nombre editable. |
| Pantalla General | `Views/DeviceGeneralView.swift` — `header` (`:77-95`), `updateSection` (`:105-128`, banner "Actualización de Aura disponible" + botón **"Actualizar Aura"**), `capacity` + `StorageBarView` (`:147-161`, `:324-381`, D-216: rosa/azul/verde/naranja), `auraContents` (`:198-232`: conteos, `pendingLabel` `:261-265` "N archivo(s) preparado(s) esperando sincronizacion", `syncProgressSection` `:237-250` **solo mientras hay `syncProgress`**), toolbar "Expulsar" (`:61-73`). | La barra de progreso **aparece y desaparece** (D-217). |
| "Sincronizado" | `Views/MediaSectionView.swift` — `syncedSourcePaths` (`:64`), `refreshSyncedItems()` (`:339-350`: manifiesto + `fileExists` del destino), `statusCell` (`:456-494`: `.ready` → "Sincronizado" con `ipod` o "Listo"), refrescado en `onAppear`, cambio de `device`, cambio de `lastSyncSummary` (`:147-151`). D-202/D-215. | Ignora tamaño/fecha → **falso "Sincronizado"** tras editar metadata. No distingue "quitado del iPod" de "nunca copiado". |
| Actualizaciones de firmware | `Services/AuraUpdateChecker.checkForUpdate` (ST-006), disparado en `ContentView.refreshUpdateAvailability` (`:130-138`) al cambiar `device`; instalación **solo** por "Actualizar Aura" → `InstallerViewModel.startAutomaticUpdate()`. | Regla innegociable de ST-006: ese botón es el único disparador. |

---

## 4. Fase 0.4 — Estrategia de detección del estado de sincronización

### 4.1 Qué significa cada estado (por elemento de la biblioteca, con iPod conectado)

| Estado | Condición | Columna (texto) |
|---|---|---|
| `synced` | Hay registro propio; huella del **preparado** == registro; destino existe y su huella (tamaño + fecha de modificación **tal como quedó tras copiar**) == registro | "Sincronizado" |
| `pending` | Sin registro (nunca copiado a **este** iPod), o `status != .ready` | "Pendiente" |
| `changedLocally` | Registro existe pero la huella del preparado difiere (metadata editada, relectura, transcodificación nueva, cambio de organización) | "Con cambios" |
| `modifiedOnDevice` | Destino existe pero su huella ≠ la registrada | "Modificado en el iPod" |
| `removedFromDevice` | Registro existe, destino no existe | "Quitado del iPod" |

**"Sincronizado" cuando el archivo existe pero la metadata cambió en la biblioteca** = `changedLocally`. Nunca `synced`: la huella del preparado cambia porque `prepareMusic` reescribe la tag (`LibraryViewModel.swift:335-345`), y eso es exactamente lo que el sync debe volver a copiar. Es lo que hoy la columna hace mal.

Fuera de la tabla (indicadores en General): `orphanedOnDevice` (registro propio cuyo origen ya no está en la biblioteca) y `foreignOnDevice` (archivo bajo `Music/`, `Videos/`, `Photos/`, `Playlists/` sin ningún registro propio).

### 4.2 Índice cacheado

- **La fuente es el manifiesto que ya vive en el iPod** (`.rockbox/aura/sync_manifest.json`) — por diseño es por-dispositivo. Se extiende (`SyncManifest` v2, `contract_version: 2`, decodificación tolerante de v1: registros viejos sin huella de destino se tratan como `changedLocally` una vez y se rellenan en el primer sync — no se recopia si tamaño+fecha del destino coinciden con las del preparado): `SyncRecord` gana `destinationSize`, `destinationModifiedAt` (leídos **después** de copiar), `writtenBy` (id de esta Mac, `AppPreferences.installationID`, UUID persistido — para que dos Macs no se pisen registros: cada una solo considera propios los suyos, y ve los del otro como "de otra Mac", ni propios ni ajenos: no los reemplaza ni los borra), y `syncedAt`.
- **`DeviceSyncIndex`** (nuevo, `Services/`; struct + actor de cálculo): `[itemID: SyncState]`, `orphans: [SyncRecord]`, `foreign: [URL]`, `computedAt`. Se calcula fuera del hilo principal en una sola pasada: (a) 1 `attributesOfItem` por registro (una biblioteca de 5 000 canciones ≈ 5 000 `stat` por USB 2 — del orden de segundos, con progreso "Verificando el iPod…" en la barra), (b) 1 enumeración de `Music/`, `Videos/`, `Photos/`, `Playlists/` (`FileManager.enumerator`, sin leer contenido) para `foreign`; los `cover.jpg`/`.jpg` de poster/`.m3u8` propios se reconocen por convención de nombre, no se marcan ajenos.
- **Se invalida y recalcula** con: conexión del iPod (`IPodMonitor.device` no-nil), fin de un sync/cancelación, "Actualizar" (explícito), y "Sincronizar" (recalcula justo antes, siempre — nunca decide sobre un índice viejo). **El lado local** (huella del preparado vs. registro) se reevalúa sin tocar el iPod cada vez que un item cambia (`persistCatalog()`), así "Con cambios" aparece al instante al editar.
- Sin iPod: no hay índice; la columna vuelve a "Listo/En cola/Revisar".

---

## 5. Fase 1.1 — Separar las tres cosas que la spec llama "Actualizar"

| Acción | Nombre en pantalla | Dónde | Efecto | Riesgo |
|---|---|---|---|---|
| Refrescar estado (dispositivo, índice de sync, huellas de origen de la biblioteca, resumen del último sync, listas) | **"Actualizar"** — símbolo `arrow.clockwise`, ayuda: *"Vuelve a leer el estado del iPod y de tu biblioteca. No copia ni borra nada."* | Barra de la ventana (donde hoy está "Sincronizar"), habilitado también **sin iPod** (refresca solo la biblioteca) | Solo lectura; recalcula `DeviceSyncIndex`, `AuraDeviceProbe.probe`, `sourceFingerprint` de cada item | Ninguno |
| Consultar si hay firmware nuevo | **"Buscar actualizaciones de Aura"** — botón secundario en General → sección "Aura" (la actual `updateSection`) | General | `AuraUpdateChecker.checkForUpdate` (ST-006, hoy corre solo al conectar) — informa, no instala | Ninguno |
| Instalar firmware | **"Instalar actualización de Aura"** (hoy "Actualizar Aura") — botón prominente **solo** cuando hay actualización | General, mismo banner de hoy | `InstallerViewModel.startAutomaticUpdate()` — sin cambios | El de siempre; sigue siendo el **único** disparador (ST-006) |
| Copiar la biblioteca al iPod | **"Sincronizar"** — símbolo `arrow.triangle.2.circlepath` | General, junto a la barra (spec 2), + comando de menú `Archivo → Sincronizar con el iPod` (⇧⌘S) | `LibraryViewModel.sync` (rediseñado, §7) | Escritura; con la hoja previa solo si hay conflictos (§1.2) |

**Confusión "Actualizar" vs. "Sincronizar"** — se mitiga con cuatro cosas: (1) verbos distintos con símbolos distintos y ayudas (`.help`) que dicen literalmente si copian o no; (2) ubicaciones distintas: "Actualizar" arriba (contexto: la ventana), "Sincronizar" en General junto a la barra que muestra su efecto; (3) "Actualizar" nunca pide confirmación ni cambia el iPod — si el usuario se equivoca, no pasa nada; (4) el firmware ya no comparte verbo: "Instalar actualización de Aura". Alternativa considerada y descartada: "Refrescar" para el botón superior — es anglicismo de traducción, y Finder/Safari/Mail en español de macOS usan "Actualizar" para exactamente este gesto (⌘R); mantener el verbo del sistema es lo que menos confunde. Ver P1.

**Pérdida del atajo desde Música/Video/Fotos** (D-202 puso "Sincronizar" en la barra para eso): lo cubre el comando de menú con atajo y, además, "Sincronizar la selección" en el menú contextual de la tabla (§6). No se duplica el botón en la barra.

---

## 6. Fase 1.2 — Alcance: control segmentado, no casillas

- Control: `Picker` con `.pickerStyle(.segmented)` (radio visual de macOS) junto al botón: **"Toda la biblioteca"** | **"Solo la selección (N)"**. Estado de sesión (`LibraryViewModel.syncScope`), no preferencia persistida; al arrancar siempre "Toda la biblioteca".
- **N** = `LibraryViewModel.selectionForSync.count`, alimentado por `MediaSectionView.selection` (Música, Video, Fotos publican su selección; la de la vista activa manda; se limpia al cambiar de sección). Etiqueta secundaria bajo el control: *"Selecciona elementos en Música, Video o Fotos para sincronizar solo esos."*
- **N = 0 en modo selección**: la opción "Solo la selección (0)" queda **deshabilitada** y, si estaba elegida, el `Picker` vuelve solo a "Toda la biblioteca"; el botón "Sincronizar" se deshabilita solo si además no hay nada pendiente en toda la biblioteca. Nunca falla: no hay camino a "sincronizar nada".
- Semántica de "solo la selección": copia/actualiza **exclusivamente** esos elementos; no evalúa huérfanos ni conflictos de otros; sí escribe `sync_summary.cfg`, playlists y `.tcd` al final (son globales y baratos). Los elementos seleccionados que ya están `synced` se saltan (mensaje "Ya estaban sincronizados").
- Menú contextual de la tabla: **"Sincronizar la selección"** (solo con iPod Aura conectado) — atajo al mismo camino con `scope = .selection`.

---

## 7. Fase 1.3 — Barra persistente (`DeviceActivityBar`)

Una sola vista en General, siempre presente, plana (§8). Estados:

| Estado | Barra | Texto principal | Controles |
|---|---|---|---|
| **Sin dispositivo** | Cápsula gris vacía (`SHELL_RAIL`), sin segmentos | "Conecta tu iPod" + (si hay pendientes) "N elementos listos para sincronizar" | "Sincronizar" deshabilitado |
| **Conectado, en reposo** | **Uso de almacenamiento** (segmentos música/video/fotos/otro de `StorageBarView`, D-216) + leyenda | "Al día" · o "N pendientes · M con cambios · K modificados fuera de Aura Studio · J solo en el iPod" (solo los ≠ 0) | Alcance + "Sincronizar" |
| **Verificando** (tras conectar / Actualizar) | Segmentos atenuados + barra indeterminada fina encima | "Verificando el iPod…" | "Sincronizar" deshabilitado |
| **Sincronizando** | Relleno de progreso en **acento** sobre carril `PROGRESS_TRACK` (mismos tokens que el firmware), **por bytes** (no por archivos: un video de 700 MB no puede pesar lo mismo que un MP3) | "Sincronizando 12 de 40 · 1 min restante" + nombre del archivo actual en secundario | **Pausar**, **Cancelar** |
| **Pausado** | Relleno congelado, atenuado | "En pausa — 12 de 40" | **Reanudar**, **Cancelar** |
| **Cancelando** | Relleno congelado | "Cancelando… se termina el archivo actual" | (deshabilitados) |
| **Error** | Vuelve a almacenamiento + franja de texto en rojo | "Se desconectó el iPod durante la sincronización. 12 de 40 quedaron copiados; al reconectarlo puedes continuar." / mensaje real de Cocoa con la ruta (como hoy) | "Reintentar" cuando vuelve el iPod |

Se adopta la idea del dueño (almacenamiento en reposo) porque: elimina el "0 % atascado", reutiliza `StorageBarView` ya existente, y es el mismo concepto que la barra de "Acerca de" del firmware. Para que sea **la misma barra** y no una parecida, se alinea a lo verificado en el firmware (`draw_storage_segments`, `aura_screens.c:1856-1930`; `about.md` §Tokens): **6 segmentos en este orden** — Música (`aura_accent()`), Video (`category_video` `#1E3A5F`), Fotos (`category_photos` `#FF9500`), **Sistema** (`category_settings_gray` `#8E8E93`: el peso de `.rockbox/`, que Studio mide una vez al conectar), Otros (`category_extras_yellow` `#FFCC00`: usado − conocido) y Libre (`progress_track`); alto 12 px, extremos en cápsula, separadores de 1 px en `shell_bg`, ancho mínimo 2 px para todo segmento > 0, y la leyenda con punto de 6 px + etiqueta secundaria + "tamaño · %" (5 filas, Libre sin fila). Studio hoy usa `.pink/.blue/.green/.orange` del sistema porque `AuraColors` no trae tokens por categoría (D-216); esos hex ya están publicados en `CONTRATO-formato-tema.md` §B (`category_*`) — cero cambio de contrato. Ver P6.

La barra de la ventana (toolbar) mientras sincroniza muestra un indicador compacto "12/40" con `ProgressView` circular (reemplaza el actual `Label("\(copied)/\(total)")`) para que se vea desde cualquier sección — sin botones ahí.

---

## 8. Fase 1.4 — Pausar y cancelar de forma segura

### 8.1 Escritura por archivo (transaccional)
1. Copiar a **`<destino>.aura-tmp`** en el mismo directorio del destino, por bloques de 4 MB con `FileHandle` (no `FileManager.copyItem`, que no es interrumpible ni reporta bytes) — cada bloque revisa `Task.isCancelled`/pausa y publica bytes.
2. Al terminar el archivo: `rename` (`FileManager.moveItem` sobre el mismo volumen = renombre atómico en FAT32) del temporal al destino final (borrando antes el destino viejo si existe). Nunca hay un archivo final truncado.
3. **Registrar en el manifiesto y guardarlo** (`saveManifest`, ya atómico) — **por archivo**, no al final. Es lo que hace que pausar/cancelar/desconectar conserven progreso.
4. Poster/`cover.jpg`/`.m3u8`/`.jpg` de playlist: mismos temporales + renombre.

### 8.2 Marcador y barrido
- Al empezar: escribir `.rockbox/aura/sync_in_progress` (contenido: `started_at`, `machine_id`, `contract_version`); al cerrar limpio (fin o cancelación completada): borrarlo. Al conectar un iPod que lo tiene → el sync anterior no cerró (desconexión, cierre de la app, cuelgue) → estado "Sincronización interrumpida — N archivos pendientes" con "Continuar"; los `.aura-tmp` huérfanos se borran en el barrido inicial de cada sync (buscar por sufijo bajo `Music/`, `Videos/`, `Photos/`, `Playlists/`).
- El firmware **no** necesita leer el marcador (los archivos finales siempre están completos y el `.tcd` viejo sigue vigente hasta el cierre limpio); se documenta en el contrato como opcional para un futuro aviso en "Acerca de". Ver el hallazgo del firmware en §9/P8.

### 8.3 Orden de las fases y qué se hace al cancelar
`sync()` pasa a ser una máquina de fases: `verify` (índice) → `plan` (+ hoja previa si hay conflictos) → `copy` (interrumpible) → `finalize` (portadas, playlists **solo con rutas que existen en el iPod**, `sync_summary.cfg`, `ratings.cfg`, borrar `.tcd`, quitar marcador). **Cancelar** aborta `copy` en la frontera del bloque actual (borra el temporal), y **ejecuta `finalize` igual** para lo ya copiado — así el iPod queda consistente e indexa lo nuevo en el próximo arranque; el resumen dice "Se sincronizaron 12 de 40; 28 quedaron pendientes". **Pausar** suspende entre bloques (`AsyncStream`/`CheckedContinuation` en el actor de sync), no borra nada, la sesión y las estimaciones se conservan; reanudar sigue del mismo bloque. Pausa > 10 min o desconexión durante la pausa → se convierte en cancelación.

### 8.4 Desconexión física a media sincronización (el caso más probable)
`IPodMonitor.device` pasa a `nil` (`Services/IPodMonitor.swift:82-87`) → `LibraryViewModel` cancela la tarea; la escritura en curso falla con EIO/ENOENT y el actor lo trata como cancelación no solicitada: no intenta `finalize` (no hay volumen), publica el error de la tabla de §7, y **no** deja el catálogo local en estado raro (los items copiados ya están en el manifiesto del iPod, que se leerá al reconectar). Al reconectar: marcador presente → "Continuar". El temporal truncado en el iPod se borra en el barrido. `.tcd` no se tocó → el firmware arranca con el índice anterior (sin las canciones nuevas, todas completas) hasta que el próximo sync cierre limpio.

### 8.5 Diferencia real entre pausar y cancelar
| | Pausar | Cancelar |
|---|---|---|
| Progreso | Se conserva (bloque, archivo, estimación) | Lo copiado se conserva (manifiesto por archivo); lo restante queda pendiente |
| Temporal en curso | Se conserva | Se borra |
| `finalize` | No corre | Corre (índice, resumen, playlists coherentes) |
| Estado del iPod al desconectar en ese momento | Igual a cancelar + barrido al reconectar | Consistente |

**Tests obligatorios (Fase 2)**: cancelación entre archivos → cero `.aura-tmp` y cero truncados, manifiesto con exactamente lo copiado, `finalize` ejecutado; cancelación a mitad de archivo (bloque) → temporal borrado, destino ausente; "desconexión" simulada (el volumen falso desaparece a mitad de copia) → error publicado, sin `finalize`, marcador presente, y el sync siguiente barre y continúa; modo "solo seleccionados" con selección vacía → botón deshabilitado y `sync(scope: .selection([]))` no escribe nada; conflicto "modificado en el iPod" → sin confirmación no se toca; huérfanos → no se borran sin opt-in.

---

## 9. Fase 1.5 — Nombre del dispositivo (🔗 contrato con el firmware)

*(Se completa con la evidencia del firmware — ver §9.2.)*

### 9.1 Default y almacenamiento
- Default: **`iPod de <NSFullUserName()>`**; si viene vacío o solo espacios → `NSUserName()`; si también → **"iPod"** a secas. Se genera la primera vez que Studio ve un iPod con Aura sin nombre y se **guarda en el dispositivo** de inmediato (así otra Mac lo lee igual).
- Dónde vive: **en el iPod**, en un archivo **propio de Studio** — `.rockbox/aura/device.cfg` — no en `aura.cfg` (el firmware lo regenera entero en cada `aura_settings_save()`, `CONTRATO-firmware-studio.md` §D: Studio solo *edita una línea* ahí y solo para `theme_id`; una clave que el firmware no conoce no sobrevive), ni en la etiqueta del volumen FAT32 (11 caracteres, sin acentos: "iPod de Ricardo" no cabe; y renombrar el volumen requiere `diskutil rename`, otro flujo privilegiado sin necesidad). Precedente exacto: `sync_summary.cfg` — Studio escribe, el firmware solo lee, mismo parser `settings_parseline`.
- Espejo opcional en `/.rockbox/playername.txt` (Rockbox lo lee para IAP `RequestIPodName`, §9.4): recortado a 31 bytes en frontera de carácter, solo si el usuario puso un nombre (nunca se sobrescribe el default `"Apple iPod Classic/6G"` que crea el firmware). Ver P12.
- Copia local: `AppPreferences` guarda **solo el último nombre visto por dispositivo** (`[deviceID: name]`) para mostrarlo en la barra lateral **mientras el iPod está desconectado**; el iPod manda al reconectar.
- Edición: en General, el nombre grande del `header` (`DeviceGeneralView.swift:83`) pasa a ser editable al hacer clic (`TextField` in-place, Enter guarda, Esc cancela); "Restablecer nombre" en el menú contextual. La barra lateral (`ContentView.swift:297`) muestra el nombre en vez de `volumeName`.

### 9.2 Contrato — `CONTRATO-dispositivo.md` (nuevo, copia idéntica en ambos repos, canónico en el firmware)
```
/.rockbox/aura/device.cfg        UTF-8, LF, formato clave: valor (settings_parseline)
contract_version: 1
device_id: 6F2C1B4A-…            UUID v4 generado por Studio la primera vez; estable
device_name: iPod de Ricardo     ≤ N caracteres (§9.3), sin control chars, sin salto de línea
device_name_updated_at: 2026-08-17T20:14:00Z
```
- **Escribe** Studio (atómico); **lee** el firmware (opcional: mostrarlo en el slot superior de "Acerca de" en vez del literal "Mi iPod", `aura_screens.c:2039` — con marquee si no cabe, como ya hace ese slot) — nunca lo escribe. Claves desconocidas se ignoran. Ausente = sin nombre (el firmware sigue mostrando "Mi iPod"). Un firmware anterior lo ignora sin daño. Líneas ≤ 63 bytes (buffer `read_line` del firmware), sin BOM, LF.
- `device_id` es además lo que permite a Studio recordar por dispositivo (nombre local, exclusiones) sin depender de la etiqueta del volumen ni del BSD name.
- Cualquier cambio de clave/semántica sube `contract_version` y se registra cruzado (`D-NNN` / `ST-NNN`), como los otros contratos.

### 9.3 Validación
- Longitud máxima: la fija la **tipografía del firmware**, no macOS. Con los datos de §9.4: **32 caracteres y ≤ 48 bytes UTF-8** (`DeviceName.maxLength`/`maxBytes`, documentados en el contrato): 32 coincide con los precedentes del firmware (`style_id[33]`, `ipod_name[32]`), y 48 bytes garantiza que `device_name: <valor>` (13 + 48 = 61) cabe en el buffer de 63 bytes de `read_line` que usan todos los lectores `.cfg` del firmware. La UI muestra en vivo *"En el iPod se leen ~15 caracteres de un vistazo; el resto se desplaza"* (152 px a Bold 18, §9.4) — límite de legibilidad, no técnico.
- Caracteres: se recortan espacios en los extremos y se colapsan los internos; se prohíben caracteres de control, saltos de línea y `:` **al inicio** (el parser parte en el primer `:` — el valor sí puede llevar `:` porque va después de la clave, pero se evita igual por claridad); Unicode permitido dentro del **BMP** (lo que cubren las `.fnt` de Aura, U+0020–U+FFFD según AUDITORIA-01 A-02).
- **Emoji**: fuera del BMP (U+1F300+) → el iPod no tiene glifo y mostraría cajas. Studio los **quita al guardar** y lo dice en línea: *"El iPod no puede mostrar emoji; se guardó sin ellos."* (no falla, no los "convierte").
- Vacío tras validar → vuelve al default.

### 9.4 Evidencia del firmware (verificada en `Aura-Firmware`)
- **Hoy el firmware no muestra ningún nombre de iPod.** El texto superior de "Acerca de" es una constante: `aura_screens.c:2039` `*panel_top = aura_str(AURA_STR_ABOUT_MY_IPOD)` → `aura_lang.c:250` `"Mi iPod"` (`:482` `"My iPod"`). No lee la etiqueta FAT32 (`get_volume_name()` de `pathfuncs.c:263` devuelve el nombre sintético `<volume0>`; nadie en `apps/aura/` lo llama). Ese slot es **exactamente** donde iría `device_name`.
- **Dónde y con qué fuente se vería**: slot superior del panel derecho de "Acerca de" (split), `A26_FONT_STYLE_DS_BOLD_18` (`aura_selection_summary.c:571,620`; *"única línea — nunca se envuelve"*), ancho útil `160 − 2×4 = 152 px`; texto más largo → **marquee** (`draw_text_slot` → `aura_marquee_draw`), no elipsis. Con Bold 18 (`a26-ds_bold_18-18.fnt`: `maxwidth 38`, `height 19`) caben ~15–17 caracteres latinos sin desplazamiento ("iPod de Ricardo" = 15). En la página 1 expandida (`DS_REG_10`, 182 px) cabrían ~30–35. El único recorte con "…" del firmware es la línea de unidad (`draw_about_drive_line`, `aura_screens.c:2603-2632`) y recorta **bytes**, no puntos de código — cuidado si algún día se aplica a un nombre con acentos.
- **`aura.cfg` no sirve para guardar el nombre desde Studio**: `aura_settings_save()` (`aura_settings.c:300-341`) hace `creat()` + 22 `fdprintf` de las claves **conocidas** — cualquier clave ajena **se pierde** en el primer guardado (comentario explícito en `:279-283`; `PLAN-themes-impl.md:143` del firmware ya lo advierte). Buffer de lectura `char line[64]` (`:212`) → línea completa ≤ 63 bytes; el precedente `theme_id` usa `style_id[33]` (32 caracteres). Además `aura_settings_is_first_boot()` = `!file_exists(aura.cfg)` (`:145-148`): crearlo desde Studio falsearía "ya arrancó" (`AuraDeviceProbe`). Todo esto confirma la elección de un archivo propio (`device.cfg`) que el firmware **lee** con el mismo `read_line`+`settings_parseline` de `sync_summary.cfg` (`aura_manifest.c:33,54`, buffer 64).
- **Bonus sin tocar el firmware**: Rockbox ya lee `/.rockbox/playername.txt` para responder `RequestIPodName` por IAP (accesorios/estéreos de coche): `iap.c:207-213`, `char ipod_name[32]` (31 bytes útiles); `main.c:209-217` lo crea con `"Apple iPod Classic/6G"` solo si falta y **nunca lo sobrescribe**. Studio puede reflejar ahí el nombre (recortado a 31 bytes en frontera de carácter) — ver P12.
- **Tagcache**: borrar `database_*.tcd` ⇒ `check_all_headers()` falla (`tagcache.c:703-734`) ⇒ `aura_music_db_ready()` dispara `tagcache_rebuild()` a ~0,5 s del arranque (`aura_music.c:429-433`, `aura_main.c:456`); con base válida corre una pasada de actualización por arranque (`aura_music.c:461`) que indexa archivos nuevos por `mtime`. Un archivo **truncado** con extensión válida **sí se indexa** si el parser lee la cabecera (`add_tagcache`, `tagcache.c:2261,2294,2341`) y se auto-corrige recién en el siguiente scan — razón de peso para los temporales `.aura-tmp` (extensión desconocida → `probe_file_format` = `AFMT_UNKNOWN` → **nunca indexado**) y el renombre atómico (§8.1). Existe además `/.rockbox/database_commit.ignore` (`TAGCACHE_FILE_NOCOMMIT`, `tagcache.c:139,3400-3407`: pospone el *commit* mientras el archivo exista) y `database.ignore` por carpeta (`check_ignore`, `:4843-4855`) — mecanismos de Rockbox aprovechables si hiciera falta "no indexes todavía", **no necesarios** con el diseño de §8 (todo archivo final está siempre completo). El firmware **no lee** `sync_manifest.json` (contrato §D `:56`; `DECISIONS-ARCHIVE.md:510`).

---

## 10. Fase 1.6 — Columna de estado en la biblioteca

- **Sin salto de layout**: la columna "Estado" **ya existe siempre** (`MediaSectionView.swift:341-379`); no se agrega ni quita al conectar — cambian sus **valores**. Sin iPod: "En cola / Procesando / Listo / Revisar / Error" (como hoy). Con iPod Aura: `.ready` se reemplaza por los 5 estados de §4.1. Ancho fijo actual (`min 90, ideal 120`) alcanza para "Modificado en el iPod" a 11 pt; se sube `ideal` a 150 una sola vez, sin cambiar con el dispositivo.
- **Representación (plana, símbolo + texto, sin fondo ni translucidez, colores por token de `AuraColors`)**:
  - Sincronizado — `checkmark.circle` secundario · "Sincronizado"
  - Pendiente — `arrow.up.circle` en **acento** · "Pendiente"
  - Con cambios — `arrow.triangle.2.circlepath` en acento · "Con cambios"
  - Modificado en el iPod — `exclamationmark.triangle` naranja · "Modificado en el iPod" (tooltip: qué difiere)
  - Quitado del iPod — `minus.circle` secundario · "Quitado del iPod" (tooltip: "Volver a copiar")
- **"Solo en el iPod"** no es una fila de la tabla (no hay `LibraryItem`): se muestra como **chip de filtro/contador** sobre la tabla ("Solo en el iPod: 7") que abre la hoja "Contenido solo en el iPod" (lista de rutas, tamaño, "Importar a la biblioteca" / "Eliminar del iPod" con confirmación).
- Ordenable por estado (la columna ya usa `KeyPathComparator`; se agrega `syncStateSort: Int` a `MediaTableRow`).
- Coherencia con `PLAN-studio-ux.md` §1 (tratamiento plano): mismos tokens, mismo criterio; cuando exista `StudioStyle`, esta celda migra a `.studioChip` sin cambio visual.

---

## 11. Preguntas abiertas (con recomendación)

| # | Pregunta | Recomendación |
|---|---|---|
| **P1** | ¿"Actualizar" (verbo del sistema, ⌘R) o "Refrescar" para el botón superior? | **"Actualizar"**, con `.help` explícito "No copia ni borra nada" y símbolo `arrow.clockwise`; el firmware deja de compartir verbo ("Instalar actualización de Aura"). |
| **P2** | ¿Un archivo propio **modificado en el iPod** se reemplaza por defecto (biblioteca autoritativa) o se conserva por defecto? | **Conservar por defecto**, reemplazar solo si el usuario lo marca en la hoja previa. Es la interpretación segura de "autoritativa": manda cuando el usuario lo pide, no destruye por omisión. |
| **P3** | ¿Un archivo propio **borrado a mano en el iPod** se vuelve a copiar? | **No** (se respeta el borrado); "Volver a copiar" por elemento/lote. Evita el comportamiento más odiado de iTunes. |
| **P4** | ¿Los elementos **quitados de la biblioteca** se borran del iPod? | **Nunca sin opt-in explícito** en la hoja previa (casilla desmarcada, lista visible). |
| **P5** | ¿"Sincronizar" solo en General (spec) o también en la barra (D-202)? | **General + comando de menú ⇧⌘S + "Sincronizar la selección" en el menú contextual.** Un solo botón visible evita la confusión con "Actualizar". |
| **P6** | Colores/segmentos de la barra en reposo: ¿los 4 de sistema (D-216) o los 6 tokens del firmware? | **Los 6 del firmware** (Música acento · Video `#1E3A5F` · Fotos `#FF9500` · Sistema `#8E8E93` · Otros `#FFCC00` · Libre `progress_track`), misma geometría (§7). Los hex se leen de `theme-format-v1.json` (`default_category`, ya en `Vendor/firmware-dist/`, aún no bundleado — se bundlea, misma unidad que pide `PLAN-studio-ux.md` §5) en vez de editar `AuraPalette.swift` a mano. |
| **P7** | ¿Manifiesto por-Mac (`writtenBy`) o global? | **Por-Mac** (`installationID`): dos Macs con Studio no se pisan; el costo es un UUID en `AppPreferences` y un campo por registro. |
| **P8** | ¿El firmware debe leer `sync_in_progress` / `device.cfg`? | **Opcional, sin fecha** — se documenta en el contrato como "consumo esperado"; Studio funciona igual sin que el firmware los lea. |
| **P9** | Límite del nombre. | **32 caracteres y ≤ 48 bytes UTF-8** (§9.3), con aviso en vivo de que ~15 se leen de un vistazo en el iPod (152 px a Bold 18; el firmware hace marquee, no corta). |
| **P10** | Orden respecto a `PLAN-studio-ux.md`: ¿este plan antes o después de su tanda 2 (§1)? | **Antes** puede ir: no comparten archivos salvo `statusCell`; ambos usan el criterio plano. Si el dueño prefiere terminar aquel primero, tampoco hay dependencia dura. |
| **P11** | ¿Copia por bloques propia (`FileHandle`) o `FileManager.copyItem` + temporal? | **Bloques propios**: cancelación dentro del archivo, progreso por bytes real, y detección temprana de EIO al desconectar. Es ~40 líneas y se testea con archivos grandes falsos. |
| **P12** | ¿Reflejar el nombre también en `/.rockbox/playername.txt` (Rockbox ya lo usa para `RequestIPodName` por IAP — estéreos de coche/accesorios)? | **Sí, opcional y barato**: solo cuando el usuario puso un nombre, recortado a 31 bytes en frontera de carácter; nunca se toca si el usuario no nombró el iPod. Cero cambio de firmware. |
| **P13** | ¿`device.cfg` propio de Studio (firmware solo lee) o clave `device_name` en `aura.cfg` (patrón `theme_id`)? | **`device.cfg`**: funciona hoy sin esperar firmware, no depende de que `aura_settings_save()` conozca la clave (las desconocidas se pierden, `aura_settings.c:300-341`), no falsea "ya arrancó", y da un `device_id` estable que Studio necesita de todos modos. Que el firmware lo lea para "Acerca de" queda como consumo esperado (`D-NNN` futura, MINOR en ambos por §E). |

---

## 12. Fase 2 (solo tras aprobación) — resumen de ejecución

- `swift build`/`swift test` limpios tras cada cambio; la falla conocida de `LiveEnrichmentIntegrationTests` no cuenta; sin regresiones nuevas.
- Tandas propuestas: (1) motor — `SyncManifest` v2, `DeviceSyncIndex`, copia transaccional por bloques, cancelación/pausa, marcador y barrido, `finalize`, candado `InstallerFlowRegistry` (+ tests obligatorios de §8); (2) UI — `DeviceActivityBar` con sus 7 estados, botones "Actualizar"/"Sincronizar"/menú, alcance segmentado, hoja previa de conflictos, hoja "Solo en el iPod", columna de estado; (3) nombre del dispositivo — `CONTRATO-dispositivo.md`, `DeviceNameStore`, edición in-place, validación (+ tests); (4) bitácora y contrato: `DECISIONS.md` ST-NNN por tanda, `CONTRATO-firmware-studio.md` §D (fila nueva `device.cfg` y `sync_in_progress`, `sync_manifest.json` v2), textos en español (Principio 7).
- Commits atómicos. Sin push.

---

## BARRERA

**Aquí se detiene la Fase 1.** Nada de código tocado; este documento (en `docs/plans/`, activo, sin encabezado de archivado) es el único cambio en el árbol, sin commit. La Fase 2 arranca únicamente con la aprobación explícita del dueño sobre el modelo de §1.2 y las recomendaciones P1–P11, o con las correcciones que indique.
