import Foundation

/// Categoria de una foto o un video DENTRO de la biblioteca de Aura
/// Studio (encargo del dueño, 2026-08-13: "dividir su biblioteca de
/// fotos por imagenes, fotos, hechos con ia"; "dividirlos [videos] por
/// Caseros, videos, peliculas"). Es un dato de organizacion de la app,
/// no de la carpeta donde termina en el iPod -- `LibrarySync` sigue
/// escribiendo `Photos/`/`Videos/` planas porque el navegador del
/// firmware todavia no recorre subcarpetas (ver `AppPreferences.
/// organizePhotosByCategory`). Un solo enum para ambos tipos (no dos
/// separados) porque `LibraryItem` ya distingue `.photo`/`.video` por
/// `kind`, y comparten el mismo mecanismo (heuristica automatica +
/// override manual en la vista de biblioteca, Fase 1B).
enum MediaCategory: String, Codable, CaseIterable, Identifiable {
    // Fotos
    /// Sin datos de camara (EXIF) -- capturas de pantalla, graficos,
    /// memes, escaneos.
    case images
    /// Con datos de camara (EXIF de lente/apertura/modelo) -- fotos
    /// tomadas con una camara o telefono real.
    case photos
    /// Metadata de software coincide con un generador de IA conocido
    /// (Midjourney, DALL-E, Stable Diffusion, etc).
    case aiGenerated

    // Videos
    /// Duracion corta (<= 3 min) -- clips caseros, tomados con telefono.
    case homeVideos
    /// Duracion media, sin clasificar como casero ni pelicula.
    case videos
    /// Duracion larga (> 40 min) -- probablemente una pelicula o
    /// episodio completo.
    case movies

    var id: String { rawValue }

    static let photoCategories: [MediaCategory] = [.images, .photos, .aiGenerated]
    static let videoCategories: [MediaCategory] = [.homeVideos, .videos, .movies]

    var displayNameSpanish: String {
        switch self {
        case .images: return "Imágenes"
        case .photos: return "Fotos"
        case .aiGenerated: return "Hechas con IA"
        case .homeVideos: return "Caseros"
        case .videos: return "Videos"
        case .movies: return "Películas"
        }
    }

    var displayNameEnglish: String {
        switch self {
        case .images: return "Images"
        case .photos: return "Photos"
        case .aiGenerated: return "AI-generated"
        case .homeVideos: return "Home movies"
        case .videos: return "Videos"
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

    static func classifyPhoto(softwareTag: String?, hasCameraExif: Bool) -> MediaCategory {
        if let softwareTag {
            let lowered = softwareTag.lowercased()
            if aiGeneratorSoftwareNames.contains(where: { lowered.contains($0) }) {
                return .aiGenerated
            }
        }
        return hasCameraExif ? .photos : .images
    }

    static func classifyVideo(durationSeconds: Double?) -> MediaCategory {
        guard let durationSeconds, durationSeconds > 0 else { return .videos }
        if durationSeconds <= 180 { return .homeVideos }
        if durationSeconds > 2400 { return .movies }
        return .videos
    }
}
