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
    /// ST-221: la ruta que el catálogo NOMBRA, exista el archivo o no.
    ///
    /// `resolve` devuelve `nil` cuando el archivo no está, y eso es lo
    /// correcto para decidir si algo se puede sincronizar. Pero para
    /// **conservar** el elemento en el catálogo hace falta saber a qué
    /// apuntaba, aunque ahora mismo no esté: un disco desconectado no
    /// puede significar perder las entradas.
    ///
    /// No comprueba existencia y no inventa nada: solo traduce los
    /// separadores de Windows.
    ///
    /// Y ahí está la diferencia con `resolve`, que prueba **primero la
    /// ruta literal**. Esa preferencia por lo literal tiene sentido
    /// mientras haya un disco que consultar: si el archivo con la barra
    /// invertida en el nombre de verdad existe (en macOS `\` es un
    /// carácter válido), gana él. Sin esa comprobación la preferencia se
    /// da vuelta y hace daño: `Música\Fatboy Slim\Signos\01 x.m4a`
    /// quedaría como **un solo componente** de nombre absurdo, y como
    /// esta ruta es la que se conserva y se vuelve a guardar, el
    /// catálogo compartido saldría corrupto para Windows. Entre las dos
    /// lecturas posibles de algo que no se puede comprobar, la que
    /// preserva el significado es la de separadores.
    static func recordedURL(_ relative: String, in root: URL) -> URL? {
        guard !relative.isEmpty, !isForeignAbsolute(relative) else { return nil }
        if relative.hasPrefix("/") { return URL(fileURLWithPath: catalogNormalized(relative)) }
        return root.appendingPathComponent(catalogNormalized(withUnixSeparators(relative)))
    }
}

extension SharedCatalogPath {
    /// ST-221, añadido por el hallazgo de Windows en B1: **las rutas
    /// relativas del catálogo se escriben en NFC, y toda comparación
    /// de rutas normaliza los dos lados antes de comparar.**
    ///
    /// macOS entrega los acentos descompuestos (NFD: `u` + acento
    /// combinante) y Windows los escribe compuestos (NFC). Los dos son
    /// "Música" en pantalla y ninguna de las dos apps nota la
    /// diferencia... hasta que algo COMPARA las cadenas. Y ST-221
    /// agregó justo eso: `LibraryStorageMode.infer` pregunta si la ruta
    /// cuelga de `Música/`. Sin normalizar, una biblioteca copiada
    /// escrita por la Mac se leería entera como **referenciada** en
    /// Windows -- en silencio, y con el efecto de que la app se
    /// creería sin permiso para escribir etiquetas en archivos que sí
    /// son suyos. El error no se ve por ningún lado: se ve al final,
    /// como "las ediciones no llegan al iPod".
    ///
    /// Esto es aparte de la tolerancia de lectura de `resolve`, que
    /// sigue igual: contra el disco se prueban las dos formas, porque
    /// ahí manda lo que el sistema de archivos conserve.
    static func catalogNormalized(_ path: String) -> String {
        path.precomposedStringWithCanonicalMapping
    }

    /// La ruta de `url` relativa a `root`, **en NFC**; o la absoluta
    /// **tal como viene**, sin normalizar, si no cuelga de ahí. Es lo
    /// que se guarda en el catálogo.
    ///
    /// La asimetría es del contrato y es deliberada: una ruta relativa
    /// la interpretan las dos apps contra su propia raíz, así que su
    /// forma es parte del formato y se fija en NFC. Una ruta absoluta es
    /// un dato del sistema donde vive el archivo -- se compara
    /// normalizada, pero se escribe como vino.
    static func relativePath(of url: URL, in root: URL) -> String {
        let rawFullPath = url.standardizedFileURL.path
        let rootPath = catalogNormalized(root.standardizedFileURL.path)
        let fullPath = catalogNormalized(rawFullPath)
        if fullPath.hasPrefix(rootPath + "/") {
            return String(fullPath.dropFirst(rootPath.count + 1))
        }
        return rawFullPath
    }

    /// ST-221: la carpeta gestionada `name` (`Música`, `Imágenes`,
    /// `Videos`) dentro de `root`, **reusando la que ya exista aunque en
    /// disco su nombre esté descompuesto**.
    ///
    /// En APFS da igual -- compara sin distinguir las dos formas -- pero
    /// en exFAT o en un recurso de red no, y ahí crear `Música` en NFC
    /// junto a la `Música` en NFD que dejó otra instalación parte la
    /// biblioteca en dos carpetas que se ven idénticas. Windows hace lo
    /// mismo de su lado (`MediaRoots.Directory`, ST-241).
    ///
    /// Si no hay ninguna, se crea con el nombre en NFC.
    /// Lo que esto **no** puede hacer, y conviene saberlo antes de
    /// intentarlo: crear la carpeta con el nombre compuesto. En macOS,
    /// Foundation descompone al bajar al sistema de archivos -- lo hacen
    /// `appendingPathComponent`, `createDirectory` y también
    /// `URL(fileURLWithPath:)` con una cadena compuesta. Una carpeta
    /// creada desde la Mac se lee descompuesta, se pida como se pida
    /// (hay una prueba que lo deja escrito).
    ///
    /// Que es exactamente por qué el contrato normaliza **las cadenas
    /// del catálogo** y no los nombres de archivo: lo primero está en
    /// nuestras manos, lo segundo no. Y por qué la mitad que sirve de
    /// esta función es la otra: **reusar** lo que ya haya.
    static func managedDirectory(_ name: String, in root: URL,
                                 fileManager: FileManager = .default) -> URL {
        let wanted = catalogNormalized(name)
        let chosen: String
        if let entries = try? fileManager.contentsOfDirectory(atPath: root.path),
           let existing = entries.first(where: { catalogNormalized($0) == wanted }) {
            chosen = existing
        } else {
            chosen = wanted
        }
        return URL(fileURLWithPath: root.standardizedFileURL.path + "/" + chosen, isDirectory: true)
    }

    /// `true` si `url` está dentro de `root`, comparando en NFC y **por
    /// componentes de ruta**, no por prefijo de texto.
    ///
    /// ST-223: la diferencia importa. Con prefijo, una raíz
    /// `/Música` haría que `/Música de Ana/x.mp3` cuente como "dentro"
    /// si a alguien se le olvida la barra final -- y "dentro de la
    /// biblioteca" es justamente lo que decide si un archivo se copia o
    /// se deja en su sitio, y si la app se cree con permiso de
    /// escribirle etiquetas. Comparar componente a componente no admite
    /// ese error.
    static func isInside(_ url: URL, root: URL) -> Bool {
        let rootParts = pathComponents(of: root)
        let parts = pathComponents(of: url)
        guard parts.count > rootParts.count else { return false }
        return Array(parts.prefix(rootParts.count)) == rootParts
    }

    private static func pathComponents(of url: URL) -> [String] {
        catalogNormalized(url.standardizedFileURL.path)
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
    }

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
