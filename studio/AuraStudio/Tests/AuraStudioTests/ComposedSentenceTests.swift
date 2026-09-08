import XCTest
@testable import AuraStudio

/// ST-227 (A7c, addendum 3): **las frases que se arman de pedazos**.
///
/// Windows encontró el defecto de su lado y acá era idéntico: un resumen
/// se componía de ocho fragmentos y solo el que llevaba plural venía del
/// catálogo. Con la app en alemán el usuario leía *"Biblioteca migrada:
/// die Tags von 3 Titeln wurden geschrieben, se ordenaron 2
/// preparados."* Sin error, ilegible, y **ninguna prueba de cadenas
/// sueltas podía verlo**: cada fragmento por separado estaba bien
/// traducido. El defecto solo existe en la unión.
///
/// Así que estas pruebas **arman la oración entera** en un idioma que no
/// es el español y fallan si aparece un resto de español. Se comprueba
/// palabra por palabra contra el español real del catálogo, no contra
/// una lista escrita a mano: si mañana alguien cambia el texto fuente,
/// la prueba sigue midiendo lo mismo.
@MainActor
final class ComposedSentenceTests: XCTestCase {
    private var english: Bundle!

    override func setUpWithError() throws {
        english = try XCTUnwrap(
            Bundle(path: try XCTUnwrap(AuraBundle.strings.path(forResource: "en", ofType: "lproj"))),
            "falta en.lproj -- ¿corriste tools/compilar-catalogo.py?")
    }

    override func tearDown() {
        AuraBundle.overrideForTests = nil
        super.tearDown()
    }

    /// Arma `body` con la tabla de un idioma.
    private func composed(in bundle: Bundle, _ body: () -> String) -> String {
        AuraBundle.overrideForTests = bundle
        defer { AuraBundle.overrideForTests = nil }
        return body()
    }

    // MARK: - Las palabras que delatan al español

