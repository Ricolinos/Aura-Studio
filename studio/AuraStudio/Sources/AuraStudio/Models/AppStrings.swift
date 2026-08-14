import Foundation

/// Tabla de cadenas propia, ES/EN, con el mismo criterio que la del
/// firmware (aura_lang.c, D-013): una tabla chica y explicita en vez del
/// mecanismo de .strings de Apple, que obligaria a declarar recursos en
/// SwiftPM y en xcodegen a la vez.
///
/// ESTADO HONESTO: por ahora cubre unicamente la pantalla de Ajustes y la
/// barra lateral -- el resto de la app sigue con texto en espanol fijo.
/// El selector de idioma funciona de verdad sobre lo que esta aca; las
/// demas pantallas se van pasando a esta tabla de a poco. No se agrego
/// un selector que no hiciera nada.
enum S {
    case settings, settingsGeneral, settingsLibrary, settingsServices
    case language, languageSystem, languageSpanish, languageEnglish
    case languageNote
    case coverArt, coverArtAlbumOnly, coverArtPerTrack
    case coverArtAlbumOnlyDetail, coverArtPerTrackDetail
    case importing, fetchLyrics, fetchLyricsDetail
    case enrichOnline, enrichOnlineDetail
    case general, music, video, photos, extras, installer, noDevice
    case playlists

    var text: String {
        AppLanguageResolver.current == .english ? english : spanish
    }

    private var spanish: String {
        switch self {
        case .settings:            return "Ajustes"
        case .settingsGeneral:     return "General"
        case .settingsLibrary:     return "Biblioteca"
        case .settingsServices:    return "Servicios"
        case .language:            return "Idioma"
        case .languageSystem:      return "Igual que el sistema"
        case .languageSpanish:     return "Espanol"
        case .languageEnglish:     return "Ingles"
        case .languageNote:        return "Por ahora el idioma se aplica a Ajustes y a la barra lateral. El resto de la app todavia esta solo en espanol."
        case .coverArt:            return "Caratulas"
        case .coverArtAlbumOnly:   return "Una por album"
        case .coverArtPerTrack:    return "Una por cancion"
        case .coverArtAlbumOnlyDetail:
            return "Se guarda una sola imagen en la carpeta del album y todas sus canciones la comparten. Ocupa menos espacio y es lo que el firmware busca primero."
        case .coverArtPerTrackDetail:
            return "Cada cancion lleva su propia caratula embebida en el archivo. Util para singles y recopilaciones, donde una unica portada por album seria incorrecta."
        case .importing:           return "Al importar"
        case .fetchLyrics:         return "Buscar letras sincronizadas"
        case .fetchLyricsDetail:   return "Descarga letras con tiempos para que se sigan en pantalla mientras suena la cancion."
        case .enrichOnline:        return "Completar metadata en linea"
        case .enrichOnlineDetail:  return "Rellena artista, album, ano y caratula cuando el archivo no los trae. Si lo apagas, solo se usa lo que ya tiene el archivo."
        case .general:             return "General"
        case .music:               return "Musica"
        case .video:               return "Video"
        case .photos:              return "Fotos"
        case .extras:              return "Extras"
        case .installer:           return "Instalador"
        case .noDevice:            return "Sin dispositivo"
        case .playlists:           return "Listas"
        }
    }

    private var english: String {
        switch self {
        case .settings:            return "Settings"
        case .settingsGeneral:     return "General"
        case .settingsLibrary:     return "Library"
        case .settingsServices:    return "Services"
        case .language:            return "Language"
        case .languageSystem:      return "Match system"
        case .languageSpanish:     return "Spanish"
        case .languageEnglish:     return "English"
        case .languageNote:        return "For now the language applies to Settings and the sidebar. The rest of the app is still Spanish only."
        case .coverArt:            return "Cover art"
        case .coverArtAlbumOnly:   return "One per album"
        case .coverArtPerTrack:    return "One per song"
        case .coverArtAlbumOnlyDetail:
            return "A single image is stored in the album folder and shared by all its songs. Uses less space, and it is what the firmware looks for first."
        case .coverArtPerTrackDetail:
            return "Each song carries its own cover embedded in the file. Useful for singles and compilations, where one cover per album would be wrong."
        case .importing:           return "On import"
        case .fetchLyrics:         return "Fetch synced lyrics"
        case .fetchLyricsDetail:   return "Downloads timed lyrics so they follow along on screen while the song plays."
        case .enrichOnline:        return "Complete metadata online"
        case .enrichOnlineDetail:  return "Fills in artist, album, year and cover art when the file lacks them. Turn it off to use only what the file already has."
        case .general:             return "General"
        case .music:               return "Music"
        case .video:               return "Video"
        case .photos:              return "Photos"
        case .extras:              return "Extras"
        case .installer:           return "Installer"
        case .noDevice:            return "No device"
        case .playlists:           return "Playlists"
        }
    }
}

/// El idioma activo tiene que ser legible desde `S.text`, que es una
/// propiedad pura sin acceso al entorno de SwiftUI. `AppPreferences` lo
/// publica aca cada vez que cambia.
enum AppLanguageResolver {
    nonisolated(unsafe) static var current: AppLanguage = .spanish
}
