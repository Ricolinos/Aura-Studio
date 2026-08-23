import Foundation

/// Que firmware de la familia Aura dice ser el que esta instalado, leido
/// de la clave `firmware_family` de `.rockbox/aura/aura.cfg` (contrato
/// v8, ST-046).
///
/// Es un TERCER hecho, deliberadamente separado de los dos que ya
/// distingue `AuraDevice` (ST-016):
///
///   1. `AuraDevice.firmware` -- que ARCHIVOS hay en el disco.
///   2. `AuraDevice.runningFirmware` -- quien atiende el USB ahora.
///   3. `declaredFamily` (esto) -- que dice el firmware DE SI MISMO.
///
/// Hacia falta un tercero porque los otros dos no pueden responder la
/// pregunta: Metro-Aura escribe en `.rockbox/aura/` exactamente igual que
/// Aura (comparten el contrato entero de §D a proposito), y por USB los
/// dos se anuncian como "Rockbox.org" -- son forks del mismo Rockbox
/// (`USBDeviceIdentity.classify`). Sin una clave declarada no hay forma
/// de distinguirlos, y Studio trataba a Metro como Aura: le ofrecia
/// actualizaciones del repo equivocado, que al aceptarse lo habrian
/// SOBRESCRITO.
///
/// **La ausencia de la clave significa `.aura`**, y eso es lo que hace el
/// cambio retrocompatible: Aura-Firmware nunca la escribio ni la
/// escribira, asi que todo iPod con Aura instalada -- incluidos los
/// instalados antes de esta version de Studio -- cae en el caso correcto
/// sin tocar el firmware. Metro si la escribe (`metro_settings.c`, M-004).
enum FirmwareFamily: Equatable {
    case aura
    case metro
    /// Una familia que esta version de Studio no conoce. Se conserva el
    /// texto crudo para poder mostrarlo y para no fingir que es Aura: un
    /// firmware que se molesto en declararse NO es Aura, aunque no
    /// sepamos cual es.
    case unknown(String)

    /// Valor tal como aparece en `aura.cfg`. `nil` para Aura: la clave
    /// simplemente no existe (ver arriba).
    var configValue: String? {
        switch self {
        case .aura: return nil
        case .metro: return "metro"
        case .unknown(let raw): return raw
        }
    }

    /// Nombre de producto, para la UI.
    var displayName: String {
        switch self {
        case .aura: return "Aura"
        case .metro: return "Metro"
        case .unknown(let raw): return raw
        }
    }

    /// Repositorio de GitHub que publica los Releases de esta familia
    /// (`owner/repo`). `nil` para una familia desconocida: no hay a donde
    /// preguntar, y adivinar seria peor que no ofrecer actualizaciones.
    var releaseRepository: String? {
        switch self {
        case .aura: return "Ricolinos/Aura-Firmware"
        case .metro: return "Ricolinos/Metro-Aura"
        case .unknown: return nil
        }
    }

    /// ST-047: las dos familias que esta version de Studio trae
    /// EMBEBIDAS y por lo tanto puede instalar. Una familia desconocida
    /// se detecta pero no se instala.
    static let installable: [FirmwareFamily] = [.aura, .metro]

    var isInstallable: Bool { Self.installable.contains(self) }

    /// Subdirectorio de Resources donde viven los artefactos de la
    /// familia (ver project.yml / scripts/fetch-firmware.sh). `nil` =
    /// raiz del bundle, que es donde Aura siempre estuvo: mover los
    /// suyos habria sido riesgo sin beneficio.
    var bundleSubdirectory: String? {
        switch self {
        case .aura: return nil
        case .metro: return "metro"
        case .unknown: return nil
        }
    }

    /// Un archivo del arbol `.rockbox/` que el firmware carga al arrancar
    /// -- el instalador lo usa como centinela de "el zip se extrajo
    /// completo" (InstallerViewModel.copyFirmwareFiles). Cada familia
    /// trae sus propias fuentes, asi que el centinela es por familia.
    var installedTreeSentinel: String? {
        switch self {
        case .aura: return ".rockbox/fonts/a26-title-20.fnt"
        case .metro: return ".rockbox/fonts/metro-list-20.fnt"
        case .unknown: return nil
        }
    }

    /// URL publica del repositorio (para Licencias y para "ver el
    /// Release").
    var repositoryURL: URL? {
        guard let repo = releaseRepository else { return nil }
        return URL(string: "https://github.com/\(repo)")
    }

    /// ST-056 / contrato v10: nombre del arbol DORMIDO de esta familia en
    /// la raiz del iPod (`/.firmware-aura/`, `/.firmware-metro/`): un
    /// `.rockbox` completo, en reposo, con sus propios ajustes. El activo
    /// es siempre `/.rockbox/` (lo unico que el bootloader arranca).
    var dormantTreeName: String? {
        switch self {
        case .aura: return ".firmware-aura"
        case .metro: return ".firmware-metro"
        case .unknown: return nil
        }
    }

    /// Interpreta el valor crudo de la clave. Insensible a mayusculas y
    /// espacios porque el parser del firmware (`settings_parseline()`) no
    /// normaliza nada: lo que se escriba es lo que se lee.
    static func parse(configValue raw: String?) -> FirmwareFamily {
        guard let raw else { return .aura }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch value {
        case "": return .aura
        case "aura": return .aura
        case "metro": return .metro
        default: return .unknown(value)
        }
    }
}
