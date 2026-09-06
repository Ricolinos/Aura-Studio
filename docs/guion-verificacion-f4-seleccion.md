# Guion de verificación — F4: selección tipo Finder completa

> PLAN-studio-rendimiento-2.md §B, Fase F4 (ST-184, commit 57e6ca6).
> Criterio de cierre: "(M) guion XCUITest o manual documentado de los
> ocho gestos en Álbumes y Canciones". F4 ya cerró -- este documento
> refleja el estado final: qué quedó automatizado (la mayoría, contra el
> núcleo puro de `GridSelection`/`GridMarquee`/`GridSelectionModel`) y qué
> sigue siendo **solo verificable a mano**.

## Los ocho gestos (§A del plan)

Clic, ⌘/Ctrl+clic, Shift+clic, Shift+flechas, casilla, arrastre
(marquee), ⌘A/Ctrl+A (y ⇧⌘A para deseleccionar) por menú Edición, Escape.

## Lo único NO verificado automáticamente: el arrastre (marquee) real

**El arrastre es el único de los ocho gestos que no se pudo probar sin
mover un mouse de verdad, y es exactamente donde termina lo que se puede
verificar sin la app corriendo.** Toda la LÓGICA del arrastre —qué
tarjetas toca un rectángulo, qué selección resulta, que agrandar y
achicar sea reversible, que `base` (la selección al empezar) no cambie a
mitad de camino— está probada entera y en verde (`GridSelectionTests.
swift`, ver más abajo). Lo que **no** se pudo verificar es el CABLEADO:
que el `NSViewRepresentable` de fondo (dentro del `ScrollView` con
`LazyVGrid`) de verdad reciba los eventos `mouseDown`/`mouseDragged` de
AppKit y los traduzca en el rectángulo correcto.

Se intentó un XCUITest de macOS para cerrar esto del todo (pedido de
"Sesión Maestra", con tope de una hora) y **no fue viable en ese tiempo**,
por una razón concreta y no solo de esfuerzo: el proyecto no tiene hoy
ningún target de UI testing (`project.yml` solo declara `AuraStudio` y
`AuraStudioTests`), la app no tiene forma de arrancar apuntando a una
biblioteca sintética (no hay ninguna variable de entorno ni argumento de
lanzamiento que reemplace `libraryRoot`/`AppPreferences.shared` -- se
comprobó con un `grep` de `ProcessInfo.processInfo.environment`/
`CommandLine.arguments` en todo `Sources/`, y no hay nada), y ninguna
vista tiene `accessibilityIdentifier` para que XCUITest encuentre una
tarjeta o la barra de estado por nombre. Armar esto de cero --agregar el
target, un modo de arranque de prueba, e identificadores de
accesibilidad-- son cambios de `Sources/`/`project.yml` que no le tocan a
esta sesión sin coordinarlos primero, y por su tamaño no entran en el
tope de una hora. Queda pendiente como una posibilidad real para el
futuro (F7, o una PARADA aparte), no descartada por imposible.

**Por qué esto no bloquea nada de los otros siete gestos**: cada uno de
los otros siete llama directo a una función pura de `GridSelection`
(`handleTap`, `move`, `toggle`, `selectAll`, `clear`) que no pasa por
ningún `NSViewRepresentable` -- si el capturador de eventos del arrastre
tuviera un bug de cableado, sería un problema AISLADO al arrastre, y no
afectaría a ningún otro gesto. El guion manual de abajo lo separa
explícitamente por esa razón.

## Estado final de los ocho gestos

