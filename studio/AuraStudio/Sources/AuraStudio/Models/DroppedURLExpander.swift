import Foundation

/// Expande las URLs de un drag-and-drop: si alguna es una carpeta, la
/// reemplaza por la lista plana de archivos que contiene (cualquier
/// profundidad); las que ya son archivos se devuelven tal cual. No
/// clasifica por tipo de medio -- eso lo sigue haciendo
/// `LibraryItemKind.classify` en `LibraryViewModel.addDroppedFiles`, sin
/// duplicar esa logica aca. Pura y sin `@MainActor` a proposito: asi se
/// puede probar directo contra una carpeta temporal real, sin necesidad
/// de un `LibraryViewModel`.
enum DroppedURLExpander {
    static func expand(_ urls: [URL]) -> [URL] {
        urls.flatMap { url -> [URL] in
            isDirectory(url) ? filesInsideDirectory(url) : [url]
        }
    }

    /// Tambien la usa `LibraryViewModel` para decidir cuales de las URLs
    /// del drop ORIGINAL son carpetas (y por lo tanto candidatas a
    /// "biblioteca vinculada", ver `AppPreferences.linkedLibraryFolders`)
    /// -- una sola forma de responder la pregunta en toda la app.
    static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    /// `.skipsHiddenFiles` descarta `.DS_Store`/dotfiles sueltos;
    /// `.skipsPackageDescendants` evita bajar dentro de un `.app` o
    /// cualquier otro paquete que hubiera quedado adentro de la carpeta
    /// soltada -- un folder-drop no deberia desarmar un bundle ajeno en
    /// archivos sueltos. El `errorHandler` hace que una subcarpeta sin
    /// permisos (o que desaparece a mitad de la enumeracion) se salte en
    /// vez de abortar el resto: sin ese closure, `FileManager.enumerator`
    /// devuelve `nil` directo ante el primer error y se perderia TODA la
    /// carpeta por un solo item ilegible.
    private static func filesInsideDirectory(_ directory: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return [] }

        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            let isDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if !isDir {
                files.append(fileURL)
            }
        }
        return files
    }
}
