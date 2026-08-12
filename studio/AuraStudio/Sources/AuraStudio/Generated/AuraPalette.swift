// Generado por design-system/generate.py a partir de tokens.json.
// NO editar a mano: los cambios se perderian al regenerar.

import SwiftUI

/// Paleta compartida con el firmware -- misma fuente de verdad
/// (design-system/tokens.json) que apple2026_tokens.h. Los nombres de
/// los campos son los mismos tokens del sistema de diseno Apple2026
/// (docs/design/Reglas de diseno Apple2026 (v2).md); "Aura" en el
/// nombre del tipo es el producto, no el sistema de diseno.
struct AuraColors {
    let shellBg: Color
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let accent: Color
    let shellRail: Color
    let progressFill: Color
    let progressTrack: Color
    let selectionFill: Color
    let whiteConstant: Color
}

extension AuraColors {
    static let light = AuraColors(
        shellBg: Color(red: 1.0000, green: 1.0000, blue: 1.0000),
        textPrimary: Color(red: 0.0000, green: 0.0000, blue: 0.0000),
        textSecondary: Color(red: 0.4314, green: 0.4314, blue: 0.4510),
        textTertiary: Color(red: 0.2353, green: 0.2353, blue: 0.2627),
        accent: Color(red: 1.0000, green: 0.1765, blue: 0.3333),
        shellRail: Color(red: 0.7765, green: 0.7765, blue: 0.7843),
        progressFill: Color(red: 0.2353, green: 0.2353, blue: 0.2627),
        progressTrack: Color(red: 0.8980, green: 0.8980, blue: 0.9176),
        selectionFill: Color(red: 0.8980, green: 0.8980, blue: 0.9176),
        whiteConstant: Color(red: 1.0000, green: 1.0000, blue: 1.0000)
    )
    static let dark = AuraColors(
        shellBg: Color(red: 0.1098, green: 0.1098, blue: 0.1176),
        textPrimary: Color(red: 1.0000, green: 1.0000, blue: 1.0000),
        textSecondary: Color(red: 0.5961, green: 0.5961, blue: 0.6157),
        textTertiary: Color(red: 0.7804, green: 0.7804, blue: 0.8000),
        accent: Color(red: 1.0000, green: 0.2706, blue: 0.4235),
        shellRail: Color(red: 0.2275, green: 0.2275, blue: 0.2353),
        progressFill: Color(red: 0.8980, green: 0.8980, blue: 0.9176),
        progressTrack: Color(red: 0.2824, green: 0.2824, blue: 0.2902),
        selectionFill: Color(red: 0.1725, green: 0.1725, blue: 0.1804),
        whiteConstant: Color(red: 1.0000, green: 1.0000, blue: 1.0000)
    )
}
