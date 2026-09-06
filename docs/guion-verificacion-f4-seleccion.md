# Guion de verificación — F4: selección tipo Finder completa

> PLAN-studio-rendimiento-2.md §B, Fase F4 (ST-184). Criterio de cierre:
> "(M) guion XCUITest o manual documentado de los ocho gestos en Álbumes
> y Canciones". Este archivo es ese guion — se llena de verdad (con qué
> se automatizó y qué quedó solo manual) cuando "experto en código opus"
> cierre F4; por ahora es la preparación que pidió "Sesión Maestra"
> mientras esa PARADA no existe todavía.

## Los ocho gestos (§A del plan)

Clic, ⌘/Ctrl+clic, Shift+clic, Shift+flechas, casilla, arrastre
(marquee), ⌘A/Ctrl+A (y ⇧⌘A para deseleccionar) por menú Edición, Escape.

## Estado de cada uno, hoy (antes de F4)

| Gesto | Álbumes | Canciones |
|---|---|---|
| Clic (reemplaza selección) | Automatizado — `GridSelectionModel.selection.handleTap(_:order:modifierFlags:[])`, ver `AlbumsGridPerformanceBaselineTests` | Manual (tabla nativa, sin seam inyectable todavía) |
| ⌘/Ctrl+clic (alterna) | Automatizado — `handleTap(_:order:modifierFlags:[.command])` | Manual |
| Shift+clic (rango) | Automatizado — `handleTap(_:order:modifierFlags:[.shift])` | Manual |
| Shift+flechas (mueve el ancla) | **Pendiente de F4** — `GridSelection` no tiene hoy un método para esto (`lastTapped` es privado); F4 lo expone | Manual |
| Casilla | Automatizado — `GridSelectionModel.selection.toggle(_:)` | Manual |
| Arrastre (marquee) | **Pendiente de F4** — no existe ningún mecanismo hoy, ni manual (no hay nada que probar) | **Pendiente de F4** |
| ⌘A/Ctrl+A por menú Edición | Parcial — `GridSelection.selectAll(_:)` ya existe y se prueba (`.onKeyPress` en `AlbumsView`), pero el atajo hoy es un `.onKeyPress` de la vista, no una entrada real del menú Edición — F4 lo enruta ahí | Manual |
| ⇧⌘A (deseleccionar) | No existe todavía como atajo — hoy es `Escape` el que limpia | Manual |
| Escape (limpia selección) | Automatizado — `GridSelection.clear()` | Manual |

## Qué se puede automatizar con `GridSelectionModel` inyectable (Álbumes)

Los cinco gestos ya cubiertos arriba usan el mismo arnés que ST-181/ST-182
(`NSHostingController` + `GridSelectionModel<String>` inyectado en
`AlbumsView.init`, ver `AlbumsGridPerformanceBaselineTests.
hostAlbumsView`). Cuando F4 agregue Shift+flechas y el menú Edición, la
forma más directa de seguir automatizando es la misma: exponer el
mecanismo (ancla + dirección, o la acción del menú) como un método
público de `GridSelection`/`GridSelectionModel` que la prueba pueda
llamar directo, igual que `handleTap(_:order:modifierFlags:)` ya separó
el gesto de leer `NSEvent.modifierFlags` real (ST-152).

**El arrastre (marquee) es la excepción real.** Por diseño traduce
`mouseDragged` a un rectángulo que cruza con los marcos de las tarjetas
vía `anchorPreference` (`NSViewRepresentable`, patrón de
`TableHeaderMenu.swift`) — no hay un método puro equivalente a
"simular un arrastre" sin simular eventos de mouse reales sobre una
ventana real. Esto queda **solo manual** (o XCUITest de verdad, con el
costo de infraestructura que eso implica) incluso después de que F4 lo
implemente.

## Canciones: por qué todo sigue manual

`MediaSectionView` (la tabla de Canciones) no tiene hoy un seam
inyectable equivalente a `GridSelectionModel` — su selección vive en el
mecanismo nativo de `Table`/`SelectionStore`, no en un objeto que una
prueba pueda mutar desde afuera sin hospedar la vista completa con datos
reales de tabla. F4 "rehace la selección de todas [las cuadrículas] de
fondo" según el experto — si de paso expone un seam parecido para
Canciones, este documento se actualiza para automatizar esa columna
también.

## Guion manual (para cuando F4 cierre, verificación con el dueño)

En Álbumes y en Canciones, por separado:

1. Clic sobre un elemento — selecciona solo ese, se ve resaltado.
2. ⌘/Ctrl+clic sobre otro — se suma a la selección, sin perder el primero.
3. ⌘/Ctrl+clic de nuevo sobre el mismo — se quita, el resto queda igual.
4. Clic sobre un tercero, después Shift+clic sobre uno lejano — selecciona
   el rango completo entre ambos.
5. Con algo seleccionado, Shift+flecha derecha/abajo — extiende la
   selección elemento por elemento en esa dirección; Shift+flecha
   izquierda/arriba la recorta.
6. Casilla de un elemento no seleccionado — lo selecciona sin afectar al
   resto; de uno seleccionado — lo quita.
7. Clic y arrastre desde un punto vacío de la cuadrícula sobre varios
   elementos — los selecciona a todos los que toca el rectángulo;
   soltar cerca del borde de la ventana debe desplazar el scroll
   (autoscroll).
8. Menú Edición → "Seleccionar todo" (⌘A) — selecciona todo lo visible
   (respeta el filtro/búsqueda activos); "Deseleccionar" (⇧⌘A) — limpia.
9. Escape — limpia la selección completa, sin importar cómo se armó.

Verificar en cada paso que **solo** el elemento/rango tocado cambia de
apariencia (sin parpadeo de los demás) y que no hay demora perceptible
con la biblioteca completa del dueño cargada.
