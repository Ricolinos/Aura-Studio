# Guion de verificación — ronda "ajustes 3": almacenamiento e idiomas

> `PLAN-studio-ajustes-3.md` (carpeta padre `Aura/docs/plans/`), Fase A8
> (ST-228). Criterio: "guion del dueño". Este documento es ese guion --
> para correrlo con la app real, instalada (build de Release, no la de
> Debug de Xcode), contra una biblioteca de prueba.
>
> **Completado para el cierre de la ronda (0.4.0, A0-A8/ST-220-228).**
> Empezó como borrador antes de que A3 llegara a `origin/main`, con
> pasos marcados `[pendiente Ax]` donde la fase que fijaba el detalle
> todavía no había cerrado -- todas esas fases (A3-A7b, más A7c en
> código) cerraron y los pasos correspondientes ya tienen el
> comportamiento y los textos reales, no supuestos. Única excepción
> real: japonés/alemán/ruso/francés existen en el catálogo pero A7d/
> B7d (triaje de textos fuera de la extracción) no cerró, así que el
> selector de Ajustes no los ofrece hasta 0.4.1 -- ver §6.
>
> Ningún número de esta ronda se inventa acá: donde el criterio pide
> medir algo (tiempos, conteos exactos), la celda queda vacía para
> llenarse en la corrida real, o ya trae el número medido con su
> fuente en `DECISIONS.md` (§8, tabla final).

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

## 2. Modo referencia: el preparado se arma solo cuando hace falta (A4/ST-224)

Con "Referenciar en su lugar" activo en Ajustes. A diferencia del modo
copia, acá `.preparados/` NO se llena siempre -- solo cuando el
archivo de verdad lo necesita (conversión, o etiquetas distintas de
las del catálogo). Un original que ya dice lo que dice el catálogo
**nunca** tiene preparado -- es su propio preparado, y eso es
justamente lo que promete Ajustes ("no ocupa espacio extra").

1. Soltar un MP3/FLAC/M4A cuyas etiquetas YA coincidan con lo que va a
   quedar en el catálogo (p. ej. un archivo recién exportado con las
   etiquetas correctas). Tras importar, abrir `.preparados/` en Finder
   (⌘⇧. para ver ocultas si hace falta) y confirmar que **no hay
   ninguna entrada nueva** para este ítem -- `preparedURL` queda
   ausente, y eso es el estado correcto, no "todavía no se preparó".
2. Editar el título de ESE MISMO ítem. Confirmar en Finder que AHORA
   SÍ aparece `.preparados/<ID-EN-MAYÚSCULAS>.ext` (el UUID del
   elemento, no un nombre legible) -- y que el archivo original,
   fuera de la biblioteca, **no cambió** ni un byte ni de fecha de
   modificación.
3. Editar el título una segunda vez, a otro valor distinto. Confirmar
   que la fecha de modificación de `.preparados/<ID>.ext` avanzó de
   nuevo (se reescribió) -- sigue sin tocar el original.
4. Tocar el archivo ORIGINAL por fuera de Aura (en Finder: abrirlo y
   volver a guardarlo, o cualquier acción que le cambie la fecha de
   modificación) sin avisarle a Aura. Reabrir la app o forzar un
   reproceso del ítem y confirmar que el preparado se **regenera**
   (nueva fecha en `.preparados/<ID>.ext`) -- la regla es "origen más
   nuevo que el derivado", no "el catálogo cambió".
5. Soltar un WAV o AIFF en modo referencia, con "Original sin
   pérdida". A diferencia de MP3/FLAC/M4A del punto 1, acá SIEMPRE
   hay preparado (WAV/AIFF siempre necesitan conversión, nunca
   pueden ser su propio preparado): confirmar que
   `.preparados/<ID>.m4a` existe y es ALAC (mismo criterio de
   extensión que el modo copia, punto 1).
6. "Convertir referenciados en copias" **[nota A8]**: la acción existe
   en el código (`LibraryViewModel.convertReferencedToCopies`) pero
   **no tiene ningún botón que la dispare en ninguna vista** --
   confirmado revisando las Views, cero llamadas fuera de pruebas. Este
   paso no se puede correr desde la UI real todavía -- es un pendiente
   de UI a reportar, no un defecto de este guion. Mientras tanto,
   seleccionar varios ítems referenciados, incluido uno cuyo original
   esté en un disco desconectado (desmontar un volumen externo, o
   mover el archivo fuera y no reconectarlo), y llamar la acción desde
   una prueba/Xcode para confirmar en el resumen que el ausente se
   cuenta **aparte** de cualquier fallo real -- nunca mezclado en un
   solo número de "fallaron".
