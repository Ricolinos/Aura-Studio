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

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="$ROOT_DIR/studio/AuraStudio/Vendor/firmware-dist"
VERSION_FILE="$ROOT_DIR/FIRMWARE_VERSION"

ASSETS=(rockbox.ipod rockbox.zip mks5lboot checksums.txt)
OPTIONAL_ASSETS=(bootloader-ipod6g.ipod AuraPalette.swift MODIFICATIONS.md theme-format-v1.json aura-theme-default.zip)

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
  echo "==> Copiando artefactos locales desde $src (modo desarrollo, --from-dir)"
  mkdir -p "$VENDOR_DIR"
  rm -f "$VENDOR_DIR"/*
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
  echo "==> Listo: $VENDOR_DIR (modo desarrollo -- sin bootloader-ipod6g.ipod si package_dist.sh no lo produjo)"
}

from_release() {
  if [[ ! -f "$VERSION_FILE" ]]; then
    echo "ERROR: falta $VERSION_FILE (tag del Release de Aura-Firmware a usar)" >&2
    exit 1
  fi
  local tag
  tag="$(grep '^tag=' "$VERSION_FILE" | cut -d= -f2)"
  if [[ -z "$tag" ]]; then
    echo "ERROR: $VERSION_FILE no define 'tag=' -- ver FIRMWARE_VERSION.example" >&2
    exit 1
  fi
  echo "==> Descargando Release $tag de Aura-Firmware (gh release download)"
  mkdir -p "$VENDOR_DIR"
  rm -f "$VENDOR_DIR"/*
  gh release download "$tag" --repo Ricolinos/Aura-Firmware --dir "$VENDOR_DIR" --clobber
  verify_checksums "$VENDOR_DIR"
  restore_exec_bit "$VENDOR_DIR"
  echo "==> Listo: $VENDOR_DIR ($tag)"
}

if [[ "${1:-}" == "--from-dir" ]]; then
  [[ -n "${2:-}" ]] || { echo "Uso: $0 --from-dir <ruta a firmware/dist/>" >&2; exit 1; }
  from_dir "$2"
else
  from_release
fi
