#!/usr/bin/env bash
# Puebla studio/AuraStudio/Vendor/firmware-dist/ con los artefactos que
# el firmware Aura publica -- nunca lee el arbol de fuentes de un
# checkout de Aura-Firmware. Ver CONTRATO-firmware-studio.md §A.
#
# Uso normal (con Release publicado):
#   scripts/fetch-firmware.sh
#     Descarga el tag fijado en FIRMWARE_VERSION con `gh release download`.
#
# Uso de desarrollo (sin Release publico todavia):
#   scripts/fetch-firmware.sh --from-dir /ruta/a/Aura-Firmware/firmware/dist
#     Copia desde un firmware/dist/ local (generado alla con
#     firmware/tools/package_dist.sh). Documentado como excepcion de
#     desarrollo, nunca la ruta por defecto de project.yml.
#
# En ambos casos verifica checksums.txt antes de dejar los archivos
# utilizables, y falla con mensaje claro si algo no coincide o falta.

# ST-047 / ST-065 (tres familias de firmware): el mismo script sirve a
# Aura, a Metro-Aura y a moonlit.aura. Aura se queda EXACTAMENTE donde
# estaba (Vendor/firmware-dist/, con sus extras de temas y paleta que solo
# Aura publica); Metro va en el subdirectorio Vendor/firmware-dist/metro/
# y moonlit en Vendor/firmware-dist/moonlit/, que project.yml empaqueta
# como referencias de carpeta para que sus rockbox.ipod/rockbox.zip no
# choquen con los de Aura dentro del bundle. En FIRMWARE_VERSION la
# seccion de cada familia lleva su prefijo (`metro.tag=...`,
# `moonlit.tag=...`). La lista de familias vive en FAMILIES (abajo) y en
# `FirmwareFamily.installable` del lado Swift: se mantienen a la par.
#
#   scripts/fetch-firmware.sh                 # todas las familias
#   scripts/fetch-firmware.sh --family aura   # solo una
#   scripts/fetch-firmware.sh --family metro
#   scripts/fetch-firmware.sh --family moonlit
#   scripts/fetch-firmware.sh --from-dir <dist>            # Aura, desarrollo
#   scripts/fetch-firmware.sh --family metro --from-dir <dist>
#   scripts/fetch-firmware.sh --family moonlit --from-dir <dist>

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_ROOT="$ROOT_DIR/studio/AuraStudio/Vendor/firmware-dist"
VERSION_FILE="$ROOT_DIR/FIRMWARE_VERSION"

ASSETS=(rockbox.ipod rockbox.zip mks5lboot checksums.txt)
OPTIONAL_ASSETS=(bootloader-ipod6g.ipod AuraPalette.swift MODIFICATIONS.md theme-format-v1.json aura-theme-default.zip THIRD-PARTY-NOTICES.txt)

# Por familia: repositorio, prefijo de clave en FIRMWARE_VERSION y
# destino. Se fijan con set_family antes de cualquier operacion.
FAMILY=""
REPO=""
KEY_PREFIX=""
VENDOR_DIR=""

set_family() {
  FAMILY="$1"
  case "$FAMILY" in
    aura)
      REPO="Ricolinos/Aura-Firmware"; KEY_PREFIX=""; VENDOR_DIR="$VENDOR_ROOT" ;;
    metro)
      REPO="Ricolinos/Metro-Aura"; KEY_PREFIX="metro."; VENDOR_DIR="$VENDOR_ROOT/metro" ;;
    moonlit)
      REPO="Ricolinos/moonlit-aura"; KEY_PREFIX="moonlit."; VENDOR_DIR="$VENDOR_ROOT/moonlit" ;;
    *)
      echo "ERROR: familia desconocida '$FAMILY' (aura|metro|moonlit)" >&2; exit 1 ;;
  esac
}

# Deja junto a los artefactos el tag que se descargo, para que la
# pantalla de Licencias de la app (CONTRATO §B) pueda mostrarlo sin
# leer FIRMWARE_VERSION, que no viaja en el bundle.
write_version_marker() {
  local dir="$1" tag="$2"
  printf '%s\n' "$tag" > "$dir/firmware-version.txt"
}

