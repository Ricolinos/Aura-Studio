import Foundation

/// Registro local, legible por humanos, de cada operación privilegiada
/// que Aura Studio ejecutó -- qué se corrió, cuándo, y el resultado.
/// Vive en `~/Library/Application Support/AuraStudio/` (no dentro del
/// bundle de la app, que puede ser de solo lectura una vez firmada).
struct PrivilegedOperationLog: Sendable {
    private let fileURL: URL

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("AuraStudio", isDirectory: true)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("AuraStudio", isDirectory: true)

        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.fileURL = base.appendingPathComponent("privileged-operations.log")
    }

    /// `operation` es una descripcion corta (no el script completo, que
    /// puede contener rutas largas) -- pensado para diagnostico rapido,
    /// no como auditoria forense byte a byte.
    func append(operation: String, result: String) {
        let timestamp = ISO8601DateFormatter().string(from: referenceNow())
        let line = "[\(timestamp)] \(operation) -> \(result)\n"
        guard let data = line.data(using: .utf8) else { return }

        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL)
        }
    }

    /// Punto de inyección para tests -- evita depender del reloj real.
    var referenceNow: @Sendable () -> Date = { Date() }

    func readAll() -> String {
        (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    }
}
