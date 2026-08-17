import SwiftUI
import AppKit

/// Gestión de temas del iPod conectado -- lista los instalados, activa,
/// elimina, y construye/instala uno nuevo desde una carpeta de assets ya
/// generados (Fase 2A, `PLAN-themes-impl.md` Q4). Presentada como hoja
/// desde `ExtrasView` ("Temas"): la app no tiene un patrón de navegación
/// por `NavigationStack`/`NavigationLink` en ningún otro lado, así que
/// no se introduce uno nuevo solo para esto.
@MainActor
final class ThemesViewModel: ObservableObject {
    @Published var installed: [InstalledTheme] = []
    @Published var activeID: String = "default"
    @Published var isBusy = false
    @Published var errorMessage: String?

    let mountPath: String

    init(mountPath: String) {
        self.mountPath = mountPath
        refresh()
    }

    func refresh() {
        installed = ThemeInstaller.listInstalled(mountPath: mountPath)
        activeID = ThemeInstaller.activeThemeID(mountPath: mountPath)
    }

    func activate(id: String) {
        do {
            try ThemeInstaller.activate(id: id, mountPath: mountPath)
            activeID = id
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(id: String) {
        do {
            if activeID == id {
                try ThemeInstaller.activate(id: "default", mountPath: mountPath)
                activeID = "default"
            }
            try ThemeInstaller.delete(id: id, mountPath: mountPath)
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func buildAndInstall(sourceFolder: URL, name: String, author: String, isRestrictedLicense: Bool) async {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else {
            errorMessage = "Ponle un nombre al tema."
            return
        }
        let id = Self.suggestID(from: trimmedName)
        guard AuraThemeID.isValid(id) else {
            errorMessage = "\"\(trimmedName)\" no produce un id válido -- usa letras, números y espacios."
            return
        }

        isBusy = true
        defer { isBusy = false }

        let manifest = AuraThemeManifest(
            id: id, name: trimmedName, author: author.trimmingCharacters(in: .whitespaces),
            license: isRestrictedLicense ? .personal : .open,
            redistributable: !isRestrictedLicense
        )
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("AuraThemeBuild-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        do {
            try ThemePackager.package(sourceRoot: sourceFolder, manifest: manifest, destinationRoot: tempRoot)
            _ = try await ThemeInstaller.install(packageRoot: tempRoot, mountPath: mountPath)
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// De "Apple (uso personal)" a "apple-uso-personal" -- letras/números
    /// en minúscula, todo lo demás colapsa a un solo "-", sin guiones al
    /// final. `AuraThemeID.isValid()` es quien de verdad decide si sirve.
    private static func suggestID(from name: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789")
        var result = ""
        var lastWasDash = false
        for scalar in name.lowercased().unicodeScalars {
            if allowed.contains(scalar) {
                result.unicodeScalars.append(scalar)
                lastWasDash = false
            } else if !lastWasDash && !result.isEmpty {
                result.append("-")
                lastWasDash = true
            }
        }
        while result.hasSuffix("-") { result.removeLast() }
        if result.count > AuraThemeID.maxLength { result = String(result.prefix(AuraThemeID.maxLength)) }
        return result
    }
}

struct ThemesView: View {
    @StateObject private var viewModel: ThemesViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingBuildSheet = false
    @State private var pendingDelete: InstalledTheme?

    init(mountPath: String) {
        _viewModel = StateObject(wrappedValue: ThemesViewModel(mountPath: mountPath))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row(id: "default", name: "Aura", loadable: true, reason: nil, isDefault: true)
                    ForEach(viewModel.installed) { theme in
                        row(id: theme.id, name: theme.name, loadable: theme.loadable, reason: theme.reason, isDefault: false)
                    }
                } footer: {
                    Text("Se aplican en el iPod al arrancar. Un tema que no carga (formato incompatible o archivos faltantes) aparece atenuado -- el firmware nunca finge soportar lo que no tiene.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Temas")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Construir tema nuevo…") { showingBuildSheet = true }
                        .disabled(viewModel.isBusy)
                }
            }
            .overlay {
                if viewModel.isBusy {
                    ProgressView("Construyendo e instalando…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .frame(minWidth: 480, minHeight: 360)
        .sheet(isPresented: $showingBuildSheet) {
            BuildThemeView { sourceFolder, name, author, restricted in
                showingBuildSheet = false
                Task { await viewModel.buildAndInstall(sourceFolder: sourceFolder, name: name, author: author, isRestrictedLicense: restricted) }
            }
        }
        .alert("No se pudo completar la operación", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("Entendido", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .confirmationDialog(
            "¿Eliminar \"\(pendingDelete?.name ?? "")\"?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Eliminar", role: .destructive) {
                if let theme = pendingDelete { viewModel.delete(id: theme.id) }
                pendingDelete = nil
            }
            Button("Cancelar", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Esto borra el tema del iPod. Si estaba activo, Aura vuelve a ser el tema integrado.")
        }
    }

    @ViewBuilder
    private func row(id: String, name: String, loadable: Bool, reason: String?, isDefault: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .foregroundStyle(loadable ? .primary : .secondary)
                if let reason, !loadable {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if viewModel.activeID == id {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
            }
        }
        .opacity(loadable ? 1 : 0.5)
        .contentShape(Rectangle())
        .onTapGesture {
            guard loadable, viewModel.activeID != id else { return }
            viewModel.activate(id: id)
        }
        .contextMenu {
            if !isDefault {
                Button("Eliminar", role: .destructive) {
                    pendingDelete = InstalledTheme(id: id, name: name, loadable: loadable)
                }
            }
        }
    }
}

/// Formulario para construir un tema desde una carpeta con el layout de
/// `design-system/out/` del firmware (o
/// `~/Aura-local/theme-apple-source/design-system-out/`, el primer caso
/// de uso real). Fase 2A: no rasteriza nada, solo reempaqueta lo que ya
/// existe en esa carpeta -- ver `ThemePackager`.
private struct BuildThemeView: View {
    let onSubmit: (_ sourceFolder: URL, _ name: String, _ author: String, _ restrictedLicense: Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var sourceFolder: URL?
    @State private var name = ""
    @State private var author = ""
    @State private var restrictedLicense = false

    var body: some View {
        Form {
            Section("Carpeta de origen") {
                HStack {
                    Text(sourceFolder?.path ?? "Ninguna elegida")
                        .foregroundStyle(sourceFolder == nil ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Elegir…") { chooseFolder() }
                }
                Text("Una carpeta con fonts/ e icons/masks/ ya generados -- por ejemplo, la salida de design-system/generate.py del firmware, o ~/Aura-local/theme-apple-source/design-system-out/.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Tema") {
                TextField("Nombre", text: $name)
                TextField("Autor (opcional)", text: $author)
            }
            Section {
                Toggle("Usa tipografías o símbolos con licencia restringida (por ejemplo, SF Pro o SF Symbols)", isOn: $restrictedLicense)
                if restrictedLicense {
                    Text("Este tema se construye solo para tu propio iPod: no lo compartas ni lo distribuyas -- la licencia de esos assets no lo permite fuera de tu dispositivo. Aura Studio nunca incluye ni descarga estos archivos; solo usa los que tu Mac ya tiene.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, minHeight: 360)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Construir e instalar") {
                    guard let sourceFolder else { return }
                    onSubmit(sourceFolder, name, author, restrictedLicense)
                }
                .disabled(sourceFolder == nil || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Elegir"
        panel.message = "Elige la carpeta con fonts/ e icons/masks/ ya generados."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        sourceFolder = url
    }
}
