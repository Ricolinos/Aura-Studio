import Foundation

/// ST-222 (PLAN-studio-ajustes-3.md, Fase A2): escritor nativo de
/// etiquetas M4A/ALAC -- los átomos `ilst` de iTunes, que viven en
/// `moov/udta/meta/ilst`.
///
/// **Por qué es el más delicado de los tres.** En MP3 la tag se antepone
/// y no toca nada; en FLAC los metadatos se pueden crecer o encoger
/// libremente porque la tabla de búsqueda mide **desde el primer
/// fotograma**. En M4A no: la tabla de fragmentos (`stco`/`co64`) guarda
/// **desplazamientos absolutos dentro del archivo**. Si `moov` está antes
/// de `mdat` y crece, todo el audio se corre hacia adelante y esos
/// números quedan apuntando al lugar equivocado -- el archivo sigue
/// pareciendo válido, abre sin error, y suena mal o no suena. Por eso
/// cada desplazamiento se corrige acá.
///
/// La corrección es por desplazamiento y no por "moov está antes de
/// mdat": se mueve lo que estaba **después** del `moov` original y no lo
/// que estaba antes. Así queda bien también el archivo raro que tiene
/// `mdat` a los dos lados, sin ningún caso especial.
///
/// **Qué se toca y qué no.** Solo los átomos del juego que gobierna el
/// catálogo. Cualquier otro átomo de `ilst` que ya estuviera (los que
/// pone iTunes, agrupaciones, identificadores) pasa **intacto**: no es
/// nuestro y no lo entendemos, así que no lo tiramos. `mdat` se copia
/// byte a byte.
enum MP4TagWriter {
    enum WriterError: Error, Equatable {
        /// No se pudo recorrer la estructura de cajas: el archivo está
        /// truncado o no es ISO-BMFF. No se reescribe nada.
        case malformedBoxes
        /// Sin `moov` no hay dónde poner las etiquetas.
        case missingMoov
    }

    /// Los átomos que gobierna el catálogo. Se reemplazan enteros; el
    /// resto de `ilst` no se toca.
    private static let managedAtoms: Set<String> = [
        "\u{A9}nam", "\u{A9}ART", "\u{A9}alb", "aART",
        "\u{A9}day", "\u{A9}gen", "\u{A9}wrt", "trkn", "disk", "covr",
    ]

    /// Tipos de caja que contienen otras cajas y hay que recorrer para
    /// llegar a `stco`/`co64`.
    private static let chunkOffsetContainers: Set<String> = ["trak", "mdia", "minf", "stbl", "edts"]

    private struct ParsedBox {
        let type: String
        let range: Range<Int>        // la caja entera, con su cabecera
        let payloadRange: Range<Int> // solo el contenido
    }

    // MARK: - Entrada

    static func write(_ tag: AudioTag, toFileAt url: URL) throws {
        let original = try Data(contentsOf: url)
        let updated = try writing(tag, into: original)
        // Un archivo que no cambia no se reescribe (misma razón que en
        // FLAC: no moverle la fecha ni hacer que el sync lo recopie).
        guard updated != original else { return }
        try updated.write(to: url, options: .atomic)
    }

    static func writing(_ tag: AudioTag, into data: Data) throws -> Data {
        let topLevel = try parseBoxes(in: data, range: 0..<data.count)
        guard let moovIndex = topLevel.firstIndex(where: { $0.type == "moov" }) else {
            throw WriterError.missingMoov
        }
        let moov = topLevel[moovIndex]

        var newMoov = box("moov", payload: try rebuildMoovPayload(data, moov.payloadRange, tag))
        let delta = newMoov.count - moov.range.count
        if delta != 0 {
            patchChunkOffsets(in: &newMoov, range: 8..<newMoov.count,
                              movedFrom: moov.range.lowerBound, by: delta)
        }

        var output = Data()
        for (index, boxToCopy) in topLevel.enumerated() {
            output += index == moovIndex ? newMoov : data.subdata(in: boxToCopy.range)
        }
        return output
    }

    // MARK: - Reconstrucción, de afuera hacia adentro

    private static func rebuildMoovPayload(_ data: Data, _ range: Range<Int>, _ tag: AudioTag) throws -> Data {
        var output = Data()
        var wroteUdta = false
        for child in try parseBoxes(in: data, range: range) {
            if child.type == "udta" {
                output += box("udta", payload: try rebuildUdtaPayload(data, child.payloadRange, tag))
                wroteUdta = true
            } else {
                output += data.subdata(in: child.range)
            }
        }
        if !wroteUdta {
            output += box("udta", payload: try rebuildUdtaPayload(data, nil, tag))
        }
        return output
    }

    private static func rebuildUdtaPayload(_ data: Data, _ range: Range<Int>?, _ tag: AudioTag) throws -> Data {
        var output = Data()
        var wroteMeta = false
        if let range {
            for child in try parseBoxes(in: data, range: range) {
                if child.type == "meta" {
                    output += try rebuildMetaBox(data, child.payloadRange, tag)
                    wroteMeta = true
                } else {
                    output += data.subdata(in: child.range)
                }
            }
        }
        if !wroteMeta {
            output += fullBox("meta", payload: mdirHandlerBox() + box("ilst", payload: ilstPayload(nil, nil, tag)))
        }
        return output
    }

