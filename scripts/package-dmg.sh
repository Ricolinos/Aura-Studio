#!/usr/bin/env bash
# Arma un DMG de Aura Studio listo para llevar a OTRA Mac.
#
# Que hace: compila Release con scripts/build-app.sh (que ya verifica
# los artefactos de firmware embebidos y el bit de ejecucion de
# mks5lboot), y empaqueta la app en un .dmg comprimido junto con un
# alias a /Applications y un LEEME.
#
# LO QUE ESTE SCRIPT **NO** PUEDE HACER, y hay que saberlo antes de
# mandarle el archivo a alguien:
#
#   La app se firma AD-HOC (CODE_SIGN_IDENTITY "-", ver project.yml),
#   porque en esta Mac no hay ningun certificado Developer ID
#   (`security find-identity -v -p codesigning` -> 0 identidades). Sin
#   certificado no se puede notarizar, y sin notarizar **Gatekeeper
#   bloquea la app la primera vez** en cualquier otra Mac. El LEEME que
#   viaja adentro explica el paso para abrirla igual.
#
#   Notarizar de verdad exige una cuenta paga del Apple Developer
#   Program (certificado Developer ID Application + `xcrun notarytool`).
#   Con eso, este script se extiende con los pasos de firma/notarizado y
#   el usuario final no ve ninguna advertencia.
#
# Uso:
#   scripts/package-dmg.sh                  # -> dist/AuraStudio-<version>-<fecha>.dmg
#   scripts/package-dmg.sh --out ~/Desktop
#   scripts/package-dmg.sh --fetch          # vuelve a bajar los firmwares primero
#
# Requiere: xcodegen, xcodebuild, hdiutil.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/dist"
FETCH_FLAG="--no-fetch"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) OUT_DIR="$2"; shift 2 ;;
    --fetch) FETCH_FLAG=""; shift ;;
    *) echo "Uso: $0 [--out <carpeta>] [--fetch]" >&2; exit 1 ;;
  esac
done

STAGE="$(mktemp -d /tmp/aurastudio-dmg.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT

echo "==> Compilando Release"
# build-app.sh instala la app en --dest; se le da una carpeta temporal
# para NO tocar la /Applications de esta Mac al armar el paquete.
"$ROOT_DIR/scripts/build-app.sh" --dest "$STAGE/app" ${FETCH_FLAG:+$FETCH_FLAG}

APP="$STAGE/app/AuraStudio.app"
[[ -d "$APP" ]] || { echo "ERROR: no se produjo $APP" >&2; exit 1; }

VERSION="$(defaults read "$APP/Contents/Info" CFBundleShortVersionString)"
AURA_TAG="$(cat "$APP/Contents/Resources/firmware-version.txt" 2>/dev/null || echo "?")"
ARCHS="$(lipo -archs "$APP/Contents/MacOS/AuraStudio")"
MIN_OS="$(defaults read "$APP/Contents/Info" LSMinimumSystemVersion 2>/dev/null || echo "14.4")"

echo "==> Armando el contenido del DMG"
ROOTFS="$STAGE/dmg"
mkdir -p "$ROOTFS"
ditto "$APP" "$ROOTFS/AuraStudio.app"
ln -s /Applications "$ROOTFS/Applications"

cat > "$ROOTFS/LÉEME antes de abrir.txt" <<LEEME
Aura Studio $VERSION
====================

1. Arrastra "AuraStudio.app" a la carpeta "Applications" de esta misma
   ventana.

2. La PRIMERA vez, macOS te va a decir que no puede comprobar si la app
   contiene software malicioso, y no te va a dejar abrirla. Eso NO es un
   error de la app: es que Aura Studio no está firmada con un
   certificado de desarrollador de Apple (cuesta 99 USD al año y este
   proyecto no lo tiene).

   Para destrabarla, una sola vez. El ORDEN importa: el permiso solo
   aparece en Ajustes DESPUÉS de que intentaste abrirla y falló.

     a) Abre Aura Studio desde Aplicaciones con doble clic. Va a salir
        el aviso y no va a abrir: eso es lo esperado, sigue al paso b.
     b) Abre "Ajustes del Sistema" › "Privacidad y seguridad".
     c) Baja hasta el aviso que menciona a AuraStudio y pulsa
        "Abrir de todos modos". Confirma con tu contraseña o Touch ID.
     d) Vuelve a abrir la app y pulsa "Abrir" en el último aviso.

   (En macOS 15 y posteriores ya NO sirve el truco viejo de abrirla con
   clic derecho › Abrir. Hay que pasar por Ajustes.)

   Alternativa en un solo paso, si prefieres la Terminal: pega esta
   línea, dale Enter y después abre la app normal.

     xattr -dr com.apple.quarantine /Applications/AuraStudio.app

3. Requisitos: macOS $MIN_OS o superior. Funciona en Mac con Apple
   Silicon y con Intel ($ARCHS).

Qué trae embebido
-----------------
Los firmwares para iPod Classic 6G ($AURA_TAG y las otras familias) son
software libre bajo GPL v2, derivados de Rockbox, incluidos sin
modificar. La pantalla "Extras › Licencias" dentro de la app tiene los
enlaces al código fuente exacto de cada uno, como pide la sección 3 de
esa licencia.

Aura Studio necesita acceso a volúmenes removibles para detectar tu iPod
y sincronizar tu biblioteca; te lo va a pedir la primera vez.
LEEME

VOLNAME="Aura Studio $VERSION"
mkdir -p "$OUT_DIR"
DMG="$OUT_DIR/AuraStudio-$VERSION-$(date +%Y%m%d).dmg"
rm -f "$DMG"

echo "==> Creando $DMG"
hdiutil create -quiet -volname "$VOLNAME" -srcfolder "$ROOTFS" \
  -fs HFS+ -format UDZO -imagekey zlib-level=9 "$DMG"

echo
echo "==> Listo"
echo "    Archivo:      $DMG"
echo "    Tamaño:       $(du -h "$DMG" | cut -f1)"
echo "    Versión:      $VERSION"
echo "    Arquitectura: $ARCHS  (universal)"
echo "    macOS mínimo: $MIN_OS"
echo "    Firmware:     $AURA_TAG"
echo "    SHA-256:      $(shasum -a 256 "$DMG" | cut -d' ' -f1)"
echo
echo "    Sin notarizar: en la otra Mac hay que destrabarla una vez."
echo "    El LEEME que viaja dentro del DMG explica cómo."
