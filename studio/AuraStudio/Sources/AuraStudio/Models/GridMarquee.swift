import CoreGraphics
import Foundation

/// PLAN-studio-rendimiento-2.md Fase 4 (ST-184): las teclas modificadoras
/// de un gesto, como valor puro.
///
/// `GridSelection` ya tenía la separación entre "el gesto" y "leer
/// `NSEvent.modifierFlags`" (ST-152/ST-154) porque el estado global del
/// teclado no se puede simular en una prueba. F4 agrega tres gestos más
/// —arrastre, flechas y el menú Edición— y todos necesitan lo mismo, así
/// que el concepto deja de ser un detalle de `handleTap` y pasa a ser un
/// tipo: **la lógica de selección no conoce AppKit**, y la capa que sí
/// (el traductor de eventos del arrastre) no decide nada.
struct GridSelectionModifiers: OptionSet, Equatable, Sendable {
    let rawValue: Int

    init(rawValue: Int) { self.rawValue = rawValue }

    /// Suma al conjunto (rango, en un clic; unión, en un arrastre).
    static let shift = GridSelectionModifiers(rawValue: 1 << 0)
    /// Alterna elemento por elemento.
    static let command = GridSelectionModifiers(rawValue: 1 << 1)

    static let none: GridSelectionModifiers = []
}

/// Hacia dónde mueve el foco una flecha del teclado. En una cuadrícula,
/// arriba/abajo saltan una FILA entera; en una lista de una sola
/// columna, `columnsPerRow == 1` y las cuatro direcciones se reducen a
/// las dos que tienen sentido.
enum GridDirection: Equatable, Sendable {
    case left, right, up, down

    /// Cuántas posiciones del orden visible se mueve el foco.
    func step(columnsPerRow: Int) -> Int {
        let columns = max(1, columnsPerRow)
        switch self {
        case .left: return -1
        case .right: return 1
        case .up: return -columns
        case .down: return columns
        }
    }

    /// Hacia atrás en el orden -- decide dónde empieza el foco cuando
    /// todavía no hay ninguno.
    var isBackwards: Bool { self == .left || self == .up }
}

/// El núcleo **puro** de la selección por arrastre (marquee).
///
/// La capa de AppKit (`GridMarqueeOverlay`) solo traduce eventos del
/// ratón a un rectángulo y a un `GridSelectionModifiers`; toda la
/// decisión —qué tarjetas toca el rectángulo, y qué selección resulta de
/// eso— vive acá, sin vistas, sin `NSEvent` y sin hilo principal, para
/// que se pueda probar entera sin mover un mouse. Es lo que pidió la
/// sesión maestra al abrir F4: "núcleo puro y probable, y la capa
/// `NSViewRepresentable` solo como traductor".
enum GridMarquee {
    /// El marco de una tarjeta realizada, en el espacio de coordenadas
    /// de la cuadrícula. Solo llegan las que SwiftUI tiene en pantalla
    /// (`LazyVGrid` no realiza las demás), que es también lo único que
    /// un arrastre puede tocar.
    struct Frame<ID: Hashable>: Equatable {
        let id: ID
        let rect: CGRect

        init(id: ID, rect: CGRect) {
            self.id = id
            self.rect = rect
        }
    }

    /// El rectángulo que definen dos puntos, en cualquier orden -- se
    /// arrastra igual hacia arriba y a la izquierda que hacia abajo y a
    /// la derecha.
    static func rect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(x: min(start.x, end.x),
               y: min(start.y, end.y),
               width: abs(end.x - start.x),
               height: abs(end.y - start.y))
    }

    /// Las tarjetas que toca el rectángulo. Basta con que lo ROCE (como
    /// en Finder): pedir que la tarjeta quede contenida entera obligaría
    /// a rodear cada portada, que no es lo que nadie espera.
    static func hits<ID>(in rect: CGRect, frames: [Frame<ID>]) -> Set<ID> {
        var result = Set<ID>()
        for frame in frames where frame.rect.intersects(rect) {
            result.insert(frame.id)
        }
        return result
    }

    /// La selección que resulta de un arrastre.
    ///
    /// - `base` es la selección **al empezar** el arrastre, no la actual:
    ///   mientras el usuario mueve el mouse, cada posición se resuelve
    ///   contra el mismo punto de partida. Sin eso, agrandar y achicar el
    ///   rectángulo no sería reversible -- lo que entró no volvería a
    ///   salir.
    /// - sin modificadores, el arrastre **reemplaza** la selección;
    /// - con Shift, **suma** a la de partida;
    /// - con ⌘, **alterna** respecto de la de partida (lo que ya estaba
    ///   y el rectángulo toca, sale);
    /// - con Shift y ⌘ **a la vez, manda ⌘** (alternar).
    ///
    /// El último caso es la regla que la sesión maestra fijó para las
    /// dos plataformas (Windows ST-209): no es obvia -- Shift está
    /// primero en cualquier orden de lectura -- y sin fijarla cada lado
    /// habría elegido la suya. Se decide por ⌘ porque alternar es la
    /// operación más específica de las dos: sumar ya se consigue con
    /// Shift solo, mientras que "sacar de la selección lo que toque el
    /// recuadro" no se consigue de ninguna otra forma.
    static func selection<ID>(base: Set<ID>, hits: Set<ID>,
                              modifiers: GridSelectionModifiers) -> Set<ID> {
        if modifiers.contains(.command) { return base.symmetricDifference(hits) }
        if modifiers.contains(.shift) { return base.union(hits) }
        return hits
    }

    /// Todo junto, que es como lo usa la vista.
    static func selection<ID>(rect: CGRect, frames: [Frame<ID>], base: Set<ID>,
                              modifiers: GridSelectionModifiers) -> Set<ID> {
        selection(base: base, hits: hits(in: rect, frames: frames), modifiers: modifiers)
    }
}
