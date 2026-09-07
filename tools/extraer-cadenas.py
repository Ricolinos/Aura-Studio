#!/usr/bin/env python3
"""PLAN-studio-ajustes-3.md §3 (Fase A7a, ST-227): extracción EN SECO de
los literales de interfaz de Sources/AuraStudio -- nunca toca Sources/,
solo lee y produce dos borradores de revisión en docs/extraccion-cadenas/:

- revision.csv: archivo:línea, literal, clave propuesta, tipo, si es
  duplicado de otro sitio, si tiene interpolación, si es un ternario de
  plural.
- borrador.Localizable.xcstrings: un String Catalog con el español como
  fuente y "en" vacío -- el punto de partida para que "experto en
  código opus" aplique la extracción real en A7a (cambiar cada literal
  por `String(localized: "<clave>", defaultValue: "<texto>")` o
  equivalente, según decida).

Uso: python3 tools/extraer-cadenas.py [--sources-dir RUTA] [--out-dir RUTA]

Las claves y las conversiones de interpolación a %@/%lld son heurísticas
-- este script es un borrador para que una persona (o Opus) revise, no
un resultado final automático.
"""

import argparse
import csv
import json
import re
import unicodedata
from pathlib import Path

# Cada patrón encuentra el llamado y se detiene justo DESPUÉS de la
# comilla de apertura del primer argumento -- el contenido ya NO lo
# captura el regex (ver `scan_swift_string_literal`, más abajo, y por
# qué). Suficiente para el barrido de un solo renglón que cubre la
# enorme mayoría de los casos reales (confirmado con la auditoría
# previa, docs/auditoria-idiomas.md).
PATTERNS = [
    ("Text", re.compile(r'\bText\(\s*"')),
    ("Button", re.compile(r'\bButton\(\s*"')),
    ("Label", re.compile(r'\bLabel\(\s*"')),
    (".help", re.compile(r'\.help\(\s*"')),
    (".navigationTitle", re.compile(r'\.navigationTitle\(\s*"')),
    ("Menu", re.compile(r'\bMenu\(\s*"')),
    ("CommandMenu", re.compile(r'\bCommandMenu\(\s*"')),
    (".alert", re.compile(r'\.alert\(\s*"')),
    ("Alert", re.compile(r'\bAlert\(\s*title:\s*Text\(\s*"')),
    ("Toggle", re.compile(r'\bToggle\(\s*"')),
    ("Picker", re.compile(r'\bPicker\(\s*"')),
    ("Section", re.compile(r'\bSection\(\s*"')),
    ("String(format:)", re.compile(r'String\(\s*format:\s*"')),
]


def scan_swift_string_literal(text, start):
    """A partir de `start` (justo después de la comilla de apertura),
    devuelve (contenido_crudo, posición justo después de la comilla de
    cierre).

    Por qué existe: un regex de un solo carácter (`[^"\\]|\\.`) no
    puede distinguir la comilla que CIERRA el literal de una comilla
    que vive DENTRO de una interpolación con su propio ternario
    anidado -- casos reales de este repo, `Text("\\(x == 1 ? "1 cosa" :
    "\\(x) cosas")")` (SeriesView.swift/SimilarItemsView.swift): el
    regex viejo cortaba en la primera comilla del ternario interno,
    dejando la clave a mitad de frase y terminada en un espacio suelto
    -- exactamente el defecto que Windows encontró con su
    concatenación por `+`, acá con interpolaciones anidadas en vez de
    `+`. Escanea carácter por carácter y solo trata una comilla como
    cierre cuando la profundidad de `\\(...)` es cero.
    """
    i = start
    depth = 0
    result = []
    while i < len(text):
        ch = text[i]
        if ch == "\\" and i + 1 < len(text):
            if text[i + 1] == "(":
                depth += 1
            result.append(text[i:i + 2])
            i += 2
            continue
        if ch == "(" and depth > 0:
            depth += 1
        elif ch == ")" and depth > 0:
            depth -= 1
        elif ch == '"' and depth == 0:
            return "".join(result), i + 1
        result.append(ch)
        i += 1
    return "".join(result), i  # sin cerrar -- se llegó al final de la línea

