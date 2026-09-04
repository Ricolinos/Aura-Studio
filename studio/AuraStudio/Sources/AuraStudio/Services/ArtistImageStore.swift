import Foundation

/// Fotos de artista para la vista Artistas (ST-031/ST-032). Viven en la
/// biblioteca, junto a las carátulas: `<biblioteca>/.portadas/artistas/
/// <clave>.jpg`, donde la clave es la misma con la que agrupa
/// `LibraryGrouping.artistKey(of:)` (nombre normalizado) codificada como
/// nombre de archivo seguro. No van a `biblioteca.json`: el archivo es
/// la fuente de verdad, igual que las carátulas (`.portadas/<id>.jpg`).
/// PLAN-biblioteca-medios-v2.md §3.5 (Tanda 5): viajan reducidas a
/// `.rockbox/aura/artists/<mismo nombre de archivo>` en cada sync
/// (`LibrarySync.writeArtistImages`) -- el firmware ya sabe leerlas
/// (D-322, contrato v6 §D.3) y mostrarlas en círculo en Música →
/// Artistas.
/// Se lee desde las vistas (MainActor) y se escribe desde la descarga
/// (`LibraryViewModel.fetchArtistImages`, tambien MainActor) -- pero
/// para que el tipo sea `Sendable` de verdad (Swift 6 estricto), el
/// cache en memoria va bajo un `NSLock` en vez de confiar en quien llama.
final class ArtistImageStore: @unchecked Sendable {
    let directory: URL
    private var cache: [String: Data] = [:]
    private var misses: Set<String> = []
    private let lock = NSLock()
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
        lock.lock(); defer { lock.unlock() }
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

    /// ST-141: la foto se guarda **cuadrada** (lado = min(lado corto,
    /// 1000)). El contrato §D.3 exige cuadradas en el iPod y hasta v18
    /// Studio mandaba el lado mayor a 128 con la proporción original --
    /// se arregla desde el origen, no al sincronizar, para que la vista
    /// Artistas y el aparato muestren la misma imagen.
    func save(_ data: Data, forArtistKey key: String) throws {
        let data = CoverArtNormalizer.normalized(data)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url(forArtistKey: key), options: .atomic)
        lock.lock(); defer { lock.unlock() }
        cache[key] = data
        misses.remove(key)
    }

    func remove(forArtistKey key: String) {
        try? fileManager.removeItem(at: url(forArtistKey: key))
        lock.lock(); defer { lock.unlock() }
        cache[key] = nil
        misses.remove(key)
    }

    /// Al cambiar de biblioteca (o tras descargar en lote) se olvida lo
    /// leido para releer del disco.
    func invalidate() {
        lock.lock(); defer { lock.unlock() }
        cache.removeAll()
        misses.removeAll()
    }
}
