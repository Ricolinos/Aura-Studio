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

    /// PLAN-sync-media-hardening.md PARTE 2A: `/Photos/` y `/Videos/`
    /// son planos en el iPod -- el nombre de archivo final (con
    /// extensión) es lo único que el firmware ve, y su límite real es
    /// un buffer C de tamaño fijo (`PHOTO_NAME_LEN`/`VIDEO_NAME_LEN`,
    /// 96 con el NUL — docs/contracts/library-layout-v1.md §1: "≤ 95
    /// bytes UTF-8 incluyendo la extensión"). Un nombre con acentos/ñ
    /// puede tener MENOS caracteres que bytes -- capar por caracteres
    /// (como `sanitize(_:maxLength:)`, pensado para componentes de ruta
    /// de música, donde el firmware no tiene ese límite exacto) seguía
    /// pudiendo exceder el límite real en bytes para un nombre muy
    /// acentuado. Recorta un `Character` (nunca a mitad de una
    /// secuencia UTF-8 multibyte) a la vez desde el final de la base,
    /// conservando la extensión completa.
    static func sanitizeFilename(_ raw: String, maxBytes: Int) -> String {
        let ext = (raw as NSString).pathExtension
        var base = sanitize((raw as NSString).deletingPathExtension, maxLength: Int.max)
        let suffix = ext.isEmpty ? "" : ".\(ext)"

        while (base + suffix).utf8.count > maxBytes, !base.isEmpty {
            base.removeLast()
        }
        while let last = base.last, last == "." || last == " " {
            base.removeLast()
        }
        let result = base + suffix
        return result.isEmpty ? "_" + suffix : result
    }
}
