import Foundation

/// Escribe hora y zona horaria del Mac en `aura.cfg` para que el dueño
/// nunca tenga que configurarlas a mano en el iPod (encargo 2026-08-18) --
/// ver CONTRATO-firmware-studio.md §D.4. Mismo patrón que
/// `ThemeInstaller.activate`: upserta SOLO las líneas que le
/// corresponden, preserva el resto del archivo tal cual. No administra
/// el candado de `InstallerFlowRegistry` -- el llamador ya lo sostiene
/// (`IPodMonitor` lo toma él mismo; `InstallerViewModel` ya lo sostiene
/// durante la instalación).
enum ClockSyncWriter {
    private static let auraConfigRelativePath = ".rockbox/aura/aura.cfg"

    /// Puro y testeable: dadas las líneas actuales de `aura.cfg`, la
    /// fecha/hora y la zona horaria a sincronizar, devuelve las líneas
    /// resultantes. `rtc_sync_*` son transitorias -- el firmware las
    /// aplica una vez al RTC real y las descarta en su próximo
    /// `aura_settings_save()`; `tz_local_quarters` es la MISMA clave
    /// persistente que ya usa el reloj mundial de Aura (D-293), así que
    /// aquí solo se refresca, nunca se agrega una clave nueva para eso.
    static func upsertClockLines(
        _ lines: [String],
        date: Date,
        timeZone: TimeZone,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> [String] {
        var cal = calendar
        cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let quarters = timeZone.secondsFromGMT(for: date) / 900

        var result = lines
        func upsert(_ key: String, _ value: Int) {
            let prefix = "\(key):"
            if let i = result.firstIndex(where: { $0.hasPrefix(prefix) }) {
                result[i] = "\(key): \(value)"
            } else {
                result.append("\(key): \(value)")
            }
        }
        upsert("rtc_sync_year", c.year ?? 1970)
        upsert("rtc_sync_month", c.month ?? 1)
        upsert("rtc_sync_day", c.day ?? 1)
        upsert("rtc_sync_hour", c.hour ?? 0)
        upsert("rtc_sync_min", c.minute ?? 0)
        upsert("rtc_sync_sec", c.second ?? 0)
        upsert("tz_local_quarters", quarters)
        return result
    }

    /// Lee, actualiza y reescribe `aura.cfg` en `mountPath`. Silencioso
    /// ante rutas inválidas (mismo criterio que `ThemeInstaller`) --
    /// esta sincronización es una cortesía en segundo plano, nunca debe
    /// interrumpir al dueño ni bloquear otro flujo.
    static func writeToDisk(
        mountPath: String,
        fileManager: FileManager = .default,
        date: Date = Date(),
        timeZone: TimeZone = .current
    ) throws {
        guard !mountPath.isEmpty, mountPath.hasPrefix("/") else { return }
        let cfgURL = URL(fileURLWithPath: mountPath).appendingPathComponent(auraConfigRelativePath)
        var lines: [String]
        if let text = try? String(contentsOf: cfgURL, encoding: .utf8) {
            lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        } else {
            lines = []
        }
        let updated = upsertClockLines(lines, date: date, timeZone: timeZone)
        try fileManager.createDirectory(at: cfgURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let text = updated.joined(separator: "\n") + "\n"
        try text.write(to: cfgURL, atomically: true, encoding: .utf8)
    }
}
