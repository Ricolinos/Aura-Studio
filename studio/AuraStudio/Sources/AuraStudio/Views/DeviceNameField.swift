import SwiftUI

/// Nombre del iPod, editable con un clic (PLAN-general-sync.md §1.5).
/// Enter confirma, Esc cancela sin guardar -- mismo patron de edicion
/// in-place que ya usa el resto de la app (p. ej. "Cambiar nombre..."
/// de la biblioteca, `RenameSheet`), pero directo en la fila en vez de
/// una hoja aparte: es un solo campo de texto corto.
struct DeviceNameField: View {
    let name: String
    let onRename: (String) -> Void

    @State private var isEditing = false
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        if isEditing {
            TextField("Nombre del iPod", text: $draft)
                .textFieldStyle(.roundedBorder)
                .font(.title3.bold())
                .frame(maxWidth: 260)
                .focused($isFocused)
                .onAppear {
                    draft = name
                    isFocused = true
                }
                .onSubmit(commit)
                .onExitCommand { isEditing = false }
                .onChange(of: isFocused) { focused in
                    // Perder el foco (clic afuera) confirma, igual que
                    // el resto de los campos in-place de la app -- no
                    // deja el campo abierto "colgado" si el usuario
                    // sigue de largo sin apretar Enter.
                    if !focused, isEditing { commit() }
                }
        } else {
            Text(name)
                .font(.title2.bold())
                .onTapGesture {
                    draft = name
                    isEditing = true
                }
                .help("Haz clic para cambiar el nombre del iPod")
        }
    }

    private func commit() {
        isEditing = false
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != name else { return }
        onRename(trimmed)
    }
}