| Gesto | Álbumes/Películas/Series/Fotos | Canciones |
|---|---|---|
| Clic (reemplaza selección) | **Automatizado** -- `GridSelection.handleTap(_:order:modifiers:)`, forma pura sin AppKit | Manual (`MediaSectionView`/`Table`, sin seam inyectable) |
| ⌘/Ctrl+clic (alterna) | **Automatizado** | Manual |
| Shift+clic (rango, YA NO acumula -- reemplaza el rango anterior conservando lo marcado con ⌘) | **Automatizado**, incluido el caso que reduce un rango (`testShiftClickReplacesThePreviousRangeButKeepsCommandClickedItems`) | Manual |
| Shift+flechas (extiende desde el ancla, reversible) | **Automatizado** -- `GridSelection.move(_:order:columnsPerRow:extending:)` | Manual |
| Casilla | **Automatizado** -- `GridSelection.toggle(_:)` | Manual |
| Arrastre (marquee) | **Lógica automatizada** (`GridMarquee`); **cableado de eventos NO verificado automáticamente** -- ver arriba | **Pendiente** -- Canciones no tiene el seam de selección todavía |
| ⌘A/Ctrl+A por menú Edición | **Automatizado** el mecanismo (`GridSelection.selectAll(_:)`); el enrutamiento real del ítem de menú a la sección con foco es cableado de vista, no verificado por esta sesión | Manual |
| ⇧⌘A (deseleccionar) | **Automatizado** el mecanismo (`GridSelection.clear()`); mismo comentario sobre el cableado del menú | Manual |
| Escape (limpia selección) | **Automatizado** -- `GridSelection.clear()` | Manual |

## Dónde vive lo automatizado

`Tests/AuraStudioTests/GridSelectionTests.swift` -- el núcleo puro
completo: `GridSelection` (tap con los tres modificadores, `move` con las
cuatro direcciones y extensión con Shift, `applyMarquee`, `lastTapped`
público), `GridMarquee` (rect/hits/selection, reversibilidad de agrandar
y achicar), `GridDirection` (step por columna, degradado a 1 columna sin
marcos), y `GridSelectionModel` (`columnsPerRow` deducido de los marcos,
ciclo de vida del arrastre con `setFramesForTesting`).

`Tests/AuraStudioTests/AlbumsGridPerformanceBaselineTests.swift` --
`AlbumsView` hospedada de verdad con `NSHostingController` +
`GridSelectionModel` inyectado, para el costo de `body` por gesto (ver
ST-181/ST-184 en DECISIONS.md). `MoviesView`, `SeriesView` y
`PhotoAlbumsView` ya aceptan el mismo `selectionModel:` inyectable --
queda como trabajo futuro extender el mismo arnés de hosting a esas tres
si hace falta para F7.

## Guion manual (verificación con el dueño, F7)

En Álbumes, Películas, Series y Fotos (todas ya con `GridSelectionModel`)
y en Canciones (todo manual, sin seam):

1. Clic sobre un elemento — selecciona solo ese, se ve resaltado.
2. ⌘/Ctrl+clic sobre otro — se suma a la selección, sin perder el primero.
3. ⌘/Ctrl+clic de nuevo sobre el mismo — se quita, el resto queda igual.
4. Clic sobre un tercero, después Shift+clic sobre uno lejano — selecciona
   el rango completo entre ambos; un segundo Shift+clic más cerca debe
   ACHICAR el rango (no dejar seleccionado lo que ya no toca).
5. Con algo seleccionado, Shift+flecha derecha/abajo — extiende la
   selección elemento por elemento en esa dirección; Shift+flecha
   izquierda/arriba la recorta.
6. Casilla de un elemento no seleccionado — lo selecciona sin afectar al
   resto; de uno seleccionado — lo quita.
7. **(El gesto no verificado automáticamente.)** Clic y arrastre desde un
   punto vacío de la cuadrícula sobre varios elementos — los selecciona a
   todos los que toca el rectángulo; soltar cerca del borde de la ventana
   debe desplazar el scroll (autoscroll); agrandar y achicar el
   rectángulo antes de soltar debe ser reversible.
8. Menú Edición → "Seleccionar todo" (⌘A) — selecciona todo lo visible
   (respeta el filtro/búsqueda activos); "Deseleccionar" (⇧⌘A) — limpia.
9. Escape — limpia la selección completa, sin importar cómo se armó.

Verificar en cada paso que **solo** el elemento/rango tocado cambia de
apariencia (sin parpadeo de los demás) y que no hay demora perceptible
con la biblioteca completa del dueño cargada.
