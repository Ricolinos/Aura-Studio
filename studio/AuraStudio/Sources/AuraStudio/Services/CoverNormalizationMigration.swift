import Foundation

/// La pasada única que deja cuadradas las carátulas de una biblioteca
/// hecha antes de ST-141. Es la mitad "recorrer y reescribir" del
/// trabajo; qué archivos entran lo decide `LibraryViewModel`
/// (`coverFilesToNormalize`), que es quien sabe cuáles son de música y
/// cuáles son pósters de video -- **los pósters no se tocan: son 3:4 por
/// diseño** (contrato §A.1).
///
/// Tres propiedades que no son negociables, y por las que esto es un
/// tipo aparte con pruebas propias:
///
/// - **No reescribe lo que ya cumple.** Un archivo cuadrado de lado
///   ≤ 1000 se salta sin decodificarlo: leer la cabecera cuesta casi
///   nada y recomprimirlo de gratis solo perdería calidad.
/// - **Se puede cancelar**, y se consulta antes de cada archivo. Un
///   archivo empezado se termina (la escritura es atómica), pero no se
///   empieza el siguiente.
/// - **Se puede retomar.** No hace falta un archivo de progreso: como
///   saltarse lo ya hecho es la regla, la segunda corrida arranca donde
///   quedó la primera. Por eso la marca `coversNormalized` se escribe
///   **solo al terminar la pasada completa**: si se canceló, la próxima
///   apertura vuelve a recorrer (barato) y termina el resto.
enum CoverNormalizationMigration {
    struct Result: Equatable {
        /// Cuántas se reescribieron de verdad.
        var normalized = 0
        /// Cuántas se miraron (normalizadas + ya correctas + ilegibles).
        var visited = 0
        /// Quedó trabajo pendiente porque se canceló.
        var cancelled = false
    }

    /// Recorre `files` en orden. `isCancelled` se consulta antes de cada
    /// archivo; `onProgress` recibe (hechas, total) después de cada uno.
    static func run(files: [URL],
                    isCancelled: @Sendable () -> Bool = { false },
                    onProgress: @Sendable (Int, Int) -> Void = { _, _ in }) -> Result {
        var result = Result()
        for url in files {
            if isCancelled() {
                result.cancelled = true
                return result
            }
            if CoverArtNormalizer.normalizeFile(at: url) { result.normalized += 1 }
            result.visited += 1
            onProgress(result.visited, files.count)
        }
        return result
    }
}

/// Lo que la app muestra mientras la migración corre (barra de estado).
struct CoverNormalizationProgress: Equatable {
    var completed: Int
    var total: Int

    var fraction: Double { total > 0 ? Double(completed) / Double(total) : 0 }

    var label: String {
        "Normalizando carátulas… \(completed) de \(total)"
    }
}
