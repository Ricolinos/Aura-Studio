import Foundation

/// ST-058 / CONTRATO-firmware-studio.md v11: actualizaciones selectivas.
///
/// Actualizar extraía el `rockbox.zip` completo sobre el iPod -- 9,431
/// archivos en Aura, y cada archivo chico paga su ida y vuelta USB+FAT:
/// minutos. Medido entre releases consecutivos reales cambian ~5 archivos
/// (~2 MB), porque las builds de Rockbox son reproducibles. Este módulo
/// es la contabilidad que lo aprovecha:
///
///  - `entriesFromZip`: la lista (ruta, tamaño, CRC32) del zip embebido,
///    leída de su directorio central vía `unzip -lv` -- no se calcula
///    ningún hash.
///  - `.rockbox/aura/install_manifest.cfg`: lo que Studio dejó instalado
///    la última vez (contrato v11; los firmwares lo ignoran). Es POR
///    ÁRBOL (v10): viaja con su árbol al dormir/despertar y nunca se
///    espeja a los dormidos.
///  - `diff`: qué extraer (nuevo o cambiado) y qué borrar (desapareció
///    del zip -- la extracción-merge de antes dejaba huérfanos para
///    siempre).
///
/// La decisión delta-vs-completo y el respaldo a extracción completa
/// viven en `InstallerViewModel.copyFirmwareFiles` -- cualquier duda
/// (sin manifiesto, ilegible, error a mitad) cae a lo de siempre.
struct InstallManifest: Equatable {
    struct Entry: Equatable {
        let path: String
        let size: UInt64
        let crc32: UInt32
    }

    static let headerLine = "# aura-install-manifest v1"
    static let relativePath = ".rockbox/aura/install_manifest.cfg"

    var tag: String?
    /// Ruta → entrada. Solo archivos (nunca directorios).
    var entries: [String: Entry]

    // MARK: - Zip

    /// Entradas del zip según su directorio central (`unzip -lv`), sin
    /// extraer nada. Filtra directorios. Lanza si unzip falla o si la
    /// salida no trae ninguna entrada reconocible (un zip válido nunca
    /// está vacío aquí: siempre trae `.rockbox/...`).
    static func entriesFromZip(_ zipURL: URL) throws -> [String: Entry] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-lv", zipURL.path]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let text = String(data: data, encoding: .utf8) else {
            throw InstallerError.processFailed(exitCode: process.terminationStatus,
                                               output: "unzip -lv falló")
        }
        let entries = parseUnzipListing(text)
        guard !entries.isEmpty else {
            throw InstallerError.processFailed(exitCode: -1,
                                               output: "unzip -lv no devolvió entradas")
        }
        return entries
    }

    /// Formato de `unzip -lv` (columnas fijas, nombre al final):
    /// `  Length   Method    Size  Cmpr    Date    Time   CRC-32   Name`
    /// `   1234  Defl:N     456  63% 08-23-2026 03:04 89abcdef  .rockbox/x`
    static func parseUnzipListing(_ text: String) -> [String: Entry] {
        var result: [String: Entry] = [:]
        let pattern = #"^\s*(\d+)\s+\S+\s+\d+\s+-?\d+%\s+\S+\s+\S+\s+([0-9a-fA-F]{8})\s\s(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return result }
        for line in text.split(separator: "\n") {
            let s = String(line)
            let range = NSRange(s.startIndex..., in: s)
            guard let m = regex.firstMatch(in: s, range: range),
                  let sizeRange = Range(m.range(at: 1), in: s),
                  let crcRange = Range(m.range(at: 2), in: s),
                  let nameRange = Range(m.range(at: 3), in: s) else { continue }
            let name = String(s[nameRange])
            guard !name.hasSuffix("/") else { continue } // directorio
            guard let size = UInt64(s[sizeRange]),
                  let crc = UInt32(s[crcRange], radix: 16) else { continue }
            result[name] = Entry(path: name, size: size, crc32: crc)
        }
        return result
    }

    // MARK: - install_manifest.cfg

    func serialized() -> String {
        var lines = [Self.headerLine]
        if let tag { lines.append("tag: \(tag)") }
        for entry in entries.values.sorted(by: { $0.path < $1.path }) {
            lines.append(String(format: "%08x %llu %@", entry.crc32, entry.size, entry.path))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// `nil` si el texto no empieza con la cabecera v1 (otra versión, o
    /// no es un manifiesto): el llamador cae a extracción completa.
    static func parse(_ text: String) -> InstallManifest? {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)[...]
        guard let first = lines.first,
              first.trimmingCharacters(in: .whitespaces) == headerLine else { return nil }
        lines = lines.dropFirst()
        var tag: String?
        var entries: [String: Entry] = [:]
        for raw in lines {
            let line = String(raw)
            if line.hasPrefix("tag: ") {
                tag = String(line.dropFirst("tag: ".count)).trimmingCharacters(in: .whitespaces)
                continue
            }
            // <crc 8 hex> <size> <path...>
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3,
                  let crc = UInt32(parts[0], radix: 16), parts[0].count == 8,
                  let size = UInt64(parts[1]) else { continue }
            let path = String(parts[2])
            guard !path.isEmpty else { continue }
            entries[path] = Entry(path: path, size: size, crc32: crc)
        }
        return InstallManifest(tag: tag, entries: entries)
    }

    static func read(volumeRoot: URL, fileManager: FileManager = .default) -> InstallManifest? {
        let url = volumeRoot.appendingPathComponent(relativePath)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parse(text)
    }

    func write(volumeRoot: URL, fileManager: FileManager = .default) throws {
        let url = volumeRoot.appendingPathComponent(Self.relativePath)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
        try serialized().write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Diff

    struct Delta: Equatable {
        /// Rutas del zip nuevo que hay que escribir (nuevas o cambiadas).
        var toExtract: [String]
        /// Rutas instaladas que desaparecieron del zip nuevo.
        var toDelete: [String]
    }

    static func delta(installed: [String: Entry], new: [String: Entry]) -> Delta {
        var toExtract: [String] = []
        for (path, entry) in new {
            if let old = installed[path], old.size == entry.size, old.crc32 == entry.crc32 {
                continue
            }
            toExtract.append(path)
        }
        // Solo bajo .rockbox/: jamás borrar fuera del árbol del firmware,
        // pase lo que pase con un manifiesto corrupto.
        let toDelete = installed.keys.filter { new[$0] == nil && $0.hasPrefix(".rockbox/") }
        return Delta(toExtract: toExtract.sorted(), toDelete: toDelete.sorted())
    }
}
