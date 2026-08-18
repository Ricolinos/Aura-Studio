import Foundation
import AVFoundation

/// Lee las tags nativas de un archivo de audio para TODOS los formatos
/// que Aura Studio acepta (mp3/m4a/flac/aiff/aif/wav), via AVFoundation.
///
/// Reemplaza a `ID3Writer.readTag` como lector de produccion (ver
/// PLAN-studio-ux.md §2): ese parser solo entendia el subconjunto de
/// ID3v2.3 que el propio `ID3Writer` escribe (UTF-16 con BOM, `TYER`,
/// tamaño de frame no-synchsafe) y solo se invocaba para `.mp3` -- con
/// ID3v2.4 real (el default de ffmpeg/MusicBrainz Picard/yt-dlp, que
/// usa UTF-8 y `TDRC`) perdia año/pista/portada y corrompia acentos, y
/// no leia FLAC/M4A/AIFF en absoluto. `ID3Writer.readTag` sigue
/// existiendo solo para verificar el round-trip de lo que el propio
/// `ID3Writer` escribe (sus tests).
///
/// Se itera `.metadata` (todos los items), no `.commonMetadata`: para
/// Vorbis comments (FLAC) los items individuales SI traen `commonKey`
/// poblado aunque `AVAsset.commonMetadata` venga vacio -- verificado
/// contra archivos reales generados con ffmpeg.
enum LocalTagReader {
    static func readTag(from url: URL) async -> TrackMetadata {
        let asset = AVURLAsset(url: url)
        var metadata = TrackMetadata()

        let items = (try? await asset.load(.metadata)) ?? []
        for item in items {
            guard let value = try? await item.load(.value) else { continue }
            apply(item: item, value: value, to: &metadata)
        }

        // METADATA_BLOCK_PICTURE de FLAC: AVFoundation no lo expone via
        // `commonKeyArtwork` (verificado) -- unico caso que necesita un
        // parser propio del contenedor.
        if metadata.coverArtData == nil, url.pathExtension.lowercased() == "flac" {
            metadata.coverArtData = readFLACPicture(from: url)
        }

        // ST-012 (contrato SS2): la caratula de CARPETA (`cover.jpg`,
        // `folder.jpg`... -- mismos nombres que busca el firmware) es un
        // asset asociado a la cancion, no una entrada de Imagenes: si la
        // pista no trae portada embebida, se toma de ahi. Es lo que hace
        // que un album arrastrado con su cover.jpg conserve la portada
        // aunque el importador ya no lo cuente como foto.
        if metadata.coverArtData == nil, let cover = CoverArtAssets.folderCover(near: url) {
            metadata.coverArtData = try? Data(contentsOf: cover)
        }

        return metadata
    }

    private static func apply(item: AVMetadataItem, value: Any, to metadata: inout TrackMetadata) {
        // `commonKey` cubre lo mismo sin importar el contenedor (ID3,
        // iTunes, Vorbis) -- se prueba primero porque es la via mas
        // confiable.
        if let commonKey = item.commonKey {
            switch commonKey {
            case .commonKeyTitle:
                metadata.title = metadata.title ?? stringValue(value)
            case .commonKeyArtist:
                metadata.artist = metadata.artist ?? stringValue(value)
            case .commonKeyAlbumName:
                metadata.album = metadata.album ?? stringValue(value)
            case .commonKeyType:
                metadata.genre = metadata.genre ?? stringValue(value)
            case .commonKeyCreator:
                metadata.composer = metadata.composer ?? stringValue(value)
            case .commonKeyCreationDate:
                metadata.year = metadata.year ?? yearPrefix(stringValue(value))
            case .commonKeyArtwork:
                metadata.coverArtData = metadata.coverArtData ?? (value as? Data)
            default:
                break
            }
        }

        // Campos que ID3/Vorbis exponen pero que AVFoundation NO mapea
        // a un `commonKey`: album-artist, año y pista de ID3 (`TPE2`/
        // `TDRC`/`TYER`/`TRCK`), y sus equivalentes Vorbis
        // (`ALBUMARTIST`/`DATE`/`TRACKNUMBER`).
        if item.keySpace == .id3, let key = item.key as? String {
            switch key {
            case "TPE2":
                metadata.albumArtist = metadata.albumArtist ?? stringValue(value)
            case "TDRC", "TYER":
                metadata.year = metadata.year ?? yearPrefix(stringValue(value))
            case "TRCK":
                metadata.trackNumber = metadata.trackNumber ?? trackNumber(fromSlashed: stringValue(value))
            case "TCOM":
                metadata.composer = metadata.composer ?? stringValue(value)
            case "TCON":
                metadata.genre = metadata.genre ?? stringValue(value)
            default:
                break
            }
        } else if item.keySpace?.rawValue == "vorb", let key = item.key as? String {
            switch key.uppercased() {
            case "ALBUMARTIST":
                metadata.albumArtist = metadata.albumArtist ?? stringValue(value)
            case "DATE":
                metadata.year = metadata.year ?? yearPrefix(stringValue(value))
            case "TRACKNUMBER":
                metadata.trackNumber = metadata.trackNumber ?? trackNumber(fromSlashed: stringValue(value))
            case "COMPOSER":
                metadata.composer = metadata.composer ?? stringValue(value)
            case "GENRE":
                metadata.genre = metadata.genre ?? stringValue(value)
            default:
                break
            }
        } else if item.keySpace == .iTunes, let code = fourCharCode(from: item.key) {
            // Los items de iTunes/MP4 (`©day`, `©wrt`, `©gen`, `aART`,
            // `trkn`) traen `key` como un FourCharCode numerico (OSType),
            // no como String -- se decodifica a mano en vez de depender
            // de constantes `AVMetadataIdentifier` (evita adivinar
            // nombres exactos de simbolos).
            switch code {
            case "aART":
                metadata.albumArtist = metadata.albumArtist ?? stringValue(value)
            case "\u{a9}day":
                metadata.year = metadata.year ?? yearPrefix(stringValue(value))
            case "\u{a9}wrt":
                metadata.composer = metadata.composer ?? stringValue(value)
            case "\u{a9}gen":
                metadata.genre = metadata.genre ?? stringValue(value)
            case "trkn":
                metadata.trackNumber = metadata.trackNumber ?? trackNumber(fromiTunesData: value as? Data)
            default:
                break
            }
        }
    }

