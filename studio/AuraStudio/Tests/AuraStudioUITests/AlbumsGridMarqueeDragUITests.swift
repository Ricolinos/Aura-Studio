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
/// **Requiere un permiso de una sola vez, a mano, en la Mac**: la
/// primera corrida de `xcodebuild test -scheme AuraStudioUITests` falla
/// con "The test runner failed to initialize for UI testing (Timed out
/// while enabling automation mode)" hasta que alguien autoriza el modo
/// de automatización/accesibilidad para el ejecutor de pruebas -- un
/// diálogo del sistema, no algo que una sesión pueda conceder por sí
/// misma (documentado por "experto en código opus" en ST-188).
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

        // Navegar a Álbumes -- la fila de la barra lateral es un
        // `Label(sub.title, systemImage:)` (ver `SidebarView.groupRow`),
        // dentro de un `DisclosureGroup`/`List` -- eso puede exponerse
        // como celda o botón según cómo AppKit arme el árbol de
        // accesibilidad, no necesariamente como `staticTexts` suelto.
        // Se busca por predicado sobre CUALQUIER tipo de elemento en vez
        // de apostar a uno solo.
        let albumsPredicate = NSPredicate(format: "label == %@", "Álbumes")
        let sidebarAlbums = app.descendants(matching: .any).matching(albumsPredicate).firstMatch
        if !sidebarAlbums.waitForExistence(timeout: 20) {
            print("[DIAG] árbol de accesibilidad completo:\n\(app.debugDescription)")
        }
        XCTAssertTrue(sidebarAlbums.exists, "no apareció la sección Álbumes en la barra lateral")
        sidebarAlbums.click()

        let grid = app.otherElements[UITestEnvironmentIDs.albumsGrid]
        XCTAssertTrue(grid.waitForExistence(timeout: 15), "no apareció la cuadrícula de Álbumes")

        let firstCard = app.otherElements[UITestEnvironmentIDs.albumCard(0)]
        let secondCard = app.otherElements[UITestEnvironmentIDs.albumCard(1)]
        let lastCard = app.otherElements[UITestEnvironmentIDs.albumCard(Self.albumCount - 1)]
        XCTAssertTrue(firstCard.waitForExistence(timeout: 15), "no apareció la primera tarjeta")
        XCTAssertTrue(secondCard.waitForExistence(timeout: 5), "no apareció la segunda tarjeta")
        XCTAssertTrue(lastCard.waitForExistence(timeout: 5), "no apareció la última tarjeta -- ¿entran las 30 sin scroll?")

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
        let end = lastCard.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.9))
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
