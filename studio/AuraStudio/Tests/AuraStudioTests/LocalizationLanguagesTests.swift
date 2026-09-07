import XCTest
@testable import AuraStudio

/// ST-227 (A7c): los seis idiomas están completos y dicen lo mismo.
///
/// Ninguna de estas fallas se manifiesta como un error: una clave sin
/// japonés cae al español y la app se ve mezclada; un `%@` de más en una
/// traducción imprime basura o se lleva la app por delante; un `.lproj`
/// generado que quedó viejo devuelve el texto de ayer sin avisar. Todo
/// eso solo se atrapa mirándolo desde una prueba.
@MainActor
final class LocalizationLanguagesTests: XCTestCase {
    /// El orden es el de `AppLanguage`: español primero porque es el
    /// idioma FUENTE, el resto detrás.
    private static let languages = ["es", "en", "ja", "de", "ru", "fr"]

    private func catalogStrings() throws -> [String: Any] {
        let url = try XCTUnwrap(AuraBundle.strings.url(forResource: "Localizable", withExtension: "xcstrings"))
        let object = try JSONSerialization.jsonObject(with: try Data(contentsOf: url))
        return try XCTUnwrap((object as? [String: Any])?["strings"] as? [String: Any])
    }

    private func localizations(_ entry: Any) -> [String: Any] {
        ((entry as? [String: Any])?["localizations"] as? [String: Any]) ?? [:]
    }

