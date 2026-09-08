# Triaje del español que B7a no alcanzó (ST-247)

B7a sacó a recursos el texto que el extractor podía ver: los atributos del
XAML y la fachada `AppStrings`. Quedó fuera todo lo que se arma en el código
—mensajes de error, avisos de progreso, descripciones de Ajustes— y para que
eso no creciera en silencio se le puso un trinquete: `HardcodedSpanishTests`
cuenta lo que queda y falla si sube.

Este documento es el triaje de esa lista, con el criterio fijado: **lo que ve
el usuario se traduce; el registro y las excepciones internas no**.

La lista línea por línea está en `triaje-fuera-de-b7a.tsv`, con la línea de
código de cada una — el texto solo no alcanza para decidir, porque «No se pudo
leer el disco» puede ser un diálogo o una entrada de bitácora.

## Avance de B7d

El `.tsv` es la foto del triaje al cerrar B7c y **no se regenera**: es contra lo
que se comprueba que la clasificación fue la que fue. Lo que va bajando es el
trinquete de `HardcodedSpanishTests`, y acá queda dicho por qué.

| paso | trinquete | qué se hizo |
|---|---:|---|
| cierre de B7c | 386 | — |
| trampa 1, `MediaInfoDialog` | 372 | los 27 textos de la hoja "Más información" a recursos en los seis idiomas, después de cambiar la llave del diccionario |
| trampas 2 y 3, `PreparedMusic` | 371 | desenlace tipado en vez de `Contains("no se pudo")`, y tres frases enteras en lugar de una a medias |
| trampa 4, `LibraryGrouping` | 369 | los rótulos de los cajones a recursos, `IsUnknownArtist` como campo, y fuera las dos comparaciones contra el rótulo en `AlbumCoverSearch` |
| paso 2, `InstallerError` | 344 | los 16 errores del asistente a recursos en los seis idiomas |
| paso 2, familia privilegiada | 324 | los 20 mensajes de `PrivilegedOperation`, `PrivilegedHost` y `PrivilegedRunner`, y el idioma viajando al proceso elevado |
| paso 2, `FirmwareArtifacts` y `DfuFlashRunner` | 309 | las dos últimas familias críticas: verificación de artefactos y grabado por DFU |
| paso 2, `SettingsViewModel` | 277 | las explicaciones de Ajustes; la de colaboraciones pasa a enumerar los separadores desde el código |
| paso 2, `DeviceFirmwareLabel` y `ExtrasViewModel` | 250 | la etiqueta de firmware con su sufijo de dual boot como hueco, y la pantalla de Extras |
| paso 2, `SyncViewModel` | 240 | la ficha de sincronización; los conteos con «archivo(s)» pasan a formas de plural de verdad |
| paso 2, temas | 218 | `ThemeInstaller`, `ThemePackager` y `ThemesViewModel`; otro «fuente(s)» a formas de plural |
| paso 2, `SimilarItemsDetector` | 206 | los motivos y la sugerencia; los nombres de campo se piden a la hoja de metadata |
| paso 2, rótulos de tabla | 194 | columnas de Canciones, estados de la biblioteca y los avisos de alcance |
| paso 2, biblioteca y cuadrículas | 168 | `LibraryViewModel`, `MediaGridViewModel` y la sección de claves de Ajustes |
| paso 2, cola de Core y de la app | 93 | aviso de versión del firmware, servicios de red, credenciales, actualizaciones, hojas y vistas sueltas |
| paso 2, razones de Abort | 91 | las nueve razones por las que NO se escribe en el disco, más lo que la segunda barrida sacó con ellas |
| paso 2, cierre de la barrida | 91 | ~45 frases que el trinquete **no cuenta**: el trinquete no baja, y por eso hizo falta la barrida |
| paso 3, las 11 DATO | 91 | comprobadas: su valor no cambia con el idioma, y por eso el trinquete tampoco baja |

