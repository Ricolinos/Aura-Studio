import SwiftUI

struct InstallingView: View {
    let mode: InstallerMode
    let message: String

    private var title: String {
        switch mode {
        case .install: return "Instalando Aura..."
        case .restore: return "Restaurando iPod original..."
        // ST-143: no dice "Instalando" porque no se instala nada -- solo
        // se regraba el arranque, y el disco no se toca.
        case .updateBootloader: return "Actualizando el arranque..."
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .controlSize(.large)
            Text(title)
                .font(.title.bold())
            Text(message)
                .foregroundStyle(.secondary)
            Text("No desconectes el iPod ni cierres Aura Studio durante este paso.")
                .font(.callout)
                .foregroundStyle(.orange)
        }
    }
}
