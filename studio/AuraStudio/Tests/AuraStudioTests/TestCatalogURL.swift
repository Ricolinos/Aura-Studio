import Foundation
@testable import AuraStudio

/// La URL del catálogo de localización para las pruebas que lo auditan
/// crudo (LocalizationCatalog/Languages/English/Draft, ComposedSentence).
///
/// Con los toolchains actuales, SwiftPM **compila** el String Catalog a
/// `.strings`/`.stringsdict` y ya no copia el `.xcstrings` fuente al
/// bundle -- `Bundle.module.url(forResource: "Localizable",
/// withExtension: "xcstrings")` devuelve nil y esas pruebas reventaban
/// antes de empezar. El catálogo fuente siempre existe en el árbol de
/// código durante `swift test`, así que la respaldo es leerlo directo
/// de `Sources/AuraStudio/Resources/` (se localiza desde `#filePath`
/// de este archivo, no de una ruta absoluta de una Mac concreta).
enum TestCatalogURL {
    static func localizable() -> URL? {
        if let bundled = AuraBundle.strings.url(forResource: "Localizable", withExtension: "xcstrings") {
            return bundled
        }
        // Tests/AuraStudioTests/TestCatalogURL.swift -> raíz del paquete
        // es dos niveles arriba; el catálogo vive en Sources/AuraStudio.
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // AuraStudioTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // AuraStudio/ (raíz del paquete)
        let candidate = packageRoot
            .appendingPathComponent("Sources/AuraStudio/Resources/Localizable.xcstrings")
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }
}
