import AppKit
import AVFoundation
import Foundation
@testable import AuraStudio

/// PLAN-studio-ajustes-3.md, Fase A0 (ST-220): bytes sintéticos, reales
/// y pequeños, para cada formato de música que la ronda va a tocar --
/// con etiquetas que AVFoundation pueda leer de verdad (confirmado con
/// una prueba de lectura en `MediaStorageBaselineTests`, no solo
/// supuesto). Nunca se usa un archivo real del dueño.
enum MediaFixture {
    /// Encabezado de frame MPEG-1 Layer III, 128 kbps/44100 Hz/joint
    /// stereo, sin CRC -- el mismo patrón que ya usan
    /// `LibraryFileWorkerEquivalenceTests`/`ID3WriterTests`, repetido
    /// varias veces (con relleno en vez de audio real: no hace falta
    /// que suene, solo que un lector de tags no truene). Frame size =
    /// 144*128000/44100 ≈ 417 bytes.
    static func mp3Data(title: String, artist: String, album: String,
                       albumArtist: String, year: String, genre: String,
                       trackNumber: Int) -> Data {
        let frameHeader: [UInt8] = [0xFF, 0xFB, 0x90, 0x44]
        let frame = frameHeader + Array(repeating: UInt8(0), count: 413)
        var audio = Data()
        for _ in 0..<20 { audio += Data(frame) }
        let tag = ID3Writer.Tag(title: title, artist: artist, album: album,
                                albumArtist: albumArtist, year: year, genre: genre,
                                composer: nil, trackNumber: trackNumber)
        return ID3Writer.writing(tag, into: audio)
    }

    // MARK: - FLAC

    /// `fLaC` + STREAMINFO (obligatorio, primero) + VORBIS_COMMENT, sin
    /// frames de audio -- confirmado en un spike aparte (fuera de este
    /// repo) que `AVURLAsset.load(.metadata)` los lee igual (keySpace
    /// "vorb"); `duration` sale en 0 porque `totalSamples` se declara
    /// en 0, que es honesto: no hay audio real, solo etiquetas.
    static func flacData(title: String, artist: String, album: String,
                        albumArtist: String, year: String, genre: String,
                        trackNumber: Int) -> Data {
        var out: [UInt8] = Array("fLaC".utf8)
        let streamInfo = makeFLACStreamInfo(sampleRate: 44100, channels: 2, bitsPerSample: 16, totalSamples: 0)
        let comments = [
            "TITLE": title, "ARTIST": artist, "ALBUM": album,
            "ALBUMARTIST": albumArtist, "DATE": year, "GENRE": genre,
            "TRACKNUMBER": String(trackNumber),
        ]
        let vorbis = makeVorbisCommentBlock(vendor: "AuraStudioTest", comments: comments)

        out.append(0x00) // STREAMINFO: not last, type 0
        out += u24be(UInt32(streamInfo.count))
        out += streamInfo

        out.append(0x80 | 0x04) // VORBIS_COMMENT: last, type 4
        out += u24be(UInt32(vorbis.count))
        out += vorbis

        return Data(out)
    }

