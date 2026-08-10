import Foundation
import Security

/// Guarda las API keys opcionales de Genius/Musixmatch en el Keychain
/// del usuario (no en UserDefaults/disco plano -- son credenciales,
/// aunque de bajo riesgo, y el Keychain es la forma estandar de macOS
/// de guardar esto). Nunca se pide una key para el flujo por defecto:
/// LRCLIB ya cubre letras sincronizadas gratis sin ninguna key (ver
/// LRCLIBClient) -- Genius/Musixmatch son estrictamente opcionales.
struct APIKeyStore {
    enum Provider: String {
        case genius = "com.ricolinos.aurastudio.apikey.genius"
        case musixmatch = "com.ricolinos.aurastudio.apikey.musixmatch"
    }

    func save(_ key: String, for provider: Provider) {
        delete(provider)
        guard let data = key.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: provider.rawValue,
            kSecValueData as String: data,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    func load(_ provider: Provider) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: provider.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func delete(_ provider: Provider) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: provider.rawValue,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
