import Foundation

/// Escritor (y lector minimo, para poder verificar round-trip) de tags
/// ID3v2.3 -- el formato de metadata que lee tagcache de Rockbox en
/// archivos MP3. Implementado a mano, sin dependencias externas: es un
/// formato binario simple (cabecera + frames TLV) y evita traer una
/// libreria de terceros para algo tan acotado.
///
/// Alcance deliberado (ver D-037 en DECISIONS.md): esta es la unica
/// escritura de tags "nativa en el archivo" que Aura Studio implementa
/// en esta fase. Para FLAC/MP4/ALAC/WAV/AIFF, el enriquecimiento
/// (MusicBrainz/CAA/LRCLIB) se resuelve igual y la caratula/letra se
/// escriben como sidecars (cover.jpg / .lrc, que Aura ya sabe leer via
/// find_albumart/aura_lrc -- D-019, Fase 4), pero el titulo/artista/
/// album que alimenta el tagcache de Rockbox para esos formatos sigue
/// siendo el que ya traiga el archivo. Escribir Vorbis comments (FLAC)
/// o atomos MP4 correctamente requiere reescribir la estructura interna
/// de esos contenedores (mucho mas riesgoso que anteponer una tag ID3,
/// que es aditiva y no toca el resto del archivo) -- queda para una
/// iteracion futura si hace falta.
enum ID3Writer {
    struct Tag: Equatable {
        var title: String?
        var artist: String?
        var album: String?
        var albumArtist: String?
        var year: String?
        var genre: String?
        /// Autor/compositor -- frame TCOM, lo que lee `tag_composer` del
        /// tagcache de Rockbox (AURA_SCREEN_MUSIC_COMPOSERS).
        var composer: String?
        var trackNumber: Int?
        var coverArtData: Data?
        var coverArtMIMEType: String = "image/jpeg"
    }

    enum WriterError: Error {
        case fileNotReadable
    }

    // MARK: - Escritura

    /// Antepone una tag ID3v2.3 nueva a `data`, reemplazando cualquier
    /// tag ID3v2 existente al principio del archivo (se detecta y se
    /// descarta via `existingTagSize`). El audio despues de la tag no
    /// se toca en absoluto.
    static func writing(_ tag: Tag, into data: Data) -> Data {
        let skip = existingTagSize(in: data)
        let audioData = data.subdata(in: skip..<data.count)
        let tagData = buildTag(tag)
        return tagData + audioData
    }

    static func write(_ tag: Tag, toFileAt url: URL) throws {
        let original = try Data(contentsOf: url)
        let newData = writing(tag, into: original)
        try newData.write(to: url, options: .atomic)
    }

    static func buildTag(_ tag: Tag) -> Data {
        var frames = Data()
        if let title = tag.title { frames += textFrame("TIT2", title) }
        if let artist = tag.artist { frames += textFrame("TPE1", artist) }
        if let album = tag.album { frames += textFrame("TALB", album) }
        if let albumArtist = tag.albumArtist { frames += textFrame("TPE2", albumArtist) }
        if let year = tag.year { frames += textFrame("TYER", year) }
        if let genre = tag.genre { frames += textFrame("TCON", genre) }
        if let composer = tag.composer { frames += textFrame("TCOM", composer) }
        if let track = tag.trackNumber { frames += textFrame("TRCK", String(track)) }
        if let cover = tag.coverArtData { frames += pictureFrame(cover, mimeType: tag.coverArtMIMEType) }

        var header = Data()
        header.append(contentsOf: [0x49, 0x44, 0x33]) // "ID3"
        header.append(contentsOf: [0x03, 0x00])       // version 2.3.0
        header.append(0x00)                            // flags
        header += synchsafe(UInt32(frames.count))

        return header + frames
    }

    private static func textFrame(_ id: String, _ value: String) -> Data {
        // Encoding 0x01 = UTF-16 con BOM: soporta acentos/ñ sin
        // depender de que el texto sea representable en Latin-1.
        var payload = Data([0x01])
        payload += Data([0xFF, 0xFE]) // BOM little-endian
        payload += value.data(using: .utf16LittleEndian) ?? Data()
        payload += Data([0x00, 0x00]) // terminador UTF-16

        return frame(id: id, payload: payload)
    }

    private static func pictureFrame(_ imageData: Data, mimeType: String) -> Data {
        var payload = Data([0x00]) // encoding: Latin-1 (mime/descripcion son ASCII)
        payload += (mimeType.data(using: .isoLatin1) ?? Data())
        payload += Data([0x00]) // terminador del MIME type
        payload += Data([0x03]) // picture type: 3 = front cover
        payload += Data([0x00]) // descripcion vacia + su terminador
        payload += imageData

        return frame(id: "APIC", payload: payload)
    }

    private static func frame(id: String, payload: Data) -> Data {
        var f = Data()
        f += id.data(using: .ascii) ?? Data()
        f += bigEndian32(UInt32(payload.count)) // tamaño de frame en 2.3: NO es synchsafe
        f += Data([0x00, 0x00])                  // flags
        f += payload
        return f
    }

