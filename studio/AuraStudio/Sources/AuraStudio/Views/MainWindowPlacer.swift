import AppKit
import SwiftUI

/// ST-188 (addendum): coloca la ventana en la pantalla **principal**
/// cuando lo pide una prueba de interfaz.
///
/// `XCUIElement.press(forDuration:thenDragTo:)` revienta con
/// `point.x/y != INFINITY` si la ventana está en una pantalla
/// secundaria — un defecto conocido de XCTest, no de la app. En la Mac
/// del dueño (una 5K principal en x 0-2560 más una 1920×1080 en x 2560)
/// la ventana caía en la segunda, y ahí el gesto de arrastre —lo único
/// que ST-188 existe para poder verificar— no se puede ejercer.
///
/// **Sin `AURA_UITEST_MAIN_SCREEN=1` esto no hace absolutamente nada**, y
/// fuera de DEBUG la variable ni siquiera se lee: la ventana de quien usa
/// la app se abre donde el usuario la dejó, como siempre.
///
/// ## Por qué no alcanzaba colocarla una vez
///
/// El primer intento colocaba la ventana en `viewDidMoveToWindow` y no
/// surtió efecto: el mecánico midió el arrastre saliendo en x 3190→3853,
/// o sea la pantalla secundaria. La causa es de orden: SwiftUI
/// **restaura el marco guardado** de la ventana (autosave/state
/// restoration) *después* de que la vista se adjunta, así que pisaba la
/// colocación.
///
/// De ahí las tres cosas que hace esta versión:
/// 1. **Apaga la restauración** (`isRestorable = false`,
///    `setFrameAutosaveName("")`) antes de colocar, para que no haya un
///    marco guardado que aplicar.
/// 2. Coloca en varios momentos —al adjuntarse, al volverse principal, y
///    en el siguiente ciclo del runloop— porque no hay un instante único
///    garantizado en el que SwiftUI ya no vaya a tocar la ventana.
/// 3. **Registra el marco antes y después** de cada intento, para que un
///    fallo futuro se diagnostique leyendo el volcado de la prueba en vez
///    de adivinando.
struct MainWindowPlacer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { PlacerView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class PlacerView: NSView {
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard UITestEnvironment.forcesMainScreenWindow else { return }
            guard let window else {
                // La vista salió de pantalla: se suelta el observador acá
                // y no en un `deinit` -- en modo Swift 6 un `deinit` no
                // aislado no puede tocar un `NSObjectProtocol`.
                if let observer {
                    NotificationCenter.default.removeObserver(observer)
                    self.observer = nil
                }
                return
            }

            // 1. Que no haya marco guardado que restaurar.
            window.isRestorable = false
            window.setFrameAutosaveName("")

            place(window, reason: "viewDidMoveToWindow")

            // 2. Y de nuevo cuando la ventana se vuelva principal...
            if observer == nil {
                observer = NotificationCenter.default.addObserver(
                    forName: NSWindow.didBecomeMainNotification,
                    object: window, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self, let window = self.window else { return }
                        self.place(window, reason: "didBecomeMain")
                    }
                }
            }

            // ...y en el siguiente ciclo del runloop, por si SwiftUI la
            // mueve justo después de esta pasada de layout.
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                self.place(window, reason: "siguiente ciclo")
            }
        }

        /// La pantalla **principal**: la que tiene el origen del espacio
        /// de coordenadas de AppKit, que es la misma que la de la barra
        /// de menús y la única en la que XCTest sabe apuntar.
        ///
        /// No se usa `NSScreen.main`: ésa es la que tiene el foco de
        /// teclado, que puede ser perfectamente la secundaria — y sería
        /// justo el caso en el que este seam hace falta.
        private var primaryScreen: NSScreen? {
            NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens.first
        }

        private func place(_ window: NSWindow, reason: String) {
            guard let screen = primaryScreen else { return }
            let size = UITestEnvironment.mainScreenWindowSize
            let visible = screen.visibleFrame
            let target = NSRect(x: visible.midX - size.width / 2,
                                y: visible.midY - size.height / 2,
                                width: size.width, height: size.height)
            let before = window.frame
            guard before != target else { return }
            window.setFrame(target, display: true)
            window.makeKeyAndOrderFront(nil)
            log("[MainWindowPlacer] \(reason): \(describe(before)) → \(describe(window.frame))"
                + "  (pantalla principal: \(describe(screen.frame)))")
        }

        private func describe(_ rect: NSRect) -> String {
            "(\(Int(rect.origin.x)), \(Int(rect.origin.y)) \(Int(rect.width))×\(Int(rect.height)))"
        }

        /// ST-188 (2.º addendum): además de `print`, al archivo.
        ///
        /// El `print` de la app bajo prueba **no llega** a la salida de
        /// `xcodebuild test` -- se buscó en el log capturado, en
        /// `log show` acotado al pid y en el `.xcresult`, y en ninguno
        /// aparecía. Lo que sí aparece son los `print` del proceso de
        /// PRUEBA, que es otro proceso. Por eso el diagnóstico se
        /// escribe también donde la prueba puede ir a buscarlo
        /// (`<AURA_UITEST_LIBRARY>/uitest.log`).
        private func log(_ message: String) {
            print(message)
            fflush(stdout)
            UITestLog.write(message)
        }
    }
}
