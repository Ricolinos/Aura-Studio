import XCTest
@testable import AuraStudio

/// Regresion de D-070: la app detectaba el disco de arranque del Mac
/// como si fuera el iPod, mostraba su capacidad (2 TB) e intentaba
/// escribirle encima.
///
/// Todos los datos de abajo son los REALES medidos con DiskArbitration
/// en la maquina donde se reprodujo el bug, no inventados.
final class WrongVolumeRegressionTests: XCTestCase {

    // MARK: - Los tres eventos que dispara un iPod conectado

    /// DiskArbitration avisa por el disco entero, por la particion de
    /// firmware y por el volumen de datos. Solo el ultimo sirve.
    private func wholeIPodDisk() -> DiskCandidateInfo {
        DiskCandidateInfo(bsdName: "disk9", vendor: "Apple", model: "iPod",
                          isRemovable: true, isInternal: false,
                          sizeBytes: 124_868_366_336, volumeName: nil)
    }

    private func iPodDataVolume() -> DiskCandidateInfo {
        DiskCandidateInfo(bsdName: "disk9s2", vendor: "Apple", model: "iPod",
                          isRemovable: true, isInternal: false,
                          sizeBytes: 124_868_067_328, volumeName: "iPod")
    }

    /// El SSD interno del Mac. Ojo: DiskArbitration reporta el vendor
    /// VACIO y mete "APPLE SSD AP2048Z" en el modelo -- por eso un
    /// criterio que mire solo el texto no alcanza, y hacen falta
    /// removible + externo.
    private func macBootDisk() -> DiskCandidateInfo {
        DiskCandidateInfo(bsdName: "disk3s1s1", vendor: "", model: "APPLE SSD AP2048Z",
                          isRemovable: false, isInternal: true,
                          sizeBytes: 1_995_218_165_760, volumeName: "Macintosh HD")
    }

    func testMacBootDiskIsNeverMistakenForAnIPod() {
        XCTAssertFalse(macBootDisk().matchesIPodCriteria)
        XCTAssertEqual(IPodDiskIdentifier.identify(from: [macBootDisk()]), .notFound)
    }

    /// Discos externos grandes de terceros que estaban conectados en la
    /// misma sesion -- ninguno debe confundirse con el iPod.
    func testOtherExternalDrivesAreNotIPods() {
        let kingston = DiskCandidateInfo(bsdName: "disk8s1", vendor: "KINGSTON",
                                          model: "SNV2S2000G", isRemovable: false,
                                          isInternal: false, sizeBytes: 2_000_170_000_000,
                                          volumeName: "Ricolinos")
        let sandisk = DiskCandidateInfo(bsdName: "disk5s3", vendor: "SanDisk",
                                         model: "Extreme 55AE", isRemovable: false,
                                         isInternal: false, sizeBytes: 2_000_170_000_000,
                                         volumeName: "NBA SSD Rick")
        XCTAssertFalse(kingston.matchesIPodCriteria)
        XCTAssertFalse(sandisk.matchesIPodCriteria)
    }

    /// El iPod real de esta sesion: 124.9 GB, o sea un 6G con el disco
    /// cambiado por flash. Con el criterio viejo (120GB +/- 5GB y nada
    /// mas) pasaba por apenas 130 MB de margen.
    func testRealModdedIPodIsRecognised() {
        XCTAssertTrue(iPodDataVolume().matchesIPodCriteria)
    }

    /// Y estos son los que el criterio viejo rechazaba de plano: mods de
    /// flash mas grandes, que hoy son lo normal para mantener vivo un
    /// Classic. Son iPods de verdad y tienen que poder usarse.
    func testLargerFlashModdedIPodsAreRecognised() {
        for size: Int64 in [256_000_000_000, 512_000_000_000, 1_000_000_000_000] {
            let modded = DiskCandidateInfo(bsdName: "disk9s2", vendor: "Apple", model: "iPod",
                                            isRemovable: true, isInternal: false,
                                            sizeBytes: size, volumeName: "iPod")
            XCTAssertTrue(modded.matchesIPodCriteria, "un iPod modificado de \(size) bytes deberia reconocerse")
        }
    }

    /// El disco de fabrica no dice "iPod" en ningun lado (D-046): ahi el
    /// tamaño sigue siendo la unica señal, y tiene que seguir andando.
    func testStockDiskWithoutIPodInTheNameStillMatchesBySize() {
        let stock = DiskCandidateInfo(bsdName: "disk9", vendor: "Apple Computer, Inc.",
                                       model: "HS12YHA", isRemovable: true, isInternal: false,
                                       sizeBytes: 120_034_123_776, volumeName: "IPOD")
        XCTAssertTrue(stock.matchesIPodCriteria)
    }

    /// Un dispositivo Apple removible que NO es un iPod (ni por nombre
    /// ni por tamaño) sigue rechazandose: ampliar el rango de tamaños no
    /// puede volverse un colador.
    func testOtherAppleRemovableDeviceIsStillRejected() {
        let other = DiskCandidateInfo(bsdName: "disk11", vendor: "Apple", model: "Some Device",
                                       isRemovable: true, isInternal: false,
                                       sizeBytes: 32_000_000_000, volumeName: "OTHER")
        XCTAssertFalse(other.matchesIPodCriteria)
    }

    // MARK: - La ruta de montaje vacia, que es lo que hizo el daño

    /// El disco entero y la particion de firmware pasan los criterios de
    /// dispositivo, pero no tienen punto de montaje. Antes se aceptaban,
    /// `mountPath` quedaba vacio, y todo lo de abajo terminaba operando
    /// sobre "/" sin avisar.
    func testWholeDiskPassesDeviceCriteriaButHasNoVolumeToWorkOn() {
        XCTAssertTrue(wholeIPodDisk().matchesIPodCriteria,
                      "como dispositivo es un iPod...")
        XCTAssertNil(wholeIPodDisk().volumeName,
                     "...pero no tiene volumen montado, asi que no sirve para leer ni escribir")
    }

    func testProbeRefusesEmptyMountPath() {
        let info = DiskModeInfo(volumeName: "iPod", mountPath: "",
                                bsdName: "disk9", isFAT32: false)
        XCTAssertNil(AuraDeviceProbe.probe(diskInfo: info),
                     "una ruta vacia se resolveria como \"/\" -- el disco de arranque del Mac")
    }

    func testProbeRefusesRelativeMountPath() {
        let info = DiskModeInfo(volumeName: "iPod", mountPath: "Volumes/iPod",
                                bsdName: "disk9s2", isFAT32: false)
        XCTAssertNil(AuraDeviceProbe.probe(diskInfo: info))
    }

    func testProbeRefusesPathThatDoesNotExist() {
        let info = DiskModeInfo(volumeName: "iPod",
                                mountPath: "/Volumes/NoExisteEsteVolumen-\(UUID().uuidString)",
                                bsdName: "disk9s2", isFAT32: false)
        XCTAssertNil(AuraDeviceProbe.probe(diskInfo: info))
    }
}
