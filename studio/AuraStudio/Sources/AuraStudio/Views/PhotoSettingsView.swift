import SwiftUI

struct PhotoSettingsView: View {
    @ObservedObject var preferences: AppPreferences
    /// D-228: nombre en edicion en el campo "Agregar" de abajo -- vive
    /// aca (no en `AppPreferences`) porque es estado de la UI, no de la
    /// biblioteca.
    @State private var newCollectionName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Calidad de imagen").font(.headline)
                Picker("Calidad de imagen", selection: $preferences.photoQuality) {
                    Text("Optimizar espacio (320px, recomendado)").tag(AppPreferences.PhotoQuality.optimized)
                    Text("Versión HD (640px)").tag(AppPreferences.PhotoQuality.hd)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                Text("La pantalla del iPod es de 320x240 -- una foto de una cámara o teléfono actual pesa decenas de veces más de lo que esa pantalla puede mostrar. \"Optimizar espacio\" reduce cada foto a 320px de lado mayor, el ancho nativo de la pantalla. \"Versión HD\" la deja en 640px: se ve un poco más nítida al hacer zoom en el visor, a cambio de más espacio en el iPod. En ambos casos se guarda como JPEG comprimido, nunca la foto original completa.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Toggle("Organizar por colección en la biblioteca", isOn: $preferences.organizePhotosByCategory)
                Text("Separa tus fotos en colecciones (Imágenes, Fotos e IA por defecto, editables abajo) para encontrarlas más fácil DENTRO de Aura Studio -- la colección se sugiere sola al importar, y se puede corregir a mano en Biblioteca → Fotos. Con este ajuste activo, cada colección es ademas una carpeta dentro de \"Imágenes\" en la carpeta local de la biblioteca (Finder). No cambia dónde quedan en el iPod: ahí siempre se copian juntas en \"Photos\", porque el visor del iPod todavía no navega por subcarpetas.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                collectionsList
            }
        }
    }

    /// Lista editable de colecciones (D-228, encargo del dueño: a
    /// diferencia de las categorías de video, estas se pueden agregar/
    /// quitar sin tocar código). Quitar una no des-etiqueta las fotos
    /// que ya la tenían asignada -- ver `AppPreferences.
    /// removePhotoCollection`.
    private var collectionsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(preferences.photoCollections, id: \.self) { name in
                HStack {
                    Text(name)
                    Spacer()
                    Button {
                        preferences.removePhotoCollection(name)
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }

            HStack {
                TextField("Nueva colección", text: $newCollectionName)
                    .textFieldStyle(.roundedBorder)
                Button("Agregar") {
                    preferences.addPhotoCollection(newCollectionName)
                    newCollectionName = ""
                }
                .disabled(newCollectionName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.top, 4)
    }
}
