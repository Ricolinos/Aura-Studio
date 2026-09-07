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
    /// mismo barrido): 24 filas hoy (subió de 23 el 2026-09-06 a 24 el
    /// 2026-09-07 -- A1..A5 agregaron código real entre las dos
    /// corridas, con al menos un ternario de plural nuevo,
    /// `LibraryViewModel.swift:594`, "1 falló"/"fallaron"; no es un
    /// bug de esta ronda, es Sources/ moviéndose). No los resuelve esta prueba (eso
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
        // `csv.writer` de Python escribe terminadores `\r\n` por
        // omisión (dialecto `excel`, RFC 4180) -- partir por `"\n"` a
        // secas no encuentra NADA que partir, porque Swift trata
        // `\r\n` como un solo `Character` (un grafema, según UAX #29),
        // nunca como un `\n` suelto. `.isNewline` sí reconoce las dos
        // formas.
        let lines = text.split(whereSeparator: \.isNewline).dropFirst() // sin encabezado

        var rows: [(singular: String, plural: String)] = []
        for line in lines {
            let fields = line.split(separator: ",", maxSplits: 3, omittingEmptySubsequences: false)
            guard fields.count == 4 else { continue }
            rows.append((singular: String(fields[2]), plural: String(fields[3])))
        }

        // 24 es el conteo real de hoy (2026-09-07; era 23 el
        // 2026-09-06, ver docs/auditoria-idiomas.md) -- si vuelve a
        // correr el extractor tras cambios en Sources/, este número
        // puede moverse; si esta aserción falla por eso, actualizar el
        // número, no borrar la prueba.
        XCTAssertEqual(rows.count, 24, "el número de plurales por ternario cambió -- confirmar si es real o un bug del extractor")

        for row in rows {
            XCTAssertFalse(row.singular.isEmpty && row.plural.isEmpty, "singular y plural vacíos a la vez -- fila sin contenido real")
            XCTAssertNotEqual(row.singular, row.plural,
                              "singular y plural idénticos (\"\(row.singular)\") -- no es una variación real, probable falso positivo del ternario")
        }
    }

    // MARK: - Ninguna clave cortada a mitad de oración (ST-247 addendum)

    /// Windows encontró el defecto más serio de su extractor hasta
    /// ahora: una frase concatenada con `+` entre líneas se partía en
    /// un fragmento por literal (41 frases, 56 claves de más,
    /// intraducibles). Acá el patrón es más chico -- 4 sitios reales
    /// en Swift, no 41 -- pero el defecto era el mismo en espíritu, y
    /// uno de los cuatro tenía una variante peor: una interpolación
    /// con un ternario ANIDADO (`\(x == 1 ? "a" : "\(x) b")`) hacía
    /// que el regex de captura del literal terminara en la primera
    /// comilla del ternario interno, dejando la clave cortada a mitad
    /// de frase y terminada en un espacio suelto -- ni siquiera hacía
    /// falta un `+` para que pasara.
    ///
    /// Heurística de "cortada a mitad de oración" (la misma que pidió
    /// "Sesión Maestra", igual a la que usó Windows): termina en
    /// espacio, en coma, o en una conjunción/artículo suelto ("y",
    /// "o", "de", "la", "el") sin nada después.
    func testNoKeyEndsMidSentence() throws {
        let json = try loadDraftJSON()
        let strings = try XCTUnwrap(json["strings"] as? [String: Any])
        let danglingWords: Set<String> = ["y", "o", "de", "la", "el"]

        func lastWord(_ text: String) -> String? {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: ".?!"))
            return trimmed.split(separator: " ").last.map { $0.lowercased() }
        }

        var offenders: [String] = []
        for (key, entry) in strings {
            guard let entryDict = entry as? [String: Any],
                  let localizations = entryDict["localizations"] as? [String: Any],
                  let es = localizations["es"] as? [String: Any],
                  let stringUnit = es["stringUnit"] as? [String: Any],
                  let value = stringUnit["value"] as? String, !value.isEmpty else { continue }

            if value.hasSuffix(" ") {
                offenders.append("\(key): termina en espacio (\"\(value)\")")
            } else if value.trimmingCharacters(in: .whitespaces).hasSuffix(",") {
                offenders.append("\(key): termina en coma (\"\(value)\")")
            } else if let last = lastWord(value), danglingWords.contains(last) {
                offenders.append("\(key): termina en \"\(last)\" suelto (\"\(value)\")")
            }
        }
        XCTAssertTrue(offenders.isEmpty, "claves cortadas a mitad de oración: \(offenders)")
    }

    /// `docs/extraccion-cadenas/fragmentos-unidos.csv` (ST-247
    /// addendum): confirma el número EXACTO de frases que la
    /// herramienta unió porque venían concatenadas con `+` -- mismo
    /// espíritu que los "41" de Windows, para que un cambio en
    /// `Sources/` que agregue o quite una concatenación se note acá
    /// (el número se mueve) en vez de perderse en silencio.
    ///
    /// 3 unidas hoy: `LibraryUnavailableView.swift:40`,
    /// `MusicSettingsView.swift:84`, `SettingsSectionView.swift:258`.
    /// 1 detectada pero SIN unir con confianza
    /// (`ExtrasView.swift:173`): una interpolación con un ternario
    /// anidado adentro de la rama no vacía hace que ni siquiera el
    /// escaneo con profundidad de paréntesis (`scan_swift_string_literal`)
    /// pueda separar el fragmento con seguridad -- queda marcada
    /// "revisar a mano", no se inventa un texto unido a la fuerza.
    func testJoinedConcatenationCountMatchesToday() throws {
        let url = try repoRoot().appendingPathComponent("docs/extraccion-cadenas/fragmentos-unidos.csv")
        let text = try String(contentsOf: url, encoding: .utf8)
        // `.isNewline`, no `"\n"` -- ver el comentario de
        // `testPluralCSVRowsHaveTwoDistinctForms` (mismo `csv.writer`,
        // mismo `\r\n`).
        let rows = text.split(whereSeparator: \.isNewline).dropFirst()

        var joined = 0
        var needsReview = 0
        for row in rows {
            let fields = row.split(separator: ",", maxSplits: 3, omittingEmptySubsequences: false)
            guard fields.count == 4 else { continue }
            switch fields[2] {
            case "unido": joined += 1
            case "\"revisar a mano\"", "revisar a mano": needsReview += 1
            default: break
            }
        }

        XCTAssertEqual(joined, 3, "el número de frases unidas por concatenación cambió -- confirmar si es real (Sources/ cambió) o un bug del extractor")
        XCTAssertEqual(needsReview, 1, "el número de concatenaciones sin unir con confianza cambió -- revisar docs/extraccion-cadenas/fragmentos-unidos.csv")
    }

    // MARK: - Detector de literales (el que sí espera a A7a)

    /// El criterio de cierre real de A7a (§3 del plan): CERO
    /// `Text("...")`/`Label("...")` con una letra acentuada o "ñ" que no
    /// pase por `String(localized:)`/una clave real. Hoy falla por
    /// cientos -- se deja documentado con `XCTSkip`, línea base de la
    /// auditoría (`docs/auditoria-idiomas.md`, 2026-09-06), para que
    /// "experto en código opus" quite el `XCTSkip` al cerrar A7a.
    /// El criterio de cierre de A7a: **cero** literales de interfaz con
    /// acento o "ñ" fuera del catálogo. La línea base era 484 sitios.
    ///
    /// Se mira el acento a propósito: es la señal barata y sin falsos
    /// positivos de que un literal es texto **para el usuario** y no un
    /// identificador, una clave o un nombre de sistema.
    func testNoAccentedInterfaceLiteralsRemainOutsideTheCatalog() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/AuraStudio")
        let constructors = ["Text", "Button", "Label", "Menu", "CommandMenu", "Toggle",
                            "Picker", "Section", "Alert"]
        let modifiers = [".help", ".navigationTitle", ".alert"]
        let accented = CharacterSet(charactersIn: "áéíóúÁÉÍÓÚñÑ¿¡üÜ")

        var offenders: [String] = []
        let walker = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
        while let url = walker?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            // El catálogo mismo y el puente de bundles no son interfaz.
            guard url.lastPathComponent != "AppStrings.swift" else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            for (number, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//") else { continue }
                let opensLiteral = constructors.contains { trimmed.contains("\($0)(\"") }
                    || modifiers.contains { trimmed.contains("\($0)(\"") }
                guard opensLiteral else { continue }
                guard line.rangeOfCharacter(from: accented) != nil else { continue }
                offenders.append("\(url.lastPathComponent):\(number + 1)  \(trimmed.prefix(90))")
            }
        }

        XCTAssertTrue(offenders.isEmpty,
                      "quedan \(offenders.count) literales de interfaz fuera del catálogo:\n"
                        + offenders.prefix(20).joined(separator: "\n"))
    }
}
