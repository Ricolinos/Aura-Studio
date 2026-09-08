# Capturas por idioma

PLAN-studio-ajustes-3.md §3, Fase A7c (ST-227 addendum). Generadas por
[`tools/capturas-idiomas.sh`](../../../tools/capturas-idiomas.sh) + su
compañero
[`tools/capturas-idiomas-window-id.swift`](../../../tools/capturas-idiomas-window-id.swift)
-- ver esos dos archivos para el detalle completo del mecanismo (lanza
la app DEBUG con `-AppleLanguages`/`-AppleLocale` + las variables
`AURA_UITEST_*`, navega seleccionando filas de la barra lateral por
`accessibilityIdentifier` con AppleScript/System Events, obtiene el
`CGWindowID` con Quartz vía el Swift porque System Events no lo expone
en esta versión de macOS, y captura por ventana con `screencapture
-l`).

## Estructura

```
docs/capturas/idiomas/<idioma>/<pantalla>.png
```

`<idioma>` ∈ `es`, `en`, `ja`, `de`, `ru`, `fr`.
`<pantalla>` ∈ `albumes`, `canciones`, `ajustes`, `dispositivos`,
`acerca-de` (más `ajustes-almacenamiento` y
`barra-estado-mensaje-largo` cuando existan -- ver "Qué falta" abajo).

## Estado (2026-09-07, tras A7c)

**Los seis idiomas ya producen contenido real.** A7c (commit 662fbb7)
cerró: `CFBundleLocalizations` declara `es/en/ja/de/ru/fr` y cada uno
resuelve del bundle de verdad (confirmado visualmente, ver abajo).

**`albumes.png` y `canciones.png` confirmados y comiteados para los
seis idiomas** (`es en ja de ru fr`, japonés y ruso corridos primero
por riesgo de ancho de texto). Verificados a mano contra la app real
(build Debug fresca sobre 662fbb7, lanzada con `-AppleLanguages`,
navegada por `accessibilityIdentifier`, capturada por `screencapture
-l <CGWindowID>`). Sin desbordes ni cortes de texto en ninguna de las
dos pantallas en ninguno de los seis idiomas -- ni siquiera en ruso
("Настройки", "Дополнения", "Установка" caben cómodos en el ancho fijo
de la barra lateral).

Observación para A7d (no es tarea mía, solo la anoto porque la vi en
vivo): en `ja` y `ru`, "Fotos"/"Imágenes" (grupo Fotos) y el
placeholder "Buscar en Álbumes" del buscador quedaron sin traducir --
todo el resto de la barra lateral sí cambió de idioma. Screens:
`ja/albumes.png`, `ru/albumes.png`.

**`ajustes.png` -- defecto real encontrado y NO comiteado.** El
mecanismo `select_sidebar_row` (AppleScript `select` sobre el `AXRow`
que contiene `biblioteca.barraLateral.ajustes`) no dispara el cambio
de selección de SwiftUI: la llamada devuelve éxito (sin error) pero la
pantalla visible se queda en la que estaba antes. Confirmado dos
veces, con la Mac libre y sin nada más corriendo: (1) desde el estado
inicial (`General`), seleccionar `ajustes` deja la pantalla en
`General`; (2) desde `Álbumes`, seleccionar `ajustes` deja la pantalla
en `Álbumes`. En la corrida por lotes de hoy esto pasó para LOS SEIS
IDIOMAS -- `ajustes.png` era, byte a byte casi idéntico,
`canciones.png` (la pantalla previa) en cada uno; se borraron esas seis
capturas mal etiquetadas en vez de comitear algo que no es Ajustes.
Esto también explica por qué `ajustes-almacenamiento`/`dispositivos`/
`acerca-de` fallaron: el script nunca llegó de verdad a Ajustes, así
que el resto de los pasos partía de un estado equivocado (`Álbumes`/
`Canciones` según el idioma corrido primero).

Por qué `select` sí funciona en `albumes`/`canciones` (mismo mecanismo,
misma estructura de `AXRow` -- comprobado con un volcado del árbol de
accesibilidad, ambas filas son estructuralmente idénticas) y no en
`ajustes` sigue sin explicarse -- **y ya no es solo `select`**.

**Segunda sesión en vivo (2026-09-07, más tarde, Mac libre de nuevo tras
el barrido A7d)**: se probaron TRES mecanismos distintos contra la fila
`biblioteca.barraLateral.ajustes`, cada uno confirmado con una
captura/lectura real, no solo "sin error":

1. `select` sobre el `AXRow` (el original) -- pantalla se queda igual.
2. `perform action "AXPress"` sobre el mismo `AXRow` -- **también**
   deja la pantalla igual (probado desde el estado inicial `General`,
   la app queda en `General`).