El trinquete baja poco en el segundo paso y eso es correcto: **doce literales
cambiaron de clase, no de sitio.** Las razones de `PreparedMusic` estaban como
PANTALLA porque salían a la barra de estado pegadas a otra frase; ahora que el
mensaje se elige por el desenlace, esas razones son lo que siempre debieron ser
—diagnóstico— y se quedan en español a propósito. Cuentan igual en el
trinquete, que mide literales en español y no si están bien puestos; lo que
bajó de la deuda de traducción son doce, aunque el número de arriba diga uno.

## El trinquete es un piso, no un censo

**Este triaje salió de `HardcodedSpanishTests`, y por eso heredó su ceguera.**

El trinquete decide qué es español con una **lista de palabras** —«archivo»,
«canción», «álbum», «biblioteca»…—. Una frase que no contenga ninguna de ellas
no la ve, y hay muchas: «Formatos distintos», «Misma duración», «El árbol de X
en el iPod está incompleto», «Se importó «X» con N canciones».

Así que **las 303 de la tabla de abajo eran un subconteo**. No era la lista de
todo lo que el usuario lee; era la lista de lo que ese léxico alcanzaba.

Se descubrió por un error de método: las sustituciones se venían haciendo con
`s///` **sin `/g`**, y el detector de parecidos repite los mismos motivos en
tres bloques —música, video, foto—. La primera pasada convirtió solo la primera
aparición de cada frase. **El trinquete no vio ninguna de las diez que quedaron
sin convertir.**

Lo que sí las vio fue una segunda barrida con otra señal:
`barrida-frases.pl`, que busca literales de **dos o más palabras** que no
parezcan ruta, identificador ni clave. Da más ruido a propósito — es para leer,
no para contar, y ningún número suyo entra en un trinquete. Encontró, entre
otras, **las nueve razones por las que Aura Studio se niega a escribir en el
disco**, que este triaje había clasificado como bitácora y que el usuario lee
justo cuando el formateo se detiene.

La regla que queda: **el trinquete sirve para que no crezca; no sirve para dar
por terminado un archivo.** Eso hay que hacerlo leyendo el archivo.

## Conteo

| clase | cuántas | qué se hace |
|---|---:|---|
| PANTALLA | 303 | sale a recurso y se traduce a los seis idiomas |
| INTERNO | 67 | se queda en español: bitácora y excepciones que nadie ve |
| DATO | 11 | **no se traduce nunca**: se compara, se guarda o nombra una carpeta |
| TRAMPA | 5 | algo depende del texto en español; traducirlo rompe algo |
| **total** | **386** | |

Son 386 y no 392 porque B7c ya se llevó seis al arreglar las dos frases
compuestas a medias (`LibraryMigrationText`). El trinquete sigue en 392: es un
techo, no una meta.

**303 literales no son 303 frases.** Una frase larga partida en cinco líneas
de fuente cuenta cinco veces — las descripciones de Ajustes son así. El número
de mensajes distintos es bastante menor; el de líneas a tocar, ese.

## Lo que no es texto: DATO

Once literales que parecen español y no lo son. Traducirlos no cambia lo que
se lee: cambia lo que el programa hace.

- `MediaCategory.cs` — `"Fotos"` / `"Imágenes"`: la categoría que se guarda en
  `item.category`, cuyo valor canónico es el español (D-283). El nombre en
  pantalla ya sale aparte, por `LocalizedName()`.
- `LibrarySyncFinalizer.cs`, `LibraryPersistence.cs` — comparan contra esos
  mismos valores.
- `LibraryOptions.cs` — `["Imágenes", "Fotos", "IA"]`: carpetas de la
  biblioteca en disco.
- `LibraryFileLayout.cs` — `"Sin categoría"`: también una carpeta.
- `StorageBreakdown.cs` — la clave de una sección del desglose.
- `LibraryGrouping.cs` — la lista de artículos (`"the "`, `"los "`, `"el "`…)
  con la que se ordena ignorando el artículo inicial. Es el algoritmo, no un
  texto.
