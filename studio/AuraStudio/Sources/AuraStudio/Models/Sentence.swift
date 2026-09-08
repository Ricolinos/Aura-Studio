import Foundation

/// ST-227 (A7c, addendum 3): arma una oración a partir de piezas.
///
/// **Por qué hace falta un tipo para unir strings.** Windows encontró el
/// defecto en su lado y acá era idéntico: un resumen se armaba de ocho
/// pedazos y solo el que tenía plural venía del catálogo. Con la app en
/// alemán el usuario leía *"Biblioteca migrada: die Tags von 3 Titeln
/// wurden geschrieben, se ordenaron 2 preparados."* -- sin ningún error,
/// ilegible, y **invisible para cualquier prueba de cadenas sueltas**:
/// cada pedazo por separado estaba bien. El defecto solo existe en la
/// unión, así que la unión tiene que pasar por un sitio.
///
/// **Los separadores también son texto.** La coma, el "y", el punto
/// final y los dos puntos no son puntuación universal: el japonés usa
/// `、` y `。`, y el francés pone espacio fino antes de `;` y `:`. Un
/// `", "` escrito en el código es español disfrazado de puntuación.
enum Sentence {
    /// "a, b y c" -- coma entre las primeras y "y" antes de la última,
    /// que es como se enumera en español, inglés, alemán y francés. En
    /// japonés las tres claves son `、`, así que sale bien sola.
    static func list(_ parts: [String]) -> String {
        guard let last = parts.last else { return "" }
        guard parts.count > 1 else { return last }
        return parts.dropLast().joined(separator: LS("sentence.separator-comma"))
            + LS("sentence.separator-and") + last
    }

    /// "a, b, c" -- enumeración simple, sin "y".
    static func commaList(_ parts: [String]) -> String {
        parts.joined(separator: LS("sentence.separator-comma"))
    }

    /// "a; b; c" -- para cláusulas que ya llevan comas adentro.
    static func clauses(_ parts: [String]) -> String {
        parts.joined(separator: LS("sentence.separator-semicolon"))
    }

    /// "a · b · c" -- el estilo de la barra de estado, sin punto final.
    static func fields(_ parts: [String]) -> String {
        parts.joined(separator: LS("sentence.separator-middot"))
    }

    /// Cierra con el punto del idioma. Si la frase ya termina en un
    /// signo de cierre no se le agrega otro: un "…" o un "?" que quedó
    /// al final de un fragmento es el final de la oración.
    static func ended(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        let closers: Set<Character> = [".", "。", "!", "?", "…", "！", "？"]
        if let last = text.last, closers.contains(last) { return text }
        return text + LS("sentence.period")
    }

    /// Dos oraciones seguidas. En español, inglés, alemán, francés y
    /// ruso van separadas por un espacio; en japonés el `。` ya cierra y
    /// no se agrega nada, así que el separador es la clave
    /// `sentence.separator-sentence` y no un `" "` incrustado.
    static func sentences(_ parts: [String]) -> String {
        parts.filter { !$0.isEmpty }.map(ended)
            .joined(separator: LS("sentence.separator-sentence"))
    }

    /// "Encabezado: resto".
    static func titled(_ title: String, _ rest: String) -> String {
        title + LS("sentence.colon") + rest
    }
}
