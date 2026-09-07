import Foundation

/// PLAN-studio-ajustes-3.md, Fase A2 (ST-222): lectores propios,
/// independientes de AVFoundation, para verificar por bytes crudos que
/// lo que escriba el escritor nativo de "experto en código opus" es de
/// verdad un VORBIS_COMMENT/`ilst` válido -- no solo que AVFoundation
/// (que es tolerante) logre extraer algo de ahí. Viven en Tests/ (no
/// son parte de la app) porque el único consumidor es esta verificación
/// de ida y vuelta.
enum FLACTagReader {
    /// Recorre los bloques de metadata de un FLAC (después del "fLaC")
    /// hasta encontrar VORBIS_COMMENT (tipo 4) y devuelve sus
    /// comentarios `CLAVE=valor` como diccionario (mayúsculas, como los
    /// escribe Vorbis por convención).
    static func readVorbisComments(from data: Data) -> [String: String]? {
        guard data.count >= 4, data.subdata(in: 0..<4) == Data("fLaC".utf8) else { return nil }
        var offset = 4
        while offset + 4 <= data.count {
            let header = data[data.startIndex + offset]
            let isLast = (header & 0x80) != 0
            let blockType = header & 0x7F
            let length = Int(data[data.startIndex + offset + 1]) << 16
                | Int(data[data.startIndex + offset + 2]) << 8
                | Int(data[data.startIndex + offset + 3])
            let payloadStart = offset + 4
            guard payloadStart + length <= data.count else { return nil }
            if blockType == 4 {
                return parseVorbisCommentPayload(data.subdata(in: (data.startIndex + payloadStart)..<(data.startIndex + payloadStart + length)))
            }
            offset = payloadStart + length
            if isLast { break }
        }
        return nil
    }

    private static func parseVorbisCommentPayload(_ payload: Data) -> [String: String] {
        var result: [String: String] = [:]
        var cursor = payload.startIndex
        func readLE32() -> Int? {
            guard cursor + 4 <= payload.endIndex else { return nil }
            let bytes = payload[cursor..<(cursor + 4)]
            cursor += 4
            return bytes.enumerated().reduce(0) { $0 | (Int($1.element) << (8 * $1.offset)) }
        }
        guard let vendorLength = readLE32(), cursor + vendorLength <= payload.endIndex else { return result }
        cursor += vendorLength // se salta el vendor string, no hace falta para verificar tags
        guard let commentCount = readLE32() else { return result }
        for _ in 0..<commentCount {
            guard let entryLength = readLE32(), cursor + entryLength <= payload.endIndex else { break }
            let entryData = payload.subdata(in: cursor..<(cursor + entryLength))
            cursor += entryLength
            guard let entry = String(data: entryData, encoding: .utf8),
                  let equalsIndex = entry.firstIndex(of: "=") else { continue }
            let key = String(entry[entry.startIndex..<equalsIndex]).uppercased()
            let value = String(entry[entry.index(after: equalsIndex)...])
            result[key] = value
        }
        return result
    }
}

/// Lector mínimo de `moov/udta/meta/ilst` (los átomos iTunes de un
/// M4A/MP4) -- suficiente para leer `©nam`/`©ART`/`©alb` de vuelta sin
/// pasar por AVFoundation. `meta` es la única caja "de versión
/// completa" (4 bytes de version+flags antes de sus hijos); el resto
/// de las cajas contenedoras no llevan ese prefijo.
enum MP4TagReader {
    private struct Box {
        let type: String
        let payloadRange: Range<Int>
        let end: Int
    }

    /// ISO-BMFF permite tamaño de 64 bits: `size32 == 1` quiere decir
    /// "el tamaño real va en los 8 bytes que siguen al tipo" (el propio
    /// `mdat` del M4A que escribe `AVAssetWriter` usa esta forma) --
    /// sin esto, el parser lee mal el tamaño y se pierde el resto del
    /// archivo completo, `moov` incluido.
    private static func readBoxes(in data: Data, range: Range<Int>) -> [Box] {
        var boxes: [Box] = []
        var offset = range.lowerBound
        while offset + 8 <= range.upperBound {
            let size32 = data.subdata(in: offset..<(offset + 4)).reduce(0) { ($0 << 8) | Int($1) }
            // `.isoLatin1`, no `.ascii`: los átomos "bien conocidos" de
            // iTunes (©nam, ©ART...) empiezan con el byte 0xA9 -- no es
            // ASCII válido, y `.ascii` devuelve `nil` en silencio para
            // los cuatro bytes enteros, no solo para ese uno.
            let type = String(data: data.subdata(in: (offset + 4)..<(offset + 8)), encoding: .isoLatin1) ?? ""
            let headerLength: Int
            let size: Int
            if size32 == 1 {
                guard offset + 16 <= range.upperBound else { break }
                size = data.subdata(in: (offset + 8)..<(offset + 16)).reduce(0) { ($0 << 8) | Int($1) }
                headerLength = 16
            } else {
                size = size32
                headerLength = 8
            }
            guard size >= headerLength, offset + size <= range.upperBound else { break }
            boxes.append(Box(type: type, payloadRange: (offset + headerLength)..<(offset + size), end: offset + size))
            offset += size
        }
        return boxes
    }

