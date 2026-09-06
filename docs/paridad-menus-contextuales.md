# Paridad de menús contextuales — macOS → Windows

**Qué es esto.** El inventario EXACTO de los menús contextuales (clic
derecho) de Aura Studio para macOS, por tipo de elemento, con sus ítems
en orden, sus separadores y las condiciones que hacen que cada uno
aparezca, desaparezca o se muestre deshabilitado.

**Para qué.** Es el insumo del Paquete B de la Ronda de ajustes 1
(`docs/plans/PLAN-aura-studio-windows-v2.md`): la versión Windows tiene
que igualar estos menús, y "igualar" no es aproximarse — es el mismo
ítem, con el mismo texto en español de México, en la misma posición y
con la misma condición.

**Cómo leerlo.** Cada sección es un menú. `───` es un separador real.
La columna *Condición* dice cuándo se muestra el ítem; cuando dice
**deshabilitado**, el ítem SE VE pero no se puede usar (nunca se
esconde: que una acción exista y no aplique ahora es información, y
esconderla deja al usuario buscándola).

**Estado:** al 2026-09-01, tras ST-102…ST-105 y la Ronda de ajustes 2
(ST-113…ST-116). Si cambia un menú en macOS, se actualiza este archivo en
el mismo cambio.

---

## 0. Reglas que valen para TODOS los menús

Estas son la parte que más fácil se pierde al portar, porque no están en
ningún texto de la interfaz:

1. **Criterio Finder para la selección.** Un clic derecho sobre un
   elemento que YA está seleccionado actúa sobre **toda la selección**;
   sobre uno que NO lo está, actúa **solo sobre ese**, y no se pierde la
   selección anterior. En macOS lo implementa
   `GridSelection.effectiveIDs(for:)` (`Models/GridSelection.swift`) y
   cada vista tiene su `effectiveAlbums`/`effectiveMovies`/… que lo
   aplica.
2. **Los textos cambian de número.** Cuando la acción alcanza a más de
   un elemento, el ítem se escribe en plural ("Eliminar álbumes" vs
   "Eliminar álbum"). Está anotado ítem por ítem más abajo.
3. **Aridad: un ítem se ofrece si la acción tiene sentido para lo
   alcanzado** (R2-2, ST-114). Un ítem se restringe a un solo elemento
   **solo** cuando en plural sería absurdo o ambiguo — renombrar N cosas
   con un nombre, abrir N detalles a la vez. Si la acción tiene sentido
   plural, o si la selección es **homogénea** y resuelve a un objeto
   único, se ofrece. El caso que originó la regla: «Buscar carátulas del
   álbum...» desaparecía con más de una canción seleccionada, aunque
   todas fueran del mismo disco.
4. **Lo destructivo va marcado.** `role: .destructive` — en macOS lo
   pinta en rojo. Equivalente en WinUI: el estilo de acción destructiva,
   no un ítem normal.
5. **Nada pide confirmación en el propio menú.** Las confirmaciones y
   las hojas (renombrar, más información, revisión de carátulas) son
   pantallas aparte.
6. **Los ítems que abren una hoja terminan en `...`** (tres puntos, no
   el carácter `…`), como manda la convención de macOS. En Windows se
   conserva el mismo texto.
7. **Selección múltiple visible (ST-103, revisada por R2-1 en
   ST-113).** Las tablas traen una columna de casillas. En las
   cuadrículas la casilla va en la esquina superior izquierda de cada
   tarjeta (y al principio de cada fila de episodio), y **su visibilidad
   sigue esta regla, idéntica en las dos apps**:
   - **Sin nada seleccionado: ninguna casilla.** La cuadrícula se ve
     limpia.
   - **Al pasar el cursor por una tarjeta: solo la de ella.** Es lo que
     hace descubrible la selección múltiple sin ensuciar la cuadrícula.
   - **Con 1 o más elementos seleccionados: todas.** El usuario ya está
     en modo selección y necesita ver dónde sumar o quitar.
   - Una tarjeta seleccionada muestra su casilla siempre.

   La semántica no cambia: la casilla **alterna** ese elemento (equivale
   a Cmd/Ctrl+clic); el clic sobre la tarjeta **reemplaza** la selección.
   La casilla se oculta con opacidad, no quitándola del layout, para que
   la cuadrícula no dé un salto al aparecer.

