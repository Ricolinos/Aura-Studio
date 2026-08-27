import Foundation
import Security

/// ST-074: token de GitHub de SOLO LECTURA para consultar Releases de
/// los repositorios del firmware, que pasaron a ser privados. Vive
/// únicamente en el Llavero de macOS (`kSecClassGenericPassword`,
/// sin iCloud Keychain), igual que las API keys de `APIKeyStore`
/// (D-203, ST-032): nunca en `UserDefaults`, nunca en logs, nunca en
/// el repo.
///
/// Solo lo consume `GitHubReleaseChecker.fetchReleases` (el aviso de
/// "hay una versión nueva"). La INSTALACIÓN no lo necesita: los
/// binarios viajan embebidos en la app (`Vendor/firmware-dist/`, que
/// `scripts/fetch-firmware.sh` descarga con la sesión `gh` del
/// desarrollador al compilar).
enum GitHubToken {
    private static let service = "com.ricolinos.aurastudio.github-token"
    private static let account = "github"

    private static var query: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
    }

    static func load() -> String? {
        var q = query
        q[kSecReturnData] = true
        q[kSecMatchLimit] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func save(_ token: String) {
        let data = Data(token.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        var attributes = query
        if SecItemCopyMatching(attributes as CFDictionary, nil) == errSecSuccess {
            SecItemUpdate(attributes as CFDictionary, [kSecValueData: data] as CFDictionary)
        } else {
            attributes[kSecValueData] = data
            attributes[kSecAttrSynchronizable] = false
            SecItemAdd(attributes as CFDictionary, nil)
        }
    }

    static func delete() {
        SecItemDelete(query as CFDictionary)
    }

    static func hasToken() -> Bool {
        load() != nil
    }

    /// Formato de un token personal de GitHub: fine-grained
    /// (`github_pat_…`) o clásico (`ghp_…`), sin espacios ni saltos de
    /// línea. Se valida ANTES de guardar para no meter al Llavero algo
    /// que GitHub va a rechazar de todos modos (una URL pegada por
    /// error, la contraseña de la cuenta, etc.). No se valida contra la
    /// red: eso lo hace el botón "Probar" de Ajustes.
    static func validateFormat(_ raw: String) -> Bool {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty,
              token.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return false }
        let prefixes = ["github_pat_", "ghp_"]
        guard let prefix = prefixes.first(where: { token.hasPrefix($0) }) else { return false }
        let body = token.dropFirst(prefix.count)
        guard body.count >= 20 else { return false }
        return body.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
    }
}
