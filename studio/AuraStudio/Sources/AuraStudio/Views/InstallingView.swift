import SwiftUI

struct InstallingView: View {
    let mode: InstallerMode
    let message: String

    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .controlSize(.large)
            Text(mode == .install ? "Instalando Aura..." : "Restaurando iPod original...")
                .font(.title.bold())
            Text(message)
                .foregroundStyle(.secondary)
            Text("No desconectes el iPod ni cierres Aura Studio durante este paso.")
                .font(.callout)
                .foregroundStyle(.orange)
        }
    }
}
