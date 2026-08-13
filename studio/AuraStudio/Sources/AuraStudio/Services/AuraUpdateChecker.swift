import Foundation

/// Decide si el firmware Aura instalado en el iPod es mas viejo que el
/// que trae embebida ESTA version de Aura Studio.
///
/// La comparacion es por hash SHA-256 de `rockbox.ipod`, no por numero
/// de version ni fecha: el binario embebido es la fuente de verdad de
/// "lo mas nuevo que esta app conoce", y dos binarios distintos = hay
/// algo que actualizar (en cualquier direccion -- si el usuario tiene
/// una app vieja y un firmware mas nuevo, actualizar lo "regresaria";
/// ese caso se resuelve actualizando la app, y el texto de la UI habla
/// de "esta version de Aura Studio" a proposito).
///
/// NOTA sobre GitHub (encargo del dueño, 2026-08-13): la idea original
/// era consultar el ultimo release publicado del repositorio. Hoy el
/// repo es PRIVADO y sin releases -- una consulta anonima a la API
/// fallaria siempre. Cuando existan releases publicos, este es el punto
/// unico donde se agregaria esa consulta (comparar el hash del asset
/// del release contra el instalado, con el embebido como respaldo
/// offline).
enum AuraUpdateChecker {
    /// Rutas candidatas del binario instalado, en orden de preferencia:
    /// el que arranca el bootloader es `/.rockbox/rockbox.ipod` (viaja
    /// en el arbol desde D-178); el de la raiz es la copia que el
    /// instalador dejaba desde el principio.
    static let installedRelativePaths = [".rockbox/rockbox.ipod", "rockbox.ipod"]

    static func isUpdateAvailable(deviceMountPath: String) async -> Bool {
        guard !deviceMountPath.isEmpty, deviceMountPath.hasPrefix("/"),
              let bundledURL = BundledArtifacts.shared.url(for: .firmware) else { return false }

        let root = URL(fileURLWithPath: deviceMountPath)
        let fm = FileManager.default
        guard let installedURL = installedRelativePaths
            .map({ root.appendingPathComponent($0) })
            .first(where: { fm.fileExists(atPath: $0.path) }) else {
            // Aura detectada pero sin binario a la vista (arbol a medio
            // copiar): eso lo arregla reinstalar, asi que cuenta como
            // actualizacion disponible.
            return true
        }

        let bundledHash = try? BundledArtifacts.sha256Hex(of: bundledURL)
        let installedHash = try? BundledArtifacts.sha256Hex(of: installedURL)
        guard let bundledHash, let installedHash else { return false }
        return bundledHash != installedHash
    }
}