verify_checksums() {
  local dir="$1"
  echo "==> Verificando checksums en $dir"
  (
    cd "$dir"
    if [[ ! -f checksums.txt ]]; then
      echo "ERROR: falta checksums.txt en $dir" >&2
      exit 1
    fi
    # shasum -c ignora entradas de checksums.txt cuyo archivo no esta
    # presente localmente (p. ej. bootloader-ipod6g.ipod si el release
    # o el dist local no lo tiene todavia -- ver nota en README del
    # firmware sobre su compilacion manual); pero SI falla si un
    # archivo presente no coincide con su hash esperado.
    present=()
    while IFS= read -r line; do
      f="$(echo "$line" | awk '{print $2}')"
      [[ -f "$f" ]] && present+=("$line")
    done < checksums.txt
    if [[ ${#present[@]} -eq 0 ]]; then
      echo "ERROR: checksums.txt no describe ningun archivo presente en $dir" >&2
      exit 1
    fi
    printf '%s\n' "${present[@]}" | shasum -a 256 -c -
  )
}

# Los assets de un Release de GitHub (y `cp` desde un dist con permisos
# raros) llegan sin bit de ejecucion. Xcode copia el recurso al bundle
# tal cual, y un mks5lboot sin +x hace que `Process.run()` falle con
# "permission denied": el sondeo DFU nunca ve el iPod y el instalador
# se queda en "Esperando modo DFU..." (ST-018). Restaurarlo aqui es
# la primera linea; project.yml lo vuelve a asegurar dentro del bundle.
restore_exec_bit() {
  local dir="$1"
  if [[ -f "$dir/mks5lboot" ]]; then
    chmod 755 "$dir/mks5lboot"
    echo "==> mks5lboot: bit de ejecucion restaurado"
  fi
}

from_dir() {
  local src="$1"
  if [[ ! -d "$src" ]]; then
    echo "ERROR: $src no existe" >&2
    exit 1
  fi
  echo "==> [$FAMILY] Copiando artefactos locales desde $src (modo desarrollo, --from-dir)"
  mkdir -p "$VENDOR_DIR"
  # Solo archivos: `rm -f dir/*` no toca el subdirectorio metro/ cuando
  # se limpia la raiz de Aura, ni al reves.
  find "$VENDOR_DIR" -maxdepth 1 -type f -delete
  for f in "${ASSETS[@]}" "${OPTIONAL_ASSETS[@]}"; do
    [[ -f "$src/$f" ]] && cp "$src/$f" "$VENDOR_DIR/$f"
  done
  for f in "${ASSETS[@]}"; do
    if [[ ! -f "$VENDOR_DIR/$f" ]]; then
      echo "ERROR: falta $f en $src -- corre firmware/tools/package_dist.sh alla primero" >&2
      exit 1
    fi
  done
  verify_checksums "$VENDOR_DIR"
  restore_exec_bit "$VENDOR_DIR"
  write_version_marker "$VENDOR_DIR" "local-dev"
  echo "==> Listo: $VENDOR_DIR (modo desarrollo -- sin bootloader-ipod6g.ipod si package_dist.sh no lo produjo)"
}

from_release() {
  if [[ ! -f "$VERSION_FILE" ]]; then
    echo "ERROR: falta $VERSION_FILE (tags de los Releases a usar)" >&2
    exit 1
  fi
  local tag
  tag="$(grep "^${KEY_PREFIX}tag=" "$VERSION_FILE" | cut -d= -f2)"
  if [[ -z "$tag" ]]; then
    echo "ERROR: $VERSION_FILE no define '${KEY_PREFIX}tag=' -- ver FIRMWARE_VERSION.example" >&2
    exit 1
  fi
  echo "==> [$FAMILY] Descargando Release $tag de $REPO (gh release download)"
  mkdir -p "$VENDOR_DIR"
  find "$VENDOR_DIR" -maxdepth 1 -type f -delete
  gh release download "$tag" --repo "$REPO" --dir "$VENDOR_DIR" --clobber
  verify_checksums "$VENDOR_DIR"
  restore_exec_bit "$VENDOR_DIR"
  write_version_marker "$VENDOR_DIR" "$tag"
  echo "==> Listo: $VENDOR_DIR ($tag)"
}

FAMILIES=(aura metro moonlit)
FROM_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --family)
      [[ -n "${2:-}" ]] || { echo "Uso: $0 [--family aura|metro|moonlit] [--from-dir <dist>]" >&2; exit 1; }
      FAMILIES=("$2"); shift 2 ;;
    --from-dir)
      [[ -n "${2:-}" ]] || { echo "Uso: $0 [--family aura|metro|moonlit] --from-dir <ruta a firmware/dist/>" >&2; exit 1; }
      FROM_DIR="$2"; shift 2 ;;
    *)
      echo "Uso: $0 [--family aura|metro|moonlit] [--from-dir <dist>]" >&2; exit 1 ;;
  esac
done

if [[ -n "$FROM_DIR" && ${#FAMILIES[@]} -ne 1 ]]; then
  # --from-dir es un dist concreto de UNA familia; sin --family se asume
  # Aura, que es lo que el script siempre hizo.
  FAMILIES=(aura)
fi

for fam in "${FAMILIES[@]}"; do
  set_family "$fam"
  if [[ -n "$FROM_DIR" ]]; then
    from_dir "$FROM_DIR"
  else
    from_release
  fi
done
