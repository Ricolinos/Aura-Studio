#!/usr/bin/env bash
# ST-227 addendum ("Sesión Maestra", 2026-09-07): correr el suite
# completo de `swift test` en una Mac bajo presión de memoria real (no
# competencia con otra sesión -- confirmado: ~40 GB en el compresor,
# ~90 MB libres, apps reales del dueño -- Parallels, Adobe, Microsoft,
# Brave). Cinco intentos seguidos del suite completo se murieron por
# presión de memoria, uno de ellos con el candado de compilación
# tomado en solitario (sin competencia posible). Correr en tandas
# chicas (8-10 clases cada una) reduce el pico de memoria de cada
# corrida individual -- no evita la presión de fondo, pero evita que
# UNA corrida gigante la empuje por encima del límite.
#
# REANUDABLE: si una tanda muere (la mata el propio sistema por
# memoria, no este script), correr el script DE NUEVO retoma desde la
# primera tanda sin resultado registrado -- no repite tandas ya en
# verde. Si una tanda en particular sigue muriendo, pártela a mano con
# --only (ver más abajo) usando la mitad de sus clases.
#
# USO:
#   tools/swift-test-por-lotes.sh                    # corre todas las tandas que falten
#   tools/swift-test-por-lotes.sh --batch-size 5      # tandas más chicas
#   tools/swift-test-por-lotes.sh --only "ClaseA,ClaseB"   # una tanda ad-hoc (para partir una que murió)
#   tools/swift-test-por-lotes.sh --reset             # borra los resultados guardados, vuelve a empezar
#   tools/swift-test-por-lotes.sh --verify            # solo confirma que las tandas registradas cubren el 100% de las clases, no corre nada
#
# El candado de compilación (`.mac-build-lock`, hermano de Aura-Firmware)
# se toma antes de CADA tanda y se suelta después -- nunca se lo quita
# si el dueño real es otra sesión (revisa el archivo `owner` primero).

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/studio/AuraStudio"
BUILD_LOCK="$(cd "$ROOT_DIR/../.." && pwd)/.mac-build-lock"
RESULTS_FILE="$ROOT_DIR/tools/.swift-test-batches-results.tsv"
LOG_DIR="$(mktemp -d)"

BATCH_SIZE=10
ONLY=""
RESET=0
VERIFY_ONLY=0

log() { printf '[swift-test-por-lotes] %s\n' "$*" >&2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --batch-size) BATCH_SIZE="$2"; shift 2 ;;
    --only) ONLY="$2"; shift 2 ;;
    --reset) RESET=1; shift ;;
    --verify) VERIFY_ONLY=1; shift ;;
    *) log "argumento desconocido: $1"; exit 1 ;;
  esac
done

if [[ $RESET -eq 1 ]]; then
  rm -f "$RESULTS_FILE"
  log "resultados borrados -- $RESULTS_FILE"
  [[ -z "$ONLY" && $VERIFY_ONLY -eq 0 ]] && exit 0
fi

touch "$RESULTS_FILE"

# --- Descubrir todas las clases de prueba reales -----------------------
#
# `swift test list` imprime "Target.Clase/metodo" por línea -- las
# clases únicas son lo que se agrupa en tandas.

discover_classes() {
  ( cd "$PACKAGE_DIR" && swift test list 2>/dev/null ) \
    | sed -E 's/^[A-Za-z0-9_]+\.([A-Za-z0-9_]+)\/.*/\1/' \
    | sort -u
}

all_classes_file="$LOG_DIR/all_classes.txt"
discover_classes > "$all_classes_file"
total_classes=$(wc -l < "$all_classes_file" | tr -d ' ')
if [[ "$total_classes" -eq 0 ]]; then
  log "ERROR: swift test list no devolvió ninguna clase -- ¿compila el paquete?"
  exit 1
fi
log "clases de prueba descubiertas: $total_classes"

# --- Verificar cobertura -------------------------------------------------
#
# Compara las clases que YA tienen un resultado DONE registrado contra
# la lista completa de clases reales -- si algo no coincide (una clase
# nueva que ningún lote incluyó, o un nombre que ya no existe), lo dice
# explícito en vez de reportar "100%" a ciegas.

verify_coverage() {
  local covered_file="$LOG_DIR/covered.txt"
  awk -F'\t' '$1 == "DONE" { print $3 }' "$RESULTS_FILE" | tr ',' '\n' | sort -u > "$covered_file"
  local missing extra
  missing=$(comm -23 "$all_classes_file" "$covered_file")
  extra=$(comm -13 "$all_classes_file" "$covered_file")
  local missing_count extra_count
  missing_count=$(printf '%s' "$missing" | grep -c . || true)
  extra_count=$(printf '%s' "$extra" | grep -c . || true)

  echo "--- cobertura ---"
  echo "clases reales: $total_classes"
  echo "clases cubiertas por tandas en verde: $(wc -l < "$covered_file" | tr -d ' ')"
  if [[ "$missing_count" -gt 0 ]]; then
    echo "SIN cubrir ($missing_count): $missing"
  fi
  if [[ "$extra_count" -gt 0 ]]; then
    echo "en tandas pero YA NO existen como clase real ($extra_count) -- ¿el código cambió desde que se registró esa tanda?: $extra"
  fi
  if [[ "$missing_count" -eq 0 && "$extra_count" -eq 0 ]]; then
    echo "100% cubierto, sin sobrantes."
    return 0
  fi
  return 1
}

