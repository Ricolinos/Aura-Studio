# Homologación de artistas — especificación vinculante

**Qué es esto.** La regla exacta con la que Aura Studio decide que
«Gorillaz feat. De La Soul» y «Gorillaz» son **el mismo artista** para
agrupar.

**Para qué.** R2-4 de la Ronda de ajustes 2 exige **la misma regla, los
mismos separadores y el mismo resultado** en macOS y en Windows. Una
diferencia acá parte la vista Artistas en dos según desde qué máquina se
abrió la biblioteca — y, peor, hace que el iPod reciba dos fotos de
artista distintas para el mismo artista.

**Implementación de referencia (macOS):**
`Sources/AuraStudio/Models/ArtistNameNormalizer.swift`.
Pruebas: `Tests/AuraStudioTests/ArtistNameNormalizerTests.swift`.

**Estado:** al 2026-09-01 (ST-116).

---

## 1. La regla

El **artista principal** es lo que precede al **primer separador de
colaboración** encontrado en el crédito.

El separador se busca como **palabra completa** — es decir, como un token
delimitado por espacios — comparado **sin distinguir mayúsculas ni
acentos**.

## 2. Los separadores — lista CERRADA

```
feat.    feat    ft.    ft    featuring    +    with    con
```

Ocho entradas, y **no se amplían "porque parece"**: cada entrada nueva
reagrupa la biblioteca de alguien de un día para el otro.

`feat.` y `feat` son entradas distintas a propósito (y `ft.` y `ft`
también): al comparar tokens completos, `feat.` no matchearía un token
`feat`.

## 3. Lo que NUNCA homologa

```
vs.    vs    versus
```

**Decisión explícita del dueño**, no un olvido: una colaboración con
identidad propia es **otro artista**, no el principal con invitados.
"Spacemonkeyz vs. Gorillaz" es un proyecto con nombre y discografía
propios; agruparlo bajo "Gorillaz" perdería esa distinción.

Se documentan como lista para que se lean como decisión.

## 4. Casos borde, todos obligatorios

| Entrada | Resultado | Por qué |
|---|---|---|
| `Gorillaz feat. De La Soul` | `Gorillaz` | El caso base. |
| `Calle 13 feat. Rubén Blades ft. Café Tacvba` | `Calle 13` | Se corta en el **primero**. |
| `Gorillaz FEAT. De La Soul` | `Gorillaz` | Sin distinguir mayúsculas. |
| `Julieta Venegas CON Juanes` | `Julieta Venegas` | `con` como palabra, sin distinguir mayúsculas ni acentos. |
| `Daft Punk` | `Daft Punk` | `ft` vive **dentro** de "Daft": no es un token. |
| `Confeti de Odio` | `Confeti de Odio` | `con` dentro de "Confeti": no es un token. |
| `Blink+182` | `Blink+182` | `+` pegado, no es un token suelto. |
| `Spacemonkeyz vs. Gorillaz` | *(sin cambio)* | `vs.` no homologa. |
| `feat. Alguien` | *(sin cambio)* | Un separador en primera posición **no deja artista principal**. Recortarlo daría cadena vacía y esa pista caería bajo "Artista desconocido" — peor que no hacer nada. |
| `  Café Tacvba  ` | `Café Tacvba` | Solo se recortan los espacios extremos. |
| `` (vacío) | `` | Nada que hacer. |

El resultado **nunca es la cadena vacía** si la entrada no lo era.

## 5. Alcance — dónde aplica y dónde NO

Aplica **solo a la AGRUPACIÓN**:

- La vista **Artistas** (una fila por artista principal).
- El **artista del álbum** con el que se agrupan los discos.
- Las **fotos de artista**: una sola foto para "Gorillaz", que es el
  efecto que R2-4 vino a conseguir.
- Los **conteos de la barra de estado**, para que no digan "3 artistas"
  debajo de una lista de dos filas.

**Jamás se reescribe el `artist` de la pista.** Los créditos completos se
conservan en la metadata, viajan en el archivo y se siguen viendo en la
tabla de canciones y en «Más información». La homologación no escribe
nada: es una función de lectura.

### Lo que deliberadamente NO cambia: las rutas en disco

Ni la carpeta local de la biblioteca
(`LibrarySync.localLibraryRelativePath`) ni la carpeta del iPod usan el
artista principal: las dos siguen armando su nombre con el valor
**crudo** (`albumArtist ?? artist`), como antes de R2-4.

Es a propósito. R2-4 pidió **agrupación**, no reorganización, y mover
carpetas en el iPod es una operación destructiva sobre archivos ya
sincronizados. **Consecuencia conocida y aceptada:** un álbum que Studio
muestra bajo "Gorillaz" puede vivir en el iPod en una carpeta
`Gorillaz feat. De La Soul`. Si el dueño quiere que también se unifiquen
las carpetas, es una decisión aparte — toca el contrato de layout y
obliga a mover archivos en el próximo sync.

### Por qué las fotos de artista funcionan sin tocar el contrato

El índice `artist_images.cfg` (CONTRATO §D.3) escribe **una línea por
cada valor crudo distinto de `metadata.artist`** dentro del grupo,
apuntando todas al mismo archivo de imagen. Al agrupar por principal,
"Gorillaz" y "Gorillaz feat. De La Soul" quedan en el mismo grupo y sus
dos líneas apuntan a `gorillaz.jpg`. El firmware sigue buscando por el
tag real de la pista y encuentra la foto. **El contrato no cambia.**

## 6. Ajuste y excepciones

- **Ajuste para desactivar**: Ajustes › Música › "Agrupar las
  colaboraciones bajo el artista principal". **Encendido por omisión.**
  Apagarlo devuelve la agrupación exacta de antes de R2-4 — sin migrar
  nada, porque la homologación nunca escribió nada.
- **Lista de excepciones editable**, en la misma pantalla: nombres que
  **no se recortan** aunque traigan un separador. Existe porque la lista
  de separadores es cerrada y ciega, y hay nombres de grupo que la
  contienen:
  - `Simon + Garfunkel`
  - `Café con Leche`

  Las excepciones se comparan **sin distinguir mayúsculas ni acentos**
  contra el crédito completo, y se guardan como arreglo nativo (no lista
  separada por comas: un nombre real puede traer una coma, como
  "Earth, Wind & Fire").

## 7. Riesgos asumidos

`con` y `with` como separadores son los más agresivos de la lista: en
español e inglés aparecen en nombres de grupo reales. No hay forma
automática de distinguir "Julieta Venegas con Juanes" (colaboración) de
"Café con Leche" (nombre) — por eso existe la lista de excepciones, y por
eso el ajuste se puede apagar entero. Está anotado acá para que la
decisión se vea, no se descubra.
