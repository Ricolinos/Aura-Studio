import Foundation

/// Fase 24 (PLAN-UX.md): una playlist armada en Studio a partir de los
/// `LibraryItem` de musica ya agregados en esta sesion (no de un catalogo
/// persistente del dispositivo -- Studio no mantiene una base de datos
/// de lo que ya esta en el iPod, ver LibrarySync). `trackItemIDs` guarda
/// el orden elegido por el usuario; se resuelve a rutas reales del
/// dispositivo recien al sincronizar, en `LibrarySync`.
struct Playlist: Identifiable, Equatable {
    let id: UUID
    var name: String
    var trackItemIDs: [UUID]

    init(id: UUID = UUID(), name: String, trackItemIDs: [UUID] = []) {
        self.id = id
        self.name = name
        self.trackItemIDs = trackItemIDs
    }
}