# Un ternario de plural: `algo == 1 ? "singular" : "plural"` (o `> 1`,
# `!= 1`) en el mismo renglón que uno de los patrones de arriba, o
# suelto en cualquier línea -- el plan pide listarlos aparte (nunca se
# van a resolver solo traduciendo el texto).
PLURAL_TERNARY = re.compile(r'==?\s*1\s*\?\s*"((?:[^"\\]|\\.)*)"\s*:\s*"((?:[^"\\]|\\.)*)"')

INTERPOLATION = re.compile(r'\\\(([^()]*(?:\([^()]*\)[^()]*)*)\)')

# ST-247 (Windows) encontró que su extractor partía una frase
# concatenada con `+` en un fragmento por literal -- 41 frases, 56
# claves de más, intraducibles. Acá el patrón real es más chico (un
# solo sitio, ExtrasView.swift:173: `Text("..." + (cond ? "" :
# "..."))`) pero el defecto es el mismo en espíritu: el barrido de un
# solo renglón capturaba el primer literal completo (termina en punto,
# se ve bien solo) y el segundo desaparecía sin ninguna clave --
# "cortado a mitad de oración" al revés, la mitad que falta ni
# siquiera se nota si no se busca a propósito.
PLAIN_STRING_LITERAL = re.compile(r'^\s*"((?:[^"\\]|\\.)*)"')
TERNARY_STRING_BRANCHES = re.compile(r'^\(?\s*[^()"]*\?\s*"((?:[^"\\]|\\.)*)"\s*:\s*"((?:[^"\\]|\\.)*)"\s*\)?')
LEADING_PLUS = re.compile(r'^\s*\+\s*')


def marker_for_computed_expression(expr):
    """Heurística para el tramo CALCULADO entre dos `+`
    (`ArtistNameNormalizer.collaborationSeparators.joined(...)`,
    MusicSettingsView.swift:84) -- mismo criterio de tipo que
    `convert_interpolations` (¿parece un conteo? -> `%lld`; si no,
    `%@`), pero acá el expr puede no reconocerse en absoluto (llamadas
    encadenadas, closures) y en ESE caso NO se asume `%@` a ciegas:
    Opus cazó a mano el defecto real (ST-227, "separadores-que-
    agrupan"): esta misma función, antes de existir, dejaba
    desaparecer el tramo del todo, sin ningún marcador -- aplicar esa
    clave tal cual habría borrado la lista de separadores de la
    pantalla. Un marcador `{n}` genérico, de forma distinta a `%@`,
    es una señal VISIBLE de "esto necesita ojos humanos" -- nunca
    desaparecer en silencio es la prioridad, aunque el marcador quede
    sin poder afirmar el tipo.
    """
    stripped = expr.strip()
    if not stripped:
        return None
    if re.search(r"\.count\b", stripped) or (re.fullmatch(r"[a-zA-Z_][a-zA-Z0-9_.]*", stripped) and "count" in stripped.lower()):
        return "%lld"
    if re.fullmatch(r"[a-zA-Z_][a-zA-Z0-9_.]*", stripped):
        return "%@"
    return "{n}"


def _parens_balanced(fragment):
    """El caso real que esto existe para atrapar
    (ExtrasView.swift:173): una interpolación con una coma adentro,
    `\\(x.joined(separator: ", "))`, tiene una comilla suelta que el
    regex de rama de ternario no puede distinguir de "acá termina la
    rama" -- ninguna expresión regular puede, sin un parser de Swift de
    verdad (fuera de alcance para un borrador). El fragmento capturado
    en ese caso queda cortado a la mitad, con paréntesis sin cerrar --
    eso SÍ se puede detectar sin parsear Swift, y es la señal de "no
    confíes en este fragmento, no lo unas en silencio"."""
    return fragment.count("(") == fragment.count(")")


