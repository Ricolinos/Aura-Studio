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
            // ST-227 (A7c): el mensaje principal no cede espacio. Sin
            // prioridad, SwiftUI reparte el recorte entre los dos textos
            // de una línea, y en alemán -- donde la nota secundaria mide
            // 447 pt contra 283 del mensaje -- el usuario terminaba
            // leyendo "Hay una versión nueva de Aura Stu…" con la nota
            // entera al lado. Se ajusta el layout, no la traducción.
            Text(LSf("app-update-bar.hay-version-nueva-aura-studio", update.version.releaseString))
                .lineLimit(1)
                .layoutPriority(1)
            if update.downloadURL == nil {
                // Sin el asset esperado no se ofrece descarga -- un botón
                // que falla es peor que no tenerlo (ST-191 §3).
                Text(LS("app-update-bar.instalador-todavia-no-esta-publicado-ese"))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
            if let page = update.releasePageURL {
                Button(LS("app-update-bar.ver-novedades")) { NSWorkspace.shared.open(page) }
                    .buttonStyle(.link)
                    .help(LSf("app-update-bar.abre-notas-version-github", update.version.releaseString))
            }
            if let download = update.downloadURL {
                Button(LS("app-update-bar.descargar")) { NSWorkspace.shared.open(download) }
                    .buttonStyle(.link)
                    .help(LSf("app-update-bar.baja-aura-studio-no-se-actualiza", update.assetName))
            }
            Button(LS("app-update-bar.ahora-no"), action: onDismiss)
                .buttonStyle(.link)
                .help(LS("app-update-bar.oculta-este-aviso-no-vuelve-aparecer"))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 28)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(LSf("app-update-bar.accesibilidad-version-nueva", update.version.releaseString))
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
