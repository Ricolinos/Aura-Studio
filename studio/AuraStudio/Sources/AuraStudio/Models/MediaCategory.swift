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

    var displayName: String {
        AppLanguageResolver.current == .english ? displayNameEnglish : displayNameSpanish
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
                return "IA"
            }
        }
        return hasCameraExif ? "Fotos" : "Imágenes"
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