- `Mks5lbootOutput.cs` — `"no DFU devices found"`: se busca en la salida de
  `mks5lboot.exe`. Es de la herramienta, no nuestro.

## Lo que rompe si se traduce: TRAMPA

Cinco sitios donde el comportamiento depende del texto. Los cuatro primeros
hoy funcionan y esperan a que alguien traduzca; el quinto ya está mal.

### `MediaInfoDialog.cs:136` — pérdida de datos silenciosa

Los campos del formulario viven en un diccionario **con la etiqueta de
pantalla como llave**: `Field("Álbum", …)` guarda y `Text("Álbum")` lee.

Traducir las etiquetas rompe de dos formas, y ninguna avisa. Si se traducen
las dos puntas y una queda distinta, `Text` usa `TryGetValue` y devuelve
cadena vacía: el usuario edita el álbum, guarda, y el álbum se borra. Y
`fields[key]` de la línea 136 no usa `TryGetValue` — ahí sí, la hoja de
metadata revienta al abrirse.

El arreglo es llevar la llave a un identificador estable y que la etiqueta sea
solo lo que se pinta. Es la misma separación de `MediaCategory`.

### `LibraryViewModel.cs:1851` — un `Contains` sobre prosa

```csharp
if (result.Action != PreparedMusicAction.None || result.Reason.Contains("no se pudo"))
```

Decide si mostrar el aviso de fallo buscando un pedazo de frase dentro de la
razón que devuelve `PreparedMusicBuilder`. No hace falta traducir nada para
que se rompa: basta con que alguien reescriba una de esas razones en español y
diga «no fue posible». El aviso deja de salir y nadie se entera.

`PreparedMusicResult` tiene que decir si falló con un campo, no con una
palabra dentro de una oración.

### `PreparedMusic.cs` y `PreparedMusicBuilder.cs` — razones que sí se ven

Las once razones (`"el archivo de origen cambió de tamaño"`, `"hay que
convertirlo y no hay convertidor"`…) parecen internas y salen a pantalla
pegadas a otra frase:

```csharp
StatusMessage = $"No se pudo preparar «{name}» para el iPod: {result.Reason}"
```

Es exactamente la frase compuesta a medias que B7c ya arregló dos veces
(`LibraryMigrationText`): la mitad de la oración saldría del recurso y la otra
mitad se quedaría en español. Van juntas o no van.

### `LibraryGrouping.cs:156,158` — `"Sin álbum"` es rótulo y centinela

Se muestra como título del grupo **y** se compara en `AlbumCoverSearch` para
no salir a buscar tapa de un álbum que no tiene título. La comparación es
contra la misma constante, así que traducirla no la rompe hoy; pero deja un
rótulo de pantalla haciendo de bandera, que es de dónde salen los bugs de
mañana. Le toca lo mismo que a `MediaCategory`: una bandera y una etiqueta.

### `TMDBClient.cs:69` — esta ya está mal

```csharp
string language = "es-MX")
```

Todas las consultas a TMDB piden los datos en español de México, siempre. Es
de donde salen los títulos y las sinopsis de películas y series, así que la
app en japonés muestra al usuario texto en español que vino de la red.

No es una cadena de interfaz y por eso ninguna prueba de extracción la iba a
ver nunca: es un parámetro. Tiene que seguir a `CultureInfo.CurrentUICulture`.

## Qué queda para después

Traducir las 303 es una fase, no un paso: son seis idiomas y, sobre todo, unas
setenta y siete caen en familias que `CriticalStrings` marca como críticas
—`InstallerError`, `PrivilegedHost`, `FirmwareArtifacts`, `DfuFlashRunner`,
`PrivilegedRunner`—, es decir texto que habla de formatear el disco, de DFU y
del bootloader. Ese texto no se manda a cuatro idiomas sin la ronda de
retrotraducción a ciegas que se le hizo al resto; hacerlo sería quedarse con
la etiqueta de revisado y sin la revisión.

Las trampas sí conviene arreglarlas antes, y no por la traducción: cuatro de
las cinco son bugs latentes con el texto en español intacto.