    /// Las palabras de más de tres letras que aparecen en el español del
    /// catálogo y **no** aparecen en su inglés. Si una de ésas asoma en
    /// una frase compuesta en inglés, es un fragmento que se quedó
    /// escrito en el código.
    private lazy var spanishOnlyWords: Set<String> = {
        let url = AuraBundle.strings.url(forResource: "Localizable", withExtension: "xcstrings")!
        let object = try! JSONSerialization.jsonObject(with: try! Data(contentsOf: url))
        let strings = (object as! [String: Any])["strings"] as! [String: Any]

        func values(_ entry: Any, _ language: String) -> [String] {
            guard let localization = ((entry as? [String: Any])?["localizations"] as? [String: Any])?[language]
                    as? [String: Any] else { return [] }
            if let unit = localization["stringUnit"] as? [String: Any],
               let value = unit["value"] as? String { return [value] }
            guard let plural = (localization["variations"] as? [String: Any])?["plural"] as? [String: Any]
            else { return [] }
            return plural.values.compactMap { (($0 as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String }
        }
        func words(_ texts: [String]) -> Set<String> {
            Set(texts.flatMap { $0.lowercased().split(whereSeparator: { !$0.isLetter }) }
                .map(String.init).filter { $0.count > 3 })
        }
        var spanish: Set<String> = [], english: Set<String> = []
        for (_, entry) in strings {
            spanish.formUnion(words(values(entry, "es")))
            english.formUnion(words(values(entry, "en")))
        }
        return spanish.subtracting(english)
    }()

    private func assertNoSpanish(_ sentence: String, _ label: String,
                                 file: StaticString = #filePath, line: UInt = #line) {
        let found = sentence.lowercased().split(whereSeparator: { !$0.isLetter })
            .map(String.init).filter { spanishOnlyWords.contains($0) }
        XCTAssertTrue(found.isEmpty,
                      "«\(label)» compuesta en inglés trae español: \(Set(found).sorted()) -- «\(sentence)»",
                      file: file, line: line)
    }

    // MARK: - Las frases

    func testTheMigrationNoticeIsFullyTranslated() {
        for need in [LibraryMigrationNeed(itemsWithoutStorage: 1, legacyPrepared: 0),
                     LibraryMigrationNeed(itemsWithoutStorage: 0, legacyPrepared: 7),
                     LibraryMigrationNeed(itemsWithoutStorage: 3, legacyPrepared: 2)] {
            let sentence = composed(in: english) { need.message }
            assertNoSpanish(sentence, "aviso de migración \(need.itemsWithoutStorage)/\(need.legacyPrepared)")
            XCTAssertFalse(sentence.isEmpty)
        }
    }

    func testTheMigrationSummaryIsFullyTranslated() {
        let cases: [LibraryMigrationSummary] = [
            LibraryMigrationSummary(tagged: 3, preparedRenamed: 2),
            LibraryMigrationSummary(tagged: 1, preparedRenamed: 1, preparedBuilt: 1, orphansDeleted: 1),
            LibraryMigrationSummary(errors: ["a.mp3"]),
            LibraryMigrationSummary(tagged: 2, errors: ["a.mp3", "b.flac"], cancelled: true),
            LibraryMigrationSummary(),
        ]
        for summary in cases {
            assertNoSpanish(composed(in: english) { summary.message }, "resumen de migración")
        }
    }

    func testTheImportNoticeIsFullyTranslated() {
        for notice in [LibraryViewModel.ImportNotice(duplicatesSkipped: 1, similarGroups: 0),
                       LibraryViewModel.ImportNotice(duplicatesSkipped: 0, similarGroups: 4),
                       LibraryViewModel.ImportNotice(duplicatesSkipped: 5, similarGroups: 2)] {
            assertNoSpanish(composed(in: english) { notice.message }, "aviso de importación")
        }
    }

    func testTheDeletionConfirmationIsFullyTranslated() {
        for pending in [LibraryViewModel.PendingDeletion(ids: [UUID()], itemCount: 1,
                                                         filesToTrash: 2, bytesToTrash: 4_000_000),
                        LibraryViewModel.PendingDeletion(ids: [UUID()], itemCount: 1,
                                                         filesToTrash: 0, bytesToTrash: 0),
                        LibraryViewModel.PendingDeletion(ids: [UUID(), UUID()], itemCount: 2,
                                                         filesToTrash: 0, bytesToTrash: 0)] {
            assertNoSpanish(composed(in: english) { pending.message }, "confirmación de eliminar")
            assertNoSpanish(composed(in: english) { pending.title }, "título de eliminar")
        }
    }

    func testTheSimilarityConfidenceCountsAreFullyTranslated() {
        for level in SimilarityConfidence.allCases {
            for n in [1, 2, 5] {
                assertNoSpanish(composed(in: english) { level.countText(n) }, "conteo de \(level)")
            }
            assertNoSpanish(composed(in: english) { level.title }, "título de \(level)")
            assertNoSpanish(composed(in: english) { level.detail }, "detalle de \(level)")
        }
    }

    /// El separador y el punto final también son texto: si alguien los
    /// vuelve a escribir en el código, esto no lo ve -- pero sí ve que
    /// el japonés no pueda cambiarlos, que es la consecuencia.
    func testSeparatorsComeFromTheCatalogAndChangeWithTheLanguage() throws {
        let japanese = try XCTUnwrap(
            Bundle(path: try XCTUnwrap(AuraBundle.strings.path(forResource: "ja", ofType: "lproj"))))
        let spanishList = composed(in: english) { Sentence.list(["a", "b"]) }
        let japaneseList = composed(in: japanese) { Sentence.list(["a", "b"]) }
        XCTAssertNotEqual(spanishList, japaneseList,
                          "el separador no cambia con el idioma -- ¿volvió a estar escrito en el código?")
        XCTAssertEqual(composed(in: japanese) { Sentence.ended("あ") }, "あ。",
                       "el punto final del japonés es «。», no «.»")
    }

    /// `Sentence.ended` no encadena signos: una frase que ya cierra no
    /// recibe otro punto. Sale barato y evita "…." en las tres frases
    /// que terminan en puntos suspensivos.
    func testEndedDoesNotStackClosingMarks() {
        XCTAssertEqual(Sentence.ended("Listo."), "Listo.")
        XCTAssertEqual(Sentence.ended("Buscando…"), "Buscando…")
        XCTAssertEqual(Sentence.ended("¿Seguro?"), "¿Seguro?")
        XCTAssertEqual(Sentence.ended(""), "")
        XCTAssertEqual(Sentence.ended("Listo"), "Listo" + LS("sentence.period"))
    }

    /// La red de seguridad de la propia prueba: si el vocabulario
    /// "solo español" quedara vacío, `assertNoSpanish` pasaría siempre y
    /// estas seis pruebas dejarían de comprobar nada sin decirlo.
    func testTheSpanishVocabularyIsNotEmpty() {
        XCTAssertGreaterThan(spanishOnlyWords.count, 200,
                             "el vocabulario que delata al español quedó casi vacío: las demás pruebas de este archivo no medirían nada")
        XCTAssertTrue(spanishOnlyWords.contains("biblioteca"))
        XCTAssertTrue(spanishOnlyWords.contains("elementos"))
    }

    // MARK: - Dos oraciones seguidas

    /// `Sentence.sentences(_:)` (ST-227, A7d): el espacio entre dos
    /// oraciones **también es tipografía del idioma**. Donde el
    /// instalador dice "no se pudo descargar. Se instalará la versión
    /// incluida", el español pega las dos con un espacio y el japonés
    /// no pega nada, porque el `。` ya cerró la primera.
    ///
    /// La prueba se hace contra el catálogo, no contra literales: si
    /// mañana alguien le pone un espacio al japonés, falla acá y no en
    /// una captura de pantalla.
    func testTwoSentencesJoinWithTheTypographyOfEachLanguage() throws {
        for (idioma, esperado) in [("es", " "), ("en", " "), ("de", " "),
                                   ("fr", " "), ("ru", " "), ("ja", "")] {
            let bundle = try XCTUnwrap(
                Bundle(path: try XCTUnwrap(AuraBundle.strings.path(forResource: idioma, ofType: "lproj"))))
            let unidas = composed(in: bundle) { Sentence.sentences(["A.", "B."]) }
            XCTAssertEqual(unidas, "A." + esperado + "B.",
                           "el separador entre oraciones de \(idioma) no es el del catálogo")
        }
    }

    /// Y no apila cierres: una primera frase que ya venía con punto no
    /// recibe otro. Es la misma regla de `ended(_:)`, comprobada donde
    /// de verdad se usa -- el aviso de respaldo del instalador arma
    /// `errorDescription` (que trae punto) con la frase siguiente.
    func testJoiningSentencesNeverStacksTwoPeriods() {
        let unidas = composed(in: english) {
            Sentence.sentences(["The download failed.", "The bundled version will be installed."])
        }
        XCTAssertFalse(unidas.contains(".."), unidas)
        XCTAssertEqual(unidas, "The download failed. The bundled version will be installed.")
    }
}