---

## 1. Álbum de música — cuadrícula de «Álbumes»

`Views/AlbumsView.swift` → `albumContextMenu(_:)`.
Alcance: `effectiveAlbums(for:)` → las canciones de todos los álbumes
alcanzados (`items`).

| # | Ítem | Condición |
|---|------|-----------|
| 1 | **Abrir** | solo si el alcance es UN álbum |
| — | ─── | solo si se mostró «Abrir» |
| 2 | **Marcar como favorito** / **Quitar favorito** | «Quitar favorito» si TODAS las canciones alcanzadas ya son favoritas; si no, «Marcar como favorito» |
| 3 | **Buscar información en línea** | siempre |
| 4 | **Buscar carátulas del álbum...** | solo si el alcance **resuelve a UN álbum** con título propio (no «Sin álbum») — ST-104, aridad corregida en R2-2. Aplica al álbum COMPLETO, no solo a lo seleccionado |
| 5 | **Aplicar carátula recomendada** / **Aplicar carátula recomendada a N álbumes** | si algún álbum alcanzado tiene título propio; plural con más de uno. **Deshabilitado** mientras se está aplicando. Aplica sin preguntar solo lo que supere el umbral de `docs/caratula-recomendada.md` — R2-3 |
| — | ─── | siempre |
| 6 | **Mostrar en Finder** | siempre — en Windows: «Mostrar en el Explorador» |
| 7 | **Eliminar álbum** / **Eliminar álbumes** (destructivo) | plural con más de un álbum |

## 2. Artista — lista de «Artistas»

`Views/ArtistsView.swift` → `artistContextMenu(_:)`.
Alcance: `effectiveArtists(for:)` → todas las canciones de esos
artistas. **Nota:** Artistas es una `List(selection:)` nativa, no una
cuadrícula: la selección múltiple es la del sistema y **no lleva
casillas** (R2-1 no aplica aquí).

**R2-4:** las filas son artistas **principales** — «Gorillaz feat. De La
Soul» aparece dentro de «Gorillaz», no como fila propia. Ver
`docs/normalizacion-artistas.md`.

| # | Ítem | Condición |
|---|------|-----------|
| 1 | **Marcar como favorito** / **Quitar favorito** | «Quitar favorito» si TODAS las canciones alcanzadas ya son favoritas |
| 2 | **Buscar información en línea** | siempre |
| 3 | **Buscar foto del artista** / **Buscar fotos de los artistas** | solo si la vista recibió el callback `onFetchArtistImages`; plural con más de un artista |
| 4 | **Quitar foto del artista** / **Quitar fotos de los artistas** | si **algún** artista alcanzado ya tiene foto guardada; plural cuando son varios los que la tienen. Antes se ofrecía solo con uno — corregido en R2-2 |
| — | ─── | siempre |
| 5 | **Mostrar en Finder** | siempre. Con un solo artista revela **una** canción; con varios, todas |
| 6 | **Eliminar artista** / **Eliminar artistas** (destructivo) | plural con más de un artista |

## 3. Canción — lista de canciones dentro de «Artistas»

`Views/ArtistsView.swift`, menú inline de la fila de canción del
detalle de artista. Alcance: **siempre esa sola canción** (esta lista no
tiene selección múltiple).

| # | Ítem | Condición |
|---|------|-----------|
| 1 | **Más información...** | siempre |
| 2 | **Marcar como favorito** / **Quitar de favoritos** | según el estado de esa canción |
| — | ─── | siempre |
| 3 | **Mostrar en Finder** | siempre |

## 4. Canción / video / foto — tablas de `MediaSectionView`

`Views/MediaSectionView.swift` → `contextMenuContent(for:)`. Es el menú
de las tablas de **Canciones**, **Video** y **Fotos**, y también el de
la tabla embebida en el detalle de un álbum. Alcance: los ids sobre los
que se hizo clic derecho, o la selección actual si el clic fue en vacío.

Este menú se arma por bloques; los bloques que no aplican desaparecen
enteros, con su separador.

### 4.1 Bloque de música — solo con `kind == .music` y alcance no vacío

