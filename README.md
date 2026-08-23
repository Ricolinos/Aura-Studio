# Aura Studio

App nativa de macOS (Swift/SwiftUI, Apple Silicon) para instalar el firmware **Aura** en un iPod Classic 6G (2008) y gestionar su biblioteca de música, fotos y videos.

Este repositorio es solo la app. El firmware que instala (fork de Rockbox, GPL v2, con la interfaz "Aura UI") vive en un **repositorio aparte**, sin dependencia de rutas entre ambos: Aura Studio consume sus binarios y la paleta de colores únicamente a través de **GitHub Releases**, nunca leyendo su árbol de fuentes directamente. El contrato completo entre los dos repositorios — qué se publica, cumplimiento GPL de lo que esta app embebe, y el formato de los archivos que ambos leen/escriben en el disco del iPod — está en [`CONTRATO-firmware-studio.md`](CONTRATO-firmware-studio.md).

## Por qué esta app existe

El iPod Classic no expone un modo de transferencia de archivos estándar utilizable a mano: instalar un firmware alternativo requiere hablar el protocolo DFU del dispositivo, y sincronizar música requiere generar la base de datos indexada que el firmware espera. Aura Studio hace ambas cosas con una interfaz gráfica, sin depender de Terminal ni de conocimiento técnico del usuario — ver [`docs/guia-instalacion.md`](docs/guia-instalacion.md).

## Por qué no está sandboxed / no está en la App Store

Aura Studio necesita hablar directo con IOKit/DiskArbitration para detectar el iPod y desmontarlo programáticamente, y ejecutar el binario `mks5lboot` embebido para el flasheo DFU — el sandbox de la App Store restringe justamente eso. La app se distribuye fuera de la App Store, firmada localmente (ver `DECISIONS-ARCHIVE.md`, D-033).

## Temas

Extras → Temas: instala, activa, elimina y construye paquetes de tema
(fuentes + íconos + paleta) para el iPod, además del tema integrado
("Aura") y de Claro/Oscuro. Studio es un **constructor**, no un
distribuidor — un tema construido con assets de licencia restringida
(SF Pro, SF Symbols) se marca `theme_license: personal` y la opción de
exportar/compartir queda deshabilitada, con la explicación en pantalla.
Fase 2A (actual): reempaqueta assets ya generados (por ejemplo, la
salida de `design-system/generate.py` del firmware, o
`~/Aura-local/theme-apple-source/design-system-out/`) — construir un
tema rasterizando fuentes/íconos del sistema directamente es trabajo de
seguimiento (Fase 2B). Formato exacto, compartido con el firmware, en
[`CONTRATO-formato-tema.md`](CONTRATO-formato-tema.md).

## Seguridad

Todas las operaciones que tocan el disco del usuario o piden privilegios elevados pasan por rutas nativas de macOS (nunca se le pide al usuario usar Terminal), con una pantalla propia que explica qué va a pasar *antes* del diálogo nativo de autorización, y con identificación del disco del iPod por múltiples criterios (nunca un identificador hardcodeado), re-verificada inmediatamente antes de cualquier operación destructiva — ver `CLAUDE.md` para el detalle de estas reglas y `IPodDiskIdentifier`/`PrivilegedExecutor` en el código.

## Estado del proyecto

Compila y pasa sus tests con `xcodebuild` real (no solo con el camino alternativo de `swift build`/`swift test` — ver D-034 en `DECISIONS-ARCHIVE.md`), generando `AuraStudio.app` con los artefactos del firmware embebidos y verificados por checksum. Sin verificación de arranque/flasheo de punta a punta contra un iPod físico en cada sesión de desarrollo — ver `DECISIONS.md`/`DECISIONS-ARCHIVE.md` para qué se verificó contra hardware real y cuándo.

## Compilar

Ver [`docs/guia-desarrollo.md`](docs/guia-desarrollo.md) para el detalle completo. En resumen:

```bash
brew install xcodegen gh
scripts/fetch-firmware.sh                    # baja Aura Y Metro-Aura (tags de FIRMWARE_VERSION)
# scripts/fetch-firmware.sh --family metro   # solo una familia
# scripts/fetch-firmware.sh --from-dir /ruta/a/Aura-Firmware/firmware/dist   # Aura, en desarrollo
cd studio/AuraStudio
xcodegen generate
open AuraStudio.xcodeproj
```

## Documentos clave

- [`docs/guia-instalacion.md`](docs/guia-instalacion.md) — guía para el usuario final: instalar Aura y sincronizar tu biblioteca.
- [`docs/guia-desarrollo.md`](docs/guia-desarrollo.md) — cómo compilar y probar este repositorio.
- [`CONTRATO-firmware-studio.md`](CONTRATO-firmware-studio.md) — contrato con el repositorio del firmware.
- [`CONTRATO-formato-tema.md`](CONTRATO-formato-tema.md) — formato del paquete de tema instalable, compartido con el firmware.
- [`DECISIONS.md`](DECISIONS.md) — bitácora de decisiones desde la separación de repositorios (ST-001+), con el índice de las entradas relevantes de Aura Studio en el archivo histórico.
- [`DECISIONS-ARCHIVE.md`](DECISIONS-ARCHIVE.md) — bitácora congelada del monorepo original (D-001…D-285), de solo lectura, compartida con `Aura-Firmware`.

## Licencia

Software propietario — ver [`LICENSE`](LICENSE). Los binarios del firmware embebidos en tiempo de build (`rockbox.ipod`, `rockbox.zip`, `bootloader-ipod6g.ipod`, `mks5lboot`) son GPL v2, distribuidos como agregación; ver `CONTRATO-firmware-studio.md` §B para el detalle de cumplimiento.