    private static func u24be(_ v: UInt32) -> [UInt8] {
        [UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
    }

    private struct BitBuffer {
        var bytes: [UInt8] = []
        var current: UInt64 = 0
        var currentBits = 0
        mutating func write(_ value: UInt64, width: Int) {
            current = (current << UInt64(width)) | (value & ((UInt64(1) << UInt64(width)) - 1))
            currentBits += width
            while currentBits >= 8 {
                let shift = currentBits - 8
                bytes.append(UInt8((current >> UInt64(shift)) & 0xFF))
                currentBits -= 8
            }
        }
        mutating func finish() -> [UInt8] {
            if currentBits > 0 {
                bytes.append(UInt8((current << UInt64(8 - currentBits)) & 0xFF))
                currentBits = 0
            }
            return bytes
        }
    }

    private static func makeFLACStreamInfo(sampleRate: UInt32, channels: UInt32,
                                            bitsPerSample: UInt32, totalSamples: UInt64) -> [UInt8] {
        var buffer = BitBuffer()
        buffer.write(4096, width: 16) // min block size
        buffer.write(4096, width: 16) // max block size
        buffer.write(0, width: 24) // min frame size (0 = desconocido)
        buffer.write(0, width: 24) // max frame size (0 = desconocido)
        buffer.write(UInt64(sampleRate), width: 20)
        buffer.write(UInt64(channels - 1), width: 3)
        buffer.write(UInt64(bitsPerSample - 1), width: 5)
        buffer.write(totalSamples, width: 36)
        return buffer.finish() + Array(repeating: UInt8(0), count: 16) // MD5 en cero
    }

    private static func makeVorbisCommentBlock(vendor: String, comments: [String: String]) -> [UInt8] {
        var data: [UInt8] = []
        func writeLE32(_ v: UInt32) {
            data.append(UInt8(v & 0xFF)); data.append(UInt8((v >> 8) & 0xFF))
            data.append(UInt8((v >> 16) & 0xFF)); data.append(UInt8((v >> 24) & 0xFF))
        }
        let vendorBytes = Array(vendor.utf8)
        writeLE32(UInt32(vendorBytes.count))
        data += vendorBytes
        writeLE32(UInt32(comments.count))
        for (key, value) in comments.sorted(by: { $0.key < $1.key }) {
            let entryBytes = Array("\(key)=\(value)".utf8)
            writeLE32(UInt32(entryBytes.count))
            data += entryBytes
        }
        return data
    }

    // MARK: - M4A

    /// `AVAssetWriter` real con una pista AAC de silencio (0,1 s) --
    /// AVFoundation no da forma de escribir M4A a mano de otro modo, y
    /// esto SÍ produce átomos iTunes reales, legibles por
    /// `AVURLAsset.load(.metadata)` (confirmado en el mismo spike que
    /// FLAC). Escribe a un archivo temporal propio (AVAssetWriter no
    /// puede escribir a un `Data` en memoria) y lo borra al terminar.
    static func m4aData(title: String, artist: String, album: String) async throws -> Data {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediaFixture-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: url) }

