import Foundation
import Combine
import CoreGraphics

/// D-203: de donde sale la caratula cuando el archivo no trae una
/// propia. Cover Art Archive es la unica fuente activa desde el
/// principio (D-069); fanart.tv y Deezer son opcionales -- fanart.tv
/// necesita una API key propia (Keychain, ver `APIKeyStore`), Deezer no
/// necesita nada pero el usuario puede apagarla igual. El orden importa:
/// se prueban en la secuencia de `AppPreferences.coverArtProviderOrder`
/// y se usa la primera que devuelva un resultado.
enum CoverArtProvider: String, Codable, CaseIterable, Identifiable {
    case coverArtArchive, fanartTV, deezer

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .coverArtArchive: return "Cover Art Archive"
        case .fanartTV: return "fanart.tv"
        case .deezer: return "Deezer"
        }
    }

    /// Vive aca (no en `AppPreferences`, aislada a `@MainActor`) para que
    /// `LibraryEnricher` -- que corre fuera del main actor -- la pueda
    /// usar como valor default de parametro sin arrastrar aislamiento.
    static let defaultOrder: [CoverArtProvider] = [.coverArtArchive, .fanartTV, .deezer]
}

/// Preferencias de la app (no del dispositivo: los ajustes del firmware
/// viven en el iPod, en su propio aura.cfg). Se guardan en UserDefaults
/// -- son preferencias, no credenciales. La unica fuente que hoy pide
/// API key es fanart.tv (ver ServicesSettingsView); esa credencial vive
/// en el Keychain, no aca.
@MainActor
final class AppPreferences: ObservableObject {
    static let shared = AppPreferences()

    /// Como se resuelve la caratula de cada cancion al preparar la
    /// biblioteca. No es cosmetico: cambia que archivos terminan en el
    /// iPod y como los encuentra el firmware (find_albumart, D-010).
    enum CoverArtPolicy: String, Codable, CaseIterable, Identifiable {
        /// Una sola imagen por album, compartida por todas sus pistas:
        /// `cover.jpg` dentro de la carpeta del album. Es lo que el
        /// firmware busca primero y ocupa mucho menos espacio.
        case albumOnly
        /// Cada pista lleva su propia caratula embebida en el archivo,
        /// para singles y recopilaciones donde una portada por album
        /// seria incorrecta.
        case perTrack

        var id: String { rawValue }
    }

    @Published var coverArtPolicy: CoverArtPolicy {
        didSet { defaults.set(coverArtPolicy.rawValue, forKey: Keys.coverArtPolicy) }
    }

    /// Buscar letras sincronizadas al importar. Se puede apagar para que
    /// la importacion no toque la red.
    @Published var fetchSyncedLyrics: Bool {
        didSet { defaults.set(fetchSyncedLyrics, forKey: Keys.fetchSyncedLyrics) }
    }

    /// Completar metadata faltante contra servicios en linea. Apagado,
    /// solo se usa lo que ya traen las tags del archivo y su nombre.
    @Published var enrichOnline: Bool {
        didSet { defaults.set(enrichOnline, forKey: Keys.enrichOnline) }
    }

