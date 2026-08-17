#!/usr/bin/env bash
# Genera el fixture de foto que usa LibraryPipelineIntegrationTests
# (video y audio de prueba se generan al vuelo dentro del test mismo,
# con ffmpeg). Copia recortada del generador equivalente del
# repositorio Aura-Firmware (firmware/tools/gen_test_media.sh) -- ver
# CONTRATO-firmware-studio.md §F: cada repo genera sus propios fixtures,
# sin depender de una ruta a un checkout ajeno.
#
# Salida: test-media/ (no se versiona -- generado on-demand).
#
# Uso: tools/gen_test_media.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/test-media"

mkdir -p "$OUT_DIR/Photos"

echo "==> Generando $OUT_DIR/Photos/photo1.jpg"
# -pix_fmt yuvj420p: submuestreo de croma 4:2:0 estandar, ver D-030 en
# DECISIONS-ARCHIVE.md (mismo motivo que en el generador del firmware,
# aunque aqui no se decodifica en Rockbox, solo se ejercita el pipeline
# de ingesta/transcode de Aura Studio).
ffmpeg -y -loglevel error -f lavfi -i "testsrc=size=320x240:rate=1" \
  -pix_fmt yuvj420p -frames:v 1 "$OUT_DIR/Photos/photo1.jpg"

echo "==> Listo: $OUT_DIR"
