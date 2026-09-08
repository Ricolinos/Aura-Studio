#!/usr/bin/env python3
"""ST-227 (A7c, cierre 7): TODO literal de dos o más palabras en Sources/.

**Por qué hace falta una segunda barrida.** El detector de literales de
A7a (`LocalizationDraftTests`) reconoce el español por el acento y la
"ñ", y el triaje de `triaje-fuera-de-a7a.tsv` añadía una lista de
palabras funcionales. Las dos comparten el mismo agujero, que Windows
descubrió en su lado: **una frase en español sin acento y sin ninguna de
esas palabras es invisible**. "Formatos distintos", "Misma duración",
"El arbol de X en el iPod esta incompleto" -- ninguna se veía, y el
conteo del triaje era un subconteo.

Así que esta barrida **no tiene léxico**. No decide si algo es español:
saca todo literal que parezca una frase y deja el juicio a una persona.
Es para LEER, no para contar; que sobren candidatos es el punto.

Lo que sí se descarta, porque no es prosa por su forma y no por su
idioma: rutas, URLs, identificadores en reverse-DNS, nombres de símbolo
SF, claves de configuración, formatos de fecha o de printf, nombres de
archivo con extensión conocida, y lo que ya pasa por `LS`/`LSf`.

Uso:
    python3 tools/barrido-literales.py                 # a stdout
    python3 tools/barrido-literales.py --tsv <archivo> # TSV para triaje
"""
import argparse
import collections
import pathlib
import re
import sys

RAIZ = pathlib.Path(__file__).resolve().parent.parent
FUENTES = RAIZ / "studio/AuraStudio/Sources/AuraStudio"

# Un literal de UNA línea. Los `"""` van aparte: ver `MULTILINEA`.
LITERAL = re.compile(r'(?<!")"((?:[^"\\]|\\.)*)"(?!")')
# ST-227 (addendum): los literales MULTILÍNEA de Swift. Los tres barridos
# anteriores eran ciegos a ellos porque sus expresiones regulares solo
# miraban una línea, y ahí viven los cuerpos de diálogo -- en la Mac
# escondían los dos párrafos que Ajustes muestra bajo el interruptor de
# calidad de audio. Windows encontró lo mismo por otro camino (su filtro
# de rutas descartaba todo lo que llevara barra invertida, y "\n" lleva
# una).
MULTILINEA = re.compile(r'"""(.*?)"""', re.S)
PALABRA = re.compile(r"[A-Za-zÀ-ÿ]{2,}")

# Extensiones que aparecen en nombres de archivo del proyecto.
EXTENSIONES = r"(mp3|flac|m4a|m4b|mp4|wav|aiff|jpg|jpeg|png|gif|lrc|m3u|m3u8|cfg|json|tcd|zip|ipod|swift|py|sh|plist|txt|md|csv|tsv|xcstrings|strings|stringsdict)"

def es_ruido(s: str) -> bool:
    """Lo que NO es prosa por su FORMA (no por su idioma)."""
    t = s.strip()
    if len(t) < 4:
        return True
    if len(PALABRA.findall(t)) < 2:          # menos de dos palabras
        return True
    if t.startswith("/") or "://" in t:      # ruta o URL
        return True
    if re.fullmatch(r"[a-z0-9_.\-]+", t):    # identificador
        return True
    if re.fullmatch(r"[a-z]+(\.[a-z0-9]+)+", t):   # reverse-DNS
        return True
    if re.fullmatch(r"[\d%@$.:,\-/ ]+", t):  # formato de número/fecha/printf
        return True
    if re.fullmatch(r"[yMdHmsSZ\-/:. ]+", t):      # patrón de fecha
        return True
    if re.fullmatch(r"[\w.\- ]+\." + EXTENSIONES, t, re.I):   # nombre de archivo
        return True
    if re.fullmatch(r"[a-z]+(\.[a-z]+)*\.(fill|circle|slash)", t):  # símbolo SF
        return True
    if re.fullmatch(r"[a-z_]+:\s*\S*", t):   # clave de configuración ("theme: 1")
        return True
    return False

SHELL = re.compile(r"set -e|do shell script|pkill |diskutil |/bin/sh|nohup |\bdd \b|>/dev/null")

def sugerencia(linea: str, cuerpo: str = "") -> str:
    """Pista para quien haga el triaje. NO es la clasificación."""
    # Un guion de shell no es texto de pantalla por muchas palabras que
    # tenga: los de `PrivilegedExecutor` pasan de 300 y marcarlos
    # "¿PANTALLA?" llena el triaje de ruido.
    if SHELL.search(cuerpo) or SHELL.search(linea):
        return "¿INTERNO?"
    if re.search(r"\bprint\(|\blog\(|fatalError\(|assertionFailure|NSLog|debugPrint|\[[A-Z]\w+\]", linea):
        return "¿INTERNO?"
    if re.search(r"defaults\.set\(|forKey:|lines\.append\(|\.write\(to:", linea):
        return "¿DATO?"
    return "¿PANTALLA?"

def sin_comentarios(texto: str) -> list[str]:
    texto = re.sub(r"/\*.*?\*/", lambda m: "\n" * m.group(0).count("\n"), texto, flags=re.S)
    return ["" if l.strip().startswith(("//", "*", "///")) else l for l in texto.split("\n")]

def barrer():
    filas = []
    for ruta in sorted(FUENTES.rglob("*.swift")):
        relativa = ruta.relative_to(RAIZ)
        crudo = ruta.read_text(encoding="utf-8")

        # Multilínea primero, y se tapan en el texto para que el barrido
        # de una línea no vuelva a trocear su contenido.
        limpio_completo = "\n".join(sin_comentarios(crudo))
        for m in MULTILINEA.finditer(limpio_completo):
            cuerpo = " ".join(m.group(1).split())
            numero = limpio_completo[: m.start()].count("\n") + 1
            if es_ruido(cuerpo):
                continue
            linea_ctx = limpio_completo.split("\n")[numero - 1]
            filas.append((str(relativa), numero, len(PALABRA.findall(cuerpo)),
                          sugerencia(linea_ctx, cuerpo), cuerpo))
        sin_multi = MULTILINEA.sub(lambda m: "\n" * m.group(0).count("\n"), limpio_completo)

        for numero, linea in enumerate(sin_multi.split("\n"), 1):
            for m in LITERAL.finditer(linea):
                antes = linea[: m.start()].rstrip()
                if antes.endswith(("LS(", "LSf(")):
                    continue
                s = m.group(1)
                if es_ruido(s):
                    continue
                filas.append((str(relativa), numero, len(PALABRA.findall(s)), sugerencia(linea, s), s))
    return filas

def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--tsv")
    args = p.parse_args()
    filas = barrer()
    if args.tsv:
        import csv
        with open(args.tsv, "w", newline="", encoding="utf-8") as fh:
            w = csv.writer(fh, delimiter="\t")
            w.writerow(["clase", "archivo", "linea", "palabras", "sugerencia", "texto"])
            for a, n, pal, sug, s in filas:
                w.writerow(["", a, n, pal, sug, s[:300]])
        print(f"{len(filas)} literales -> {args.tsv}")
    else:
        for a, n, pal, sug, s in filas:
            print(f"{a}:{n}\t{sug}\t{s[:120]}")
        print(f"\nTOTAL: {len(filas)}", file=sys.stderr)
    por = collections.Counter(f[0].split("/")[-2] for f in filas)
    print("por carpeta:", dict(por), file=sys.stderr)
    return 0

if __name__ == "__main__":
    sys.exit(main())
