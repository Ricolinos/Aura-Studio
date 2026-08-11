import Foundation

/// Fase 24 (PLAN-UX.md): saneo de un unico componente de ruta (nombre de
/// artista/album/titulo/playlist) para que sea valido como nombre de
/// archivo/carpeta en el FAT32 del iPod -- los metadatos reales traen
/// con frecuencia caracteres que ese sistema de archivos no acepta
/// ("AC/DC", "Sigur Ros: ()" con dos puntos, etc).
enum PathSanitizer {
    private static let illegalCharacters = CharacterSet(charactersIn: "/\\:*?\"<>|")

    static func sanitize(_ raw: String) -> String {
        let replaced = String(String.UnicodeScalarView(
            raw.unicodeScalars.map { illegalCharacters.contains($0) ? "_" : $0 }
        ))

        var result = replaced.trimmingCharacters(in: .whitespaces)
        // FAT32/Windows no permite que un nombre termine en "." o espacio.
        while let last = result.last, last == "." || last == " " {
            result.removeLast()
        }

        return result.isEmpty ? "_" : result
    }
}
