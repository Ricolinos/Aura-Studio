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
            Text("Permisos necesarios")
                .font(.title.bold())

            PermissionRow(
                icon: "externaldrive",
                title: "Acceso a volumenes removibles",
                explanation: "Aura Studio necesita ver y desmontar el iPod apenas lo conectas -- si no, macOS lo deja montado en Finder y el instalador no puede escribir en el. macOS pide confirmar esto la primera vez que la app intenta acceder a un disco removible."
            )

            PermissionRow(
                icon: "lock.shield",
                title: "Acceso total al disco (opcional, recomendado)",
                explanation: "Si macOS bloquea la lectura/escritura del iPod incluso despues de aceptar el permiso anterior, activa Acceso total al disco para Aura Studio en Ajustes del Sistema > Privacidad y Seguridad. Es un permiso amplio: solo lo necesitas si el paso de deteccion falla."
            )

            PermissionRow(
                icon: "person.badge.key",
                title: "Contraseña de administrador (en pasos puntuales)",
                explanation: "En algunos pasos -- pausar servicios que interfieren con la deteccion del iPod, o preparar el disco antes de instalar -- macOS te va a pedir tu contraseña con su propio dialogo nativo. Aura Studio siempre te explica antes que va a hacer y por que, en una pantalla propia, antes de que aparezca ese dialogo. Nunca vas a necesitar abrir Terminal ni escribir ningun comando."
            )

            Button("Abrir Ajustes del Sistema (Privacidad y Seguridad)") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.link)

            Spacer()

            BackContinueRow(onBack: onBack, continueTitle: "Continuar", onContinue: onContinue)
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
