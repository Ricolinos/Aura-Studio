import AppKit
import SwiftUI

/// ST-193: la franja que anuncia una versión más nueva de Aura Studio.
///
/// Misma forma que `CoverNormalizationBar` (ST-141) a propósito: una
/// franja angosta al pie, del mismo alto y con el mismo fondo. **Nada
/// modal**: una app no interrumpe a nadie para contarle que existe otra
/// versión de sí misma.
///
/// Se puede cerrar, y cerrada **no vuelve por esa misma versión** (ver
/// `AppUpdateChecker.dismissAnnouncement`). La siguiente sí, porque su
/// tag será otro.
struct AppUpdateBar: View {
    let update: AppUpdateDecision.Available
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle")
                .foregroundStyle(AuraColors.light.accent)
            Text("Hay una versión nueva de Aura Studio: \(update.version.releaseString)")
                .lineLimit(1)
            if update.downloadURL == nil {
                // Sin el asset esperado no se ofrece descarga -- un botón
                // que falla es peor que no tenerlo (ST-191 §3).
                Text("El instalador todavía no está publicado en ese Release.")
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
            if let page = update.releasePageURL {
                Button("Ver novedades") { NSWorkspace.shared.open(page) }
                    .buttonStyle(.link)
                    .help("Abre las notas de la versión \(update.version.releaseString) en GitHub")
            }
            if let download = update.downloadURL {
                Button("Descargar") { NSWorkspace.shared.open(download) }
                    .buttonStyle(.link)
                    .help("Baja \(update.assetName). Aura Studio no se actualiza sola: cuando termine, ábrelo y arrastra la app a Aplicaciones.")
            }
            Button("Ahora no", action: onDismiss)
                .buttonStyle(.link)
                .help("Oculta este aviso. No vuelve a aparecer por esta versión.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 28)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Hay una versión nueva de Aura Studio: \(update.version.releaseString)")
    }
}

/// El único observador de `AppUpdateChecker`, por el mismo motivo que
/// `LibraryStatusBarHost` y `CoverNormalizationBarHost` (ST-181/ST-186):
/// que anunciar una versión nueva invalide esta franja de 28 pt y no la
/// ventana entera.
struct AppUpdateBarHost: View {
    @ObservedObject var checker: AppUpdateChecker

    var body: some View {
        if let update = checker.pendingAnnouncement {
            AppUpdateBar(update: update) { checker.dismissAnnouncement() }
        }
    }
}
