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
    /// Imagen elegida a mano por el usuario (encargo del dueno,
    /// 2026-08-14), relativa a la carpeta de biblioteca -- mismo criterio
    /// que `coverRelativePath` de un `LibraryItem` (LibraryPersistence.swift):
    /// un archivo cacheado en `.portadas/`, no Data embebida aca, para
    /// que el catalogo siga siendo liviano. `nil` = sin imagen propia;
    /// LibrarySync genera un default (colage/tile) al sincronizar.
    var imageRelativePath: String?

    init(id: UUID = UUID(), name: String, trackItemIDs: [UUID] = [], imageRelativePath: String? = nil) {
        self.id = id
        self.name = name
        self.trackItemIDs = trackItemIDs
        self.imageRelativePath = imageRelativePath
    }
}
