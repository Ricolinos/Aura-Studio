#!/usr/bin/env bash
# Empaqueta Aura Studio lista para USAR (no para depurar): genera el
# proyecto con XcodeGen, compila Release con xcodebuild (firma ad-hoc,
# "Sign to Run Locally", la misma de project.yml) y deja la app en
# /Applications/AuraStudio.app (o en --dest).
#
# Por que existe (ST-049): la app que se prueba a mano era la Debug que
# Xcode deja en DerivedData al pulsar Run. Tras un cambio que solo vive
# en el codigo (p. ej. el selector de firmware de ST-047) esa app vieja
# no lo trae, y parece que "no aparece la opcion". Este script hace la
# build real, con los artefactos de firmware embebidos y verificados.
#
# Uso:
#   scripts/build-app.sh                 # -> /Applications/AuraStudio.app
#   scripts/build-app.sh --dest ~/Applications
#   scripts/build-app.sh --no-fetch      # no vuelve a bajar los firmwares
#
# Requiere: xcodegen, xcodebuild, gh (para fetch-firmware.sh).

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJ_DIR="$ROOT_DIR/studio/AuraStudio"
DEST_DIR="/Applications"
FETCH=1
DERIVED="$(mktemp -d /tmp/aurastudio-build.XXXXXX)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dest) DEST_DIR="$2"; shift 2 ;;
    --no-fetch) FETCH=0; shift ;;
    *) echo "Uso: $0 [--dest <carpeta>] [--no-fetch]" >&2; exit 1 ;;
  esac
done

if [[ $FETCH -eq 1 ]]; then
  echo "==> Artefactos de firmware (todas las familias, FIRMWARE_VERSION)"
  "$ROOT_DIR/scripts/fetch-firmware.sh"
fi

for f in rockbox.ipod rockbox.zip mks5lboot checksums.txt metro/rockbox.ipod metro/rockbox.zip metro/mks5lboot metro/checksums.txt moonlit/rockbox.ipod moonlit/rockbox.zip moonlit/mks5lboot moonlit/checksums.txt; do
  if [[ ! -f "$PROJ_DIR/Vendor/firmware-dist/$f" ]]; then
    echo "ERROR: falta Vendor/firmware-dist/$f -- corre scripts/fetch-firmware.sh" >&2
    exit 1
  fi
done

echo "==> xcodegen generate"
(cd "$PROJ_DIR" && xcodegen generate >/dev/null)

echo "==> xcodebuild Release"
(cd "$PROJ_DIR" && xcodebuild -project AuraStudio.xcodeproj -scheme AuraStudio \
    -configuration Release -derivedDataPath "$DERIVED" build 2>&1 \
  | grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true)

APP="$DERIVED/Build/Products/Release/AuraStudio.app"
if [[ ! -d "$APP" ]]; then
  echo "ERROR: no se produjo $APP" >&2
  exit 1
fi

echo "==> Verificando el bundle"
codesign -vv "$APP" >/dev/null
for f in rockbox.ipod firmware-version.txt metro/rockbox.ipod metro/firmware-version.txt moonlit/rockbox.ipod moonlit/firmware-version.txt; do
  [[ -f "$APP/Contents/Resources/$f" ]] || { echo "ERROR: el bundle no trae Resources/$f" >&2; exit 1; }
done
[[ -x "$APP/Contents/Resources/mks5lboot" && -x "$APP/Contents/Resources/metro/mks5lboot" \
   && -x "$APP/Contents/Resources/moonlit/mks5lboot" ]] \
  || { echo "ERROR: mks5lboot sin bit de ejecucion en el bundle" >&2; exit 1; }

echo "==> Instalando en $DEST_DIR/AuraStudio.app"
pkill -x AuraStudio 2>/dev/null || true
mkdir -p "$DEST_DIR"
rm -rf "$DEST_DIR/AuraStudio.app"
ditto "$APP" "$DEST_DIR/AuraStudio.app"
rm -rf "$DERIVED"

echo "==> Listo: $DEST_DIR/AuraStudio.app"
echo "    Aura:  $(cat "$DEST_DIR/AuraStudio.app/Contents/Resources/firmware-version.txt")"
echo "    Metro: $(cat "$DEST_DIR/AuraStudio.app/Contents/Resources/metro/firmware-version.txt")"
echo "    moonlit: $(cat "$DEST_DIR/AuraStudio.app/Contents/Resources/moonlit/firmware-version.txt")"
