import SwiftUI
import AppKit

/// Donde el usuario carga sus propias API keys para las fuentes
/// opcionales (encargo del dueño, 2026-08-13: "crear las guías y
/// configuraciones para instalar API Keys de los servicios ligados que
/// potenciarían la biblioteca"). Complementa a `SourcesSettingsView`
/// (que explica QUE es cada fuente y POR QUE): esta vista es DONDE se
/// carga la credencial. Guardado real en Keychain via `APIKeyStore` --
/// nunca en UserDefaults.
struct APIKeysSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Estas claves son opcionales: la biblioteca funciona sin ninguna (ver la pestaña Fuentes). Cárgalas solo si te faltan portadas u otro contenido que una fuente con key pueda completar.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(APIKeyService.allCases) { service in
                APIKeyRow(service: service)
                Divider()
            }
        }
    }
}

private struct APIKeyRow: View {
    let service: APIKeyService

    @State private var keyText: String = ""
    @State private var isSaved: Bool = false
    @State private var showGuide: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(service.displayName).font(.headline)
                if isSaved {
                    Label("Guardada", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                Spacer()
                Button {
                    NSWorkspace.shared.open(service.guideURL)
                } label: {
                    Label("Cómo conseguirla", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.caption)
            }

            Text(service.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(service.guideText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                SecureField("Pega tu API key aquí", text: $keyText)
                    .textFieldStyle(.roundedBorder)
                Button("Guardar") {
                    let trimmed = keyText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    APIKeyStore.save(trimmed, for: service)
                    isSaved = true
                }
                .disabled(keyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if isSaved {
                    Button("Quitar", role: .destructive) {
                        APIKeyStore.delete(for: service)
                        keyText = ""
                        isSaved = false
                    }
                }
            }
        }
        .onAppear {
            isSaved = APIKeyStore.hasKey(for: service)
        }
    }
}
