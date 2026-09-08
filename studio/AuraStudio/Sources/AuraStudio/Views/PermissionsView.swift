import SwiftUI
import AppKit

/// Explica, en criollo, por que Aura Studio pide permisos que la
/// mayoria de las apps no piden -- y por que sin ellos el asistente no
/// puede funcionar. macOS moderno no deja que una app le hable
/// directamente a discos removibles/dispositivos USB sin autorizacion
/// explicita del usuario en Ajustes del Sistema.
struct PermissionsView: View {
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(LS("permissions-view.permisos-necesarios"))
                .font(.title.bold())

            PermissionRow(
                icon: "externaldrive",
                title: LS("permissions.removable.title"),
                explanation: LS("permissions.removable.body")
            )

            PermissionRow(
                icon: "lock.shield",
                title: LS("permissions.full-disk.title"),
                explanation: LS("permissions.full-disk.body")
            )

            PermissionRow(
                icon: "person.badge.key",
                title: LS("permissions.admin.title"),
                explanation: LS("permissions.admin.body")
            )

            Button(LS("permissions-view.abrir-ajustes-sistema-privacidad-segurid")) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.link)

            Spacer()

            BackContinueRow(onBack: onBack, continueTitle: LS("installer-wizard-view.continuar"), onContinue: onContinue)
        }
    }
}

private struct PermissionRow: View {
    let icon: String
    let title: String
    let explanation: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(explanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
