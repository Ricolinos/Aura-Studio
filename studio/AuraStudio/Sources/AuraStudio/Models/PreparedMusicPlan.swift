import Foundation

/// Qué hay que hacer con el derivado de una canción referenciada
/// (ST-224). Hermano de `PreparedMusic.cs` de Windows (ST-244): mismos
/// casos, mismos motivos, misma holgura.
enum PreparedMusicAction: Equatable {
    /// No hace falta ninguno: al iPod puede viajar el archivo tal como
    /// está.
    case none
    /// Hay que armarlo desde el origen.
    case build
    /// Ya está y sirve; a lo sumo hay que refrescarle las etiquetas.
    case keep
}

/// La decisión, con el motivo dicho. El motivo es lo que se registra y
/// lo que se prueba -- una decisión sin motivo no se puede revisar
/// después.
struct PreparedMusicDecision: Equatable {
    var action: PreparedMusicAction
    var reason: String
}

/// ST-224: cuándo hace falta un derivado de música y cuándo no.
///
/// **La regla que evita duplicar la biblioteca entera.** En modo
/// referencia, Ajustes le promete al usuario que su disco no termina con
/// una copia de toda su biblioteca. Armar un derivado por cada canción
/// rompería esa promesa -- y `.preparados/` no se limpia sola (ST-087).
/// Así que **solo se prepara lo que hay que preparar**: la canción cuyo
/// archivo ya dice lo que dice el catálogo viaja al iPod tal como está.
///
/// Hasta acá la Mac preparaba **siempre**: toda canción referenciada
/// tenía su copia en `.preparados/`, la necesitara o no.
///
/// Y una vez preparado, **no se rehace por gusto**. Se rehace si el
/// origen cambió -- de tamaño, o con fecha más nueva que el derivado --;
/// si solo cambió una etiqueta, se le reescribe la etiqueta al derivado
/// y listo. Copiar de nuevo cincuenta megabytes porque alguien corrigió
/// un año es exactamente lo que esta ronda vino a no hacer.
enum PreparedMusicPlan {
    /// Holgura al comparar fechas. Los sistemas de archivos no guardan
    /// todos la misma precisión -- FAT redondea a dos segundos -- y sin
    /// holgura un derivado se reharía en cada pasada, para siempre.
    /// Mismo valor que Windows, a propósito: la misma biblioteca se abre
    /// desde los dos lados.
    static let modifiedTolerance: TimeInterval = 2

    /// Qué hacer, **sin tocar disco**: quien llama trae los datos ya
    /// leídos. Así la regla se puede probar sin fabricar archivos con
    /// fechas puestas a mano.
    ///
    /// - Parameters:
    ///   - needed: si hace falta un derivado, porque hay que convertir el
    ///     formato o porque el archivo de origen no dice lo que dice el
    ///     catálogo.
    ///   - catalogSourceSize: el tamaño del origen **según el catálogo**
    ///     (ST-186). `nil` en un catálogo viejo que no lo trae: entonces
    ///     el tamaño no opina y decide la fecha.
    static func decide(needed: Bool,
                       preparedExists: Bool,
                       catalogSourceSize: Int?,
                       currentSourceSize: Int,
                       sourceModified: Date?,
                       preparedModified: Date?) -> PreparedMusicDecision {
        guard needed else {
            return PreparedMusicDecision(action: .none,
                                         reason: "el archivo de origen ya sirve tal como está")
        }
        guard preparedExists else {
            return PreparedMusicDecision(action: .build, reason: "todavía no hay preparado")
        }
        if let known = catalogSourceSize, known != currentSourceSize {
            return PreparedMusicDecision(action: .build, reason: "el archivo de origen cambió de tamaño")
        }
        guard let sourceModified, let preparedModified else {
            // Sin fechas no se puede afirmar que el derivado esté al día,
            // y el lado seguro es rehacerlo: servir uno viejo manda al
            // iPod las etiquetas que el usuario ya corrigió.
            return PreparedMusicDecision(action: .build, reason: "no se pudo leer la fecha de los archivos")
        }
        if sourceModified.timeIntervalSince(preparedModified) > modifiedTolerance {
            return PreparedMusicDecision(action: .build, reason: "el archivo de origen es más nuevo que el preparado")
        }
        return PreparedMusicDecision(action: .keep, reason: "el preparado sigue sirviendo")
    }
}