    @Published var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Keys.language)
            AppLanguageResolver.current = language.resolved
        }
    }

    /// Carpeta de la biblioteca Aura (encargo del dueño, 2026-08-13):
    /// por default es donde vive todo lo que la app necesita para
    /// funcionar como biblioteca -- el catalogo, lo preparado para el
    /// iPod, y (si `copyMediaIntoLibrary` esta activo) las copias de los
    /// archivos originales.
    @Published var libraryFolderPath: String {
        didSet { defaults.set(libraryFolderPath, forKey: Keys.libraryFolderPath) }
    }

    /// Si es `true` (default, y el unico comportamiento que existia
    /// hasta ahora): todo lo que se suelta en la app se COPIA a
    /// `Originales/` dentro de la biblioteca -- el archivo del usuario
    /// jamas se toca, pero queda una copia completa ahi.
    ///
    /// Si es `false`: la biblioteca REFERENCIA el archivo original en su
    /// ubicacion actual (nunca se copia), y solo guarda ahi la
    /// configuracion que lo liga al catalogo (metadata, letras,
    /// portadas) -- exactamente lo mismo que ya se escribe en
    /// `Preparados/`/`Portadas/`/`biblioteca.json` en ambos modos. La
    /// diferencia real ocurre recien al sincronizar: con copia, el
    /// archivo final para el iPod ya estaba preparado de antemano; sin
    /// copia, `LibraryViewModel.process(itemAt:)` arma ese archivo leyendo
    /// el original en su ubicacion externa en ese momento -- mas lento la
    /// primera vez que se procesa, pero el disco del usuario nunca
    /// termina con una copia duplicada de su biblioteca completa.
    @Published var copyMediaIntoLibrary: Bool {
        didSet { defaults.set(copyMediaIntoLibrary, forKey: Keys.copyMediaIntoLibrary) }
    }

    /// Como se arma la carpeta de cada cancion al sincronizar con el
    /// iPod. El tagcache de Rockbox escanea el volumen entero sin
    /// importar la profundidad de carpetas (a diferencia del navegador
    /// de fotos/video, que es plano por ahora -- ver `organizePhotos...`/
    /// `organizeVideos...` mas abajo), asi que esta eleccion es libre.
    enum MusicOrganization: String, Codable, CaseIterable, Identifiable {
        /// `Music/<Artista>/<Album>/`. El default desde D-180.
        case artistAlbum
        /// `Music/<Album>/`, sin carpeta de artista -- util para quien
        /// organiza por album sin pensar en el artista (recopilaciones,
        /// bandas sonoras).
        case album
        /// `Music/<Artista>/`, todas las canciones del artista juntas
        /// sin carpeta de album.
        case artist

        var id: String { rawValue }
    }

    /// Formato del nombre de archivo de cada cancion (sin extension).
    enum MusicFilenameFormat: String, Codable, CaseIterable, Identifiable {
        /// Solo el titulo. Default (encargo del dueño, 2026-08-13).
        case titleOnly
        /// "NN Titulo" -- con el numero de pista al frente.
        case trackNumberTitle
        /// "Titulo - Artista".
        case titleArtist
        /// "Titulo - Album".
        case titleAlbum

        var id: String { rawValue }
    }

    @Published var musicOrganization: MusicOrganization {
        didSet { defaults.set(musicOrganization.rawValue, forKey: Keys.musicOrganization) }
    }

    @Published var musicFilenameFormat: MusicFilenameFormat {
        didSet { defaults.set(musicFilenameFormat.rawValue, forKey: Keys.musicFilenameFormat) }
    }

    /// Calidad de audio al sincronizar. El iPod (y Rockbox) leen FLAC/
    /// ALAC/WAV sin problema, asi que "mantener original" es seguro por
    /// default -- comprimir es una eleccion del usuario para ahorrar
    /// espacio, no algo que la app le imponga.
    enum AudioQuality: String, Codable, CaseIterable, Identifiable {
        /// Copia el archivo tal cual (FLAC/ALAC/WAV/MP3/M4A sin tocar).
        /// Default: nunca se pierde calidad sin que el usuario lo pida.
        case originalLossless
        /// Transcodifica a MP3 256kbps VBR -- buena calidad, una
        /// fraccion del espacio de un FLAC.
        case compressed

        var id: String { rawValue }
    }

    @Published var audioQuality: AudioQuality {
        didSet { defaults.set(audioQuality.rawValue, forKey: Keys.audioQuality) }
    }

    /// Ancho maximo (en px) al redimensionar fotos para el LCD de
    /// 320x240 del iPod. `optimized` es el comportamiento que ya existia
    /// (D-028/ImageResizer) antes de que esto fuera una preferencia.
    enum PhotoQuality: String, Codable, CaseIterable, Identifiable {
        /// 320px de lado mayor -- el ancho nativo del LCD, el minimo
        /// espacio posible. Default.
        case optimized
        /// 640px -- se sigue comprimiendo (sigue siendo JPEG, sigue
        /// siendo mucho mas chico que la foto original de una camara o
        /// telefono actual), pero se ve mas nitida al hacer zoom en el
        /// visor del iPod, a cambio de mas espacio en disco.
        case hd

        var id: String { rawValue }

        var maxDimension: CGFloat {
            switch self {
            case .optimized: return 320
            case .hd: return 640
            }
        }
    }

    @Published var photoQuality: PhotoQuality {
        didSet { defaults.set(photoQuality.rawValue, forKey: Keys.photoQuality) }
    }

    /// Agrupar fotos/videos por categoria (Imagenes/Fotos/Hechas con IA;
    /// Caseros/Videos/Peliculas) SOLO dentro de la biblioteca de Aura
    /// Studio -- es una ayuda para que el usuario encuentre las cosas en
    /// la app. NO cambia la carpeta donde se sincronizan en el iPod
    /// (`Photos/`/`Videos/`, siempre planas): el navegador de fotos/
    /// video del firmware todavia no recorre subcarpetas (ver
    /// aura_photos.c/aura_video.c, D-062 sigue pendiente como su propia
    /// funcionalidad) -- anidar por categoria ahi haria que esos
    /// archivos dejaran de aparecer en el iPod, justo lo contrario de lo
    /// que se busca.
    @Published var organizePhotosByCategory: Bool {
        didSet { defaults.set(organizePhotosByCategory, forKey: Keys.organizePhotosByCategory) }
    }

    @Published var organizeVideosByCategory: Bool {
        didSet { defaults.set(organizeVideosByCategory, forKey: Keys.organizeVideosByCategory) }
    }

    /// D-203: orden de intento para resolver caratula cuando falta.
    /// Persistido como lista separada por comas (mismo criterio que las
    /// columnas visibles de `MediaSectionView`) porque es un array chico
    /// de un enum simple -- no justifica el costo de un blob JSON.
    /// Entradas invalidas o repetidas de una version vieja se filtran al
    /// leer; si el resultado queda vacio, se vuelve al default.
    @Published var coverArtProviderOrder: [CoverArtProvider] {
        didSet {
            defaults.set(coverArtProviderOrder.map(\.rawValue).joined(separator: ","), forKey: Keys.coverArtProviderOrder)
        }
    }

    /// Deezer no pide key, pero el usuario puede apagarla igual (a
    /// diferencia de fanart.tv, cuyo "habilitado" real es tener una key
    /// guardada). Default true: sus terminos permiten explicitamente
    /// este uso (ver ServicesSettingsView) y no hay ninguna credencial
    /// que pedirle primero al usuario.
    @Published var deezerEnabled: Bool {
        didSet { defaults.set(deezerEnabled, forKey: Keys.deezerEnabled) }
    }

    static var defaultLibraryFolderPath: String {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Aura Library", isDirectory: true).path
            ?? NSHomeDirectory() + "/Documents/Aura Library"
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let coverArtPolicy = "aura.coverArtPolicy"
        static let fetchSyncedLyrics = "aura.fetchSyncedLyrics"
        static let enrichOnline = "aura.enrichOnline"
        static let language = "aura.language"
        static let libraryFolderPath = "aura.libraryFolderPath"
        static let copyMediaIntoLibrary = "aura.copyMediaIntoLibrary"
        static let musicOrganization = "aura.musicOrganization"
        static let musicFilenameFormat = "aura.musicFilenameFormat"
        static let audioQuality = "aura.audioQuality"
        static let photoQuality = "aura.photoQuality"
        static let organizePhotosByCategory = "aura.organizePhotosByCategory"
        static let organizeVideosByCategory = "aura.organizeVideosByCategory"
        static let coverArtProviderOrder = "aura.coverArtProviderOrder"
        static let deezerEnabled = "aura.deezerEnabled"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.coverArtPolicy = (defaults.string(forKey: Keys.coverArtPolicy)
            .flatMap(CoverArtPolicy.init(rawValue:))) ?? .albumOnly
        self.fetchSyncedLyrics = defaults.object(forKey: Keys.fetchSyncedLyrics) as? Bool ?? true
        self.enrichOnline = defaults.object(forKey: Keys.enrichOnline) as? Bool ?? true
        self.language = (defaults.string(forKey: Keys.language)
            .flatMap(AppLanguage.init(rawValue:))) ?? .system
        self.libraryFolderPath = defaults.string(forKey: Keys.libraryFolderPath)
            ?? Self.defaultLibraryFolderPath
        self.copyMediaIntoLibrary = defaults.object(forKey: Keys.copyMediaIntoLibrary) as? Bool ?? true
        self.musicOrganization = (defaults.string(forKey: Keys.musicOrganization)
            .flatMap(MusicOrganization.init(rawValue:))) ?? .artistAlbum
        self.musicFilenameFormat = (defaults.string(forKey: Keys.musicFilenameFormat)
            .flatMap(MusicFilenameFormat.init(rawValue:))) ?? .titleOnly
        self.audioQuality = (defaults.string(forKey: Keys.audioQuality)
            .flatMap(AudioQuality.init(rawValue:))) ?? .originalLossless
        self.photoQuality = (defaults.string(forKey: Keys.photoQuality)
            .flatMap(PhotoQuality.init(rawValue:))) ?? .optimized
        self.organizePhotosByCategory = defaults.object(forKey: Keys.organizePhotosByCategory) as? Bool ?? true
        self.organizeVideosByCategory = defaults.object(forKey: Keys.organizeVideosByCategory) as? Bool ?? true
        let storedOrder = defaults.string(forKey: Keys.coverArtProviderOrder)?
            .split(separator: ",")
            .compactMap { CoverArtProvider(rawValue: String($0)) } ?? []
        self.coverArtProviderOrder = storedOrder.isEmpty ? CoverArtProvider.defaultOrder : storedOrder
        self.deezerEnabled = defaults.object(forKey: Keys.deezerEnabled) as? Bool ?? true
        AppLanguageResolver.current = self.language.resolved
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case spanish
    case english

    var id: String { rawValue }

    /// Codigo que se le pasa a la tabla de cadenas. `system` se resuelve
    /// contra el idioma preferido de macOS, cayendo a espanol.
    var resolved: AppLanguage {
        guard self == .system else { return self }
        let preferred = Locale.preferredLanguages.first ?? "es"
        return preferred.hasPrefix("en") ? .english : .spanish
    }
}
