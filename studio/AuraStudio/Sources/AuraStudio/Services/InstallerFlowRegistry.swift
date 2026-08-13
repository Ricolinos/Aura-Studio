import Foundation
import Combine

/// Punto unico de verdad sobre la actividad del instalador entre TODAS
/// las instancias de `InstallerViewModel` (D-185). Existen al menos dos
/// (la del asistente manual en la pestaña Instalador y la del recorrido
/// automatico de pantalla completa), y en el incidente real del
/// 2026-08-13 ambas terminaron extrayendo el arbol .rockbox al mismo
/// tiempo sobre el mismo volumen -- dos `ditto` en carrera producen
/// exactamente los errores "File exists" que abortaron la instalacion.
@MainActor
final class InstallerFlowRegistry: ObservableObject {
    static let shared = InstallerFlowRegistry()

    /// Hay un flujo de instalacion/restauracion activo iniciado por el
    /// usuario (asistente abierto) o por el recorrido automatico.
    /// `ContentView` NO dispara la toma de pantalla completa mientras
    /// este encendido -- el disparo en medio de un flujo activo (la
    /// ventana transitoria sin volumen mientras NUESTRO PROPIO formateo
    /// corria) fue lo que lanzo el segundo instalador en paralelo.
    @Published var flowActive = false

    /// Alguna instancia esta escribiendo en el disco del iPod ahora
    /// mismo (formateo o copia de archivos). Cinturon y tirantes por
    /// debajo de `flowActive`: aunque dos flujos llegaran a coexistir,
    /// solo uno puede escribir.
    private(set) var isWritingToDisk = false

    private init() {}

    /// Intenta adquirir el candado de escritura. `false` = otra
    /// instancia ya esta escribiendo y el llamador NO debe tocar el
    /// disco.
    func beginWriting() -> Bool {
        guard !isWritingToDisk else { return false }
        isWritingToDisk = true
        return true
    }

    func endWriting() {
        isWritingToDisk = false
    }
}