        let writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 64000,
        ]
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        input.expectsMediaDataInRealTime = false
        writer.add(input)
        writer.metadata = [
            metadataItem(.commonKeyTitle, value: title),
            metadataItem(.commonKeyArtist, value: artist),
            metadataItem(.commonKeyAlbumName, value: album),
        ]

        guard writer.startWriting() else { throw MediaFixtureError.writerFailed(writer.error) }
        writer.startSession(atSourceTime: .zero)

        guard let pcmFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 2, interleaved: false),
              let pcmBuffer = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: 4410),
              let formatDesc = pcmFormat.formatDescription as CMAudioFormatDescription? else {
            throw MediaFixtureError.pcmSetupFailed
        }
        pcmBuffer.frameLength = 4410 // 0,1 s de silencio
        if let channelData = pcmBuffer.floatChannelData {
            for channel in 0..<2 { for frame in 0..<4410 { channelData[channel][frame] = 0 } }
        }

        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 44100),
                                        presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        var sampleBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreate(allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: false,
                                          makeDataReadyCallback: nil, refcon: nil, formatDescription: formatDesc,
                                          sampleCount: 4410, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                                          sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sampleBuffer)
        guard status == noErr, let sampleBuffer else { throw MediaFixtureError.sampleBufferFailed }
        guard CMSampleBufferSetDataBufferFromAudioBufferList(sampleBuffer, blockBufferAllocator: kCFAllocatorDefault,
                                                              blockBufferMemoryAllocator: kCFAllocatorDefault, flags: 0,
                                                              bufferList: pcmBuffer.mutableAudioBufferList) == noErr else {
            throw MediaFixtureError.sampleBufferFailed
        }

        while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 5_000_000) }
        input.append(sampleBuffer)
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw MediaFixtureError.writerFailed(writer.error) }

        return try Data(contentsOf: url)
    }

    private static func metadataItem(_ key: AVMetadataKey, value: String) -> AVMutableMetadataItem {
        let item = AVMutableMetadataItem()
        item.keySpace = .common
        item.key = key as (NSCopying & NSObjectProtocol)
        item.value = value as NSString
        return item
    }

    enum MediaFixtureError: Error {
        case writerFailed(Error?)
        case pcmSetupFailed
        case sampleBufferFailed
    }

    // MARK: - WAV

    /// RIFF/WAVE PCM mínimo (44 bytes de cabecera + una fracción de
    /// segundo de silencio real) -- ni la producción actual ni este
    /// formato dependen de que el archivo lleve etiquetas propias
    /// (D-037: WAV nunca las recibe), así que no hace falta un chunk
    /// `LIST/INFO` para que la medición de A0 tenga sentido.
    static func wavData(sampleRate: UInt32 = 44100, channels: UInt16 = 2, seconds: Double = 0.1) -> Data {
        let bitsPerSample: UInt16 = 16
        let frameCount = Int(Double(sampleRate) * seconds)
        let dataSize = UInt32(frameCount * Int(channels) * Int(bitsPerSample / 8))
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)

        var data = Data()
        data += Data("RIFF".utf8)
        data += withUnsafeBytes(of: UInt32(36 + dataSize).littleEndian) { Data($0) }
        data += Data("WAVE".utf8)
        data += Data("fmt ".utf8)
        data += withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) }
        data += withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) } // PCM
        data += withUnsafeBytes(of: channels.littleEndian) { Data($0) }
        data += withUnsafeBytes(of: sampleRate.littleEndian) { Data($0) }
        data += withUnsafeBytes(of: byteRate.littleEndian) { Data($0) }
        data += withUnsafeBytes(of: blockAlign.littleEndian) { Data($0) }
        data += withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) }
        data += Data("data".utf8)
        data += withUnsafeBytes(of: dataSize.littleEndian) { Data($0) }
        data += Data(repeating: 0, count: Int(dataSize)) // silencio real

        return data
    }

    // MARK: - Video y fotos (fixture de biblioteca completa, ST-220)

    /// JPEG mínimo (cabecera + relleno) -- el mismo patrón que ya usan
    /// las pruebas de rendimiento (`AlbumsGridPerformanceBaselineTests`)
    /// para carátulas/fotos; decodifica de verdad.
    static func jpegData(seed: UInt8) -> Data {
        let side = 32
        var buffer = [UInt8](repeating: seed, count: side * side * 4)
        for i in buffer.indices { buffer[i] = buffer[i] &+ UInt8(i % 251) }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: &buffer, width: side, height: side,
                                      bitsPerComponent: 8, bytesPerRow: side * 4, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let cgImage = context.makeImage(),
              let rep = NSBitmapImageRep(cgImage: cgImage).representation(using: .jpeg, properties: [.compressionFactor: 0.6])
        else { fatalError("MediaFixture: no se pudo generar el JPEG sintético") }
        return rep
    }

    /// MOV real y corto (0,2 s), un solo cuadro de color sólido --
    /// alcanza para que la biblioteca lo trate como video de verdad
    /// (kind == .video, AVFoundation puede abrirlo) sin pagar un
    /// encoder de video completo.
    static func movData() async throws -> Data {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediaFixture-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: url) }

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let width = 32, height = 32
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width, AVVideoHeightKey: height,
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw MediaFixtureError.writerFailed(writer.error) }
        writer.startSession(atSourceTime: .zero)

        guard let pixelBufferPool = adaptor.pixelBufferPool else { throw MediaFixtureError.pcmSetupFailed }
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferPool, &pixelBuffer)
        guard let pixelBuffer else { throw MediaFixtureError.pcmSetupFailed }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
            memset(base, 0x80, CVPixelBufferGetDataSize(pixelBuffer))
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

        while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 5_000_000) }
        adaptor.append(pixelBuffer, withPresentationTime: .zero)
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw MediaFixtureError.writerFailed(writer.error) }

        return try Data(contentsOf: url)
    }
}
