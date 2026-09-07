import XCTest
@testable import AuraStudio

/// PLAN-studio-ajustes-3.md §3 (Fase A7a, ST-227): "ensayo en seco" que
/// pidió "Sesión Maestra" -- los borradores de `tools/extraer-cadenas.py`
/// (`docs/extraccion-cadenas/`) ya existen (ST-227), así que estas
/// pruebas verifican su FORMA de verdad, ahora, sin esperar ninguna API
/// nueva -- no son placeholders. Sirven de red de regresión si alguien
/// (Opus o una corrida futura del script) vuelve a generar esos
/// archivos: si el borrador se rompe, esto lo dice antes de que alguien
/// intente construir el `.xcstrings` real sobre él.
///
/// La única excepción es `testNoAccentedTextOrEneLiteralsOutsideStringLocalized`,
/// el "detector de literales" del plan -- ESE sí espera a A7a (hoy
/// fallaría con cientos de sitios sin localizar), así que queda con
/// `XCTSkip` y el conteo de hoy como línea base documentada.
final class LocalizationDraftTests: XCTestCase {
    private func repoRoot() throws -> URL {
        // Igual que `LibraryPipelineIntegrationTests.repoTestMediaURL()`:
        // sube desde #filePath hasta encontrar la raíz del repo (acá,
        // por `docs/extraccion-cadenas/`), estable sin importar el build
        // system ni el directorio de trabajo actual.
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("docs/extraccion-cadenas").path) {
                return dir
            }
            dir = dir.deletingLastPathComponent()
        }
        throw XCTSkip("docs/extraccion-cadenas/ no se encontró -- ¿corriste tools/extraer-cadenas.py? (ST-227)")
    }

    private func loadDraftText() throws -> String {
        let url = try repoRoot().appendingPathComponent("docs/extraccion-cadenas/borrador.Localizable.xcstrings")
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func loadDraftJSON() throws -> [String: Any] {
        let data = Data(try loadDraftText().utf8)
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }

    // MARK: - Claves únicas

    /// `JSONSerialization` COLAPSA en silencio una clave de objeto
    /// repetida (se queda con la última) -- "claves únicas" hay que
    /// verificarlo sobre el TEXTO crudo, no sobre el diccionario ya
    /// decodificado, o una clave duplicada nunca se detectaría. La
    /// herramienta ya evita colisiones (`used_keys`/sufijo `-N`), así
    /// que esto es una red de regresión, no algo que hoy falle.
    func testAllKeysAreUnique() throws {
        let text = try loadDraftText()
        // `json.dumps(..., indent=2, sort_keys=True)` de Python: las
        // claves propuestas cuelgan de "strings" con 4 espacios de
        // sangría -- ver el archivo real, docs/extraccion-cadenas/
        // borrador.Localizable.xcstrings, para la forma exacta.
        let pattern = try NSRegularExpression(pattern: #"^    "([^"]+)": \{$"#, options: [.anchorsMatchLines])
        let matches = pattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
        let keys = matches.compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
        XCTAssertGreaterThan(keys.count, 0, "no se encontró ninguna clave -- ¿cambió el formato del borrador?")
        XCTAssertEqual(keys.count, Set(keys).count,
                       "hay claves repetidas en el borrador -- JSONSerialization las habría colapsado en silencio, ocultando el bug")
    }

    // MARK: - Especificadores de `%` consistentes entre variantes

    /// `tools/extraer-cadenas.py` solo produce dos formas
    /// (`convert_interpolations`): `%@` y `%lld` -- no hace falta un
    /// parser de printf general, solo reconocer esas dos. Para cada
    /// clave, compara los especificadores de TODAS las localizaciones
    /// con `stringUnit.value` no vacío -- hoy solo "es" tiene texto
    /// real ("en" es `state: "new", value: ""`), así que esto pasa
    /// trivialmente hoy (nada que comparar contra sí mismo), pero es la
    /// misma prueba que sí va a detectar una traducción que cambió de
    /// "%@ de %@" a solo "%@" el día que "en"/"ja"/"de"/"ru"/"fr" tengan
    /// contenido real.
    func testFormatSpecifiersMatchAcrossLocalizationsPerKey() throws {
        let json = try loadDraftJSON()
        let strings = try XCTUnwrap(json["strings"] as? [String: Any])
        XCTAssertGreaterThan(strings.count, 0)

        func specifiers(in value: String) -> [String] {
            let pattern = try! NSRegularExpression(pattern: #"%@|%lld"#)
            let matches = pattern.matches(in: value, range: NSRange(value.startIndex..., in: value))
            return matches.map { String(value[Range($0.range, in: value)!]) }
        }

        var mismatches: [String] = []
        for (key, entry) in strings {
            guard let entryDict = entry as? [String: Any],
                  let localizations = entryDict["localizations"] as? [String: Any] else { continue }
            var seen: [String: [String]] = [:]
            for (locale, localization) in localizations {
                guard let localizationDict = localization as? [String: Any],
                      let stringUnit = localizationDict["stringUnit"] as? [String: Any],
                      let value = stringUnit["value"] as? String,
                      !value.isEmpty else { continue }
                seen[locale] = specifiers(in: value)
            }
            guard let first = seen.values.first else { continue }
            if seen.values.contains(where: { $0 != first }) {
                mismatches.append("\(key): \(seen)")
            }
        }
        XCTAssertTrue(mismatches.isEmpty,
                      "especificadores %@/%lld distintos entre localizaciones de la misma clave: \(mismatches)")
    }

    // MARK: - Plurales por ternario: forma de variación válida

    /// `docs/extraccion-cadenas/plurales-ternario.csv` (ST-227, del
    /// mismo barrido): 23 filas hoy. No los resuelve esta prueba (eso
    /// necesita un mecanismo real de reglas de plural, ver la auditoría)
    /// -- solo confirma que cada fila tiene DOS formas DISTINTAS entre
    /// sí, el mínimo para que algo sea "una variación de plural" y no
    /// un ternario que en realidad no varía (falso positivo de la
    /// extracción). Una de las dos formas SÍ puede venir vacía --
    /// `SimilarItemsView.swift:188` es un sufijo real, `n == 1 ? "" :
    /// "s"` (inglés, no el patrón de palabra completa en español que
    /// domina el resto del archivo) -- así que no se exige que ambas
    /// tengan contenido, solo que no sean la MISMA cosa.
    func testPluralCSVRowsHaveTwoDistinctForms() throws {
        let url = try repoRoot().appendingPathComponent("docs/extraccion-cadenas/plurales-ternario.csv")
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).dropFirst() // sin encabezado

        var rows: [(singular: String, plural: String)] = []
        for line in lines {
            let fields = line.split(separator: ",", maxSplits: 3, omittingEmptySubsequences: false)
            guard fields.count == 4 else { continue }
            rows.append((singular: String(fields[2]), plural: String(fields[3])))
        }

        // 23 es el conteo real de hoy (docs/auditoria-idiomas.md,
        // 2026-09-06) -- si vuelve a correr el extractor tras cambios en
        // Sources/, este número puede moverse; si esta aserción falla
        // por eso, actualizar el número, no borrar la prueba.
        XCTAssertEqual(rows.count, 23, "el número de plurales por ternario cambió -- confirmar si es real o un bug del extractor")

        for row in rows {
            XCTAssertFalse(row.singular.isEmpty && row.plural.isEmpty, "singular y plural vacíos a la vez -- fila sin contenido real")
            XCTAssertNotEqual(row.singular, row.plural,
                              "singular y plural idénticos (\"\(row.singular)\") -- no es una variación real, probable falso positivo del ternario")
        }
    }

    // MARK: - Detector de literales (el que sí espera a A7a)

    /// El criterio de cierre real de A7a (§3 del plan): CERO
    /// `Text("...")`/`Label("...")` con una letra acentuada o "ñ" que no
    /// pase por `String(localized:)`/una clave real. Hoy falla por
    /// cientos -- se deja documentado con `XCTSkip`, línea base de la
    /// auditoría (`docs/auditoria-idiomas.md`, 2026-09-06), para que
    /// "experto en código opus" quite el `XCTSkip` al cerrar A7a.
    func testNoAccentedTextOrEneLiteralsOutsideStringLocalized_pendienteDeA7a() throws {
        throw XCTSkip("""
            Pendiente de A7a (extracción real sobre Sources/, ST-227). Forma: recorrer \
            Sources/AuraStudio y fallar si aparece Text("...")/Label("...") (u otro de \
            los patrones de tools/extraer-cadenas.py: Button/.help/.navigationTitle/Menu/ \
            CommandMenu/.alert/Alert/Toggle/Picker/Section/String(format:)) con una letra \
            acentuada o "ñ" en el literal, sin pasar por String(localized:)/ \
            LocalizedStringKey con clave real. Línea base de HOY (docs/auditoria-idiomas.md, \
            2026-09-06): 484 sitios como mínimo (225 Text + 169 Button + 43 Label + 31 \
            .help + 7 .navigationTitle + 7 Menu + 2 .alert) en unos 45-50 archivos, \
            concentrados en MediaSectionView/DeviceGeneralView/SimilarItemsView/ \
            ArtistsView/ServicesSettingsView/BatchMediaInfoView. Quitar este XCTSkip \
            cuando el conteo real deba ser 0 -- esa es la señal de que A7a cerró.
            """)
    }
}
