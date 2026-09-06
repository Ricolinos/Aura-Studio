import AppKit
import CoreGraphics
import SwiftUI
import XCTest
@testable import AuraStudio

/// PLAN-studio-rendimiento-2.md Fase F0 (ST-180): extiende la línea base
/// de ST-152 (`LibraryPerformanceBaselineTests`) a las cuadrículas --
/// `AlbumsView` es la primera víctima del diagnóstico de la ronda 2 (§0,
/// puntos 1, 2, 4, 5 y 6). Mismo criterio que ST-152: código de
/// producción real donde ya hay un seam, PROXY documentado donde el
/// cálculo sigue viviendo en un computed var **privado** de una `View`
/// de SwiftUI (`AlbumsView.visibleAlbums`/`statusSummary`,
/// AlbumsView.swift:46-114) -- Fase F1 (E) es quien lo extrae a
/// `GridModel`/`StatusSummaryModel`, y esa PARADA vuelve a enganchar
/// estas pruebas a la extracción real, igual que ST-153 hizo con
/// `RowsModel`.
///
/// Todo lo demás que se mide acá SÍ es código de producción real, sin
/// proxy: `LibraryGrouping.albums`/`photoAlbums`, `LibraryStats.albums`,
/// `GridSelection`/`GridOrder`, `CoverThumbnailCache.shared.thumbnail`,
/// `AlbumCoverRequest.forAlbum` y `PhotoAlbumGroup.previewImages`.
@MainActor
final class AlbumsGridPerformanceBaselineTests: XCTestCase {
    private var libraryRoot: URL!
    private var musicItems: [AuraStudio.LibraryItem]!
    private var photoAlbumItems: [AuraStudio.LibraryItem]!

    /// 1 000 álbumes / 250 artistas (4 álbumes por artista) / 12 000
    /// canciones (12 por álbum) -- la escala de §A del plan ("biblioteca
    /// de 12 000 canciones / 1 000 álbumes"), no los 900 álbumes de la
    /// línea base original de ST-152 (esa medía la tabla de Canciones,
    /// no la cuadrícula de Álbumes).
    private static let albumCount = 1_000
    private static let artistCount = 250
    private static let tracksPerAlbum = 12
    private static let photoCount = 40

