import Foundation

enum ThemeInstallerError: LocalizedError, Equatable {
    case invalidMountPath
    case invalidId(String)
    case validationFailed(ThemeValidationError)
    case writeLocked
    case dittoFailed(String)
    case cannotDeleteDefault

    var errorDescription: String? {
        switch self {
        case .invalidMountPath:
            return "No hay un iPod montado en una ruta válida."
        case .invalidId(let id):
            return "\"\(id)\" no es un id válido de tema."
        case .validationFailed(let underlying):
            return underlying.errorDescription
        case .writeLocked:
            return "Ya hay otra operación escribiendo en el iPod -- espera a que termine."
        case .dittoFailed(let reason):
            return "No se pudo copiar el tema al iPod: \(reason)."
        case .cannotDeleteDefault:
            return "\"Aura\" es el tema integrado del firmware -- no se puede eliminar."
        }
    }
}

/// Instala/lista/activa/elimina paquetes de tema en el volumen montado
/// del iPod -- `CONTRATO-formato-tema.md`. Mismas reglas de seguridad
/// que el resto de Studio: `mountPath` se revalida en cada llamada
/// (nunca una captura vieja de un `AuraDevice` guardado), candado
/// global compartido con el instalador del firmware
/// (`InstallerFlowRegistry`, para no cruzarse con un sync o una
/// instalación en curso), y `<id>` siempre pasa por
/// `AuraThemeID.isValid()` antes de tocar cualquier ruta que lo
/// contenga -- nunca se construye una ruta de borrado a partir de un id
/// sin validar.
enum ThemeInstaller {
    static let themesRelativePath = ".rockbox/aura/themes"
    private static let auraConfigRelativePath = ".rockbox/aura/aura.cfg"

    private static func isValidMountPath(_ mountPath: String) -> Bool {
        !mountPath.isEmpty && mountPath.hasPrefix("/")
    }

    private static func themesRoot(mountPath: String) -> URL? {
        guard isValidMountPath(mountPath) else { return nil }
        return URL(fileURLWithPath: mountPath).appendingPathComponent(themesRelativePath)
    }

    /// Lista los temas instalados -- no incluye "Aura" (el default,
    /// integrado en el firmware): la UI lo agrega aparte, siempre
    /// primero, siempre disponible.
    static func listInstalled(mountPath: String, fileManager: FileManager = .default) -> [InstalledTheme] {
        guard let root = themesRoot(mountPath: mountPath),
              let entries = try? fileManager.contentsOfDirectory(atPath: root.path) else {
            return []
        }
        var result: [InstalledTheme] = []
        for entry in entries.sorted() where AuraThemeID.isValid(entry) {
            let packageRoot = root.appendingPathComponent(entry)
            let supported = supportedThemeFormat(mountPath: mountPath, fileManager: fileManager)
            switch ThemeValidator.validate(packageRoot: packageRoot, firmwareSupportedFormat: supported, fileManager: fileManager) {
            case .success(let manifest):
                result.append(InstalledTheme(id: entry, name: manifest.name.isEmpty ? entry : manifest.name, loadable: true))
            case .failure(let error):
                result.append(InstalledTheme(id: entry, name: entry, loadable: false, reason: error.errorDescription))
            }
        }
        return result
    }

    /// Instala `packageRoot` (ya en el layout del contrato -- ver
    /// `ThemePackager`) en `mountPath`, validando primero. Usa `ditto`
    /// sin privilegios (el volumen ya está montado como disco de
    /// usuario, igual que el instalador del firmware). `@MainActor`
    /// (como `InstallerViewModel`): `InstallerFlowRegistry` vive ahí,
    /// para que el candado sea el mismo entre esta operación y una
    /// instalación/sync en curso.
    @MainActor
    static func install(packageRoot: URL, mountPath: String,
                         fileManager: FileManager = .default) async throws -> AuraThemeManifest {
        guard InstallerFlowRegistry.shared.beginWriting() else {
            throw ThemeInstallerError.writeLocked
        }
        defer { InstallerFlowRegistry.shared.endWriting() }

        guard let root = themesRoot(mountPath: mountPath) else {
            throw ThemeInstallerError.invalidMountPath
        }
        let supported = supportedThemeFormat(mountPath: mountPath, fileManager: fileManager)
        let validation = ThemeValidator.validate(packageRoot: packageRoot, firmwareSupportedFormat: supported, fileManager: fileManager)
        let manifest: AuraThemeManifest
        switch validation {
        case .success(let value): manifest = value
        case .failure(let error): throw ThemeInstallerError.validationFailed(error)
        }

        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let destination = root.appendingPathComponent(manifest.id)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try await ditto(from: packageRoot, to: destination)

        guard fileManager.fileExists(atPath: destination.appendingPathComponent("theme.cfg").path) else {
            throw ThemeInstallerError.dittoFailed("no se encontró theme.cfg en \(manifest.id)/ después de copiar")
        }
        return manifest
    }