if [[ $VERIFY_ONLY -eq 1 ]]; then
  verify_coverage
  exit $?
fi

acquire_lock() {
  local reason="$1" waited=0
  while [[ -d "$BUILD_LOCK" ]]; do
    if [[ $waited -eq 0 ]]; then
      log "candado ocupado por: $(cat "$BUILD_LOCK/owner" 2>/dev/null || echo '?') -- esperando"
    fi
    sleep 5
    waited=$((waited + 5))
  done
  mkdir "$BUILD_LOCK"
  printf 'swift-test-por-lotes.sh (%s) - %s\n' "$reason" "$(date)" > "$BUILD_LOCK/owner"
}

release_lock() {
  # Solo si el candado sigue siendo el que tomamos nosotros -- nunca se
  # quita el de otra sesión (protocolo de siempre).
  if [[ -d "$BUILD_LOCK" ]] && grep -q "swift-test-por-lotes.sh" "$BUILD_LOCK/owner" 2>/dev/null; then
    rm -rf "$BUILD_LOCK"
  fi
}

run_batch() {
  local batch_classes="$1" batch_label="$2"
  local filter
  filter="$(printf '%s' "$batch_classes" | tr ',' '|')"
  local batch_log="$LOG_DIR/batch-$batch_label.log"

  log "=== tanda $batch_label: $batch_classes ==="
  acquire_lock "tanda $batch_label"
  set +e
  ( cd "$PACKAGE_DIR" && swift test --no-parallel --filter "$filter" ) > "$batch_log" 2>&1
  local exit_code=$?
  set -e
  release_lock

  local summary
  summary=$(grep -E "^\s*Executed [0-9]+ tests?, with" "$batch_log" | tail -1 || true)
  if [[ $exit_code -eq 0 && -n "$summary" ]]; then
    log "  OK: $summary"
    printf 'DONE\t%s\t%s\t%s\n' "$batch_label" "$batch_classes" "$summary" >> "$RESULTS_FILE"
  else
    log "  FALLÓ o se interrumpió (exit $exit_code) -- log completo: $batch_log"
    log "  copiando el log a $ROOT_DIR/tools/.swift-test-batch-$batch_label-failed.log para revisar"
    cp "$batch_log" "$ROOT_DIR/tools/.swift-test-batch-$batch_label-failed.log" 2>/dev/null || true
    printf 'FAILED\t%s\t%s\t(exit %s, ver .swift-test-batch-%s-failed.log)\n' "$batch_label" "$batch_classes" "$exit_code" "$batch_label" >> "$RESULTS_FILE"
    return 1
  fi
}

# --- Una tanda ad-hoc (--only), para partir a mano una que murió -------

if [[ -n "$ONLY" ]]; then
  run_batch "$ONLY" "ad-hoc-$(date +%s)"
  exit $?
fi

# --- Armar tandas a partir de lo que falte -------------------------------

already_done_file="$LOG_DIR/already_done.txt"
awk -F'\t' '$1 == "DONE" { print $3 }' "$RESULTS_FILE" | tr ',' '\n' | sort -u > "$already_done_file" || true
pending_file="$LOG_DIR/pending.txt"
comm -23 "$all_classes_file" "$already_done_file" > "$pending_file"
pending_count=$(wc -l < "$pending_file" | tr -d ' ')
log "clases pendientes: $pending_count de $total_classes"

if [[ "$pending_count" -eq 0 ]]; then
  log "nada pendiente -- todas las clases ya están en tandas DONE"
  verify_coverage
  exit $?
fi

batch_number=0
overall_failed=0
current_batch=()

flush_batch() {
  [[ ${#current_batch[@]} -eq 0 ]] && return 0
  batch_number=$((batch_number + 1))
  local joined
  joined="$(IFS=,; echo "${current_batch[*]}")"
  if ! run_batch "$joined" "$batch_number"; then
    overall_failed=1
    log "tanda $batch_number falló -- si fue por memoria, correr de nuevo con --only y la MITAD de estas clases: $joined"
  fi
  current_batch=()
}

while IFS= read -r class; do
  [[ -z "$class" ]] && continue
  current_batch+=("$class")
  if [[ ${#current_batch[@]} -ge $BATCH_SIZE ]]; then
    flush_batch
  fi
done < "$pending_file"
flush_batch

echo
verify_coverage || overall_failed=1

if [[ $overall_failed -eq 1 ]]; then
  log "terminó con al menos una tanda fallida o cobertura incompleta -- correr de nuevo (retoma solo lo pendiente)"
  exit 1
fi
log "listo: todas las tandas en verde, 100% de cobertura."
