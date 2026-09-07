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
                Text(LS("photo-settings-view.calidad-imagen")).font(.headline)
                Picker(LS("photo-settings-view.calidad-imagen"), selection: $preferences.photoQuality) {
                    Text(LS("photo-settings-view.optimizar-espacio-320px-recomendado")).tag(AppPreferences.PhotoQuality.optimized)
                    Text(LS("photo-settings-view.version-hd-640px")).tag(AppPreferences.PhotoQuality.hd)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                Text(LS("photo-settings-view.pantalla-ipod-es-320x240-foto-camara"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Toggle(LS("photo-settings-view.organizar-por-coleccion-biblioteca"), isOn: $preferences.organizePhotosByCategory)
                Text(LS("photo-settings-view.separa-tus-fotos-colecciones-imagenes-fo"))
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
                Button(LS("music-settings-view.agregar")) {
                    preferences.addPhotoCollection(newCollectionName)
                    newCollectionName = ""
                }
                .disabled(newCollectionName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.top, 4)
    }
}
