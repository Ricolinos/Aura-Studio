import XCTest
@testable import AuraStudio

/// Cubre el bug real de §2 (PLAN-studio-ux.md): `ID3Writer.readTag`
/// solo entendia ID3v2.3 UTF-16 con BOM y ni siquiera se llamaba para
/// FLAC/M4A/AIFF -- estos tests generan archivos reales con ffmpeg
/// (mismo binario que ya localiza `FFmpegLocator`, D-038) en las
/// variantes que de verdad producen los etiquetadores comunes
/// (ID3v2.4 UTF-8, ID3v2.3, FLAC/Vorbis, M4A/iTunes, AIFF) y verifican
/// que `LocalTagReader` los lee correctamente donde el lector viejo
/// fallaba. Se saltean con `XCTSkip` si ffmpeg no esta disponible,
/// mismo criterio que `LibraryPipelineIntegrationTests`.
final class LocalTagReaderTests: XCTestCase {
    private var workDir: URL!

    override func setUpWithError() throws {
        workDir = FileManager.default.temporaryDirectory.appendingPathComponent("LocalTagReaderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workDir)
    }

    private func ffmpeg() throws -> URL {
        guard let url = FFmpegLocator.locate() else {
            throw XCTSkip("ffmpeg no esta instalado (brew install ffmpeg)")
        }
        return url
    }

    @discardableResult
    private func run(_ ffmpeg: URL, _ arguments: [String]) throws -> Bool {
        let process = Process()
        process.executableURL = ffmpeg
        process.arguments = ["-y", "-loglevel", "error"] + arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw XCTSkip("ffmpeg no pudo generar el fixture de prueba")
        }
        return true
    }

    // MARK: - MP3 ID3v2.4 UTF-8 (default de ffmpeg/MusicBrainz Picard/yt-dlp)

    func testReadsID3v24UTF8WithAccentsYearAndTrackNumber() async throws {
        let ffmpeg = try ffmpeg()
        let url = workDir.appendingPathComponent("v24.mp3")
        try run(ffmpeg, [
            "-f", "lavfi", "-i", "sine=frequency=440:duration=1",
            "-metadata", "title=Canción de práctica",
            "-metadata", "artist=Ñandú y Compañía",
            "-metadata", "album=Álbum Número Uno",
            "-metadata", "album_artist=Ñandú",
            "-metadata", "date=2020",
            "-metadata", "track=3/12",
            "-metadata", "genre=Rock",
            "-metadata", "composer=Autor Ñ",
            url.path,
        ])

        let metadata = await LocalTagReader.readTag(from: url)

        XCTAssertEqual(metadata.title, "Canción de práctica", "ID3Writer.readTag daba mojibake con UTF-8 (0x03), el bug real de §2")
        XCTAssertEqual(metadata.artist, "Ñandú y Compañía")
        XCTAssertEqual(metadata.album, "Álbum Número Uno")
        XCTAssertEqual(metadata.albumArtist, "Ñandú")
        XCTAssertEqual(metadata.year, "2020", "TDRC (ID3v2.4) -- ID3Writer.readTag solo entendia TYER")
        XCTAssertEqual(metadata.trackNumber, 3, "\"3/12\" -- Int(\"3/12\") da nil, hay que partir por \"/\"")
        XCTAssertEqual(metadata.genre, "Rock")
        XCTAssertEqual(metadata.composer, "Autor Ñ")
    }

    func testReadsID3v24CoverArt() async throws {
        let ffmpeg = try ffmpeg()
        let cover = workDir.appendingPathComponent("cover.jpg")
        try run(ffmpeg, ["-f", "lavfi", "-i", "testsrc=size=64x64:rate=1", "-frames:v", "1", cover.path])

        let url = workDir.appendingPathComponent("v24_cover.mp3")
        try run(ffmpeg, [
            "-f", "lavfi", "-i", "sine=frequency=440:duration=1",
            "-i", cover.path, "-map", "0:a", "-map", "1:v", "-c:v", "copy",
            "-id3v2_version", "4",
            "-metadata:s:v", "comment=Cover (front)",
            "-metadata", "title=Con portada", "-metadata", "artist=Artista X",
            url.path,
        ])

        let metadata = await LocalTagReader.readTag(from: url)

        XCTAssertEqual(metadata.title, "Con portada")
        XCTAssertNotNil(metadata.pendingCoverData, "el frame APIC de ID3v2.4 es synchsafe -- ID3Writer.readTag lo leia como big-endian plano y perdia la portada")
        XCTAssertGreaterThan(metadata.pendingCoverData?.count ?? 0, 0)
    }

    // MARK: - MP3 ID3v2.3 (lo que ID3Writer SI produce)

    func testReadsID3v23TrackNumberWithTotal() async throws {
        let ffmpeg = try ffmpeg()
        let url = workDir.appendingPathComponent("v23.mp3")
        try run(ffmpeg, [
            "-f", "lavfi", "-i", "sine=frequency=440:duration=1",
            "-id3v2_version", "3",
            "-metadata", "title=Prueba", "-metadata", "artist=Artista",
            "-metadata", "track=5/10",
            url.path,
        ])

        let metadata = await LocalTagReader.readTag(from: url)

        XCTAssertEqual(metadata.title, "Prueba")
        XCTAssertEqual(metadata.trackNumber, 5, "bug presente incluso en v2.3: Int(\"5/10\") tambien da nil")
    }

