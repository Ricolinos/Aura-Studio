import Foundation

/// Por qué conviene migrar esta biblioteca (ST-226). Los dos motivos se
/// cuentan por separado porque se le dicen por separado al usuario.
struct LibraryMigrationNeed: Equatable {
    /// Elementos cuyo catálogo no dice cómo están guardados (anterior a
    /// ST-221).
    var itemsWithoutStorage: Int = 0
    /// Derivados con el nombre viejo -- el del archivo de origen -- en
    /// vez del identificador (ST-221).
    var legacyPrepared: Int = 0

    static let none = LibraryMigrationNeed()

    var isNeeded: Bool { itemsWithoutStorage > 0 || legacyPrepared > 0 }
    var total: Int { itemsWithoutStorage + legacyPrepared }

    /// Lo que dice la franja. Nombra **los dos motivos por separado**:
    /// "hay que migrar 400 cosas" no le dice al usuario qué va a pasar
    /// con su biblioteca.
    var message: String {
        var parts: [String] = []
        if itemsWithoutStorage > 0 {
            parts.append(LSf("library-migration.plural.sin-modo-guardado", itemsWithoutStorage))
        }
        if legacyPrepared > 0 {
            parts.append(LSf("library-migration.plural.nombre-viejo", legacyPrepared))
        }
        // ST-227 (A7c addendum 3): la frase entera sale del catálogo,
        // separadores incluidos. Antes el encabezado y el " y " eran
        // literales en español pegados a fragmentos traducidos -- con la
        // app en alemán salía media oración en cada idioma.
        return Sentence.ended(LSf("library-migration.viene-de-version-anterior", Sentence.list(parts)))
    }
}

/// ST-226: detecta si una biblioteca viene de una versión anterior.
///
/// **Barato, y solo con el catálogo.** Corre al abrir la biblioteca, así
/// que no puede preguntarle al disco por cada archivo: las rondas
/// anteriores sacaron justamente eso de la carga, y volver a meterlo por
/// una comprobación de migración sería deshacerlo. Las dos señales salen
/// de datos que la carga ya tenía en la mano.
///
/// **Y no hay campo "migrada" en el catálogo.** Las señales se apagan
/// solas cuando la migración hace su trabajo: el `storage` queda escrito
/// y los derivados quedan renombrados. Una marca aparte sería un dato que
/// puede mentir -- alguien copia el catálogo de otra máquina, o algo
/// falla a mitad y la marca ya está puesta.
///
/// **Lo que no se puede detectar barato se confirma adentro de la
/// migración.** Que una copia de `Música/` tenga o no las etiquetas del
/// catálogo solo se sabe abriendo el archivo, y eso lo hace la migración
/// cuando corre, no el arranque. La consecuencia, dicha para que no
/// sorprenda: una biblioteca cuyo **único** problema sea ese no dispara
/// el aviso sola; se migra desde Ajustes, donde la acción está siempre.
enum LibraryMigrationScanner {
    /// - Parameter itemsWithoutStorage: lo que contó la carga. **No se
    ///   puede recalcular** desde los elementos vivos: para cuando llegan
    ///   acá, `storage` ya está inferido y no queda rastro de que faltaba.
    static func detect(items: [LibraryItem], itemsWithoutStorage: Int) -> LibraryMigrationNeed {
        LibraryMigrationNeed(itemsWithoutStorage: itemsWithoutStorage,
                             legacyPrepared: items.filter(hasLegacyPreparedName).count)
    }

    /// Si el derivado de este elemento tiene el nombre viejo. Es
    /// comparación de texto: **no toca disco**.
    ///
    /// La música **copiada** no cuenta: su derivado es el archivo mismo
    /// (ST-223) y no vive en `.preparados/`, así que su nombre no tiene
    /// por qué ser un identificador.
    static func hasLegacyPreparedName(_ item: LibraryItem) -> Bool {
        guard let prepared = item.preparedURL else { return false }
        if item.kind == .music && item.storage == .copy { return false }
        if prepared.standardizedFileURL == item.sourceURL.standardizedFileURL { return false }
        let expected = "\(item.id.uuidString).\(prepared.pathExtension)"
        return SharedCatalogPath.catalogNormalized(prepared.lastPathComponent).caseInsensitiveCompare(expected) != .orderedSame
    }
}

/// Qué hizo la migración (ST-226). Se le cuenta al usuario tal cual.
struct LibraryMigrationSummary: Equatable {
    /// Copias de `Música/` a las que se les escribieron las etiquetas.
    var tagged: Int = 0
    /// Derivados que pasaron a llamarse por identificador.
    var preparedRenamed: Int = 0
    /// Derivados que hubo que armar porque faltaban.
    var preparedBuilt: Int = 0
    /// Derivados y carátulas que ya no referenciaba nadie.
    var orphansDeleted: Int = 0
    /// Qué falló, con el nombre del archivo. Para poder decirlo, no para
    /// tragárselo.
    var errors: [String] = []
    /// Si el usuario la paró a mitad. Lo hecho hasta ahí queda hecho.
    var cancelled: Bool = false

    var touched: Int { tagged + preparedRenamed + preparedBuilt + orphansDeleted }

    var message: String {
        var parts: [String] = []
        if tagged > 0 { parts.append(LSf("library-migration.plural.con-etiquetas-nuevas", tagged)) }
        if preparedRenamed > 0 { parts.append(LSf("library-migration.plural.preparados-renombrados", preparedRenamed)) }
        if preparedBuilt > 0 { parts.append(LSf("library-migration.plural.preparados-armados", preparedBuilt)) }
        if orphansDeleted > 0 { parts.append(LSf("library-migration.plural.huerfanos-borrados", orphansDeleted)) }
        if parts.isEmpty { parts.append(LS("library-migration.no-hizo-falta-tocar-nada")) }
        let cuerpo = Sentence.commaList(parts)
        // La clave con un literal en cada rama, no un ternario adentro
        // de `LSf`: el inventario de claves lee el código con una
        // expresión regular y una clave calculada se le vuelve
        // invisible (ver `testEveryLocalizationCallUsesALiteralKey`).
        let encabezado = cancelled
            ? LSf("library-migration.cancelada", cuerpo)
            : LSf("library-migration.terminada", cuerpo)
        var message = Sentence.ended(encabezado)
        if !errors.isEmpty {
            message += " " + Sentence.ended(LSf("library-migration.plural.fallaron-siguen", errors.count))
        }
        return message
    }
}
