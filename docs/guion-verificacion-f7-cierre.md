# Guion de verificación — F7: cierre de la ronda de rendimiento

> PLAN-studio-rendimiento-2.md §B, Fase F7 (ST-187). Criterio: "el guion
> de verificación interactiva con el dueño". Este documento es ese
> guion -- para correrlo con la app real, instalada, y la biblioteca
> del dueño (o una copia sintética de tamaño comparable si todavía no
> se quiere tocar la real).
>
> Para el detalle de los ocho gestos de selección (clic, ⌘/Ctrl+clic,
> Shift+clic, Shift+flechas, casilla, arrastre, ⌘A/⇧⌘A, Escape) ver
> `docs/guion-verificacion-f4-seleccion.md` -- este documento no lo
> repite, lo referencia.

## Antes de empezar

- Build de Release instalada (`scripts/build-app.sh`), no la de Debug de
  Xcode -- una build vieja en DerivedData puede no traer los cambios de
  esta ronda.
- Si se usa la biblioteca real del dueño: **hacer una copia de
  `biblioteca.json` y `.portadas/`** antes de abrir la app con esta
  build, en una carpeta aparte, y apuntar Ajustes a esa copia -- nunca
  la carpeta viva. La migración de `fileSizeBytes`/`coverHash` (F5/F6)
  escribe el catálogo en el primer guardado, y la app 0.2.3 instalada
  sigue leyendo el archivo real -- una prueba que lo toque por error
  podría desincronizar las dos.

## 1. Álbumes

1. Abrir la sección Álbumes. Debe verse la cuadrícula sin demora
   perceptible (objetivo: ventana interactiva < 1 s, aunque la
   biblioteca siga cargando en segundo plano).
2. ⌘A -- selecciona todo lo visible. Debe sentirse instantáneo (< 100 ms)
   y las tarjetas deben mostrar su casilla marcada sin parpadeo.
3. Escape -- limpia la selección.
4. Clic en la primera tarjeta, Shift+clic hasta la última (con 1 000
   álbumes, esto es un Shift+clic real de 1→1000) -- debe sentirse
   instantáneo, sin que la ventana se congele ni un instante.
5. Arrastre (marquee): clic y arrastre desde un hueco de la cuadrícula
   sobre varias tarjetas -- deben quedar seleccionadas todas las que
   toca el rectángulo; soltar cerca del borde de la ventana debe mover
   el scroll solo (autoscroll). **Este es el único de los ocho gestos
   que no quedó verificado automáticamente en esta ronda** (ver
   `docs/guion-verificacion-f4-seleccion.md` y ST-188 en DECISIONS.md) --
   presta más atención acá que en el resto.

   **Antes de este punto, hay una corrida aparte y previa: el XCUITest
   real del arrastre** (`AlbumsGridMarqueeDragUITests`, ST-187/ST-188),
   que la sesión de Claude Code corre por su cuenta -- no reemplaza este
   punto 5 (que sigue siendo la verificación de que el gesto SE SIENTE
   bien), pero si ese XCUITest queda en verde, el punto 5 solo necesita
   confirmar la sensación, no la mecánica.

   **Condiciones exactas para esa corrida, ninguna del código** (tres
   intentos en esta ronda fallaron cada uno por una de estas, nunca por
   el gesto en sí -- confirmado por "experto en código opus" tras
   revisar `MainWindowPlacer`):
   - El permiso de automatización/accesibilidad de macOS para el
     ejecutor de pruebas, ya concedido una vez por el dueño
     (2026-09-06) -- si se revocara, hay que concederlo de nuevo antes
     de intentar.
   - **Nadie usando la Mac mientras corre.** No es una preferencia, es
     un límite real: una sesión gráfica de macOS es una sola, y un
     XCUITest toma el cursor y el foco de teclado para sintetizar sus
     eventos. Si el dueño (o cualquiera) está trabajando en la Mac al
     mismo tiempo -- incluso en otra pantalla -- la prueba falla de una
     forma distinta cada vez (la ventana no llega a dibujarse, la
     barra de menús salta de pantalla, el foco se lo lleva otra app),
     y cada fallo parece un bug nuevo cuando no lo es. El dueño puede
     mirar la pantalla mientras corre -- lo que no puede es usar el
     mouse o el teclado de esta Mac en ese rato.
   - La ventana de la app se coloca sola en la pantalla que tenga la
     barra de menús (`AURA_UITEST_MAIN_SCREEN=1`, seam de DEBUG) -- no
     hace falta preparar nada de pantallas de antemano, solo que nadie
     esté usando la máquina durante la corrida.
6. Con varios álbumes seleccionados, clic derecho → "Buscar carátulas de
   N álbumes..." -- el menú debe aparecer sin demora perceptible (< 200
   ms), y la acción en lote debe mostrar progreso "N de M" en el centro
   de tareas, con opción de cancelar.
7. Scroll completo de la cuadrícula -- sin tirones ni parpadeos; las
   miniaturas deben aparecer solas a medida que se desplaza (no de
   golpe todas, no en blanco).

## 2. Canciones

1. ⌘A con las 12 000 canciones -- debe sentirse instantáneo.
2. Clic derecho → debe existir ahora "Buscar carátulas de N álbumes..."
   (antes de esta ronda esta acción NO existía en Canciones -- era el
   reporte original del dueño). Debe abrir sin demora perceptible.
3. Los dudosos deben encolarse en el selector uno por uno, con "Álbum X
   de Y" / "Omitir este álbum" / "Cancelar el resto".

## 3. Fotos

1. Abrir la sección Fotos (o un álbum de fotos con varias decenas de
   fotos). El mosaico de cada álbum debe aparecer sin bloquear el
   scroll -- las miniaturas se rellenan solas, nunca se lee el archivo
   completo de golpe.

## 4. Importar 200 elementos

1. Soltar ~200 archivos (fotos y/o video mezclados) sobre la biblioteca.
2. Mientras se procesan, la ventana debe seguir respondiendo -- se puede
   seguir navegando, seleccionando, sin que nada se congele.
3. El centro de tareas debe mostrar progreso y permitir cancelar.

## 5. Sincronizar

1. Con el iPod conectado, iniciar una sincronización con cambios reales
   (algo que de verdad haya que copiar/actualizar).
2. La ventana debe seguir respondiendo durante la sincronización.
3. Al terminar, la biblioteca y el estado de sincronización de cada
   ítem deben quedar correctos (sin repetir un sync completo para
   confirmarlo).

## Qué anotar

Para cada punto: ¿se sintió instantáneo (< 100-200 ms según el caso), o
hubo alguna demora perceptible? Cualquier congelamiento real (la ventana
deja de responder, aunque sea un instante) es justo lo que esta ronda
buscó eliminar -- anotar el paso exacto donde pasó, para poder
reproducirlo con Instruments.
