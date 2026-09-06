import Foundation
import SwiftUI

/// Lo que muestra la barra de estado al pie de cada sección de la
/// biblioteca (ST-063, encargo del dueño, 2026-08-23: "al estilo de la
/// barra de estado del Finder"): un resumen del total de la sección
/// (izquierda), opcionalmente lo que hay seleccionado (centro) y un
/// dato extra a la derecha (tamaño en disco, duración total...).
///
/// Cada vista arma el suyo con `LibraryStats` y lo publica hacia
/// `ContentView` con `.libraryStatus(_:)` (ver `LibraryStatusCenter`,
/// así la barra vive UNA sola vez en la raíz y las vistas no saben nada
/// de cómo se dibuja ni de si el usuario la ocultó desde el menú
/// Visualización).
struct LibraryStatusSummary: Equatable {
    /// "128 canciones · 12 artistas · 20 álbumes"
    var total: String
    /// "5 seleccionadas · 2 artistas · 3 álbumes" -- `nil` sin selección.
    var selection: String?
    /// Dato a la derecha: "8 h 12 min · 1.2 GB". `nil` si no aplica.
    var trailing: String?

    init(total: String, selection: String? = nil, trailing: String? = nil) {
        self.total = total
        self.selection = selection
        self.trailing = trailing
    }
}

/// PLAN-studio-rendimiento-2.md Fase 1 (ST-181): a dónde publica cada
/// sección su resumen. Antes era un `PreferenceKey` que `ContentView`
/// recogía con `onPreferenceChange` hacia un `@State` suyo -- y eso
/// cuesta **dos pasadas completas de `body` por cada clic**: la primera
/// calcula el árbol y sus preferencias, la segunda vuelve a calcularlo
/// todo porque el `@State` de la raíz cambió (diagnóstico §0.3, era el
/// punto que la ronda 1 pidió quitar y quedó pendiente).
///
/// Con un objeto chico y aparte, publicar el resumen invalida SOLO a la
/// barra de estado (`LibraryStatusBarHost`, que es quien lo observa) y
/// no a la ventana entera: `ContentView` lo guarda en un `@State` --
/// que sostiene la referencia sin suscribirse -- y se lo pasa a la
/// barra y al entorno.
///
/// `owner` (un id estable por vista publicadora) conserva la semántica
/// que daba `reduce` del `PreferenceKey`: publicar `nil` desde una vista
/// que NO es la dueña no borra el resumen de la que sí lo es -- así, la
/// tabla embebida dentro de un álbum abierto (que publica `nil`, porque
/// el resumen lo arma la vista contenedora) no apaga la barra.
@MainActor
final class LibraryStatusCenter: ObservableObject {
    @Published private(set) var summary: LibraryStatusSummary?

    private var owner: UUID?

    func publish(_ summary: LibraryStatusSummary?, from owner: UUID) {
        if let summary {
            self.owner = owner
            if self.summary != summary { self.summary = summary }
        } else if self.owner == owner {
            withdraw(owner)
        }
    }

    /// La vista publicadora se va de pantalla.
    func withdraw(_ owner: UUID) {
        guard self.owner == owner else { return }
        self.owner = nil
        if summary != nil { summary = nil }
    }
}

private struct LibraryStatusCenterKey: EnvironmentKey {
    /// `nil` a propósito: el centro lo inyecta `ContentView`, uno por
    /// ventana (`WindowGroup` puede abrir varias y cada una tiene su
    /// propia biblioteca). Sin centro, `.libraryStatus(_:)` no hace nada
    /// -- que es justo lo que corresponde en una vista suelta de prueba.
    static let defaultValue: LibraryStatusCenter? = nil
}

extension EnvironmentValues {
    var libraryStatusCenter: LibraryStatusCenter? {
        get { self[LibraryStatusCenterKey.self] }
        set { self[LibraryStatusCenterKey.self] = newValue }
    }
}