    /// `meta` es la única caja del camino que lleva 4 bytes de
    /// versión+banderas antes de sus hijos... **casi siempre**. Hay
    /// archivos de QuickTime donde no los lleva, y leerlos como si los
    /// llevara desplaza todo 4 bytes y no se encuentra nada. Se detecta
    /// probando: si los hijos cierran exactamente al final del contenido
    /// leyendo desde +4, es una caja de versión completa; si cierran
    /// leyendo desde +0, no lo es.
    private static func rebuildMetaBox(_ data: Data, _ payloadRange: Range<Int>, _ tag: AudioTag) throws -> Data {
        let isFullBox = boxesFitExactly(data, (payloadRange.lowerBound + 4)..<payloadRange.upperBound)
        let childrenRange = isFullBox ? (payloadRange.lowerBound + 4)..<payloadRange.upperBound : payloadRange
        let versionAndFlags = isFullBox
            ? data.subdata(in: payloadRange.lowerBound..<(payloadRange.lowerBound + 4))
            : Data()

        var children = Data()
        var wroteIlst = false
        var hasHandler = false
        for child in try parseBoxes(in: data, range: childrenRange) {
            switch child.type {
            case "ilst":
                children += box("ilst", payload: ilstPayload(data, child.payloadRange, tag))
                wroteIlst = true
            case "hdlr":
                hasHandler = true
                children += data.subdata(in: child.range)
            default:
                children += data.subdata(in: child.range)
            }
        }
        // El `hdlr` con handler `mdir` es lo que le dice a iTunes (y a
        // AVFoundation) que este `meta` contiene etiquetas y no otra
        // cosa. Sin él, el `ilst` está pero nadie lo mira. Va primero.
        if !hasHandler { children = mdirHandlerBox() + children }
        if !wroteIlst { children += box("ilst", payload: ilstPayload(nil, nil, tag)) }

        return isFullBox
            ? box("meta", payload: versionAndFlags + children)
            : box("meta", payload: children)
    }

    private static func ilstPayload(_ data: Data?, _ range: Range<Int>?, _ tag: AudioTag) -> Data {
        var output = Data()
        // Lo que ya estaba y no es nuestro se conserva tal cual.
        if let data, let range, let existing = try? parseBoxes(in: data, range: range) {
            for atom in existing where !managedAtoms.contains(atom.type) {
                output += data.subdata(in: atom.range)
            }
        }
        func addText(_ type: String, _ value: String?) {
            guard let value, !value.isEmpty else { return }
            output += box(type, payload: dataBox(typeIndicator: 1, value: Data(value.utf8)))
        }
        addText("\u{A9}nam", tag.title)
        addText("\u{A9}ART", tag.artist)
        addText("\u{A9}alb", tag.album)
        addText("aART", tag.albumArtist)
        addText("\u{A9}day", tag.year)
        addText("\u{A9}gen", tag.genre)
        addText("\u{A9}wrt", tag.composer)
        if let track = tag.trackNumber, track > 0 {
            // `trkn` son 8 bytes: relleno, número, total, relleno. El
            // total va en 0 porque el catálogo no lo tiene.
            var value = Data([0, 0])
            value += be16(UInt16(clamping: track))
            value += be16(0)
            value += Data([0, 0])
            output += box("trkn", payload: dataBox(typeIndicator: 0, value: value))
        }
        if let disc = tag.discNumber, disc > 0 {
            var value = Data([0, 0])
            value += be16(UInt16(clamping: disc))
            value += be16(0)
            output += box("disk", payload: dataBox(typeIndicator: 0, value: value))
        }
        if let cover = tag.coverArtData, !cover.isEmpty {
            // 13 = JPEG, 14 = PNG. No es un adorno: es cómo el lector
            // sabe qué está decodificando.
            let indicator: UInt32 = tag.coverArtMIMEType.lowercased().contains("png") ? 14 : 13
            output += box("covr", payload: dataBox(typeIndicator: indicator, value: cover))
        }
        return output
    }

    // MARK: - Desplazamientos de fragmento

    /// Corrige `stco`/`co64` dentro de `data`, sumando `delta` **solo** a
    /// los desplazamientos que apuntaban después de `movedFrom` -- que
    /// son exactamente los bytes que se movieron al cambiar de tamaño el
    /// `moov`. Los que apuntaban antes no se tocan.
    ///
    /// Corregir no cambia ningún tamaño, así que se puede hacer sobre los
    /// bytes ya armados.
    private static func patchChunkOffsets(in data: inout Data, range: Range<Int>,
                                          movedFrom: Int, by delta: Int) {
        guard let boxes = try? parseBoxes(in: data, range: range) else { return }
        for boxToVisit in boxes {
            switch boxToVisit.type {
            case "stco":
                patchOffsetTable(in: &data, payloadRange: boxToVisit.payloadRange,
                                 entryBytes: 4, movedFrom: movedFrom, by: delta)
            case "co64":
                patchOffsetTable(in: &data, payloadRange: boxToVisit.payloadRange,
                                 entryBytes: 8, movedFrom: movedFrom, by: delta)
            case let type where chunkOffsetContainers.contains(type):
                patchChunkOffsets(in: &data, range: boxToVisit.payloadRange,
                                  movedFrom: movedFrom, by: delta)
            default:
                continue
            }
        }
    }

