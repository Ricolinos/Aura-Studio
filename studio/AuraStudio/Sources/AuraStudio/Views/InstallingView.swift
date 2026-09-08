import SwiftUI

struct InstallingView: View {
    let mode: InstallerMode
    let message: String
    /// ST-047/ST-050: "Aura" o "Metro", lo que se esté instalando. Antes
    /// el título decía "Instalando Aura" siempre -- con Metro elegido en
    /// Extras, la pantalla nombraba un firmware que no era el que se
    /// estaba copiando.
    var firmwareName: String = "Aura"

    private var title: String {
        switch mode {
        case .install: return LSf("installing.title.install", firmwareName)
        case .restore: return LS("installing.title.restore")
        // ST-143: no dice "Instalando" porque no se instala nada -- solo
        // se regraba el arranque, y el disco no se toca.
        case .updateBootloader: return LS("installing.title.update-bootloader")
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
            Text(LS("installing-view.no-desconectes-ipod-ni-cierres-aura"))
                .font(.callout)
                .foregroundStyle(.orange)
        }
    }
}
