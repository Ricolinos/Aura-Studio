import Foundation
import Combine

/// Preferencias de la app (no del dispositivo: los ajustes del firmware
/// viven en el iPod, en su propio aura.cfg). Se guardan en UserDefaults
/// -- son preferencias, no credenciales. Hoy ninguna fuente de datos
/// necesita API key (ver SourcesSettingsView); cuando alguna lo pida, la
/// credencial va al Keychain, no aca.
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

    private let defaults: UserDefaults

    private enum Keys {
        static let coverArtPolicy = "aura.coverArtPolicy"
        static let fetchSyncedLyrics = "aura.fetchSyncedLyrics"
        static let enrichOnline = "aura.enrichOnline"
        static let language = "aura.language"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.coverArtPolicy = (defaults.string(forKey: Keys.coverArtPolicy)
            .flatMap(CoverArtPolicy.init(rawValue:))) ?? .albumOnly
        self.fetchSyncedLyrics = defaults.object(forKey: Keys.fetchSyncedLyrics) as? Bool ?? true
        self.enrichOnline = defaults.object(forKey: Keys.enrichOnline) as? Bool ?? true
        self.language = (defaults.string(forKey: Keys.language)
            .flatMap(AppLanguage.init(rawValue:))) ?? .system
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
