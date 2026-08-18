import Foundation

/// Fase 24 (PLAN-UX.md): saneo de un unico componente de ruta (nombre de
/// artista/album/titulo/playlist) para que sea valido como nombre de
/// archivo/carpeta en el FAT32 del iPod -- los metadatos reales traen
/// con frecuencia caracteres que ese sistema de archivos no acepta
/// ("AC/DC", "Sigur Ros: ()" con dos puntos, etc).
enum PathSanitizer {
    private static let illegalCharacters = CharacterSet(charactersIn: "/\\:*?\"<>|")

    /// PLAN-sync-media-hardening.md PARTE 1A: visto en produccion, un
    /// solo componente de ruta (el tag de artista, en ese caso) puede
    /// traer metadata real de decenas de caracteres -- un credito de
    /// composicion completo pegado ahi ("Los Aguas Aguas, Luis Felipe
    /// Balderas Lopez, ..."), sin ningun limite. `Music/<ese
    /// componente>/<album>/<archivo>.mp3.aura-tmp` (el sufijo temporal
    /// de `copyFileTransactionally`) termino excediendo lo que el driver
    /// msdosfs de macOS acepta -- Cocoa lo reporta como "el nombre de
    /// archivo es invalido", sin mencionar que la causa real es el largo
    /// acumulado. 120 caracteres por componente es holgado para nombres
    /// reales (artista/album/titulo) y deja margen de sobra bajo
    /// cualquier limite practico de FAT32/msdosfs para la ruta completa.
    static let defaultMaxLength = 120

    static func sanitize(_ raw: String, maxLength: Int = defaultMaxLength) -> String {
        let replaced = String(String.UnicodeScalarView(
            raw.unicodeScalars.map { illegalCharacters.contains($0) ? "_" : $0 }
        ))

        var result = replaced.trimmingCharacters(in: .whitespaces)
        if result.count > maxLength {
            result = String(result.prefix(maxLength))
        }
        // FAT32/Windows no permite que un nombre termine en "." o espacio
        // -- se revisa DESPUES de truncar, por si el corte dejo alguno.
        while let last = result.last, last == "." || last == " " {
            result.removeLast()
        }

        return result.isEmpty ? "_" : result
    }
}