def extend_with_concatenation(lines, line_idx, after_pos, first_raw, max_lookahead_lines=6):
    """Si lo que sigue al literal ya capturado es ` + ...` (misma
    línea o las siguientes -- `Text("fragmento A" + otraCosa)`), reúne
    los fragmentos de la MISMA expresión antes de que el llamador arme
    la clave. Dos formas reales, las dos vistas en este repo o en el
    hermano de Windows:

    - Concatenación simple: `"A" + "B"` (MusicSettingsView.swift:84-85,
      con un tramo calculado en el medio, `"A" + calculado() + "B"`) --
      se unen los literales, tal cual, saltando lo que no es literal.
    - Ternario con una rama vacía (ExtrasView.swift:173,
      `"A" + (cond ? "" : "B")`): la rama vacía es el caso "sin nada
      que agregar" (A solo ya es una oración completa); la rama con
      texto es la variante MÁS LARGA de la misma oración -- se toma
      esa, no las dos concatenadas a la fuerza (un ternario significa
      "una u otra", nunca las dos a la vez).

    El `+` de Swift no se repite en cada línea envuelta -- puede quedar
    al FINAL de la primera línea (ExtrasView, el ternario sigue solo,
    sin `+` propio, en el renglón de abajo) o al PRINCIPIO de cada
    línea siguiente (MusicSettingsView, con `+` al inicio de la
    línea 85) -- por eso todo esto trabaja sobre una VENTANA de texto
    plana (esta línea + las siguientes, unidas), no línea por línea.

    Devuelve (texto_combinado, estado) -- estado es `"unido"`,
    `"revisar"` (se detectó una concatenación pero no se pudo separar
    con confianza -- ver `_parens_balanced`) o `None` (no había nada
    que unir). `texto_combinado` sigue con el escape de Swift sin
    resolver, igual que `first_raw` -- `unescape()` se aplica una sola
    vez, después, sobre el resultado ya unido.
    """
    window = " ".join([lines[line_idx][after_pos:]] + lines[line_idx + 1:line_idx + 1 + max_lookahead_lines])

    if not LEADING_PLUS.match(window):
        return first_raw, None

    combined = first_raw
    status = None
    cursor = 0
    while True:
        plus = LEADING_PLUS.match(window[cursor:])
        if not plus:
            break
        cursor += plus.end()
        rest = window[cursor:]

        ternary = TERNARY_STRING_BRANCHES.match(rest)
        plain = PLAIN_STRING_LITERAL.match(rest)
        if ternary:
            branch_a, branch_b = ternary.group(1), ternary.group(2)
            # La rama no vacía es la variante completa -- si las dos
            # tienen texto, un ternario de verdad significa "una U
            # otra", no las dos juntas; se deja la segunda (el caso más
            # común: "" vacío / "con esto" al final).
            fragment = branch_a if branch_a.strip() and not branch_b.strip() else branch_b
            if _parens_balanced(fragment):
                combined += fragment
                status = "unido"
            else:
                status = "revisar"
                break  # fragmento sin confianza -- no seguir de acá
            cursor += ternary.end()
        elif plain:
            combined += plain.group(1)
            status = "unido"
            cursor += plain.end()
        else:
            # Después del `+` no hay ni un literal plano ni un ternario
            # reconocible en lo que queda de la ventana -- tramo
            # CALCULADO (`ArtistNameNormalizer....joined(...)`,
            # MusicSettingsView.swift:84). El defecto real que Opus
            # cazó al aplicar el borrador: saltarse este tramo SIN
            # dejar ningún marcador hace que el texto final no diga
            # que ahí faltaba algo -- aplicarlo tal cual borra la
            # lista de separadores de la pantalla, en silencio. Un
            # marcador (`%@`/`%lld`/`{n}`) reemplaza el tramo, nunca
            # desaparece sin dejar rastro.
            next_plus = re.search(r'\+', rest)
            expr = rest[:next_plus.start()] if next_plus else rest
            marker = marker_for_computed_expression(expr)
            if marker:
                combined += marker
                status = "unido"
            if not next_plus:
                break
            cursor += next_plus.start()

    return combined, status


