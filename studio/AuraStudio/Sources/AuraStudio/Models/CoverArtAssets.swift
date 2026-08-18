import Foundation

/// ST-012 / `docs/contracts/library-layout-v1.md` SS2: las caratulas son
/// ASSETS asociados a sus entradas de Musica o Video, nunca entradas
/// propias del modulo de Imagenes. Este modulo puro (sin `@MainActor`,
/// sin acceso a la biblioteca) contesta dos preguntas:
///
///  - al importar: ¿este JPEG/PNG que venia en el drop es una caratula
///    (y por lo tanto NO se agrega a Imagenes)?
///  - al leer metadatos de una cancion: ¿hay una caratula de carpeta al
///    lado (`cover.jpg`, `folder.jpg`...) que sirva de portada?
///
/// Los nombres reconocidos son los mismos que busca el firmware
/// (`apps/recorder/albumart.c`: `cover.*`, `folder.jpg`, `<album>.*`) mas
/// los sinonimos que traen los rippers/tiendas habituales.
enum CoverArtAssets {
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "bmp", "heic", "tiff"]
    static let audioExtensions: Set<String> = ["flac", "mp3", "m4a", "wav", "aiff", "aif"]
    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "avi", "mkv", "mpg", "mpeg"]
    static var audioVideoExtensions: Set<String> { audioExtensions.union(videoExtensions) }
    /// Nombres base (sin extension, minusculas) que casi siempre son una
    /// caratula y no una foto personal.
    static let coverBaseNames: Set<String> = [
        "cover", "folder", "front", "back", "album", "albumart", "albumartsmall",
        "artwork", "art", "thumb", "thumbnail", "booklet", "cd", "disc", "inlay",
        "poster",
    ]
    /// Orden de preferencia para elegir LA portada de una carpeta.
    static let preferredCoverBaseNames = ["cover", "folder", "front", "album", "albumart", "artwork"]

    static func isImage(_ url: URL) -> Bool {
        imageExtensions.contains(url.pathExtension.lowercased())
    }

    static func isAudioOrVideo(_ url: URL) -> Bool {
        audioVideoExtensions.contains(url.pathExtension.lowercased())
    }

    static func isAudio(_ url: URL) -> Bool {
        audioExtensions.contains(url.pathExtension.lowercased())
    }

    static func isVideo(_ url: URL) -> Bool {
        videoExtensions.contains(url.pathExtension.lowercased())
    }

    /// `cover.jpg`, `Folder.PNG`, `front-1.jpg`, `cover (1).jpeg`,
    /// `AlbumArt_{...}_Large.jpg` (Windows Media Player)...
    static func hasCoverLikeName(_ url: URL) -> Bool {
        guard isImage(url) else { return false }
        let base = url.deletingPathExtension().lastPathComponent.lowercased()
        if coverBaseNames.contains(base) { return true }
        // Sufijos numericos / separadores: "cover 2", "front-1", "cover_small"
        let stripped = base
            .replacingOccurrences(of: "[\\s_\\-()]+", with: " ", options: .regularExpression)
            .split(separator: " ")
        if let first = stripped.first, coverBaseNames.contains(String(first)) { return true }
        if base.hasPrefix("albumart") { return true }
        return false
    }

    /// Lo que un conjunto de URLs (el drop expandido, o la biblioteca)
    /// aporta como CONTEXTO para decidir si una imagen es caratula:
    /// directorios con audio (carpetas de album) y nombres base de los
    /// videos (su poster `<video>.jpg` viaja al lado). Solo AUDIO define
    /// "carpeta de album": una carpeta de fotos de un viaje puede traer
    /// clips `.mov` y sus fotos siguen siendo fotos.
    struct DropContext {
        var audioDirectories: Set<String> = []
        /// "<directorio>/<nombre base>" de cada video del conjunto.
        var videoBaseNames: Set<String> = []

        init(urls: [URL]) {
            for url in urls {
                if CoverArtAssets.isAudio(url) {
                    audioDirectories.insert(url.deletingLastPathComponent().standardizedFileURL.path)
                } else if CoverArtAssets.isVideo(url) {
                    videoBaseNames.insert(url.deletingPathExtension().standardizedFileURL.path)
                }
            }
        }
    }

    /// Decision de importacion. Una imagen es caratula/poster (y no foto) si:
    ///  - vive en un directorio que en el MISMO conjunto trae audio (un
    ///    album soltado entero con su `cover.jpg`, se llame como se llame), o
    ///  - es el poster de un video del conjunto (mismo nombre base), o
    ///  - tiene nombre de caratula y el drop NO fue dirigido al modulo de
    ///    Imagenes (soltarla a proposito en Fotos gana: ahi el usuario
    ///    dijo "esto es una foto"), o
    ///  - tiene nombre de caratula y en disco convive con audio (evidencia
    ///    fuera del drop, p. ej. un `cover.jpg` reimportado desde el iPod
    ///    o arrastrado suelto desde la carpeta del album).
    static func isCoverAsset(_ url: URL,
                             context: DropContext,
                             droppedIntoPhotos: Bool,
                             fileManager: FileManager = .default) -> Bool {
        guard isImage(url) else { return false }
        let dir = url.deletingLastPathComponent().standardizedFileURL.path
        if context.audioDirectories.contains(dir) { return true }
        if context.videoBaseNames.contains(url.deletingPathExtension().standardizedFileURL.path) { return true }
        guard hasCoverLikeName(url) else { return false }
        if !droppedIntoPhotos { return true }
        return directoryContainsAudio(url.deletingLastPathComponent(), fileManager: fileManager)
    }

    static func directoryContainsAudio(_ directory: URL, fileManager: FileManager = .default) -> Bool {
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return false }
        return names.contains { audioExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
    }

    /// La caratula de carpeta de una cancion, si existe: mismo criterio de
    /// nombres que el firmware, en orden de preferencia; jpg/jpeg/png.
    static func folderCover(near audioURL: URL, fileManager: FileManager = .default) -> URL? {
        let directory = audioURL.deletingLastPathComponent()
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return nil }
        let images = names.filter { imageExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
        guard !images.isEmpty else { return nil }
        for preferred in preferredCoverBaseNames {
            if let match = images.first(where: { ($0 as NSString).deletingPathExtension.lowercased() == preferred }) {
                return directory.appendingPathComponent(match)
            }
        }
        // `<album>.jpg` u otro nombre de caratula reconocido
        if let match = images.first(where: { hasCoverLikeName(directory.appendingPathComponent($0)) }) {
            return directory.appendingPathComponent(match)
        }
        return nil
    }
}
