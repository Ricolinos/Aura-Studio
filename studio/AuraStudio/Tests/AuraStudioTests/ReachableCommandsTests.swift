import XCTest
@testable import AuraStudio

/// ST-224 (addendum): **un comando que ninguna vista llama no existe
/// para el usuario.**
///
/// `convertReferencedToCopies` se escribió en A4, con sus pruebas en
/// verde, y **ninguna vista lo invocaba**. El 0.4.0 salió con una función
/// completa, probada y muerta: "Convertir referenciados en copias" era
/// inalcanzable. Ninguna prueba lo notó porque todas llamaban al modelo
/// directamente -- que es justo lo que hace que este defecto sobreviva a
/// una suite entera en verde.
///
/// Esta prueba mira lo que ninguna otra miraba: que cada comando público
/// del `LibraryViewModel` **tenga quien lo llame desde la interfaz**.
@MainActor
final class ReachableCommandsTests: XCTestCase {
    private var sourcesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/AuraStudio")
    }

    /// Comandos públicos que **no** los llama una vista, cada uno con su
    /// motivo. La lista es corta a propósito: si crece sin motivo, es que
    /// se están escribiendo funciones que nadie usa.
    private static let interiores: [String: String] = [
        "persistCatalog": "persistencia: la dispara el propio modelo tras cada cambio",
        "schedulePersistCatalog": "ídem, con retardo",
        "flushPendingPersistence": "persistencia: la usa el cierre de la app y las pruebas",
        "measureMissingFileSizes": "lo llama la carga del catálogo, no una vista",
        "performDeletion": "el borrado sin diálogo; entra por confirmPendingDeletion o por la migración, y está documentado así en ST-225",
        "makePersistenceSynchronousForTesting": "costura de pruebas",
        "replaceItemsForPerformanceTesting": "costura de pruebas",
    ]

    func testEveryPublicCommandOfTheLibraryViewModelIsReachableFromAView() throws {
        let modelo = try String(contentsOf: sourcesDirectory
            .appendingPathComponent("ViewModels/LibraryViewModel.swift"), encoding: .utf8)

        let declaracion = try NSRegularExpression(
            pattern: #"^ {4}(?:@discardableResult\s+)?(?:private\s+)?func\s+(\w+)"#,
            options: [.anchorsMatchLines])
        var publicos: Set<String> = []
        for match in declaracion.matches(in: modelo, range: NSRange(modelo.startIndex..., in: modelo)) {
            guard let rango = Range(match.range(at: 1), in: modelo) else { continue }
            let linea = String(modelo[Range(match.range, in: modelo)!])
            guard !linea.contains("private ") else { continue }
            publicos.insert(String(modelo[rango]))
        }
        XCTAssertGreaterThan(publicos.count, 30, "no se encontraron comandos -- ¿cambió la forma del archivo?")

        var vistas = ""
        let walker = FileManager.default.enumerator(
            at: sourcesDirectory.appendingPathComponent("Views"), includingPropertiesForKeys: nil)
        while let url = walker?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            vistas += try String(contentsOf: url, encoding: .utf8)
        }
        XCTAssertFalse(vistas.isEmpty)

        let inalcanzables = publicos
            .filter { !vistas.contains($0) && Self.interiores[$0] == nil }
            .sorted()
        XCTAssertTrue(inalcanzables.isEmpty,
                      "comandos que ninguna vista llama -- el usuario no puede usarlos:\n"
                        + inalcanzables.joined(separator: "\n")
                        + "\nSi de verdad son internos, agrégalos a `interiores` CON SU MOTIVO.")

        // La lista de excepciones no puede pudrirse: una entrada que ya
        // no corresponde a ningún comando es ruido que tapa el próximo.
        let sobrantes = Self.interiores.keys.filter { !publicos.contains($0) }.sorted()
        XCTAssertTrue(sobrantes.isEmpty, "excepciones que ya no existen: \(sobrantes)")
    }

    /// **Ningún ayudante de vista declarado y no usado.**
    ///
    /// Esta prueba nació de un fallo de la anterior. Al comprobarla al
    /// revés --quitando la fila del cuerpo de Ajustes-- siguió en verde:
    /// el `private var convertReferencedRow` seguía declarado en el
    /// archivo, así que el nombre del comando aparecía en `Views/` igual.
    /// O sea que la prueba comprobaba "el nombre está escrito en algún
    /// sitio", no "una vista lo usa" -- que es un grado más débil de lo
    /// que decía su propio nombre.
    ///
    /// Un ayudante declarado y nunca usado es exactamente el mismo
    /// defecto una capa más adentro: código completo, probado y muerto.
    func testNoViewHelperIsDeclaredAndNeverUsed() throws {
        let declaracion = try NSRegularExpression(
            pattern: #"^\s{4}(?:@ViewBuilder\s+)?private\s+(?:var|func)\s+(\w+)"#,
            options: [.anchorsMatchLines])
        var muertos: [String] = []
        var revisados = 0
        let walker = FileManager.default.enumerator(
            at: sourcesDirectory.appendingPathComponent("Views"), includingPropertiesForKeys: nil)
        while let url = walker?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let texto = try String(contentsOf: url, encoding: .utf8)
            for match in declaracion.matches(in: texto, range: NSRange(texto.startIndex..., in: texto)) {
                guard let rango = Range(match.range(at: 1), in: texto) else { continue }
                let nombre = String(texto[rango])
                revisados += 1
                // Una vez es la declaración; hace falta al menos una más.
                let usos = texto.components(separatedBy: nombre).count - 1
                if usos < 2 { muertos.append("\(url.lastPathComponent): \(nombre)") }
            }
        }
        XCTAssertGreaterThan(revisados, 50, "no se encontraron ayudantes -- ¿cambió la forma de los archivos?")
        XCTAssertTrue(muertos.isEmpty,
                      "ayudantes de vista declarados y nunca usados -- código muerto que la interfaz no dibuja:\n"
                        + muertos.sorted().joined(separator: "\n"))
    }

    /// Y el comando concreto que faltaba, nombrado: entra por Ajustes,
    /// pide confirmación y tiene su identificador de accesibilidad.
    func testConvertingReferencedSongsIsReachableFromSettings() throws {
        let ajustes = try String(contentsOf: sourcesDirectory
            .appendingPathComponent("Views/SettingsSectionView.swift"), encoding: .utf8)

        XCTAssertTrue(ajustes.contains("requestReferenceConversion()"),
                      "Ajustes tiene que pedir la conversión")
        XCTAssertTrue(ajustes.contains("confirmReferenceConversion()"),
                      "y confirmarla: pedir sin confirmar deja el diálogo sin botón que haga nada")
        XCTAssertTrue(ajustes.contains("ajustes.almacenamiento.convertirReferenciados"),
                      "el identificador que usa el arnés de capturas")
        // Y la fila tiene que estar DIBUJADA, no solo declarada: una vez
        // es la declaración del `private var`, así que hacen falta dos.
        XCTAssertGreaterThanOrEqual(ajustes.components(separatedBy: "convertReferencedRow").count - 1, 2,
                                    "la fila está declarada pero no se dibuja: el botón no existe en pantalla")
    }
}
