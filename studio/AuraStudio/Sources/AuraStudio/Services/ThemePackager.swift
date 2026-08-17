import Foundation

enum ThemePackagerError: LocalizedError, Equatable {
    case sourceFontMissing(String)
    case sourceMasksMissing
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .sourceFontMissing(let file):
            return "No se encontró \(file) en la carpeta de origen."
        case .sourceMasksMissing:
            return "La carpeta de origen no tiene icons/masks/."
        case .writeFailed(let reason):
            return "No se pudo escribir el paquete: \(reason)."
        }
    }
}

/// Reempaqueta una carpeta con el layout de `design-system/out/` del
/// firmware (`fonts/a26-<rol>-<px>.fnt`, `icons/masks/*.bmp`, y
/// opcionalmente `icons/{light,dark}/`, `icons/aura/{backgrounds,
/// tile-icons}/`) al formato de tema instalable
/// (`CONTRATO-formato-tema.md`).
///
/// **Fase 2A** (PLAN-themes-impl.md Q4): solo reempaqueta assets YA
/// GENERADOS -- no rasteriza fuentes ni iconos desde el sistema del
/// usuario. Ese rasterizador (Fase 2B, `convttf` embebido + puerto
/// Swift del render de mascaras) es trabajo de seguimiento. Con esto
/// alcanza para el primer caso de uso real: construir el tema Apple
/// desde `~/Aura-local/theme-apple-source/design-system-out/`, que ya
/// tiene los 14 .fnt de SF Pro/Compact y las 801 mascaras horneadas por
/// el pipeline del firmware.
enum ThemePackager {
    static func package(sourceRoot: URL, manifest: AuraThemeManifest, destinationRoot: URL,
                         fileManager: FileManager = .default) throws {
        if fileManager.fileExists(atPath: destinationRoot.path) {
            try fileManager.removeItem(at: destinationRoot)
        }
        try fileManager.createDirectory(at: destinationRoot, withIntermediateDirectories: true)

        let fontsOut = destinationRoot.appendingPathComponent("fonts")
        try fileManager.createDirectory(at: fontsOut, withIntermediateDirectories: true)
        for (role, px) in ThemeFormat.fontRoles {
            let sourceName = "a26-\(role)-\(px).fnt"
            let sourceURL = sourceRoot.appendingPathComponent("fonts").appendingPathComponent(sourceName)
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                throw ThemePackagerError.sourceFontMissing(sourceName)
            }
            try fileManager.copyItem(at: sourceURL, to: fontsOut.appendingPathComponent("\(role).fnt"))
        }

        let masksSource = sourceRoot.appendingPathComponent("icons/masks")
        guard fileManager.fileExists(atPath: masksSource.path) else {
            throw ThemePackagerError.sourceMasksMissing
        }
        try copyDirectory(masksSource, to: destinationRoot.appendingPathComponent("icons/masks"), fileManager: fileManager)

        try copyDirectoryIfPresent(sourceRoot.appendingPathComponent("icons/light"),
                                    to: destinationRoot.appendingPathComponent("icons/light"), fileManager: fileManager)
        try copyDirectoryIfPresent(sourceRoot.appendingPathComponent("icons/dark"),
                                    to: destinationRoot.appendingPathComponent("icons/dark"), fileManager: fileManager)
        try copyDirectoryIfPresent(sourceRoot.appendingPathComponent("icons/aura/backgrounds"),
                                    to: destinationRoot.appendingPathComponent("backgrounds"), fileManager: fileManager)
        try copyDirectoryIfPresent(sourceRoot.appendingPathComponent("icons/aura/tile-icons"),
                                    to: destinationRoot.appendingPathComponent("tile-icons"), fileManager: fileManager)

        let manifestURL = destinationRoot.appendingPathComponent("theme.cfg")
        do {
            try manifest.serialized().write(to: manifestURL, atomically: true, encoding: .utf8)
        } catch {
            throw ThemePackagerError.writeFailed(error.localizedDescription)
        }
    }

    private static func copyDirectoryIfPresent(_ source: URL, to destination: URL, fileManager: FileManager) throws {
        guard fileManager.fileExists(atPath: source.path) else { return }
        try copyDirectory(source, to: destination, fileManager: fileManager)
    }

    private static func copyDirectory(_ source: URL, to destination: URL, fileManager: FileManager) throws {
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
    }
}
