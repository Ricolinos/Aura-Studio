import XCTest
@testable import AuraStudio

/// ST-104: "Buscar carátulas del álbum" -- varias tapas para elegir, no
/// una impuesta. Red simulada con `MockURLProtocol`; nunca sale a
/// internet.
final class AlbumCoverSearchTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    private func mockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func http(_ url: URL, _ status: Int = 200) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    /// El buscador con las tres fuentes apuntando al mock y sin espera
    /// de rate limit (el limite real de MusicBrainz es 1 req/s: sin esto
    /// la suite tardaria segundos por prueba).
    private func search(session: URLSession, deezerEnabled: Bool = true,
                        cache: AlbumCoverSearchCache? = nil) -> AlbumCoverSearch {
        AlbumCoverSearch(
            musicBrainz: MusicBrainzClient(session: session,
                                           baseURL: URL(string: "https://mb.test/ws/2")!,
                                           rateLimiter: MusicBrainzRateLimiter(minimumInterval: 0)),
            coverArtArchive: CoverArtArchiveClient(session: session,
                                                   baseURL: URL(string: "https://caa.test")!),
            deezer: DeezerClient(session: session, baseURL: URL(string: "https://deezer.test/search")!),
            deezerEnabled: deezerEnabled,
            cache: cache)
    }

    private static let releasesJSON = """
    {"releases": [
      {"id": "rel-1", "title": "Signos", "date": "1986-11-25"},
      {"id": "rel-2", "title": "Signos (Remasterizado)", "date": "2007"}
    ]}
    """

    private static func coverArtJSON(_ image: String) -> String {
        """
        {"images": [{"image": "\(image)", "front": true, "thumbnails": {"large": "\(image)"}}]}
        """
    }

    private static let deezerAlbumsJSON = """
    {"data": [
      {"title": "Signos", "cover_xl": "https://img.test/deezer-1.jpg", "artist": {"name": "Soda Stereo"}}
    ]}
    """

    // MARK: - Varias fuentes, varias tapas

    func testGathersOneCandidatePerReleaseAndAlsoDeezer() async {
        MockURLProtocol.handler = { request in
            let url = request.url!
            let body: String
            switch url.path {
            case "/ws/2/release": body = Self.releasesJSON
            case "/release/rel-1": body = Self.coverArtJSON("https://img.test/caa-1.jpg")
            case "/release/rel-2": body = Self.coverArtJSON("https://img.test/caa-2.jpg")
            case "/search/album": body = Self.deezerAlbumsJSON
            default:
                // Las imagenes: bytes distintos para cada una.
                return (self.http(url), Data(url.lastPathComponent.utf8))
            }
            return (self.http(url), Data(body.utf8))
        }

        let candidates = await search(session: mockSession()).candidates(album: "Signos", artist: "Soda Stereo")

        XCTAssertEqual(candidates.count, 3)
        XCTAssertEqual(Set(candidates.map(\.source)), [.coverArtArchive, .deezer])
        XCTAssertEqual(Set(candidates.compactMap(\.detail)),
                       ["Signos · 1986", "Signos (Remasterizado) · 2007", "Signos · Soda Stereo"])

        // R2-3: la lista viene ORDENADA POR RECOMENDACIÓN, no por
        // fuente. "Signos" (título exacto + tapa frontal) va primero; la
        // edición "Signos (Remasterizado)" queda al final porque su
        // título no coincide, aunque sea de la misma fuente que la
        // primera.
        XCTAssertEqual(candidates[0].detail, "Signos · 1986")
        XCTAssertEqual(candidates.last?.detail, "Signos (Remasterizado) · 2007")
    }

    func testTheSameImageFromTwoSourcesIsShownOnce() async {
        // Dos ediciones que comparten la MISMA tapa no son dos opciones:
        // ofrecerlas dos veces solo obliga al usuario a comparar dos
        // imagenes identicas.
        MockURLProtocol.handler = { request in
            let url = request.url!
            switch url.path {
            case "/ws/2/release": return (self.http(url), Data(Self.releasesJSON.utf8))
            case "/release/rel-1", "/release/rel-2":
                return (self.http(url), Data(Self.coverArtJSON("https://img.test/misma.jpg").utf8))
            case "/search/album": return (self.http(url), Data(#"{"data": []}"#.utf8))
            default: return (self.http(url), Data("bytes iguales".utf8))
            }
        }

        let candidates = await search(session: mockSession()).candidates(album: "Signos", artist: "Soda Stereo")

        XCTAssertEqual(candidates.count, 1)
    }

    func testAFailingSourceDoesNotCancelTheOther() async {
        // MusicBrainz caido no puede dejar sin resultados una busqueda
        // que Deezer si podia contestar.
        //
        // Se usa 500 y no 503 a proposito: 503 es "saturado" y el
        // cliente lo reintenta con espera creciente (2 s + 4 s), que es
        // lo correcto en produccion pero aca solo agregaria seis
        // segundos a la suite. Lo que esta prueba mira es el respaldo,
        // no el reintento.
        MockURLProtocol.handler = { request in
            let url = request.url!
            switch url.path {
            case "/ws/2/release": return (self.http(url, 500), Data())
            case "/search/album": return (self.http(url), Data(Self.deezerAlbumsJSON.utf8))
            default: return (self.http(url), Data("deezer-bytes".utf8))
            }
        }

        let candidates = await search(session: mockSession()).candidates(album: "Signos", artist: "Soda Stereo")

        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.source, .deezer)
    }

    func testDeezerIsNotUsedWhenTheOwnerTurnedItOff() async {
        // D-203: Deezer es opcional y se apaga en Ajustes › Servicios.
        // Apagado no se le pega ni una vez.
        nonisolated(unsafe) var touchedDeezer = false
        MockURLProtocol.handler = { request in
            let url = request.url!
            if url.path == "/search/album" { touchedDeezer = true }
            if url.path == "/ws/2/release" { return (self.http(url), Data(#"{"releases": []}"#.utf8)) }
            return (self.http(url), Data())
        }

        let candidates = await search(session: mockSession(), deezerEnabled: false)
            .candidates(album: "Signos", artist: "Soda Stereo")

        XCTAssertTrue(candidates.isEmpty)
        XCTAssertFalse(touchedDeezer)
    }

    func testNothingIsSearchedForTheUnknownAlbumGroup() async {
        // "Sin álbum" no es un disco: es el cajon de lo que no tiene uno.
        nonisolated(unsafe) var touchedNetwork = false
        MockURLProtocol.handler = { request in
            touchedNetwork = true
            return (self.http(request.url!), Data())
        }

        let candidates = await search(session: mockSession())
            .candidates(album: LibraryGrouping.unknownAlbumTitle, artist: "Soda Stereo")

        XCTAssertTrue(candidates.isEmpty)
        XCTAssertFalse(touchedNetwork)
    }

    // MARK: - ST-261: cache negativa

    func testANegativeCacheEntrySkipsTheNetworkOnlyWhenAsked() async throws {
        // La accion EN LOTE (menu Biblioteca) salta lo que ayer no tuvo
        // resultados; el picker manual siempre busca fresco.
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cover-search-negative-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let cache = AlbumCoverSearchCache(directory: tempDir)
        // "Signos" sin año y 0 pistas: la clave exacta que usa
        // `candidates(album:artist:)`.
        cache.store([], for: AlbumCoverSearchCache.Key(album: "Signos", artist: "Soda Stereo",
                                                       year: nil, trackCount: 0))

        nonisolated(unsafe) var touchedNetwork = false
        MockURLProtocol.handler = { request in
            touchedNetwork = true
            return (self.http(request.url!), Data())
        }

        // Sin el permiso expreso, la entrada negativa no aplica.
        let fresh = await search(session: mockSession(), cache: cache)
            .candidates(album: "Signos", artist: "Soda Stereo")
        XCTAssertTrue(fresh.isEmpty)
        XCTAssertTrue(touchedNetwork)

        touchedNetwork = false
        let batched = await search(session: mockSession(), cache: cache)
            .candidates(for: AlbumCoverScoring.AlbumFacts(title: "Signos", year: nil, trackCount: 0),
                        artist: "Soda Stereo", allowsNegativeCache: true)
        XCTAssertTrue(batched.isEmpty)
        XCTAssertFalse(touchedNetwork)
    }

    func testAnEmptySearchIsRememberedAsNegative() async throws {
        // La corrida que no encontro nada deja la entrada: la siguiente
        // accion en lote no vuelve a pegarle a la red por ese album.
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cover-search-negative-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let cache = AlbumCoverSearchCache(directory: tempDir)
        MockURLProtocol.handler = { request in
            (self.http(request.url!), Data(#"{"releases": []}"#.utf8))
        }

        let result = await search(session: mockSession(), deezerEnabled: false, cache: cache)
            .candidates(album: "Signos", artist: "Soda Stereo")

        XCTAssertTrue(result.isEmpty)
        XCTAssertTrue(cache.loadNegative(AlbumCoverSearchCache.Key(
            album: "Signos", artist: "Soda Stereo", year: nil, trackCount: 0)))
    }

    // MARK: - Detalle que se le muestra al usuario

    func testTheYearComesFromTheReleaseDate() {
        XCTAssertEqual(AlbumCoverSearch.year(from: "1986-11-25"), "1986")
        XCTAssertEqual(AlbumCoverSearch.year(from: "2007"), "2007")
        XCTAssertNil(AlbumCoverSearch.year(from: nil))
        XCTAssertNil(AlbumCoverSearch.year(from: "??"))
    }

    func testTheDetailSkipsWhatIsMissing() {
        XCTAssertEqual(AlbumCoverSearch.detail(title: "Signos", year: "1986"), "Signos · 1986")
        XCTAssertEqual(AlbumCoverSearch.detail(title: "Signos", year: nil), "Signos")
        XCTAssertNil(AlbumCoverSearch.detail(title: nil, year: nil))
        XCTAssertNil(AlbumCoverSearch.detail(title: "", year: nil))
    }
}

/// A qué álbum aplica "Buscar carátulas del álbum" cuando se dispara
/// desde una selección de canciones.
final class AlbumCoverRequestTests: XCTestCase {
    private func song(album: String?, artist: String?) -> AuraStudio.LibraryItem {
        var item = AuraStudio.LibraryItem(sourceURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).mp3"))
        item.metadata = TrackMetadata(artist: artist, album: album)
        return item
    }

    func testASingleAlbumGivesARequestForAllItsTracks() throws {
        let items = [song(album: "Signos", artist: "Soda Stereo"),
                     song(album: "Signos", artist: "Soda Stereo")]

        let request = try XCTUnwrap(AlbumCoverRequest.forAlbum(of: items))

        XCTAssertEqual(request.albumTitle, "Signos")
        XCTAssertEqual(request.albumArtist, "Soda Stereo")
        XCTAssertEqual(request.trackIDs, Set(items.map(\.id)))
    }

    func testASelectionSpanningTwoAlbumsHasNoCoverToSearch() {
        // ¿La tapa de cuál? Aplicar una sola imagen a dos discos seria
        // exactamente lo contrario de lo que se pidio.
        XCTAssertNil(AlbumCoverRequest.forAlbum(of: [
            song(album: "Signos", artist: "Soda Stereo"),
            song(album: "Nada Personal", artist: "Soda Stereo"),
        ]))
    }

    func testSongsWithoutAnAlbumHaveNothingToSearch() {
        XCTAssertNil(AlbumCoverRequest.forAlbum(of: [song(album: nil, artist: "Soda Stereo")]))
        XCTAssertNil(AlbumCoverRequest.forAlbum(of: [song(album: "   ", artist: "Soda Stereo")]))
        XCTAssertNil(AlbumCoverRequest.forAlbum(of: []))
    }

    // MARK: - R2-2: la aridad correcta

    func testSeveralSongsOfTheSameAlbumStillResolveToThatAlbum() throws {
        // El hallazgo del dueño: el ítem desaparecía con más de una
        // canción seleccionada. Tres canciones del mismo disco son UN
        // álbum y la acción tiene todo el sentido.
        let items = [song(album: "Signos", artist: "Soda Stereo"),
                     song(album: "Signos", artist: "Soda Stereo"),
                     song(album: "Signos", artist: "Soda Stereo")]

        let request = try XCTUnwrap(AlbumCoverRequest.forAlbum(of: items))

        XCTAssertEqual(request.albumTitle, "Signos")
        XCTAssertEqual(request.trackCount, 3)
    }

    func testTheCoverIsAppliedToTheWHOLEAlbumNotOnlyToWhatWasSelected() throws {
        // Una carátula de álbum a medias no es una carátula de álbum:
        // seleccionar 2 de 5 canciones y elegir tapa tiene que dejar las
        // 5 iguales.
        let album = (0..<5).map { _ in song(album: "Signos", artist: "Soda Stereo") }
        let otro = song(album: "Nada Personal", artist: "Soda Stereo")
        let library = album + [otro]

        let request = try XCTUnwrap(AlbumCoverRequest.forAlbum(of: Array(album.prefix(2)), in: library))

        XCTAssertEqual(request.trackCount, 5)
        XCTAssertEqual(request.trackIDs, Set(album.map(\.id)))
        XCTAssertFalse(request.trackIDs.contains(otro.id))
    }

    func testTheAlbumYearTravelsForScoring() throws {
        var item = song(album: "Signos", artist: "Soda Stereo")
        item.metadata?.year = "1986"

        let request = try XCTUnwrap(AlbumCoverRequest.forAlbum(of: [item]))

        XCTAssertEqual(request.albumYear, "1986")
    }

    func testCollaborationsDoNotSplitAnAlbumInTwo() throws {
        // R2-4 se hereda acá: un disco con una pista "feat." sigue
        // siendo un solo álbum, así que el ítem se ofrece igual.
        var invitado = song(album: "Demon Days", artist: "Gorillaz feat. De La Soul")
        invitado.metadata?.albumArtist = "Gorillaz feat. De La Soul"
        let normal = song(album: "Demon Days", artist: "Gorillaz")

        let request = try XCTUnwrap(AlbumCoverRequest.forAlbum(of: [invitado, normal]))

        XCTAssertEqual(request.albumArtist, "Gorillaz")
        XCTAssertEqual(request.trackCount, 2)
    }

    func testTheAlbumArtistWinsOverTheTrackArtist() throws {
        // Misma precedencia que el agrupado y que las carpetas del iPod
        // (`LibraryGrouping.albumArtist`): un disco de varios artistas
        // se busca por el artista del ÁLBUM.
        var item = song(album: "Signos", artist: "Invitado")
        item.metadata?.albumArtist = "Soda Stereo"

        let request = try XCTUnwrap(AlbumCoverRequest.forAlbum(of: [item]))

        XCTAssertEqual(request.albumArtist, "Soda Stereo")
    }

    // MARK: - ST-261: toda la biblioteca, sin seleccion

    private func songWithCover(album: String?, artist: String?) -> AuraStudio.LibraryItem {
        var item = song(album: album, artist: artist)
        item.metadata?.coverURL = URL(fileURLWithPath: "/tmp/tapa.jpg")
        return item
    }

    func testForAllAlbumsCoversEveryAlbumInCatalogOrder() {
        // El orden del catalogo, no el del diccionario: es el orden que
        // ve el usuario en el progreso y en la cola del selector.
        let items = [song(album: "Nada Personal", artist: "Soda Stereo"),
                     song(album: "Signos", artist: "Soda Stereo"),
                     song(album: "Signos", artist: "Soda Stereo")]
        let index = LibraryCatalogIndex(items: items, options: .default)

        let requests = AlbumCoverRequest.forAllAlbums(in: index, onlyMissingCovers: false)

        XCTAssertEqual(requests.map(\.albumTitle), ["Nada Personal", "Signos"])
        XCTAssertEqual(requests.last?.trackCount, 2)
    }

    func testForAllAlbumsOnlyMissingSkipsAlbumsThatAlreadyHaveACover() {
        // El "truco" de omitir lo completo: un album con ALGUNA pista
        // con caratula no vuelve a buscar -- no toca la red por él.
        let items = [song(album: "Signos", artist: "Soda Stereo"),
                     songWithCover(album: "Nada Personal", artist: "Soda Stereo"),
                     song(album: "Nada Personal", artist: "Soda Stereo")]
        let index = LibraryCatalogIndex(items: items, options: .default)

        let requests = AlbumCoverRequest.forAllAlbums(in: index, onlyMissingCovers: true)

        XCTAssertEqual(requests.map(\.albumTitle), ["Signos"])
    }

    func testForAllAlbumsNeverIncludesTheUnknownAlbum() {
        // "Sin album" no es un disco: no se le busca tapa ni en el modo
        // de biblioteca completa.
        let items = [song(album: nil, artist: "Soda Stereo"),
                     song(album: "Signos", artist: "Soda Stereo")]
        let index = LibraryCatalogIndex(items: items, options: .default)

        let requests = AlbumCoverRequest.forAllAlbums(in: index, onlyMissingCovers: false)

        XCTAssertEqual(requests.map(\.albumTitle), ["Signos"])
    }
}
