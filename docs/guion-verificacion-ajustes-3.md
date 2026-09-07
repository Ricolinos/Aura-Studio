# Guion de verificación — ronda "ajustes 3": almacenamiento e idiomas

> `PLAN-studio-ajustes-3.md` (carpeta padre `Aura/docs/plans/`), Fase A8
> (ST-228). Criterio: "guion del dueño". Este documento es ese guion --
> para correrlo con la app real, instalada (build de Release, no la de
> Debug de Xcode), contra una biblioteca de prueba.
>
> **Borrador escrito antes de que A3 llegue a `origin/main`** -- los
> pasos cuyo detalle todavía no está fijado (porque la fase que lo
> define no cerró) quedan marcados `[pendiente Ax]`. Cuando esa fase
> cierre, quien la cierre completa el detalle exacto (textos de UI,
> capturas) en vez de rediseñar el paso.
>
> Ningún número de esta ronda se inventa acá: donde el criterio pide
> medir algo (tiempos, conteos exactos), la celda queda vacía para
> llenarse en la corrida real.

## 0. Antes de empezar

1. **Biblioteca de prueba, nunca la real.** Crear una carpeta aparte
   con un puñado de canciones/fotos/videos de prueba (MP3, FLAC, M4A,
   WAV, AIFF -- al menos una de cada uno, más un álbum con dos discos y
   dos fotos que en origen se llamen igual, `IMG_1.jpg`, para los
   pasos 8). Apuntar Ajustes › Biblioteca a esa carpeta antes de tocar
   nada -- **nunca** la carpeta viva del dueño para este guion.
2. **Anotar la preferencia de biblioteca ANTES de cambiarla** (Ajustes
   › Biblioteca, la ruta actual) para poder restaurarla exactamente al
   terminar. Este guion no debe dejar la app apuntando a la carpeta de
   prueba después de correrlo.

## 1. Modo copia: importar y editar

Para cada formato (MP3, FLAC, M4A, WAV, AIFF), con "Copiar a la
Biblioteca de Aura" activo en Ajustes:

1. Importar con la calidad de audio en **"Original sin pérdida"**.
   Confirmar en `Música/<Artista>/<Álbum>/` qué archivo aparece y con
   qué extensión, según la tabla:

   | Formato de origen | Extensión en `Música/` con "Original sin pérdida" |
   |---|---|
   | MP3 | `.mp3` (sin convertir) |
   | FLAC | `.flac` (sin convertir) |
   | M4A/ALAC | `.m4a` (sin convertir) |
   | WAV | `.m4a` (ALAC, sin pérdida -- WAV de 8 bits sube a 16 bits) |
   | AIFF | `.m4a` (ALAC, sin pérdida -- igual que WAV) |

2. Importar con la calidad de audio en **"Comprimido"**. Confirmar:

   | Formato de origen | Extensión en `Música/` con "Comprimido" |
   |---|---|
   | MP3 | `.mp3` (sin convertir -- ya está comprimido) |
   | FLAC | `.mp3` (256 kbps) |
   | M4A/ALAC | `.mp3` (256 kbps) |
   | WAV | `.mp3` (256 kbps) |
   | AIFF | `.mp3` (256 kbps) |

   **Sin ffmpeg instalado** (Ajustes › Servicios, o desinstalarlo antes
   de esta prueba a propósito): importar en "Comprimido" cualquiera de
   los sin pérdida de arriba debe **fallar con un motivo visible**
   ("instala ffmpeg…" o similar) -- nunca copiar sin convertir en
   silencio. Confirmar que Ajustes también avisa junto al interruptor
   de calidad que "Comprimido" necesita ffmpeg.

3. Editar el título de una canción ya importada (cualquier formato).
   Confirmar en Finder (o abriendo el archivo en un reproductor/`mdls`)
   que:
   - El archivo en `Música/<Artista>/<Álbum>/` cambió (fecha de
     modificación nueva, y el título nuevo se lee de verdad en sus
     etiquetas).
   - El archivo original de origen (el que se soltó para importar, si
     todavía existe en su ubicación original fuera de la biblioteca) **no
     cambió** -- ni su fecha ni sus etiquetas.
   - `.preparados/` no tiene ninguna entrada para este ítem -- en modo
     copia ya no interviene.

## 2. Modo referencia: mismo juego, `.preparados/` mínimo

Con "Referenciar en su lugar" activo en Ajustes, repetir la importación
de los cinco formatos y la edición de título del punto 1, pero
verificando lo contrario:

1. El archivo original (fuera de la biblioteca) **nunca** cambia -- ni
   al importar ni al editar título ni al calificar/marcar favorito.
2. `.preparados/<ID>.ext` solo existe para los ítems que de verdad
   necesitaron conversión (WAV/AIFF siempre; FLAC/M4A/MP3 solo si la
   calidad es "Comprimido") **o** cuyas etiquetas quedaron editadas
   distinto de lo que dice el original. Un MP3 sin editar, con
   "Original sin pérdida", no debería tener preparado -- el original
   ya es su propio preparado.
3. Editar el título de un ítem que SÍ tenía preparado por conversión
   (p. ej. un WAV) y confirmar que el preparado se regenera reflejando
   el título nuevo, sin tocar el original.

## 3. Eliminar y limpiar huérfanos `[pendiente A5]`

