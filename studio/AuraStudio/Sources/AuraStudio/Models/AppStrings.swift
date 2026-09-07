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
    /// ST-031: subsecciones de Música en la barra lateral.
    case songs, albums, artists
    /// PLAN-biblioteca-medios-v2.md §3.2: subsecciones de Video en la
    /// barra lateral -- Películas/Series ya salen de
    /// `MediaCategory.displayName` (misma fuente que el valor que se
    /// guarda en `item.category`, sin duplicar la traducción); estas
    /// cubren solo lo que no tenía nombre localizable todavía.
    case videoAll, videoClips
    /// Subsecciones de Fotos: "Todas las fotos" es chrome de la barra
    /// lateral (localizable); "Fotos"/"Imágenes"/"IA" NO se traducen --
    /// son las mismas 3 colecciones editables de `AppPreferences.
    /// photoCollections`, que en todo el resto de la app son texto fijo
    /// en español (D-228: el usuario las puede renombrar, no son un
    /// concepto de idioma).
    case photosAll
    /// ST-225: sección "Cómo guardar tu música" y limpieza de huérfanos.
    /// Los textos en español son **los del cotejo de claves compartidas**
    /// con Windows (`studio/windows/docs/extraccion-cadenas/
    /// claves-compartidas.csv`, filas `storage-*` y `orphans-*`), palabra
    /// por palabra salvo lo que es propio de la plataforma: acá dice
    /// "Papelera" donde Windows dice "Papelera de reciclaje". Se
    /// traducen una sola vez para las dos apps (A7).
    case storageSectionTitle, storageCopyExplainer, storageReferenceExplainer
    case storageChangeOnlyAffectsFuture
    case orphansTitle, orphansDetail, orphansButton, orphansCleanButton
    case orphansNoneFound, orphansConfirmMessage
    /// ST-226: migración de bibliotecas anteriores. Las dos primeras son
    /// del cotejo compartido con Windows; la tercera es propia de la
    /// pantalla de Ajustes y dice lo que la detección barata NO puede
    /// ver.
    case migrateSectionTitle, migrateButton, migrateSettingsDetail

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
        case .songs:               return "Canciones"
        case .albums:              return "Álbumes"
        case .artists:             return "Artistas"
        case .videoAll:            return "Todos los videos"
        case .videoClips:          return "Videoclips"
        case .photosAll:           return "Todas las fotos"
        case .storageSectionTitle: return "Cómo guardar tu música"
        case .storageCopyExplainer:
            return "Copiar a la Biblioteca de Aura: Aura controla los archivos, edita sus etiquetas y los sincroniza directo; ocupa espacio en disco (una copia); puedes borrar tus originales después."
        case .storageReferenceExplainer:
            return "Referenciar en su lugar: no ocupa espacio extra ni toca tus archivos; Aura mantiene una versión preparada aparte (.preparados/), las ediciones viven solo en Aura y en el iPod, y si el disco original no está, esas canciones no se pueden sincronizar."
        case .storageChangeOnlyAffectsFuture:
            return "Cambiar este ajuste solo afecta lo que importes de ahora en adelante: lo que ya está en tu biblioteca se queda como está."
        case .orphansTitle:        return "Archivos huérfanos"
        case .orphansDetail:
            return "Preparados y carátulas que ya no le pertenecen a ningún elemento de tu biblioteca — de elementos eliminados antes de esta versión, o de un reprocesamiento. No son tus archivos originales: son copias técnicas que Aura arma sola y puede volver a armar si hicieran falta."
        case .orphansButton:       return "Buscar huérfanos"
        case .orphansCleanButton:  return "Limpiar archivos huérfanos"
        case .orphansNoneFound:    return "No hay archivos huérfanos: no hace falta limpiar nada."
        case .orphansConfirmMessage:
            return "No están ligados a ningún elemento de tu biblioteca; borrarlos no afecta ninguna canción, foto ni video que tengas."
        case .migrateSectionTitle: return "Migrar de una versión anterior"
        case .migrateButton:       return "Migrar biblioteca"
        case .migrateSettingsDetail:
            return "Pone al día una biblioteca hecha con una versión anterior: escribe las etiquetas del catálogo en las copias, renombra los archivos preparados y limpia lo que ya no le pertenece a nadie. Puedes migrar aunque Aura no te haya avisado: hay un caso que solo se detecta al migrar, porque hay que abrir los archivos para verlo -- copias cuyas etiquetas no coinciden con lo que dice tu catálogo."
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
        case .songs:               return "Songs"
        case .albums:              return "Albums"
        case .artists:             return "Artists"
        case .videoAll:            return "All Videos"
        case .videoClips:          return "Clips"
        case .photosAll:           return "All Photos"
        case .storageSectionTitle: return "How to store your music"
        case .storageCopyExplainer:
            return "Copy into the Aura Library: Aura owns the files, edits their tags and syncs them directly; it uses disk space (one copy); you can delete your originals afterwards."
        case .storageReferenceExplainer:
            return "Reference them in place: no extra space and your files are never touched; Aura keeps a prepared version aside (.preparados/), edits live only in Aura and on the iPod, and if the original disk is missing those songs can't be synced."
        case .storageChangeOnlyAffectsFuture:
            return "Changing this only affects what you import from now on: what is already in your library stays as it is."
        case .orphansTitle:        return "Orphaned files"
        case .orphansDetail:
            return "Prepared files and cover art that no longer belong to any item in your library — from items deleted before this version, or from reprocessing. They are not your original files: they are technical copies Aura makes on its own and can make again if needed."
        case .orphansButton:       return "Find orphans"
        case .orphansCleanButton:  return "Clean up orphaned files"
        case .orphansNoneFound:    return "There are no orphaned files: nothing to clean up."
        case .orphansConfirmMessage:
            return "They are not tied to any item in your library; deleting them affects no song, photo or video you have."
        case .migrateSectionTitle: return "Migrate from an earlier version"
        case .migrateButton:       return "Migrate library"
        case .migrateSettingsDetail:
            return "Brings a library made with an earlier version up to date: writes the catalog's tags into the copies, renames the prepared files and cleans up what no longer belongs to anything. You can migrate even if Aura hasn't prompted you: there is one case that only shows up during migration, because the files have to be opened to see it — copies whose tags don't match what your catalog says."
        }
    }
}

/// El idioma activo tiene que ser legible desde `S.text`, que es una
/// propiedad pura sin acceso al entorno de SwiftUI. `AppPreferences` lo
/// publica aca cada vez que cambia.
enum AppLanguageResolver {
    nonisolated(unsafe) static var current: AppLanguage = .spanish
}