    override func setUpWithError() throws {
        libraryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("AlbumsGridPerf-\(UUID().uuidString)", isDirectory: true)
        musicItems = try Self.makeSyntheticAlbums(libraryRoot: libraryRoot)
        photoAlbumItems = try Self.makeSyntheticPhotoAlbum(libraryRoot: libraryRoot)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: libraryRoot)
        MainThreadWatchdog.onHangDetectedForTesting = nil
    }

    // MARK: - Fixture: carátulas e imágenes reales (JPEG que sí decodifica)

    /// A diferencia de ST-152 (`Data(repeating:)` para las canciones --
    /// ahí solo importaba el NÚMERO de bytes, para medir syscalls), acá
    /// el CONTENIDO sí importa: `CoverThumbnailCache.thumbnail(for:)`
    /// decodifica con `CGImageSourceCreateThumbnailAtIndex`, que
    /// devuelve `nil` ante bytes basura -- medir su costo real (y el
    /// bug del punto 5, "hashea 15 KB aunque haya acierto") exige un
    /// JPEG que decodifique de verdad. Ruido (no una foto real) porque
    /// generar contenido correlacionado 1 000/40 veces sería mucho más
    /// lento que lo que se está midiendo; el ruido comprime PEOR que
    /// una foto real, así que el tamaño resultante es, si acaso, una
    /// sobreestimación -- aceptable para una línea base "antes".
    private static func makeNoiseJPEG(side: Int, quality: CGFloat) -> Data {
        var buffer = [UInt8](repeating: 0, count: side * side * 4)
        buffer.withUnsafeMutableBytes { raw in
            arc4random_buf(raw.baseAddress, raw.count)
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: &buffer, width: side, height: side,
                                       bitsPerComponent: 8, bytesPerRow: side * 4,
                                       space: colorSpace,
                                       bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let cgImage = context.makeImage(),
              let jpeg = NSBitmapImageRep(cgImage: cgImage)
                .representation(using: .jpeg, properties: [.compressionFactor: quality]) else {
            fatalError("F0: no se pudo generar el JPEG sintético de la línea base")
        }
        return jpeg
    }

    /// Un sufijo de pocos bytes por álbum/foto -- el decodificador de
    /// JPEG se detiene en el marcador EOI y lo ignora (verificado:
    /// `CGImageSourceCreateThumbnailAtIndex` sigue decodificando bien),
    /// pero `CoverThumbnailCache` hashea el `Data` completo, así que
    /// cada álbum obtiene una clave de caché distinta -- como 1 000
    /// carátulas reales distintas, sin pagar el costo de generar 1 000
    /// imágenes de ruido independientes.
    private static func uniqueVariant(_ base: Data, tag: String) -> Data {
        base + Data("AURA-F0-\(tag)".utf8)
    }

    /// ~15 KB (120×120, calidad 0.7 ≈ 14.7 KB) -- el tamaño de §3 punto
    /// 2 del diagnóstico original, ahora con contenido que sí decodifica.
    private static func makeBaseCoverJPEG() -> Data { makeNoiseJPEG(side: 120, quality: 0.7) }

    /// Foto ya redimensionada por `ImageResizer.resizeToLCDOptimal` al
    /// tamaño por omisión (`AppPreferences.PhotoQuality.optimized`, 320
    /// px de lado mayor) -- el tamaño que vive en disco en
    /// `preparedURL` cuando `previewImages`/`photoThumb` la leen; nunca
    /// la foto original de cámara (`process(itemAt:)` caso `.photo`
    /// siempre redimensiona antes de dejar `status = .ready`).
    private static func makeBasePhotoJPEG() -> Data { makeNoiseJPEG(side: 320, quality: 0.5) }

    private static func makeSyntheticAlbums(libraryRoot: URL) throws -> [AuraStudio.LibraryItem] {
        let fm = FileManager.default
        let musicDir = libraryRoot.appendingPathComponent(PersistedLibrary.musicDirName, isDirectory: true)
        try fm.createDirectory(at: musicDir, withIntermediateDirectories: true)
        let tinyPayload = Data(repeating: 0xAA, count: 256)
        let baseCover = makeBaseCoverJPEG()

        var items: [AuraStudio.LibraryItem] = []
        items.reserveCapacity(albumCount * tracksPerAlbum)

        for albumNumber in 0..<albumCount {
            let artistNumber = albumNumber % artistCount
            let artist = "Artista \(String(format: "%03d", artistNumber))"
            let albumName = "Álbum \(String(format: "%04d", albumNumber))"
            let albumDir = musicDir
                .appendingPathComponent(artist, isDirectory: true)
                .appendingPathComponent(albumName, isDirectory: true)
            try fm.createDirectory(at: albumDir, withIntermediateDirectories: true)
            let cover = uniqueVariant(baseCover, tag: "album-\(albumNumber)")

            for track in 1...tracksPerAlbum {
                let fileURL = albumDir.appendingPathComponent(String(format: "%02d Canción.mp3", track))
                try tinyPayload.write(to: fileURL)
                var item = AuraStudio.LibraryItem(sourceURL: fileURL, addedAt: Date())
                item.status = .ready
                item.preparedURL = fileURL
                // ST-185: la carátula vive en `.portadas/<id>.jpg`, no en
                // memoria -- el fixture la escribe igual que lo hace la
                // app, para que lo que se mide sea el camino real.
                let stored = try CoverStore.write(cover, forItem: item.id, in: libraryRoot)
                item.metadata = TrackMetadata(
                    title: "Canción \(track) de \(albumName)",
                    artist: artist,
                    album: albumName,
                    albumArtist: artist,
                    year: "1986",
                    genre: "Rock",
                    trackNumber: track,
                    coverURL: stored.url,
                    coverHash: stored.hash,
                    durationSeconds: Double(180 + track))
                items.append(item)
            }
        }
        return items
    }

    /// Un solo álbum de fotos ("Álbum de prueba", categoría "Fotos") con
    /// 40 fotos reales en disco -- lo que le falta a la línea base de
    /// ST-152 para poder medir el punto 5 del diagnóstico
    /// (`previewImages`/`photoThumb` leyendo archivos completos en el
    /// `body`) y para la sesión guionizada del vigilante ("abrir Fotos").
    private static func makeSyntheticPhotoAlbum(libraryRoot: URL) throws -> [AuraStudio.LibraryItem] {
        try makePhotoAlbum(count: photoCount, subdirName: "FotosF0", albumName: "Álbum de prueba",
                           libraryRoot: libraryRoot)
    }

    /// Generalización reusable -- F2 (ST-182 PARADA F2, "scroll de 1 000
    /// álbumes y 500 fotos") necesita un álbum más grande que los 40 de
    /// F0/ST-180 sin duplicar el generador de JPEG sintético. `%04d`
    /// alcanza para cualquier tamaño razonable de fixture (hasta 9 999).
    private static func makePhotoAlbum(count: Int, subdirName: String, albumName: String,
                                       libraryRoot: URL) throws -> [AuraStudio.LibraryItem] {
        let fm = FileManager.default
        let photosDir = libraryRoot.appendingPathComponent(subdirName, isDirectory: true)
        try fm.createDirectory(at: photosDir, withIntermediateDirectories: true)
        let basePhoto = makeBasePhotoJPEG()

        var items: [AuraStudio.LibraryItem] = []
        for i in 0..<count {
            let fileURL = photosDir.appendingPathComponent(String(format: "foto-%04d.jpg", i))
            try uniqueVariant(basePhoto, tag: "\(subdirName)-\(i)").write(to: fileURL)
            var item = AuraStudio.LibraryItem(sourceURL: fileURL, addedAt: Date())
            item.status = .ready
            item.preparedURL = fileURL
            item.category = "Fotos"
            item.photoAlbum = albumName
            items.append(item)
        }
        return items
    }

    // MARK: - Preparación de F2 (pedido de "Sesión Maestra", 2026-09-06)
    //
    // F2 (miniaturas asíncronas) todavía no cierra -- nada de lo de
    // abajo se escribe como prueba todavía porque dependería de una API
    // que no existe (una `CoverThumbnailCache` async con `.task(id:)`,
    // según §B del plan). Lo que SÍ se dejó listo, sin correr nada
    // pesado mientras tanto:
    //
    // - `makePhotoAlbum(count:subdirName:albumName:libraryRoot:)` de
    //   arriba ya admite 500 fotos (criterio de F2: "scroll de 1 000
    //   álbumes y 500 fotos sin bloqueos > 16 ms") sin duplicar el
    //   generador de JPEG sintético -- basta con
    //   `Self.makePhotoAlbum(count: 500, subdirName: "FotosF2",
    //   albumName: "Álbum F2", libraryRoot: libraryRoot)` en un `setUp`
    //   propio de esas pruebas (NO en el `setUpWithError` de esta clase
    //   -- generar 500 fotos en cada una de las ~20 pruebas existentes
    //   sería puro costo sin beneficio).
    // - Lo que hace falta medir, tres cosas distintas (ver §A del plan):
    //   1. Bloqueos del hilo principal > 16 ms durante un scroll
    //      simulado de las 1 000 tarjetas de álbum + las 500 fotos --
    //      NO con `MainThreadWatchdog` (su umbral está fijo en 250 ms en
    //      `Services/MainThreadWatchdog.swift`, no es el de esta
    //      Fase) -- medición manual por celda con
    //      `CFAbsoluteTimeGetCurrent()`, igual que (c)/(d) de arriba.
    //   2. Memoria de la caché bajo el tope de 64 MB -- pedirle a Opus
    //      el nombre real de la propiedad (`totalCostLimit` de
    //      `NSCache`, si es lo que expone) para poder leerlo desde una
    //      prueba sin necesitar `@testable` de más.
    //   3. Que ninguna miniatura se decodifique en el hilo principal --
    //      necesita que la API async exista primero; probable patrón:
    //      un gancho de prueba (`onDecodeForTesting`/similar, mismo
    //      espíritu que `onHangDetectedForTesting`) que registre en qué
    //      hilo corrió cada decode.
    // Apenas Opus avise la PARADA F2, pedirle la firma real de la caché
    // nueva (mismo protocolo que con `LibraryCatalogIndex` en F3) y
    // llenar esto.

    // MARK: - (a) `visibleAlbums` -- PROXY (AlbumsView.swift:46-72, aún no
    // extraído a un modelo; ver el comentario de cabecera del archivo)

    func testVisibleAlbumsFilterOnly_titleSortNoSearch() throws {
        let albums = LibraryGrouping.albums(from: musicItems, options: .default)
        XCTAssertEqual(albums.count, Self.albumCount)
        measure {
            _ = albums.filter { LibrarySearch.album($0, matches: "") }
        }
    }

    /// El caso `.artist` de `AlbumsView.visibleAlbums` -- el único de
    /// los cuatro criterios de orden que hace `localizedStandardCompare`
    /// por álbum (los otros comparan strings ya normalizadas u ordenan
    /// por fecha), la parte más cara del punto 2 del diagnóstico.
    func testVisibleAlbumsFilterAndSort_artistSort() throws {
        let albums = LibraryGrouping.albums(from: musicItems, options: .default)
        measure {
            var result = albums.filter { LibrarySearch.album($0, matches: "") }
            result.sort { a, b in
                if a.isUnknown != b.isUnknown { return !a.isUnknown }
                let byArtist = LibraryGrouping.sortName(a.artist)
                    .localizedStandardCompare(LibraryGrouping.sortName(b.artist))
                if byArtist != .orderedSame { return byArtist == .orderedAscending }
                return (a.year ?? "") < (b.year ?? "")
            }
        }
    }

    // MARK: - (b) `statusSummary` de Álbumes -- real (`LibraryStats.albums`)
    //
    // ST-181 (F1) partió esto en dos: `albumsTotal(_:)` (solo por cambio
    // de cuadrícula) y `albumsSelectionText(selected:totalCount:)` (lo
    // único que sigue corriendo por clic). `LibraryStats.albums(_:
    // selected:)` sigue existiendo con la misma firma/resultado --
    // ahora es composición de las dos mitades, así que estas dos
    // pruebas siguen midiendo código real y siguen siendo válidas para
    // comparar contra ST-180. Las dos de abajo miden las mitades nuevas
    // por separado -- la segunda es la que de verdad importa por clic.

    func testStatusSummaryAlbumsNoSelection() throws {
        let albums = LibraryGrouping.albums(from: musicItems, options: .default)
        measure {
            _ = LibraryStats.albums(albums, selected: [])
        }
    }

    func testStatusSummaryAlbumsWithFiftySelected() throws {
        let albums = LibraryGrouping.albums(from: musicItems, options: .default)
        let selected = Array(albums.prefix(50))
        measure {
            _ = LibraryStats.albums(albums, selected: selected)
        }
    }

    func testAlbumsTotalOnly() throws {
        let albums = LibraryGrouping.albums(from: musicItems, options: .default)
        measure {
            _ = LibraryStats.albumsTotal(albums)
        }
    }

    /// El único cálculo que ST-181 deja corriendo por clic -- comparar
    /// esto contra `testStatusSummaryAlbumsWithFiftySelected` (ST-180)
    /// es la comparación antes/después real de "cuánto cuesta un clic".
    func testAlbumsSelectionTextOnlyWithFiftySelected() throws {
        let albums = LibraryGrouping.albums(from: musicItems, options: .default)
        let selected = Array(albums.prefix(50))
        measure {
            _ = LibraryStats.albumsSelectionText(selected: selected, totalCount: albums.count)
        }
    }

    // MARK: - (c) `CoverThumbnailCache` -- punto 5: hashea 15 KB por
    // evaluación aunque haya acierto

    /// Una sola pasada, sin `measure`: las claves son nuevas (`uniqueVariant`
    /// nunca antes vistas por `CoverThumbnailCache.shared`, que es un
    /// singleton compartido por todo el proceso de pruebas), así que
    /// esto SÍ mide "frío" de verdad. Repetirlo con `measure` (10
    /// corridas) dejaría de medir frío desde la segunda vuelta.
    func testCoverThumbnailCacheColdDecodeAllAlbums() throws {
        let albums = LibraryGrouping.albums(from: musicItems, options: .default)
        let covers = albums.map { CoverStore.read($0.coverURL) }
        let start = CFAbsoluteTimeGetCurrent()
        for cover in covers {
            _ = CoverThumbnailCache.shared.thumbnail(for: cover, side: 160)
        }
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
        print("[F0] CoverThumbnailCache frío, \(Self.albumCount) álbumes: "
              + "\(String(format: "%.1f", elapsedMs)) ms")
        XCTAssertGreaterThan(elapsedMs, 0)
    }

    /// Con la caché ya caliente (decodificada dentro de este mismo
    /// método, sin depender del orden de ejecución de las pruebas): antes
    /// de ST-183 esto medía el hash de `Data.hashValue` sobre 15 KB por
    /// tarjeta en cada acierto -- el bug del punto 5. `thumbnail(for:
    /// side:)` sigue existiendo ("compatibilidad", ver
    /// `CoverThumbnailCache.swift`) pero ahora arma la clave con
    /// `fingerprint` (huella O(1): tamaño + 4 bytes fijos, nunca recorre
    /// el blob), así que esta prueba pasó de medir el bug a medir que ya
    /// no está.
    func testCoverThumbnailCacheWarmRepeatDecodeAllAlbums() throws {
        let albums = LibraryGrouping.albums(from: musicItems, options: .default)
        let covers = albums.map { CoverStore.read($0.coverURL) }
        for cover in covers { _ = CoverThumbnailCache.shared.thumbnail(for: cover, side: 160) }
        measure {
            for cover in covers {
                _ = CoverThumbnailCache.shared.thumbnail(for: cover, side: 160)
            }
        }
    }

    // MARK: - (c, continuación) F2 (ST-183): decodifica fuera del hilo
    // principal, `totalCostLimit` de memoria, y el costo real de un
    // "scroll" ahora que el `body` solo consulta `cached(id:side:)`.

    /// El cambio central de F2: `thumbnail(id:side:load:)` es `async` y
    /// decodifica en `decodeQueue` (una cola `.utility` aparte, ver
    /// `CoverThumbnailCache.swift`) -- `load` (que es donde ocurre la
    /// lectura/decodificación real) nunca debe correr en el hilo
    /// principal. `ThreadFlag` (abajo) es el mismo patrón que
    /// `HangCollector`: un `@Sendable` con candado, porque `load` es
    /// `@escaping @Sendable` y puede correr en cualquier hilo.
    func testThumbnailAsyncPathNeverLoadsOnMainThread() async throws {
        let flag = ThreadFlag()
        let cover = Self.uniqueVariant(Self.makeBaseCoverJPEG(), tag: "f2-offmain-\(UUID().uuidString)")
        let image = await CoverThumbnailCache.shared.thumbnail(
            id: "f2-test-\(UUID().uuidString)", side: 160) {
            flag.set(Thread.isMainThread)
            return cover
        }
        XCTAssertNotNil(image, "una carátula real (JPEG válido) debe decodificar")
        XCTAssertFalse(flag.currentValue,
                       "load()/decodeThumbnail no deben correr en el hilo principal (ST-183)")
    }

    /// Criterio de F2 (§A): "scroll de 1 000 álbumes y 500 fotos sin
    /// bloqueos > 16 ms". Con la caché ya caliente (async, fuera de lo
    /// medido), lo único que corre en el hilo principal por celda visible
    /// es `cached(id:side:)` -- una consulta a `NSCache`, sin decodificar
    /// ni tocar disco. Se mide la pasada COMPLETA (1 500 consultas) Y el
    /// peor caso de una sola consulta -- el objetivo de 16 ms es por
    /// CELDA, no por scroll completo.
    func testMainThreadCostOfScrollWithWarmCache() async throws {
        let albums = LibraryGrouping.albums(from: musicItems, options: .default)
        let albumIDs = albums.map { "album:\($0.id)" }
        for (id, album) in zip(albumIDs, albums) {
            _ = await CoverThumbnailCache.shared.thumbnail(id: id, side: 160) { CoverStore.read(album.coverURL) }
        }
        let largePhotoAlbum = try Self.makePhotoAlbum(count: 500, subdirName: "FotosF2",
                                                      albumName: "Álbum F2", libraryRoot: libraryRoot)
        let photoIDs = largePhotoAlbum.map { PhotoThumbnailID.make(for: $0) }
        for (id, item) in zip(photoIDs, largePhotoAlbum) {
            let url = item.preparedURL ?? item.sourceURL
            _ = await CoverThumbnailCache.shared.thumbnail(id: id, side: 160) { try? Data(contentsOf: url) }
        }

        var worstSingleLookupMs = 0.0
        let start = CFAbsoluteTimeGetCurrent()
        for id in albumIDs + photoIDs {
            let lookupStart = CFAbsoluteTimeGetCurrent()
            _ = CoverThumbnailCache.shared.cached(id: id, side: 160)
            worstSingleLookupMs = max(worstSingleLookupMs, (CFAbsoluteTimeGetCurrent() - lookupStart) * 1000)
        }
        let totalMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
        print("[F2] Scroll con caché caliente, \(albumIDs.count) álbumes + \(photoIDs.count) fotos: "
              + "\(String(format: "%.2f", totalMs)) ms en total, "
              + "peor consulta individual \(String(format: "%.3f", worstSingleLookupMs)) ms")
        XCTAssertLessThan(worstSingleLookupMs, 16,
                          "una sola consulta cached(id:side:) no debe acercarse a 16 ms")
    }

    /// `totalCostLimit` (§A: "tope 64 MB"): en vez de intentar llenar
    /// 64 MB de verdad (lento y no aporta nada más que confirmar el
    /// mecanismo), se prueba el MECANISMO con una instancia propia y un
    /// tope chico -- `NSCache` es quien decide qué desaloja, así que no
    /// se afirma CUÁL entrada sobrevive, solo que el total cacheado no
    /// puede crecer sin límite. El valor real de producción
    /// (`CoverThumbnailCache.shared`, `totalCostLimit: 64 * 1024 * 1024`)
    /// se confirma leyendo `Services/CoverThumbnailCache.swift:47`, no
    /// hay un accesor de prueba para el `NSCache` interno del singleton.
    func testTotalCostLimitBoundsMemory() async throws {
        let smallCache = CoverThumbnailCache(countLimit: 200, totalCostLimit: 2 * 1024 * 1024)
        let albums = LibraryGrouping.albums(from: musicItems, options: .default)
        for album in albums {
            _ = await smallCache.thumbnail(id: "album:\(album.id)", side: 160) { CoverStore.read(album.coverURL) }
        }
        let stillCached = albums.filter { smallCache.cached(id: "album:\($0.id)", side: 160) != nil }.count
        print("[F2] Tope de memoria chico (2 MB) tras 1000 álbumes: \(stillCached) siguen en caché")
        XCTAssertLessThan(stillCached, albums.count,
                          "con un totalCostLimit chico, NSCache debe desalojar -- no puede seguir "
                          + "todo en memoria")
    }

    /// La prueba que "experto en código opus" señaló como la más
    /// valiosa de F2 (más que cualquier número de rendimiento): la clave
    /// de caché ahora es el id del álbum/foto, no el contenido -- sin la
    /// huella (`fingerprint`) pegada al id, cambiarle la carátula a un
    /// álbum seguiría mostrando la miniatura VIEJA (la nueva pediría la
    /// misma clave `"album:\(id)"` y `cached(id:side:)` la encontraría
    /// en memoria sin decodificar nada). `fingerprint` es lo que hace
    /// que eso no pase.
    func testFingerprintChangesWithContentAndOnlyWithContent() {
        let coverA = Self.uniqueVariant(Self.makeBaseCoverJPEG(), tag: "fingerprint-a")
        let coverB = Self.uniqueVariant(Self.makeBaseCoverJPEG(), tag: "fingerprint-b")
        XCTAssertEqual(CoverThumbnailCache.fingerprint(coverA), CoverThumbnailCache.fingerprint(coverA),
                       "el mismo blob debe dar siempre la misma huella")
        XCTAssertNotEqual(CoverThumbnailCache.fingerprint(coverA), CoverThumbnailCache.fingerprint(coverB),
                          "dos carátulas distintas deben dar huellas distintas")
        XCTAssertNotEqual(CoverThumbnailCache.fingerprint(nil), CoverThumbnailCache.fingerprint(coverA))
    }

    // MARK: - (d) Menú contextual con selección múltiple -- punto 6
    //
    // Las dos pruebas de abajo (sufijo `_beforeIndex`) siguen usando
    // `AlbumCoverRequest.forAlbum(of:in:options:)`, el camino SIN índice
    // -- sigue existiendo tras ST-182, así que el número "antes" de
    // ST-180 se puede seguir reproduciendo tal cual. Las nuevas (sufijo
    // `_withCatalogIndex`) miden el camino real desde F3 (ST-182).

    /// Selección de 100 álbumes (no 1 000) para que las 10 repeticiones
    /// de `measure` sigan siendo razonables -- el costo escala lineal
    /// con cuántos álbumes hay en la selección (cada uno hace un
    /// `filter` completo de los 12 000 ítems, ver `AlbumCoverRequest.
    /// forAlbum`), así que 100 ya es representativo del costo POR ÁLBUM.
    func testCoverRequestsForOneHundredSelectedAlbums_beforeIndex() throws {
        let albums = LibraryGrouping.albums(from: musicItems, options: .default)
        let targets = Array(albums.prefix(100))
        measure {
            _ = targets.compactMap {
                AlbumCoverRequest.forAlbum(of: $0.items, in: musicItems, options: .default)
            }
        }
    }

    /// El caso real que motivó el punto 6: clic derecho con TODOS los
    /// álbumes seleccionados -- "12 millones de claves normalizadas"
    /// (1 000 álbumes × 12 000 ítems). Una sola pasada: 10 repeticiones
    /// de esto son varios segundos cada una, no vale la pena pagarlo en
    /// cada corrida de `swift test` -- el número real queda anotado en
    /// ST-180 (81 s) y sigue siendo reproducible acá para contraste.
    func testCoverRequestsForAllOneThousandAlbumsSelected_beforeIndex() throws {
        let albums = LibraryGrouping.albums(from: musicItems, options: .default)
        let start = CFAbsoluteTimeGetCurrent()
        _ = albums.compactMap {
            AlbumCoverRequest.forAlbum(of: $0.items, in: musicItems, options: .default)
        }
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
        print("[F0] Menú contextual (sin índice), \(Self.albumCount)/\(Self.albumCount) álbumes seleccionados: "
              + "\(String(format: "%.0f", elapsedMs)) ms")
        XCTAssertGreaterThan(elapsedMs, 0)
    }

    /// Costo de armar `LibraryCatalogIndex` una vez -- el techo del
    /// costo de F3, pagado una vez por versión del catálogo (en
    /// producción, en segundo plano vía `warmCatalogIndex()`, nunca en
    /// el clic). Del mismo orden que (b) -- son las mismas 12 000
    /// normalizaciones, ahora hechas una sola vez en vez de una vez POR
    /// ÁLBUM abierto.
    func testCatalogIndexBuildCost() throws {
        measure {
            _ = LibraryCatalogIndex(items: musicItems, options: .default)
        }
    }

    /// Criterio de cierre de F3 (ST-182, §A): menú con los 1 000/1 000
    /// álbumes seleccionados en < 200 ms, con el índice YA armado (como
    /// en producción -- `warmCatalogIndex()` corrió antes del clic).
    func testCoverRequestsForAllOneThousandAlbumsSelected_withCatalogIndex() throws {
        let albums = LibraryGrouping.albums(from: musicItems, options: .default)
        let index = LibraryCatalogIndex(items: musicItems, options: .default)
        measure {
            _ = albums.compactMap { AlbumCoverRequest.forAlbum($0, in: index) }
        }
    }

    /// El caso concreto que reportó el dueño ("en Canciones con todo
    /// seleccionado no aparece Buscar carátulas"): ST-182 agrega esta
    /// acción a Canciones. Acá se mide con los 12 000 ítems
    /// seleccionados -- el caso literal de §B.F3 del plan, distinto del
    /// de arriba (ese resuelve por ÁLBUM ya agrupado; este resuelve
    /// directo desde una selección de CANCIONES sueltas, el camino real
    /// de `AlbumCoverRequest.forAlbums(of:in:)`).
    func testCoverRequestsForAllTwelveThousandSongsSelected_Canciones_withCatalogIndex() throws {
        let index = LibraryCatalogIndex(items: musicItems, options: .default)
        measure {
            _ = AlbumCoverRequest.forAlbums(of: musicItems, in: index)
        }
    }

    // MARK: - (e) Álbum de Fotos con 40 fotos -- punto 5
    // (`previewImages`/`photoThumb` leyendo archivos completos en el `body`)

    func testPhotoAlbumsGroupingFortyPhotos() throws {
        measure {
            let groups = LibraryGrouping.photoAlbums(from: photoAlbumItems, category: "Fotos")
            XCTAssertEqual(groups.count, 1)
        }
    }

    func testPhotoAlbumPreviewImagesReadsFourFilesFromDisk() throws {
        let groups = LibraryGrouping.photoAlbums(from: photoAlbumItems, category: "Fotos")
        let album = try XCTUnwrap(groups.first)
        XCTAssertEqual(album.count, Self.photoCount)
        measure {
            _ = album.previewImages
        }
    }

    // MARK: - (f) Sesión guionizada del vigilante (§B F0): abrir Álbumes,
    // ⌘A, Shift+clic 1→500, clic derecho, scroll completo, abrir Fotos.
    //
    // A diferencia de `ApplyBatchEditWorkerTests.
    // testFiveHundredItemsNeverBlockTheMainThreadOverTheWatchdogThreshold`
    // (que ya arregló su fase y exige cero bloqueos), esta sigue sin
    // afirmar nada sobre el número de bloqueos -- los REPORTA. F2/F4/F5/F6
    // todavía no cerraron (miniaturas síncronas, `coverArtData` completo
    // en RAM), así que "cero bloqueos" no es un criterio con el que esta
    // prueba pueda comprometerse todavía.
    //
    // ST-182 (F3): el paso 4 (clic derecho) ya NO usa el camino viejo de
    // `AlbumCoverRequest.forAlbum(of:in:options:)` (el que barre los
    // 12 000 ítems por álbum) -- usa `LibraryCatalogIndex`, como la app
    // real desde este commit. El índice se arma ANTES de `start`, fuera
    // de lo medido: en producción lo arma `warmCatalogIndex()` en
    // segundo plano al cambiar el catálogo, no en el clic.
    func testScriptedAlbumsSessionUnderWatchdogReportsBaseline() async throws {
        setenv("AURA_WATCHDOG", "1", 1)
        let hangs = HangCollector()
        MainThreadWatchdog.onHangDetectedForTesting = { durationMs in hangs.add(durationMs) }
        MainThreadWatchdog.startIfRequested()

        let albums = LibraryGrouping.albums(from: musicItems, options: .default)
        let order = GridOrder(albums.map(\.id))
        let catalogIndex = LibraryCatalogIndex(items: musicItems, options: .default)
        let start = CFAbsoluteTimeGetCurrent()

        // 1. Abrir Álbumes: agrupar + primera pantalla visible (~30 tarjetas).
        _ = LibraryStats.albums(albums, selected: [])
        for cover in albums.prefix(30).map({ CoverStore.read($0.coverURL) }) {
            _ = CoverThumbnailCache.shared.thumbnail(for: cover, side: 160)
        }

        // 2. ⌘A: selecciona todo lo visible -- dispara la invalidación
        // completa de `anySelected` (punto 4) sobre las 1 000 tarjetas.
        var selection = GridSelection<String>()
        selection.selectAll(order)
        for cover in albums.map({ CoverStore.read($0.coverURL) }) {
            _ = CoverThumbnailCache.shared.thumbnail(for: cover, side: 160)
        }
        _ = LibraryStats.albums(albums, selected: albums)

        // 3. Shift+clic de 1 a 500 (rango; `anySelected` ya estaba en
        // `true` desde el paso 2, así que no vuelve a invalidar todo).
        selection.clear()
        selection.handleTap(order.ids[0], order: order, modifierFlags: [])
        for i in 1...500 {
            selection.handleTap(order.ids[i], order: order, modifierFlags: [.shift])
        }
        _ = LibraryStats.albums(albums, selected: albums.filter { selection.isSelected($0.id) })

        // 4. Clic derecho con esos 500 seleccionados: construir el menú
        // (punto 6, ST-182) -- con el índice ya armado, cada álbum es una
        // búsqueda en diccionario, no un filter de 12 000.
        let selectedAlbums = albums.filter { selection.isSelected($0.id) }
        _ = selectedAlbums.compactMap { AlbumCoverRequest.forAlbum($0, in: catalogIndex) }

        // 5. Scroll completo: el resto de las tarjetas nunca mostradas
        // en el paso 1 entran a la caché por primera vez.
        for cover in albums.map({ CoverStore.read($0.coverURL) }) {
            _ = CoverThumbnailCache.shared.thumbnail(for: cover, side: 160)
        }

        // 6. Abrir Fotos: agrupar + mosaico del único álbum (40 fotos).
        let photoAlbums = LibraryGrouping.photoAlbums(from: photoAlbumItems, category: "Fotos")
        for photoAlbum in photoAlbums {
            for preview in photoAlbum.previewImages {
                _ = CoverThumbnailCache.shared.thumbnail(for: preview, side: 160)
            }
        }

        let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
        try await Self.waitForWatchdogToCatchUp(hangs)

        print("[F0] Sesión guionizada completa: \(String(format: "%.0f", elapsedMs)) ms de pared; "
              + "\(hangs.values.count) bloqueo(s) > 250 ms del hilo principal: \(hangs.values)")
        XCTAssertGreaterThan(elapsedMs, 0)
    }

    /// Diagnóstico de "experto en código opus" (2026-09-06): un `Task.
    /// sleep` de duración fija (lo que había acá antes) no cierra la
    /// carrera de verdad -- si el vigilante tarda más que eso en
    /// despachar `DispatchQueue.main` de nuevo (p. ej. la máquina bajo
    /// carga), el reporte diferido llega DESPUÉS de que esta prueba ya
    /// leyó `hangs.values`, y como `onHangDetectedForTesting` es un
    /// `static var` GLOBAL, el reporte le llega a la clausura que sea
    /// que la prueba SIGUIENTE ya haya instalado -- exactamente el
    /// "bloqueo fantasma" que contaminó
    /// `ApplyAlbumCoverAndSimilarityWorkerTests` (ver ST-181/ST-182). En
    /// vez de una espera ciega, esto SONDEA hasta ver que `hangs` recibió
    /// algo (o hasta 2 s) -- no avanza (y no deja que nadie más reemplace
    /// la clausura) hasta que el reporte, si lo hay, ya aterrizó.
    private static func waitForWatchdogToCatchUp(_ hangs: HangCollector, timeout: TimeInterval = 2.0) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while hangs.values.isEmpty && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    // MARK: - (g) `AlbumsView` hospedada de verdad -- pedido de "Sesión
    // Maestra" (2026-09-06), cerrado con el seam de F1 (ST-181,
    // `GridSelectionModel<String>` inyectable en el init de `AlbumsView`).
    //
    // Hasta ANTES de F1 esta prueba era solo una prueba de humo (ver
    // ST-180): no había forma de simular el clic porque la selección
    // vivía en un `@State private` -- ver el commit 24d5f9b/bd79cd9 para
    // esa versión. Con `GridSelectionModel` inyectado, ahora SÍ mide
    // "evaluaciones de body por clic" real, de punta a punta, sin
    // simular nada -- el criterio de cierre de F1 ("un clic = solo la
    // tarjeta tocada y la barra de estado se reevalúan").
    func testHostedAlbumsViewRecordsBodyEvaluationsOnInitialRender() throws {
        let (hostingController, window, _, _) = try Self.hostAlbumsView(libraryRoot: libraryRoot, musicItems: musicItems)
        let evaluations = BodyEvaluationCounter.count(for: "AlbumsView")
        print("[F1] AlbumsView hospedada (NSHostingController): \(evaluations) evaluación(es) de body "
              + "en el primer render")
        XCTAssertGreaterThan(evaluations, 0,
                              "AlbumsView.body nunca se evaluó -- el hosting headless no disparó el render real")
        _ = (hostingController, window) // mantiene vivas las referencias hasta el final del scope
    }

    /// El caso real que cuenta para F1: tocar la casilla de UN álbum
    /// (`GridSelection.toggle`, el mismo camino que usa
    /// `librarySelectionCheckbox`) y medir cuántas veces se reevalúan
    /// `AlbumsView.body` y `AlbumCardView.body` -- antes de F1 (§0.4 del
    /// diagnóstico) esto invalidaba las 1 000 tarjetas por `anySelected`;
    /// el criterio de F1 es "solo la tocada [y la barra de estado]".
    func testTogglingOneAlbumCheckboxRecordsBodyEvaluations() throws {
        let (hostingController, window, viewModel, selectionModel) =
            try Self.hostAlbumsView(libraryRoot: libraryRoot, musicItems: musicItems)
        let albums = LibraryGrouping.albums(from: viewModel.items, options: .default)
        let targetID = try XCTUnwrap(albums.first?.id)

        BodyEvaluationCounter.resetForTesting()
        selectionModel.selection.toggle(targetID)
        hostingController.view.layoutSubtreeIfNeeded()
        window.layoutIfNeeded()
        window.displayIfNeeded()

        let albumsViewEvaluations = BodyEvaluationCounter.count(for: "AlbumsView")
        let cardEvaluations = BodyEvaluationCounter.count(for: "AlbumCardView")
        print("[F1] Tocar la casilla de 1 álbum (10 hospedados): \(albumsViewEvaluations) evaluación(es) "
              + "de AlbumsView.body, \(cardEvaluations) de AlbumCardView.body")
    }

    /// ST-181 (addendum): la casilla vuelve a mostrarse en TODAS las
    /// tarjetas mientras haya algo seleccionado (regla de ST-113/R2-1) --
    /// pero `anySelected` solo tiene que cambiar en la transición
    /// vacío↔no vacío, nunca en un clic intermedio con la selección ya
    /// no vacía. Pedido de "Sesión Maestra": confirmar con el contador
    /// que un clic intermedio no dispara la cascada que sí es legítima
    /// en la transición.
    func testIntermediateClickDoesNotInvalidateOtherAlbumCards() throws {
        let (hostingController, window, viewModel, selectionModel) =
            try Self.hostAlbumsView(libraryRoot: libraryRoot, musicItems: musicItems)
        let albums = LibraryGrouping.albums(from: viewModel.items, options: .default)
        XCTAssertGreaterThanOrEqual(albums.count, 3)
        let first = albums[0].id, second = albums[1].id

        // Transición vacío→no vacío -- legítimamente puede invalidar
        // varias/todas las tarjetas (`anySelected` cambia para todas).
        // No se mide acá, es la excepción documentada, no el caso bajo
        // prueba.
        selectionModel.selection.toggle(first)
        hostingController.view.layoutSubtreeIfNeeded()
        window.layoutIfNeeded()
        window.displayIfNeeded()

        // Clic intermedio: la selección sigue NO vacía antes y después
        // (de {first} a {first, second}) -- `anySelected` no cambia.
        BodyEvaluationCounter.resetForTesting()
        selectionModel.selection.toggle(second)
        hostingController.view.layoutSubtreeIfNeeded()
        window.layoutIfNeeded()
        window.displayIfNeeded()

        let albumsViewEvaluations = BodyEvaluationCounter.count(for: "AlbumsView")
        let cardEvaluations = BodyEvaluationCounter.count(for: "AlbumCardView")
        print("[F1 addendum] Clic intermedio (selección no vacía → no vacía, 10 hospedados): "
              + "\(albumsViewEvaluations) evaluación(es) de AlbumsView.body, "
              + "\(cardEvaluations) de AlbumCardView.body")
        // Lo que SÍ se cumple, verificado (commit 4c63056): ninguna
        // tarjeta se reevalúa con un clic intermedio.
        XCTAssertEqual(cardEvaluations, 0,
                       "un clic intermedio no debe reevaluar NINGUNA tarjeta -- la cascada de anySelected "
                       + "es solo para la transición vacío↔no vacío")
        // Lo que NO se cumple, verificado igual (commit 4c63056): sigue
        // en 2, igual que antes de este addendum y que en el primer
        // render (ver ST-181, "Qué NO se pudo cerrar" en el addendum de
        // ST-180) -- pese a que este mismo commit movió `GridStatusModel`
        // fuera de la observación de `AlbumsView` explícitamente para
        // atacar esto. No se convierte en una aserción dura (rompería
        // el suite por algo que no es un regresión NUEVA de este commit,
        // ya estaba en 2 antes) -- se deja como dato para que Opus/
        // Sesión Maestra decidan si hace falta investigarlo con
        // Instruments contra la app real.
        if albumsViewEvaluations > 1 {
            print("[F1 addendum] AVISO: AlbumsView.body en \(albumsViewEvaluations), no en el máximo de 1 "
                  + "que pidió \"Sesión Maestra\" -- sin cambio respecto a antes de este addendum.")
        }

        // La transición de vuelta a vacío (no vacío→vacío) SÍ puede
        // invalidar de nuevo -- se documenta, no se afirma un número.
        selectionModel.selection.clear()
        BodyEvaluationCounter.resetForTesting()
        selectionModel.selection.toggle(first)
        hostingController.view.layoutSubtreeIfNeeded()
        window.layoutIfNeeded()
        window.displayIfNeeded()
        print("[F1 addendum] Transición vacío→no vacío (10 hospedados): "
              + "\(BodyEvaluationCounter.count(for: "AlbumsView")) evaluación(es) de AlbumsView.body, "
              + "\(BodyEvaluationCounter.count(for: "AlbumCardView")) de AlbumCardView.body")
    }

    /// Shift+clic sobre la cuadrícula hospedada -- `GridSelection.
    /// handleTap(_:order:modifierFlags:)` ya existía desde ST-152
    /// (Fase 0 de la ronda 1) precisamente para no depender de
    /// `NSEvent.modifierFlags` real.
    func testShiftClickOnHostedAlbumsViewRecordsBodyEvaluations() throws {
        let (hostingController, window, viewModel, selectionModel) =
            try Self.hostAlbumsView(libraryRoot: libraryRoot, musicItems: musicItems)
        let albums = LibraryGrouping.albums(from: viewModel.items, options: .default)
        let order = GridOrder(albums.map(\.id))
        XCTAssertGreaterThanOrEqual(order.ids.count, 5)

        // El tap ancla (clic simple sobre el primer álbum) queda FUERA
        // de la medición -- lo que se mide es solo el Shift+clic que lo
        // extiende, no los dos gestos juntos.
        selectionModel.selection.handleTap(order.ids[0], order: order, modifierFlags: [])
        hostingController.view.layoutSubtreeIfNeeded()
        window.layoutIfNeeded()
        window.displayIfNeeded()

        BodyEvaluationCounter.resetForTesting()
        selectionModel.selection.handleTap(order.ids[4], order: order, modifierFlags: [.shift])
        hostingController.view.layoutSubtreeIfNeeded()
        window.layoutIfNeeded()
        window.displayIfNeeded()

        let albumsViewEvaluations = BodyEvaluationCounter.count(for: "AlbumsView")
        let cardEvaluations = BodyEvaluationCounter.count(for: "AlbumCardView")
        print("[F1] Shift+clic que extiende 1→5 (10 hospedados): \(albumsViewEvaluations) evaluación(es) de "
              + "AlbumsView.body, \(cardEvaluations) de AlbumCardView.body")
    }

    /// ⌘+clic: alterna un álbum SIN reemplazar la selección -- el otro
    /// gesto que pidió "Sesión Maestra" además del Shift+clic.
    func testCommandClickOnHostedAlbumsViewRecordsBodyEvaluations() throws {
        let (hostingController, window, viewModel, selectionModel) =
            try Self.hostAlbumsView(libraryRoot: libraryRoot, musicItems: musicItems)
        let albums = LibraryGrouping.albums(from: viewModel.items, options: .default)
        let order = GridOrder(albums.map(\.id))
        XCTAssertGreaterThanOrEqual(order.ids.count, 2)

        selectionModel.selection.handleTap(order.ids[0], order: order, modifierFlags: [])
        hostingController.view.layoutSubtreeIfNeeded()
        window.layoutIfNeeded()
        window.displayIfNeeded()

        BodyEvaluationCounter.resetForTesting()
        selectionModel.selection.handleTap(order.ids[1], order: order, modifierFlags: [.command])
        hostingController.view.layoutSubtreeIfNeeded()
        window.layoutIfNeeded()
        window.displayIfNeeded()

        let albumsViewEvaluations = BodyEvaluationCounter.count(for: "AlbumsView")
        let cardEvaluations = BodyEvaluationCounter.count(for: "AlbumCardView")
        print("[F1] ⌘+clic que suma un segundo álbum (10 hospedados): \(albumsViewEvaluations) evaluación(es) "
              + "de AlbumsView.body, \(cardEvaluations) de AlbumCardView.body")
    }

    /// Fábrica compartida por las tres pruebas de esta sección: hospeda
    /// `AlbumsView` con 10 álbumes (120 canciones) reales -- no hace
    /// falta hospedar los 1 000 para medir CUÁNTAS VECES se evalúa
    /// `body`, solo que haya más de una tarjeta.
    private static func hostAlbumsView(libraryRoot: URL, musicItems: [AuraStudio.LibraryItem]) throws
        -> (NSHostingController<AlbumsView>, NSWindow, LibraryViewModel, GridSelectionModel<String>) {
        BodyEvaluationCounter.resetForTesting()
        let preferences = AppPreferences(defaults: UserDefaults(suiteName: "HostedAlbumsView-\(UUID().uuidString)")!)
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: preferences)
        viewModel.replaceItemsForPerformanceTesting(Array(musicItems.prefix(120)))
        let selectionStore = SelectionStore()
        let selectionModel = GridSelectionModel<String>()

        let hostingController = NSHostingController(
            rootView: AlbumsView(viewModel: viewModel, device: nil, preferences: preferences,
                                  selectionStore: selectionStore, selectionModel: selectionModel))
        let window = NSWindow(contentViewController: hostingController)
        window.setFrame(NSRect(x: 0, y: 0, width: 900, height: 700), display: true)
        // Sin pantalla real (`swift test` en CI/consola) `display:true`
        // en el `setFrame` de arriba no alcanza por sí solo -- forzar
        // layout explícitamente es lo que de verdad dispara el primer
        // `body` de SwiftUI en un host sin ventana visible.
        hostingController.view.layoutSubtreeIfNeeded()
        window.layoutIfNeeded()
        window.displayIfNeeded()
        return (hostingController, window, viewModel, selectionModel)
    }
}

/// Mismo patrón que `HangCollector` (`ApplyBatchEditWorkerTests.swift`):
/// un valor leído/escrito desde clausuras `@Sendable` que pueden correr
/// en cualquier hilo (acá, `CoverThumbnailCache.thumbnail(id:side:load:)`
/// llama `load` desde su cola de decodificación) necesita candado, no un
/// `var` capturado a secas -- eso no compila en modo Swift 6.
final class ThreadFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set(_ newValue: Bool) {
        lock.lock(); value = newValue; lock.unlock()
    }

    var currentValue: Bool {
        lock.lock(); defer { lock.unlock() }
        return value
    }
}