| # | Ítem | Condición |
|---|------|-----------|
| 1 | **Buscar información en línea** | siempre en este bloque |
| 2 | **Buscar carátulas del álbum...** / **Buscar carátulas de N álbumes...** | si el alcance **resuelve a UN álbum** con título — **también con varias canciones seleccionadas**, que es el caso que R2-2 vino a corregir. La tapa elegida se aplica al álbum COMPLETO, no solo a las canciones seleccionadas. **Con la selección tocando varios discos va en plural** (ST-182 en macOS, ST-206 en Windows): antes desaparecía, y era el caso que el dueño reportó. Entonces aplica sola la que supere el umbral de `docs/caratula-recomendada.md` y las dudosas se revisan de a una |
| 3 | **Buscar letra** | siempre en este bloque |
| 4 | **Volver a leer etiquetas del archivo** | siempre en este bloque |
| 5 | **Eliminar carátula** | siempre visible; **deshabilitado** si ninguna canción alcanzada tiene carátula |
| — | ─── | |
| 6 | **Marcar como favorito** / **Quitar de favoritos** | «Marcar» si alguna alcanzada NO es favorita; «Quitar» si todas lo son |
| — | ─── | |
| 7 | **Seleccionar canciones del mismo álbum** | solo si la primera canción alcanzada tiene álbum |
| 8 | **Seleccionar canciones del mismo artista** | solo si la primera canción alcanzada tiene artista |
| — | ─── | |

### 4.2 Bloque de video — solo con `kind == .video` y alcance no vacío

| # | Ítem | Condición |
|---|------|-----------|
| 1 | **Buscar póster en línea** | siempre en este bloque |
| 2 | **Quitar póster** | siempre visible; **deshabilitado** si ningún video alcanzado tiene póster |
| — | ─── | |

### 4.3 Bloque de categoría — con alcance no vacío y sección que tenga categorías

Solo **Fotos** y **Video** tienen categorías (la música se organiza por
artista/álbum y eso se elige en Ajustes, no por elemento).

| # | Ítem | Condición |
|---|------|-----------|
| 1 | Submenú **Cambiar categoría** | Fotos: una entrada por colección de `preferences.photoCollections` (editable por el usuario). Video: una por `MediaCategory.videoCategories` (conjunto fijo) |
| — | ─── | |

### 4.4 Bloque de información

| # | Ítem | Condición |
|---|------|-----------|
| 1 | **Cambiar nombre...** | solo con UN elemento alcanzado |
| 2 | **Más información...** | solo con UN elemento alcanzado |
| 3 | **Obtener información...** | solo con música y MÁS de un elemento (edición en lote, D-218) |
| — | ─── | |

### 4.5 Bloque de sincronización

| # | Ítem | Condición |
|---|------|-----------|
| 1 | **Sincronizar la selección** | solo con un iPod conectado que corra Aura (`supportsAuraContract`); **deshabilitado** si ningún elemento alcanzado está «listo» |
| — | ─── | |

### 4.6 Bloque final

| # | Ítem | Condición |
|---|------|-----------|
| 1 | **Mostrar en Finder** | alcance no vacío |
| 2 | **Buscar elementos similares...** | alcance no vacío |
| — | ─── | |
| 3 | **Eliminar** (destructivo) | siempre visible; **deshabilitado** con alcance vacío |

## 5. Película — cuadrícula de «Películas»

`Views/MoviesView.swift` → `movieContextMenu(_:)`.

| # | Ítem | Condición |
|---|------|-----------|
| 1 | **Abrir** | solo con UNA película |
| — | ─── | solo si se mostró «Abrir» |
| 2 | **Marcar como favorito** / **Quitar favorito** | «Quitar» si todos los videos alcanzados ya son favoritos |
| 3 | **Buscar póster en línea** | siempre |
| 4 | Submenú **Cambiar categoría** | siempre; una entrada por `MediaCategory.videoCategories` |
| — | ─── | siempre |
| 5 | **Mostrar en Finder** | siempre |
| 6 | **Eliminar película** / **Eliminar películas** (destructivo) | plural con más de una |

## 6. Serie — cuadrícula de «Series»

`Views/SeriesView.swift` → `seriesContextMenu(_:)`. Idéntico al de
Películas salvo los textos:

