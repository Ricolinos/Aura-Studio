import Foundation

/// ST-189 (paridad con Windows ST-171): que el disco de la biblioteca no
/// esté conectado **es un estado, no un error**.
///
/// El dueño reportó esto en Windows -- abrió la app con su disco externo
/// sin montar y le salió un diálogo de "Algo salió mal". En macOS no
/// salta ningún diálogo, pero pasa algo peor en silencio: con la
/// biblioteca en `/Volumes/Mac Externo/…` y ese volumen desmontado,
/// `ensureLibraryStructure()` hace `createDirectory(withIntermediateDirectories:)`
/// sobre esa ruta y **macOS la crea igual**, como carpetas normales
/// dentro de `/Volumes`. El resultado es una biblioteca vacía recién
/// inventada, tapando el punto de montaje del disco de verdad; y el
/// catálogo vacío que se guarda encima parece "no tenías nada".
///
/// La regla, igual que en Windows: **decide el volumen, no la carpeta**.
/// Sin el volumen no se lee, no se escribe y no se concluye nada. Con el
/// volumen presente, una carpeta que todavía no existe es una biblioteca
/// **nueva** y se comporta como siempre -- es lo que mantiene intacto el
/// primer arranque, que fue justamente lo que Windows tuvo que corregir
/// sobre sí mismo antes de commitear.
enum LibraryAvailability: Equatable, Sendable {
    case available
    /// El volumen que contiene la biblioteca no está montado.
    case volumeMissing
}

enum LibraryRoot {
    /// ¿Está montado el volumen que contiene `root`?
    ///
    /// En macOS los volúmenes que no son el de arranque se montan bajo
    /// `/Volumes/<nombre>`. Se resuelve por **el punto de montaje más
    /// largo que sea prefijo de la ruta**: si el único que califica es
    /// `/` pero la ruta cuelga de `/Volumes/`, entonces ese volumen no
    /// está -- y lo que hay (o lo que se crearía) en `/Volumes/<nombre>`
    /// son carpetas comunes, no el disco.
    ///
    /// Una ruta que NO cuelga de `/Volumes/` (la carpeta de Documentos,
    /// por ejemplo) vive en el volumen de arranque, que por definición
    /// está montado.
    static func volumeIsMounted(_ root: URL,
                                mountedVolumes: [URL]? = nil,
                                fileManager: FileManager = .default) -> Bool {
        let path = root.standardizedFileURL.path
        let mounted = (mountedVolumes ?? fileManager.mountedVolumeURLs(
            includingResourceValuesForKeys: nil,
            options: [.skipHiddenVolumes]) ?? [])
            .map { $0.standardizedFileURL.path }

        let matches = mounted.filter { mountPoint in
            if mountPoint == "/" { return true }
            return path == mountPoint || path.hasPrefix(mountPoint + "/")
        }
        let longest = matches.max { $0.count < $1.count }

        guard let longest else { return false }
        if longest == "/" && path.hasPrefix("/Volumes/") {
            // El volumen externo no está montado: lo que cuelga de
            // `/Volumes/<nombre>` sería una carpeta común.
            return false
        }
        return true
    }

    static func availability(of root: URL,
                             mountedVolumes: [URL]? = nil,
                             fileManager: FileManager = .default) -> LibraryAvailability {
        volumeIsMounted(root, mountedVolumes: mountedVolumes, fileManager: fileManager)
            ? .available
            : .volumeMissing
    }

    /// El nombre del volumen que la ruta espera encontrar, para poder
    /// decírselo al usuario ("conecta «Mac Externo»"). `nil` si la ruta
    /// no cuelga de `/Volumes/`.
    static func expectedVolumeName(of root: URL) -> String? {
        let path = root.standardizedFileURL.path
        guard path.hasPrefix("/Volumes/") else { return nil }
        let rest = path.dropFirst("/Volumes/".count)
        guard let name = rest.split(separator: "/", maxSplits: 1).first, !name.isEmpty else { return nil }
        return String(name)
    }
}
