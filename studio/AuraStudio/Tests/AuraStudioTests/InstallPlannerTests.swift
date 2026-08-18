import XCTest
@testable import AuraStudio

/// ST-017: el orden del instalador segun el modo de arranque. Solo Aura
/// flashea primero (formatear -> DFU -> copiar via "Bootloader USB
/// mode"); dual boot copia primero. Cada caso es la primera accion que
/// toma `InstallerViewModel.acknowledgeDeviceReady()`.
final class InstallPlannerTests: XCTestCase {
    private func plan(fat32: Bool?, single: Bool, canSkip: Bool = false, isAura: Bool = false,
                      flashed: Bool = false, prepared: Bool = false) -> InstallPlanner.Plan {
        InstallPlanner.plan(volumeIsFAT32: fat32, singleBoot: single, canSkipFlash: canSkip,
                            deviceIsAura: isAura, bootloaderFlashedThisFlow: flashed,
                            diskPreparedThisFlow: prepared)
    }

    // MARK: - Solo Aura (el encargo): formatear -> DFU -> copiar

    /// El caso exacto del dueño: iPod con firmware original de Apple en
    /// FAT32, Solo Aura. Antes copiaba archivos y despues pedia DFU;
    /// ahora formatea y va a DFU -- la copia llega despues.
    func testSingleBootOnStockFAT32FormatsThenFlashes() {
        let p = plan(fat32: true, single: true)
        XCTAssertEqual(p, .init(action: .formatThenFlash, flashFirst: true))
    }

    func testSingleBootOnNonFAT32FormatsThenFlashes() {
        XCTAssertEqual(plan(fat32: false, single: true).action, .formatThenFlash)
        XCTAssertEqual(plan(fat32: nil, single: true).action, .formatThenFlash)
    }

    /// Con Aura verificada en el disco se conserva la biblioteca: sin
    /// formatear, directo a DFU.
    func testSingleBootOverVerifiedAuraGoesStraightToDFU() {
        XCTAssertEqual(plan(fat32: true, single: true, isAura: true),
                       .init(action: .enterDFU, flashFirst: true))
    }

    /// Reintento tras un DFU que no aplico: el disco ya se formateo en
    /// esta corrida, no se vuelve a pedir contraseña -- directo a DFU.
    func testSingleBootRetryAfterPreparedDiskGoesStraightToDFU() {
        XCTAssertEqual(plan(fat32: true, single: true, prepared: true).action, .enterDFU)
    }

    /// El flasheo ya se hizo en esta corrida: solo falta copiar (FAT32),
    /// o formatear y copiar (sin FAT32 -- p. ej. se entro directo en DFU).
    func testAfterFlashOnlyTheCopyRemains() {
        XCTAssertEqual(plan(fat32: true, single: true, flashed: true),
                       .init(action: .copyFiles, flashFirst: false))
        XCTAssertEqual(plan(fat32: false, single: true, flashed: true),
                       .init(action: .formatThenCopy, flashFirst: false))
        XCTAssertEqual(plan(fat32: nil, single: true, flashed: true).action, .formatThenCopy)
    }

    // MARK: - Dual boot: copiar primero, DFU al final (sin cambio)

    func testDualBootOnFAT32CopiesFirst() {
        XCTAssertEqual(plan(fat32: true, single: false), .init(action: .copyFiles, flashFirst: false))
    }

    /// D-185: dual boot sobre un disco que habria que formatear se
    /// detiene antes de borrar nada.
    func testDualBootOnNonFAT32Refuses() {
        XCTAssertEqual(plan(fat32: false, single: false).action, .refuseDualBootRequiresWinpod)
        XCTAssertEqual(plan(fat32: nil, single: false).action, .refuseDualBootRequiresWinpod)
    }

    // MARK: - Evidencia de bootloader (ST-016) gana en ambos modos

    func testBootloaderEvidenceSkipsFlashInBothModes() {
        XCTAssertEqual(plan(fat32: true, single: true, canSkip: true),
                       .init(action: .copyFiles, flashFirst: false))
        XCTAssertEqual(plan(fat32: true, single: false, canSkip: true),
                       .init(action: .copyFiles, flashFirst: false))
    }
}
