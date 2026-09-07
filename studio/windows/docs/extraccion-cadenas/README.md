# `docs/extraccion-cadenas/` — borradores de B7a/B7b, Windows

Insumo para A7a/B7a real (ST-227/ST-247). Generado por
`tools/ExtraerCadenasWindows` (`dotnet run --project tools/ExtraerCadenasWindows`),
nunca a mano — con una excepción, ver abajo.

- `revision.csv` — una fila por cadena de interfaz de Windows, con clave
  propuesta, tipo, archivo:línea, texto original, texto con `{0}`/`{1}`,
  si tiene interpolación, y una nota (cultura fija, si aplica).
- `plurales-ternario.csv` — los ternarios de plural (`n == 1 ? "..." :
  "..."`), aparte: necesitan el mecanismo real de reglas de plural de B7c,
  nunca una clave más.
- `Strings/es/Resources.resw` — borrador con el texto real en español.
- `Strings/en/Resources.resw` — mismas claves, valor vacío: nunca se
  traduce a mano acá.

## `claves-compartidas.csv` — co-propiedad con la Mac

Cotejo de las cadenas que el plan (§0.4, §2) marca como compartidas entre
las dos plataformas, contra el borrador de la Mac
(`docs/extraccion-cadenas/revision.csv` y `borrador.Localizable.xcstrings`
en la raíz del repo). **Las dos plataformas lo editan a la vez** —pasó una
vez que la Maestra tuvo que fusionarlo fila por fila a mano— así que desde
ST-247 (addendum) el reparto de columnas es una regla, no una convención:

| Columna | La edita |
|---|---|
| `clave` | quien crea la fila (la que decida el nombre compartido) |
| `texto es` | quien crea la fila |
| `sitio Mac` | **solo la Mac** |
| `sitio Windows` | **solo Windows** |
| `estado` | **solo la Mac**, salvo que Windows sea quien "cierra la paridad" (rellena el lado que faltaba en una fila que antes era `solo Mac`) — ahí lo decide quien acaba de comparar los dos textos |

Una fila nueva la agrega quien encuentra el par (o el elemento sin par) —a
mano, con criterio: qué cuenta como "la misma cadena compartida" no es
mecánico, requiere leer las dos plataformas—; el estado inicial de una fila
nueva de un solo lado es simplemente `solo Mac`/`solo Windows`.

**`ClavesCompartidasCsv.UpdateSitioWindows`** (dentro de
`ExtraerCadenasWindows`, se corre automáticamente al final de cada
`dotnet run --project tools/ExtraerCadenasWindows`) es la ÚNICA edición
automática permitida del lado Windows: parchea, clave por clave, el
`archivo:línea` de cada cita que YA existe en la columna "sitio Windows" —
nunca agrega filas, nunca toca "sitio Mac" ni "estado", nunca reescribe el
archivo entero. Si una clave citada ya no existe en `revision.csv` (un
renombre, por ejemplo), la deja tal cual y la avisa por consola en vez de
adivinar. Sin cambios reales que reflejar, el archivo queda byte a byte
idéntico — no se reescribe ni se le toca la fecha de modificación.

### Formato oficial de una cita en "sitio Windows"

`<archivo>:<línea> (<clave.de.windows>[, nota libre])` — el paréntesis al
final NO es decorativo, es el mapeo formal entre la clave compartida del CSV
(columna `clave`) y la clave real que la herramienta de Windows emite en el
`.resw` (que casi siempre trae su propio prefijo, p. ej. `app-strings.`). El
CSV es la autoridad del NOMBRE compartido; la herramienta de Windows sigue
emitiendo sus propias claves — no las renombra para calzar con el CSV. Una
cita con varias citas (varios sitios) trae un paréntesis por cada una,
separadas por `; `. `ClavesCompartidasCsv.UpdateSitioWindows` conserva este
paréntesis en cada actualización (nunca lo borra, nunca lo agrega si no
estaba). La prueba `TodaClaveCompartidaMarcadaIgualExisteEnElReswDeWindows`
(`tests/AuraStudio.Core.Tests/LocalizationDraftTests.cs`) lo usa para
verificar una fila `"igual"` cuando la clave del CSV y la clave de Windows no
coinciden textualmente: entra por este paréntesis y compara el texto real
del `.resw` contra "texto es".

Agregar una fila nueva, o decidir que dos filas de un solo lado en
realidad son la misma cadena, sigue siendo trabajo de quien lo encuentra —
eso no lo automatiza nada, porque hace falta leer las dos plataformas para
saberlo.

### Columnas nuevas de la Mac (p. ej. "texto en")

La Mac puede agregar una columna nueva al CSV compartido, en cualquier
posición, sin coordinarlo antes con Windows. `UpdateSitioWindows` ubica
"sitio Windows" leyendo el ENCABEZADO en cada corrida, nunca por un índice
fijo, así que una columna nueva antes o después de "sitio Windows" no le
hace perder el campo ni pisar el equivocado -- todo lo que no sea esa
columna, en cualquier posición, se copia carácter por carácter.