    /// El texto simple de una localización, o `nil` si es un plural.
    private func simpleValue(_ localization: Any?) -> String? {
        ((localization as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String
    }

    /// Las formas de plural de una localización, vacío si no es plural.
    private func pluralForms(_ localization: Any?) -> [String: String] {
        guard let plural = ((localization as? [String: Any])?["variations"] as? [String: Any])?["plural"]
                as? [String: Any] else { return [:] }
        return plural.compactMapValues { ($0 as? [String: Any])?["stringUnit"] as? [String: Any] }
            .compactMapValues { $0["value"] as? String }
    }

    // MARK: - Cobertura

    func testEveryKeyHasAllSixLanguages() throws {
        var incomplete: [String] = []
        for (key, entry) in try catalogStrings() {
            let present = localizations(entry).keys
            let missing = Self.languages.filter { !present.contains($0) }
            if !missing.isEmpty { incomplete.append("\(key): falta \(missing.joined(separator: ", "))") }
        }
        XCTAssertTrue(incomplete.isEmpty,
                      "claves incompletas (\(incomplete.count)):\n" + incomplete.sorted().prefix(15).joined(separator: "\n"))
    }

    /// Ninguna traducción puede quedar vacía: una cadena vacía no cae al
    /// español -- se muestra como nada, y el usuario ve un botón en
    /// blanco.
    func testNoTranslationIsEmpty() throws {
        var empties: [String] = []
        for (key, entry) in try catalogStrings() {
            for language in Self.languages {
                let localization = localizations(entry)[language]
                if let simple = simpleValue(localization) {
                    if simple.isEmpty { empties.append("\(key) [\(language)]") }
                } else {
                    for (form, text) in pluralForms(localization) where text.isEmpty {
                        empties.append("\(key) [\(language).\(form)]")
                    }
                }
            }
        }
        XCTAssertTrue(empties.isEmpty, "traducciones vacías: \(empties.sorted().prefix(15))")
    }

    // MARK: - Los plurales, con las formas que exige cada idioma

    /// Cada idioma tiene sus propias categorías de plural (CLDR), y no
    /// son opinables:
    ///
    /// - **ru**: `one` (1, 21, 31…), `few` (2-4, 22-24…), `many` (0,
    ///   5-20…) y `other` (fraccionarios). Faltando `many`, "5 треков"
    ///   sale con la forma de "2" y suena mal en la mitad de los
    ///   números.
    /// - **de**, **fr**: `one` y `other`. En francés `one` cubre además
    ///   el 0 -- por eso sus formas `one` llevan el número adentro en
    ///   vez de un "1" escrito a mano.
    /// - **ja**: solo `other`. El japonés no marca número en el
    ///   sustantivo; declarar un `one` sería inventar una distinción que
    ///   el idioma no hace.
    func testPluralsHaveTheFormsEachLanguageRequires() throws {
        let required: [String: Set<String>] = [
            "es": ["one", "other"], "en": ["one", "other"],
            "de": ["one", "other"], "fr": ["one", "other"],
            "ru": ["one", "few", "many", "other"],
            "ja": ["other"],
        ]
        var problems: [String] = []
        for (key, entry) in try catalogStrings() {
            let spanish = localizations(entry)["es"]
            guard !pluralForms(spanish).isEmpty else { continue } // no es un plural
            for language in Self.languages {
                let forms = Set(pluralForms(localizations(entry)[language]).keys)
                let missing = required[language]!.subtracting(forms)
                if !missing.isEmpty { problems.append("\(key) [\(language)]: falta \(missing.sorted())") }
                // El japonés con un `one` no es "de más": es una forma
                // que el sistema NUNCA va a elegir, así que quien la
                // edite creerá que cambió algo y no cambiará nada.
                let extra = forms.subtracting(required[language]!)
                if !extra.isEmpty { problems.append("\(key) [\(language)]: sobra \(extra.sorted()) -- el sistema no la usa nunca") }
            }
        }
        XCTAssertTrue(problems.isEmpty, "plurales incompletos:\n" + problems.sorted().joined(separator: "\n"))
    }

    // MARK: - Marcadores y posicionales intactos

    /// Los especificadores de una traducción tienen que ser los mismos
    /// que los del español, en tipo y en cantidad. Uno de más lee un
    /// argumento que no existe -- basura en pantalla en el mejor caso, y
    /// la app caída en el peor.
    ///
    /// **La excepción, dicha en vez de escondida:** en un plural, una
    /// forma `one` puede llevar el número aunque el español la escriba
    /// con un "1" literal. En español `one` es exactamente el 1 y
    /// escribirlo es correcto; en ruso `one` cubre 21, 31, 41… y en
    /// francés cubre también el 0, así que ahí el número TIENE que
    /// salir del argumento. Por eso se admite que una forma coincida con
    /// los especificadores de la suya **o** con los de `other`.
    func testFormatSpecifiersSurviveEveryTranslation() throws {
        func specifiers(_ text: String) -> [String] {
            let pattern = try! NSRegularExpression(pattern: #"%(?:\d+\$)?(?:@|lld|d|02d)"#)
            return pattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
                .map { String(text[Range($0.range, in: text)!]) }
                .sorted()
        }

        var mismatches: [String] = []
        for (key, entry) in try catalogStrings() {
            let spanish = localizations(entry)["es"]
            if let reference = simpleValue(spanish) {
                let expected = specifiers(reference)
                for language in Self.languages.dropFirst() {
                    guard let value = simpleValue(localizations(entry)[language]) else { continue }
                    if specifiers(value) != expected {
                        mismatches.append("\(key) [\(language)]: \(specifiers(value)) ≠ \(expected) del español")
                    }
                }
                continue
            }
            let spanishForms = pluralForms(spanish)
            guard !spanishForms.isEmpty else { continue }
            let fallback = specifiers(spanishForms["other"] ?? "")
            for language in Self.languages.dropFirst() {
                for (form, text) in pluralForms(localizations(entry)[language]) {
                    let found = specifiers(text)
                    let sameForm = spanishForms[form].map(specifiers)
                    if found != fallback && found != sameForm {
                        mismatches.append("\(key) [\(language).\(form)]: \(found) -- ni los de «\(form)» del español"
                                          + " (\(sameForm.map(String.init(describing:)) ?? "no existe")) ni los de «other» (\(fallback))")
                    }
                }
            }
        }
        XCTAssertTrue(mismatches.isEmpty,
                      "marcadores que no sobrevivieron la traducción:\n" + mismatches.sorted().joined(separator: "\n"))
    }

    // MARK: - Los `.lproj` generados dicen lo mismo que el catálogo

    /// `tools/compilar-catalogo.py` se corre **a mano**. Un catálogo
    /// editado y un `.lproj` sin regenerar no fallan en ningún lado: la
    /// app de SwiftPM sigue mostrando el texto viejo. Esta prueba es lo
    /// único que lo nota.
    ///
    /// De paso es la prueba de resolución de los seis idiomas: cada
    /// tabla se abre explícitamente (`<idioma>.lproj`) porque el
    /// `locale:` de `String(localized:)` decide el FORMATO, no la tabla
    /// -- ver `LocalizationEnglishTests`, donde ese error ya costó una
    /// vuelta.
    func testEachLanguageTableMatchesTheCatalogAndNeverFallsBack() throws {
        let strings = try catalogStrings()
        for language in Self.languages {
            let bundle = try XCTUnwrap(
                AuraBundle.strings.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)),
                "falta \(language).lproj -- ¿corriste tools/compilar-catalogo.py?")

            var wrong: [String] = []
            var checked = 0
            for (key, entry) in strings {
                guard let expected = simpleValue(localizations(entry)[language]) else { continue }
                let resolved = String(localized: String.LocalizationValue(key), bundle: bundle)
                checked += 1
                if resolved != expected { wrong.append("\(key): «\(resolved)» ≠ «\(expected)»") }
            }
            XCTAssertGreaterThan(checked, 400, "\(language): se comprobaron muy pocas claves")
            XCTAssertTrue(wrong.isEmpty,
                          "\(language).lproj no coincide con el catálogo (\(wrong.count)):\n"
                            + wrong.sorted().prefix(10).joined(separator: "\n"))
        }
    }

    /// Con un idioma elegido, una muestra devuelve **ese** idioma: ni la
    /// clave ni el español. Es la comprobación de cara al usuario, con
    /// textos escritos a mano acá para que un cambio del catálogo tenga
    /// que pasar por alguien que lea las dos cosas.
    func testASampleResolvesInEachLanguageWithoutFallingBackToSpanish() throws {
        let sample: [String: [String: String]] = [
            "settings.language": ["ja": "言語", "de": "Sprache", "ru": "Язык", "fr": "Langue"],
            "settings.music": ["ja": "ミュージック", "de": "Musik", "ru": "Музыка", "fr": "Musique"],
            "media-section-view.importar": ["ja": "読み込む", "de": "Importieren", "ru": "Импортировать", "fr": "Importer"],
            "storage-section-title": ["ja": "音楽の保存方法", "de": "Wie deine Musik gespeichert wird",
                                      "ru": "Как хранить вашу музыку", "fr": "Comment stocker votre musique"],
        ]
        for (language, _) in sample.first!.value {
            let bundle = try XCTUnwrap(
                AuraBundle.strings.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)))
            for (key, expectations) in sample {
                let value = String(localized: String.LocalizationValue(key), bundle: bundle)
                XCTAssertEqual(value, expectations[language], "\(key) [\(language)]")
                XCTAssertNotEqual(value, key, "\(key) [\(language)]: devuelve la clave")
            }
        }
    }

    /// El idioma fuente no se toca: si el español cambiara al traducir,
    /// la traducción habría reescrito el original en vez de acompañarlo.
    func testTranslatingDidNotChangeAnySpanishText() throws {
        let strings = try catalogStrings()
        let spanish = try XCTUnwrap(
            AuraBundle.strings.path(forResource: "es", ofType: "lproj").flatMap(Bundle.init(path:)))
        for (key, entry) in strings {
            guard let expected = simpleValue(localizations(entry)["es"]) else { continue }
            XCTAssertEqual(String(localized: String.LocalizationValue(key), bundle: spanish), expected, key)
        }
    }
}
