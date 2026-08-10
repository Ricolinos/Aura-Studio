import SwiftUI
import AppKit

/// LRCLIB (LRCLIBClient) ya resuelve letras sincronizadas gratis sin
/// ninguna key -- esta pantalla es estrictamente para el caso opcional
/// en que el usuario quiera complementar con Genius (metadata/
/// confirmacion) usando su propia cuenta de desarrollador, tal como
/// pide el brief ("opcional con API key propia + asistente").
struct APIKeySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var geniusKey: String = ""
    private let store = APIKeyStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Fuentes de letras")
                .font(.title2.bold())

            Text("Por defecto, Aura Studio ya busca letras sincronizadas gratis en LRCLIB, sin ninguna configuracion. Esto es opcional, solo si LRCLIB no encuentra una cancion y queres complementar con Genius usando tu propia cuenta.")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Genius API Client Access Token").font(.headline)
                SecureField("Pegá tu token aca", text: $geniusKey)
                    .textFieldStyle(.roundedBorder)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Como conseguir uno:").font(.callout.bold())
                    Text("1. Entra a genius.com/api-clients y creá una cuenta de desarrollador.")
                    Text("2. Creá un \"New API Client\" (el nombre y la URL pueden ser cualquiera).")
                    Text("3. Copiá el \"Client Access Token\" que te genera y pegalo aca arriba.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Button("Abrir genius.com/api-clients") {
                    if let url = URL(string: "https://genius.com/api-clients") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Guardar") {
                    if !geniusKey.isEmpty {
                        store.save(geniusKey, for: .genius)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                Button("Cerrar") { dismiss() }
            }
        }
        .padding(28)
        .frame(width: 480)
        .onAppear {
            geniusKey = store.load(.genius) ?? ""
        }
    }
}