def slugify(text, max_words=6, max_len=40):
    """Texto en español -> slug ascii-kebab-case, para la mitad
    "texto-corto" de la clave. Nunca vacío: si no queda nada legible
    (el literal era solo interpolación/símbolos), usa "texto"."""
    normalized = unicodedata.normalize("NFKD", text)
    ascii_text = normalized.encode("ascii", "ignore").decode("ascii")
    ascii_text = re.sub(r"\\\([^)]*\)", " ", ascii_text)  # quita interpolaciones antes de eslugificar
    words = re.findall(r"[a-zA-Z0-9]+", ascii_text.lower())
    words = [w for w in words if w not in {"el", "la", "los", "las", "de", "del", "un", "una", "y", "en", "a"}][:max_words]
    slug = "-".join(words) or "texto"
    return slug[:max_len].rstrip("-")


def file_stem_key(path: Path) -> str:
    stem = path.stem  # "PlaylistsView"
    # CamelCase -> kebab-case
    kebab = re.sub(r"(?<!^)(?=[A-Z])", "-", stem).lower()
    return kebab


def convert_interpolations(text):
    """`\\(expr)` -> `%@` (o `%lld` si `expr` huele a entero/conteo) --
    heurística, para revisar a mano. Devuelve (texto_convertido, huboInterpolacion)."""
    found = False

    def replace(match):
        nonlocal found
        found = True
        expr = match.group(1)
        if re.search(r"\.count\b", expr) or re.fullmatch(r"[a-zA-Z_][a-zA-Z0-9_]*", expr) and "count" in expr.lower():
            return "%lld"
        if re.fullmatch(r"\d+", expr):
            return "%lld"
        return "%@"

    converted = INTERPOLATION.sub(replace, text)
    return converted, found


