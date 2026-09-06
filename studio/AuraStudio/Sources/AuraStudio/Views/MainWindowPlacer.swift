import AppKit
import SwiftUI

/// ST-188 (addendum): coloca la ventana en la pantalla **principal**
/// cuando lo pide una prueba de interfaz.
///
/// `XCUIElement.press(forDuration:thenDragTo:)` revienta con
/// `point.x/y != INFINITY` si la ventana está en una pantalla
/// secundaria — un defecto conocido de XCTest, no de la app. En la Mac
/// del dueño (una 5K principal más una 1920×1080) la ventana caía en la
/// segunda, y ahí el gesto de arrastre —lo único que ST-188 existe para
/// poder verificar— no se puede ejercer.
///
/// **Sin `AURA_UITEST_MAIN_SCREEN=1` esto no hace absolutamente nada**, y
/// fuera de DEBUG la variable ni siquiera se lee: la ventana de quien usa
/// la app se abre donde el usuario la dejó, como siempre.
struct MainWindowPlacer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { PlacerView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class PlacerView: NSView {
        private var placed = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard UITestEnvironment.forcesMainScreenWindow,
                  !placed,
                  let window,
                  // `screens.first` es la que tiene la barra de menús --
                  // la "principal" en el sentido que le importa a XCTest.
                  // `NSScreen.main` es otra cosa: la que tiene el foco.
                  let screen = NSScreen.screens.first else { return }
            placed = true

            let size = UITestEnvironment.mainScreenWindowSize
            let visible = screen.visibleFrame
            let origin = CGPoint(x: visible.midX - size.width / 2,
                                 y: visible.midY - size.height / 2)
            window.setFrame(NSRect(origin: origin, size: size), display: true)
            // Que además quede al frente: una ventana colocada pero
            // detrás de otra tampoco sirve para un gesto.
            window.makeKeyAndOrderFront(nil)
        }
    }
}
