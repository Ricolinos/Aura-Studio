import Foundation

/// Los 8 roles de paleta de un tema -- espejo exacto de
/// `AURA_STYLE_ROLE_*` (aura_style_manifest.h, repositorio del
/// firmware) y de `CONTRATO-formato-tema.md` SS B. `accent` y
/// `white_constant` quedan afuera a proposito: el acento es un ajuste
/// del USUARIO, nunca del tema; el blanco constante del Selector es
/// estructura.
enum ThemePaletteRole: String, CaseIterable {
    case shellBg = "shell_bg"
    case textPrimary = "text_primary"
    case textSecondary = "text_secondary"
    case textTertiary = "text_tertiary"
    case shellRail = "shell_rail"
    case progressFill = "progress_fill"
    case progressTrack = "progress_track"
    case selectionFill = "selection_fill"
}

/// Los 4 colores fijos de categoria (Ajustes/Video/Fotos/el amarillo de
/// Extras) que un tema puede sustituir -- CONTRATO-formato-tema.md SS B.
enum ThemeCategoryKey: String, CaseIterable {
    case settingsGray = "settings_gray"
    case video
    case photos
    case extrasYellow = "extras_yellow"
}

/// Constantes del formato de tema v1 -- `CONTRATO-formato-tema.md`.
/// Mismos 14 roles/9 tamaños que `aura_style.c` (firmware) hardcodea;
/// Studio NO los lee de `theme-format-v1.json` en runtime todavia (ese
/// archivo no viaja embebido en el .app en esta pasada -- ver
/// `scripts/fetch-firmware.sh`, que si lo trae a `Vendor/firmware-dist/`
/// para uso de desarrollo/futuro). Si el contrato sube de version,
/// estas constantes y las del firmware suben juntas, en la misma
/// unidad de trabajo.
enum ThemeFormat {
    static let current = 1

    /// (rol, tamaño en pt) -- mismo orden que `CONTRATO-formato-tema.md` SS C.
    static let fontRoles: [(role: String, px: Int)] = [
        ("title", 20), ("body", 13), ("caption", 13), ("header", 13),
        ("micro", 7), ("ds_reg_8", 8), ("ds_semibold_15", 15),
        ("ds_reg_10", 10), ("ds_bold_10", 10), ("ds_reg_12", 12),
        ("ds_bold_12", 12), ("ds_bold_14", 14), ("ds_bold_18", 18),
        ("ds_medium_16", 16),
    ]
    static let iconSizes = [12, 16, 20, 24, 28, 36, 48, 60, 64]
    static let iconKeyCount = 89
    /// 89 × 9 -- CONTRATO-formato-tema.md SS D. Es el numero MINIMO de
    /// mascaras que un paquete debe traer; no se validan los 89 nombres
    /// exactos en esta pasada (ThemeValidator solo cuenta), a proposito:
    /// mantener la lista completa de icon_key duplicada a mano en dos
    /// lenguajes es mas fragil que contar archivos.
    static let requiredMaskCount = iconKeyCount * iconSizes.count
}

/// Id de un paquete de tema -- mismas reglas que `aura_style_id_is_valid()`
/// del firmware (aura_style_manifest.c): 1-32 caracteres `[a-z0-9-]`,
/// nunca vacio, nunca "default" (reservado para el tema compilado). El
/// alfabeto permitido no incluye "." ni "/", asi que cualquier intento
/// de recorrido de ruta queda rechazado por el filtro de caracteres,
/// sin chequeo aparte -- mismo razonamiento que el lado C.
enum AuraThemeID {
    static let maxLength = 32
    private static let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")

    static func isValid(_ id: String) -> Bool {
        guard !id.isEmpty, id.count <= maxLength, id != "default" else { return false }
        return id.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}

/// Licencia declarada por el constructor del tema -- el firmware la
/// ignora por completo (CONTRATO-formato-tema.md SS I); Studio la
/// respeta al ofrecer exportar/compartir.
enum ThemeLicense: Equatable {
    case open
    case personal
    case custom(String)

    init(rawValue: String) {
        switch rawValue.lowercased() {
        case "open": self = .open
        case "personal": self = .personal
        default: self = .custom(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .open: return "open"
        case .personal: return "personal"
        case .custom(let value): return value
        }
    }

    var displayName: String {
        switch self {
        case .open: return "Libre"
        case .personal: return "Uso personal"
        case .custom(let value): return value
        }
    }
}

/// Manifiesto `theme.cfg` -- mismo formato "clave: valor" que
/// `aura.cfg` (`settings_parseline()` del firmware: sin comillas, `#`
/// inicial comenta la linea). CONTRATO-formato-tema.md SS B.
struct AuraThemeManifest: Equatable {
    var format: Int
    var id: String
    var name: String
    var author: String
    var license: ThemeLicense
    var redistributable: Bool
    var paletteLight: [ThemePaletteRole: String]
    var paletteDark: [ThemePaletteRole: String]
    var category: [ThemeCategoryKey: String]
    var accentDefault: String?
    var accentPresets: [String]

