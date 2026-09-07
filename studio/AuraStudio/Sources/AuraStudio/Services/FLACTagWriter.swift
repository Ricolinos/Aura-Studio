import Foundation
import ImageIO

/// ST-222 (PLAN-studio-ajustes-3.md, Fase A2): escritor nativo de
/// etiquetas FLAC -- bloque VORBIS_COMMENT y bloque PICTURE.
///
/// **Por qué existe.** `ID3Writer` antepone una tag ID3 al archivo, que
/// es aditivo y no toca nada del resto; por eso la Mac escribía etiquetas
/// solo en MP3, y una edición sobre un FLAC no llegaba nunca al iPod. Un
/// FLAC no admite ese truco: sus metadatos son bloques con estructura
/// propia justo después de la firma `fLaC`, y hay que reescribirlos
/// entendiéndolos.
///
/// **Qué se toca y qué no.** Se reemplazan **solo** los bloques
/// VORBIS_COMMENT (tipo 4) y, cuando se escribe carátula, el PICTURE de
/// portada frontal. STREAMINFO, SEEKTABLE, APPLICATION y CUESHEET pasan
/// intactos byte a byte, y el padding se conserva. Los **fotogramas de
/// audio se copian sin mirarlos**: son el archivo del usuario.
///
/// **Por qué mover los metadatos no rompe la búsqueda.** Los puntos de
/// SEEKTABLE guardan desplazamientos **desde el primer fotograma**, no
/// desde el principio del archivo -- así que crecer o encoger los
/// bloques de metadatos no los invalida. (En M4A no es así, y por eso
/// `MP4TagWriter` sí tiene que corregir `stco`/`co64`.)
enum FLACTagWriter {
    enum WriterError: Error, Equatable {
        /// No empieza con `fLaC`: no es un FLAC nativo. Un `.flac` con
        /// contenedor Ogg entra por acá y **no se toca** -- decir que no
        /// es mejor que escribir algo que el archivo no sabe leer.
        case notANativeFLAC
        /// Los bloques de metadatos no cierran donde dicen. El archivo
        /// está truncado o corrupto: no se reescribe nada.
        case malformedMetadataBlocks
        /// No hay STREAMINFO, que el formato exige como primer bloque.
        case missingStreamInfo
    }

    private enum BlockType: UInt8 {
        case streamInfo = 0
        case padding = 1
        case application = 2
        case seekTable = 3
        case vorbisComment = 4
        case cueSheet = 5
        case picture = 6
    }

    private struct Block {
        var type: UInt8
        var payload: Data
    }

    private static let magic = Data("fLaC".utf8)
    private static let defaultVendor = "Aura Studio"
    /// Tipo 3 del estándar: portada frontal. Es la única que esta app
    /// escribe y la única que reemplaza.
    private static let frontCoverPictureType: UInt32 = 3

    // MARK: - Entrada

    /// Devuelve si de verdad escribió (ST-226).
    @discardableResult
    static func write(_ tag: AudioTag, toFileAt url: URL) throws -> Bool {
        let original = try Data(contentsOf: url)
        let updated = try writing(tag, into: original)
        // Un archivo que no cambia no se reescribe: así conserva su
        // fecha de modificación, y el sync diferencial no lo vuelve a
        // copiar al iPod por nada.
        guard updated != original else { return false }
        try updated.write(to: url, options: .atomic)
        return true
    }

    /// Devuelve el archivo con las etiquetas de `tag` escritas. No toca
    /// disco -- así se puede probar por bytes.
    static func writing(_ tag: AudioTag, into data: Data) throws -> Data {
        guard data.count > magic.count, data.prefix(magic.count) == magic else {
            throw WriterError.notANativeFLAC
        }
        let (blocks, audioStart) = try parseMetadataBlocks(in: data)
        guard blocks.first?.type == BlockType.streamInfo.rawValue else {
            throw WriterError.missingStreamInfo
        }

        let existingVendor = blocks
            .first { $0.type == BlockType.vorbisComment.rawValue }
            .flatMap { vendorString(in: $0.payload) }

        var rebuilt: [Block] = []
        var paddingBytes = 0
        for block in blocks {
            switch BlockType(rawValue: block.type) {
            case .vorbisComment:
                continue // se reemplaza entero, más abajo
            case .padding:
                // El padding no se copia tal cual: se acumula y se
                // vuelve a emitir como UN bloque al final, que es donde
                // el formato lo espera y donde sirve para que otro
                // programa pueda editar sin mover el audio.
                paddingBytes += block.payload.count
            case .picture where tag.coverArtData != nil && isFrontCover(block.payload):
                continue // se reemplaza por la carátula nueva
            default:
                rebuilt.append(block)
            }
        }

        rebuilt.append(Block(type: BlockType.vorbisComment.rawValue,
                             payload: vorbisCommentPayload(tag, vendor: existingVendor ?? defaultVendor)))
        if let cover = tag.coverArtData, !cover.isEmpty {
            rebuilt.append(Block(type: BlockType.picture.rawValue,
                                 payload: picturePayload(cover, mimeType: tag.coverArtMIMEType)))
        }
        if paddingBytes > 0 {
            rebuilt.append(Block(type: BlockType.padding.rawValue,
                                 payload: Data(repeating: 0, count: paddingBytes)))
        }

        var output = magic
        for (index, block) in rebuilt.enumerated() {
            output += serialize(block, isLast: index == rebuilt.count - 1)
        }
        output += data.subdata(in: audioStart..<data.count)
        return output
    }