    /// Los cuatro campos comunes que "experto en código opus" va a
    /// escribir (título/artista/álbum/álbum-artista) -- se puede ampliar
    /// cuando anuncie la firma real de su escritor.
    private static let atomKeys: [String: String] = [
        "\u{A9}nam": "title", "\u{A9}ART": "artist", "\u{A9}alb": "album", "aART": "albumArtist",
        "\u{A9}day": "year", "\u{A9}wrt": "composer", "\u{A9}gen": "genre",
    ]

    static func readIlstAtoms(from data: Data) -> [String: String] {
        guard let moov = readBoxes(in: data, range: 0..<data.count).first(where: { $0.type == "moov" }) else { return [:] }
        guard let udta = readBoxes(in: data, range: moov.payloadRange).first(where: { $0.type == "udta" }) else { return [:] }
        guard let metaBox = readBoxes(in: data, range: udta.payloadRange).first(where: { $0.type == "meta" }) else { return [:] }
        // `meta` es una caja de versión completa: 4 bytes de
        // version+flags antes de que empiecen sus hijos.
        let metaChildren = (metaBox.payloadRange.lowerBound + 4)..<metaBox.payloadRange.upperBound
        guard let ilst = readBoxes(in: data, range: metaChildren).first(where: { $0.type == "ilst" }) else { return [:] }

        var result: [String: String] = [:]
        for atom in readBoxes(in: data, range: ilst.payloadRange) {
            guard let fieldName = atomKeys[atom.type] else { continue }
            guard let dataBox = readBoxes(in: data, range: atom.payloadRange).first(where: { $0.type == "data" }) else { continue }
            // Dentro de `data`: 4 bytes de tipo (el primer byte es la
            // clase real, p. ej. 1 = UTF-8) + 4 bytes de locale + el
            // valor.
            let valueStart = dataBox.payloadRange.lowerBound + 8
            guard valueStart <= dataBox.payloadRange.upperBound else { continue }
            let valueBytes = data.subdata(in: valueStart..<dataBox.payloadRange.upperBound)
            result[fieldName] = String(data: valueBytes, encoding: .utf8)
        }
        return result
    }
}

// MARK: - ST-222: lo que hace falta para verificar los escritores de A2

extension FLACTagReader {
    /// Los tipos de bloque de metadatos, en orden, con su tamaño. Sirve
    /// para comprobar que el escritor conservó lo que no le tocaba
    /// (STREAMINFO, SEEKTABLE, padding) y no solo que escribió lo suyo.
    static func metadataBlockLayout(from data: Data) -> [(type: UInt8, length: Int)]? {
        guard data.count >= 4, data.subdata(in: 0..<4) == Data("fLaC".utf8) else { return nil }
        var layout: [(UInt8, Int)] = []
        var offset = 4
        while offset + 4 <= data.count {
            let header = data[data.startIndex + offset]
            let isLast = (header & 0x80) != 0
            let length = Int(data[data.startIndex + offset + 1]) << 16
                | Int(data[data.startIndex + offset + 2]) << 8
                | Int(data[data.startIndex + offset + 3])
            guard offset + 4 + length <= data.count else { return nil }
            layout.append((header & 0x7F, length))
            offset += 4 + length
            if isLast { break }
        }
        return layout
    }

    /// Dónde empieza el audio (después del último bloque de metadatos).
    static func audioStartOffset(from data: Data) -> Int? {
        guard let layout = metadataBlockLayout(from: data) else { return nil }
        return layout.reduce(4) { $0 + 4 + $1.length }
    }

