import Foundation

/// Cómo se homologan los nombres de artista al AGRUPAR (R2-4, ST-116).
/// Viaja explícito por parámetro -- igual que `musicOrganization` y
/// compañía en `LibrarySync.sync` -- en vez de vivir en un global: así
/// una prueba puede fijar sus opciones sin tocar las preferencias
/// reales, y `LibrarySync` (que corre fuera del hilo principal) las
/// recibe como valor.
struct ArtistGroupingOptions: Sendable, Equatable {
    /// Ajuste del usuario. Apagado, `principalArtist` devuelve el nombre
    /// tal cual y la agrupación vuelve a ser exactamente la de antes.
    var homologateCollaborations: Bool
    /// Nombres que NUNCA se recortan, tal como el usuario los escribió.
    /// Existe porque la lista de separadores es cerrada y ciega: "Café
    /// con Leche" o "Simon + Garfunkel" son nombres de grupo, no
    /// colaboraciones, y no hay forma de distinguirlos automáticamente.
    var exceptions: [String]

    static let `default` = ArtistGroupingOptions(homologateCollaborations: true, exceptions: [])

    init(homologateCollaborations: Bool = true, exceptions: [String] = []) {
        self.homologateCollaborations = homologateCollaborations
        self.exceptions = exceptions
    }
}

/// Artista PRINCIPAL de un crédito con colaboración (R2-4).
///
/// Ver `docs/normalizacion-artistas.md` -- ese documento es la
/// especificación vinculante y la app de Windows implementa lo mismo.
/// Lo esencial:
///
/// - El principal es **lo que precede al primer separador de
///   colaboración**, buscando los separadores como PALABRA COMPLETA
///   (entre espacios), sin distinguir mayúsculas ni acentos.
/// - La lista de separadores es **cerrada**: no se amplía "porque
///   parece" -- cada entrada nueva reagrupa la biblioteca de alguien.
/// - **`vs.` / `versus` NO homologan**: una colaboración con identidad
///   propia es un artista distinto ("Spacemonkeyz vs. Gorillaz" no es
///   Gorillaz). Decisión explícita del dueño.
/// - Esto es **solo para agrupar**. El `artist` de la pista no se toca
///   nunca: los créditos completos se conservan en la metadata y se
///   siguen viendo en la tabla y en "Más información".
enum ArtistNameNormalizer {
    /// Lista CERRADA, en el orden en que se documenta. Se comparan como
    /// palabra completa, así que "feat." y "feat" son entradas
    /// distintas a propósito (y "ft." no matchea dentro de "Daft").
    static let collaborationSeparators: [String] = [
        "feat.", "feat", "ft.", "ft", "featuring", "+", "with", "con",
    ]

    /// Lo que explícitamente NO es un separador, aunque una a dos
    /// artistas. Documentado como lista para que se lea como decisión y
    /// no como olvido.
    static let neverSeparators: [String] = ["vs.", "vs", "versus"]

    /// Comparación insensible a mayúsculas y acentos, para separadores y
    /// para excepciones.
    static func fold(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// El artista principal de `raw`, o `raw` intacto si no hay nada que
    /// recortar.
    ///
    /// Devuelve SIEMPRE algo no vacío: un crédito que empieza con el
    /// separador ("feat. Alguien", sin artista antes) se deja tal cual
    /// -- recortarlo daría la cadena vacía, que agruparía esa pista bajo
    /// "Artista desconocido" y sería peor que no hacer nada.
    static func principalArtist(_ raw: String, options: ArtistGroupingOptions = .default) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard options.homologateCollaborations, !trimmed.isEmpty else { return trimmed }

        let folded = fold(trimmed)
        guard !options.exceptions.contains(where: { fold($0) == folded }) else { return trimmed }

        // Se parte por espacios en blanco y se busca el primer token que
        // sea exactamente un separador. Trabajar por tokens (y no con
        // `range(of:)`) es lo que evita cortar "Daft Punk" por el "ft"
        // de adentro, y lo que hace que "+" solo cuente cuando va suelto
        // ("Simon + Garfunkel", no "Blink+182").
        let tokens = trimmed.split(whereSeparator: \.isWhitespace)
        guard tokens.count >= 2 else { return trimmed }

        for (index, token) in tokens.enumerated() {
            let foldedToken = fold(String(token))
            guard collaborationSeparators.contains(foldedToken) else { continue }
            // Un separador en la primera posición no deja artista
            // principal: no hay nada que recortar.
            guard index > 0 else { return trimmed }
            let principal = tokens[0..<index].joined(separator: " ")
            return principal.isEmpty ? trimmed : principal
        }
        return trimmed
    }

    /// `true` si `raw` trae créditos además del artista principal --
    /// para poder decirlo en pantalla sin recalcular.
    static func hasCollaborators(_ raw: String, options: ArtistGroupingOptions = .default) -> Bool {
        principalArtist(raw, options: options) != raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
