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

## Estado (2026-09-07)

**Solo `es` produce contenido real hoy.** `CFBundleLocalizations`
declara únicamente español (`docs/auditoria-idiomas.md`) -- A7a/A7b/A7c
todavía no cerraron, así que correr el script con `en`/`ja`/`de`/`ru`/
`fr` ejercita el MISMO mecanismo pero cae al mismo español fijo. El
resto de los idiomas no se comitea todavía -- no aportaría nada
distinto de ver.

**De `es/`, dos pantallas confirmadas y comiteadas hoy: `albumes.png` y
`canciones.png`.** Verificadas a mano contra la app real (lanzada,
navegada por `accessibilityIdentifier`, capturada por `screencapture
-l <CGWindowID>`, contenido correcto -- biblioteca de prueba visible,
título de ventana correcto). `ajustes.png`/`dispositivos.png`/
`acerca-de.png` usan el MISMO mecanismo en el script (mismo tipo de
fila de barra lateral, o menú posicional para "Acerca de") pero una
prueba en vivo se interrumpió a mitad de la corrida porque la Mac dejó
de estar libre (`frontmost` cambió a otro proceso -- alguien más
usándola) y se cortó por precaución, mismo criterio que ST-187 con
XCUITest. No se comitean capturas sin confirmar visualmente -- se
corren y se agregan la próxima vez que la Mac esté libre.

## Qué falta (para quien cierre A7c)

- **`ajustes-almacenamiento`**: no existe todavía una pestaña de
  Ajustes para esto -- `SettingsSectionView.Tab` hoy es `general/
  library/music/photos/video/services`, ninguna se llama
  "Almacenamiento". Se agrega cuando ST-225 la cree. **Recomendación
  para quien la agregue**: dale un `accessibilityIdentifier` real a la
  pestaña (el `Picker` segmentado de `SettingsSectionView` hoy no tiene
  ninguno -- se navega por texto, que solo sirve para español) para que
  este script pueda seguir usando identificadores en vez de texto
  localizado también ahí.
- **`barra-estado-mensaje-largo`**: necesita disparar una operación
  real (importar/sincronizar en curso) para que `LibraryStatusBar`
  muestre un mensaje largo, y confirmar que no se corta -- no
  automatizado todavía, queda como `TODO` explícito en el script.
- **Idiomas reales**: en cuanto A7b (inglés) o A7c (japonés/alemán/
  ruso/francés) tengan contenido, correr `tools/capturas-idiomas.sh en
  ja de ru fr` (o el idioma que corresponda) y comitear el resultado.

## Mapeo pantalla → identificador/mecanismo

| Pantalla | Cómo se llega |
|---|---|
| `albumes` | `accessibilityIdentifier` `biblioteca.barraLateral.albumes` |
| `canciones` | `accessibilityIdentifier` `biblioteca.barraLateral.canciones` |
| `ajustes` | `accessibilityIdentifier` `biblioteca.barraLateral.ajustes` (pestaña General, la que muestra la versión instalada) |
| `dispositivos` | `accessibilityIdentifier` `biblioteca.barraLateral.general` (`DeviceGeneralView`, sin ningún iPod conectado en esta corrida -- el estado "sin dispositivo" también es una pantalla real) |
| `acerca-de` | panel estándar de macOS, por POSICIÓN de menú (primer ítem del menú de la app) -- nunca depende del idioma ni de un identificador propio |

## Biblioteca de prueba

El script genera su propia biblioteca sintética (dos artistas, tres
álbumes, cinco canciones) en un directorio temporal -- **nunca la
biblioteca real del dueño**. Se apunta con `AURA_UITEST_LIBRARY`, que
solo existe en builds DEBUG (`Sources/AuraStudio/Models/
UITestEnvironment.swift`) y nunca se guarda en Ajustes.
