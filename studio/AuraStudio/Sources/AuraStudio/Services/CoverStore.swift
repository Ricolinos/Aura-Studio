import CryptoKit
import Foundation

/// PLAN-studio-rendimiento-2.md Fase 5 (ST-185): el único lugar que sabe
/// dónde vive una carátula y cómo se la identifica.
///
/// Diagnóstico §0.8: `TrackMetadata.coverArtData` guardaba el JPEG
/// ENTERO en memoria, por ítem -- unos 180 MB con 12 000 canciones, y
/// eso aunque la carátula del álbum sea la misma para sus doce pistas.
/// Los archivos ya vivían en `.portadas/<id>.jpg` desde siempre (los
/// escribe `CatalogPersister`); lo que sobraba era la copia en RAM.
///
/// El identificador es `coverHash`: **SHA-256 de los bytes del archivo,
/// hexadecimal en MAYÚSCULAS, sin separadores** (64 caracteres). Es el
/// mismo formato que ya calcula `CoverThumbnailKey` en Windows, fijado
/// con la sesión maestra para que las dos plataformas compartan la
/// definición del campo (W3/ST-208 lo implementa allá).
///
/// Semántica, tal como quedó acordada:
/// - `coverRelativePath == nil` significa **no hay carátula**;
/// - `coverHash == nil` significa **no se sabe** (catálogo viejo), no
///   "no hay";
/// - invariante: sin ruta no hay hash.
enum CoverStore {
    static func directory(in libraryRoot: URL) -> URL {
        libraryRoot.appendingPathComponent(PersistedLibrary.coversDirName, isDirectory: true)
    }

    /// El nombre en disco NO cambia con esto (`<id>.jpg`): el hash
    /// identifica el contenido, no nombra el archivo. Cambiarlo habría
    /// obligado a mover 1 000 archivos en la biblioteca del dueño para
    /// no ganar nada.
    static func url(forItem id: UUID, in libraryRoot: URL) -> URL {
        directory(in: libraryRoot).appendingPathComponent("\(id.uuidString).jpg")
    }

    static func relativePath(forItem id: UUID) -> String {
        "\(PersistedLibrary.coversDirName)/\(id.uuidString).jpg"
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02X", $0) }.joined()
    }

    /// El hash de un archivo ya escrito -- para la migración de un
    /// catálogo guardado antes de que el campo existiera.
    static func hashOfFile(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return hash(data)
    }

    static func read(_ url: URL?) -> Data? {
        guard let url else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Escribe la carátula de un ítem y devuelve dónde quedó y su hash.
    @discardableResult
    static func write(_ data: Data, forItem id: UUID, in libraryRoot: URL) throws -> (url: URL, hash: String) {
        let directory = directory(in: libraryRoot)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = url(forItem: id, in: libraryRoot)
        try data.write(to: url, options: .atomic)
        return (url, hash(data))
    }

    static func remove(forItem id: UUID, in libraryRoot: URL) {
        try? FileManager.default.removeItem(at: url(forItem: id, in: libraryRoot))
    }
}
