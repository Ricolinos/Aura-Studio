import AppKit
import CoreGraphics
import CryptoKit
import XCTest

/// ST-188/F7: el único gesto de §A que el núcleo puro de F4
/// (`GridSelectionTests`, 35/35 en verde) no puede probar --
/// `press(forDuration:thenDragTo:)` sobre la app real, para confirmar
/// que el `NSViewRepresentable` que traduce eventos de mouse a un
/// arrastre (ST-184) de verdad recibe esos eventos dentro de un
/// `ScrollView`/`LazyVGrid`.
///
/// Construye la biblioteca a mano, con JSON plano (`Foundation`, sin
/// `@testable import` -- este target no tiene acceso a los tipos
/// internos de `AuraStudio`, solo a la app compilada de verdad vía
/// Accessibility) replicando el esquema de `PersistedLibrary`/
/// `PersistedLibraryItem` (`Sources/AuraStudio/Models/
/// LibraryPersistence.swift`). 30 álbumes, una pista cada uno, con una
/// carátula JPEG real y pequeña por álbum -- alcanza para arrastrar
/// sobre varias tarjetas sin pagar el costo de armar 1 000 en un
/// proceso de prueba de interfaz (mucho más lento que uno de XCTest
/// normal: cada lanzamiento de la app real cuesta segundos).
///
/// **Requiere UNA condición de máquina, no un defecto de código
/// (ST-187/ST-188)**: el permiso de automatización/accesibilidad del
/// sistema para el ejecutor de pruebas -- el dueño lo concedió una vez
/// (2026-09-06); sin él, `xcodebuild test` falla con "Timed out while
/// enabling automation mode" antes de llegar a lanzar nada.
///
/// La otra hipótesis que se manejó (que estas sesiones de Claude Code no
/// tienen consola gráfica real y por eso `app.windows.count` daba 0) SE
/// DESCARTÓ (2026-09-06): un lanzamiento directo del binario (sin pasar
/// por LaunchServices) mostró la ventana perfectamente, con `sample`
/// confirmando que el proceso lanzado vía `open --env`/XCUITest se
/// quedaba colgado en `_dyld_start` (96K de huella, nunca llega a
/// `main()`) mientras que el binario directo arrancaba normal (44,9M).
/// Es decir: sí hay consola real, el problema era el propio lanzamiento
/// con variables de entorno inyectadas pasando por LaunchServices. Tras
/// reintentar el mismo lanzamiento (posible efecto Gatekeeper de
/// reintento en primer arranque de una app firmada ad-hoc en un disco
/// externo, según hipótesis de "experto en código opus" -- ver
/// DECISIONS.md ST-187), el proceso arrancó con ventana real
/// (`app.windows.count == 1`). Tras eso salieron tres bugs reales de
/// ESTA prueba, ya corregidos: el predicado de "Álbumes" asumía
/// `label` cuando el árbol real usa `value`; `otherElements` nunca
/// encontraba las tarjetas porque el identificador lo llevan una
/// `Image` y dos `StaticText`, ninguno de tipo `Other`; y pedir una
/// tarjeta fuera de pantalla (existe en el árbol de `LazyVGrid` aunque
/// nunca se dibujó) revienta `press(forDuration:thenDragTo:)`.
///
/// **Lo que queda abierto, y SÍ es de la máquina, no del código**: esta
/// Mac tiene dos pantallas (5K principal + 1920x1080 secundaria) y la
/// ventana nueva aparece en la secundaria. Ahí, `press(forDuration:
/// thenDragTo:)` revienta la síntesis de eventos con "point.x/y !=
/// INFINITY" para CUALQUIER punto final probado (esquina de tarjeta,
/// centro de tarjeta, tarjeta ya `isHittable`) -- documentado como bug
/// conocido de XCTest con ventanas fuera de la pantalla principal.
/// Reposicionar la ventana por Accessibility (`System Events`, sin
/// sintetizar mouse) para sortearlo NO funcionó: el proceso lanzado por
/// `xcodebuild test` no aparece como "application process" para
/// `System Events` ("-600, la aplicación no está abierta"). El gesto
/// llega escrito, compilado, y verificado hasta el arrastre en sí --
/// sidebar, cuadrícula y las 30 tarjetas se encuentran y clickean bien;
/// falta correrlo con la ventana en la pantalla principal (con el
/// dueño sentado ahí) o resolver el bug de XCTest.
final class AlbumsGridMarqueeDragUITests: XCTestCase {
    private var libraryRoot: URL!
    private static let albumCount = 30