7. Tras esa conversión, confirmar en Finder que el archivo ORIGINAL
   sigue exactamente donde estaba (la acción **copia**, nunca mueve
   ni borra) -- y que ahora también existe una copia dentro de
   `Música/<Artista>/<Álbum>/`.

## 3. Eliminar y limpiar huérfanos (A5/ST-225, cerrado)

`OrphanScan` solo mira `.preparados/` y `.portadas/` -- **nunca**
`Música/`/`Imágenes/`/`Videos/`, esos archivos no pueden ser huérfanos
por definición (siempre pertenecen a un ítem real o no existen). El
flujo de limpieza vive en Ajustes › Biblioteca, dos pasos: "Buscar
huérfanos" primero (cuenta y muestra el tamaño), "Limpiar archivos
huérfanos" después (acción destructiva, separada de la búsqueda).

1. Eliminar un ítem en modo copia. Debe aparecer un diálogo de
   confirmación que diga cuántos archivos y cuánto ocupan antes de
   borrar. Tras confirmar: el archivo sale de `Música/` (a la Papelera
   del sistema, verificable ahí) y el ítem desaparece de la biblioteca.
2. Eliminar un ítem en modo referencia. Sin Papelera de por medio: el
   original sigue en su carpeta, byte a byte; solo desaparece de la
   biblioteca (y su preparado, `.lrc` y carátula, si tenía).
3. Provocar un huérfano a propósito (p. ej. interrumpir una operación,
   o dejar un archivo suelto en `.preparados/` a mano) e ir a Ajustes ›
   Biblioteca. Pulsar **"Buscar huérfanos"** (`ajustes.almacenamiento.
   buscarHuerfanos`): si no hay ninguno, el texto es exactamente "No
   hay archivos huérfanos: no hace falta limpiar nada." (no un botón
   deshabilitado sin explicación). Con al menos uno, aparece "Archivos
   huérfanos" (título) + una explicación de qué son ("Preparados y
   carátulas que ya no le pertenecen a ningún elemento de tu
   biblioteca...") + cuántos y cuánto ocupan (`ByteCountFormatter`) +
   el mensaje de confirmación exacto: "No están ligados a ningún
   elemento de tu biblioteca; borrarlos no afecta ninguna canción,
   foto ni video que tengas." Confirmar con **"Limpiar archivos
   huérfanos"** (`.limpiarHuerfanos`, botón destructivo) o descartar
   con "Cancelar". Tras confirmar: borra solo lo encontrado (nada
   referenciado por un ítem real, ni nada dentro de `Música/`/
   `Imágenes/`/`Videos/` -- el scan nunca los toca).

## 4. Migración de una biblioteca 0.3.0 (A6/ST-226, cerrado)

El aviso vive en una franja de `ContentView` (arriba de la lista, no
un diálogo modal) con tres estados posibles, más el mismo botón
repetido en Ajustes (`ajustes.almacenamiento.migrar`, siempre
disponible ahí porque detectar la necesidad exige abrir archivos, algo
que nunca pasa solo con abrir la app).

1. Abrir la app 0.4.0 apuntando a una biblioteca real generada con una
   versión anterior a esta ronda (0.3.x, sin `storage` en el catálogo,
   o con preparados "legacy"). Debe aparecer la franja de aviso
   ("Migrar de una versión anterior") con el motivo exacto (ítems sin
   `storage`, preparados legacy, o ambos) y el botón **"Migrar
   biblioteca"** (`franja.migrarBiblioteca`) -- **nunca** migra sola al
   abrir.
2. Sin tocar el aviso: confirmar que la biblioteca se ve y funciona
   igual que antes (lectura tolerante), y que ningún archivo cambió
   (mismo criterio que `MediaStorageAfterA5A6Tests.
   testMigrationIsNeverSilent…`).
3. Pulsar "Migrar biblioteca" (desde la franja o desde Ajustes). La
   franja cambia a progreso (barra + texto) con botón **"Detener"**
   (cancela a mitad de camino -- confirmar que un "Detener" a medias
   dice explícitamente que quedó incompleta, no el mismo resumen que
   un final normal). Al terminar sin cancelar: franja con ✓/⚠ + botón
   **"Entendido"**, resumen con conteos SEPARADOS de: etiquetas
   escritas, preparados renombrados, preparados reconstruidos,
   huérfanos borrados, y errores (nunca mezclados en un solo número).
   Confirmar que las etiquetas de los archivos en `Música/` ahora
   coinciden con el catálogo, y que `.preparados/` quedó sin huérfanos
   de la migración.