    private static func patchOffsetTable(in data: inout Data, payloadRange: Range<Int>,
                                         entryBytes: Int, movedFrom: Int, by delta: Int) {
        // 4 bytes de versión+banderas, 4 de cantidad de entradas, y
        // después la tabla.
        let tableStart = payloadRange.lowerBound + 8
        guard tableStart <= payloadRange.upperBound else { return }
        let count = Int(readBE(data, payloadRange.lowerBound + 4, 4))
        for index in 0..<count {
            let entryStart = tableStart + index * entryBytes
            guard entryStart + entryBytes <= payloadRange.upperBound else { return }
            let value = Int(readBE(data, entryStart, entryBytes))
            guard value >= movedFrom else { continue }
            writeBE(&data, UInt64(value + delta), at: entryStart, bytes: entryBytes)
        }
    }

    // MARK: - Recorrido de cajas

    private static func parseBoxes(in data: Data, range: Range<Int>) throws -> [ParsedBox] {
        var boxes: [ParsedBox] = []
        var offset = range.lowerBound
        while offset + 8 <= range.upperBound {
            let size32 = Int(readBE(data, offset, 4))
            // `.isoLatin1`, no `.ascii`: los átomos de iTunes empiezan
            // con 0xA9 (©), que no es ASCII -- y `.ascii` devuelve nil
            // para los cuatro bytes enteros, no solo para ese uno.
            let type = String(data: data.subdata(in: (offset + 4)..<(offset + 8)), encoding: .isoLatin1) ?? ""
            let size: Int
            let headerLength: Int
            if size32 == 1 {
                // ISO-BMFF admite tamaño de 64 bits: el real va en los 8
                // bytes que siguen al tipo. El `mdat` que escribe
                // `AVAssetWriter` usa esta forma.
                guard offset + 16 <= range.upperBound else { throw WriterError.malformedBoxes }
                size = Int(readBE(data, offset + 8, 8))
                headerLength = 16
            } else if size32 == 0 {
                // "hasta el final del contenedor".
                size = range.upperBound - offset
                headerLength = 8
            } else {
                size = size32
                headerLength = 8
            }
            guard size >= headerLength, offset + size <= range.upperBound else {
                throw WriterError.malformedBoxes
            }
            boxes.append(ParsedBox(type: type,
                                   range: offset..<(offset + size),
                                   payloadRange: (offset + headerLength)..<(offset + size)))
            offset += size
        }
        guard offset == range.upperBound else { throw WriterError.malformedBoxes }
        return boxes
    }

    /// `true` si las cajas de `range` lo cubren exactamente. Es lo que
    /// distingue un `meta` de versión completa de uno que no lo es.
    private static func boxesFitExactly(_ data: Data, _ range: Range<Int>) -> Bool {
        guard range.lowerBound <= range.upperBound else { return false }
        guard let boxes = try? parseBoxes(in: data, range: range) else { return false }
        return !boxes.isEmpty
    }

    // MARK: - Construcción de cajas

    private static func box(_ type: String, payload: Data) -> Data {
        var out = be32(UInt32(payload.count + 8))
        out += Data(type.unicodeScalars.map { UInt8($0.value & 0xFF) })
        out += payload
        return out
    }

    private static func fullBox(_ type: String, payload: Data) -> Data {
        box(type, payload: Data([0, 0, 0, 0]) + payload)
    }

    private static func dataBox(typeIndicator: UInt32, value: Data) -> Data {
        box("data", payload: be32(typeIndicator) + be32(0) + value)
    }

    /// El `hdlr` que marca este `meta` como contenedor de etiquetas de
    /// iTunes (`mdir` / `appl`).
    private static func mdirHandlerBox() -> Data {
        var payload = Data([0, 0, 0, 0]) // versión + banderas
        payload += Data([0, 0, 0, 0])    // predefinido
        payload += Data("mdir".utf8)
        payload += Data("appl".utf8)
        payload += Data(repeating: 0, count: 9) // reservado + nombre vacío
        return box("hdlr", payload: payload)
    }

    // MARK: - Enteros

    private static func readBE(_ data: Data, _ offset: Int, _ bytes: Int) -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<bytes {
            value = (value << 8) | UInt64(data[data.startIndex + offset + index])
        }
        return value
    }

    private static func writeBE(_ data: inout Data, _ value: UInt64, at offset: Int, bytes: Int) {
        for index in 0..<bytes {
            let shift = UInt64(8 * (bytes - 1 - index))
            data[data.startIndex + offset + index] = UInt8((value >> shift) & 0xFF)
        }
    }

    private static func be32(_ value: UInt32) -> Data {
        Data([UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
              UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)])
    }

    private static func be16(_ value: UInt16) -> Data {
        Data([UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)])
    }
}
