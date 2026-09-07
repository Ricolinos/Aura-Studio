#!/usr/bin/env bash
# PLAN-studio-ajustes-3.md §3, Fase A7c (ST-227 addendum, "Sesión
# Maestra"): arnés de capturas por idioma. Objetivo final (cuando A7c
# cierre): docs/capturas/idiomas/<idioma>/<pantalla>.png para
# es/en/ja/de/ru/fr de las pantallas principales.
#
# CÓMO FUNCIONA: lanza el binario de AuraStudio.app (build DEBUG --
# UITestEnvironment es #if DEBUG, ver Sources/AuraStudio/Models/
# UITestEnvironment.swift, así que una build Release ignoraría todo
# esto) directo, sin `open` (mismo motivo que el diagnóstico de ST-187:
# lanzar vía LaunchServices puede colgarse con variables de entorno
# puestas), con `-AppleLanguages`/`-AppleLocale` más las variables
# AURA_UITEST_* apuntando a una biblioteca de prueba sintética generada
# acá mismo (nunca la real). Navega con System Events (AppleScript) por
# `accessibilityIdentifier` -- nunca por texto localizado, salvo donde
# se dice explícitamente que es así. Captura por VENTANA
# (`screencapture -l <windowID>`, no pantalla completa) para no
# necesitar XCUITest ni estorbar a quien esté usando la Mac.
#
# QUÉ FUNCIONA HOY (2026-09-07): solo "es" produce contenido real --
# CFBundleLocalizations declara únicamente español (ver
# docs/auditoria-idiomas.md), así que -AppleLanguages con cualquier
# otro código hoy cae al mismo español fijo. El resto de los idiomas
# queda PARAMETRIZADO (se puede invocar, corre el mismo mecanismo) para
# cuando A7b/A7c agreguen contenido real -- no producen capturas
# distintas todavía, y este script no finge que sí.
#
# QUÉ PANTALLAS CAPTURA HOY, y cuáles no:
#   - albumes, canciones, ajustes, dispositivos: sí, por
#     accessibilityIdentifier de la barra lateral (estables, ver
#     UITestEnvironment.ID.sidebarRow -- Sources/AuraStudio/Models/
#     UITestEnvironment.swift). VERIFICADAS en vivo contra la app real
#     (2026-09-07) -- ver docs/capturas/idiomas/README.md.
#   - ajustes-almacenamiento: por `ajustes.pestana.almacenamiento`
#     (ST-225/A5, ya en Sources/) -- el mecanismo de clic es
#     GENÉRICO (`press_element_by_identifier`, AXPress directo), NO el
#     mismo `select` de fila que usan albumes/canciones/ajustes/
#     dispositivos (un Picker segmentado es un control distinto a una
#     fila de `AXOutline`) -- sin confirmar en vivo todavía, ver el
#     comentario de la función.
#   - acerca-de: sí, pero por POSICIÓN de menú (primer ítem del menú de
#     la app, "Acerca de <app>" -- convención estándar de macOS, nunca
#     cambia de posición aunque cambie el idioma), no por identificador
#     ni por texto.
#   - barra-estado-mensaje-largo: NO -- necesita disparar una operación
#     real (importar/sincronizar en curso) para que la barra de estado
#     muestre un mensaje largo, y eso es frágil de reproducir sin mirar
#     la pantalla. Queda con un TODO explícito en el código, no se
#     intenta hoy.
#
# USO:
#   tools/capturas-idiomas.sh [--app RUTA_A_AuraStudio.app] [idiomas...]
#
#   Sin argumentos: corre solo "es". Con argumentos ("es en ja de ru
#   fr"): corre cada uno con el mismo mecanismo (ver la nota de arriba
#   sobre qué produce contenido real hoy).
#
# REQUISITOS: build DEBUG ya generada (o se compila acá si no se pasa
# --app, con xcodebuild -configuration Debug -- toma el candado
# compartido mientras compila); permiso de Accesibilidad/Automatización
# ya concedido para quien corre este script (Terminal/el ejecutor de
# Claude Code) sobre "Eventos del sistema" -- si falta, macOS lo pide
# la primera vez.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/docs/capturas/idiomas"
BUILD_LOCK="$(cd "$ROOT_DIR/../.." && pwd)/.mac-build-lock"
SCRATCH_DIR="$(mktemp -d)"
LIBRARY_DIR="$SCRATCH_DIR/biblioteca-prueba"
BUNDLE_ID="com.ricolinos.AuraStudio"
APP_PATH=""
LANGUAGES=()

