// Generado por design-system/generate.py a partir de tokens.json.
// NO editar a mano: los cambios se perderian al regenerar.

import SwiftUI

/// Paleta compartida con el firmware -- misma fuente de verdad
/// (design-system/tokens.json) que aura_tokens.h.
struct AuraColors {
    let background: Color
    let surface: Color
    let textPrimary: Color
    let textSecondary: Color
    let border: Color
    let accent: Color
    let selection: Color
    let onSelection: Color
}

extension AuraColors {
    static let light = AuraColors(
        background: Color(red: 1.0000, green: 1.0000, blue: 1.0000),
        surface: Color(red: 0.9686, green: 0.9686, blue: 0.9686),
        textPrimary: Color(red: 0.0392, green: 0.0392, blue: 0.0392),
        textSecondary: Color(red: 0.4196, green: 0.4196, blue: 0.4196),
        border: Color(red: 0.8784, green: 0.8784, blue: 0.8784),
        accent: Color(red: 0.9490, green: 0.1059, blue: 0.2000),
        selection: Color(red: 0.9373, green: 0.9373, blue: 0.9373),
        onSelection: Color(red: 0.9490, green: 0.1059, blue: 0.2000)
    )
    static let dark = AuraColors(
        background: Color(red: 0.0000, green: 0.0000, blue: 0.0000),
        surface: Color(red: 0.1098, green: 0.1098, blue: 0.1176),
        textPrimary: Color(red: 1.0000, green: 1.0000, blue: 1.0000),
        textSecondary: Color(red: 0.6039, green: 0.6039, blue: 0.6039),
        border: Color(red: 0.1725, green: 0.1725, blue: 0.1804),
        accent: Color(red: 0.9490, green: 0.1059, blue: 0.2000),
        selection: Color(red: 0.1725, green: 0.1725, blue: 0.1804),
        onSelection: Color(red: 0.9490, green: 0.1059, blue: 0.2000)
    )
}