    // MARK: - Lectura de la estructura

    /// Los bloques de metadatos y dónde empieza el audio. Un bloque
    /// declara su tamaño en 3 bytes big-endian, y el bit alto del primer
    /// byte marca cuál es el último.
    private static func parseMetadataBlocks(in data: Data) throws -> (blocks: [Block], audioStart: Int) {
        var blocks: [Block] = []
        var offset = magic.count
        let base = data.startIndex
        while true {
            guard offset + 4 <= data.count else { throw WriterError.malformedMetadataBlocks }
            let header = data[base + offset]
            let isLast = (header & 0x80) != 0
            let type = header & 0x7F
            let length = Int(data[base + offset + 1]) << 16
                | Int(data[base + offset + 2]) << 8
                | Int(data[base + offset + 3])
            let payloadStart = offset + 4
            guard payloadStart + length <= data.count else { throw WriterError.malformedMetadataBlocks }
            blocks.append(Block(type: type,
                                payload: data.subdata(in: (base + payloadStart)..<(base + payloadStart + length))))
            offset = payloadStart + length
            if isLast { break }
        }
        return (blocks, offset)
    }

    private static func serialize(_ block: Block, isLast: Bool) -> Data {
        var out = Data()
        out.append(isLast ? (block.type | 0x80) : block.type)
        let length = UInt32(block.payload.count)
        out.append(UInt8((length >> 16) & 0xFF))
        out.append(UInt8((length >> 8) & 0xFF))
        out.append(UInt8(length & 0xFF))
        out += block.payload
        return out
    }

    private static func isFrontCover(_ picturePayload: Data) -> Bool {
        guard picturePayload.count >= 4 else { return false }
        let base = picturePayload.startIndex
        let type = picturePayload[base..<(base + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return type == frontCoverPictureType
    }

    /// El vendor de un VORBIS_COMMENT existente. Se conserva a propósito:
    /// según el formato identifica al **codificador** que produjo el
    /// archivo, no a quien editó las etiquetas. Pisarlo con "Aura Studio"
    /// sería afirmar algo falso sobre el archivo del usuario.
    private static func vendorString(in payload: Data) -> String? {
        let base = payload.startIndex
        guard payload.count >= 4 else { return nil }
        let length = Int(payload[base..<(base + 4)].enumerated().reduce(UInt32(0)) {
            $0 | (UInt32($1.element) << (8 * UInt32($1.offset)))
        })
        guard length >= 0, 4 + length <= payload.count else { return nil }
        return String(data: payload.subdata(in: (base + 4)..<(base + 4 + length)), encoding: .utf8)
    }

    // MARK: - Construcción de los bloques

    /// VORBIS_COMMENT: todo en little-endian (al revés que el resto del
    /// formato, que es big-endian -- lo hereda de Vorbis y es la fuente
    /// habitual de errores al escribirlo a mano).
    private static func vorbisCommentPayload(_ tag: AudioTag, vendor: String) -> Data {
        var comments: [(String, String)] = []
        func add(_ key: String, _ value: String?) {
            guard let value, !value.isEmpty else { return }
            comments.append((key, value))
        }
        add("TITLE", tag.title)
        add("ARTIST", tag.artist)
        add("ALBUM", tag.album)
        add("ALBUMARTIST", tag.albumArtist)
        add("DATE", tag.year)
        add("GENRE", tag.genre)
        add("COMPOSER", tag.composer)
        add("TRACKNUMBER", tag.trackNumber.map(String.init))
        add("DISCNUMBER", tag.discNumber.map(String.init))

        var payload = Data()
        let vendorBytes = Data(vendor.utf8)
        payload += le32(UInt32(vendorBytes.count))
        payload += vendorBytes
        payload += le32(UInt32(comments.count))
        for (key, value) in comments {
            let entry = Data("\(key)=\(value)".utf8)
            payload += le32(UInt32(entry.count))
            payload += entry
        }
        return payload
    }

    /// PICTURE: todo big-endian. El ancho, alto y profundidad se leen de
    /// la imagen con ImageIO en vez de escribir ceros -- el formato los
    /// admite en 0 como "no se sabe", pero un reproductor que decida por
    /// ellos qué carátula usar merece el dato bueno, y sale barato.
    private static func picturePayload(_ imageData: Data, mimeType: String) -> Data {
        let (width, height, depth) = imageDimensions(imageData)
        var payload = Data()
        payload += be32(frontCoverPictureType)
        let mimeBytes = Data(mimeType.utf8)
        payload += be32(UInt32(mimeBytes.count))
        payload += mimeBytes
        payload += be32(0) // descripción vacía
        payload += be32(width)
        payload += be32(height)
        payload += be32(depth)
        payload += be32(0) // colores del índice: 0 = no es una imagen indexada
        payload += be32(UInt32(imageData.count))
        payload += imageData
        return payload
    }

    private static func imageDimensions(_ data: Data) -> (width: UInt32, height: UInt32, depth: UInt32) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return (0, 0, 0)
        }
        let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.uint32Value ?? 0
        let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.uint32Value ?? 0
        // Profundidad POR PÍXEL, que es lo que pide el formato -- ImageIO
        // reporta la de cada componente.
        let perComponent = (properties[kCGImagePropertyDepth] as? NSNumber)?.uint32Value ?? 8
        return (width, height, perComponent * 3)
    }

    private static func le32(_ value: UInt32) -> Data {
        Data([UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF),
              UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF)])
    }

    private static func be32(_ value: UInt32) -> Data {
        Data([UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
              UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)])
    }
}
