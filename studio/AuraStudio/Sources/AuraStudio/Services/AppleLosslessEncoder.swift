import AVFoundation
import Foundation

/// ST-223: convierte WAV y AIFF a **ALAC** dentro de un `.m4a`, con el
/// codificador que trae el sistema -- sin ffmpeg y sin perder una sola
/// muestra.
///
/// **Por qué ALAC y no MP3.** Convertir a MP3 bajo un ajuste llamado
/// "Mantener formato original" era perder calidad a escondidas. ALAC es
/// sin pérdida de verdad, lo codifica AudioToolbox (MP3 **no**: el
/// sistema lo decodifica pero no lo codifica, comprobado enumerando los
/// codificadores disponibles) y el resultado queda etiquetable con
/// `MP4TagWriter` de A2. Windows hace lo mismo con
/// `MediaEncodingProfile.CreateAlac`, así que el formato es el mismo en
/// las dos plataformas.
enum AppleLosslessEncoder {
    enum EncodeError: LocalizedError, Equatable {
        /// Un AIFF-C cuya compresión no es "ninguna": los datos ya
        /// vienen codificados (IMA4, µ-law, incluso MP3). Tratarlos como
        /// PCM produciría ruido, así que se dice que no.
        case compressedAIFFNotSupported(String)
        case noAudioTrack
        /// El archivo se abre pero declara un formato imposible (tasa de
        /// muestreo 0, cero canales). Pasa con archivos truncados o con
        /// cabeceras mal escritas.
        case unusableSourceFormat(String)
        case readerFailed(String)
        case writerFailed(String)

        var errorDescription: String? {
            switch self {
            case .compressedAIFFNotSupported(let compression):
                return "Este AIFF está comprimido (\(compression)) y Aura Studio no lo convierte. Expórtalo como AIFF o WAV sin comprimir y vuelve a importarlo."
            case .noAudioTrack:
                return "El archivo no tiene pista de audio que convertir."
            case .unusableSourceFormat(let detail):
                return "El archivo declara un formato de audio que no se puede usar (\(detail)). Puede estar truncado o mal escrito."
            case .readerFailed(let message):
                return "No se pudo leer el audio para convertirlo: \(message)"
            case .writerFailed(let message):
                return "No se pudo escribir el archivo convertido: \(message)"
            }
        }
    }

    /// Convierte `input` a ALAC en `output` (que debe terminar en
    /// `.m4a` y **no** existir todavía).
    ///
    /// La profundidad se fija en 16 bits cuando el origen trae menos --
    /// un WAV de 8 bits sube a 16, que es lo mínimo que ALAC codifica.
    /// Un origen de 24 bits se conserva en 24.
    static func encode(input: URL, output: URL) async throws {
        if ["aiff", "aif"].contains(input.pathExtension.lowercased()) {
            try rejectCompressedAIFF(at: input)
        }

        let asset = AVURLAsset(url: input)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw EncodeError.noAudioTrack
        }
        let (sampleRate, channels, sourceBitDepth) = try await sourceFormat(of: track)
        let bitDepth = max(sourceBitDepth, 16)
        // `AVAssetWriterInput` lanza una **excepción de Objective-C** con
        // valores fuera de rango, y eso no se puede atrapar desde Swift:
        // tumba el proceso. Un archivo con la cabecera mal escrita no
        // puede tirar la app, así que se comprueba antes de construirlo.
        guard sampleRate >= 8_000, sampleRate <= 192_000 else {
            throw EncodeError.unusableSourceFormat("tasa de muestreo \(Int(sampleRate)) Hz")
        }
        guard channels >= 1, channels <= 8 else {
            throw EncodeError.unusableSourceFormat("\(channels) canales")
        }

        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: bitDepth,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        reader.add(readerOutput)

        let writer = try AVAssetWriter(outputURL: output, fileType: .m4a)
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatAppleLossless,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitDepthHintKey: bitDepth,
        ])
        writerInput.expectsMediaDataInRealTime = false
        writer.add(writerInput)

        guard reader.startReading() else {
            throw EncodeError.readerFailed(reader.error?.localizedDescription ?? "desconocido")
        }
        guard writer.startWriting() else {
            throw EncodeError.writerFailed(writer.error?.localizedDescription ?? "desconocido")
        }
        writer.startSession(atSourceTime: .zero)

        while let buffer = readerOutput.copyNextSampleBuffer() {
            while !writerInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            writerInput.append(buffer)
        }
        if reader.status == .failed {
            writer.cancelWriting()
            throw EncodeError.readerFailed(reader.error?.localizedDescription ?? "desconocido")
        }
        writerInput.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw EncodeError.writerFailed(writer.error?.localizedDescription ?? "desconocido")
        }
    }

    private static func sourceFormat(of track: AVAssetTrack) async throws -> (Double, Int, Int) {
        let descriptions = try await track.load(.formatDescriptions)
        guard let description = descriptions.first,
              let basic = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee else {
            throw EncodeError.noAudioTrack
        }
        let bitDepth = basic.mBitsPerChannel > 0 ? Int(basic.mBitsPerChannel) : 16
        return (basic.mSampleRate, Int(basic.mChannelsPerFrame), bitDepth)
    }

    /// Mira el trozo `COMM` de un AIFF para saber si es un AIFF-C
    /// comprimido.
    ///
    /// AVFoundation decodifica varios de esos formatos, así que la
    /// conversión "funcionaría" -- y ahí está el problema: el resultado
    /// sería un ALAC sin pérdida **de un audio que ya perdió calidad**,
    /// vendido como "sin pérdida" y ocupando el triple. Decirlo es mejor
    /// que entregar eso en silencio.
    ///
    /// `NONE`, `sowt`, `twos`, `fl32` y `fl64` son PCM (cambian el orden
    /// de bytes o el tipo de muestra, no comprimen) y sí se aceptan.
    private static let uncompressedAIFFCompressionTypes: Set<String> = [
        "NONE", "sowt", "twos", "in24", "in32", "fl32", "fl64", "raw ", "lpcm",
    ]

    private static func rejectCompressedAIFF(at url: URL) throws {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), data.count >= 12 else { return }
        let base = data.startIndex
        guard data.subdata(in: base..<(base + 4)) == Data("FORM".utf8) else { return }
        let formType = data.subdata(in: (base + 8)..<(base + 12))
        // Un AIFF clásico (`AIFF`) nunca está comprimido; solo `AIFC` lo
        // puede estar.
        guard formType == Data("AIFC".utf8) else { return }

        var offset = 12
        while offset + 8 <= data.count {
            let chunkID = data.subdata(in: (base + offset)..<(base + offset + 4))
            let size = Int(data[(base + offset + 4)..<(base + offset + 8)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
            let payloadStart = offset + 8
            if chunkID == Data("COMM".utf8) {
                // COMM de AIFC: canales(2) muestras(4) bits(2)
                // tasa(10 bytes, coma flotante extendida) y recién ahí el
                // tipo de compresión.
                let compressionStart = payloadStart + 18
                guard compressionStart + 4 <= data.count else { return }
                let raw = data.subdata(in: (base + compressionStart)..<(base + compressionStart + 4))
                let compression = String(data: raw, encoding: .isoLatin1) ?? "????"
                guard uncompressedAIFFCompressionTypes.contains(compression) else {
                    throw EncodeError.compressedAIFFNotSupported(compression.trimmingCharacters(in: .whitespaces))
                }
                return
            }
            guard size >= 0 else { return }
            // Los trozos de IFF se alinean a byte par.
            offset = payloadStart + size + (size % 2)
        }
    }
}
