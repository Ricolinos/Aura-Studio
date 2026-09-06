#!/usr/bin/env bash
# ST-194: borra los `.plist` que dejaron tiradas las pruebas de
# Aura Studio en ~/Library/Preferences.
#
# POR QUÉ EXISTE
#
# Las pruebas aíslan sus preferencias creando una suite de UserDefaults
# con nombre único (`PerfBaselineTests-<UUID>`), que es lo correcto: sin
# eso le cambiarían los ajustes reales a quien corra el suite. Lo que
# faltaba era borrarlas al terminar, y cada suite deja un archivo. Con 23
# familias de pruebas, cada corrida completa dejaba cientos; en la Mac
# del dueño se habían acumulado más de diez mil.
#
# El origen ya está arreglado (ver `Tests/AuraStudioTests/TestDefaults.swift`:
# `makeIsolatedDefaults` borra la suite Y su archivo al terminar cada
# prueba, medido). Este script es solo para limpiar lo que quedó de antes.
#
# POR QUÉ NO SE EJECUTA SOLO
#
# Borra archivos de la carpeta de preferencias del usuario. Eso no lo
# decide un script que corre por su cuenta dentro de un build o de una
# corrida de pruebas: lo corre una persona, mirando primero qué va a
# pasar. Por eso el modo por omisión es SIMULACIÓN: hay que pasar
# `--borrar` explícitamente.
#
#   tools/limpiar-preferencias-de-pruebas.sh            # solo muestra
#   tools/limpiar-preferencias-de-pruebas.sh --borrar   # borra
#
# QUÉ BORRA, EXACTAMENTE
#
# Solo archivos cuyo nombre sea `<Familia>-<UUID>.plist`, con `<Familia>`
# en la lista blanca de abajo -- los nombres que usan nuestras pruebas y
# nada más. Un `com.apple.finder.plist` no puede coincidir ni por
# accidente: no está en la lista y no tiene forma de UUID.

set -euo pipefail

PREFS_DIR="$HOME/Library/Preferences"

# Prefijos que usan las pruebas de este repositorio. Si agregas una
# familia nueva en `Tests/`, agrégala también acá.
PREFIXES=(
  AlbumCoverSimilarityTests
  AppPreferencesTests
  AuraUpdateCheckerTests
  BatchEditWorkerTests
  BootloaderUpdate
  BootloaderVerified
  CoverArtAssetsTests
  F5MeasurementBefore
  FileWorkerEquivTests
  HostedAlbumsView
  LibraryCoverMemoryTests
  LibraryFolderDropTests
  LoadCatalogParallelTests
  LocalTagRereadTests
  MusicTableColumnTests
  PerfBaselineTests
  PersistCoalescedTests
  PhotoStagingTests
  ReleaseCacheTests
  RemainingCallSitesTests
  ST046
  ST047
  SetRatingTests
  SharedPrepared
  SyncScopeTests
)

# `<UUID>.plist` en mayúsculas, que es lo que produce `UUID().uuidString`.
UUID_RE='[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}\.plist'

DELETE=0
if [[ "${1:-}" == "--borrar" ]]; then
  DELETE=1
elif [[ $# -gt 0 ]]; then
  echo "Uso: $0 [--borrar]" >&2
  exit 1
fi

total=0
for prefix in "${PREFIXES[@]}"; do
  # `find -E` (regex extendida de BSD/macOS: sin ella los intervalos
  # `{8}` del UUID no se interpretan) con -maxdepth 1 y -regex, que
  # compara la RUTA COMPLETA: nada de globs sueltos ni de `rm -rf` sobre
  # una ruta armada por concatenación.
  count=$(find -E "$PREFS_DIR" -maxdepth 1 -type f \
            -regex "^${PREFS_DIR}/${prefix}-${UUID_RE}$" | wc -l | tr -d ' ')
  [[ "$count" == "0" ]] && continue
  total=$((total + count))
  if [[ $DELETE -eq 1 ]]; then
    find -E "$PREFS_DIR" -maxdepth 1 -type f \
      -regex "^${PREFS_DIR}/${prefix}-${UUID_RE}$" -delete
    printf '  borrados %6s  %s-*\n' "$count" "$prefix"
  else
    printf '  %6s  %s-*\n' "$count" "$prefix"
  fi
done

if [[ $total -eq 0 ]]; then
  echo "No hay preferencias de pruebas que limpiar."
  exit 0
fi

if [[ $DELETE -eq 1 ]]; then
  echo "Listo: $total archivos borrados de $PREFS_DIR"
else
  echo
  echo "$total archivos coinciden. Nada se borró todavía."
  echo "Para borrarlos:  $0 --borrar"
fi
