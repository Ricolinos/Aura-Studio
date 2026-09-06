import Foundation
import XCTest

/// ST-194: crear una suite de `UserDefaults` aislada **y borrarla al
/// terminar la prueba**.
///
/// Las pruebas de este paquete aíslan sus preferencias creando una suite
/// con nombre único (`"PerfBaselineTests-<UUID>"`), que es lo correcto:
/// sin eso, una prueba le cambiaría los ajustes reales a quien corra el
/// suite. Lo que faltaba es el otro extremo: **nadie las borraba**, y
/// cada suite deja un `.plist` en `~/Library/Preferences`. Con veintitrés
/// familias de pruebas, cada corrida completa deja cientos de archivos;
/// en la Mac del dueño se habían acumulado **más de diez mil**.
///
/// `addTeardownBlock` es lo que lo cierra: se ejecuta al terminar **esa**
/// prueba, pase o falle, así que la limpieza no depende de que nadie se
/// acuerde de llamarla ni de que el proceso termine bien.
///
/// La limpieza de lo que YA quedó tirado es otra cosa y no corre sola:
/// `tools/limpiar-preferencias-de-pruebas.sh`, que se ejecuta a mano.
extension XCTestCase {
    /// Una suite de `UserDefaults` para esta prueba, que se borra al
    /// terminar. `prefix` es el nombre de familia de siempre.
    func makeIsolatedDefaults(_ prefix: String) -> UserDefaults {
        makeIsolatedDefaults(named: "\(prefix)-\(UUID().uuidString)")
    }

    /// Igual, pero con el nombre completo ya armado -- para las pruebas
    /// que necesitan RECORDAR el nombre (por ejemplo, para construir dos
    /// `AppPreferences` sobre la misma suite y comprobar que lo guardado
    /// sobrevive).
    func makeIsolatedDefaults(named suiteName: String) -> UserDefaults {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("no se pudo crear la suite de preferencias «\(suiteName)»")
            return .standard
        }
        TestDefaults.register(suiteName: suiteName)
        cleanUpDefaults(named: suiteName)
        return defaults
    }

    /// Registra el borrado de una suite creada por otra vía. Útil para
    /// las pruebas que arman el nombre ellas mismas.
    func cleanUpDefaults(named suiteName: String) {
        addTeardownBlock {
            TestDefaults.destroy(suiteName: suiteName)
        }
    }
}

enum TestDefaults {
    /// Borra una suite **y su archivo**.
    ///
    /// `removePersistentDomain(forName:)` NO alcanza, y esto se midió:
    /// `AuraUpdateCheckerTests` y `ReleaseCacheTests` ya lo llamaban en
    /// su `tearDown` desde siempre, y aun así habían dejado 735 y 390
    /// `.plist` respectivamente. Vacía el dominio, pero `cfprefsd`
    /// conserva el archivo. Hay que borrarlo.
    ///
    /// Y borrarlo una vez tampoco alcanza, y esto **también** se midió:
    /// con el borrado por prueba, una corrida aislada de
    /// `AppPreferencesTests` dejaba cero archivos, pero el suite completo
    /// seguía dejando 108. `cfprefsd` escribe el archivo cuando le
    /// conviene, y en una corrida larga alcanza a reescribir el que
    /// acabamos de borrar. Por eso hay dos pasadas: una por prueba
    /// (barata, y suficiente casi siempre) y una **al terminar el
    /// bundle**, cuando ya nadie va a volver a tocar esas suites.
    ///
    /// El borrado está **acotado a nombres que solo pueden ser
    /// nuestros**: el patrón exige `<Familia>-<UUID>`. Así, ni por un
    /// error de programación ni por un nombre venido de otro lado se
    /// puede apuntar esto a un `.plist` de verdad del usuario (un
    /// `com.apple.finder` no pasa el filtro).
    static func destroy(suiteName: String) {
        let defaults = UserDefaults(suiteName: suiteName)
        defaults?.removePersistentDomain(forName: suiteName)
        // Fuerza a que el vaciado llegue a `cfprefsd` antes de borrar el
        // archivo; si no, puede reescribirlo justo después.
        defaults?.synchronize()
        UserDefaults.standard.removeSuite(named: suiteName)
        removeFile(suiteName: suiteName)
    }

    private static func removeFile(suiteName: String) {
        guard isTestSuiteName(suiteName) else { return }
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/\(suiteName).plist")
        try? FileManager.default.removeItem(at: url)
    }

    /// `<Familia>-<UUID en mayúsculas>`, que es lo que produce
    /// `makeIsolatedDefaults`. Nada más.
    static func isTestSuiteName(_ name: String) -> Bool {
        let parts = name.split(separator: "-", maxSplits: 1)
        guard parts.count == 2,
              !parts[0].isEmpty,
              parts[0].allSatisfy({ $0.isLetter || $0.isNumber }),
              UUID(uuidString: String(parts[1])) != nil else {
            return false
        }
        return true
    }

    // MARK: - Segunda pasada, al terminar el bundle

    private static let lock = NSLock()
    nonisolated(unsafe) private static var createdSuiteNames: Set<String> = []
    nonisolated(unsafe) private static var observer: CleanupObserver?

    static func register(suiteName: String) {
        lock.lock()
        createdSuiteNames.insert(suiteName)
        let needsObserver = observer == nil
        if needsObserver { observer = CleanupObserver() }
        let created = observer
        lock.unlock()
        if needsObserver, let created {
            XCTestObservationCenter.shared.addTestObserver(created)
        }
    }

    /// Borra lo que `cfprefsd` haya alcanzado a reescribir. Corre una
    /// vez, al final de todo.
    static func sweep() {
        lock.lock()
        let names = createdSuiteNames
        createdSuiteNames.removeAll()
        lock.unlock()
        for name in names { removeFile(suiteName: name) }
    }
}

private final class CleanupObserver: NSObject, XCTestObservation {
    func testBundleDidFinish(_ testBundle: Bundle) {
        TestDefaults.sweep()
    }
}
