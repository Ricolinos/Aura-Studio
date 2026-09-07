import XCTest
@testable import AuraStudio

/// ST-227 (A7b): el inglés existe de verdad y el selector de idioma no
/// toca nada que no deba.
@MainActor
final class LocalizationEnglishTests: XCTestCase {
    private func catalogStrings() throws -> [String: Any] {
        let url = try XCTUnwrap(AuraBundle.strings.url(forResource: "Localizable", withExtension: "xcstrings"))
        let object = try JSONSerialization.jsonObject(with: try Data(contentsOf: url))
        return try XCTUnwrap((object as? [String: Any])?["strings"] as? [String: Any])
    }

    /// Ninguna clave puede quedarse sin inglés. Si falta, el sistema cae
    /// al español y la app queda mezclada -- y eso no falla en ningún
    /// lado, solo se ve raro.
    func testEveryKeyHasEnglish() throws {
        let strings = try catalogStrings()
        let missing = strings.filter { (_, value) in
            ((value as? [String: Any])?["localizations"] as? [String: Any])?["en"] == nil
        }.keys.sorted()

        XCTAssertTrue(missing.isEmpty, "claves sin inglés (\(missing.count)): \(missing.prefix(10))")
    }

    /// Los plurales también: `one` y `other` en inglés, o el idioma se
    /// queda a medias justo en las frases con números.
    func testEveryPluralHasBothEnglishForms() throws {
        var incomplete: [String] = []
        for (key, value) in try catalogStrings() {
            guard let localizations = (value as? [String: Any])?["localizations"] as? [String: Any] else { continue }
            guard let spanish = localizations["es"] as? [String: Any], spanish["variations"] != nil else { continue }
            let english = localizations["en"] as? [String: Any]
            let plural = ((english?["variations"] as? [String: Any])?["plural"] as? [String: Any])
            if plural?["one"] == nil || plural?["other"] == nil { incomplete.append(key) }
        }
        XCTAssertTrue(incomplete.isEmpty, "plurales sin las dos formas en inglés: \(incomplete.sorted())")
    }

