import Foundation

/// Marcador de sincronizacion pendiente -- `docs/contracts/library-layout-v1.md`
/// SS4 (D-293 en el firmware / ST-012 aca). El firmware NO corre mientras
/// el iPod esta montado por USB, asi que Studio no puede pedirle nada: le
/// deja este archivo en `/.aura/sync-pending.json` al terminar cada
/// sincronizacion que toco archivos, y el firmware lo lee al arrancar y al
/// volver de la pantalla USB, reconstruye los indices de las secciones
/// marcadas y lo borra solo al terminar bien.
///
/// `attempts` lo escribe el FIRMWARE (contador de reintentos, 3 fallos
/// seguidos = deja de reintentar solo); Studio siempre escribe 0.
struct SyncPendingMarker: Codable, Equatable {
    struct Changes: Codable, Equatable {
        var music: Bool
        var video: Bool
        var images: Bool

        var isEmpty: Bool { !music && !video && !images }
    }

    /// Version del esquema que este Studio escribe. Sube junto con la
    /// version de `library-layout-vN.md`.
    static let currentVersion = 1
    static let relativePath = ".aura/sync-pending.json"

    var version: Int
    var timestamp: String
    var changes: Changes
    var attempts: Int

    init(changes: Changes, date: Date = Date()) {
        self.version = Self.currentVersion
        self.timestamp = Self.iso8601String(from: date)
        self.changes = changes
        self.attempts = 0
    }

    /// Un formateador por llamada: `ISO8601DateFormatter` no es `Sendable`
    /// y un `static let` compartido no pasa el chequeo de concurrencia de
    /// Swift 6 en el proyecto real (D-041: lo que solo `xcodebuild` ve).
    /// Se escribe un marcador por sync -- el costo es irrelevante.
    private static func iso8601String(from date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    /// Escritura atomica en el volumen montado. Crea `/.aura/` si falta.
    func write(to volumeRoot: URL, fileManager: FileManager = .default) throws {
        let url = volumeRoot.appendingPathComponent(Self.relativePath)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    static func read(from volumeRoot: URL, fileManager: FileManager = .default) -> SyncPendingMarker? {
        let url = volumeRoot.appendingPathComponent(relativePath)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SyncPendingMarker.self, from: data)
    }
}

/// Que entiende el firmware instalado en el iPod, leido de `aura.cfg`
/// (claves de SOLO ESCRITURA del lado firmware, misma convencion que
/// `theme_format_supported`, ver `ThemeInstaller.supportedThemeFormat`).
enum FirmwareCapabilities {
    static let auraConfigRelativePath = ".rockbox/aura/aura.cfg"

    /// Version de esquema del marcador que el firmware entiende, o `nil`
    /// si el firmware es anterior a D-293 (no escribe la clave) -- en ese
    /// caso `LibrarySync` conserva su mecanismo previo (borrar la base de
    /// tagcache para forzar la reconstruccion al arrancar), contrato SS4.4.
    static func supportedSyncMarkerVersion(volumeRoot: URL, fileManager: FileManager = .default) -> Int? {
        let cfgURL = volumeRoot.appendingPathComponent(auraConfigRelativePath)
        guard let text = try? String(contentsOf: cfgURL, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") where line.hasPrefix("sync_marker_supported:") {
            return Int(line.dropFirst("sync_marker_supported:".count).trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    /// ST-046 / contrato v8: que familia dice ser el firmware instalado
    /// (`firmware_family`). **La ausencia de la clave devuelve `.aura`**, y
    /// eso no es un fallback defensivo sino el contrato: Aura-Firmware
    /// nunca escribio esta clave ni la escribira, asi que "no esta" es
    /// precisamente su firma. El unico firmware que la escribe hoy es
    /// Metro-Aura (`metro_settings.c`).
    ///
    /// Sin `aura.cfg` (firmware recien copiado, nunca arrancado) tambien
    /// devuelve `.aura`. Es correcto: en ese estado
    /// `AuraDevice.supportsAuraContract` es `false` y nadie usa la familia
    /// todavia.
    static func declaredFamily(volumeRoot: URL, fileManager: FileManager = .default) -> FirmwareFamily {
        let cfgURL = volumeRoot.appendingPathComponent(auraConfigRelativePath)
        guard let text = try? String(contentsOf: cfgURL, encoding: .utf8) else { return .aura }
        let key = "firmware_family:"
        for line in text.split(separator: "\n") where line.hasPrefix(key) {
            return FirmwareFamily.parse(configValue: String(line.dropFirst(key.count)))
        }
        return .aura
    }
}
