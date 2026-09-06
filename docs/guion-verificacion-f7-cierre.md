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
