import Foundation

/// Categoria FIJA de un video DENTRO de la biblioteca de Aura Studio
/// (encargo del dueño, 2026-08-13: "dividirlos [videos] por Videos,
/// Series, Peliculas"). Es un dato de organizacion de la app, no de la
/// carpeta donde termina en el iPod -- `LibrarySync` sigue escribiendo
/// `Videos/` plana porque el navegador del firmware todavia no recorre
/// subcarpetas (ver `AppPreferences.organizeVideosByCategory`).
///
/// D-228: las colecciones de FOTOS dejaron de vivir aca -- el dueño
/// pidio que esas fueran editables por el usuario (agregar/quitar sin
/// tocar codigo), asi que pasaron a `AppPreferences.photoCollections`
/// (un `[String]` libre). Video se queda con el enum a proposito: su
/// conjunto es fijo, nunca hay una cuarta categoria, y el compilador
/// garantiza que no aparezca un valor invalido.
enum MediaCategory: String, Codable, CaseIterable, Identifiable {
    /// Duracion media, sin clasificar como pelicula. Default cuando no
    /// hay duracion o no aplica ningun otro caso.
    case videos
    /// Sin heuristica automatica (D-228): no hay forma confiable de
    /// distinguir "esto es un episodio de una serie" solo por
    /// duracion, asi que el usuario la asigna a mano desde el picker
    /// de categoria.
    case series
    /// Duracion larga (> 40 min) -- probablemente una pelicula o
    /// episodio completo.
    case movies

    var id: String { rawValue }

    static let videoCategories: [MediaCategory] = [.videos, .series, .movies]

    var displayNameSpanish: String {
        switch self {
        case .videos: return "Videos"
        case .series: return "Series"
        case .movies: return "Películas"
        }
    }

    var displayNameEnglish: String {
        switch self {
        case .videos: return "Videos"
        case .series: return "Series"
        case .movies: return "Movies"
        }
    }

    /// **El valor que se GUARDA** en `item.category` (D-283), y contra el
    /// que se compara. Es el español, siempre.
    ///
    /// ST-227 (A7b): hasta acá esto devolvía el nombre en el idioma
    /// activo, así que la categoría que quedaba guardada dependía del
    /// idioma con que se hubiera importado -- y el código de comparación
    /// tenía que probar contra los dos. Con seis idiomas eso deja de
    /// funcionar: una categoría guardada como "Filme" no coincide con
    /// nada. Lo que se guarda es un dato, no un texto de pantalla.
    var displayName: String { displayNameSpanish }

    /// **El nombre que se MUESTRA.** Este sí se traduce.
    var localizedName: String {
        switch self {
        case .videos: return LS("media-category.videos")
        case .series: return LS("media-category.series")
        case .movies: return LS("media-category.movies")
        }
    }
}

/// Heuristicas de clasificacion automatica -- solo una sugerencia
/// inicial, el usuario la puede corregir a mano en la biblioteca
/// (Fase 1B). Funciones puras/testables por separado de donde se
/// invocan (ImageIO/ffmpeg necesitan el archivo real en disco).
enum MediaCategoryHeuristics {
    /// Nombres de software que identifican una imagen como generada por
    /// IA, buscados sin distinguir mayusculas dentro del tag EXIF/TIFF
    /// "Software" o "Artist". Lista deliberadamente chica: falsos
    /// negativos (una IA no listada cae en "Fotos" o "Imagenes") son
    /// preferibles a falsos positivos.
    static let aiGeneratorSoftwareNames = [
        "midjourney", "dall-e", "dalle", "stable diffusion", "stablediffusion",
        "firefly", "leonardo.ai", "leonardo ai", "ideogram", "runway",
    ]

    /// D-228: devuelve un `String` (no `MediaCategory`) porque las
    /// colecciones de foto ahora son la lista libre de
    /// `AppPreferences.photoCollections` -- estos tres nombres literales
    /// coinciden con el default de esa lista a proposito, para que
    /// "recien instalado, sin tocar nada" clasifique exactamente igual
    /// que antes. No se usa `AppLanguageResolver`/`displayName` aca: el
    /// resto de la app (fuera de Ajustes/barra lateral) sigue en
    /// español fijo (ver AppStrings.swift), y estos nombres tienen que
    /// coincidir con el default de una preferencia que tampoco se
    /// traduce.
    static func classifyPhoto(softwareTag: String?, hasCameraExif: Bool) -> String {
        if let softwareTag {
            let lowered = softwareTag.lowercased()
            if aiGeneratorSoftwareNames.contains(where: { lowered.contains($0) }) {
                return PhotoCollection.ai
            }
        }
        return hasCameraExif ? PhotoCollection.photos : PhotoCollection.images
    }

    /// D-228: se elimino el corte de "casero" (<= 3 min) -- no hay
    /// heuristica confiable para eso por duracion sola, asi que ya no
    /// se intenta: solo pelicula (larga) vs. video (todo lo demas). El
    /// usuario asigna "Series" a mano.
    static func classifyVideo(durationSeconds: Double?) -> MediaCategory {
        guard let durationSeconds, durationSeconds > 0 else { return .videos }
        if durationSeconds > 2400 { return .movies }
        return .videos
    }
}

/// Las tres colecciones de fotos, **como valores del catálogo**.
///
/// Siguen siendo español y así se quedan (D-283: lo que se guarda es
/// dato del usuario, no texto de pantalla; lo que se muestra sale del
/// catálogo). Lo que cambia es que dejan de ser literales sueltos
/// repetidos por el código.
///
/// **Por qué existe este tipo.** `LibraryViewModel` comparaba
/// `item.category == "Fotografías"` para no proponer nunca una
/// fotografía de cámara como carátula contaminante. El clasificador
/// nunca devolvió "Fotografías" -- devuelve "Fotos" -- así que la guarda
/// no se cumplía jamás y la promesa del comentario era falsa. La prueba
/// que la cubría sembraba el catálogo con "Fotografías" a mano, así que
/// pasaba en verde sin tocar el camino real. Con un símbolo en vez de un
/// literal, el compilador no deja escribir un nombre que no existe.
enum PhotoCollection {
    static let images = "Imágenes"
    static let photos = "Fotos"
    static let ai = "IA"

    static let all = [images, photos, ai]
}
