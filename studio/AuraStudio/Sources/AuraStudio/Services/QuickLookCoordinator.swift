import AppKit
import Quartz

/// Reproduccion de un archivo de la biblioteca = Vista Previa de Finder
/// (Quick Look), NUNCA un reproductor propio dentro de la app (encargo
/// del dueño, 2026-08-13: "no que sea un reproductor... al darle espacio
/// al elemento, se reproducira" -- el gesto de Finder). `QLPreviewPanel`
/// es un panel COMPARTIDO del sistema (una sola instancia por app); esta
/// clase es su `dataSource`/`delegate` mientras esta abierto.
///
/// Se conecta directo (sin pasar por la cadena de respondedores de
/// `acceptsPreviewPanelControl`/`beginPreviewPanelControl`) porque Aura
/// Studio tiene una sola ventana -- el patron completo de "varios
/// controladores compitiendo por el panel" no aplica aca.
@MainActor
final class QuickLookCoordinator: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    private var url: URL?

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { self.url == nil ? 0 : 1 }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        MainActor.assumeIsolated { self.url as NSURL? }
    }

    /// Espacio sobre el mismo elemento ya abierto: cierra (como Finder).
    /// Espacio sobre otro elemento con el panel ya abierto: cambia la
    /// vista previa sin parpadear cerrando/abriendo.
    func toggle(for url: URL) {
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible, self.url == url {
            panel.orderOut(nil)
            return
        }
        self.url = url
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        QLPreviewPanel.shared()?.orderOut(nil)
    }
}
