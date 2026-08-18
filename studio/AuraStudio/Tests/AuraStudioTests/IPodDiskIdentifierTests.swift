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

    // MARK: - ST-016: VID/PID USB como señal de identidad

    private static let iPodClassicUSB = USBDeviceIdentity(
        vendorName: "Rockbox.org", productName: "Rockbox media player", serialNumber: nil,
        vendorID: 0x05AC, productID: 0x1261)

    /// iPod corriendo Aura/Rockbox con un disco Toshiba de fabrica: el
    /// INQUIRY SCSI (de donde DiskArbitration saca vendor/modelo) dice lo
    /// que dice el disco -- ni "Apple" ni "iPod". Sin el VID/PID USB, este
    /// aparato era invisible para Studio.
    func testRockboxUSBWithPlainDriveStringsMatchesByVIDPID() {
        let candidate = DiskCandidateInfo(
            bsdName: "disk7", vendor: "TOSHIBA", model: "MK1231GAL",
            isRemovable: true, isInternal: false,
            sizeBytes: 120_034_123_776, volumeName: "IPOD",
            usb: Self.iPodClassicUSB)
        XCTAssertTrue(candidate.matchesIPodCriteria)
    }

    /// El VID/PID no salta las reglas duras: interno/no removible o un
    /// tamaño imposible siguen descartando.
    func testVIDPIDDoesNotBypassHardRules() {
        let internalDisk = DiskCandidateInfo(
            bsdName: "disk0", vendor: "", model: "", isRemovable: false, isInternal: true,
            sizeBytes: 120_034_123_776, volumeName: nil, usb: Self.iPodClassicUSB)
        XCTAssertFalse(internalDisk.matchesIPodCriteria)

        let absurdSize = DiskCandidateInfo(
            bsdName: "disk8", vendor: "", model: "", isRemovable: true, isInternal: false,
            sizeBytes: 1_000_000, volumeName: nil, usb: Self.iPodClassicUSB)
        XCTAssertFalse(absurdSize.matchesIPodCriteria)
    }

    /// Un iPad (0x05AC, otro PID) con las cadenas de un disco cualquiera
    /// no pasa: el PID es lo que identifica al iPod Classic.
    func testOtherApplePIDDoesNotMatch() {
        let ipad = DiskCandidateInfo(
            bsdName: "disk9", vendor: "", model: "", isRemovable: true, isInternal: false,
            sizeBytes: 64_000_000_000, volumeName: nil,
            usb: USBDeviceIdentity(vendorName: "Apple Inc.", productName: "iPad", serialNumber: nil,
                                   vendorID: 0x05AC, productID: 0x12AB))
        XCTAssertFalse(ipad.matchesIPodCriteria)
    }
}
