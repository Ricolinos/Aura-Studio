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

# Cada patrón captura el PRIMER argumento con cadena literal del
# llamado -- suficiente para el barrido de un solo renglón que cubre
# la enorme mayoría de los casos reales (confirmado con la auditoría
# previa, docs/auditoria-idiomas.md).
PATTERNS = [
    ("Text", re.compile(r'\bText\(\s*"((?:[^"\\]|\\.)*)"')),
    ("Button", re.compile(r'\bButton\(\s*"((?:[^"\\]|\\.)*)"')),
    ("Label", re.compile(r'\bLabel\(\s*"((?:[^"\\]|\\.)*)"')),
    (".help", re.compile(r'\.help\(\s*"((?:[^"\\]|\\.)*)"')),
    (".navigationTitle", re.compile(r'\.navigationTitle\(\s*"((?:[^"\\]|\\.)*)"')),
    ("Menu", re.compile(r'\bMenu\(\s*"((?:[^"\\]|\\.)*)"')),
    ("CommandMenu", re.compile(r'\bCommandMenu\(\s*"((?:[^"\\]|\\.)*)"')),
    (".alert", re.compile(r'\.alert\(\s*"((?:[^"\\]|\\.)*)"')),
    ("Alert", re.compile(r'\bAlert\(\s*title:\s*Text\(\s*"((?:[^"\\]|\\.)*)"')),
    ("Toggle", re.compile(r'\bToggle\(\s*"((?:[^"\\]|\\.)*)"')),
    ("Picker", re.compile(r'\bPicker\(\s*"((?:[^"\\]|\\.)*)"')),
    ("Section", re.compile(r'\bSection\(\s*"((?:[^"\\]|\\.)*)"')),
    ("String(format:)", re.compile(r'String\(\s*format:\s*"((?:[^"\\]|\\.)*)"')),
]

# Un ternario de plural: `algo == 1 ? "singular" : "plural"` (o `> 1`,
# `!= 1`) en el mismo renglón que uno de los patrones de arriba, o
# suelto en cualquier línea -- el plan pide listarlos aparte (nunca se
# van a resolver solo traduciendo el texto).
PLURAL_TERNARY = re.compile(r'==?\s*1\s*\?\s*"((?:[^"\\]|\\.)*)"\s*:\s*"((?:[^"\\]|\\.)*)"')

INTERPOLATION = re.compile(r'\\\(([^()]*(?:\([^()]*\)[^()]*)*)\)')


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

    for path in swift_files:
        rel = path.relative_to(repo_root)
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        for line_number, line in enumerate(lines, start=1):
            for kind, pattern in PATTERNS:
                for match in pattern.finditer(line):
                    raw = match.group(1)
                    if not raw.strip():
                        continue
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
    print(f"-> {csv_path.relative_to(repo_root)}")
    print(f"-> {plurals_path.relative_to(repo_root)}")
    print(f"-> {xcstrings_path.relative_to(repo_root)}")


if __name__ == "__main__":
    main()