extension View {
    /// Publica el resumen de esta sección para la barra de estado.
    func libraryStatus(_ summary: LibraryStatusSummary?) -> some View {
        modifier(LibraryStatusPublisher(summary: summary))
    }
}

/// El puente entre una sección y el centro. Publica **fuera del `body`**
/// (`onAppear`/`onChange`), así escribir el resumen nunca es un cambio
/// de estado durante una pasada de dibujo.
private struct LibraryStatusPublisher: ViewModifier {
    let summary: LibraryStatusSummary?

    @Environment(\.libraryStatusCenter) private var center
    /// Identidad estable de ESTA vista mientras viva en pantalla.
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { center?.publish(summary, from: id) }
            .onChange(of: summary) { _, new in center?.publish(new, from: id) }
            .onDisappear { center?.withdraw(id) }
    }
}

/// Cálculos puros (testables) detrás de la barra de estado: conteos de
/// canciones/artistas/álbumes, duración y tamaño, con la pluralización
/// en español que usa toda la app.
enum LibraryStats {
    // MARK: - Texto

    /// "1 canción" / "3 canciones".
    static func count(_ n: Int, _ singular: String, _ plural: String) -> String {
        "\(formatted(n)) \(n == 1 ? singular : plural)"
    }

    static func formatted(_ n: Int) -> String {
        Self.numberFormatter.string(from: NSNumber(value: n)) ?? String(n)
    }

