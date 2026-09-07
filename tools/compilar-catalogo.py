#!/usr/bin/env python3
"""ST-227: genera los `.lproj` que consume SwiftPM desde el String Catalog.

**Por qué existe.** `Localizable.xcstrings` es la fuente única y editable;
Xcode lo COMPILA solo al construir la app (que es el entregable). SwiftPM
no: copia el archivo tal cual, así que `String(localized:)` no encuentra
nada y devuelve la clave -- la app de pruebas mostraría
`media-section.eliminar` en vez de "Eliminar", y ninguna prueba sobre
texto valdría nada.

Este script rellena ese hueco: escribe `<idioma>.lproj/Localizable.strings`
(y `.stringsdict` cuando hay plurales) a partir del catálogo. Los archivos
generados NO se editan a mano -- misma regla que `Generated/AuraPalette.swift`
(ver CLAUDE.md) -- y hay una prueba que falla si se apartan del catálogo.

Uso: python3 tools/compilar-catalogo.py
"""
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
RESOURCES = ROOT / "studio/AuraStudio/Sources/AuraStudio/Resources"
CATALOG = RESOURCES / "Localizable.xcstrings"

AVISO = ("/* GENERADO por tools/compilar-catalogo.py desde\n"
         "   Localizable.xcstrings. No editar a mano: los cambios se pierden. */\n")


def escape(value: str) -> str:
    return (value.replace("\\", "\\\\").replace('"', '\\"')
                 .replace("\n", "\\n").replace("\t", "\\t"))


def build(language: str, strings: dict) -> tuple[str, dict]:
    """Devuelve (contenido de .strings, diccionario de plurales)."""
    lines = [AVISO]
    plurals: dict = {}
    for key in sorted(strings):
        localization = strings[key].get("localizations", {}).get(language)
        if localization is None:
            continue
        unit = localization.get("stringUnit")
        if unit is not None:
            lines.append(f'"{escape(key)}" = "{escape(unit["value"])}";')
            continue
        # Variantes de plural: van al .stringsdict, que es el formato que
        # el sistema sabe leer para elegir la forma correcta.
        variations = localization.get("variations", {}).get("plural")
        if not variations:
            continue
        forms = {name: spec["stringUnit"]["value"] for name, spec in variations.items()
                 if "stringUnit" in spec}
        if not forms:
            continue
        plurals[key] = forms
    return "\n".join(lines) + "\n", plurals


def stringsdict(plurals: dict) -> str:
    def entry(key: str, forms: dict) -> str:
        rows = "".join(
            f"\t\t\t<key>{name}</key>\n\t\t\t<string>{value}</string>\n"
            for name, value in forms.items())
        return (f"\t<key>{key}</key>\n\t<dict>\n"
                f"\t\t<key>NSStringLocalizedFormatKey</key>\n\t\t<string>%#@n@</string>\n"
                f"\t\t<key>n</key>\n\t\t<dict>\n"
                f"\t\t\t<key>NSStringFormatSpecTypeKey</key>\n\t\t\t<string>NSStringPluralRuleType</string>\n"
                f"\t\t\t<key>NSStringFormatValueTypeKey</key>\n\t\t\t<string>lld</string>\n"
                f"{rows}\t\t</dict>\n\t</dict>\n")
    body = "".join(entry(key, forms) for key, forms in sorted(plurals.items()))
    return ('<?xml version="1.0" encoding="UTF-8"?>\n'
            '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
            '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
            '<plist version="1.0">\n<dict>\n' + body + '</dict>\n</plist>\n')


def main() -> int:
    catalog = json.loads(CATALOG.read_text())
    strings = catalog.get("strings", {})
    languages = sorted({language
                        for entry in strings.values()
                        for language in entry.get("localizations", {})})
    for language in languages:
        content, plurals = build(language, strings)
        folder = RESOURCES / f"{language}.lproj"
        folder.mkdir(parents=True, exist_ok=True)
        (folder / "Localizable.strings").write_text(content)
        target = folder / "Localizable.stringsdict"
        if plurals:
            target.write_text(stringsdict(plurals))
        elif target.exists():
            target.unlink()
        print(f"{language}: {content.count(chr(10)) - 2} cadenas, {len(plurals)} plurales")
    return 0


if __name__ == "__main__":
    sys.exit(main())
