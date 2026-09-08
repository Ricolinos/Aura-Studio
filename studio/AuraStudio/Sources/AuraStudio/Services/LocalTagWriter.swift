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
/// al importarlos en modo copia se convierten -- a ALAC con "Mantener
/// formato original", a MP3 con "Comprimido" (`AudioConversionRule`) --
/// y lo que queda en la biblioteca sí lleva etiquetas. Decir que no acá,
/// en vez de fallar en silencio, es la diferencia entre un formato que
/// no se etiqueta y un escritor roto.
enum LocalTagWriter {
    /// Qué pasó al intentar escribir. Mismo contrato que
    /// `TagWriteResult` de Windows: `written == false` significa que **el
    /// archivo no se tocó**, y `reason` dice por qué.
    /// Por qué NO se escribió, **tipado** (ST-227, A7c cierre 2).
    ///
    /// Antes esto era solo texto, y dos sitios de `LibraryViewModel`
    /// decidían con `reason.hasPrefix("no se pudieron escribir")` si
    /// avisarle al usuario. Windows encontró de su lado que esa misma
    /// forma ya fallaba en producción, y acá era cuestión de tiempo:
    /// cambiarle una palabra al mensaje --traducirlo, sin ir más lejos--
    /// apagaba las dos ramas **en silencio**. Los errores de escritura
    /// dejarían de mostrarse y la migración dejaría de contarlos, con
    /// todo en verde.
    ///
    /// El texto sigue viajando, porque es lo que se le enseña al
    /// usuario; lo que ya no viaja es la DECISIÓN metida dentro del
    /// texto.
    enum Skip: Equatable {
        /// El formato no lleva etiquetas. No es un fallo.
        case formatCarriesNoTags(String)
        /// No había ningún campo que escribir. No es un fallo.
        case nothingToWrite(String)
        /// Se intentó escribir y no se pudo. **Esto sí se le dice al
        /// usuario**: su edición no llegó al archivo.
        case writeFailed(String)

        var text: String {
            switch self {
            case let .formatCarriesNoTags(t), let .nothingToWrite(t), let .writeFailed(t): return t
            }
        }

        var isFailure: Bool {
            if case .writeFailed = self { return true }
            return false
        }
    }

    struct Result: Equatable {
        /// Se pudo escribir (o no hacía falta). `false` = el archivo no
        /// se tocó y `skip` dice por qué.
        var written: Bool
        /// Si el archivo **cambió de verdad**. ST-226: `written` sin esto
        /// no alcanza -- un resumen de migración que cuenta "1 con
        /// etiquetas nuevas" cuando el archivo ya decía lo mismo le está
        /// contando al usuario algo que no pasó.
        var changed: Bool = false
        var skip: Skip?

        /// El texto del motivo, para mostrarlo. Nadie decide con esto.
        var reason: String? { skip?.text }
        /// Si hay que avisarle al usuario. **Ésta es la pregunta que
        /// antes se hacía comparando prefijos de una frase en español.**
        var isFailure: Bool { skip?.isFailure == true }

        static func wroteFile(changed: Bool) -> Result { Result(written: true, changed: changed, skip: nil) }
        static func skipped(_ skip: Skip) -> Result { Result(written: false, changed: false, skip: skip) }
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
        write(tag, toFileAt: url, as: url.pathExtension)
    }

    /// Igual, pero diciendo el formato aparte del nombre del archivo.
    ///
    /// Existe por la importación atómica de ST-223: el archivo se arma
    /// en un temporal `.aura-tmp` —a propósito **sin** extensión de
    /// música, para que un archivo a medio escribir no parezca una
    /// canción importable— y hay que etiquetarlo ANTES de moverlo a su
    /// nombre definitivo. Sin este parámetro, el despachador miraría
    /// `.aura-tmp`, no reconocería el formato y se saltaría las
    /// etiquetas en silencio.
    @discardableResult
    static func write(_ tag: AudioTag, toFileAt url: URL, as formatExtension: String) -> Result {
        let ext = formatExtension.lowercased()
        guard taggableExtensions.contains(ext) else {
            return .skipped(.formatCarriesNoTags("el formato .\(ext) no lleva etiquetas (al importarlo en copia se convierte, ver AudioConversionRule)"))
        }
        guard !tag.isEmpty else {
            return .skipped(.nothingToWrite("no hay ningún campo que escribir"))
        }
        do {
            let changed: Bool
            switch ext {
            case "mp3":
                changed = try ID3Writer.write(tag, toFileAt: url)
            case "flac":
                changed = try FLACTagWriter.write(tag, toFileAt: url)
            default:
                changed = try MP4TagWriter.write(tag, toFileAt: url)
            }
            return .wroteFile(changed: changed)
        } catch {
            return .skipped(.writeFailed("no se pudieron escribir las etiquetas de \(url.lastPathComponent): \(error)"))
        }
    }

    /// ST-224: ¿el archivo **ya dice** lo que dice el catálogo?
    ///
    /// Es la mitad barata de la regla que evita duplicar la biblioteca en
    /// modo referencia: una canción cuyo archivo ya coincide no necesita
    /// derivado y viaja tal cual (`PreparedMusicPlan`).
    ///
    /// Se compara contra lo que el archivo dice **hoy**, no contra lo que
    /// se le escribió la última vez: el archivo manda sobre su propio
    /// estado, y alguien pudo haberlo tocado por fuera. Y un campo que el
    /// catálogo **no** dice no cuenta como diferencia -- no se escribe un
    /// vacío encima de algo que el archivo ya traía.
    static func matches(_ tag: AudioTag, fileAt url: URL) async -> Bool {
        guard canWrite(url), FileManager.default.fileExists(atPath: url.path) else { return false }
        return await pendingFields(tag, fileAt: url).isEmpty
    }

    /// Qué campos habría que cambiarle al archivo. Devuelve nombres
    /// porque es lo que se registra y lo que se prueba: "no coincide" sin
    /// decir en qué no se puede revisar.
    static func pendingFields(_ tag: AudioTag, fileAt url: URL) async -> [String] {
        let current = await LocalTagReader.readTag(from: url)
        var pending: [String] = []

        func compare(_ field: String, _ desired: String?, _ actual: String?) {
            guard let desired, !desired.isEmpty else { return } // el catálogo no dice nada: no se toca
            if desired != actual { pending.append(field) }
        }
        compare("título", tag.title, current.title)
        compare("artista", tag.artist, current.artist)
        compare("álbum", tag.album, current.album)
        compare("artista del álbum", tag.albumArtist, current.albumArtist)
        compare("compositor", tag.composer, current.composer)
        compare("género", tag.genre, current.genre)
        compare("año", tag.year, current.year)

        if let track = tag.trackNumber, track > 0, track != current.trackNumber { pending.append("pista") }
        if let disc = tag.discNumber, disc > 0, disc != current.discNumber { pending.append("disco") }

        // La carátula se compara por bytes: es la única forma de saber si
        // la que está incrustada es la que el catálogo quiere, y a esta
        // altura las dos ya pasaron por el mismo recorte.
        if let desiredCover = tag.coverArtData, !desiredCover.isEmpty,
           current.pendingCoverData != desiredCover {
            pending.append("carátula")
        }
        return pending
    }
}
