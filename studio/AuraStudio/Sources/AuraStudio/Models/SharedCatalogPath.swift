import Foundation

/// Resolucion TOLERANTE de las rutas relativas que trae
/// `biblioteca.json` (ST-102).
///
/// La biblioteca es COMPARTIDA: el dueno apunta la misma carpeta desde
/// Aura Studio en la Mac y desde Aura Studio en Windows, y las dos apps
/// escriben el mismo catalogo. El formato de ESCRITURA no cambia -- esta
/// app sigue guardando siempre rutas relativas con `/`, como siempre --
/// pero la LECTURA tiene que aguantar lo que la otra app haya dejado:
///
/// 1. **Separadores `\`.** Windows arma sus rutas con `Path.Combine`, y
///    lo que queda en el JSON es `Música\Soda Stereo\Signos\01 x.mp3`.
///    Pegado con `appendingPathComponent` eso es UN solo componente con
///    barras invertidas adentro, un archivo que no existe. Y como
///    `loadCatalog()` omite en silencio todo item cuyo archivo no este
///    (criterio correcto: de un archivo ausente no hay nada que
///    preparar ni sincronizar), el resultado no es un error sino una
///    BIBLIOTECA VACIA -- indistinguible de "todavia no agregaste
///    nada". Fue exactamente lo que paso con el catalogo real del
///    dueno: 401 elementos, 0 visibles.
///
/// 2. **Normalizacion Unicode.** `Música` puede venir precompuesta
///    (NFC, como la escribe Windows) o descompuesta (NFD, como la deja
///    macOS). APFS y HFS+ comparan sin distinguir las dos formas, asi
///    que ahi da igual; en exFAT o en un recurso compartido por red no,
///    y ahi la misma carpeta "no existe". Cuesta dos lineas cubrirlo.
///
/// El orden de los candidatos importa: **la ruta literal va primero**.
/// En macOS `\` es un caracter valido en un nombre de archivo, asi que
/// una biblioteca hecha aca que tenga un archivo con barra invertida en
/// el nombre sigue resolviendo a ese archivo y no a una interpretacion
/// inventada. La tolerancia solo entra cuando la ruta literal no existe.
enum SharedCatalogPath {
    /// Traduce separadores de Windows a `/`. No toca nada mas: no
    /// normaliza, no colapsa, no resuelve `..`.
    static func withUnixSeparators(_ relative: String) -> String {
        relative.replacingOccurrences(of: "\\", with: "/")
    }

    /// Las formas en que una misma ruta relativa pudo haber quedado
    /// escrita, de la mas literal a la mas tolerante y sin repetidos.
    static func candidates(for relative: String) -> [String] {
        var result: [String] = []
        for separators in [relative, withUnixSeparators(relative)] {
            for form in [separators,
                         separators.precomposedStringWithCanonicalMapping,
                         separators.decomposedStringWithCanonicalMapping] {
                if !result.contains(form) { result.append(form) }
            }
        }
        return result
    }

    /// `true` si la ruta no es relativa a la carpeta de biblioteca sino
    /// absoluta: `/Users/...` (modo "sin copiar medios", D-192) o
    /// `C:\Users\...` / `\\servidor\recurso` de un catalogo escrito en
    /// Windows. Las de Windows no se pueden resolver desde aca, y lo
    /// correcto es tratarlas como archivo ausente (el item se omite),
    /// nunca pegarlas debajo de la raiz de la biblioteca.
    static func isAbsolute(_ path: String) -> Bool {
        if path.hasPrefix("/") || path.hasPrefix("\\\\") { return true }
        // Letra de unidad de Windows: "C:\..." o "V:/...".
        let characters = Array(path)
        guard characters.count >= 3, characters[1] == ":",
              characters[0].isLetter, characters[0].isASCII else { return false }
        return characters[2] == "\\" || characters[2] == "/"
    }

    /// `true` si la ruta absoluta es de otra plataforma y por lo tanto
    /// no puede existir en esta Mac.
    static func isForeignAbsolute(_ path: String) -> Bool {
        isAbsolute(path) && !path.hasPrefix("/")
    }

    /// La URL del archivo que esa ruta del catalogo designa, o `nil` si
    /// no existe ninguno.
    ///
    /// Una ruta absoluta de macOS se prueba tal cual (D-192); una
    /// absoluta de Windows devuelve `nil` sin tocar disco.
    static func resolve(_ relative: String,
                        in root: URL,
                        fileManager: FileManager = .default) -> URL? {
        guard !relative.isEmpty else { return nil }
        if isForeignAbsolute(relative) { return nil }
        if relative.hasPrefix("/") {
            let url = URL(fileURLWithPath: relative)
            return fileManager.fileExists(atPath: url.path) ? url : nil
        }
        for candidate in candidates(for: relative) {
            let url = root.appendingPathComponent(candidate)
            if fileManager.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    /// La caratula de un item.
    ///
    /// Ademas de la tolerancia de `resolve`, cae al nombre CANONICO
    /// (`.portadas/<UUID>.jpg`, que es el unico que esta app escribe)
    /// cuando la ruta anotada no resuelve. Hace falta porque las dos
    /// apps nombran ese archivo distinto para el MISMO id: macOS usa
    /// `uuidString` de Foundation (mayusculas y con guiones,
    /// `F26DBF19-0C21-...jpg`) y Windows el hexadecimal pelado del
    /// `Guid` (`f26dbf190c21...jpg`). Sin este respaldo, un catalogo
    /// guardado del otro lado deja sin caratula a canciones cuya imagen
    /// SI esta en `.portadas/`.
    static func coverURL(recorded: String?,
                         itemID: UUID,
                         in root: URL,
                         fileManager: FileManager = .default) -> URL? {
        if let recorded, let url = resolve(recorded, in: root, fileManager: fileManager) {
            return url
        }
        let canonical = "\(PersistedLibrary.coversDirName)/\(itemID.uuidString).jpg"
        return resolve(canonical, in: root, fileManager: fileManager)
    }
}

extension SharedCatalogPath {
    /// La ruta relativa -- en la forma exacta que SI existe en disco --
    /// o `nil` si ninguna existe. Sirve para dejar guardada la forma
    /// buena en vez de la que venia del otro sistema.
    static func existingRelative(_ relative: String,
                                 in root: URL,
                                 fileManager: FileManager = .default) -> String? {
        guard !relative.isEmpty, !isAbsolute(relative) else { return nil }
        return candidates(for: relative).first {
            fileManager.fileExists(atPath: root.appendingPathComponent($0).path)
        }
    }
}
