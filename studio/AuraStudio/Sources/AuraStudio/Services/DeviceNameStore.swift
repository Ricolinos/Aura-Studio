import Foundation

/// Identidad de un iPod: `deviceID` (UUID estable, generado por Studio
/// una sola vez) y `deviceName` (editable por el usuario). Vive **en el
/// dispositivo** (`.rockbox/aura/device.cfg`, ver `CONTRATO-dispositivo.md`)
/// para que persista si el iPod se conecta a otra Mac -- PLAN-general-sync.md
/// §1.5/§9.
struct DeviceIdentity: Equatable {
    let deviceID: String
    let deviceName: String
    let updatedAt: Date
    /// ST-013 (`CONTRATO-dispositivo.md` v2, SS C bis): `installationID` de
    /// la instalacion de Aura Studio que le puso nombre al iPod la
    /// primera vez -- la UNICA que puede cambiarlo despues. `nil` en un
    /// `device.cfg` v1 (anterior a este campo): reclamable por la primera
    /// instalacion que lo guarde.
    var ownerInstallationID: String? = nil

    init(deviceID: String, deviceName: String, updatedAt: Date, ownerInstallationID: String? = nil) {
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.updatedAt = updatedAt
        self.ownerInstallationID = ownerInstallationID
    }

    /// Regla de propiedad del nombre. Sin propietario (archivo v1) todos
    /// pueden -- y el que guarde primero, reclama.
    func canRename(from installationID: String) -> Bool {
        ownerInstallationID == nil || ownerInstallationID == installationID
    }
}

/// Lee/escribe `.rockbox/aura/device.cfg` -- mismo formato `clave: valor`
/// que `sync_summary.cfg`/`aura.cfg` (el firmware no tiene parser JSON,
/// ver `CatalogSummaryWriter`). Studio es quien escribe este archivo;
/// el firmware, si algún día lo consume, solo lee (§9.2 del plan,
/// `CONTRATO-dispositivo.md`).
enum DeviceNameStore {
    static let relativePath = ".rockbox/aura/device.cfg"
    /// v2 (ST-013): `device_owner`. Un archivo v1 se lee igual (sin
    /// propietario) y se reescribe como v2 en el proximo guardado.
    static let currentContractVersion = 2

    /// El firmware lee líneas de `.rockbox/aura/*.cfg` con un buffer de
    /// 64 bytes (`read_line`, ver `aura_manifest.c`/`aura_settings.c`) --
    /// `device_name: <valor>` tiene que caber ahí completo. 32 caracteres
    /// coincide además con los precedentes ya existentes del firmware
    /// (`style_id[33]` de temas, D-289; `playername.txt` de IAP, 31
    /// bytes) -- ver PLAN-general-sync.md §9.3/§9.4.
    static let maxCharacters = 32
    static let maxBytes = 48

    // MARK: - Lectura/escritura

    static func load(volumeRoot: URL, fileManager: FileManager = .default) -> DeviceIdentity? {
        let url = volumeRoot.appendingPathComponent(relativePath)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parse(text)
    }

    static func save(_ identity: DeviceIdentity, volumeRoot: URL, fileManager: FileManager = .default) throws {
        let url = volumeRoot.appendingPathComponent(relativePath)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try serialize(identity).write(to: url, atomically: true, encoding: .utf8)
    }

    static func parse(_ text: String) -> DeviceIdentity? {
        var values: [String: String] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            values[key] = value
        }
        guard let deviceID = values["device_id"], !deviceID.isEmpty,
              let deviceName = values["device_name"], !deviceName.isEmpty else { return nil }
        let updatedAt = values["device_name_updated_at"].flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
        let owner = values["device_owner"].flatMap { $0.isEmpty ? nil : $0 }
        return DeviceIdentity(deviceID: deviceID, deviceName: deviceName, updatedAt: updatedAt,
                              ownerInstallationID: owner)
    }

    static func serialize(_ identity: DeviceIdentity) -> String {
        let timestamp = ISO8601DateFormatter().string(from: identity.updatedAt)
        var lines = [
            "contract_version: \(currentContractVersion)",
            "device_id: \(identity.deviceID)",
            "device_name: \(identity.deviceName)",
        ]
        if let owner = identity.ownerInstallationID, !owner.isEmpty {
            lines.append("device_owner: \(owner)")
        }
        lines.append("device_name_updated_at: \(timestamp)")
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Default y validación (§1.5/§9.3)

    /// `iPod de <NSFullUserName()>`, con los fallbacks de la spec --
    /// nunca se queda sin nombre que ofrecer.
    static func defaultName() -> String {
        let full = NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        if !full.isEmpty { return "iPod de \(full)" }
        let short = NSUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        if !short.isEmpty { return "iPod de \(short)" }
        return "iPod"
    }

    /// Recorta espacios en los extremos, colapsa espacios internos,
    /// quita caracteres de control/saltos de línea, quita Unicode fuera
    /// del BMP (emoji -- el iPod no tiene glifo, mostraría cajas) y
    /// trunca a `maxCharacters`/`maxBytes`. `strippedEmoji` avisa a la UI
    /// si hubo algo que quitar, para decirlo en vez de que el nombre
    /// simplemente aparezca distinto sin explicación.
    static func sanitize(_ raw: String) -> (name: String, strippedEmoji: Bool) {
        var strippedEmoji = false
        let filteredScalars = raw.unicodeScalars.filter { scalar -> Bool in
            if scalar.value > 0xFFFF {
                strippedEmoji = true
                return false
            }
            if scalar.properties.generalCategory == .control {
                return false
            }
            return true
        }
        let filtered = String(String.UnicodeScalarView(filteredScalars))
        let collapsed = filtered
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
        let trimmed = collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
        return (truncate(trimmed), strippedEmoji)
    }

    private static func truncate(_ string: String) -> String {
        var result = String(string.prefix(maxCharacters))
        while result.utf8.count > maxBytes, !result.isEmpty {
            result.removeLast()
        }
        return result
    }
}