| # | Ítem | Condición |
|---|------|-----------|
| 1 | **Abrir** | solo con UNA serie |
| — | ─── | solo si se mostró «Abrir» |
| 2 | **Marcar como favorito** / **Quitar favorito** | «Quitar» si todos los episodios alcanzados ya son favoritos |
| 3 | **Buscar póster en línea** | siempre |
| 4 | Submenú **Cambiar categoría** | siempre; `MediaCategory.videoCategories` |
| — | ─── | siempre |
| 5 | **Mostrar en Finder** | siempre |
| 6 | **Eliminar serie** / **Eliminar series** (destructivo) | plural con más de una |

## 7. Episodio — filas del detalle de una serie

`Views/SeriesView.swift` → `episodeContextMenu(_:show:)`.

| # | Ítem | Condición |
|---|------|-----------|
| 1 | **Más información...** | solo con UN episodio |
| — | ─── | solo si se mostró «Más información...» |
| 2 | **Marcar como favorito** / **Quitar favorito** | «Quitar» si todos los alcanzados ya son favoritos |
| 3 | Submenú **Cambiar categoría** | siempre; `MediaCategory.videoCategories` |
| — | ─── | siempre |
| 4 | **Mostrar en Finder** | siempre |
| 5 | **Eliminar episodio** / **Eliminar episodios** (destructivo) | plural con más de uno |

## 8. Álbum de fotos — cuadrícula de «Fotos»

`Views/PhotoAlbumsView.swift` → `albumContextMenu(_:)`. El MISMO menú
se usa como menú del botón «⋯» en el detalle del álbum (ahí solo si el
álbum no es «Sin álbum»).

| # | Ítem | Condición |
|---|------|-----------|
| 1 | **Abrir** | solo con UN álbum |
| — | ─── | solo si se mostró «Abrir» |
| 2 | Submenú **Cambiar categoría** | siempre visible; **deshabilitado** si no hay fotos alcanzadas. Una entrada por colección de `preferences.photoCollections` |
| — | ─── | solo si algún álbum alcanzado NO es «Sin álbum» |
| 3 | **Renombrar álbum...** | solo con UN álbum y que no sea «Sin álbum» |
| 4 | **Disolver álbum** / **Disolver álbumes** (destructivo) | solo si algún álbum alcanzado no es «Sin álbum»; plural con más de uno |
| — | ─── | siempre |
| 5 | **Mostrar en Finder** | siempre |
| 6 | **Eliminar fotos de la biblioteca** (destructivo) | siempre, sin variante en plural |

## 9. Foto — miniaturas dentro de un álbum

`Views/PhotoAlbumsView.swift` → `photoContextMenu(_:album:)`.

| # | Ítem | Condición |
|---|------|-----------|
| 1 | **Vista previa** | solo con UNA foto (abre Quick Look) |
| — | ─── | solo si se mostró «Vista previa» |
| 2 | Submenú **Cambiar categoría** | siempre; `preferences.photoCollections` |
| 3 | **Quitar del álbum** | siempre |
| 4 | **Mostrar en Finder** | siempre |
| — | ─── | siempre |
| 5 | **Eliminar de la biblioteca** (destructivo) | siempre, sin variante en plural |

## 10. Tema — cuadrícula de «Temas»

`Views/ThemesView.swift`. No es un elemento de biblioteca; se incluye
para que el inventario esté completo.

| # | Ítem | Condición |
|---|------|-----------|
| 1 | **Eliminar** (destructivo) | solo si el tema NO es el tema por omisión. Abre la confirmación, no borra directo |

Con el tema por omisión el menú queda **vacío** (macOS no muestra
ningún menú). En Windows debe comportarse igual: no mostrar un menú con
un solo ítem deshabilitado.

## 11. Encabezados de la tabla de Canciones

`Views/MediaSectionView.swift` → `headerMenuEntries`, instalado sobre el
`NSTableHeaderView` real (`TableHeaderMenu.swift`). El MISMO contenido
sale del botón de la barra superior, así que Windows debe compartirlo
igual entre las dos entradas.

| # | Ítem | Condición |
|---|------|-----------|
| 1 | **Todas las canciones** | marcado (✓) si el filtro de favoritos está apagado |
| 2 | **Solo favoritos** | marcado (✓) si está encendido |
| — | ─── | |
| 3 | Submenú **Opciones para ordenar** (símbolo `arrow.up.arrow.down`) | ver abajo |
| — | ─── | |
| 4 | **Mostrar opciones de visualización** (símbolo `gearshape`) | abre la ventana de opciones |

