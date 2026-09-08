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
(ver CLAUDE.md). Como este script se corre A MANO, un catálogo editado sin
regenerar no falla en ningún lado: la app sigue mostrando el texto viejo.
Lo único que lo nota es
`LocalizationLanguagesTests.testEachLanguageTableMatchesTheCatalogAndNeverFallsBack`.

Uso: python3 tools/compilar-catalogo.py [--output-root RUTA]

`--output-root`: escribe los `.lproj` ahí en vez de en el repo real --
SIEMPRE lee el mismo `Localizable.xcstrings` real (nunca se genera
contra un catálogo de prueba, sería probar otra cosa). Existe para la
prueba de deriva (ST-227 addendum, `LocalizationCatalogTests`).
"""
import argparse
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
        # ST-227 (A7d): plural con SUSTITUCIÓN. El catálogo de Xcode lo
        # guarda como un `stringUnit` con tokens `%N$#@nombre@` más un
        # bloque `substitutions`; es la única forma de que la FORMA del
        # plural la elija un argumento y el texto MUESTRE otro -- que es
        # lo que hace falta para "12 345 canciones", donde el número va
        # ya formateado con el separador de miles del idioma y un `%lld`
        # a secas lo perdería.
        substitutions = localization.get("substitutions")
        if substitutions:
            plurals[key] = {"formato": localization["stringUnit"]["value"],
                            "sustituciones": {
                                nombre: {
                                    "argNum": spec.get("argNum", 1),
                                    "formatSpecifier": spec.get("formatSpecifier", "lld"),
                                    "formas": {f: v["stringUnit"]["value"]
                                               for f, v in spec["variations"]["plural"].items()
                                               if "stringUnit" in v},
                                }
                                for nombre, spec in substitutions.items()
                            }}
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


def xml_escape(value: str) -> str:
    """Un `.stringsdict` es un plist XML: `&`, `<` y `>` van escapados.

    Ninguna traducción los usa hoy, pero la que los use rompería el plist
    entero -- y el sistema no dice "este texto está mal", simplemente deja
    de leer TODOS los plurales de ese idioma. Escapar acá cuesta nada.
    """
    return (value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))


def stringsdict(plurals: dict) -> str:
    def bloque(nombre: str, especificador: str, formas: dict) -> str:
        rows = "".join(
            f"\t\t\t<key>{xml_escape(f)}</key>\n\t\t\t<string>{xml_escape(v)}</string>\n"
            for f, v in formas.items())
        return (f"\t\t<key>{xml_escape(nombre)}</key>\n\t\t<dict>\n"
                f"\t\t\t<key>NSStringFormatSpecTypeKey</key>\n\t\t\t<string>NSStringPluralRuleType</string>\n"
                f"\t\t\t<key>NSStringFormatValueTypeKey</key>\n\t\t\t<string>{xml_escape(especificador)}</string>\n"
                f"{rows}\t\t</dict>\n")

    def entry(key: str, forms) -> str:
        # Plural de toda la cadena: un solo argumento, el número.
        if not isinstance(forms, dict) or "sustituciones" not in forms:
            cuerpo = bloque("n", "lld", forms)
            return (f"\t<key>{xml_escape(key)}</key>\n\t<dict>\n"
                    f"\t\t<key>NSStringLocalizedFormatKey</key>\n\t\t<string>%#@n@</string>\n"
                    f"{cuerpo}\t</dict>\n")
        # Plural con sustitución: el formato exterior nombra los tokens.
        cuerpo = "".join(bloque(nombre, spec["formatSpecifier"], spec["formas"])
                         for nombre, spec in sorted(forms["sustituciones"].items()))
        return (f"\t<key>{xml_escape(key)}</key>\n\t<dict>\n"
                f"\t\t<key>NSStringLocalizedFormatKey</key>\n\t\t<string>{xml_escape(forms['formato'])}</string>\n"
                f"{cuerpo}\t</dict>\n")
    body = "".join(entry(key, forms) for key, forms in sorted(plurals.items()))
    return ('<?xml version="1.0" encoding="UTF-8"?>\n'
            '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
            '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
            '<plist version="1.0">\n<dict>\n' + body + '</dict>\n</plist>\n')


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-root", default=None,
                        help="escribir los .lproj acá en vez de en el repo real "
                             "(el catálogo que se lee sigue siendo siempre el real)")
    args = parser.parse_args()
    output_resources = pathlib.Path(args.output_root) if args.output_root else RESOURCES

    catalog = json.loads(CATALOG.read_text())
    strings = catalog.get("strings", {})
    languages = sorted({language
                        for entry in strings.values()
                        for language in entry.get("localizations", {})})
    for language in languages:
        content, plurals = build(language, strings)
        folder = output_resources / f"{language}.lproj"
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
