import Foundation
import Security

/// Fuentes opcionales que SI necesitan una API key propia (a diferencia
/// de MusicBrainz/Cover Art Archive/LRCLIB, que no la piden -- ver
/// `ServicesSettingsView`). Extensible: agregar una fuente nueva que
/// necesite key es agregar un caso aca, nada mas -- la vista de
/// Ajustes y el almacenamiento en Keychain ya funcionan para
/// cualquier caso de este enum.
///
/// D-203: fanart.tv esta conectada de verdad (`FanartTVClient`, usada
/// desde `LibraryEnricher.resolveCoverArt`).
enum APIKeyService: String, CaseIterable, Identifiable {
    case fanartTV

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fanartTV: return "fanart.tv"
        }
    }

    var summary: String {
        switch self {
        case .fanartTV: return "Caratulas y arte de disco en alta resolucion (~1000px), varias imagenes por album."
        }
    }

    /// Instrucciones cortas para conseguir la key -- se muestran junto
    /// al campo antes de que el usuario la pegue, no despues de que
    /// falle.
    var guideText: String {
        switch self {
        case .fanartTV:
            return "Crea una cuenta gratuita en fanart.tv, entra a tu perfil y copia la \"Personal API Key\" (no la de proyecto)."
        }
    }

    var guideURL: URL {
        switch self {
        case .fanartTV: return URL(string: "https://fanart.tv/get-an-api-key/")!
        }
    }
}

/// Guarda las API keys en el Keychain de macOS -- nunca en
/// UserDefaults/plist (comentario original en `AppPreferences`, D-180:
/// "cuando alguna [fuente] pida [key], la credencial va al Keychain, no
/// aca"). Item generico (`kSecClassGenericPassword`), sin iCloud
/// Keychain (`kSecAttrSynchronizable: false`): una API key personal de
/// un servicio de terceros no tiene por que viajar a otros Mac del
/// usuario junto con el resto de su llavero.
enum APIKeyStore {
    private static let service = "com.ricolinos.aurastudio.apikeys"

    private static func query(for key: APIKeyService) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key.rawValue,
        ]
    }

    static func save(_ value: String, for key: APIKeyService) {
        let data = Data(value.utf8)
        var attributes = query(for: key)
        if SecItemCopyMatching(attributes as CFDictionary, nil) == errSecSuccess {
            SecItemUpdate(attributes as CFDictionary, [kSecValueData: data] as CFDictionary)
        } else {
            attributes[kSecValueData] = data
            attributes[kSecAttrSynchronizable] = false
            SecItemAdd(attributes as CFDictionary, nil)
        }
    }

    static func load(for key: APIKeyService) -> String? {
        var query = query(for: key)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(for key: APIKeyService) {
        SecItemDelete(query(for: key) as CFDictionary)
    }

    static func hasKey(for key: APIKeyService) -> Bool {
        load(for: key) != nil
    }
}