    // MARK: - Lectura minima (para round-trip / revision)

    /// Tamaño total (cabecera de 10 bytes + frames) de la tag ID3v2 al
    /// principio de `data`, o 0 si no hay ninguna.
    static func existingTagSize(in data: Data) -> Int {
        guard data.count >= 10 else { return 0 }
        let bytes = [UInt8](data.prefix(10))
        guard bytes[0] == 0x49, bytes[1] == 0x44, bytes[2] == 0x33 else { return 0 }
        let size = unsynchsafe(bytes[6], bytes[7], bytes[8], bytes[9])
        return 10 + Int(size)
    }

    /// Parser de solo lectura, usado por los tests para verificar que
    /// lo que se escribio se puede leer de vuelta exactamente igual.
    static func readTag(from data: Data) -> Tag? {
        guard data.count >= 10 else { return nil }
        let bytes = [UInt8](data)
        guard bytes[0] == 0x49, bytes[1] == 0x44, bytes[2] == 0x33 else { return nil }
        let tagSize = Int(unsynchsafe(bytes[6], bytes[7], bytes[8], bytes[9]))

        var tag = Tag()
        var offset = 10
        let end = min(10 + tagSize, data.count)

        while offset + 10 <= end {
            let idBytes = data.subdata(in: offset..<(offset + 4))
            guard let id = String(data: idBytes, encoding: .ascii), id != "\0\0\0\0" else { break }
            let sizeBytes = [UInt8](data.subdata(in: (offset + 4)..<(offset + 8)))
            let frameSize = Int(bigEndian32Value(sizeBytes))
            let payloadStart = offset + 10
            let payloadEnd = payloadStart + frameSize
            guard payloadEnd <= end, frameSize > 0 else { break }
            let payload = data.subdata(in: payloadStart..<payloadEnd)

            switch id {
            case "TIT2": tag.title = decodeText(payload)
            case "TPE1": tag.artist = decodeText(payload)
            case "TALB": tag.album = decodeText(payload)
            case "TPE2": tag.albumArtist = decodeText(payload)
            case "TYER": tag.year = decodeText(payload)
            case "TCON": tag.genre = decodeText(payload)
            case "TCOM": tag.composer = decodeText(payload)
            case "TRCK": tag.trackNumber = Int(decodeText(payload) ?? "")
            case "APIC": tag.coverArtData = decodePicture(payload)
            default: break
            }

            offset = payloadEnd
        }

        return tag
    }

    private static func decodeText(_ payload: Data) -> String? {
        guard let encodingByte = payload.first else { return nil }
        let body = payload.dropFirst()
        switch encodingByte {
        case 0x01:
            // BOM (2 bytes) + UTF-16 + terminador nulo de 2 bytes
            let withoutBOM = body.dropFirst(2)
            let trimmed = trimTrailingNulls(withoutBOM, nullWidth: 2)
            return String(data: trimmed, encoding: .utf16LittleEndian)
        default:
            let trimmed = trimTrailingNulls(body, nullWidth: 1)
            return String(data: trimmed, encoding: .isoLatin1)
        }
    }

    private static func decodePicture(_ payload: Data) -> Data? {
        guard let mimeEnd = payload.dropFirst().firstIndex(of: 0x00) else { return nil }
        // payload: [encoding][mime...\0][picture type][description...\0][data]
        var offset = mimeEnd + 1 // salta encoding+mime+\0
        offset += 1 // picture type
        guard offset < payload.endIndex, let descEnd = payload[offset...].firstIndex(of: 0x00) else { return nil }
        let dataStart = descEnd + 1
        guard dataStart < payload.endIndex else { return nil }
        return payload.subdata(in: dataStart..<payload.endIndex)
    }

    private static func trimTrailingNulls(_ data: Data, nullWidth: Int) -> Data {
        var result = data
        while result.count >= nullWidth && result.suffix(nullWidth).allSatisfy({ $0 == 0 }) {
            result = result.dropLast(nullWidth)
        }
        return result
    }

    // MARK: - Utilidades binarias

    private static func synchsafe(_ value: UInt32) -> Data {
        var v = value
        var bytes = [UInt8](repeating: 0, count: 4)
        for i in stride(from: 3, through: 0, by: -1) {
            bytes[i] = UInt8(v & 0x7F)
            v >>= 7
        }
        return Data(bytes)
    }

    private static func unsynchsafe(_ b0: UInt8, _ b1: UInt8, _ b2: UInt8, _ b3: UInt8) -> UInt32 {
        (UInt32(b0) << 21) | (UInt32(b1) << 14) | (UInt32(b2) << 7) | UInt32(b3)
    }

    private static func bigEndian32(_ value: UInt32) -> Data {
        Data([UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)])
    }

    private static func bigEndian32Value(_ bytes: [UInt8]) -> UInt32 {
        (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16) | (UInt32(bytes[2]) << 8) | UInt32(bytes[3])
    }
}
