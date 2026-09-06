import Foundation

/// PLAN-studio-rendimiento.md Fase 4 punto 1: una única fuente de verdad
/// para "qué está corriendo en segundo plano ahora mismo", que reemplaza
/// los booleanos sueltos de `LibraryViewModel` (`isProcessing`,
/// `isFetchingArtistImages`, `isVerifyingDevice`, `isFetchingVideoPosters`,
/// `isApplyingRecommendedCovers`, más el `@State isEnriching` que vivía
/// en `MediaSectionView`) -- cada uno era su propio interruptor, sin
/// cola, sin cancelación uniforme, y sin un solo lugar donde mostrarlos
/// todos.
///
/// Diagnóstico §0.8: "bien hechos y patrón a copiar" ya señalaba al sync
/// (`DeviceActivityBar`) y a la migración de carátulas ST-141
/// (`CoverNormalizationBar`) como el modelo -- esto generaliza esa idea
/// a cualquier operación larga, no solo a esas dos.
@MainActor
final class BackgroundTaskCenter: ObservableObject {
    /// PLAN-studio-rendimiento-2.md Fase 6 (ST-186): de qué TIPO es una
    /// tarea, para poder decir "de estas, una a la vez".
    ///
    /// No es una categoría decorativa: dos operaciones del mismo tipo
    /// pelean por el mismo recurso. Dos enriquecimientos a la vez
    /// (pedir "Buscar información en línea" desde Álbumes y desde
    /// Canciones, que hoy nada impide) se reparten el mismo cupo de 1
    /// pedido/segundo de MusicBrainz y tardan el doble cada uno, sin que
    /// nada vaya más rápido. Tipos DISTINTOS sí corren en paralelo:
    /// enriquecer mientras se sincroniza es perfectamente razonable.
    enum TaskKind: Sendable, Equatable {
        /// Metadata en línea (MusicBrainz/LRCLIB): cupo compartido.
        case enrichment
        /// Carátulas y pósters en línea (Cover Art Archive, Deezer,
        /// TMDB, fanart.tv).
        case artwork
        /// Trabajo local sobre archivos (importar, editar en lote,
        /// aplicar una carátula ya elegida).
        case files
        /// Lo que no necesita exclusión con nada.
        case other
    }

    enum Progress: Equatable {
        /// "N de M" -- se conoce el total de antemano (enriquecer,
        /// edición en lote, importar).
        case determinate(completed: Int, total: Int)
        /// No se puede estimar cuánto falta (verificar dispositivo,
        /// buscar carátulas recomendadas).
        case indeterminate

        var fraction: Double? {
            guard case let .determinate(completed, total) = self, total > 0 else { return nil }
            return Double(completed) / Double(total)
        }
    }

    /// Una tarea visible en el centro. `ObservableObject` propio (no
    /// solo un struct) para que actualizar SU progreso no publique
    /// `objectWillChange` de todo `BackgroundTaskCenter` -- una fila del
    /// popover se repinta sola, no la lista entera ni la ventana.
    @MainActor
    final class TaskHandle: ObservableObject, Identifiable {
        let id = UUID()
        /// En español, de cara al usuario -- "Buscando información en
        /// línea…", "Importando 200 archivos…".
        let title: String
        let kind: TaskKind
        @Published private(set) var progress: Progress
        /// Detalle opcional bajo el título -- "Álbum 12 de 40".
        @Published var statusText: String?
        /// `nil` mientras corre bien. Si se pone, la fila del popover lo
        /// muestra y dejar de existir depende de `finish`/`cancel`, igual
        /// que una que terminó bien -- un error no dura para siempre.
        @Published private(set) var errorText: String?
        private(set) var isCancelled = false
        private let onCancelRequested: (@MainActor () -> Void)?

        /// `true` cuando la tarea no ofrece cancelar (encargo del
        /// dueño: algunas operaciones, como escribir el catálogo, no se
        /// pueden interrumpir a medias sin arriesgar corromper algo).
        var isCancellable: Bool { onCancelRequested != nil }

        init(title: String, kind: TaskKind = .other, progress: Progress,
             onCancelRequested: (@MainActor () -> Void)? = nil) {
            self.title = title
            self.kind = kind
            self.progress = progress
            self.onCancelRequested = onCancelRequested
        }

        func update(_ progress: Progress, statusText: String? = nil) {
            self.progress = progress
            if let statusText { self.statusText = statusText }
        }

        func fail(_ message: String) {
            errorText = message
        }

        func requestCancel() {
            guard !isCancelled else { return }
            isCancelled = true
            onCancelRequested?()
        }
    }

    @Published private(set) var tasks: [TaskHandle] = []

    var isEmpty: Bool { tasks.isEmpty }
    var count: Int { tasks.count }

    /// Progreso agregado para el anillo de la barra de estado: el
    /// promedio de las tareas determinadas: las indeterminadas no
    /// aportan una fracción, así que no cuentan para el promedio, pero
    /// SU sola presencia ya alcanza para que `count > 0` muestre el
    /// indicador (un anillo animado sin fracción fija, como el de
    /// Finder mientras calcula "Preparando…").
    var aggregateFraction: Double? {
        let fractions = tasks.compactMap(\.progress.fraction)
        guard !fractions.isEmpty else { return nil }
        return fractions.reduce(0, +) / Double(fractions.count)
    }

    /// Registra una tarea nueva y la deja visible de inmediato. El
    /// llamador se queda con el `TaskHandle` para actualizar su
    /// progreso y llamar `finish(_:)` cuando termine -- `defer { center.
    /// finish(handle) }` es el patrón esperado, para que un `throw` a
    /// mitad de camino no deje la tarea pegada en el centro para
    /// siempre.
    @discardableResult
    func begin(title: String, kind: TaskKind = .other, progress: Progress = .indeterminate,
              onCancelRequested: (@MainActor () -> Void)? = nil) -> TaskHandle {
        let handle = TaskHandle(title: title, kind: kind, progress: progress,
                                onCancelRequested: onCancelRequested)
        tasks.append(handle)
        return handle
    }

    /// ¿Hay ya una tarea de este tipo corriendo? (ST-186.) Quien va a
    /// empezar una que pelea por un recurso compartido pregunta acá en
    /// vez de llevar su propio booleano suelto -- que es lo que ST-156
    /// dejó anotado como pendiente: cada operación tenía su interruptor,
    /// sin un solo lugar donde mirarlos todos.
    func isRunning(_ kind: TaskKind) -> Bool {
        tasks.contains { $0.kind == kind && !$0.isCancelled }
    }

    func finish(_ handle: TaskHandle) {
        tasks.removeAll { $0.id == handle.id }
    }
}