3. Un clic sintético REAL (`click at {x, y}`, System Events) en el
   centro exacto de la fila (posición/tamaño leídos en el momento con
   `position of`/`size of` sobre el mismo `AXRow`) -- **también** deja
   la pantalla igual.

Los tres confirmados con una captura visual del resultado (no solo el
retorno del comando), en una Mac verificablemente libre (tiempo de
inactividad subiendo de forma continua, sin saltos, durante toda la
prueba). Los tres fallan de la MISMA manera -- la fila nunca cambia la
selección de SwiftUI -- lo que descarta que sea un problema de "el
mecanismo de clic equivocado" (hipótesis original) y apunta a algo más
estructural en cómo esta fila en particular (bajo el rótulo "Aura
Studio", fuera de `SidebarSection.deviceSections`) está conectada al
`selection` del `NavigationSplitView` -- una pregunta de `Sources/`
(`ContentView.swift`) que no me corresponde perseguir más a fondo.

**Efecto secundario encontrado, anotado para quien siga**: la
verificación por AppleScript (`containsIdentifier`, recorrido
recursivo del árbol de accesibilidad) que hasta ahora había sido
rápida y confiable **se colgó dos veces seguidas por más de 2 minutos**
justo después de probar `AXPress` y el clic real contra esta fila --
hubo que matar el proceso `osascript` a mano (no terminaba solo). No
se pudo determinar si el árbol de accesibilidad quedó en un estado más
grande/inestable tras esos intentos, o si es una lentitud de
AppleScript bajo cierta carga -- quien retome esto debe tener cuidado
con confiar ciegamente en que esa verificación siempre responde rápido,
y matar el proceso a mano si se cuelga en vez de esperarlo indefinidamente.

## Qué falta (para la próxima vez que la Mac esté libre)

- **La fila `ajustes` (y probablemente `general`/dispositivos, mismo
  grupo "Aura Studio" fuera de `deviceSections`) no responde a NINGÚN
  mecanismo de accesibilidad ni a un clic sintético real** -- los tres
  se probaron y fallaron igual. El siguiente paso ya no es "probar otro
  mecanismo de clic", es entender en `Sources/ContentView.swift` cómo
  esta fila conecta con `selection` (o si necesita Accessibility
  Inspector de Xcode en vivo, mirando el AX real mientras se hace clic
  a mano, para ver qué evento SÍ dispara el cambio) -- candidato claro
  para pasarle a "experto en código opus" como pregunta puntual, no
  para seguir adivinando mecanismos de AppleScript.
- **`ajustes-almacenamiento`**: la pestaña existe
  (`ajustes.pestana.almacenamiento`, ST-225/A5) pero el paso previo
  (llegar a Ajustes) es el que está roto -- sigue sin poderse probar.
- **`barra-estado-mensaje-largo`**: necesita disparar una operación
  real (importar/sincronizar en curso) para que `LibraryStatusBar`
  muestre un mensaje largo, y confirmar que no se corta -- no
  automatizado todavía, queda como `TODO` explícito en el script.

## Mapeo pantalla → identificador/mecanismo

| Pantalla | Cómo se llega |
|---|---|
| `albumes` | `accessibilityIdentifier` `biblioteca.barraLateral.albumes` |
| `canciones` | `accessibilityIdentifier` `biblioteca.barraLateral.canciones` |
| `ajustes` | `accessibilityIdentifier` `biblioteca.barraLateral.ajustes` (pestaña General, la que muestra el selector de idioma) -- **`select` no dispara el cambio de selección, ver "Estado" arriba; no confiar en este mecanismo todavía** |
| `ajustes-almacenamiento` | `ajustes.pestana.almacenamiento` (ST-225/A5) dentro de Ajustes -- `AXPress` directo, no `select` de fila (sin confirmar en vivo; depende de llegar a Ajustes primero) |
| `dispositivos` | `accessibilityIdentifier` `biblioteca.barraLateral.general` (`DeviceGeneralView`, sin ningún iPod conectado en esta corrida -- el estado "sin dispositivo" también es una pantalla real) -- mismo mecanismo `select` que `ajustes`, sin confirmar en aislamiento todavía |
| `acerca-de` | panel estándar de macOS, por POSICIÓN de menú (primer ítem del menú de la app) -- nunca depende del idioma ni de un identificador propio |

## Biblioteca de prueba

El script genera su propia biblioteca sintética (dos artistas, tres
álbumes, cinco canciones) en un directorio temporal -- **nunca la
biblioteca real del dueño**. Se apunta con `AURA_UITEST_LIBRARY`, que
solo existe en builds DEBUG (`Sources/AuraStudio/Models/
UITestEnvironment.swift`) y nunca se guarda en Ajustes.
