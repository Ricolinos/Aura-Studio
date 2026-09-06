import AppKit
import SwiftUI

/// PLAN-studio-rendimiento-2.md Fase 4 (ST-184): la selección por
/// arrastre (marquee) de las cuadrículas.
///
/// **Esta capa no decide nada.** Traduce eventos del ratón a un
/// rectángulo y a un `GridSelectionModifiers`, y se los pasa al núcleo
/// puro (`GridMarquee`, `GridSelection.applyMarquee`). Es la división que
/// pidió la sesión maestra al abrir F4: la lógica se prueba entera sin
/// mover un mouse, y lo que queda para verificar a mano es solo el gesto
/// físico.
///
/// Va como **fondo** de la cuadrícula, no como capa encima: en Finder,
/// arrastrar DESDE un elemento lo mueve (eso es `.draggable`) y
/// arrastrar desde un hueco dibuja el recuadro. Poniéndolo detrás, las
/// tarjetas siguen recibiendo sus clics y sus arrastres exactamente como
/// antes, y acá solo llega lo que empezó en un hueco.
struct GridMarqueeCapture: NSViewRepresentable {
    /// Empezó un arrastre en un hueco.
    let onBegin: () -> Void
    /// Se movió: rectángulo en coordenadas de la cuadrícula.
    let onDrag: (CGRect, GridSelectionModifiers) -> Void
    /// Terminó (o se canceló).
    let onEnd: () -> Void
    /// Clic simple en un hueco, sin arrastrar: limpia la selección,
    /// como en Finder.
    let onClickAway: (GridSelectionModifiers) -> Void

    func makeNSView(context: Context) -> MarqueeCaptureView {
        let view = MarqueeCaptureView()
        view.onBegin = onBegin
        view.onDrag = onDrag
        view.onEnd = onEnd
        view.onClickAway = onClickAway
        return view
    }

    func updateNSView(_ view: MarqueeCaptureView, context: Context) {
        view.onBegin = onBegin
        view.onDrag = onDrag
        view.onEnd = onEnd
        view.onClickAway = onClickAway
    }

    /// La vista que escucha el ratón. Nada de estado de selección acá:
    /// solo el punto donde empezó el arrastre y si ya se movió lo
    /// suficiente para considerarlo arrastre y no clic.
    final class MarqueeCaptureView: NSView {
        var onBegin: (() -> Void)?
        var onDrag: ((CGRect, GridSelectionModifiers) -> Void)?
        var onEnd: (() -> Void)?
        var onClickAway: ((GridSelectionModifiers) -> Void)?

        /// Debajo de esto, el gesto es un clic y no un arrastre. Mismo
        /// orden de magnitud que usa AppKit para distinguirlos.
        private static let dragThreshold: CGFloat = 4

        private var anchorPoint: CGPoint?
        private var didDrag = false
        private var autoscrollTask: Task<Void, Never>?
        private var lastEvent: NSEvent?

        /// Coordenadas con el origen ARRIBA a la izquierda, como
        /// SwiftUI: sin esto, el rectángulo del arrastre saldría
        /// espejado respecto de los marcos que reportan las tarjetas.
        override var isFlipped: Bool { true }

        override func mouseDown(with event: NSEvent) {
            anchorPoint = convert(event.locationInWindow, from: nil)
            didDrag = false
        }

        override func mouseDragged(with event: NSEvent) {
            guard let anchorPoint else { return }
            let point = convert(event.locationInWindow, from: nil)
            if !didDrag {
                let moved = hypot(point.x - anchorPoint.x, point.y - anchorPoint.y)
                guard moved >= Self.dragThreshold else { return }
                didDrag = true
                onBegin?()
                startAutoscroll()
            }
            lastEvent = event
            onDrag?(GridMarquee.rect(from: anchorPoint, to: point),
                    GridSelectionModifiers(event.modifierFlags))
        }

        override func mouseUp(with event: NSEvent) {
            stopAutoscroll()
            if didDrag {
                onEnd?()
            } else {
                // Clic en un hueco: limpia, salvo que se esté sumando a
                // la selección con Shift o ⌘ (ahí, no tocar nada es lo
                // correcto -- el usuario está construyendo una selección).
                let modifiers = GridSelectionModifiers(event.modifierFlags)
                if modifiers.isEmpty { onClickAway?(modifiers) }
            }
            anchorPoint = nil
            didDrag = false
            lastEvent = nil
        }

        // MARK: - Autoscroll

        /// Cerca del borde del `NSScrollView` que contiene la
        /// cuadrícula, arrastrar la desplaza -- si no, no se puede
        /// seleccionar más de lo que entra en pantalla.
        private func startAutoscroll() {
            stopAutoscroll()
            autoscrollTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    guard !Task.isCancelled,
                          let self, self.window != nil, let event = self.lastEvent,
                          let anchorPoint = self.anchorPoint else { return }
                    self.autoscroll(with: event)
                    // Reaplicar el rectángulo con la posición nueva: al
                    // desplazarse, el punto del mouse pasó a apuntar a
                    // otra parte de la cuadrícula.
                    let point = self.convert(event.locationInWindow, from: nil)
                    self.onDrag?(GridMarquee.rect(from: anchorPoint, to: point),
                                 GridSelectionModifiers(event.modifierFlags))
                }
            }
        }

        private func stopAutoscroll() {
            autoscrollTask?.cancel()
            autoscrollTask = nil
        }

        deinit {
            autoscrollTask?.cancel()
        }

        /// Salir de la ventana a mitad de un arrastre (cambiar de
        /// sección, cerrar) también lo termina.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { stopAutoscroll() }
        }
    }
}

/// El recuadro que se dibuja mientras se arrastra. Estilo de la
/// selección de Finder: relleno de acento muy translúcido y borde fino.
struct GridMarqueeRectangle: View {
    let rect: CGRect

    var body: some View {
        Rectangle()
            .fill(AuraColors.light.accent.opacity(0.15))
            .overlay(Rectangle().stroke(AuraColors.light.accent.opacity(0.7), lineWidth: 1))
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
            .allowsHitTesting(false)
    }
}

extension View {
    /// Reporta el marco de esta tarjeta al modelo de selección, en el
    /// espacio de coordenadas `space`, y lo retira al salir de pantalla.
    ///
    /// Escribir el marco no publica nada (ver `GridSelectionModel.
    /// reportFrame`), así que desplazarse no repinta la cuadrícula por
    /// esto; y son solo las celdas realizadas, no las 1 000.
    func gridMarqueeFrame<ID: Hashable>(id: ID, in space: String,
                                        model: GridSelectionModel<ID>) -> some View {
        background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear { model.reportFrame(geometry.frame(in: .named(space)), for: id) }
                    .onChange(of: geometry.frame(in: .named(space))) { _, rect in
                        model.reportFrame(rect, for: id)
                    }
                    .onDisappear { model.forgetFrame(for: id) }
            }
        )
    }
}
