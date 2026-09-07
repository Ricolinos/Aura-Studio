#!/usr/bin/env python3
"""Pruebas de `extraer-cadenas.py` (ST-227 addendum): el defecto real que
"experto en código opus" cazó al aplicar el borrador -- un tramo
CALCULADO entre dos `+` (`ArtistNameNormalizer.collaborationSeparators.
joined(...)`, MusicSettingsView.swift:84) desaparecía sin dejar ningún
marcador. Aplicar esa clave tal cual habría borrado la lista de
separadores de la pantalla, en silencio -- exactamente la clase de
defecto que una prueba tiene que impedir que se repita.

Sin `pytest` (no hay ninguna dependencia Python en este repo todavía) --
`unittest` de la biblioteca estándar alcanza. Uso:

    python3 tools/test_extraer_cadenas.py
"""

import importlib.util
import unittest
from pathlib import Path

_SPEC = importlib.util.spec_from_file_location(
    "extraer_cadenas", Path(__file__).resolve().parent / "extraer-cadenas.py")
extraer_cadenas = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(extraer_cadenas)


class MarkerForComputedExpressionTests(unittest.TestCase):
    def test_simple_identifier_becomes_at_marker(self):
        self.assertEqual(extraer_cadenas.marker_for_computed_expression("albumName"), "%@")

    def test_count_like_identifier_becomes_lld_marker(self):
        self.assertEqual(extraer_cadenas.marker_for_computed_expression("items.count"), "%lld")
        self.assertEqual(extraer_cadenas.marker_for_computed_expression("trackCount"), "%lld")

    def test_method_chain_becomes_generic_marker_not_at_sign(self):
        # El caso real: NO se puede afirmar el tipo, pero TAMPOCO se
        # asume %@ a ciegas -- {n} es la señal visible de "revisar".
        expr = "ArtistNameNormalizer.collaborationSeparators.joined(separator: \", \")"
        self.assertEqual(extraer_cadenas.marker_for_computed_expression(expr), "{n}")

    def test_empty_expression_yields_no_marker(self):
        self.assertIsNone(extraer_cadenas.marker_for_computed_expression("   "))


class ExtendWithConcatenationComputedExpressionTests(unittest.TestCase):
    """El caso real de MusicSettingsView.swift:84-85, reducido a lo
    mínimo -- un literal, un tramo calculado, otro literal."""

    def test_computed_expression_between_two_literals_gets_a_marker_not_silence(self):
        lines = [
            'Text("Separadores que agrupan: " + ArtistNameNormalizer.joined(separator: ", ")',
            '     + ". fin.")',
        ]
        combined, status = extraer_cadenas.extend_with_concatenation(
            lines, 0, len('Text("Separadores que agrupan: "'), "Separadores que agrupan: ")
        self.assertEqual(status, "unido")
        # El tramo calculado NUNCA desaparece sin dejar rastro -- antes
        # de este arreglo, `combined` habría quedado
        # "Separadores que agrupan: . fin." (el "{n}" faltante), que es
        # justo el defecto que Opus encontró a mano.
        self.assertIn("{n}", combined)
        self.assertTrue(combined.endswith(". fin."))

    def test_pure_literal_concatenation_still_works_unaffected(self):
        # ST-247 addendum original -- no debe regresionar por este
        # cambio: "A" + "B" sigue uniéndose tal cual, sin ningún
        # marcador de por medio (no hay ningún tramo calculado acá).
        lines = ['Text("Hola " + "mundo.")']
        combined, status = extraer_cadenas.extend_with_concatenation(
            lines, 0, len('Text("Hola "'), "Hola ")
        self.assertEqual(status, "unido")
        self.assertEqual(combined, "Hola mundo.")
        self.assertNotIn("{n}", combined)


if __name__ == "__main__":
    unittest.main()
