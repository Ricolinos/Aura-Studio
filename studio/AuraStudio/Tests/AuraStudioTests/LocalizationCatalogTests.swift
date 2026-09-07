import XCTest
@testable import AuraStudio

/// ST-227: el String Catalog y el código no pueden divergir en silencio.
///
/// Una clave que no está en el catálogo **no falla**: `String(localized:)`
/// devuelve la clave misma, así que la app muestra `media-section.eliminar`
/// en pantalla y sigue andando. Es exactamente la clase de defecto que hay
/// que cazar con una prueba y no con la vista.
@MainActor
final class LocalizationCatalogTests: XCTestCase {
    private func catalog() throws -> [String: Any] {
        let url = try XCTUnwrap(AuraBundle.strings.url(forResource: "Localizable", withExtension: "xcstrings"),
                                "el catálogo tiene que estar en el bundle -- si esto falla, el recurso no se está empaquetando")
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testTheCatalogIsInTheBundleAndItsSourceIsSpanish() throws {
        let catalog = try catalog()
        XCTAssertEqual(catalog["sourceLanguage"] as? String, "es",
                       "el idioma fuente es el español: el texto se escribe en español y de ahí se traduce")
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        XCTAssertGreaterThan(strings.count, 300, "el catálogo llegó vacío o a medias")
    }

    /// Lo que de verdad prueba que el puente entre los dos sistemas de
    /// compilación funciona: pedir una clave y recibir el texto, no la
    /// clave.
    func testLookingUpAKeyReturnsItsSpanishTextAndNotTheKey() throws {
        let strings = try XCTUnwrap(try catalog()["strings"] as? [String: Any])
        let key = try XCTUnwrap(strings.keys.sorted().first)
        let expected = try XCTUnwrap((((strings[key] as? [String: Any])?["localizations"] as? [String: Any])?["es"]
                                      as? [String: Any])?["stringUnit"] as? [String: Any])["value"] as? String

        let resolved = String(localized: String.LocalizationValue(key), bundle: AuraBundle.strings)

        XCTAssertEqual(resolved, expected)
        XCTAssertNotEqual(resolved, key, "si devuelve la clave, el catálogo no se está resolviendo")
    }

    // MARK: - El catálogo y el código no pueden divergir

    private var sourcesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/AuraStudio")
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    /// Todas las claves que el código pide, en el orden en que aparecen.
    private func keysUsedInCode() throws -> [(key: String, file: String)] {
        var used: [(String, String)] = []
        let pattern = try NSRegularExpression(pattern: #"\bLSf?\("([^"]+)"#)
        let walker = FileManager.default.enumerator(at: sourcesDirectory, includingPropertiesForKeys: nil)
        while let url = walker?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            let range = NSRange(text.startIndex..., in: text)
            for match in pattern.matches(in: text, range: range) {
                guard let keyRange = Range(match.range(at: 1), in: text) else { continue }
                used.append((String(text[keyRange]), url.lastPathComponent))
            }
        }
        return used
    }

    /// **La prueba que evita que la app muestre claves en pantalla.** Una
    /// clave que no está en el catálogo no falla: `String(localized:)`
    /// devuelve la clave, y el usuario ve `media-section.eliminar`.
    func testEveryKeyUsedInCodeExistsInTheCatalog() throws {
        let strings = try XCTUnwrap(try catalog()["strings"] as? [String: Any])
        let missing = try keysUsedInCode().filter { strings[$0.key] == nil }

        XCTAssertTrue(missing.isEmpty,
                      "claves pedidas por el código que no están en el catálogo:\n"
                        + missing.map { "\($0.file): \($0.key)" }.joined(separator: "\n"))
    }

    /// El español que ve el usuario **no cambió ni una letra**: lo que
    /// dice el catálogo es lo que decía el literal antes de moverlo.
    ///
    /// Se compara contra `revision.csv`, que es la foto de lo que había.
    /// Hay **una** excepción y está dicha acá con su motivo -- una
    /// excepción visible es revisable; una silenciosa no.
    func testTheSpanishInTheCatalogIsWhatTheSourcesSaidBefore() throws {
        let csv = repositoryRoot.appendingPathComponent("docs/extraccion-cadenas/revision.csv")
        let rows = try parseCSV(try String(contentsOf: csv, encoding: .utf8))
        let strings = try XCTUnwrap(try catalog()["strings"] as? [String: Any])

        // `music-settings-view.separadores-...`: el borrador de la
        // extracción se comió el trozo CALCULADO del medio (la lista de
        // separadores), así que su texto quedó sin `%@`. Dejarlo así
        // habría hecho desaparecer la lista de la pantalla -- que es
        // justo el cambio de español que esta prueba existe para evitar.
        let corrected = ["music-settings-view.separadores-que-agrupan-vs-versus-nunca"]

        var differences: [String] = []
        for row in rows {
            guard let key = row["clave_propuesta"], let expected = row["texto_con_marcadores"] else { continue }
            guard !corrected.contains(key) else { continue }
            guard let entry = strings[key] as? [String: Any] else { continue }
            guard let value = ((entry["localizations"] as? [String: Any])?["es"] as? [String: Any])
                    .flatMap({ $0["stringUnit"] as? [String: Any] })?["value"] as? String else { continue }
            if value != expected {
                differences.append("\(key)\n  antes: \(expected)\n  ahora: \(value)")
            }
        }
        XCTAssertTrue(differences.isEmpty,
                      "el español cambió en \(differences.count) claves:\n" + differences.prefix(10).joined(separator: "\n"))
    }

    /// Las claves compartidas con Windows tienen que existir de este lado
    /// -- o estar en la tabla `S`, que es lo que A7b va a mudar al
    /// catálogo. La lista de las que faltan se afirma explícitamente:
    /// cuando A7b vacíe `S`, esta prueba obliga a actualizarla, así que
    /// lo pendiente queda **visible** en vez de tapado.
    func testSharedKeysWithWindowsExistHereOrAreListedAsPendingForA7b() throws {
        let csv = repositoryRoot
            .appendingPathComponent("studio/windows/docs/extraccion-cadenas/claves-compartidas.csv")
        let rows = try parseCSV(try String(contentsOf: csv, encoding: .utf8))
        let strings = try XCTUnwrap(try catalog()["strings"] as? [String: Any])

        /// Textos compartidos que todavía viven en `AppStrings.S`, que
        /// carga la tabla ES/EN y el resolutor de idioma -- eso es A7b.
        let pendingInAppStrings: Set<String> = [
            "storage-section-title", "storage-copy-explainer", "storage-reference-explainer",
            "storage-change-only-affects-future", "orphans-title", "orphans-detail",
            "orphans-button", "orphans-clean-button", "orphans-none-found",
            "orphans-confirm-message",
            "settings-page.migrar-version-anterior", "settings-page.migrar-biblioteca",
        ]

        var missing: [String] = []
        for row in rows {
            guard let key = row["clave"], let state = row["estado"] else { continue }
            guard state == "igual" || state == "clave distinta" else { continue }
            guard strings[key] == nil, !pendingInAppStrings.contains(key) else { continue }
            missing.append(key)
        }
        XCTAssertTrue(missing.isEmpty,
                      "claves compartidas que no están ni en el catálogo ni en la lista de pendientes de A7b: \(missing)")
    }

    /// Un lector de CSV que aguanta comillas y saltos de línea dentro de
    /// un campo -- los textos largos del cotejo los tienen.
    private func parseCSV(_ text: String) throws -> [[String: String]] {
        var records: [[String]] = []
        var field = ""
        var record: [String] = []
        var inQuotes = false
        var iterator = text.makeIterator()
        var pending: Character?
        while let character = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if character == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") } else { inQuotes = false; pending = next }
                    } else { inQuotes = false }
                } else { field.append(character) }
                continue
            }
            switch character {
            case "\"": inQuotes = true
            case ",": record.append(field); field = ""
            case "\r": break
            case "\n": record.append(field); field = ""; records.append(record); record = []
            default: field.append(character)
            }
        }
        if !field.isEmpty || !record.isEmpty { record.append(field); records.append(record) }
        guard let header = records.first else { return [] }
        return records.dropFirst().filter { $0.count == header.count }.map { row in
            Dictionary(uniqueKeysWithValues: zip(header, row))
        }
    }
}
