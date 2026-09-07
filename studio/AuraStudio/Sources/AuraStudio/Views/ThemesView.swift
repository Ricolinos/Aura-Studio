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
                    Text(LS("themes-view.se-aplican-ipod-al-arrancar-tema"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(LS("themes-view.temas"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LS("cover-contamination-sheet.cerrar")) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(LS("themes-view.construir-tema-nuevo")) { showingBuildSheet = true }
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
        .alert(LS("themes-view.no-se-pudo-completar-operacion"), isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button(LS("themes-view.entendido"), role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .confirmationDialog(
            "¿Eliminar \"\(pendingDelete?.name ?? "")\"?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button(LS("artists-view.eliminar"), role: .destructive) {
                if let theme = pendingDelete { viewModel.delete(id: theme.id) }
                pendingDelete = nil
            }
            Button(LS("background-task-center-indicator.cancelar"), role: .cancel) { pendingDelete = nil }
        } message: {
            Text(LS("themes-view.esto-borra-tema-ipod-si-estaba"))
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
                Button(LS("artists-view.eliminar"), role: .destructive) {
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
            Section(LS("themes-view.carpeta-origen")) {
                HStack {
                    Text(sourceFolder?.path ?? "Ninguna elegida")
                        .foregroundStyle(sourceFolder == nil ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button(LS("themes-view.elegir")) { chooseFolder() }
                }
                Text(LS("themes-view.carpeta-con-fonts-e-icons-masks"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section(LS("themes-view.tema")) {
                TextField("Nombre", text: $name)
                TextField("Autor (opcional)", text: $author)
            }
            Section {
                Toggle(LS("themes-view.usa-tipografias-o-simbolos-con-licencia"), isOn: $restrictedLicense)
                if restrictedLicense {
                    Text(LS("themes-view.este-tema-se-construye-solo-para"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, minHeight: 360)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(LS("background-task-center-indicator.cancelar")) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(LS("themes-view.construir-e-instalar")) {
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