    init(format: Int = ThemeFormat.current, id: String, name: String,
         author: String = "", license: ThemeLicense = .personal, redistributable: Bool = false,
         paletteLight: [ThemePaletteRole: String] = [:], paletteDark: [ThemePaletteRole: String] = [:],
         category: [ThemeCategoryKey: String] = [:],
         accentDefault: String? = nil, accentPresets: [String] = []) {
        self.format = format
        self.id = id
        self.name = name
        self.author = author
        self.license = license
        self.redistributable = redistributable
        self.paletteLight = paletteLight
        self.paletteDark = paletteDark
        self.category = category
        self.accentDefault = accentDefault
        self.accentPresets = accentPresets
    }

    var isFormatCurrentOrOlder: Bool {
        format <= ThemeFormat.current
    }

    /// Parsea `theme.cfg`. `nil` si no hay `theme_format` (obligatoria,
    /// CONTRATO-formato-tema.md SS G) o si el texto no tiene ninguna
    /// linea valida. Claves desconocidas (`requires_firmware_min`, o de
    /// un formato futuro) se ignoran en silencio -- mismo criterio que
    /// `aura_style_manifest_apply_line()` del firmware.
    static func parse(_ text: String) -> AuraThemeManifest? {
        var format: Int?
        var id = ""
        var name = ""
        var author = ""
        var license = ThemeLicense.personal
        var redistributable = false
        var paletteLight: [ThemePaletteRole: String] = [:]
        var paletteDark: [ThemePaletteRole: String] = [:]
        var category: [ThemeCategoryKey: String] = [:]
        var accentDefault: String?
        var accentPresets: [String] = []

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), let colonIndex = line.firstIndex(of: ":") else { continue }
            let key = line[line.startIndex..<colonIndex].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }

            if key == "theme_format" {
                format = Int(value)
            } else if key == "theme_id" {
                id = value
            } else if key == "theme_name" {
                name = value
            } else if key == "theme_author" {
                author = value
            } else if key == "theme_license" {
                license = ThemeLicense(rawValue: value)
            } else if key == "theme_redistributable" {
                redistributable = (value.lowercased() == "yes")
            } else if key == "accent_default" {
                accentDefault = value
            } else if key == "accent_presets" {
                accentPresets = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            } else if key.hasPrefix("palette_light_"),
                      let role = ThemePaletteRole(rawValue: String(key.dropFirst("palette_light_".count))) {
                paletteLight[role] = value
            } else if key.hasPrefix("palette_dark_"),
                      let role = ThemePaletteRole(rawValue: String(key.dropFirst("palette_dark_".count))) {
                paletteDark[role] = value
            } else if key.hasPrefix("category_"),
                      let catKey = ThemeCategoryKey(rawValue: String(key.dropFirst("category_".count))) {
                category[catKey] = value
            }
            // Clave desconocida: se ignora en silencio.
        }

        guard let format else { return nil }
        return AuraThemeManifest(format: format, id: id, name: name, author: author,
                                  license: license, redistributable: redistributable,
                                  paletteLight: paletteLight, paletteDark: paletteDark,
                                  category: category, accentDefault: accentDefault, accentPresets: accentPresets)
    }

    /// Serializa en el mismo orden que `package_dist.sh` escribe el
    /// tema por defecto reempaquetado -- no es un requisito del
    /// contrato (el orden de lineas no importa para el parser), solo
    /// legibilidad si alguien abre el archivo a mano.
    func serialized() -> String {
        var lines = [
            "theme_format: \(format)",
            "theme_id: \(id)",
            "theme_name: \(name)",
        ]
        if !author.isEmpty { lines.append("theme_author: \(author)") }
        lines.append("theme_license: \(license.rawValue)")
        lines.append("theme_redistributable: \(redistributable ? "yes" : "no")")
        for role in ThemePaletteRole.allCases {
            if let hex = paletteLight[role] { lines.append("palette_light_\(role.rawValue): \(hex)") }
        }
        for role in ThemePaletteRole.allCases {
            if let hex = paletteDark[role] { lines.append("palette_dark_\(role.rawValue): \(hex)") }
        }
        for key in ThemeCategoryKey.allCases {
            if let hex = category[key] { lines.append("category_\(key.rawValue): \(hex)") }
        }
        if let accentDefault { lines.append("accent_default: \(accentDefault)") }
        if !accentPresets.isEmpty { lines.append("accent_presets: \(accentPresets.joined(separator: ","))") }
        return lines.joined(separator: "\n") + "\n"
    }
}

/// Un tema instalado en el iPod, tal como aparece en la lista de
/// gestion de Studio -- espejo de `aura_style_entry_t` (aura_style.h,
/// firmware).
struct InstalledTheme: Identifiable, Equatable {
    let id: String
    let name: String
    /// false = fila inerte en el firmware tambien (formato incompatible,
    /// manifiesto ilegible, o faltan fuentes/mascaras) -- Studio lo
    /// muestra atenuado, con el motivo, y no ofrece activarlo.
    let loadable: Bool
    let reason: String?

    init(id: String, name: String, loadable: Bool, reason: String? = nil) {
        self.id = id
        self.name = name
        self.loadable = loadable
        self.reason = reason
    }
}
