import Foundation

/// Registro de un archivo ya sincronizado, para decidir en la proxima
/// pasada si hace falta copiarlo de nuevo. Se compara por tamaño +
/// fecha de modificacion (igual que rsync por defecto) en vez de
/// hashear cada archivo entero en cada sync -- con bibliotecas de miles
/// de canciones, hashear todo cada vez seria demasiado lento para algo
/// que en la gran mayoria de los casos no cambio.
struct SyncRecord: Codable, Equatable {
    let sourcePath: String
    let sourceSize: Int64
    let sourceModifiedAt: TimeInterval
    let destinationRelativePath: String
}

struct SyncManifest: Codable, Equatable {
    var records: [String: SyncRecord] // key = sourcePath

    static let empty = SyncManifest(records: [:])
}

enum SyncPlanAction: Equatable {
    case copy
    case skip
}

struct SyncPlanItem: Equatable {
    let sourcePath: String
    let destinationRelativePath: String
    let action: SyncPlanAction
}

/// Logica pura de diferenciacion: dado un manifiesto anterior y el
/// estado actual de los archivos preparados, decide que copiar y que
/// saltear. Separada de LibrarySync (que hace la copia real) para que
/// se pueda testear sin tocar disco ni un iPod de verdad.
enum SyncPlanner {
    static func plan(
        current: [(sourcePath: String, size: Int64, modifiedAt: TimeInterval, destinationRelativePath: String)],
        previousManifest: SyncManifest
    ) -> [SyncPlanItem] {
        current.map { file in
            if let previous = previousManifest.records[file.sourcePath],
               previous.sourceSize == file.size,
               previous.sourceModifiedAt == file.modifiedAt,
               previous.destinationRelativePath == file.destinationRelativePath {
                return SyncPlanItem(sourcePath: file.sourcePath, destinationRelativePath: file.destinationRelativePath, action: .skip)
            }
            return SyncPlanItem(sourcePath: file.sourcePath, destinationRelativePath: file.destinationRelativePath, action: .copy)
        }
    }
}

/// Ejecuta la sincronizacion real contra el volumen montado del iPod:
/// copia solo lo que `SyncPlanner` marco como `.copy`, actualiza el
/// manifiesto, y borra el indice de tagcache del dispositivo para que
/// Aura lo reconstruya solo en el proximo arranque -- reusa la misma
/// logica de reconstruccion ya verificada en el firmware (D-021/D-023
/// en DECISIONS.md), en vez de intentar hablarle al formato binario de
/// tagcache directamente desde macOS.
struct LibrarySync {
    static let manifestRelativePath = ".rockbox/aura/sync_manifest.json"
    static let tagcacheFilesToClear = [
        ".rockbox/database_idx.tcd",
        ".rockbox/database_0.tcd",
        ".rockbox/database_1.tcd",
        ".rockbox/database_2.tcd",
        ".rockbox/database_3.tcd",
        ".rockbox/database_4.tcd",
        ".rockbox/database_5.tcd",
        ".rockbox/database_6.tcd",
    ]

    let volumeRoot: URL
    private let fileManager = FileManager.default

    func loadManifest() -> SyncManifest {
        let url = volumeRoot.appendingPathComponent(Self.manifestRelativePath)
        guard let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(SyncManifest.self, from: data) else {
            return .empty
        }
        return manifest
    }

    func saveManifest(_ manifest: SyncManifest) throws {
        let url = volumeRoot.appendingPathComponent(Self.manifestRelativePath)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: url, options: .atomic)
    }

    /// `items` son los LibraryItem ya procesados (metadata escrita,
    /// video transcodificado, foto redimensionada) con `preparedURL`
    /// listo para copiar. Devuelve cuantos archivos se copiaron de
    /// verdad (para mostrarle al usuario cuanto trabajo se ahorro el
    /// sync diferencial).
    @discardableResult
    func sync(items: [LibraryItem]) throws -> Int {
        var manifest = loadManifest()
        var copied = 0

        let currentFiles = try items.compactMap { item -> (sourcePath: String, size: Int64, modifiedAt: TimeInterval, destinationRelativePath: String)? in
            guard let prepared = item.preparedURL else { return nil }
            let attrs = try fileManager.attributesOfItem(atPath: prepared.path)
            let size = (attrs[.size] as? Int64) ?? 0
            let modified = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            let destRelative = destinationRelativePath(for: item)
            return (item.sourceURL.path, size, modified, destRelative)
        }

        let plan = SyncPlanner.plan(current: currentFiles, previousManifest: manifest)

        for planItem in plan {
            guard planItem.action == .copy else { continue }
            guard let item = items.first(where: { $0.sourceURL.path == planItem.sourcePath }),
                  let prepared = item.preparedURL else { continue }

            let destination = volumeRoot.appendingPathComponent(planItem.destinationRelativePath)
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: prepared, to: destination)
            copied += 1

            let attrs = try fileManager.attributesOfItem(atPath: prepared.path)
            manifest.records[planItem.sourcePath] = SyncRecord(
                sourcePath: planItem.sourcePath,
                sourceSize: (attrs[.size] as? Int64) ?? 0,
                sourceModifiedAt: (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0,
                destinationRelativePath: planItem.destinationRelativePath
            )
        }

        try saveManifest(manifest)
        if copied > 0 {
            triggerFirmwareDBRebuild()
        }
        return copied
    }

    private func destinationRelativePath(for item: LibraryItem) -> String {
        let filename = item.preparedURL?.lastPathComponent ?? item.sourceURL.lastPathComponent
        switch item.kind {
        case .music: return "Music/\(filename)"
        case .video: return "Videos/\(filename)"
        case .photo: return "Photos/\(filename)"
        case .unsupported: return "Unsupported/\(filename)"
        }
    }

    /// Borra el indice de tagcache del dispositivo. No es destructivo
    /// para la musica en si (solo el indice de busqueda, que Aura
    /// reconstruye solo en el proximo arranque, ver D-021) -- es la
    /// forma mas simple y robusta de decirle al firmware "hay archivos
    /// nuevos" sin reimplementar el formato binario de tagcache.
    private func triggerFirmwareDBRebuild() {
        for relativePath in Self.tagcacheFilesToClear {
            let url = volumeRoot.appendingPathComponent(relativePath)
            try? fileManager.removeItem(at: url)
        }
    }
}
