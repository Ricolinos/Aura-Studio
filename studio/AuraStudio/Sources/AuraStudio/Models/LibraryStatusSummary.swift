import Foundation
import SwiftUI

/// Lo que muestra la barra de estado al pie de cada sección de la
/// biblioteca (ST-063, encargo del dueño, 2026-08-23: "al estilo de la
/// barra de estado del Finder"): un resumen del total de la sección
/// (izquierda), opcionalmente lo que hay seleccionado (centro) y un
/// dato extra a la derecha (tamaño en disco, duración total...).
///
/// Cada vista arma el suyo con `LibraryStats` y lo publica hacia
/// `ContentView` con `.libraryStatus(_:)` (un `PreferenceKey`, así la
/// barra vive UNA sola vez en la raíz y las vistas no saben nada de
/// cómo se dibuja ni de si el usuario la ocultó desde el menú
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

struct LibraryStatusPreferenceKey: PreferenceKey {
    static let defaultValue: LibraryStatusSummary? = nil
    static func reduce(value: inout LibraryStatusSummary?, nextValue: () -> LibraryStatusSummary?) {
        if let next = nextValue() { value = next }
    }
}

extension View {
    /// Publica el resumen de esta sección para la barra de estado.
    func libraryStatus(_ summary: LibraryStatusSummary?) -> some View {
        preference(key: LibraryStatusPreferenceKey.self, value: summary)
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
    static func totalSize(of items: [LibraryItem]) -> Int64 {
        items.reduce(0) { $0 + fileSize(atPath: $1.sourceURL.path) }
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

    static func albums(_ albums: [AlbumGroup], selected: [AlbumGroup]) -> LibraryStatusSummary {
        let items = albums.flatMap(\.items)
        let total = join([
            count(albums.count, "álbum", "álbumes"),
            count(artistCount(of: items), "artista", "artistas"),
            count(items.count, "canción", "canciones"),
        ])
        var selection: String?
        if !selected.isEmpty {
            let selectedItems = selected.flatMap(\.items)
            selection = join([
                "\(formatted(selected.count)) de \(formatted(albums.count)) seleccionados",
                count(artistCount(of: selectedItems), "artista", "artistas"),
                count(selectedItems.count, "canción", "canciones"),
                durationText(seconds: totalDuration(of: selectedItems)),
            ])
        }
        return LibraryStatusSummary(total: total, selection: selection,
                                    trailing: durationText(seconds: totalDuration(of: items)))
    }

    static func artists(_ artists: [ArtistGroup], selected: [ArtistGroup]) -> LibraryStatusSummary {
        let items = artists.flatMap(\.items)
        let total = join([
            count(artists.count, "artista", "artistas"),
            count(albumCount(of: items), "álbum", "álbumes"),
            count(items.count, "canción", "canciones"),
        ])
        var selection: String?
        if !selected.isEmpty {
            let selectedItems = selected.flatMap(\.items)
            selection = join([
                "\(formatted(selected.count)) de \(formatted(artists.count)) seleccionados",
                count(albumCount(of: selectedItems), "álbum", "álbumes"),
                count(selectedItems.count, "canción", "canciones"),
                durationText(seconds: totalDuration(of: selectedItems)),
            ])
        }
        return LibraryStatusSummary(total: total, selection: selection,
                                    trailing: durationText(seconds: totalDuration(of: items)))
    }

    static func playlists(_ playlists: [Playlist], musicItems: [LibraryItem], selected: Playlist?) -> LibraryStatusSummary {
        let byID = Dictionary(uniqueKeysWithValues: musicItems.map { ($0.id, $0) })
        let allTrackIDs = playlists.flatMap(\.trackItemIDs)
        let total = join([
            count(playlists.count, "lista", "listas"),
            count(allTrackIDs.count, "canción", "canciones"),
        ])
        var selection: String?
        if let selected {
            let tracks = selected.trackItemIDs.compactMap { byID[$0] }
            selection = join([
                "«\(selected.name)»",
                count(tracks.count, "canción", "canciones"),
                count(artistCount(of: tracks), "artista", "artistas"),
                durationText(seconds: totalDuration(of: tracks)),
            ])
        }
        return LibraryStatusSummary(total: total, selection: selection)
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

    static func movies(_ movies: [VideoCollectionGroup], selected: [VideoCollectionGroup]) -> LibraryStatusSummary {
        let items = movies.flatMap(\.items)
        var selection: String?
        if !selected.isEmpty {
            let selectedItems = selected.flatMap(\.items)
            selection = join([
                "\(formatted(selected.count)) de \(formatted(movies.count)) seleccionadas",
                durationText(seconds: totalDuration(of: selectedItems)),
                sizeText(bytes: totalSize(of: selectedItems)),
            ])
        }
        return LibraryStatusSummary(total: count(movies.count, "película", "películas"), selection: selection,
                                    trailing: join([durationText(seconds: totalDuration(of: items)),
                                                    sizeText(bytes: totalSize(of: items))]).nilIfEmpty)
    }

    static func series(_ series: [VideoCollectionGroup], selected: [VideoCollectionGroup]) -> LibraryStatusSummary {
        let items = series.flatMap(\.items)
        let seasons = series.reduce(0) { $0 + $1.seasons.count }
        let total = join([
            count(series.count, "serie", "series"),
            count(seasons, "temporada", "temporadas"),
            count(items.count, "episodio", "episodios"),
        ])
        var selection: String?
        if !selected.isEmpty {
            let selectedItems = selected.flatMap(\.items)
            selection = join([
                "\(formatted(selected.count)) de \(formatted(series.count)) seleccionadas",
                count(selected.reduce(0) { $0 + $1.seasons.count }, "temporada", "temporadas"),
                count(selectedItems.count, "episodio", "episodios"),
                durationText(seconds: totalDuration(of: selectedItems)),
            ])
        }
        return LibraryStatusSummary(total: total, selection: selection,
                                    trailing: durationText(seconds: totalDuration(of: items)))
    }

    /// Una serie abierta: sus episodios y los seleccionados.
    static func episodes(of show: VideoCollectionGroup, selected: [LibraryItem]) -> LibraryStatusSummary {
        let total = join([
            "«\(show.title)»",
            count(show.seasons.count, "temporada", "temporadas"),
            count(show.items.count, "episodio", "episodios"),
        ])
        var selection: String?
        if !selected.isEmpty {
            selection = join([
                "\(formatted(selected.count)) de \(formatted(show.items.count)) seleccionados",
                durationText(seconds: totalDuration(of: selected)),
            ])
        }
        return LibraryStatusSummary(total: total, selection: selection,
                                    trailing: durationText(seconds: totalDuration(of: show.items)))
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

    static func photoAlbums(_ albums: [PhotoAlbumGroup], selected: [PhotoAlbumGroup]) -> LibraryStatusSummary {
        let items = albums.flatMap(\.items)
        let named = albums.filter { !$0.isUnknown }.count
        let loose = albums.first { $0.isUnknown }?.count ?? 0
        let total = join([
            count(named, "álbum", "álbumes"),
            count(items.count, "foto", "fotos"),
            loose > 0 ? "\(formatted(loose)) sin álbum" : nil,
        ])
        var selection: String?
        if !selected.isEmpty {
            let selectedItems = selected.flatMap(\.items)
            selection = join([
                "\(formatted(selected.count)) de \(formatted(albums.count)) seleccionados",
                count(selectedItems.count, "foto", "fotos"),
                sizeText(bytes: totalSize(of: selectedItems)),
            ])
        }
        return LibraryStatusSummary(total: total, selection: selection,
                                    trailing: sizeText(bytes: totalSize(of: items)))
    }

    /// Un álbum de fotos abierto.
    static func photoAlbum(_ album: PhotoAlbumGroup, selected: [LibraryItem]) -> LibraryStatusSummary {
        let total = join(["«\(album.title)»", count(album.count, "foto", "fotos")])
        var selection: String?
        if !selected.isEmpty {
            selection = join([
                "\(formatted(selected.count)) de \(formatted(album.count)) seleccionadas",
                sizeText(bytes: totalSize(of: selected)),
            ])
        }
        return LibraryStatusSummary(total: total, selection: selection,
                                    trailing: sizeText(bytes: totalSize(of: album.items)))
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