    // MARK: - FLAC (Vorbis comments) -- ID3Writer.readTag nunca se llamaba para esto

    func testReadsFLACVorbisCommentsIncludingAlbum() async throws {
        let ffmpeg = try ffmpeg()
        let url = workDir.appendingPathComponent("test.flac")
        try run(ffmpeg, [
            "-f", "lavfi", "-i", "sine=frequency=440:duration=1",
            "-metadata", "title=Canción FLAC", "-metadata", "artist=Artista FLAC",
            "-metadata", "album=Álbum FLAC", "-metadata", "date=2019",
            "-metadata", "track=2", "-metadata", "albumartist=Varios",
            url.path,
        ])

        let metadata = await LocalTagReader.readTag(from: url)

        XCTAssertEqual(metadata.title, "Canción FLAC")
        XCTAssertEqual(metadata.artist, "Artista FLAC")
        XCTAssertEqual(metadata.album, "Álbum FLAC", "antes: nil -- FLAC no pasaba nunca por el lector")
        XCTAssertEqual(metadata.year, "2019")
        XCTAssertEqual(metadata.trackNumber, 2)
        XCTAssertEqual(metadata.albumArtist, "Varios")
    }

    func testReadsFLACEmbeddedPicture() async throws {
        let ffmpeg = try ffmpeg()
        let cover = workDir.appendingPathComponent("cover.jpg")
        try run(ffmpeg, ["-f", "lavfi", "-i", "testsrc=size=64x64:rate=1", "-frames:v", "1", cover.path])

        let url = workDir.appendingPathComponent("with_cover.flac")
        try run(ffmpeg, [
            "-f", "lavfi", "-i", "sine=frequency=440:duration=1",
            "-i", cover.path, "-map", "0:a", "-map", "1:v",
            "-c:v", "copy", "-disposition:v", "attached_pic",
            "-metadata", "title=Con portada FLAC",
            url.path,
        ])

        let metadata = await LocalTagReader.readTag(from: url)

        XCTAssertNotNil(metadata.pendingCoverData, "METADATA_BLOCK_PICTURE no viene por AVFoundation, hace falta el parser propio")
    }

    // MARK: - M4A (atomos iTunes)

    func testReadsM4AAtomsIncludingAlbumAndTrackNumber() async throws {
        let ffmpeg = try ffmpeg()
        let url = workDir.appendingPathComponent("test.m4a")
        try run(ffmpeg, [
            "-f", "lavfi", "-i", "sine=frequency=440:duration=1",
            "-c:a", "aac",
            "-metadata", "title=Canción M4A", "-metadata", "artist=Artista M4A",
            "-metadata", "album=Álbum M4A", "-metadata", "date=2018",
            "-metadata", "track=4/10",
            url.path,
        ])

        let metadata = await LocalTagReader.readTag(from: url)

        XCTAssertEqual(metadata.title, "Canción M4A")
        XCTAssertEqual(metadata.artist, "Artista M4A")
        XCTAssertEqual(metadata.album, "Álbum M4A", "antes: nil -- M4A tampoco pasaba nunca por el lector")
        XCTAssertEqual(metadata.year, "2018")
        XCTAssertEqual(metadata.trackNumber, 4, "atomo trkn binario -- bytes 2-3 son la pista, big-endian")
    }

    // MARK: - AIFF (chunk ID3)

    func testReadsAIFFID3Chunk() async throws {
        let ffmpeg = try ffmpeg()
        let url = workDir.appendingPathComponent("test.aiff")
        try run(ffmpeg, [
            "-f", "lavfi", "-i", "sine=frequency=440:duration=1",
            "-metadata", "title=Canción AIFF", "-metadata", "artist=Artista AIFF",
            "-metadata", "album=Álbum AIFF", "-write_id3v2", "1",
            url.path,
        ])

        let metadata = await LocalTagReader.readTag(from: url)

        XCTAssertEqual(metadata.title, "Canción AIFF")
        XCTAssertEqual(metadata.artist, "Artista AIFF")
        XCTAssertEqual(metadata.album, "Álbum AIFF", "antes: nil -- AIFF tampoco pasaba nunca por el lector")
    }

    // MARK: - Sin tags (no debe tronar, debe devolver todo nil)

    func testUntaggedFileReturnsEmptyMetadataWithoutThrowing() async throws {
        let ffmpeg = try ffmpeg()
        let url = workDir.appendingPathComponent("untagged.mp3")
        try run(ffmpeg, ["-f", "lavfi", "-i", "sine=frequency=440:duration=1", url.path])

        let metadata = await LocalTagReader.readTag(from: url)

        XCTAssertNil(metadata.title)
        XCTAssertNil(metadata.album)
    }
}
