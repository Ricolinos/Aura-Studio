# Guía de desarrollo — Aura Studio

Cómo compilar y trabajar en este repositorio. Todos los comandos asumen que estás parado en la raíz de este repo, en un Mac con Apple Silicon.

## Requisitos (una sola vez)

```bash
brew install xcodegen gh
```

Xcode (con todos sus componentes de plataforma instalados — ábrelo una vez desde Finder si es la primera vez que lo usas en esta máquina, así macOS termina de instalar lo que falte).

## Traer los artefactos del firmware

Este repositorio no compila el firmware ni lee su árbol de fuentes — consume binarios publicados por `Aura-Firmware` (ver [`CONTRATO-firmware-studio.md`](../CONTRATO-firmware-studio.md)):

```bash
scripts/fetch-firmware.sh
```

Descarga el Release fijado en `FIRMWARE_VERSION` y verifica sus checksums. Para probar contra un checkout local sin publicar un Release nuevo (desarrollo del propio firmware, sin tocar el pin), usa el modo `--from-dir` apuntando a un checkout local de `Aura-Firmware` donde ya hayas corrido `firmware/tools/package_dist.sh`:

```bash
scripts/fetch-firmware.sh --from-dir /ruta/a/Aura-Firmware/firmware/dist
```

Puebla `studio/AuraStudio/Vendor/firmware-dist/` (gitignorado).

## Compilar y probar

**Camino rápido** (Swift Package Manager — compila el mismo código fuente, sin generar el `.app` con recursos embebidos, y **no** requiere `Vendor/firmware-dist/` poblado, ver D-034 en `DECISIONS-ARCHIVE.md`):

```bash
cd studio/AuraStudio
swift build
swift test          # incluye 4 tests que pegan contra APIs reales (MusicBrainz/CAA/LRCLIB) y se saltean solos sin red
```

**Proyecto real** (`AuraStudio.xcodeproj`, generado desde `project.yml` con [XcodeGen](https://github.com/yonaskolb/XcodeGen) — nunca se edita el `.xcodeproj` a mano; requiere `Vendor/firmware-dist/` poblado primero):

```bash
cd studio/AuraStudio
xcodegen generate
open AuraStudio.xcodeproj
```

Build/test por línea de comandos con Xcode:

```bash
xcodebuild -project AuraStudio.xcodeproj -scheme AuraStudio build
xcodebuild -project AuraStudio.xcodeproj -scheme AuraStudio test
```

**Empaquetar para usar** (ST-049): la app que Xcode deja en DerivedData al pulsar Run es Debug y solo se actualiza cuando vuelves a pulsar Run; un cambio que solo vive en el código no aparece en una app vieja. Para una build Release instalable en `/Applications`, con los dos firmwares embebidos y verificados:

```bash
scripts/build-app.sh              # fetch-firmware + xcodegen + xcodebuild Release + /Applications/AuraStudio.app
scripts/build-app.sh --no-fetch   # sin volver a bajar los firmwares
```

## Fixtures de prueba

`tools/gen_test_media.sh` genera el fixture de foto que usa `LibraryPipelineIntegrationTests` (el video y el audio de prueba se generan al vuelo dentro del test, con ffmpeg — requiere `ffmpeg` instalado):

```bash
tools/gen_test_media.sh
```

Produce `test-media/` (gitignorado, no compartido con el repositorio del firmware — ver `CONTRATO-firmware-studio.md` §F).

## Estructura del repo

```
studio/AuraStudio/            → la app (Swift/SwiftUI); Vendor/firmware-dist/ (gitignorado) recibe los artefactos del firmware
scripts/fetch-firmware.sh     → trae los artefactos del firmware desde un Release (o --from-dir en desarrollo)
tools/gen_test_media.sh       → fixtures de prueba propios de este repo
docs/                         → esta guía + guía de instalación
```

Ver [`DECISIONS.md`](../DECISIONS.md) y [`DECISIONS-ARCHIVE.md`](../DECISIONS-ARCHIVE.md) para el porqué de cada decisión no obvia.
