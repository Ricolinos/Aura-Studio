import SwiftUI
import AppKit

/// "Antes de sincronizar" (PLAN-general-sync.md §0.1/§1.2): la única
/// hoja que interrumpe el clic de Sincronizar, y solo cuando
/// `DeviceSyncIndex.hasConflicts` es real -- sin conflictos, sincronizar
/// sigue siendo un solo clic. Los dos defaults son los seguros de la
/// spec: "conservar los del iPod" y "no quitar huérfanos".
struct SyncConflictSheet: View {
    let index: DeviceSyncIndex
    let onCancel: () -> Void
    let onConfirm: (LibraryViewModel.ConflictResolution) -> Void

    @State private var replaceModified = false
    @State private var removeOrphans = false

    private var modifiedSourcePaths: [String] {
        index.states.filter { $0.value == .modifiedOnDevice }.keys.sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(LS("sync-sheets.antes-sincronizar"))
                .font(.title3.bold())

            if !modifiedSourcePaths.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(LSf("sync-sheets.archivo-s-se-modificaron-ipod-fuera", modifiedSourcePaths.count))
                        .font(.callout)
                    Picker("", selection: $replaceModified) {
                        Text(LS("sync-sheets.conservar-ipod")).tag(false)
                        Text(LS("sync-sheets.reemplazar-con-biblioteca")).tag(true)
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                }
            }

            if !index.orphanedRecords.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(LSf("sync-sheets.quitar-ipod-elemento-s-que-ya", index.orphanedRecords.count),
                           isOn: $removeOrphans)
                    Text(LS("sync-sheets.se-eliminaran-ipod-tu-biblioteca-mac"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                Button(LS("background-task-center-indicator.cancelar"), action: onCancel)
                Button(LS("device-activity-bar.sincronizar")) {
                    var resolution = LibraryViewModel.ConflictResolution()
                    if replaceModified {
                        resolution.forceRecopySourcePaths = Set(modifiedSourcePaths)
                    }
                    if removeOrphans {
                        resolution.removeOrphanedSourcePaths = Set(index.orphanedRecords.map(\.sourcePath))
                    }
                    onConfirm(resolution)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}

/// "Contenido solo en el iPod" (PLAN-general-sync.md §1.6): archivos
/// que Aura Studio nunca escribió -- nunca se tocan solos (§0.1). El
/// usuario elige, por archivo, importarlos a la biblioteca (reusa
/// `LibraryViewModel.addDroppedFiles`, el volumen montado es una ruta
/// de Finder como cualquier otra) o eliminarlos del iPod, con
/// confirmación explícita para lo destructivo.
struct ForeignContentSheet: View {
    let volumeRoot: URL
    let files: [ForeignDeviceFile]
    @ObservedObject var library: LibraryViewModel
    let onDismiss: () -> Void
    let onDeleted: () -> Void

    @State private var selection = Set<ForeignDeviceFile.ID>()
    @State private var pendingDeletion: Set<ForeignDeviceFile.ID>?
    @State private var importedCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(LS("sync-sheets.contenido-solo-ipod"))
                    .font(.title3.bold())
                Spacer()
                Button(LS("automatic-update-view.listo"), action: onDismiss)
            }
            .padding()

            Text(LS("sync-sheets.aura-studio-nunca-escribio-estos-archivo"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.bottom, 8)

            if importedCount > 0 {
                Text(LSf("sync-sheets.archivo-s-importado-s-revisalos-musica", importedCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
            }

            List(files, selection: $selection) { file in
                HStack {
                    Text(file.relativePath)
                    Spacer()
                    Text(byteString(file.size)).foregroundStyle(.secondary)
                }
            }

            HStack {
                Button(LS("sync-sheets.importar-biblioteca")) { importSelected() }
                    .disabled(selection.isEmpty)
                Button(LS("sync-sheets.eliminar-ipod"), role: .destructive) { pendingDeletion = selection }
                    .disabled(selection.isEmpty)
                Spacer()
            }
            .padding()
        }
        .frame(width: 520, height: 420)
        .alert(
            "¿Eliminar \(pendingDeletion?.count ?? 0) archivo(s) del iPod?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })
        ) {
            Button(LS("background-task-center-indicator.cancelar"), role: .cancel) { pendingDeletion = nil }
            Button(LS("artists-view.eliminar"), role: .destructive) { deleteConfirmed() }
        } message: {
            Text(LS("sync-sheets.esta-accion-no-se-puede-deshacer"))
        }
    }

    private func importSelected() {
        let urls = selection.map { volumeRoot.appendingPathComponent($0) }
        library.addDroppedFiles(urls)
        importedCount += urls.count
        selection.removeAll()
    }

    private func deleteConfirmed() {
        guard let toDelete = pendingDeletion else { return }
        for relative in toDelete {
            try? FileManager.default.removeItem(at: volumeRoot.appendingPathComponent(relative))
        }
        pendingDeletion = nil
        selection.subtract(toDelete)
        onDeleted()
    }

    private func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