## 5. Ajustes: "Cómo guardar tu música" (A5, cerrado)

Texto real en Ajustes › Biblioteca (`libraryTab`), confirmado contra
`Localizable.xcstrings` -- coincide con lo que el plan pedía, palabra
por palabra salvo detalles menores:

> **Cómo guardar tu música.** Copiar a la Biblioteca de Aura: Aura
> controla los archivos, edita sus etiquetas y los sincroniza directo;
> ocupa espacio en disco (una copia); puedes borrar tus originales
> después. Referenciar en su lugar: no ocupa espacio extra ni toca tus
> archivos; Aura mantiene una versión preparada aparte
> (`.preparados/`), las ediciones viven solo en Aura y en el iPod, y
> si el disco original no está, esas canciones no se pueden
> sincronizar. Cambiar este ajuste solo afecta lo que importes de ahora
> en adelante...

1. Abrir Ajustes › Biblioteca y confirmar que los dos modos aparecen
   con ese texto completo, no solo el interruptor sin explicación.
2. **"Convertir referenciados en copias" NO tiene botón en esta
   pantalla (ni en ninguna otra) todavía** -- ver la nota en §2 punto
   6. No hay nada que confirmar acá hasta que se le agregue UI; no
   tratar su ausencia como un defecto de este paso, es un pendiente de
   producto a reportar aparte.

## 6. Idiomas (A7a/A7b cerrados; A7c cerrado en código, ja/de/ru/fr sin ofrecerse hasta 0.4.1/A7d)

`CFBundleLocalizations` ya declara los seis idiomas (es/en/ja/de/ru/
fr) y los seis resuelven contenido real del bundle (confirmado en vivo
esta ronda, ver `docs/capturas/idiomas/`) -- pero el **selector de
Ajustes solo ofrece tres filas en 0.4.0**: "Igual que el sistema"
(`.system`), "Español", "English" -- `AppLanguage.selectable` filtra
por `isMachineTranslated`, y japonés/alemán/ruso/francés quedan
marcados así hasta que A7d (Mac) y B7d (Windows) cierren el triaje de
textos fuera de la extracción (instalador, DFU, errores). El plan
(`PLAN-studio-ajustes-3.md`) ya lo dice explícito: "0.4.0 sale con es +
en y los cuatro idiomas salen en 0.4.1".

1. Abrir Ajustes › General y confirmar que el selector de idioma
   muestra exactamente esas tres filas hoy -- ningún idioma beta
   debe aparecer todavía en 0.4.0.
2. Cambiar de idioma (p. ej. de Español a English) **mientras hay una
   tarea en curso** (sincronización/conversión/migración/firmware).
   Debe aparecer un aviso con un solo botón, **"Entendido"** --
   "Se aplicará al siguiente arranque" / "Hay tareas en curso:
   sincronización, conversión, migración o firmware..." -- **nunca**
   se ofrece cerrar la app mientras algo está corriendo.
3. Cambiar de idioma **sin nada en curso**. Debe aparecer un aviso con
   dos botones: **"Cerrar ahora"** (cierra la app; el idioma nuevo se
   ve al volver a abrirla) y **"Más tarde"** (descarta el aviso, el
   ajuste ya quedó guardado, se aplica en el próximo arranque que sea).
   Texto: "¿Cerrar Aura Studio ahora?" / "El idioma cambia al volver a
   abrir la app, y no se toca nada de tu biblioteca ni de tu iPod. Si
   eliges «Más tarde», el ajuste queda guardado...".
4. Revisar las pantallas principales (Álbumes, Canciones) en los seis
   idiomas -- japonés y ruso ya confirmados sin desbordes ni cortes en
   estas dos pantallas (`docs/capturas/idiomas/{ja,ru}/*.png`, esta
   ronda). Ajustes, Dispositivos, Acerca de y el diálogo de importación
   quedan pendientes de confirmar visualmente -- ver `docs/capturas/
   idiomas/README.md` ("Qué falta") para el defecto que bloqueó esa
   parte de la captura automatizada.
5. Confirmar los plurales en ruso (3 formas) en algún contador visible
   (p. ej. "N canciones" en la barra de estado) -- el caso que más se
   aleja del singular/plural binario que tiene hoy el código en
   español.
