import SwiftUI
import AppKit

/// ST-074: sección "GitHub (repos privados)" de Ajustes › General.
///
/// Los repositorios del firmware son privados; sin un token de solo
/// lectura en el Llavero, `AuraUpdateChecker` no puede saber si hay
/// una versión nueva (GitHub responde 404). Aquí el usuario pega el
/// token, lo guarda en el Llavero (`GitHubToken`), lo quita y lo
/// prueba contra el repo de Aura. La instalación del firmware NO
/// depende de esto: los binarios van embebidos en la app.
///
/// ST-053: ningún botón queda gris sin explicación -- "Guardar" y
/// "Probar" responden siempre y dicen en pantalla por qué no pudieron.
/// ST-054: sin `.fixedSize(horizontal: false, vertical: true)` en los
/// textos (en Release deja la ventana en blanco).
struct GitHubTokenSettingsView: View {
    @State private var tokenText: String = ""
    @State private var isSaved: Bool = false
    @State private var saveMessage: Message?
    @State private var testMessage: Message?
    @State private var isTesting = false

    struct Message {
        let text: String
        let isError: Bool
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("GitHub (repos privados)").font(.headline)
                if isSaved {
                    Label("Token en el Llavero", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                }
                Spacer()
                Button {
                    NSWorkspace.shared.open(URL(string: "https://github.com/settings/personal-access-tokens/new")!)
                } label: {
                    Label("Crear el token en GitHub", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.caption)
            }

            Text("Los repositorios del firmware son privados. Sin este token, Aura Studio no puede avisarte cuando hay una versión nueva; instalar el firmware sigue funcionando igual, porque viene incluido en la app.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Crea un fine-grained token en github.com › Settings › Developer settings con acceso solo a Aura-Firmware, Metro-Aura y moonlit-aura y permiso Contents: Read-only. Solo se usa para consultar si hay versiones nuevas.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                SecureField("Pega el token aquí (github_pat_… o ghp_…)", text: $tokenText)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: tokenText) { _, _ in saveMessage = nil }
                Button("Guardar") { save() }
                if isSaved {
                    Button("Quitar", role: .destructive) {
                        GitHubToken.delete()
                        tokenText = ""
                        isSaved = false
                        testMessage = nil
                        saveMessage = Message(text: "Token quitado del Llavero.", isError: false)
                    }
                }
                Button {
                    test()
                } label: {
                    if isTesting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Probar")
                    }
                }
                .disabled(isTesting)
                .help("Consulta los Releases de Aura-Firmware con el token guardado y muestra la versión más nueva")
            }

            if let saveMessage {
                Text(saveMessage.text)
                    .font(.caption)
                    .foregroundStyle(saveMessage.isError ? Color.red : Color.secondary)
            }
            if let testMessage {
                Text(testMessage.text)
                    .font(.caption)
                    .foregroundStyle(testMessage.isError ? Color.red : Color.secondary)
            }
        }
        .onAppear {
            isSaved = GitHubToken.hasToken()
            if isSaved, GitHubReleaseChecker.lastAuthFailure {
                testMessage = Message(text: "El token no es válido o expiró. Crea uno nuevo y guárdalo.", isError: true)
            }
        }
    }

    private func save() {
        let trimmed = tokenText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            saveMessage = Message(text: "Pega el token en el campo antes de guardar.", isError: true)
            return
        }
        guard GitHubToken.validateFormat(trimmed) else {
            saveMessage = Message(text: "Eso no parece un token de GitHub: debe empezar con github_pat_ o ghp_ y no llevar espacios.", isError: true)
            return
        }
        GitHubToken.save(trimmed)
        GitHubReleaseChecker.lastAuthFailure = false
        tokenText = ""
        isSaved = true
        testMessage = nil
        saveMessage = Message(text: "Guardado en el Llavero.", isError: false)
    }

    private func test() {
        isTesting = true
        testMessage = nil
        let token = GitHubToken.load()
        Task { @MainActor in
            defer { isTesting = false }
            do {
                let releases = try await GitHubReleaseChecker.fetchReleases(family: .aura, token: token)
                if GitHubReleaseChecker.lastAuthFailure {
                    testMessage = Message(text: "GitHub rechazó el token: no es válido, expiró o no tiene acceso a Aura-Firmware.", isError: true)
                } else if let latest = GitHubReleaseChecker.pickLatest(from: releases, includePrereleases: true) {
                    testMessage = Message(text: "Funciona. Versión más nueva de Aura: \(latest.tagName).", isError: false)
                } else {
                    testMessage = Message(text: "GitHub respondió, pero no hay ningún Release con versión reconocible.", isError: true)
                }
            } catch {
                if token == nil {
                    testMessage = Message(text: "No hay token guardado y el repositorio es privado: GitHub no devolvió nada. Pega y guarda un token primero.", isError: true)
                } else {
                    testMessage = Message(text: "No se pudo consultar GitHub (¿sin conexión?): \(error.localizedDescription)", isError: true)
                }
            }
        }
    }
}
