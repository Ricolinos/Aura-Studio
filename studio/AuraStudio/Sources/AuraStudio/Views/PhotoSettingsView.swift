import SwiftUI

struct PhotoSettingsView: View {
    @ObservedObject var preferences: AppPreferences

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
                Toggle("Organizar por categoría en la biblioteca", isOn: $preferences.organizePhotosByCategory)
                Text("Separa tus fotos en Imágenes, Fotos y Hechas con IA para encontrarlas más fácil DENTRO de Aura Studio (la categoría se sugiere sola al importar, y se puede corregir a mano en Biblioteca → Fotos). No cambia dónde quedan en el iPod: ahí siempre se copian juntas en \"Photos\", porque el visor del iPod todavía no navega por subcarpetas.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
