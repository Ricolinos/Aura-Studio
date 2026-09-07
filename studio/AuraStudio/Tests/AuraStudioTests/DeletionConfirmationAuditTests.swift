import XCTest
@testable import AuraStudio

/// ST-225 (addendum): **ningún archivo de la biblioteca se borra fuera
/// del plan, y ninguna confirmación se dibuja donde nadie la ve.**
///
/// Windows encontró de su lado un "Conservar solo" que mandaba a la
/// Papelera sin confirmar. Acá el defecto era el simétrico y por eso no
/// se veía: la confirmación **sí** estaba (vive en el modelo, ST-225),
/// pero `SimilarItemsView` es una **hoja** presentada por `ContentView`,
/// y el diálogo colgaba del fondo de `ContentView` -- de quien la hoja
/// tapa. La hoja, además, escribía "Se eliminaron N elementos" ANTES de
/// que hubiera confirmación alguna, así que decía que había borrado
/// aunque el usuario cancelara.
///
/// Estas pruebas afirman las dos mitades: la del disco (una sola puerta
/// de salida) y la de la interfaz (quien elimina desde una hoja dibuja
/// su propia confirmación).
@MainActor
final class DeletionConfirmationAuditTests: XCTestCase {
    private var sourcesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/AuraStudio")
    }

    private func swiftFiles() throws -> [(name: String, path: String, text: String)] {
        var found: [(String, String, String)] = []
        let walker = FileManager.default.enumerator(at: sourcesDirectory, includingPropertiesForKeys: nil)
        while let url = walker?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            found.append((url.lastPathComponent, url.path, try String(contentsOf: url, encoding: .utf8)))
        }
        return found
    }

    /// Las líneas de código (sin comentarios) que contienen `needle`.
    private func codeLines(_ text: String, containing needle: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasPrefix("//") && !$0.hasPrefix("*") && !$0.hasPrefix("/*") }
            .filter { $0.contains(needle) }
    }

    // MARK: - Una sola puerta hacia la Papelera

    /// `trashItem` se llama en **un solo sitio** de toda la app:
    /// `LibraryViewModel.performDeletion`, sobre `plan.toTrash`. Un
    /// segundo sitio sería un camino que se saltó el plan -- y el plan
    /// es lo único que distingue el archivo del usuario del derivado
    /// nuestro (`LibraryDeletionPlan`).
    func testTrashItemIsCalledFromExactlyOnePlaceAndItIsThePlan() throws {
        var callSites: [String] = []
        for file in try swiftFiles() {
            for line in codeLines(file.text, containing: "trashItem(") {
                callSites.append("\(file.name): \(line)")
            }
        }
        XCTAssertEqual(callSites.count, 1,
                       "trashItem debe tener UNA sola llamada, en LibraryViewModel.performDeletion: \(callSites)")
        XCTAssertTrue(callSites.first?.hasPrefix("LibraryViewModel.swift") == true, "\(callSites)")
    }

    /// Y las dos listas del plan se **consumen** en un solo sitio:
    /// `LibraryViewModel`. `LibraryDeletionPlan.swift` queda fuera de la
    /// cuenta porque ahí el plan se CONSTRUYE (`plan.toTrash.append`),
    /// que es lo contrario de saltárselo -- primera versión de esta
    /// prueba no hacía la distinción y señalaba al propio plan.
    func testTheDeletionPlanIsConsumedOnlyByPerformDeletion() throws {
        var users: [String] = []
        for file in try swiftFiles() where file.name != "LibraryDeletionPlan.swift" {
            for line in codeLines(file.text, containing: "plan.toTrash") + codeLines(file.text, containing: "plan.toDelete") {
                users.append("\(file.name): \(line)")
            }
        }
        XCTAssertFalse(users.isEmpty, "nadie consume el plan -- ¿cambió de nombre?")
        for user in users {
            XCTAssertTrue(user.hasPrefix("LibraryViewModel.swift"),
                          "el plan se consume fuera de LibraryViewModel: \(user)")
        }
    }

    // MARK: - Quien elimina desde una hoja dibuja su propia confirmación

    /// **La prueba que habría atrapado este bug.** Una `.sheet` tapa a
    /// quien la presenta: una alerta colgada del presentador no aparece
    /// mientras la hoja está arriba. Entonces una vista que se presenta
    /// como hoja **y** llama a `deleteItems` tiene que presentar ella
    /// misma la confirmación del modelo (referenciar `pendingDeletion`),
    /// o el usuario pulsa "eliminar" y no pasa absolutamente nada.
    ///
    /// No se pregunta "¿tiene una alerta?" sino "¿mira
    /// `pendingDeletion`?": eso obliga a que el texto y los números
    /// salgan del modelo, que es la regla de ST-225, y no de un diálogo
    /// escrito a mano en la vista -- que fue justamente el que decía lo
    /// mismo en modo copia y en modo referencia, siendo verdad en uno
    /// solo.
    func testEveryViewThatDeletesFromASheetPresentsTheConfirmationItself() throws {
        let files = try swiftFiles()

        // Qué vistas se construyen dentro de un `.sheet { … }`.
        var presentedAsSheet: Set<String> = []
        let sheetPattern = try NSRegularExpression(pattern: #"\.sheet\("#)
        for file in files {
            let lines = file.text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            for (index, line) in lines.enumerated() {
                let range = NSRange(line.startIndex..., in: line)
                guard sheetPattern.firstMatch(in: line, range: range) != nil else { continue }
                // El cuerpo de la hoja son las líneas que siguen hasta
                // que la sangría vuelve: alcanza con mirar unas pocas,
                // que es donde se construye la vista.
                for following in lines[index..<min(index + 8, lines.count)] {
                    for match in try NSRegularExpression(pattern: #"\b([A-Z]\w+View)\("#)
                        .matches(in: following, range: NSRange(following.startIndex..., in: following)) {
                        presentedAsSheet.insert(String(following[Range(match.range(at: 1), in: following)!]))
                    }
                }
            }
        }
        XCTAssertTrue(presentedAsSheet.contains("SimilarItemsView"),
                      "el barrido de hojas no encontró SimilarItemsView -- la prueba dejaría de proteger nada")

        var offenders: [String] = []
        for file in files {
            let typeName = file.name.replacingOccurrences(of: ".swift", with: "")
            guard presentedAsSheet.contains(typeName) else { continue }
            guard !codeLines(file.text, containing: "deleteItems(").isEmpty else { continue }
            if !file.text.contains("pendingDeletion") {
                offenders.append(typeName)
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      "se presentan como hoja y eliminan, pero no dibujan la confirmación del modelo"
                        + " -- el usuario pulsaría «eliminar» y no pasaría nada: \(offenders)")
    }

    /// Ninguna vista anuncia una eliminación antes de que el usuario la
    /// confirme. `deleteItems` **pide**; quien escriba el resumen en la
    /// misma tanda está contando algo que todavía no pasó (y que no pasa
    /// nunca si se cancela).
    func testNoViewWritesItsSuccessMessageInTheSameBreathAsAskingToDelete() throws {
        var offenders: [String] = []
        for file in try swiftFiles() {
            let lines = file.text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            for (index, line) in lines.enumerated() where line.contains("deleteItems(") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//") else { continue }
                // La línea siguiente que no sea comentario ni cierre.
                for following in lines[(index + 1)..<min(index + 3, lines.count)] {
                    let next = following.trimmingCharacters(in: .whitespaces)
                    if next.contains("lastActionSummary =") || next.contains("Summary = \"Se elimin") {
                        offenders.append("\(file.name):\(index + 2)  \(next.prefix(70))")
                    }
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      "anuncian la eliminación antes de confirmarla:\n" + offenders.joined(separator: "\n"))
    }

    // MARK: - El texto dice la verdad en cada modo

    /// El diálogo de copia promete la Papelera con número y tamaño; el
    /// de referencia promete que el original se queda. Decir lo mismo en
    /// los dos -- que es lo que hacía el diálogo propio de Similares --
    /// es mentir en uno.
    func testTheConfirmationTextTellsTheTruthForEachStorageMode() {
        let copy = LibraryViewModel.PendingDeletion(ids: [UUID()], itemCount: 1,
                                                    filesToTrash: 2, bytesToTrash: 5_000_000)
        XCTAssertEqual(copy.message, LSf("library-view-model.eliminar-copia-papelera",
                                         LSf("library-view-model.plural.archivos", 2),
                                         ByteCountFormatter.string(fromByteCount: 5_000_000, countStyle: .file)))

        let reference = LibraryViewModel.PendingDeletion(ids: [UUID()], itemCount: 1,
                                                         filesToTrash: 0, bytesToTrash: 0)
        XCTAssertEqual(reference.message, LS("library-view-model.eliminar-referencia-uno"))
        XCTAssertNotEqual(reference.message, copy.message,
                          "los dos modos no pueden decir lo mismo: en referencia no se mueve nada a la Papelera")

        let referenceMany = LibraryViewModel.PendingDeletion(ids: [UUID(), UUID()], itemCount: 2,
                                                             filesToTrash: 0, bytesToTrash: 0)
        XCTAssertEqual(referenceMany.message, LS("library-view-model.eliminar-referencia-varios"))
    }
}