    /// Elimina un tema instalado. Nunca "default" (no es un directorio
    /// real -- rechazado antes de tocar el disco). Si `id` era el
    /// activo, el llamador debe activar "default" ANTES de llamar a
    /// esto (mismo orden que exige `aura_style_delete()` del firmware:
    /// nunca dejar `theme_id` apuntando a un directorio que ya no
    /// existe). `@MainActor`: mismo candado que `install()`.
    @MainActor
    static func delete(id: String, mountPath: String, fileManager: FileManager = .default) throws {
        guard id != "default" else { throw ThemeInstallerError.cannotDeleteDefault }
        guard AuraThemeID.isValid(id) else { throw ThemeInstallerError.invalidId(id) }
        guard let root = themesRoot(mountPath: mountPath) else { throw ThemeInstallerError.invalidMountPath }
        guard InstallerFlowRegistry.shared.beginWriting() else { throw ThemeInstallerError.writeLocked }
        defer { InstallerFlowRegistry.shared.endWriting() }

        let target = root.appendingPathComponent(id)
        // Cinturón y tirantes: con el id ya validado, `target` solo
        // puede ser `root/<id-seguro>` -- este chequeo extra es defensa
        // en profundidad, no la validación real.
        guard target.deletingLastPathComponent().path == root.path else {
            throw ThemeInstallerError.invalidId(id)
        }
        try fileManager.removeItem(at: target)
    }

    /// Activa `id` (o `"default"`) escribiendo la clave `theme_id` en
    /// `aura.cfg` -- edita SOLO esa línea (o la agrega si falta),
    /// preserva el resto del archivo. Esto es una edición transitoria,
    /// no la fuente de verdad final: el firmware reescribe el archivo
    /// entero en su próximo `aura_settings_save()` -- pero tiene que
    /// sobrevivir hasta el PRÓXIMO ARRANQUE, que es exactamente cuando
    /// el firmware la lee (`aura_style_boot()`), así que no puede
    /// perderse en el camino. `@MainActor`: mismo candado que `install()`.
    @MainActor
    static func activate(id: String, mountPath: String, fileManager: FileManager = .default) throws {
        guard id == "default" || AuraThemeID.isValid(id) else { throw ThemeInstallerError.invalidId(id) }
        guard isValidMountPath(mountPath) else { throw ThemeInstallerError.invalidMountPath }
        guard InstallerFlowRegistry.shared.beginWriting() else { throw ThemeInstallerError.writeLocked }
        defer { InstallerFlowRegistry.shared.endWriting() }

        let cfgURL = URL(fileURLWithPath: mountPath).appendingPathComponent(auraConfigRelativePath)
        var lines: [String]
        if let text = try? String(contentsOf: cfgURL, encoding: .utf8) {
            lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        } else {
            lines = []
        }

        var replaced = false
        for i in lines.indices where lines[i].hasPrefix("theme_id:") {
            lines[i] = "theme_id: \(id)"
            replaced = true
            break
        }
        if !replaced {
            lines.append("theme_id: \(id)")
        }

        try fileManager.createDirectory(at: cfgURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let text = lines.joined(separator: "\n") + "\n"
        try text.write(to: cfgURL, atomically: true, encoding: .utf8)
    }

    /// `theme_id` vigente en `aura.cfg` -- `"default"` si la clave está
    /// vacía o ausente (mismo criterio que `aura_style_boot()`:
    /// `aura_settings.style_id[0] != '\0'`).
    static func activeThemeID(mountPath: String, fileManager: FileManager = .default) -> String {
        guard isValidMountPath(mountPath) else { return "default" }
        let cfgURL = URL(fileURLWithPath: mountPath).appendingPathComponent(auraConfigRelativePath)
        guard let text = try? String(contentsOf: cfgURL, encoding: .utf8) else { return "default" }
        for line in text.split(separator: "\n") where line.hasPrefix("theme_id:") {
            let value = line.dropFirst("theme_id:".count).trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? "default" : value
        }
        return "default"
    }

    /// `theme_format_supported` del firmware instalado, o `nil` si no
    /// se pudo leer (sin dispositivo, o un firmware anterior a D-289
    /// que no escribe esa clave todavía).
    static func supportedThemeFormat(mountPath: String, fileManager: FileManager = .default) -> Int? {
        guard isValidMountPath(mountPath) else { return nil }
        let cfgURL = URL(fileURLWithPath: mountPath).appendingPathComponent(auraConfigRelativePath)
        guard let text = try? String(contentsOf: cfgURL, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") where line.hasPrefix("theme_format_supported:") {
            return Int(line.dropFirst("theme_format_supported:".count).trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    private static func ditto(from source: URL, to destination: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = [source.path, destination.path]
        let errPipe = Pipe()
        process.standardError = errPipe

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { finished in
                if finished.terminationStatus == 0 {
                    continuation.resume(returning: ())
                } else {
                    let output = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    continuation.resume(throwing: ThemeInstallerError.dittoFailed(output.isEmpty ? "código \(finished.terminationStatus)" : output))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: ThemeInstallerError.dittoFailed(error.localizedDescription))
            }
        }
    }
}
