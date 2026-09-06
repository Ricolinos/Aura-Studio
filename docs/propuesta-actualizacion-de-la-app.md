# Propuesta — "Buscar actualizaciones" de Aura Studio (Mac y Windows)

> **ESTADO: PROPUESTA, sin implementar.** ST-191, encargo (4) de la
> sesión maestra: escribirla para fijarla con Windows *antes* de tocar
> código. Nada de lo que sigue está construido.

## El problema

Aura Studio ya sabe avisar de una versión nueva **del firmware** (ST-046,
ST-074, ST-150: `GitHubReleaseChecker` + `AuraUpdateChecker`), pero no
sabe nada de sí misma. Quien tenga instalada la 0.2.1 no se entera de que
existe la 0.2.3 salvo que vaya a mirar el repositorio. Y como el firmware
que la app sabe instalar viaja **dentro** de la app (`FIRMWARE_VERSION`,
assets embebidos), una app vieja es también un firmware viejo: las dos
cosas se arrastran juntas.

## Qué se propone, en una línea

Comparar la versión de la app contra el Release más nuevo de
`Ricolinos/Aura-Studio`, decirlo donde ya se habla de versiones, y
ofrecer **descargar el instalador**. No auto-actualizar.

## 1. Cuándo consulta

- **Al arrancar**, una vez, en segundo plano, y **como mucho una vez cada
  24 h** (marca en preferencias). Nunca bloquea el arranque ni la
  ventana.
- **A pedido**, desde Ajustes › Acerca de, con un botón "Buscar
  actualizaciones" que siempre consulta (ignora el intervalo) y siempre
  dice algo, incluso "ya tienes la más nueva".
- **Nunca** durante una instalación de firmware ni durante una
  sincronización: son los dos momentos en que el dueño está esperando
  algo y no queremos ni una petición de red compitiendo.

**Sin red no pasa nada y no se dice nada** en el chequeo automático. En
el chequeo a pedido sí se dice, porque ahí el usuario preguntó.

Esto último ya tiene precedente en la ronda: Windows ST-210 acaba de
arreglar justamente que "Buscar actualizaciones" de Dispositivos no
distinguía "sin red" de "sin novedades".

## 2. Cómo compara versiones

- **Lo instalado**: en macOS, `CFBundleShortVersionString` del bundle; en
  Windows, el `<Version>` del ensamblado. Los dos ya existen y ya se
  suben juntos en cada release (regla de `CLAUDE.md` § Releases: los tres
  lugares a la vez).
- **Lo publicado**: `GET /repos/Ricolinos/Aura-Studio/releases`, la misma
  llamada que ya se usa para el firmware, y por el mismo motivo se usa
  `/releases` y no `/releases/latest`: `/latest` excluye prereleases por
  definición de GitHub, y mientras Studio siga en `0.x` beta esa llamada
  no devolvería nada útil.
- **La comparación**: SemVer, ignorando drafts. Una prerelease cuenta
  como candidata solo si la instalada también lo es, o si el usuario
  activó "incluir versiones beta". (Hoy TODO es beta, así que en la
  práctica cuenta siempre; el ajuste importa el día que haya un canal
  estable.)
- **Nunca ofrece "actualizar" hacia atrás**: si lo publicado no es
  estrictamente mayor, no hay novedad.

### Qué reutiliza cada plataforma

| Pieza | macOS | Windows |
|---|---|---|
| Parseo y orden de versiones | `SemVer` (`GitHubReleaseChecker.swift`) — ya existe, sirve tal cual | equivalente en Core; **si no lo hay, se porta desde Swift** |
| Consulta a la API de GitHub | `GitHubReleaseChecker.fetchReleases` — hoy toma `FirmwareFamily`; hay que **generalizarla a "un repo cualquiera"** | `GitHubReleaseChecker` de Core (ST-210) |
| Token opcional del Llavero | `GitHubToken` — ya existe; sube el límite de 60 a 5000 peticiones/hora | equivalente ya usado por ST-210 |
| Elegir el Release más nuevo | `pickLatest(from:includePrereleases:)` — ya existe | `FirmwareVersionResolver.LatestPublishedAsync` |
| Decidir si hay que actualizar | **nuevo**: `AppUpdateDecision` | **nuevo**: `AppUpdateDecision`, mismas reglas — el hermano de `FirmwareUpdateDecision` |

`AppUpdateDecision` es la única pieza nueva de lógica y es **pura**:
`(versión instalada, releases publicados, incluir prereleases, plataforma
y arquitectura) → (hay novedad, cuál, qué asset descargar)`. Se prueba
entera sin red en las dos plataformas, y es lo que conviene que sea
idéntico a los dos lados.

## 3. Qué asset descarga cada plataforma

Aquí está **el único contrato nuevo** de la propuesta: el nombre de los
assets del Release. Hoy (v0.2.3) son exactamente:

