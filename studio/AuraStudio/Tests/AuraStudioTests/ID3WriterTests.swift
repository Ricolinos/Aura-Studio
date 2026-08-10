import XCTest
@testable import AuraStudio

final class ID3WriterTests: XCTestCase {
    func testRoundTripTextFrames() {
        let tag = ID3Writer.Tag(
            title: "Aura Test Tone",
            artist: "Aura QA",
            album: "Fase 4 Fixtures",
            albumArtist: "Aura QA",
            year: "2026",
            genre: "Electronic",
            trackNumber: 1
        )
        let built = ID3Writer.buildTag(tag)
        let readBack = ID3Writer.readTag(from: built)

        XCTAssertEqual(readBack?.title, "Aura Test Tone")
        XCTAssertEqual(readBack?.artist, "Aura QA")
        XCTAssertEqual(readBack?.album, "Fase 4 Fixtures")
        XCTAssertEqual(readBack?.albumArtist, "Aura QA")
        XCTAssertEqual(readBack?.year, "2026")
        XCTAssertEqual(readBack?.genre, "Electronic")
        XCTAssertEqual(readBack?.trackNumber, 1)
    }

    func testRoundTripWithAccentedCharacters() {
        // Unicode real (español) -- confirma que la codificacion
        // UTF-16 con BOM sobrevive el viaje completo, no solo ASCII.
        let tag = ID3Writer.Tag(title: "Canción de práctica", artist: "Ñandú y Compañía", album: nil)
        let built = ID3Writer.buildTag(tag)
        let readBack = ID3Writer.readTag(from: built)

        XCTAssertEqual(readBack?.title, "Canción de práctica")
        XCTAssertEqual(readBack?.artist, "Ñandú y Compañía")
    }

    func testRoundTripWithCoverArt() {
        let imageBytes = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46]) // cabecera JPEG real
        let tag = ID3Writer.Tag(title: "Con tapa", coverArtData: imageBytes, coverArtMIMEType: "image/jpeg")
        let built = ID3Writer.buildTag(tag)
        let readBack = ID3Writer.readTag(from: built)

        XCTAssertEqual(readBack?.title, "Con tapa")
        XCTAssertEqual(readBack?.coverArtData, imageBytes)
    }

    func testWritingReplacesExistingTagAndPreservesAudio() {
        let fakeOldTag = ID3Writer.buildTag(ID3Writer.Tag(title: "Old Title"))
        let fakeAudio = Data([0xFF, 0xFB, 0x90, 0x00]) + Data(repeating: 0xAB, count: 128)
        let originalFile = fakeOldTag + fakeAudio

        let newTag = ID3Writer.Tag(title: "New Title", artist: "New Artist")
        let result = ID3Writer.writing(newTag, into: originalFile)

        let readBack = ID3Writer.readTag(from: result)
        XCTAssertEqual(readBack?.title, "New Title")
        XCTAssertEqual(readBack?.artist, "New Artist")

        // El audio original debe estar intacto, sin importar donde
        // termine la tag nueva.
        let newTagSize = ID3Writer.existingTagSize(in: result)
        let recoveredAudio = result.subdata(in: newTagSize..<result.count)
        XCTAssertEqual(recoveredAudio, fakeAudio)
    }

    func testWritingOnFileWithoutExistingTagPrepends() {
        let fakeAudio = Data([0xFF, 0xFB, 0x90, 0x00, 0x01, 0x02, 0x03])
        let result = ID3Writer.writing(ID3Writer.Tag(title: "No previous tag"), into: fakeAudio)

        let tagSize = ID3Writer.existingTagSize(in: result)
        XCTAssertGreaterThan(tagSize, 0)
        XCTAssertEqual(result.subdata(in: tagSize..<result.count), fakeAudio)
    }

    func testExistingTagSizeIsZeroWhenNoID3Header() {
        let plainData = Data([0xFF, 0xFB, 0x90, 0x00, 0x01, 0x02])
        XCTAssertEqual(ID3Writer.existingTagSize(in: plainData), 0)
    }

    func testSynchsafeSizeHandlesLargeTagWithCoverArt() {
        // Una tapa de ~50KB obliga a que el tamaño de la tag exceda
        // 7 bits en mas de un byte -- ejercita la codificacion
        // synchsafe real, no solo el caso trivial de tags chicas.
        let bigCover = Data(repeating: 0x42, count: 50_000)
        let tag = ID3Writer.Tag(title: "Con tapa grande", coverArtData: bigCover)
        let built = ID3Writer.buildTag(tag)
        let readBack = ID3Writer.readTag(from: built)

        XCTAssertEqual(readBack?.coverArtData?.count, 50_000)
        XCTAssertEqual(ID3Writer.existingTagSize(in: built), built.count)
    }
}
