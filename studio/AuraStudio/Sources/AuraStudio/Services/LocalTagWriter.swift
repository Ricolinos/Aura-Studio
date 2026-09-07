import Foundation

/// ST-222 (PLAN-studio-ajustes-3.md, Fase A2): una sola puerta para
/// escribir las etiquetas del catálogo dentro del archivo de audio, sea
/// cual sea el formato. Hermano de `LocalTagWriter.cs` de Windows
/// (ST-242), con el mismo nombre a propósito.
///
/// **Qué había.** La Mac escribía etiquetas solo en MP3, anteponiendo
/// una tag ID3. En FLAC, M4A, WAV y AIFF no escribía nada: editar el
/// título de una canción no cambiaba el archivo, así que la edición **no
/// llegaba al iPod**. Ese era el punto del diagnóstico de la ronda.
///
/// **Qué se etiqueta y qué no.** MP3 (ID3v2.3), FLAC (VORBIS_COMMENT +
/// PICTURE) y M4A/ALAC (átomos `ilst`). WAV y AIFF **no se etiquetan**:
/// al importarlos en modo copia se convierten a MP3 (§0.2 del plan), así
/// que decir que no acá es lo correcto -- y decirlo, en vez de fallar en
/// silencio, es la diferencia entre un formato que no se etiqueta y un
/// escritor roto.
enum LocalTagWriter {
    /// Qué pasó al intentar escribir. Mismo contrato que
    /// `TagWriteResult` de Windows: `written == false` significa que **el
    /// archivo no se tocó**, y `reason` dice por qué.
    struct Result: Equatable {
        var written: Bool
        var reason: String?

        static let wroteFile = Result(written: true, reason: nil)
        static func skipped(_ reason: String) -> Result { Result(written: false, reason: reason) }
    }

    /// Los formatos en los que esta app sabe escribir etiquetas.
    static let taggableExtensions: Set<String> = ["mp3", "flac", "m4a", "m4b", "mp4"]

    static func canWrite(_ url: URL) -> Bool {
        taggableExtensions.contains(url.pathExtension.lowercased())
    }

    /// Escribe `tag` dentro del archivo. **Nunca lanza**: un archivo de
    /// solo lectura, en uso o con la estructura rota devuelve
    /// `skipped(...)` con el motivo. Fallar en escribir una etiqueta no
    /// puede tumbar una importación de mil canciones -- pero tampoco
    /// puede pasar inadvertido, y por eso el motivo viaja de vuelta en
    /// vez de perderse.
    @discardableResult
    static func write(_ tag: AudioTag, toFileAt url: URL) -> Result {
        let ext = url.pathExtension.lowercased()
        guard taggableExtensions.contains(ext) else {
            return .skipped("el formato .\(ext) no lleva etiquetas (se convierte a MP3 al importar)")
        }
        guard !tag.isEmpty else {
            return .skipped("no hay ningún campo que escribir")
        }
        do {
            switch ext {
            case "mp3":
                try ID3Writer.write(tag, toFileAt: url)
            case "flac":
                try FLACTagWriter.write(tag, toFileAt: url)
            default:
                try MP4TagWriter.write(tag, toFileAt: url)
            }
            return .wroteFile
        } catch {
            return .skipped("no se pudieron escribir las etiquetas de \(url.lastPathComponent): \(error)")
        }
    }
}
