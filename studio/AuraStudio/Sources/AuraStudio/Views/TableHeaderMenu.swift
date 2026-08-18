import SwiftUI
import AppKit

/// Entrada de un menu contextual de encabezado de tabla (ST-019),
/// declarada como dato para poder construir el mismo menu tanto en
/// AppKit (clic derecho sobre los encabezados, ver
/// `TableHeaderMenuInstaller`) como en SwiftUI (el boton de la barra
/// encima de la tabla, `Menu`) sin duplicar la logica.
enum TableHeaderMenuEntry {
    case item(title: String, symbol: String? = nil, checked: Bool = false, enabled: Bool = true, action: () -> Void)
    case submenu(title: String, symbol: String? = nil, entries: [TableHeaderMenuEntry])
    case separator
}

/// `Table` de SwiftUI no expone la fila de encabezados: no acepta
/// `.contextMenu` ahi ni deja poner vistas propias. Debajo hay un
/// `NSTableView` real, y su `NSTableHeaderView` muestra `menu` con el
/// clic derecho (comportamiento nativo de AppKit). Esta vista vacia se
/// superpone a la tabla, encuentra ese `NSTableView` en la jerarquia y
/// le instala el menu -- construido de nuevo en cada apertura
/// (`menuNeedsUpdate`) para que las marcas reflejen el estado actual.
/// El clic izquierdo (ordenar, redimensionar) no se toca. Si por
/// alguna razon no se encuentra la tabla, no pasa nada: el mismo menu
/// vive tambien en el boton de la barra encima de la tabla.
struct TableHeaderMenuInstaller: NSViewRepresentable {
    let entries: () -> [TableHeaderMenuEntry]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onAttach = { [weak coordinator = context.coordinator] in
            coordinator?.install(from: view)
        }
        context.coordinator.entries = entries
        return view
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        context.coordinator.entries = entries
        DispatchQueue.main.async { [weak coordinator = context.coordinator, weak nsView] in
            guard let nsView else { return }
            coordinator?.install(from: nsView)
        }
    }

    final class ProbeView: NSView {
        var onAttach: (() -> Void)?
        override var isOpaque: Bool { false }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            DispatchQueue.main.async { [weak self] in self?.onAttach?() }
        }
    }

    final class Coordinator: NSObject, NSMenuDelegate {
        var entries: () -> [TableHeaderMenuEntry] = { [] }
        private let menu = NSMenu()
        private weak var installedOn: NSTableHeaderView?

        override init() {
            super.init()
            menu.delegate = self
            menu.autoenablesItems = false
        }

        func install(from probe: NSView) {
            guard let table = Self.findTableView(near: probe), let header = table.headerView else { return }
            if header.menu !== menu {
                header.menu = menu
                installedOn = header
            }
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            Self.populate(menu, with: entries())
        }

        static func populate(_ menu: NSMenu, with entries: [TableHeaderMenuEntry]) {
            for entry in entries {
                switch entry {
                case .separator:
                    menu.addItem(.separator())
                case .item(let title, let symbol, let checked, let enabled, let action):
                    let item = ClosureMenuItem(title: title, action: action)
                    item.state = checked ? .on : .off
                    item.isEnabled = enabled
                    if let symbol {
                        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
                    }
                    menu.addItem(item)
                case .submenu(let title, let symbol, let children):
                    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                    if let symbol {
                        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
                    }
                    let submenu = NSMenu(title: title)
                    submenu.autoenablesItems = false
                    populate(submenu, with: children)
                    item.submenu = submenu
                    menu.addItem(item)
                }
            }
        }

        /// La vista sonda vive en un contenedor hermano del
        /// `NSScrollView` de la tabla (SwiftUI arma el `.overlay` en el
        /// mismo padre): se sube unos niveles y se busca hacia abajo el
        /// primer `NSTableView`. Acotado para no recorrer toda la
        /// ventana.
        static func findTableView(near probe: NSView) -> NSTableView? {
            var ancestor: NSView? = probe.superview
            var hops = 0
            while let current = ancestor, hops < 6 {
                if let table = firstTableView(in: current, depth: 0) { return table }
                ancestor = current.superview
                hops += 1
            }
            return nil
        }

        private static func firstTableView(in view: NSView, depth: Int) -> NSTableView? {
            guard depth < 12 else { return nil }
            for sub in view.subviews {
                if let table = sub as? NSTableView { return table }
                if let table = firstTableView(in: sub, depth: depth + 1) { return table }
            }
            return nil
        }
    }

    /// `NSMenuItem` con la accion como closure (evita un target/selector
    /// por entrada).
    final class ClosureMenuItem: NSMenuItem {
        private let handler: () -> Void

        init(title: String, action: @escaping () -> Void) {
            self.handler = action
            super.init(title: title, action: #selector(fire), keyEquivalent: "")
            self.target = self
        }

        required init(coder: NSCoder) { fatalError("init(coder:) no se usa") }

        @objc private func fire() { handler() }
    }
}

/// Mismas entradas, como contenido de un `Menu` de SwiftUI (el boton
/// de la barra encima de la tabla).
struct TableHeaderMenuContent: View {
    let entries: [TableHeaderMenuEntry]

    var body: some View {
        ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
            entryView(entry)
        }
    }

    @ViewBuilder
    private func entryView(_ entry: TableHeaderMenuEntry) -> some View {
        switch entry {
        case .separator:
            Divider()
        case .item(let title, let symbol, let checked, let enabled, let action):
            Button(action: action) {
                if checked {
                    Label(title, systemImage: "checkmark")
                } else if let symbol {
                    Label(title, systemImage: symbol)
                } else {
                    Text(title)
                }
            }
            .disabled(!enabled)
        case .submenu(let title, let symbol, let children):
            Menu {
                TableHeaderMenuContent(entries: children)
            } label: {
                if let symbol {
                    Label(title, systemImage: symbol)
                } else {
                    Text(title)
                }
            }
        }
    }
}