> El comportamiento de fondo ya está decidido (§0.4 del plan): copia →
> Papelera con confirmación; referencia → solo del catálogo. Lo que
> falta cerrar es la UI real (texto exacto del diálogo, botón "Limpiar
> archivos huérfanos" en Ajustes) -- completar este punto con capturas
> cuando A5 cierre.

1. Eliminar un ítem en modo copia. Debe aparecer un diálogo de
   confirmación que diga cuántos archivos y cuánto ocupan antes de
   borrar. Tras confirmar: el archivo sale de `Música/` (a la Papelera
   del sistema, verificable ahí) y el ítem desaparece de la biblioteca.
2. Eliminar un ítem en modo referencia. Sin Papelera de por medio: el
   original sigue en su carpeta, byte a byte; solo desaparece de la
   biblioteca (y su preparado, `.lrc` y carátula, si tenía).
3. Provocar un huérfano a propósito (p. ej. interrumpir una operación,
   o dejar un archivo suelto en `.preparados/` a mano) y correr
   "Limpiar archivos huérfanos" desde Ajustes -- debe listar lo que va
   a borrar, pedir confirmación, y borrar solo eso (nada referenciado
   por un ítem real).

## 4. Migración de una biblioteca 0.3.0 `[pendiente A6]`

> §0.3 del plan fija el comportamiento (nunca silenciosa, aviso +
> botón, escribe etiquetas y marca `storage`, borra huérfanos, con
> progreso y cancelación) pero no el texto ni la ubicación exacta del
> aviso -- completar con capturas cuando A6 cierre.

1. Abrir la app 0.4.0 apuntando a una biblioteca real generada con una
   versión anterior a esta ronda (0.3.x, sin `storage` en el catálogo).
   Debe aparecer un aviso explícito -- **nunca** migrar sola al abrir.
2. Sin tocar el aviso: confirmar que la biblioteca se ve y funciona
   igual que antes (lectura tolerante), y que ningún archivo cambió
   (mismo criterio que `MediaStorageAfterA5A6Tests.
   testMigrationIsNeverSilent…`, ya escrita esperando esta API).
3. Pulsar "Migrar biblioteca" (desde el aviso o desde Ajustes). Debe
   mostrar progreso, permitir cancelar, y al terminar reportar un
   conteo de archivos tocados. Confirmar que las etiquetas de los
   archivos en `Música/` ahora coinciden con el catálogo, y que
   `.preparados/` quedó sin huérfanos de la migración.

## 5. Ajustes: "Cómo guardar tu música" `[pendiente A5]`

> El texto sustantivo ya está fijado (§2 del plan, "beneficios y
> desventajas") -- confirmar que la UI real lo muestra con esas
> palabras (o equivalentes, revisar con el dueño) cuando A5 cierre:
> Copiar a la Biblioteca de Aura -- Aura controla los archivos, edita
> sus etiquetas y los sincroniza directo; ocupa espacio en disco (una
> copia); se pueden borrar los originales después. Referenciar en su
> lugar -- no ocupa espacio extra ni toca los archivos; Aura mantiene
> una versión preparada aparte; las ediciones viven solo en Aura y en
> el iPod; si el disco original no está, esas canciones no se pueden
> sincronizar.

1. Abrir Ajustes › (sección de almacenamiento/biblioteca) y confirmar
   que los dos modos aparecen con esos textos, no solo el interruptor
   sin explicación.
2. Confirmar que existe la acción "Convertir referenciados en copias"
   (con progreso) y que corre sin romper nada sobre un puñado de ítems
   referenciados de prueba.

## 6. Idiomas `[pendiente A7]`

> A7a/A7b/A7c todavía no cerraron (extracción, inglés, japonés/alemán/
> ruso/francés) -- este punto queda como esqueleto hasta que haya un
> selector real y traducciones reales que revisar.

1. Cambiar el selector de idioma en Ajustes (una vez exista) a cada
   idioma disponible.
2. Revisar las pantallas principales (Álbumes, Canciones, Ajustes, el
   diálogo de importación) en cada idioma -- ningún literal debe seguir
   en español fijo, ningún texto debe verse cortado o desbordado
   (japonés en botones y en la barra de estado es el caso más
   propenso).
3. Confirmar los plurales en ruso (3 formas) en algún contador visible
   (p. ej. "N canciones" en la barra de estado) -- el caso que más se
   aleja del singular/plural binario que tiene hoy el código en
   español.

## 7. Sincronizar y comprobar nombres en el iPod

1. Con el iPod conectado, sincronizar la biblioteca de prueba armada en
   el punto 0 (que incluye el álbum de dos discos y las dos fotos
   `IMG_1.jpg`).
2. **Álbum doble, número de disco**: confirmar que las pistas de ambos
   discos llegan al iPod con nombres de archivo DISTINTOS -- ninguna
   pista de un disco debe sobrescribir a la del otro por compartir el
   mismo número de pista (p. ej. "01" en Disco 1 y Disco 2).
3. **Dos fotos `IMG_1.jpg`**: confirmar que ambas llegan al iPod con
   nombres distintos y legibles (nunca un sufijo ` 2` feo, nunca una
   pisando a la otra) -- mismo criterio que confirmó
   `PhotoStagingCollisionTests` tras el addendum de ST-221.
4. Confirmar en el propio iPod (pantalla del firmware, no solo el
   Finder/Explorador) que ambas pistas/fotos aparecen y reproducen/
   muestran lo que corresponde -- no solo que el archivo llegó, que el
   firmware lo indexó bien.

## Qué anotar

Para cada punto: si algo no coincide con la tabla o el comportamiento
descrito acá, anotar el paso exacto y qué se vio en su lugar -- este
guion documenta lo que el plan promete, no reemplaza el reporte de un
hallazgo real al dueño/a la sesión que corresponda. Al terminar,
**restaurar la preferencia de biblioteca** anotada en el punto 0.2
antes de cerrar la app.
