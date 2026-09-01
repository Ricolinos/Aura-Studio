# Carátula recomendada — especificación vinculante

**Qué es esto.** El algoritmo exacto con el que Aura Studio elige, entre
varias carátulas candidatas para un álbum, cuál recomendar — y con qué
confianza puede aplicarla **sin preguntar**.

**Para qué.** R2-3 de la Ronda de ajustes 2 exige que las dos apps
(macOS y Windows) se comporten **idéntico**. "Parecido" no sirve: si las
dos recomiendan tapas distintas para el mismo disco, el dueño ve la
biblioteca cambiar sola según desde qué máquina la abrió. Este documento
es la fuente; el código lo calca.

**Implementación de referencia (macOS):**
`Sources/AuraStudio/Services/AlbumCoverScoring.swift` y
`AlbumCoverSearch.isBetter` / `recommended(from:)`.
Pruebas: `Tests/AuraStudioTests/AlbumCoverScoringTests.swift`.

**Estado:** al 2026-09-01 (ST-115). Si cambia un número, cambia en los
tres lugares — este documento, macOS y Windows — en el mismo cambio.

---

## 1. Qué se puntúa

Se puntúa **cada candidata**, no cada álbum. Una candidata es una imagen
concreta ya descargada, que viene de:

- **Cover Art Archive**, una por cada *edición* (release) que MusicBrainz
  devolvió para el álbum. Ediciones distintas del mismo disco suelen
  tener arte distinto: ahí está la variedad real que se le ofrece al
  usuario.
- **Deezer**, si está habilitado en Ajustes › Servicios. Deezer **no es
  una edición**: no trae año, ni número de pistas, ni estatus, ni país.
  Por construcción solo puede sumar el puntaje del título.

Se puntúa contra los **hechos del álbum en la biblioteca**: su título, su
año y su número de pistas.

## 2. La tabla de puntaje

| Criterio | Puntos | Cuándo suma |
|---|---:|---|
| Título del álbum coincide | **50** | El título de la edición, normalizado, es igual al del álbum. Normalizar = recortar espacios extremos e ignorar mayúsculas y acentos. Dos títulos vacíos **no** son coincidencia. |
| Año coincide | **25** | El año de la edición es igual al año del álbum. Ambos deben existir y no estar vacíos. |
| Número de pistas coincide | **15** | La edición declara tantas pistas como tiene el álbum en la biblioteca. Un conteo de **0 nunca coincide**. |
| Edición oficial | **6** | `status == "Official"`, sin distinguir mayúsculas. |
| Declara país | **2** | El campo `country` existe y no está vacío. |
| País preferido | **+2** | Además, el país está en `{XW, MX, US, GB}` (`XW` = mundial en MusicBrainz). Acumula con el anterior: máximo 4 por país. |
| Tapa frontal real | **10** | La imagen venía marcada como `front` en Cover Art Archive. Una imagen sin esa marca puede ser la contratapa o la cara del disco: sirve como último recurso, **no** como recomendación. |

**Máximo alcanzable: 110.**

El orden de la tabla es el orden de importancia que fijó la planeadora, y
los pesos están elegidos para que ese orden **se respete siempre**: nada
de lo de abajo puede compensar la falta de algo de arriba. Concretamente,
todo lo que está debajo del título suma 62 < 50 + 25: una edición con
título distinto nunca le gana a una con título igual y año igual.

## 3. El umbral de aplicación automática

**85 de 110.**

Una candidata se puede aplicar **sin preguntar** solo si su puntaje es
**mayor o igual a 85**. Las dos combinaciones mínimas que llegan:

- título + año + tapa frontal = 50 + 25 + 10 = **85**
- título + nº de pistas + oficial + país preferido + tapa frontal
  = 50 + 15 + 6 + 4 + 10 = **85**

Y lo que deliberadamente **no** alcanza:

- solo el título = 50. Es el caso que el umbral existe para frenar:
  "Greatest Hits" coincide de título con el "Greatest Hits" de cualquier
  otro artista.
- título + todas las señales menores (oficial + país + frontal) = 70. Sin
  año ni número de pistas no hay corroboración suficiente, por más
  "oficial" que sea la edición.
- cualquier candidata de **Deezer** sola: su techo es 50.

## 4. Desempates

A igual puntaje se decide en este orden, y **hay que agotarlo**: el
resultado tiene que ser el mismo en las dos apps y en dos corridas de la
misma app.

1. Mayor puntaje.
2. La que tiene **tapa frontal** marcada.
3. La de **edición oficial**.
4. La de **año más antiguo** — la edición original antes que las
   reediciones: es la tapa que la gente reconoce como la del disco. Una
   edición **sin año va al final** (no se puede afirmar que sea la
   original).
5. **Cover Art Archive** antes que Deezer.
6. El **orden de descubrimiento** (la posición en que la fuente la
   devolvió). Este último es el que garantiza un orden total: sin él, dos
   candidatas empatadas hasta acá quedarían en orden indefinido.

La lista de candidatas que se le muestra al usuario va **ordenada por
este mismo criterio**, así que la recomendada es siempre la primera.

## 5. Comportamiento en la interfaz

- El picker **marca "Recomendada"** la primera candidata y la
  **preselecciona**, con un botón **«Usar recomendada»** cuando el
  usuario ya movió la selección a otra.
- El picker **nunca aplica solo**, ni siquiera cuando hay una sola
  candidata ni cuando supera el umbral. Recomendar acelera la decisión;
  no la reemplaza.
- La **acción automática** ("Aplicar carátula recomendada", desde el
  menú contextual de Álbumes, sobre uno o varios) aplica **solo** las que
  superan el umbral. Las que no lo superan **no se tocan** y se cuentan
  en el resumen: aplicar a ciegas una tapa dudosa a veinte álbumes es
  exactamente el daño que el umbral evita.
- Si queda **exactamente un** álbum sin opción segura, se abre su picker
  ("si no lo supera, cae al picker"). Con varios no se abre ninguno: una
  fila de pickers encadenados no se puede usar, y el resumen ya dice
  cuántos quedaron pendientes.

## 6. `metadataEditedByUser`

Se marca **solo cuando la eligió el usuario a mano**.

La automática **no** lo marca. `metadataEditedByUser` significa "el
usuario lo decidió", no "algo lo escribió": blindar una tapa que nadie
miró dejaría al álbum con ella para siempre, incluso cuando después
aparezca una mejor.

## 7. Lo que no cambia respecto de ST-104

Sigue vigente todo lo de "Buscar carátulas del álbum": se exige **un solo
álbum** de destino (ni mezclas ni "Sin álbum"), se **deduplican** las
imágenes idénticas, se aplica a **todas** las canciones del álbum, se
vuelve a preparar cada archivo conservando el anterior si falla, y
**sin resultados se explica en pantalla**.