def unescape(text):
    return text.replace('\\"', '"').replace("\\n", "\n").replace("\\t", "\t")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sources-dir", default="studio/AuraStudio/Sources/AuraStudio")
    parser.add_argument("--out-dir", default="docs/extraccion-cadenas")
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[1]
    sources_dir = (repo_root / args.sources_dir).resolve()
    out_dir = (repo_root / args.out_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    swift_files = sorted(sources_dir.rglob("*.swift"))

    # sitio = (archivo relativo, línea, tipo, texto original crudo)
    sites = []
    plural_sites = []
    joined_sites = []  # (archivo, línea, texto ya unido) -- para el reporte y la prueba
    unresolved_concat_sites = []  # (archivo, línea) -- se detectó un `+` pero no se pudo separar con confianza

    for path in swift_files:
        rel = path.relative_to(repo_root)
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        for line_number, line in enumerate(lines, start=1):
            for kind, pattern in PATTERNS:
                for match in pattern.finditer(line):
                    raw, end_pos = scan_swift_string_literal(line, match.end())
                    if not raw.strip():
                        continue
                    # `raw` sale siempre seguro de acá: si el estado es
                    # "revisar", `extend_with_concatenation` deja `raw`
                    # tal como entró (el primer fragmento solo, sin
                    # texto corrupto pegado) -- lo inseguro se descarta
                    # adentro, nunca sale a `sites`.
                    raw, status = extend_with_concatenation(
                        lines, line_number - 1, end_pos, raw)
                    if status == "unido":
                        joined_sites.append((str(rel), line_number, raw))
                    elif status == "revisar":
                        unresolved_concat_sites.append((str(rel), line_number))
                    sites.append((str(rel), line_number, kind, raw))
            plural_match = PLURAL_TERNARY.search(line)
            if plural_match:
                plural_sites.append((str(rel), line_number, plural_match.group(1), plural_match.group(2)))

    # Agrupa por TEXTO ORIGINAL (tal cual, con interpolaciones crudas) --
    # el mismo texto en más de un sitio comparte una sola clave.
    by_text = {}
    for rel, line_number, kind, raw in sites:
        by_text.setdefault(raw, []).append((rel, line_number, kind))

    key_by_text = {}
    used_keys = set()
    for raw, occurrences in by_text.items():
        first_file = Path(occurrences[0][0])
        base = f"{file_stem_key(first_file)}.{slugify(unescape(raw))}"
        key = base
        suffix = 2
        while key in used_keys:
            key = f"{base}-{suffix}"
            suffix += 1
        used_keys.add(key)
        key_by_text[raw] = key

    # CSV de revisión: una fila por SITIO (no por clave), para que se
    # vea cada archivo:línea real, con la clave que comparten si hay
    # duplicados.
    csv_path = out_dir / "revision.csv"
    with csv_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["clave_propuesta", "archivo", "linea", "tipo", "texto_original",
                         "texto_con_marcadores", "tiene_interpolacion", "duplicado_de_n_sitios"])
        for raw, occurrences in sorted(by_text.items(), key=lambda kv: key_by_text[kv[0]]):
            key = key_by_text[raw]
            converted, has_interpolation = convert_interpolations(unescape(raw))
            for rel, line_number, kind in occurrences:
                writer.writerow([key, rel, line_number, kind, unescape(raw), converted,
                                 "sí" if has_interpolation else "no",
                                 len(occurrences) if len(occurrences) > 1 else ""])

    # Plurales por ternario, aparte -- el plan los pide listados, nunca
    # resueltos por esta herramienta (necesitan un mecanismo real de
    # reglas de plural, no una clave más).
    plurals_path = out_dir / "plurales-ternario.csv"
    with plurals_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["archivo", "linea", "singular", "plural"])
        for rel, line_number, singular, plural in plural_sites:
            writer.writerow([rel, line_number, unescape(singular), unescape(plural)])

    # Frases que la extracción unió porque venían concatenadas con `+`
    # -- aparte, para que se pueda revisar CADA una a mano (el ternario
    # con una rama vacía es una heurística, no un parser real de Swift)
    # y para que la prueba de A7a confirme el número exacto, igual que
    # hizo Windows con sus 41. Incluye también los casos detectados
    # pero NO unidos (estado "revisar") -- se encontró un `+` pero el
    # fragmento de después no se pudo separar con confianza (paréntesis
    # sin cerrar, típico de una interpolación con una coma adentro,
    # `\(x.joined(separator: ", "))` -- ningún regex distingue esa
    # coma de "acá termina el literal" sin parsear Swift de verdad).
    # Ahí la clave sigue siendo el primer fragmento solo, SIN texto
    # corrupto pegado -- pero el sitio queda marcado para que alguien
    # lo mire, en vez de perderse en silencio otra vez.
    joined_path = out_dir / "fragmentos-unidos.csv"
    with joined_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["archivo", "linea", "estado", "texto_unido"])
        for rel, line_number, raw in joined_sites:
            writer.writerow([rel, line_number, "unido", unescape(raw)])
        for rel, line_number in unresolved_concat_sites:
            writer.writerow([rel, line_number, "revisar a mano", ""])

    # Borrador de String Catalog (.xcstrings): español como fuente,
    # "en" vacío ("new") -- estructura real del formato de Xcode.
    strings = {}
    for raw, key in key_by_text.items():
        converted, _ = convert_interpolations(unescape(raw))
        strings[key] = {
            "extractionState": "manual",
            "localizations": {
                "es": {"stringUnit": {"state": "translated", "value": converted}},
                "en": {"stringUnit": {"state": "new", "value": ""}},
            },
        }
    catalog = {"sourceLanguage": "es", "strings": strings, "version": "1.0"}
    xcstrings_path = out_dir / "borrador.Localizable.xcstrings"
    xcstrings_path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True), encoding="utf-8")

    print(f"Archivos Swift recorridos: {len(swift_files)}")
    print(f"Sitios de literal encontrados: {len(sites)}")
    print(f"Claves únicas propuestas: {len(key_by_text)}")
    duplicated = sum(1 for occ in by_text.values() if len(occ) > 1)
    print(f"Textos duplicados (una sola clave, varios sitios): {duplicated}")
    print(f"Ternarios de plural encontrados: {len(plural_sites)}")
    print(f"Frases unidas (venían concatenadas con +): {len(joined_sites)}")
    if unresolved_concat_sites:
        print(f"Concatenaciones detectadas pero SIN unir con confianza (revisar a mano): {len(unresolved_concat_sites)}")
    print(f"-> {csv_path.relative_to(repo_root)}")
    print(f"-> {plurals_path.relative_to(repo_root)}")
    print(f"-> {joined_path.relative_to(repo_root)}")
    print(f"-> {xcstrings_path.relative_to(repo_root)}")


if __name__ == "__main__":
    main()