# Código de idioma -> -AppleLanguages / -AppleLocale. -AppleLanguages
# quiere una lista entre paréntesis, con el código ISO; -AppleLocale
# quiere el identificador de configuración regional completo (D-...:
# español de México en toda la app, ver CLAUDE.md).
#
# Función, no un array asociativo: el único bash de esta Mac es el de
# sistema (3.2, sin Homebrew) -- `declare -A` no existe ahí.
locale_for() {
  case "$1" in
    es) echo "es_MX" ;;
    en) echo "en_US" ;;
    ja) echo "ja_JP" ;;
    de) echo "de_DE" ;;
    ru) echo "ru_RU" ;;
    fr) echo "fr_FR" ;;
    *) echo "" ;;
  esac
}

log() { printf '[capturas-idiomas] %s\n' "$*" >&2; }

cleanup() {
  rm -rf "$SCRATCH_DIR"
}
trap cleanup EXIT

# --- Argumentos -------------------------------------------------------

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      APP_PATH="$2"; shift 2 ;;
    *)
      LANGUAGES+=("$1"); shift ;;
  esac
done
if [[ ${#LANGUAGES[@]} -eq 0 ]]; then
  LANGUAGES=(es)
fi

# --- Localizar o compilar la build DEBUG -------------------------------

find_app() {
  # -maxdepth 5: DerivedData/AuraStudio-<hash>/Build/Products/Debug/
  # AuraStudio.app son cinco niveles. Puede haber más de un
  # DerivedData-<hash> (build de otro worktree, otra corrida) -- se
  # toma el modificado más recientemente, no "el primero que encuentre"
  # (no determinista con `find` a secas).
  find "$HOME/Library/Developer/Xcode/DerivedData" -maxdepth 5 \
    -path "*/Build/Products/Debug/AuraStudio.app" -print0 2>/dev/null \
    | xargs -0 -I{} stat -f '%m %N' "{}" 2>/dev/null \
    | sort -rn | head -1 | cut -d' ' -f2-
}

acquire_lock() {
  local reason="$1"
  local waited=0
  while [[ -d "$BUILD_LOCK" ]]; do
    if [[ $waited -eq 0 ]]; then
      log "candado de compilación ocupado por: $(cat "$BUILD_LOCK/owner" 2>/dev/null || echo '?') -- esperando"
    fi
    sleep 5
    waited=$((waited + 5))
  done
  mkdir "$BUILD_LOCK"
  printf 'capturas-idiomas.sh (%s) - %s\n' "$reason" "$(date)" > "$BUILD_LOCK/owner"
}

release_lock() {
  rm -rf "$BUILD_LOCK"
}

if [[ -z "$APP_PATH" ]]; then
  APP_PATH="$(find_app)"
fi
if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
  log "no se encontró una build DEBUG existente -- compilando (candado compartido)"
  acquire_lock "compilar Debug para capturas"
  ( cd "$ROOT_DIR/studio/AuraStudio" && xcodebuild -scheme AuraStudio -configuration Debug build )
  release_lock
  APP_PATH="$(find_app)"
fi
if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
  log "ERROR: no se pudo localizar AuraStudio.app (Debug) ni compilarlo"
  exit 1
fi
BINARY="$APP_PATH/Contents/MacOS/AuraStudio"
log "usando build: $APP_PATH"

# --- Biblioteca de prueba (nunca la real) ------------------------------
#
# Dos álbumes, unos pocos temas cada uno -- alcanza para que Álbumes/
# Canciones no se vean vacíos. `storage: "copy"` y `preparedRelativePath`
# == `sourceRelativePath` (ST-223/A3: en copia el archivo de la
# biblioteca ES el preparado). Los bytes de audio son un cabezal MP3
# mínimo + relleno -- no hace falta que decodifiquen, la pantalla no
# reproduce nada, solo necesita que el archivo EXISTA (si no,
# `isAvailable` lo marca no disponible y la cuadrícula se ve distinta).

write_fixture_library() {
  local lib="$1"
  local music_dir="$lib/Música"
  mkdir -p "$music_dir/Soda Stéreo/Signos" "$music_dir/Soda Stéreo/Canción Animal" \
           "$music_dir/Café Tacvba/Re"

  write_mp3() {
    # Cabezal de frame MPEG-1 Layer III válido (0xFF 0xFB 0x90 0x00,
    # mismo patrón que MediaFixture.mp3Data en las pruebas) + relleno --
    # basta para que el archivo exista con una extensión reconocible.
    printf '\xFF\xFB\x90\x00' > "$1"
    head -c 4096 /dev/zero >> "$1"
  }

  write_mp3 "$music_dir/Soda Stéreo/Signos/01 Prófugos.mp3"
  write_mp3 "$music_dir/Soda Stéreo/Signos/02 En la ciudad de la furia.mp3"
  write_mp3 "$music_dir/Soda Stéreo/Canción Animal/01 De música ligera.mp3"
  write_mp3 "$music_dir/Café Tacvba/Re/01 El Aparato.mp3"
  write_mp3 "$music_dir/Café Tacvba/Re/02 Chilanga Banda.mp3"

  local now_ref_date
  now_ref_date=$(python3 -c "import datetime; print((datetime.datetime.now(datetime.timezone.utc) - datetime.datetime(2001,1,1,tzinfo=datetime.timezone.utc)).total_seconds())")

  make_item() {
    # id, ruta relativa, título, artista, álbum, pista
    python3 -c "
import json, sys
print(json.dumps({
    'id': sys.argv[1], 'sourceRelativePath': sys.argv[2], 'kind': 'music',
    'status': 'ready', 'preparedRelativePath': sys.argv[2], 'storage': 'copy',
    'metadataEditedByUser': False, 'addedAt': float(sys.argv[7]),
    'metadata': {
        'title': sys.argv[3], 'artist': sys.argv[4], 'album': sys.argv[5],
        'albumArtist': sys.argv[4], 'trackNumber': int(sys.argv[6]),
    },
}))
" "$@"
  }

  {
    echo '{"items": ['
    make_item "$(python3 -c 'import uuid; print(uuid.uuid4())')" "Música/Soda Stéreo/Signos/01 Prófugos.mp3" "Prófugos" "Soda Stéreo" "Signos" 1 "$now_ref_date"
    echo ','
    make_item "$(python3 -c 'import uuid; print(uuid.uuid4())')" "Música/Soda Stéreo/Signos/02 En la ciudad de la furia.mp3" "En la ciudad de la furia" "Soda Stéreo" "Signos" 2 "$now_ref_date"
    echo ','
    make_item "$(python3 -c 'import uuid; print(uuid.uuid4())')" "Música/Soda Stéreo/Canción Animal/01 De música ligera.mp3" "De música ligera" "Soda Stéreo" "Canción Animal" 1 "$now_ref_date"
    echo ','
    make_item "$(python3 -c 'import uuid; print(uuid.uuid4())')" "Música/Café Tacvba/Re/01 El Aparato.mp3" "El Aparato" "Café Tacvba" "Re" 1 "$now_ref_date"
    echo ','
    make_item "$(python3 -c 'import uuid; print(uuid.uuid4())')" "Música/Café Tacvba/Re/02 Chilanga Banda.mp3" "Chilanga Banda" "Café Tacvba" "Re" 2 "$now_ref_date"
    echo '], "playlists": []}'
  } > "$lib/biblioteca.json"
}

# --- Lanzar, navegar, capturar, salir ----------------------------------
#
# Tres cosas que NO funcionaron como el manual de AppleScript sugiere,
# comprobado a mano contra la app real antes de escribir esto:
#
# 1. `id of window` y `AXWindowNumber` -- ninguno de los dos existe en
#    la lista real de atributos que expone System Events para la
#    ventana de esta app en esta versión de macOS (comprobado con
#    `name of every attribute of window 1`: ni "id" ni "AXWindowNumber"
#    aparecen). El CGWindowID que pide `screencapture -l` sale de
#    `tools/capturas-idiomas-window-id.swift` (Quartz), no de System
#    Events.
# 2. `entire contents of window 1` -- devuelve CERO elementos para esta
#    ventana (SwiftUI dentro de un AXHostingView), aunque `UI elements
#    of window 1` sí anda. Hace falta bajar nivel por nivel a mano.
# 3. Los identificadores de la barra lateral
#    (`UITestEnvironment.ID.sidebarRow`) viven en un `AXStaticText`/
#    `AXHeading` DOS niveles adentro de su `AXRow` (Row > Cell >
#    StaticText) -- ni `AXPress` en el elemento identificado ni buscarlo
#    con `entire contents` selecciona la fila. Lo que sí selecciona la
#    fila es el mensaje `select` de AppleScript sobre el `AXRow` que lo
#    contiene (equivalente a clickear la fila de una `List`/
#    `NSOutlineView`), así que la búsqueda baja el árbol buscando CUÁL
#    `AXRow` contiene el identificador pedido entre sus descendientes, y
#    selecciona ESE `AXRow`, no el elemento identificado en sí.

wait_for_window() {
  # Comprobado que `count of windows of process X` de System Events
  # puede devolver 0 para una app real, con ventana real y visible,
  # cuando esa app no es la frontmost (perdió el foco -- p. ej. porque
  # alguien más está usando la Mac al mismo tiempo). El helper de
  # Quartz no tiene ese problema: consulta la lista de ventanas en
  # pantalla directo, sin pasar por accesibilidad ni por foco.
  local pid="$1" tries=0
  while [[ $tries -lt 40 ]]; do
    if swift "$ROOT_DIR/tools/capturas-idiomas-window-id.swift" "$pid" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.5
    tries=$((tries + 1))
  done
  return 1
}

window_id() {
  swift "$ROOT_DIR/tools/capturas-idiomas-window-id.swift" "$1"
}

select_sidebar_row() {
  local process_name="$1" identifier="$2"
  osascript <<EOF
on containsIdentifier(elem, targetID)
  tell application "System Events"
    try
      if (value of attribute "AXIdentifier" of elem) as string is targetID then return true
    end try
    try
      set kids to UI elements of elem
      repeat with k in kids
        if my containsIdentifier(k, targetID) then return true
      end repeat
    end try
    return false
  end tell
end containsIdentifier

on findAndSelectRow(elem, targetID)
  tell application "System Events"
    try
      set kids to UI elements of elem
      repeat with k in kids
        if (role of k as string) is "AXRow" then
          if my containsIdentifier(k, targetID) then
            select k
            return true
          end if
        else
          if my findAndSelectRow(k, targetID) then return true
        end if
      end repeat
    end try
    return false
  end tell
end findAndSelectRow

tell application "System Events"
  tell process "$process_name"
    set ok to my findAndSelectRow(window 1, "$identifier")
    if ok is false then error "no se encontró/seleccionó la fila '$identifier'"
  end tell
end tell
EOF
}

press_element_by_identifier() {
  # Genérico -- a diferencia de `select_sidebar_row` (filas de un
  # `AXOutline`, que se activan con `select` sobre el `AXRow`, nunca
  # con `AXPress`), esto es para lo demás: un `Picker` segmentado
  # (`ajustes.pestana.*`, ST-225/A5) u otro control donde el elemento
  # CON el identificador es el que hay que presionar directo, sin
  # subir a ningún contenedor. NO verificado en vivo todavía contra la
  # pestaña de Ajustes -- si falla, puede que un `Picker` segmentado
  # necesite `select` en vez de `AXPress` sobre el segmento, como pasó
  # con las filas de la barra lateral; confirmar la próxima vez que la
  # Mac esté libre y ajustar acá, no adivinar dos veces.
  local process_name="$1" identifier="$2"
  osascript <<EOF
on findElement(elem, targetID)
  tell application "System Events"
    try
      if (value of attribute "AXIdentifier" of elem) as string is targetID then return elem
    end try
    try
      set kids to UI elements of elem
      repeat with k in kids
        set found to my findElement(k, targetID)
        if found is not missing value then return found
      end repeat
    end try
    return missing value
  end tell
end findElement

tell application "System Events"
  tell process "$process_name"
    set found to my findElement(window 1, "$identifier")
    if found is missing value then error "no se encontró un elemento con AXIdentifier '$identifier'"
    perform action "AXPress" of found
  end tell
end tell
EOF
}

click_about_menu_item() {
  # "Acerca de <app>" es SIEMPRE el primer ítem del SEGUNDO menú de la
  # barra -- el primero ("menu bar item 1") es el menú  (sistema,
  # compartido por todas las apps), nunca el de esta app. Comprobado a
  # mano: con "menu bar item 1" esto abre "Acerca de esta Mac", no
  # "Acerca de Aura Studio".
  local process_name="$1"
  osascript -e "tell application \"System Events\" to tell process \"$process_name\" to click menu item 1 of menu 1 of menu bar item 2 of menu bar 1"
}

capture_window() {
  local process_name="$1" pid="$2" out_file="$3"
  local wid
  wid="$(window_id "$pid")"
  if [[ -z "$wid" ]]; then
    log "  ERROR: no se pudo obtener el CGWindowID de $process_name (pid $pid)"
    return 1
  fi
  screencapture -l "$wid" -o -x "$out_file"
  log "  -> $out_file ($(stat -f%z "$out_file" 2>/dev/null || echo '?') bytes)"
}

quit_app() {
  local process_name="$1"
  osascript -e "tell application \"System Events\" to if exists process \"$process_name\" then tell process \"$process_name\" to quit" 2>/dev/null || true
  sleep 1
  pkill -x "$process_name" 2>/dev/null || true
}

capture_language() {
  local lang="$1"
  local locale
  locale="$(locale_for "$lang")"
  if [[ -z "$locale" ]]; then
    log "idioma desconocido: $lang (usar es/en/ja/de/ru/fr) -- saltado"
    return
  fi

  local lang_out="$OUT_DIR/$lang"
  mkdir -p "$lang_out"

  local run_dir="$SCRATCH_DIR/$lang"
  mkdir -p "$run_dir"
  local library="$run_dir/biblioteca-prueba"
  mkdir -p "$library"
  write_fixture_library "$library"

  local suite="CapturasIdiomas-$lang-$$"

  log "=== $lang ($locale) ==="
  AURA_UITEST_LIBRARY="$library" \
    AURA_UITEST_DEFAULTS_SUITE="$suite" \
    AURA_UITEST_MAIN_SCREEN=1 \
    "$BINARY" -AppleLanguages "($lang)" -AppleLocale "$locale" &
  local pid=$!

  if ! wait_for_window "$pid"; then
    log "  ERROR: la ventana no apareció a tiempo -- abortando este idioma"
    kill "$pid" 2>/dev/null || true
    return
  fi
  sleep 1 # deja terminar el primer layout

  # Álbumes y Canciones: confirmadas a mano contra la app real
  # (2026-09-07) -- fila seleccionada, título de ventana cambia,
  # captura correcta, biblioteca de prueba visible.
  if select_sidebar_row "AuraStudio" "biblioteca.barraLateral.albumes" 2>/dev/null; then
    sleep 0.8
    capture_window "AuraStudio" "$pid" "$lang_out/albumes.png"
  else
    log "  aviso: no se pudo navegar a Álbumes"
  fi

  if select_sidebar_row "AuraStudio" "biblioteca.barraLateral.canciones" 2>/dev/null; then
    sleep 0.8
    capture_window "AuraStudio" "$pid" "$lang_out/canciones.png"
  else
    log "  aviso: no se pudo navegar a Canciones"
  fi

  # Ajustes/Dispositivos/Acerca de: MISMO mecanismo que Álbumes/
  # Canciones (fila de barra lateral idéntica, o menú posicional para
  # Acerca de), pero no reconfirmadas visualmente hoy -- una prueba en
  # vivo se interrumpió porque la Mac dejó de estar libre a mitad de
  # la corrida (`frontmost` pasó a otro proceso; ver DECISIONS.md) y
  # se cortó la sesión interactiva por precaución, mismo criterio que
  # ST-187 con XCUITest. Debería andar igual -- confirmarlo la próxima
  # vez que la Mac esté libre, antes de confiar ciegamente en esto para
  # los seis idiomas cuando A7c cierre.
  if select_sidebar_row "AuraStudio" "biblioteca.barraLateral.ajustes" 2>/dev/null; then
    sleep 0.8
    capture_window "AuraStudio" "$pid" "$lang_out/ajustes.png"

    # ST-225 (A5) agregó identificadores reales por pestaña
    # (`ajustes.pestana.*`) -- ya no hace falta texto localizado para
    # llegar a Almacenamiento. `press_element_by_identifier` es
    # GENÉRICO (AXPress directo, no `select` de fila) porque un
    # `Picker` segmentado es un control distinto a la barra lateral --
    # sin confirmar en vivo todavía, ver el comentario de la función.
    if press_element_by_identifier "AuraStudio" "ajustes.pestana.almacenamiento" 2>/dev/null; then
      sleep 0.8
      capture_window "AuraStudio" "$pid" "$lang_out/ajustes-almacenamiento.png"
    else
      log "  aviso: no se pudo navegar a Ajustes > Almacenamiento"
    fi
  else
    log "  aviso: no se pudo navegar a Ajustes"
  fi

  if select_sidebar_row "AuraStudio" "biblioteca.barraLateral.general" 2>/dev/null; then
    sleep 0.8
    capture_window "AuraStudio" "$pid" "$lang_out/dispositivos.png"
  else
    log "  aviso: no se pudo navegar a Dispositivos"
  fi

  if click_about_menu_item "AuraStudio" 2>/dev/null; then
    sleep 0.8
    capture_window "AuraStudio" "$pid" "$lang_out/acerca-de.png"
  else
    log "  aviso: no se pudo abrir Acerca de"
  fi

  # TODO(A7c o quien lo necesite antes): barra-estado-mensaje-largo --
  # hace falta disparar una operación real (importar/sincronizar en
  # curso) para que LibraryStatusBar muestre un mensaje largo, y
  # confirmar visualmente que no se corta -- no automatizado hoy.

  quit_app "AuraStudio"
}

# Aviso, no bloqueo: `select_sidebar_row`/`click_about_menu_item`
# mandan clics sintéticos de verdad -- mismo motivo que ST-187 con
# XCUITest ("nadie usando la Mac mientras corre"), aunque acá el riesgo
# es menor (unos pocos clics, no arrastrar el mouse). Si la app que de
# verdad está al frente ahora mismo no es Finder/nada, probablemente
# alguien esté trabajando -- se avisa y se sigue igual, porque no hay
# forma confiable de saber "está bien interrumpir" desde un script.
frontmost_now="$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null || echo '?')"
log "proceso al frente ahora mismo: $frontmost_now -- si alguien está usando la Mac, los clics de este script pueden estorbar"

mkdir -p "$OUT_DIR"
for lang in "${LANGUAGES[@]}"; do
  capture_language "$lang"
done

log "listo. Ver $OUT_DIR"
