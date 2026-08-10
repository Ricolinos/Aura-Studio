import XCTest
@testable import AuraStudio

final class IPodDiskIdentifierTests: XCTestCase {
    private func ipodCandidate(bsdName: String = "disk7") -> DiskCandidateInfo {
        DiskCandidateInfo(
            bsdName: bsdName,
            vendor: "Apple Computer, Inc.",
            model: "HS12YHA", // nombre de media real observado en hardware -- no dice "iPod"
            isRemovable: true,
            isInternal: false,
            sizeBytes: 120_034_123_776, // tamaño real observado en hardware
            volumeName: "IPOD"
        )
    }

    // MARK: - Caso: iPod presente (unico candidato)

    func testIPodPresentAlone_isFound() {
        let ipod = ipodCandidate()
        let result = IPodDiskIdentifier.identify(from: [ipod])

        XCTAssertEqual(result, .found(ipod))
    }

    func testMediaNameNotContainingIPodStringStillMatches() {
        // Caso real de esta sesion: diskutil reporto "HS12YHA" (el
        // modelo del disco duro interno), no "iPod" ni "Apple" en el
        // nombre de media -- el criterio no debe depender de eso.
        let ipod = ipodCandidate()
        XCTAssertTrue(ipod.matchesIPodCriteria)
    }

    // MARK: - Caso: iPod ausente

    func testNoCandidates_isNotFound() {
        let result = IPodDiskIdentifier.identify(from: [])
        XCTAssertEqual(result, .notFound)
    }

    func testOnlyNonMatchingDisks_isNotFound() {
        let internalDrive = DiskCandidateInfo(
            bsdName: "disk0", vendor: "Apple", model: "APPLE SSD",
            isRemovable: false, isInternal: true,
            sizeBytes: 2_000_000_000_000, volumeName: "Macintosh HD"
        )
        let result = IPodDiskIdentifier.identify(from: [internalDrive])
        XCTAssertEqual(result, .notFound)
    }

    // MARK: - Caso: disco externo de tamaño similar presente (no debe matchear)

    func testSimilarSizeExternalDiskWithDifferentVendor_isNotFound() {
        // Un SSD externo de terceros, del tamaño parecido a un iPod,
        // pero de otro fabricante -- no debe confundirse con el iPod.
        let thirdPartyDrive = DiskCandidateInfo(
            bsdName: "disk8", vendor: "SanDisk", model: "Extreme 55AE",
            isRemovable: true, isInternal: false,
            sizeBytes: 122_000_000_000, volumeName: "Extreme SSD"
        )
        let result = IPodDiskIdentifier.identify(from: [thirdPartyDrive])
        XCTAssertEqual(result, .notFound)
    }

    func testAppleVendorButWrongSize_isNotFound() {
        // Vendor Apple pero tamaño muy distinto (p.ej. un pendrive de
        // otro dispositivo Apple, o el propio iPod en un estado raro)
        // -- el tamaño tambien tiene que coincidir, no alcanza el vendor.
        let wrongSize = DiskCandidateInfo(
            bsdName: "disk9", vendor: "Apple", model: "Some Device",
            isRemovable: true, isInternal: false,
            sizeBytes: 32_000_000_000, volumeName: "OTHER"
        )
        let result = IPodDiskIdentifier.identify(from: [wrongSize])
        XCTAssertEqual(result, .notFound)
    }

    // MARK: - Caso: dos candidatos (ambiguo, nunca "el mas probable")

    func testTwoMatchingCandidates_isAmbiguousNeverPicksOne() {
        let ipod1 = ipodCandidate(bsdName: "disk7")
        let ipod2 = ipodCandidate(bsdName: "disk11") // p.ej. otro iPod Classic conectado

        let result = IPodDiskIdentifier.identify(from: [ipod1, ipod2])

        guard case .ambiguous(let candidates) = result else {
            return XCTFail("esperaba .ambiguous, obtuve \(result)")
        }
        XCTAssertEqual(Set(candidates.map(\.bsdName)), Set(["disk7", "disk11"]))
    }

    func testAmbiguousAmongMixedCandidates_ignoresNonMatchingOnes() {
        let ipod1 = ipodCandidate(bsdName: "disk7")
        let ipod2 = ipodCandidate(bsdName: "disk11")
        let unrelated = DiskCandidateInfo(
            bsdName: "disk0", vendor: "Apple", model: "APPLE SSD",
            isRemovable: false, isInternal: true,
            sizeBytes: 2_000_000_000_000, volumeName: "Macintosh HD"
        )

        let result = IPodDiskIdentifier.identify(from: [unrelated, ipod1, ipod2])

        guard case .ambiguous(let candidates) = result else {
            return XCTFail("esperaba .ambiguous, obtuve \(result)")
        }
        XCTAssertEqual(candidates.count, 2)
    }

    // MARK: - Criterios individuales

    func testInternalDiskNeverMatchesEvenIfOtherwiseIdentical() {
        var candidate = ipodCandidate()
        candidate = DiskCandidateInfo(
            bsdName: candidate.bsdName, vendor: candidate.vendor, model: candidate.model,
            isRemovable: candidate.isRemovable, isInternal: true,
            sizeBytes: candidate.sizeBytes, volumeName: candidate.volumeName
        )
        XCTAssertFalse(candidate.matchesIPodCriteria)
    }

    func testNonRemovableDiskNeverMatches() {
        var candidate = ipodCandidate()
        candidate = DiskCandidateInfo(
            bsdName: candidate.bsdName, vendor: candidate.vendor, model: candidate.model,
            isRemovable: false, isInternal: candidate.isInternal,
            sizeBytes: candidate.sizeBytes, volumeName: candidate.volumeName
        )
        XCTAssertFalse(candidate.matchesIPodCriteria)
    }
}