    private static func stringValue(_ value: Any) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func yearPrefix(_ string: String?) -> String? {
        guard let string, string.count >= 4 else { return string }
        return String(string.prefix(4))
    }

    /// `"3/12"` (pista/total, lo que escriben casi todos los
    /// etiquetadores) -> `3`. `Int("3/12")` a secas da `nil` -- este es
    /// el bug concreto que perdia el numero de pista con `ID3Writer.
    /// readTag` incluso en ID3v2.3.
    private static func trackNumber(fromSlashed string: String?) -> Int? {
        guard let string else { return nil }
        let firstPart = string.split(separator: "/").first.map(String.init) ?? string
        return Int(firstPart.trimmingCharacters(in: .whitespaces))
    }

    /// Atomo `trkn` de iTunes: 8 bytes, `[reservado(2)][pista(2)][total(2)][reservado(2)]`, big-endian.
    private static func trackNumber(fromiTunesData data: Data?) -> Int? {
        guard let data, data.count >= 4 else { return nil }
        let bytes = [UInt8](data)
        let track = Int(bytes[2]) << 8 | Int(bytes[3])
        return track > 0 ? track : nil
    }

    /// Decodifica un FourCharCode (OSType) de iTunes/MP4 a los 4
    /// caracteres del atomo real (`©day`, `trkn`, `aART`...) -- el byte
    /// alto de `©` es `0xA9` en Mac OS Roman, la codificacion clasica de
    /// QuickTime para estos nombres de atomo.
    private static func fourCharCode(from key: Any?) -> String? {
        guard let number = key as? NSNumber else { return nil }
        let code = UInt32(bitPattern: number.int32Value)
        guard code > 0 else { return nil }
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xFF), UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF), UInt8(code & 0xFF),
        ]
        return String(bytes: bytes, encoding: .macOSRoman)
    }

    // MARK: - METADATA_BLOCK_PICTURE de FLAC

    /// Parser minimo de bloques FLAC (`fLaC` + cabecera de 4 bytes por
    /// bloque + payload) hasta encontrar un bloque PICTURE (tipo 6, ver
    /// la spec de FLAC). Prefiere el tipo 3 (front cover); si no hay
    /// ninguno de tipo 3, devuelve el primero que encuentre.
    private static func readFLACPicture(from url: URL) -> Data? {
        guard let data = try? Data(contentsOf: url), data.count > 4,
              data.prefix(4).elementsEqual([0x66, 0x4C, 0x61, 0x43]) else { return nil }

        var offset = 4
        var fallback: Data?
        while offset + 4 <= data.count {
            let headerByte = data[offset]
            let isLast = (headerByte & 0x80) != 0
            let blockType = headerByte & 0x7F
            let length = Int(data[offset + 1]) << 16 | Int(data[offset + 2]) << 8 | Int(data[offset + 3])
            let blockStart = offset + 4
            guard blockStart + length <= data.count else { break }

            if blockType == 6, let picture = parsePictureBlock(data.subdata(in: blockStart..<(blockStart + length))) {
                if picture.type == 3 { return picture.data }
                if fallback == nil { fallback = picture.data }
            }

            offset = blockStart + length
            if isLast { break }
        }
        return fallback
    }

    private static func parsePictureBlock(_ block: Data) -> (type: UInt32, data: Data)? {
        var cursor = 0
        func readUInt32() -> UInt32? {
            guard cursor + 4 <= block.count else { return nil }
            let bytes = block.subdata(in: cursor..<(cursor + 4))
            cursor += 4
            return bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        }

        guard let pictureType = readUInt32() else { return nil }
        guard let mimeLength = readUInt32(), cursor + Int(mimeLength) <= block.count else { return nil }
        cursor += Int(mimeLength)
        guard let descriptionLength = readUInt32(), cursor + Int(descriptionLength) <= block.count else { return nil }
        cursor += Int(descriptionLength)
        guard readUInt32() != nil else { return nil } // width
        guard readUInt32() != nil else { return nil } // height
        guard readUInt32() != nil else { return nil } // color depth
        guard readUInt32() != nil else { return nil } // colores indexados
        guard let dataLength = readUInt32(), cursor + Int(dataLength) <= block.count else { return nil }

        let imageData = block.subdata(in: cursor..<(cursor + Int(dataLength)))
        return (pictureType, imageData)
    }
}
