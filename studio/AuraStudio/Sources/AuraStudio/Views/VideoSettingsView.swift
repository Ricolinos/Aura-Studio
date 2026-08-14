import SwiftUI

struct VideoSettingsView: View {
    @ObservedObject var preferences: AppPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Organizar por categoría en la biblioteca", isOn: $preferences.organizeVideosByCategory)
                Text("Separa tus videos en Videos, Series y Películas para encontrarlos más fácil DENTRO de Aura Studio (la categoría se sugiere sola por duración al importar -- salvo \"Series\", que no tiene una heurística confiable y siempre se asigna a mano -- y se puede corregir en Biblioteca → Video). No cambia dónde quedan en el iPod: ahí siempre se copian juntos en \"Videos\", porque el reproductor del iPod todavía no navega por subcarpetas.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Formato de video").font(.headline)
                Text("Todo video se convierte a 320x240 MPEG-1/2 al sincronizar -- es el único formato que el iPod con Aura puede reproducir a velocidad completa (el chip de este iPod no puede decodificar H.264 ni formatos modernos). No es una preferencia: es una limitación real del hardware de 2007, así que aquí no hay nada que elegir.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