    private static let numberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "es_MX")
        return f
    }()

    /// "3 h 12 min", "12 min", "45 s"; `nil` si no hay duración conocida.
    static func durationText(seconds: Double) -> String? {
        guard seconds > 0 else { return nil }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours >= 24 {
            let days = hours / 24
            return "\(days) \(days == 1 ? "día" : "días") \(hours % 24) h"
        }
        if hours > 0 { return "\(hours) h \(minutes) min" }
        if minutes > 0 { return "\(minutes) min" }
        return "\(total) s"
    }

    static func sizeText(bytes: Int64) -> String? {
        guard bytes > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func join(_ parts: [String?]) -> String {
        parts.compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: - Métricas

    static func totalDuration(of items: [LibraryItem]) -> Double {
        items.reduce(0) { $0 + ($1.metadata?.durationSeconds ?? 0) }
    }

    /// Suma de tamaños en disco de los archivos de origen. Se lee del
    /// sistema de archivos, así que las vistas lo llaman solo sobre lo
    /// que ya tienen en memoria (nunca en cada redibujo de una celda).
    /// PLAN-studio-rendimiento-2.md Fase 6 (ST-186): usa el tamaño que
    /// ya trae el catálogo y solo mide lo que todavía no lo tiene.
    static func totalSize(of items: [LibraryItem]) -> Int64 {
        items.reduce(0) { total, item in
            if let known = item.fileSizeBytes { return total + Int64(known) }
            return total + fileSize(atPath: item.sourceURL.path)
        }
    }

    /// Tamaños cacheados por ruta: la barra se recalcula en cada cambio
    /// de selección y una biblioteca grande no debe pagar miles de
    /// `stat` cada vez. Un archivo que cambia de tamaño sin cambiar de
    /// ruta (raro: los originales no se tocan) se refleja al reiniciar.
    private static let sizeCacheLock = NSLock()
    nonisolated(unsafe) private static var sizeCache: [String: Int64] = [:]

    static func fileSize(atPath path: String) -> Int64 {
        sizeCacheLock.lock()
        if let cached = sizeCache[path] { sizeCacheLock.unlock(); return cached }
        sizeCacheLock.unlock()
        let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0
        sizeCacheLock.lock()
        sizeCache[path] = size
        sizeCacheLock.unlock()
        return size
    }

    /// R2-4: los conteos de la barra de estado usan la MISMA
    /// homologación que las vistas. Si no, la barra diría "3 artistas"
    /// debajo de una lista con dos filas.
    static func artistCount(of items: [LibraryItem],
                            options: ArtistGroupingOptions = .default) -> Int {
        Set(items.map { LibraryGrouping.artistKey(of: $0, options: options) }.filter { !$0.isEmpty }).count
    }

    static func albumCount(of items: [LibraryItem],
                           options: ArtistGroupingOptions = .default) -> Int {
        Set(items.compactMap { item -> String? in
            let album = item.metadata?.album?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return album.isEmpty ? nil : LibraryGrouping.albumKey(of: item, options: options)
        }).count
    }

    // MARK: - Solo la selección (PLAN-studio-rendimiento.md Fase 1 punto 3)
    //
    // `music`/`videos`/`photos` de abajo recalculan SIEMPRE el total
    // (artistas/álbumes/duración/tamaño de TODOS los items) aunque solo
    // haga falta el texto de la selección -- exactamente lo que
    // `MediaSectionView.statusSummary` dispara en cada clic (diagnóstico
    // §0.2: "normaliza cadenas de todos los items y de todos los
    // seleccionados"). Estas tres funciones repiten SOLO la parte de
    // `selected` (barata: proporcional a lo seleccionado, no al
    // catálogo entero) para combinarla con un total ya cacheado --
    // ver `StatusSummaryModel`.

    static func musicSelectionText(selected: [LibraryItem], totalCount: Int,
                                   options: ArtistGroupingOptions = .default) -> String? {
        guard !selected.isEmpty else { return nil }
        return join([
            "\(formatted(selected.count)) de \(formatted(totalCount)) seleccionadas",
            count(artistCount(of: selected, options: options), "artista", "artistas"),
            count(albumCount(of: selected, options: options), "álbum", "álbumes"),
            durationText(seconds: totalDuration(of: selected)),
        ])
    }

    static func videoSelectionText(selected: [LibraryItem], totalCount: Int) -> String? {
        guard !selected.isEmpty else { return nil }
        return join([
            "\(formatted(selected.count)) de \(formatted(totalCount)) seleccionados",
            durationText(seconds: totalDuration(of: selected)),
            sizeText(bytes: totalSize(of: selected)),
        ])
    }

    static func photoSelectionText(selected: [LibraryItem], totalCount: Int) -> String? {
        guard !selected.isEmpty else { return nil }
        return join([
            "\(formatted(selected.count)) de \(formatted(totalCount)) seleccionadas",
            sizeText(bytes: totalSize(of: selected)),
        ])
    }

    // MARK: - Resúmenes por sección

    /// Canciones (tabla completa) y cualquier lista de pistas.
    static func music(items: [LibraryItem], selected: [LibraryItem],
                      options: ArtistGroupingOptions = .default) -> LibraryStatusSummary {
        let total = join([
            count(items.count, "canción", "canciones"),
            items.isEmpty ? nil : count(artistCount(of: items, options: options), "artista", "artistas"),
            items.isEmpty ? nil : count(albumCount(of: items, options: options), "álbum", "álbumes"),
        ])
        var selection: String?
        if !selected.isEmpty {
            selection = join([
                "\(formatted(selected.count)) de \(formatted(items.count)) seleccionadas",
                count(artistCount(of: selected, options: options), "artista", "artistas"),
                count(albumCount(of: selected, options: options), "álbum", "álbumes"),
                durationText(seconds: totalDuration(of: selected)),
            ])
        }
        return LibraryStatusSummary(total: total, selection: selection,
                                    trailing: join([durationText(seconds: totalDuration(of: items)),
                                                    sizeText(bytes: totalSize(of: items))]).nilIfEmpty)
    }

    // MARK: - Cuadrículas: el total y la selección, por separado
    //
    // PLAN-studio-rendimiento-2.md Fase 1 (ST-181): mismo corte que ya
    // tenían música/video/fotos más arriba. Las cinco cuadrículas
    // llamaban la función completa dentro del `body` (diagnóstico §0.1:
    // `flatMap` de los 12 000 ítems + una normalización de cadenas por
    // ítem, en cada clic). Ahora `GridStatusModel` memoiza el `total` --
    // que solo depende de lo visible -- y recalcula el texto de la
    // selección aparte, fuera del hilo principal cuando es caro. Las
    // funciones completas quedan como composición de las dos, para las
    // pruebas y para quien no necesite el corte.

    static func albumsTotal(_ albums: [AlbumGroup]) -> LibraryStatusSummary {
        let items = albums.flatMap(\.items)
        return LibraryStatusSummary(
            total: join([
                count(albums.count, "álbum", "álbumes"),
                count(artistCount(of: items), "artista", "artistas"),
                count(items.count, "canción", "canciones"),
            ]),
            trailing: durationText(seconds: totalDuration(of: items)))
    }

    static func albumsSelectionText(selected: [AlbumGroup], totalCount: Int) -> String? {
        guard !selected.isEmpty else { return nil }
        let selectedItems = selected.flatMap(\.items)
        return join([
            "\(formatted(selected.count)) de \(formatted(totalCount)) seleccionados",
            count(artistCount(of: selectedItems), "artista", "artistas"),
            count(selectedItems.count, "canción", "canciones"),
            durationText(seconds: totalDuration(of: selectedItems)),
        ])
    }

    static func albums(_ albums: [AlbumGroup], selected: [AlbumGroup]) -> LibraryStatusSummary {
        var summary = albumsTotal(albums)
        summary.selection = albumsSelectionText(selected: selected, totalCount: albums.count)
        return summary
    }

    static func artistsTotal(_ artists: [ArtistGroup]) -> LibraryStatusSummary {
        let items = artists.flatMap(\.items)
        return LibraryStatusSummary(
            total: join([
                count(artists.count, "artista", "artistas"),
                count(albumCount(of: items), "álbum", "álbumes"),
                count(items.count, "canción", "canciones"),
            ]),
            trailing: durationText(seconds: totalDuration(of: items)))
    }

    static func artistsSelectionText(selected: [ArtistGroup], totalCount: Int) -> String? {
        guard !selected.isEmpty else { return nil }
        let selectedItems = selected.flatMap(\.items)
        return join([
            "\(formatted(selected.count)) de \(formatted(totalCount)) seleccionados",
            count(albumCount(of: selectedItems), "álbum", "álbumes"),
            count(selectedItems.count, "canción", "canciones"),
            durationText(seconds: totalDuration(of: selectedItems)),
        ])
    }

    static func artists(_ artists: [ArtistGroup], selected: [ArtistGroup]) -> LibraryStatusSummary {
        var summary = artistsTotal(artists)
        summary.selection = artistsSelectionText(selected: selected, totalCount: artists.count)
        return summary
    }

    static func playlistsTotal(_ playlists: [Playlist]) -> LibraryStatusSummary {
        LibraryStatusSummary(total: join([
            count(playlists.count, "lista", "listas"),
            count(playlists.reduce(0) { $0 + $1.trackItemIDs.count }, "canción", "canciones"),
        ]))
    }

    static func playlistSelectionText(_ selected: Playlist?, musicItems: [LibraryItem]) -> String? {
        guard let selected else { return nil }
        let wanted = Set(selected.trackItemIDs)
        let tracks = musicItems.filter { wanted.contains($0.id) }
        return join([
            "«\(selected.name)»",
            count(tracks.count, "canción", "canciones"),
            count(artistCount(of: tracks), "artista", "artistas"),
            durationText(seconds: totalDuration(of: tracks)),
        ])
    }

    static func playlists(_ playlists: [Playlist], musicItems: [LibraryItem], selected: Playlist?) -> LibraryStatusSummary {
        var summary = playlistsTotal(playlists)
        summary.selection = playlistSelectionText(selected, musicItems: musicItems)
        return summary
    }

    /// Todos los videos / Videoclips (tabla plana). Sin `presetCategory`
    /// desglosa por categoría.
    static func videos(items: [LibraryItem], selected: [LibraryItem], breakdown: Bool) -> LibraryStatusSummary {
        var parts: [String?] = [count(items.count, "video", "videos")]
        if breakdown && !items.isEmpty {
            let movies = items.filter { $0.category == MediaCategory.movies.displayName }.count
            let episodes = items.filter { LibrarySync.isSeriesCategory($0.category) }.count
            let clips = items.filter { $0.category == MediaCategory.videos.displayName }.count
            if movies > 0 { parts.append(count(movies, "película", "películas")) }
            if episodes > 0 { parts.append(count(episodes, "episodio", "episodios")) }
            if clips > 0 { parts.append(count(clips, "videoclip", "videoclips")) }
        }
        var selection: String?
        if !selected.isEmpty {
            selection = join([
                "\(formatted(selected.count)) de \(formatted(items.count)) seleccionados",
                durationText(seconds: totalDuration(of: selected)),
                sizeText(bytes: totalSize(of: selected)),
            ])
        }
        return LibraryStatusSummary(total: join(parts), selection: selection,
                                    trailing: join([durationText(seconds: totalDuration(of: items)),
                                                    sizeText(bytes: totalSize(of: items))]).nilIfEmpty)
    }

    static func moviesTotal(_ movies: [VideoCollectionGroup]) -> LibraryStatusSummary {
        let items = movies.flatMap(\.items)
        return LibraryStatusSummary(
            total: count(movies.count, "película", "películas"),
            trailing: join([durationText(seconds: totalDuration(of: items)),
                            sizeText(bytes: totalSize(of: items))]).nilIfEmpty)
    }

    static func moviesSelectionText(selected: [VideoCollectionGroup], totalCount: Int) -> String? {
        guard !selected.isEmpty else { return nil }
        let selectedItems = selected.flatMap(\.items)
        return join([
            "\(formatted(selected.count)) de \(formatted(totalCount)) seleccionadas",
            durationText(seconds: totalDuration(of: selectedItems)),
            sizeText(bytes: totalSize(of: selectedItems)),
        ])
    }

    static func movies(_ movies: [VideoCollectionGroup], selected: [VideoCollectionGroup]) -> LibraryStatusSummary {
        var summary = moviesTotal(movies)
        summary.selection = moviesSelectionText(selected: selected, totalCount: movies.count)
        return summary
    }

    static func seriesTotal(_ series: [VideoCollectionGroup]) -> LibraryStatusSummary {
        let items = series.flatMap(\.items)
        let seasons = series.reduce(0) { $0 + $1.seasons.count }
        return LibraryStatusSummary(
            total: join([
                count(series.count, "serie", "series"),
                count(seasons, "temporada", "temporadas"),
                count(items.count, "episodio", "episodios"),
            ]),
            trailing: durationText(seconds: totalDuration(of: items)))
    }

    static func seriesSelectionText(selected: [VideoCollectionGroup], totalCount: Int) -> String? {
        guard !selected.isEmpty else { return nil }
        let selectedItems = selected.flatMap(\.items)
        return join([
            "\(formatted(selected.count)) de \(formatted(totalCount)) seleccionadas",
            count(selected.reduce(0) { $0 + $1.seasons.count }, "temporada", "temporadas"),
            count(selectedItems.count, "episodio", "episodios"),
            durationText(seconds: totalDuration(of: selectedItems)),
        ])
    }

    static func series(_ series: [VideoCollectionGroup], selected: [VideoCollectionGroup]) -> LibraryStatusSummary {
        var summary = seriesTotal(series)
        summary.selection = seriesSelectionText(selected: selected, totalCount: series.count)
        return summary
    }

    /// Una serie abierta: sus episodios y los seleccionados.
    static func episodesTotal(of show: VideoCollectionGroup) -> LibraryStatusSummary {
        LibraryStatusSummary(
            total: join([
                "«\(show.title)»",
                count(show.seasons.count, "temporada", "temporadas"),
                count(show.items.count, "episodio", "episodios"),
            ]),
            trailing: durationText(seconds: totalDuration(of: show.items)))
    }

    static func episodesSelectionText(selected: [LibraryItem], totalCount: Int) -> String? {
        guard !selected.isEmpty else { return nil }
        return join([
            "\(formatted(selected.count)) de \(formatted(totalCount)) seleccionados",
            durationText(seconds: totalDuration(of: selected)),
        ])
    }

    static func episodes(of show: VideoCollectionGroup, selected: [LibraryItem]) -> LibraryStatusSummary {
        var summary = episodesTotal(of: show)
        summary.selection = episodesSelectionText(selected: selected, totalCount: show.items.count)
        return summary
    }

    /// Todas las fotos (tabla plana). Con `breakdown` desglosa por
    /// colección (Fotos/Imágenes/IA).
    static func photos(items: [LibraryItem], selected: [LibraryItem], collections: [String]?) -> LibraryStatusSummary {
        var parts: [String?] = [count(items.count, "foto", "fotos")]
        if let collections, !items.isEmpty {
            for collection in collections {
                let n = items.filter { $0.category == collection }.count
                if n > 0 { parts.append("\(formatted(n)) en \(collection)") }
            }
        }
        let albumCount = Set(items.compactMap { $0.photoAlbum?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }).count
        if albumCount > 0 { parts.append(count(albumCount, "álbum", "álbumes")) }
        var selection: String?
        if !selected.isEmpty {
            selection = join([
                "\(formatted(selected.count)) de \(formatted(items.count)) seleccionadas",
                sizeText(bytes: totalSize(of: selected)),
            ])
        }
        return LibraryStatusSummary(total: join(parts), selection: selection,
                                    trailing: sizeText(bytes: totalSize(of: items)))
    }

    static func photoAlbumsTotal(_ albums: [PhotoAlbumGroup]) -> LibraryStatusSummary {
        let items = albums.flatMap(\.items)
        let named = albums.filter { !$0.isUnknown }.count
        let loose = albums.first { $0.isUnknown }?.count ?? 0
        return LibraryStatusSummary(
            total: join([
                count(named, "álbum", "álbumes"),
                count(items.count, "foto", "fotos"),
                loose > 0 ? "\(formatted(loose)) sin álbum" : nil,
            ]),
            trailing: sizeText(bytes: totalSize(of: items)))
    }

    static func photoAlbumsSelectionText(selected: [PhotoAlbumGroup], totalCount: Int) -> String? {
        guard !selected.isEmpty else { return nil }
        let selectedItems = selected.flatMap(\.items)
        return join([
            "\(formatted(selected.count)) de \(formatted(totalCount)) seleccionados",
            count(selectedItems.count, "foto", "fotos"),
            sizeText(bytes: totalSize(of: selectedItems)),
        ])
    }

    static func photoAlbums(_ albums: [PhotoAlbumGroup], selected: [PhotoAlbumGroup]) -> LibraryStatusSummary {
        var summary = photoAlbumsTotal(albums)
        summary.selection = photoAlbumsSelectionText(selected: selected, totalCount: albums.count)
        return summary
    }

    /// Un álbum de fotos abierto.
    static func photoAlbumTotal(_ album: PhotoAlbumGroup) -> LibraryStatusSummary {
        LibraryStatusSummary(
            total: join(["«\(album.title)»", count(album.count, "foto", "fotos")]),
            trailing: sizeText(bytes: totalSize(of: album.items)))
    }

    static func photoAlbum(_ album: PhotoAlbumGroup, selected: [LibraryItem]) -> LibraryStatusSummary {
        var summary = photoAlbumTotal(album)
        summary.selection = photoSelectionText(selected: selected, totalCount: album.count)
        return summary
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