    override func setUpWithError() throws {
        continueAfterFailure = false
        libraryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("AuraStudioUITest-Marquee-\(UUID().uuidString)", isDirectory: true)
        try Self.writeSyntheticLibrary(count: Self.albumCount, to: libraryRoot)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: libraryRoot)
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["AURA_UITEST_LIBRARY"] = libraryRoot.path
        app.launchEnvironment["AURA_UITEST_DEFAULTS_SUITE"] = "com.ricolinos.aurastudio.uitest.\(UUID().uuidString)"
        app.launch()
        return app
    }

    /// El gesto en sí: arrastrar desde un hueco de la cuadrícula (no
    /// desde una tarjeta) sobre varias tarjetas, y confirmar en la barra
    /// de estado que quedaron seleccionadas -- sin espiar el estado
    /// interno de la vista, tal como documentó Opus.
    func testDragFromEmptySpaceSelectsTheCardsItCrosses() throws {
        let app = launchApp()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "la app no llegó a primer plano")

        let screenshotAttachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshotAttachment.name = "tras-launch"
        screenshotAttachment.lifetime = .keepAlways
        add(screenshotAttachment)
        print("[DIAG] app.state tras launch: \(app.state.rawValue), app.windows.count: \(app.windows.count)")
        if app.state != .runningForeground {
            app.activate()
            print("[DIAG] tras activate(): app.state = \(app.state.rawValue), app.windows.count: \(app.windows.count)")
        }

        // Navegar a Álbumes -- confirmado con el árbol de accesibilidad
        // real (2026-09-06): las filas de la barra lateral que son
        // ítems seleccionables de un `List`/`Outline` en macOS exponen
        // su texto como `value`, no como `label` -- a diferencia de los
        // encabezados de sección ("Musica", "Video"), que sí usan
        // `label`. Se busca por predicado sobre CUALQUIER tipo de
        // elemento, aceptando ambos atributos, en vez de apostar a uno
        // solo.
        let albumsPredicate = NSPredicate(format: "label == %@ OR value == %@", "Álbumes", "Álbumes")
        let sidebarAlbums = app.descendants(matching: .any).matching(albumsPredicate).firstMatch
        if !sidebarAlbums.waitForExistence(timeout: 20) {
            print("[DIAG] árbol de accesibilidad completo:\n\(app.debugDescription)")
        }
        XCTAssertTrue(sidebarAlbums.exists, "no apareció la sección Álbumes en la barra lateral")
        sidebarAlbums.click()

        let grid = app.otherElements[UITestEnvironmentIDs.albumsGrid]
        XCTAssertTrue(grid.waitForExistence(timeout: 15), "no apareció la cuadrícula de Álbumes")

        // Confirmado con el árbol de accesibilidad real (2026-09-06): la
        // tarjeta no tiene un contenedor propio con ese identificador --
        // el mismo identificador lo comparten la `Image` de la carátula
        // y sus dos `StaticText` (título, artista), directo bajo la
        // cuadrícula. `otherElements` nunca los encuentra porque ninguno
        // es de tipo `Other`. Se usa la imagen de la carátula como ancla
        // -- es la única de los tres nodos con un tamaño (160x160) útil
        // para calcular el hueco y el punto de arrastre.
        let firstCard = app.images[UITestEnvironmentIDs.albumCard(0)]
        let secondCard = app.images[UITestEnvironmentIDs.albumCard(1)]
        if !firstCard.waitForExistence(timeout: 15) {
            print("[DIAG] cuadrícula sin tarjetas -- árbol bajo la cuadrícula:\n\(grid.debugDescription)")
        }
        XCTAssertTrue(firstCard.exists, "no apareció la primera tarjeta")
        XCTAssertTrue(secondCard.waitForExistence(timeout: 5), "no apareció la segunda tarjeta")

        // La última tarjeta (29) SÍ existe en el árbol de accesibilidad
        // (`LazyVGrid` la reporta aunque nunca se haya dibujado), pero su
        // posición lógica cae fuera de la pantalla física real -- pedirle
        // una coordenada normalizada ahí revienta la síntesis de eventos
        // de macOS ("point.x != INFINITY"), confirmado corriendo la
        // prueba real (2026-09-06). Un arrastre real solo puede terminar
        // en un punto que de verdad esté en pantalla, así que se busca la
        // última tarjeta que además sea `isHittable` -- sigue cruzando
        // varias filas/columnas sin necesitar que quepan las 30 sin
        // scroll (algo que el tamaño real de la ventana no garantiza).
        var endIndex = Self.albumCount - 1
        var lastCard = app.images[UITestEnvironmentIDs.albumCard(endIndex)]
        while !lastCard.exists || !lastCard.isHittable, endIndex > 1 {
            endIndex -= 1
            lastCard = app.images[UITestEnvironmentIDs.albumCard(endIndex)]
        }
        XCTAssertGreaterThan(endIndex, 1, "no se encontró ninguna tarjeta visible en pantalla para terminar el arrastre")

        // Diagnóstico de Opus (ST-188): el recuadro SOLO arranca desde un
        // hueco -- si el `press` cae sobre una tarjeta, lo que se
        // dispara es su `.draggable`, no el marquee. En vez de adivinar
        // un punto cerca del borde del contenedor, se calcula el hueco
        // real: el espacio horizontal entre la primera y la segunda
        // tarjeta (el `spacing` de 24 pt de `LazyVGrid`), que está
        // garantizado vacío sin importar el tamaño de la ventana.
        let firstFrame = firstCard.frame
        let secondFrame = secondCard.frame
        XCTAssertGreaterThan(secondFrame.minX, firstFrame.maxX,
                             "la segunda tarjeta no está a la derecha de la primera -- ¿una sola columna?")
        let gapPoint = CGPoint(x: (firstFrame.maxX + secondFrame.minX) / 2, y: firstFrame.midY)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: gapPoint.x, dy: gapPoint.y))
        // `lastCard.coordinate(withNormalizedOffset:)` revienta la
        // síntesis de eventos con "point.x/y != INFINITY" -- confirmado
        // corriendo la prueba real (2026-09-06), incluso armando el
        // punto absoluto igual que `start` arriba. Esta Mac tiene dos
        // pantallas (5K principal + 1920x1080 secundaria, `system_profiler
        // SPDisplaysDataType`); la ventana de la app vive en la
        // secundaria y su borde inferior lógico cae más abajo que el
        // borde físico real de esa pantalla -- un punto ahí no
        // corresponde a ningún píxel real, y CGEvent no puede
        // sintetizar un clic fuera de toda pantalla. El CENTRO de la
        // tarjeta (0.5, 0.5) -- ya garantizado real por `isHittable` --
        // en vez de cerca de su esquina (0.9, 0.9), se mantiene lejos de
        // ese borde.
        let lastFrame = lastCard.frame
        let endPoint = CGPoint(x: lastFrame.midX, y: lastFrame.midY)
        let end = origin.withOffset(CGVector(dx: endPoint.x, dy: endPoint.y))
        start.press(forDuration: 0.3, thenDragTo: end)

        let statusBar = app.staticTexts[UITestEnvironmentIDs.statusBar]
        XCTAssertTrue(statusBar.waitForExistence(timeout: 10), "no apareció la barra de estado")
        let deadline = Date().addingTimeInterval(10)
        while !statusBar.label.contains("seleccionad"), Date() < deadline {
            usleep(200_000)
        }
        XCTAssertTrue(statusBar.label.contains("seleccionad"),
                     "el arrastre no dejó ningún álbum seleccionado -- texto real: \"\(statusBar.label)\"")
        XCTAssertFalse(statusBar.label.hasPrefix("0 de"),
                      "el arrastre debía seleccionar más de cero álbumes -- texto real: \"\(statusBar.label)\"")
    }

    // MARK: - Fixture (JSON plano, sin @testable import)

    private static func writeSyntheticLibrary(count: Int, to libraryRoot: URL) throws {
        let fm = FileManager.default
        let musicDir = libraryRoot.appendingPathComponent("Música", isDirectory: true)
        let coversDir = libraryRoot.appendingPathComponent(".portadas", isDirectory: true)
        try fm.createDirectory(at: musicDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: coversDir, withIntermediateDirectories: true)

        var items: [[String: Any]] = []
        for i in 0..<count {
            let id = UUID()
            let artist = "Artista \(String(format: "%02d", i))"
            let albumName = "Álbum \(String(format: "%02d", i))"
            let albumDir = musicDir.appendingPathComponent(artist, isDirectory: true)
                .appendingPathComponent(albumName, isDirectory: true)
            try fm.createDirectory(at: albumDir, withIntermediateDirectories: true)

            let trackURL = albumDir.appendingPathComponent("01 Canción.mp3")
            try Data([0xFF, 0xFB, 0x90, 0x00]).write(to: trackURL)

            let cover = makeCoverJPEG(seed: UInt8(i % 256))
            let coverURL = coversDir.appendingPathComponent("\(id.uuidString).jpg")
            try cover.write(to: coverURL)
            let coverHash = sha256Hex(cover)

            items.append([
                "id": id.uuidString,
                "sourceRelativePath": "Música/\(artist)/\(albumName)/01 Canción.mp3",
                "kind": "music",
                "status": "ready",
                "metadata": [
                    "title": "Canción", "artist": artist, "album": albumName,
                    "albumArtist": artist, "year": "2000", "genre": "Rock",
                ],
                "preparedRelativePath": "Música/\(artist)/\(albumName)/01 Canción.mp3",
                "coverRelativePath": ".portadas/\(id.uuidString).jpg",
                "coverHash": coverHash,
            ])
        }

        let persisted: [String: Any] = ["items": items, "playlists": []]
        let data = try JSONSerialization.data(withJSONObject: persisted, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: libraryRoot.appendingPathComponent("biblioteca.json"))
    }

    /// Ruido JPEG real y pequeño (decodifica) -- mismo generador que
    /// `AlbumsGridPerformanceBaselineTests`/`LibraryCoverMemoryTests`,
    /// reproducido acá porque este target no puede importar esos
    /// archivos (viven en `AuraStudioTests`, otro target).
    private static func makeCoverJPEG(seed: UInt8) -> Data {
        let side = 64
        var buffer = [UInt8](repeating: seed, count: side * side * 4)
        for i in buffer.indices { buffer[i] = buffer[i] &+ UInt8(i % 251) }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: &buffer, width: side, height: side,
                                       bitsPerComponent: 8, bytesPerRow: side * 4,
                                       space: colorSpace,
                                       bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let cgImage = context.makeImage(),
              let rep = NSBitmapImageRep(cgImage: cgImage).representation(using: .jpeg, properties: [.compressionFactor: 0.6])
        else {
            fatalError("ST-188: no se pudo generar el JPEG sintético para el arrastre")
        }
        return rep
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02X", $0) }.joined()
    }
}

/// Copia local de `UITestEnvironment.ID` -- este target no puede
/// `@testable import AuraStudio` (es un target de UI testing, ligado a
/// la app compilada, no al módulo de la librería), así que los nombres
/// de los identificadores se duplican a mano. Si `UITestEnvironment.ID`
/// cambia sin avisar acá, esta prueba deja de encontrar los elementos --
/// tan visible como cualquier otro cambio de contrato entre módulos.
enum UITestEnvironmentIDs {
    static let albumsGrid = "albumes.cuadricula"
    static let statusBar = "biblioteca.barraEstado"
    static func albumCard(_ index: Int) -> String { "albumes.tarjeta.\(index)" }
}
