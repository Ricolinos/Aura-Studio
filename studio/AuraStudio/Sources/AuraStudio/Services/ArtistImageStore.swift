import Foundation

/// Fotos de artista para la vista Artistas (ST-020/ST-021). Viven en la
/// biblioteca, junto a las carátulas: `<biblioteca>/.portadas/artistas/
/// <clave>.jpg`, donde la clave es la misma con la que agrupa
/// `LibraryGrouping.artistKey(of:)` (nombre normalizado) codificada como
/// nombre de archivo seguro. No van a `biblioteca.json`: el archivo es
/// la fuente de verdad, igual que las carátulas (`.portadas/<id>.jpg`).
/// Nunca van al iPod (el firmware no muestra artistas con foto).
final class ArtistImageStore {
    let directory: URL
    private var cache: [String: Data] = [:]
    private var misses: Set<String> = []
    private let fileManager: FileManager

    init(libraryRoot: URL, fileManager: FileManager = .default) {
        self.directory = libraryRoot
            .appendingPathComponent(PersistedLibrary.coversDirName, isDirectory: true)
            .appendingPathComponent("artistas", isDirectory: true)
        self.fileManager = fileManager
    }

    /// Nombre de archivo estable y seguro para una clave de artista:
    /// letras/números/guiones tal cual, el resto como `_XX` -- así
    /// "gorillaz" y "Gorillaz" (misma clave normalizada) comparten foto y
    /// nada raro llega al sistema de archivos.
    static func fileName(forArtistKey key: String) -> String {
        var out = ""
        for scalar in key.unicodeScalars {
            if scalar.isASCII, (scalar.properties.isAlphabetic || ("0"..."9").contains(Character(scalar)) || scalar == "-") {
                out.unicodeScalars.append(scalar)
            } else if scalar == " " {
                out.append("-")
            } else {
                out += String(format: "_%02x", scalar.value & 0xFF)
            }
        }
        if out.isEmpty { out = "artista" }
        return String(out.prefix(120)) + ".jpg"
    }

    func url(forArtistKey key: String) -> URL {
        directory.appendingPathComponent(Self.fileName(forArtistKey: key))
    }

    func image(forArtistKey key: String) -> Data? {
        if let cached = cache[key] { return cached }
        if misses.contains(key) { return nil }
        guard let data = try? Data(contentsOf: url(forArtistKey: key)), !data.isEmpty else {
            misses.insert(key)
            return nil
        }
        cache[key] = data
        return data
    }

    func hasImage(forArtistKey key: String) -> Bool {
        image(forArtistKey: key) != nil
    }

    func save(_ data: Data, forArtistKey key: String) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url(forArtistKey: key), options: .atomic)
        cache[key] = data
        misses.remove(key)
    }

    func remove(forArtistKey key: String) {
        try? fileManager.removeItem(at: url(forArtistKey: key))
        cache[key] = nil
        misses.remove(key)
    }

    /// Al cambiar de biblioteca (o tras descargar en lote) se olvida lo
    /// leido para releer del disco.
    func invalidate() {
        cache.removeAll()
        misses.removeAll()
    }
}
