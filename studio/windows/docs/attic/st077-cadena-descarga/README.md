# Ático — cadena de descarga ST-077 (contrato v17)

> **Dos de los tres archivos ya se remontaron** (R4 / ST-132):
> `ReleaseCache.cs` y `FirmwareVersionResolver.cs` viven ahora en
> `AuraStudio.Core/Installer/`, con pruebas, alimentando las pastillas de
> versión de la pantalla Extras. Las copias de acá se dejan **solo como
> registro de dónde vinieron**; la versión viva es la de Core.
>
> **Lo que sigue apartado es `FirmwareReleaseDownloader.cs`**: la descarga real
> de los assets del Release. Extras necesitaba saber *qué versión se
> instalaría*, no bajarla — y bajarla es otra tarea, con sus cinco trampas
> documentadas más abajo intactas.

> **Esto no es código del build.** `docs/` no entra en ningún `.csproj`, así que
> nada de acá se compila ni se prueba. No muevas el descargador a
> `AuraStudio.Core/` tal cual: no compila contra el modelo de artefactos que
> sobrevivió (ver "Cómo remontarlos").

## Qué implementan

La política de **ST-077 / `CONTRATO-firmware-studio.md` v17**: *instalar desde
cero baja el Release **más nuevo** de la familia elegida; el pin de
`FIRMWARE_VERSION` — lo que `scripts\FirmwareFetch.ps1` dejó en `artifacts\` —
pasa a ser el **respaldo**, no la única vía.*

| Archivo | Qué hace |
|---|---|
| `FirmwareReleaseDownloader.cs` | Baja y verifica los assets del Release más nuevo, y los publica en el directorio de caché. |
| `ReleaseCache.cs` | Caché de la lista de Releases con TTL de 24 h, **por familia**, sobre una interfaz de almacenamiento (`IReleaseCacheStore`) en vez de `UserDefaults`. |
| `FirmwareVersionResolver.cs` | Qué tag se instalaría **hoy** (el de GitHub, o el local marcado como tal) — lo que la pastilla de versión de Extras tiene que mostrar. |

Origen macOS: `Services/FirmwareReleaseDownloader.swift`, el `enum ReleaseCache`
de `Services/AuraUpdateChecker.swift` y
`ViewModels/AvailableFirmwareVersions.swift`.

## Los cinco detalles que ST-077 pagó caro y que hay que conservar

Están comentados en el código, uno por uno. Si la Fase 6 los reescribe desde
cero, que sea con esta lista a la vista:

1. **La URL del API, nunca `browser_download_url`.** La segunda redirige a un
   host de almacenamiento que **rechaza** la cabecera `Authorization` de GitHub,
   así que en un repo privado (ST-074) falla. Se pide
   `/repos/:owner/:repo/releases/assets/:id` con
   `Accept: application/octet-stream`.
2. **`Authorization` se suelta en el 302 a otro host.** `HttpClient` —igual que
   `URLSession`— la reenviaría sola al seguir la redirección, y eso es
   exactamente lo que rompe la descarga. Por eso el salto se sigue a mano.
3. **Publicación atómica.** Se baja a `.descarga-<tag>\` y solo se renombra al
   directorio final cuando **todo** pasó la verificación. Un corte a la mitad no
   puede dejar un directorio que la próxima corrida dé por completo.
4. **`IsSafeTagComponent` antes de componer una ruta.** El tag nunca entra crudo
   a un `Path.Combine`: alfanuméricos, `.`, `-`, `_`; sin separadores, sin `..`,
   ≤ 64 — mismo criterio que `AuraThemeID.IsValid()` para los ids de tema.
5. **Fallar nunca detiene la instalación.** Cualquier problema (sin red, token
   sin acceso, Release incompleto, checksum que no cuadra) se convierte en "se
   instala lo que ya estaba, **y por esto**". `ReleaseDownloadFailed` /
   `ReleaseMissingAsset` existen para poder **decir** por qué se instaló la
   versión incluida, no para abortar nada.

Un sexto, propio de Windows y sin equivalente en el Swift: el Release publica
`mks5lboot` (binario Unix) y **no** `mks5lboot.exe`. El descargador baja los
cuatro assets que sí publica y copia el `.exe` local junto a ellos, para que el
runner y el bootloader sigan saliendo del mismo directorio. Ver `ToolProvenance`
en `AuraStudio.Core/FirmwareArtifacts.cs`, que es donde ese hueco quedó
modelado y visible.

## Por qué se apartaron del build

Se escribieron en la Fase 2 colgando de un **modelo de artefactos duplicado**
(un tipo `BundledArtifacts` propio, port directo del `struct` de macOS) que se
descartó al reconciliar el árbol: el modelo que sobrevivió es
`AuraStudio.Core/FirmwareArtifacts.cs`, que además resuelve cosas que el
duplicado no tenía (`ArtifactScope`, `ToolProvenance`/`ToolOrigin`). Mantener
dos modelos del mismo hecho era la deuda peor de las dos, así que se fue el
duplicado — y con él, estos tres archivos, que eran sus únicos consumidores.

Lo que se apartó es la **cadena de descarga**, no la política: nada de esto
estaba integrado todavía en el asistente cuando se apartó.

## Cómo remontarlos (Fase 6)

La conversión es mecánica y chica. `FirmwareArtifacts` ya expone lo que hace
falta:

| Uso en estos archivos | Equivalente que sobrevivió |
|---|---|
| `new BundledArtifacts(dir, family)` | `FirmwareArtifacts.Load(dir, family)` |
| `BundledArtifacts.ForFamily(root, family)` | `FirmwareArtifacts.Load(FirmwareArtifacts.DirectoryFor(root, family), family)` |
| `artifacts.VerifyAll()` | `FirmwareArtifactVerifier.Verify(artifacts, ArtifactScope.All)` → devuelve un resultado, **no lanza** |
| `artifacts.PathOf(ArtifactName.X)` | `artifacts.RockboxImage` / `RockboxArchive` / `Mks5lboot` / `BootloaderImage` / `Checksums` |
| `BundledArtifacts.FileNameOf(...)` / `ReleaseAssetNameOf(...)` | nombres literales; la distinción `mks5lboot` (Release) vs `mks5lboot.exe` (Windows) vive hoy en `ToolOrigin`/`ToolProvenance` |
| `artifacts.IsComplete` | `FirmwareArtifactVerifier.Verify(..., ArtifactScope.All).IsValid` |
| `artifacts.ReleaseTag` | igual (`FirmwareArtifacts.ReleaseTag`) |
| `BundledArtifacts.VersionMarkerFileName` | `FirmwareArtifacts.VersionMarkerFileName` |
| `BundledArtifacts.Sha256Hex(path)` | `FirmwareArtifactVerifier.Sha256Hex(path)` |

Un cambio de forma, no solo de nombres: `VerifyAll()` **lanzaba**
`InstallerException` y `Verify(...)` **devuelve** un
`ArtifactVerificationResult`. Los dos puntos donde importa son la verificación
de lo recién bajado (antes de renombrar al directorio final) y el atajo de
"esto ya estaba bajado y verificado": los dos tienen que mirar `IsValid` en vez
de atrapar una excepción.

Al remontarlos hace falta además:

- Una implementación real de `IReleaseCacheStore` (JSON bajo
  `%LOCALAPPDATA%\Aura Studio\`, junto a `preferences.json` — **nunca** el token
  de GitHub ahí: eso es Credential Manager, D-203/ST-032/ST-074).
- El token de solo lectura de ST-074 llegando desde `IApiKeyStore`.
- Tests: el Swift tiene `FirmwareReleaseDownloaderTests` (12 casos) como guía —
  tag inseguro rechazado, caché por familia y por tag, Release sin `assets`,
  descarga que exige la URL del API + `Accept` + `Bearer`, asset truncado,
  404 con su código, Release al que le falta un asset, rechazo de token.

## Alcance

Nada de esto tocó `studio/AuraStudio/` (macOS) ni ningún contrato. La política
ST-077 sigue siendo la vigente del lado macOS y la que la Fase 6 debe traer a
Windows.