```
AuraStudio-<versión>.dmg
AuraStudioSetup-<versión>-arm64.exe
AuraStudioSetup-<versión>-x64.exe
```

La propuesta es **fijar ese patrón** y que `AppUpdateDecision` elija por
él:

- macOS → el `.dmg` (uno solo, universal).
- Windows → el `.exe` que coincida con la arquitectura del proceso
  (`arm64` o `x64`). Elegir mal acá es peor que no ofrecer nada: ST-135
  ya documenta que el Setup x64 en una máquina ARM avisa y deja
  continuar, pero ofrecerlo por defecto sería empujar al usuario a la
  versión lenta.

**Si el asset esperado no está en el Release, no se ofrece descarga**: se
dice que hay una versión nueva y se enlaza la página del Release. Un
botón "Descargar" que falla es peor que no tenerlo.

## 4. Qué muestra

Dos lugares, ninguno modal:

1. **Ajustes › Acerca de**, junto a la versión que ya se muestra: una
   línea con el estado ("Estás en la 0.2.3, la más nueva" / "Hay una
   versión nueva: 0.3.0") y el botón de buscar.
2. **Un aviso discreto** cuando el chequeo automático encuentra algo:
   una franja en la parte de abajo, del mismo tipo que
   `CoverNormalizationBar` (ST-141) o la barra de estado — **no** un
   diálogo. Con "Ver qué hay de nuevo" (abre las notas del Release) y
   "Descargar". Se puede cerrar, y cerrada no vuelve por esa misma
   versión.

**Lo que no se hace**: nada modal, nada que interrumpa, y ningún aviso
repetido por la misma versión. La app no es un canal de marketing.

## 5. Qué hace "Descargar"

Deliberadamente **no** hay auto-actualización.

- **macOS**: baja el `.dmg` a la carpeta de Descargas, con progreso en el
  centro de tareas (`BackgroundTaskCenter`) y cancelación, y al terminar
  lo muestra en Finder. El usuario monta y arrastra, como siempre.
- **Windows**: baja el `.exe` que corresponde y lo **ejecuta**. El
  instalador es Inno Setup por usuario y sin UAC (ST-135), así que puede
  correr sin privilegios y reemplazar la instalación existente; la app se
  cierra cuando el instalador arranca.

### Por qué no auto-actualizar en macOS

Una app no puede reemplazarse a sí misma mientras corre sin un ayudante
externo (el patrón de Sparkle: un binario aparte que espera a que la app
muera, mueve el bundle y la relanza). Eso es un componente nuevo, con
firma propia, que hay que mantener y en el que hay que confiar. **No vale
la pena** para una app que se distribuye fuera de la App Store, con firma
ad-hoc, y cuyo dueño es una persona: bajar un DMG y arrastrarlo es un
paso, no un problema.

En Windows sí se ejecuta el instalador porque **ya existe** y ya sabe
actualizar sobre lo instalado: no hay componente nuevo que mantener.

## 6. Seguridad

- Solo se consulta y se descarga de `https://api.github.com` y de la URL
  de asset que devuelve esa misma API. Nunca una URL construida a mano ni
  venida de otro lado.
- **Se verifica el SHA-256** del archivo bajado contra el que publican
  las notas del Release (ya se publican ahí — ver el release de v0.2.3).
  Si no coincide, se borra y se dice; no se abre nada.
- El token de GitHub, si lo hay, es de solo lectura y vive en el Llavero
  (`GitHubToken`); es opcional y solo sube el límite de peticiones.
- La app **nunca** ejecuta nada bajado sin que el usuario lo pida: en
  macOS ni siquiera monta el DMG.

## 7. Lo que queda fuera a propósito

- Canales (estable/beta) más allá del interruptor de "incluir
  prereleases". Hoy todo es beta.
- Actualización silenciosa o programada.
- Notas de la versión dentro de la app: se enlaza la página del Release,
  que ya las tiene y no hay que mantener por duplicado.
- Actualización del **firmware** desde acá: ya existe y es otro flujo
  (`AuraUpdateChecker`, Dispositivos › Buscar actualizaciones).

## 8. Preguntas para fijar con Windows antes de implementar

1. ¿El patrón de nombres de los assets se congela tal cual está
   (`AuraStudio-<v>.dmg`, `AuraStudioSetup-<v>-<arch>.exe`), o se
   aprovecha para normalizarlo? **Cualquier cambio hay que hacerlo antes
   de que exista código que dependa de él.**
2. ¿`AppUpdateDecision` se escribe primero en Swift y se porta, o al
   revés? (La ronda 2 fue en las dos direcciones; lo que importa es que
   una de las dos sea la referencia y la otra la cite.)
3. El intervalo de 24 h para el chequeo automático: ¿se guarda por
   plataforma o se fija igual en las dos?
4. ¿El aviso discreto aparece también en Windows como franja, o allá
   encaja mejor en el `InfoBar` que ya usa la app?