Dentro de **Opciones para ordenar**:

| # | Ítem | Condición |
|---|------|-----------|
| 1..n | Un ítem por campo de `MusicSortField.menuFields` | marcado (✓) el campo de orden actual |
| — | ─── | |
| n+1 | **Ascendente** | marcado (✓) si el orden es ascendente |
| n+2 | **Descendente** | marcado (✓) si es descendente |

---

## 12. Elementos que HOY no tienen menú contextual

Se listan para que Windows no invente uno donde macOS no lo tiene — la
paridad también es no agregar de más:

- **Playlists** (`Views/PlaylistsView.swift`): ni la lista ni las pistas
  de una playlist tienen menú contextual.
- **La barra lateral** (`Views/ContentView.swift`): las secciones no
  tienen menú; sí aceptan que se les suelte una selección arrastrada.
- **Extras**, **Ajustes**, **Dispositivo**: sin menús contextuales.

---

## 13. Diferencias conocidas contra la versión Windows

Lo que el Paquete B tiene que resolver, anotado desde el lado macOS:

1. **«Mostrar en Finder»** es el único ítem cuyo texto NO se puede
   copiar literal: en Windows es «Mostrar en el Explorador». Es la
   excepción, y va anotada acá para que no se convierta en licencia
   para reescribir el resto de los textos.
2. **«Buscar carátulas del álbum...»** (ST-104) existe en macOS en dos
   lugares: el menú contextual de la cuadrícula de Álbumes y el menú de
   la tabla de Canciones, más un botón en la cabecera del detalle del
   álbum. Windows debe cubrir los tres.
3. **Las casillas de selección** (ST-103, R2-1) van en cuadrículas y en
   filas de episodio, con la regla de visibilidad de la §0 punto 7. En
   Artistas NO van: esa vista usa la selección nativa de lista.
   **Resuelto en Windows (ST-120, ST-121):** la regla de visibilidad está
   implementada en la cuadrícula, y Artistas dejó de ser una cuadrícula —
   ver el punto 6.
4. **«Aplicar carátula recomendada»** (R2-3) es un ítem nuevo del menú de
   Álbumes. Su algoritmo — puntaje, desempates y umbral — está fijado en
   `docs/caratula-recomendada.md` y Windows lo calca sin reinterpretarlo.
5. **La homologación de artistas** (R2-4) cambia lo que los menús de
   Artistas y Álbumes consideran "un artista" y "un álbum". La regla está
   en `docs/normalizacion-artistas.md`.
   **Resuelto en Windows (ST-117).**

6. **Artistas ya no es una cuadrícula en Windows** (R2-6, ST-121). Era la
   misma cuadrícula de tarjetas que Álbumes, con casillas — una
   divergencia que ST-108 había documentado como legítima y que el dueño
   revocó al verla. Ahora es **maestro-detalle**, como
   `ArtistsView.swift`: lista de artistas con avatar a la izquierda,
   ficha del seleccionado a la derecha con sus álbumes y las canciones de
   cada uno. La selección es la nativa del `ListView` (Ctrl y Mayús), que
   es el equivalente de la `List(selection:)` de macOS.

   Con eso, los menús de esa vista pasan a ser exactamente los del
   documento: **§2** en las filas de artista (y en el botón «⋯» de la
   cabecera) y **§3** en las filas de canción. El menú del álbum dentro de
   la ficha es el mismo trío que macOS —favorito, buscar en línea y
   mostrar en el Explorador—; no está numerado en este documento porque
   del lado macOS es un `Menu` de la vista, no un menú contextual.

7. **En Álbumes, el plural de «Buscar carátulas» no se repite** (ST-206,
   Windows). El §4.1 punto 2 lleva la forma plural a la tabla de
   Canciones; el menú de Álbumes (§1) **no** la lleva, porque ahí la
   misma operación ya se ofrece como «Aplicar carátula recomendada a N
   álbumes» (§1 punto 5, R2-3). Dos ítems que hacen lo mismo en el mismo
   menú son peor que uno. Con **un solo** álbum, §1 punto 4 sigue igual
   que en macOS: abre su selector.