6. Cuando A7d cierre y ja/de/ru/fr pasen a ofrecerse en el selector
   (0.4.1): repetir los pasos 2-3 con uno de esos cuatro elegido, y
   confirmar que aparece el aviso adicional "Traducción automática,
   aún sin revisar por hablantes nativos" (`ajustes.general.idioma.
   automatica`) -- no aplica a es/en/sistema.

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

## 8. Tabla final de la ronda (A8/ST-228)

Números medidos, no supuestos -- cada fila cita el `DECISIONS.md` que
la respalda. "Editar 5 campos" es siempre título/artista/álbum/año/
género, `audioQuality: .originalLossless` salvo donde se dice lo
contrario.

### Bytes escritos al editar, por fase (ST-220 y addenda)

| Formato | Modo | Antes (ST-220) -- bytes en `.preparados/` | Después de A3 (ST-223) -- `Música/` / `.preparados/` | Después de A4 (ST-224, solo referencia) |
|---|---|---|---|---|
| MP3  | copia      | 8 573  | 8 573 / 0 | -- (A4 no toca copia) |
| MP3  | referencia | 8 573  | 0 / 8 573 (sin cambios) | `build`, 8 573 (edición); `none`, 0 (sin cambios) |
| FLAC | copia      | 214    | 210 / 0 | -- |
| FLAC | referencia | 214    | 0 / 214 (sin cambios) | sin remedir por separado esta ronda |
| M4A  | copia      | 1 043  | 1 167 / 0 | -- |
| M4A  | referencia | 1 043  | 0 / 1 043 (sin cambios) | sin remedir por separado esta ronda |
| WAV  | copia      | 17 684 (PCM) | **1 158** (ALAC) / 0 | -- |
| WAV  | referencia | 17 684 (PCM) | 0 / 17 684 (sin cambios, A4 no tocó este camino en A3) | `build` (`.m4a`), **1 162** (ALAC) |

En ningún caso, en ninguna fase, el archivo ORIGINAL (el que se soltó
para importar) cambia -- ese es el invariante que las tres mediciones
comparten. El salto de WAV copiado (17 684 → 1 158 bytes) es la
diferencia real más grande de toda la ronda: es la prueba en bytes de
que "Original sin pérdida" para WAV/AIFF de verdad convierte a ALAC
en vez de copiar PCM crudo. Filas adicionales confirmadas con bytes:
edición sin cambios (mismos 4 formatos, modo copia) → **0 bytes, fecha
intacta**; calificación (rating) → **0 bytes**, nunca toca el archivo
de música, solo el catálogo.

Fuentes: `DECISIONS.md:10927` (ST-220, "antes"), `DECISIONS.md:13356`
(addendum, "después de A3"), `DECISIONS.md:14613` (addendum ST-224,
"después de A4").

### Conteo de claves del catálogo por idioma (tras A7c, 662fbb7)

| Idioma | Cadenas | Plurales |
|---|---|---|
| es | 486 | 47 |
| en | 486 | 47 |
| ja | 486 | 47 |
| de | 486 | 47 |
| ru | 486 | 47 |
| fr | 486 | 47 |

Los seis idiomas están completamente alineados por clave (mismo
`Localizable.xcstrings`, ninguno le falta ni le sobra una clave a
otro) -- lo que cambia es solo el VALOR de cada cadena, nunca el
conjunto de claves. Medido con `tools/compilar-catalogo.py
--output-root <temp>` (el mismo script de producción, no una
reimplementación) contra el HEAD de esta PARADA.

### Progresión de la suite completa (`swift test`)

| Momento | Pruebas | Saltadas | Fuente |
|---|---|---|---|
| Antes de la ronda | 830 | -- | histórico |
| Tras A1/A2 | 918→941 | 11→15 | histórico |
| Tras A3 | 950 | 10 | histórico |
| Tras A4, pre-rebase A7b | **970** | 3 | `DECISIONS.md:15252` |
| Tras rebase sobre A7b (117 clases) | **977** | 3 | esta sesión, `tools/swift-test-por-lotes.sh`, 100% cobertura, 0 fallas reales |

### Idiomas ofrecidos vs. idiomas con contenido (0.4.0)

Seis idiomas tienen contenido real en el catálogo; el selector de
Ajustes solo ofrece tres filas (Igual que el sistema / Español /
English) -- japonés/alemán/ruso/francés existen y se pueden invocar
por `-AppleLanguages` (ver `docs/capturas/idiomas/`) pero no aparecen
en el selector hasta que A7d/B7d cierren el triaje de textos fuera de
la extracción (0.4.1, per `PLAN-studio-ajustes-3.md`).

## Qué anotar

Para cada punto: si algo no coincide con la tabla o el comportamiento
descrito acá, anotar el paso exacto y qué se vio en su lugar -- este
guion documenta lo que el plan promete, no reemplaza el reporte de un
hallazgo real al dueño/a la sesión que corresponda. Al terminar,
**restaurar la preferencia de biblioteca** anotada en el punto 0.2
antes de cerrar la app.
