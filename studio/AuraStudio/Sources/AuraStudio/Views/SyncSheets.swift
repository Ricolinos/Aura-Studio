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
            Text("Antes de sincronizar")
                .font(.title3.bold())

            if !modifiedSourcePaths.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(modifiedSourcePaths.count) archivo(s) se modificaron en el iPod fuera de Aura Studio.")
                        .font(.callout)
                    Picker("", selection: $replaceModified) {
                        Text("Conservar los del iPod").tag(false)
                        Text("Reemplazar con la biblioteca").tag(true)
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                }
            }

            if !index.orphanedRecords.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Quitar del iPod los \(index.orphanedRecords.count) elemento(s) que ya no están en tu biblioteca",
                           isOn: $removeOrphans)
                    Text("Se eliminarán del iPod. Tu biblioteca en la Mac no cambia.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                Button("Cancelar", action: onCancel)
                Button("Sincronizar") {
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
                Text("Contenido solo en el iPod")
                    .font(.title3.bold())
                Spacer()
                Button("Listo", action: onDismiss)
            }
            .padding()

            Text("Aura Studio nunca escribió estos archivos -- no forman parte de tu biblioteca. Puedes importarlos (se copian a tu Mac y pasan a ser parte de tu biblioteca) o eliminarlos del iPod.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.bottom, 8)

            if importedCount > 0 {
                Text("\(importedCount) archivo(s) importado(s) -- revísalos en Música/Video/Fotos.")
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
                Button("Importar a la biblioteca") { importSelected() }
                    .disabled(selection.isEmpty)
                Button("Eliminar del iPod", role: .destructive) { pendingDeletion = selection }
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
            Button("Cancelar", role: .cancel) { pendingDeletion = nil }
            Button("Eliminar", role: .destructive) { deleteConfirmed() }
        } message: {
            Text("Esta acción no se puede deshacer.")
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
