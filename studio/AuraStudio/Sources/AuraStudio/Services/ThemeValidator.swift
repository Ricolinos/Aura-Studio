import Foundation

/// CONTRATO-formato-tema.md SS G: "Aura Studio, antes de instalar:
/// manifiesto completo y parseable; los 14 fonts/<rol>.fnt presentes;
/// las 801 mascaras presentes; theme_format <= el que reporto el
/// firmware. Rechaza el paquete antes de copiar si algo falta."
enum ThemeValidationError: LocalizedError, Equatable {
    case manifestMissing
    case manifestUnreadable
    case invalidId(String)
    case formatUnsupported(found: Int, supported: Int)
    case missingFonts([String])
    case missingMasks(found: Int, required: Int)

    var errorDescription: String? {
        switch self {
        case .manifestMissing:
            return "Falta theme.cfg en el paquete."
        case .manifestUnreadable:
            return "theme.cfg no se pudo leer, o no declara theme_format."
        case .invalidId(let id):
            return "\"\(id)\" no es un id valido de tema (theme_id en theme.cfg)."
        case .formatUnsupported(let found, let supported):
            return "Este tema requiere el formato \(found); el firmware instalado en el iPod soporta hasta el \(supported)."
        case .missingFonts(let roles):
            return "Faltan fuentes en el paquete: \(roles.joined(separator: ", "))."
        case .missingMasks(let found, let required):
            return "Faltan mascaras de icono: el paquete trae \(found), se necesitan \(required)."
        }
    }
}

enum ThemeValidator {
    /// Valida un paquete YA en el layout del contrato (`theme.cfg` +
    /// `fonts/` + `icons/masks/` bajo `packageRoot`).
    /// `firmwareSupportedFormat`: lo que reporto el iPod montado
    /// (`aura.cfg` -> `theme_format_supported`, via
    /// `ThemeInstaller.supportedThemeFormat`); `nil` si no se pudo leer
    /// (p. ej. sin dispositivo conectado, o firmware anterior a D-289
    /// que no escribe esa clave) -- en ese caso se compara contra
    /// `ThemeFormat.current` como mejor esfuerzo, y se avisa en la UI
    /// que no se confirmo contra el dispositivo real.
    static func validate(packageRoot: URL, firmwareSupportedFormat: Int?,
                          fileManager: FileManager = .default) -> Result<AuraThemeManifest, ThemeValidationError> {
        let manifestURL = packageRoot.appendingPathComponent("theme.cfg")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            return .failure(.manifestMissing)
        }
        guard let text = try? String(contentsOf: manifestURL, encoding: .utf8),
              let manifest = AuraThemeManifest.parse(text) else {
            return .failure(.manifestUnreadable)
        }
        guard AuraThemeID.isValid(manifest.id) else {
            return .failure(.invalidId(manifest.id))
        }
        let supported = firmwareSupportedFormat ?? ThemeFormat.current
        guard manifest.format <= supported else {
            return .failure(.formatUnsupported(found: manifest.format, supported: supported))
        }

        // CONTRATO-formato-tema.md SS G pide tambien la cabecera del
        // .fnt valida, no solo que el archivo exista -- eso requeriria
        // parsear el formato binario de Rockbox (FC_HEADER_VAL,
        // firmware/font.c) en Swift. Fase 2A no lo hace (queda para
        // cuando exista el rasterizador de Fase 2B, que de todos modos
        // produce el archivo y podria verificarlo al escribirlo): esta
        // pasada solo confirma que los 14 archivos existen. El firmware
        // sigue siendo la ultima palabra -- si un .fnt esta corrupto,
        // font_load() falla ahi y aura_style_activate() revierte solo
        // (D-289), asi que un paquete que pase esta validacion pero
        // tenga un .fnt roto no deja el dispositivo sin UI legible.
        let fontsDir = packageRoot.appendingPathComponent("fonts")
        let missingFonts = ThemeFormat.fontRoles.map(\.role).filter { role in
            !fileManager.fileExists(atPath: fontsDir.appendingPathComponent("\(role).fnt").path)
        }
        guard missingFonts.isEmpty else {
            return .failure(.missingFonts(missingFonts))
        }

        let masksDir = packageRoot.appendingPathComponent("icons/masks")
        let maskCount = (try? fileManager.contentsOfDirectory(atPath: masksDir.path))?
            .filter { $0.hasSuffix(".bmp") }.count ?? 0
        guard maskCount >= ThemeFormat.requiredMaskCount else {
            return .failure(.missingMasks(found: maskCount, required: ThemeFormat.requiredMaskCount))
        }

        return .success(manifest)
    }
}