    /// **La prueba que de verdad importa**: con el idioma en inglés, una
    /// muestra de claves devuelve el inglés -- ni la clave ni el
    /// español.
    /// Se resuelve contra el bundle de `en.lproj` explícitamente, y no
    /// pasando un `Locale`: el `locale:` de `String(localized:)` decide
    /// **el formato** (números, fechas), no de qué tabla de idioma sale
    /// el texto. La tabla la elige el sistema al arrancar, con
    /// `AppleLanguages`, y eso no se puede cambiar a mitad de proceso --
    /// por eso cambiar de idioma en Ajustes pide reiniciar.
    ///
    /// Lo probé al revés primero y devolvía el español: el error era de
    /// la prueba, no del catálogo, y vale dejarlo dicho para que nadie
    /// "arregle" el catálogo por esto.
    func testWithEnglishSelectedTheStringsComeBackInEnglish() throws {
        let englishBundle = try XCTUnwrap(
            AuraBundle.strings.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:)),
            "no hay tabla en inglés en el bundle")
        let cases: [(String, String, String)] = [
            ("settings.language", "Idioma", "Language"),
            ("albums-view.albumes", "Álbumes", "Albums"),
            ("media-section-view.importar", "Importar", "Import"),
            ("storage-section-title", "Cómo guardar tu música", "How to store your music"),
            ("settings-page.migrar-biblioteca", "Migrar biblioteca", "Migrate library"),
        ]
        for (key, spanish, expected) in cases {
            let value = String(localized: String.LocalizationValue(key), bundle: englishBundle)
            XCTAssertEqual(value, expected, key)
            XCTAssertNotEqual(value, spanish, "\(key): sigue devolviendo el español")
            XCTAssertNotEqual(value, key, "\(key): devuelve la clave, no hay traducción")
        }
    }

    // MARK: - La preferencia de idioma

    /// "Seguir al sistema" **borra** la clave en vez de escribir el
    /// idioma que hoy usa el sistema: dejarlo escrito congelaría esa
    /// elección y la app dejaría de seguir al Mac cuando el usuario lo
    /// cambie.
    ///
    /// La prueba corre sobre una suite propia y la borra al terminar
    /// (ST-194): nunca sobre el dominio real.
    func testFollowingTheSystemRemovesTheKeyInsteadOfFreezingToday() throws {
        let suite = "AuraLanguageTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        AppLanguageApplier.apply(.english, to: defaults)
        XCTAssertEqual(defaults.stringArray(forKey: AppLanguageApplier.appleLanguagesKey), ["en"])

        AppLanguageApplier.apply(.system, to: defaults)

        // Se mira el DOMINIO, no `object(forKey:)`. `AppleLanguages`
        // vive también en el dominio global, así que una lectura normal
        // cae ahí y devuelve el idioma del sistema aunque la app no
        // tenga nada escrito -- y eso, lejos de ser un problema, **es**
        // el mecanismo: borrar la clave de la app hace que la búsqueda
        // caiga al sistema, que es justo lo que "seguir al sistema"
        // significa. Lo que hay que comprobar es que la app no dejó
        // nada escrito.
        let domain = UserDefaults.standard.persistentDomain(forName: suite) ?? [:]
        XCTAssertNil(domain[AppLanguageApplier.appleLanguagesKey],
                     "«seguir al sistema» tiene que BORRAR la clave de la app, no escribir el idioma de hoy")
    }

    func testEveryLanguageWritesItsOwnCode() throws {
        let suite = "AuraLanguageTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        for language in AppLanguage.allCases where language != .system {
            AppLanguageApplier.apply(language, to: defaults)
            XCTAssertEqual(defaults.stringArray(forKey: AppLanguageApplier.appleLanguagesKey),
                           [language.rawValue], "\(language)")
        }
    }

    /// Cada idioma se ofrece **en su propio idioma**: alguien que abrió
    /// la app en un idioma que no entiende tiene que poder encontrar el
    /// suyo en la lista.
    func testEachLanguageIsOfferedInItsOwnLanguage() {
        XCTAssertEqual(AppLanguage.spanish.nativeName, "Español")
        XCTAssertEqual(AppLanguage.english.nativeName, "English")
        // ST-227 (A7c addendum): los cuatro traducidos a máquina llevan
        // "(beta)" en el nombre. El nombre del idioma sigue escrito en
        // su propio idioma; la marca es lo único que se le suma.
        XCTAssertEqual(AppLanguage.japanese.nativeName, "日本語 (beta)")
        XCTAssertEqual(AppLanguage.german.nativeName, "Deutsch (beta)")
        XCTAssertEqual(AppLanguage.russian.nativeName, "Русский (beta)")
        XCTAssertEqual(AppLanguage.french.nativeName, "Français (beta)")
    }

    /// La marca y la advertencia van juntas: un idioma marcado sin la
    /// línea que explica por qué, o al revés, deja al usuario adivinando.
    /// Y el español y el inglés NO se marcan -- se escribieron y se
    /// revisaron acá.
    func testOnlyTheMachineTranslatedLanguagesAreMarked() {
        for language in AppLanguage.allCases {
            let marked = language.nativeName.contains("(beta)")
            XCTAssertEqual(marked, language.isMachineTranslated, "\(language)")
        }
        XCTAssertFalse(AppLanguage.spanish.isMachineTranslated)
        XCTAssertFalse(AppLanguage.english.isMachineTranslated)
        XCTAssertFalse(AppLanguage.system.isMachineTranslated)
        XCTAssertFalse(LS("settings.language-machine-translated").isEmpty)
        XCTAssertNotEqual(LS("settings.language-machine-translated"),
                          "settings.language-machine-translated",
                          "la advertencia no está en el catálogo")
    }

    /// ST-227: lo que se GUARDA como categoría es el español, siempre --
    /// aunque la app esté en otro idioma. Es un dato del catálogo, no un
    /// texto de pantalla, y una categoría guardada como "Filme" no
    /// coincidiría con nada.
    func testTheStoredCategoryNameIsAlwaysSpanish() {
        XCTAssertEqual(MediaCategory.movies.displayName, "Películas")
        XCTAssertEqual(MediaCategory.series.displayName, "Series")
        XCTAssertEqual(MediaCategory.videos.displayName, "Videos")
    }
}