    /// El payload del primer bloque PICTURE (tipo 6), ya separado en sus
    /// campos -- para verificar que la carátula viajó entera y con el
    /// tipo "portada frontal".
    static func readPicture(from data: Data) -> (pictureType: UInt32, mimeType: String, imageData: Data)? {
        guard data.count >= 4, data.subdata(in: 0..<4) == Data("fLaC".utf8) else { return nil }
        var offset = 4
        while offset + 4 <= data.count {
            let header = data[data.startIndex + offset]
            let isLast = (header & 0x80) != 0
            let length = Int(data[data.startIndex + offset + 1]) << 16
                | Int(data[data.startIndex + offset + 2]) << 8
                | Int(data[data.startIndex + offset + 3])
            let payloadStart = offset + 4
            guard payloadStart + length <= data.count else { return nil }
            if (header & 0x7F) == 6 {
                return parsePicturePayload(data.subdata(in: (data.startIndex + payloadStart)..<(data.startIndex + payloadStart + length)))
            }
            offset = payloadStart + length
            if isLast { break }
        }
        return nil
    }

    private static func parsePicturePayload(_ payload: Data) -> (UInt32, String, Data)? {
        var cursor = payload.startIndex
        func readBE32() -> UInt32? {
            guard cursor + 4 <= payload.endIndex else { return nil }
            let value = payload[cursor..<(cursor + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            cursor += 4
            return value
        }
        guard let pictureType = readBE32(),
              let mimeLength = readBE32(), cursor + Int(mimeLength) <= payload.endIndex else { return nil }
        let mime = String(data: payload.subdata(in: cursor..<(cursor + Int(mimeLength))), encoding: .utf8) ?? ""
        cursor += Int(mimeLength)
        guard let descriptionLength = readBE32(), cursor + Int(descriptionLength) <= payload.endIndex else { return nil }
        cursor += Int(descriptionLength)
        // ancho, alto, profundidad, colores del índice
        for _ in 0..<4 { guard readBE32() != nil else { return nil } }
        guard let imageLength = readBE32(), cursor + Int(imageLength) <= payload.endIndex else { return nil }
        return (pictureType, mime, payload.subdata(in: cursor..<(cursor + Int(imageLength))))
    }
}

extension MP4TagReader {
    /// `trkn` y `disk`: el número va en los bytes 2-3 del valor, después
    /// de los 8 de cabecera del átomo `data`.
    static func readTrackAndDisc(from data: Data) -> (track: Int?, disc: Int?) {
        (numberAtom("trkn", in: data), numberAtom("disk", in: data))
    }

    static func readCoverArt(from data: Data) -> (typeIndicator: UInt32, imageData: Data)? {
        guard let payload = rawAtomPayload("covr", in: data) else { return nil }
        guard payload.count > 8 else { return nil }
        let base = payload.startIndex
        let indicator = payload[base..<(base + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return (indicator, payload.subdata(in: (base + 8)..<payload.endIndex))
    }

    /// Los tipos de átomo presentes en `ilst`, para comprobar que el
    /// escritor no tiró los que no son suyos.
    static func ilstAtomTypes(from data: Data) -> [String] {
        guard let range = ilstRange(in: data) else { return [] }
        return readBoxes(in: data, range: range).map(\.type)
    }

    private static func numberAtom(_ type: String, in data: Data) -> Int? {
        guard let payload = rawAtomPayload(type, in: data), payload.count >= 12 else { return nil }
        let base = payload.startIndex
        return Int(payload[(base + 10)..<(base + 12)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
    }

    /// El contenido del `data` que hay dentro del átomo `type`.
    private static func rawAtomPayload(_ type: String, in data: Data) -> Data? {
        guard let range = ilstRange(in: data) else { return nil }
        guard let atom = readBoxes(in: data, range: range).first(where: { $0.type == type }),
              let dataBox = readBoxes(in: data, range: atom.payloadRange).first(where: { $0.type == "data" }) else {
            return nil
        }
        return data.subdata(in: dataBox.payloadRange)
    }

    private static func ilstRange(in data: Data) -> Range<Int>? {
        guard let moov = readBoxes(in: data, range: 0..<data.count).first(where: { $0.type == "moov" }),
              let udta = readBoxes(in: data, range: moov.payloadRange).first(where: { $0.type == "udta" }),
              let metaBox = readBoxes(in: data, range: udta.payloadRange).first(where: { $0.type == "meta" }) else {
            return nil
        }
        let metaChildren = (metaBox.payloadRange.lowerBound + 4)..<metaBox.payloadRange.upperBound
        return readBoxes(in: data, range: metaChildren).first(where: { $0.type == "ilst" })?.payloadRange
    }
}
