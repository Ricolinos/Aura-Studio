import SwiftUI
import AppKit

/// ST-047 / CONTRATO-firmware-studio.md §B: la pantalla de "Licencias".
///
/// Aura Studio distribuye embebidos, sin modificarlos, los binarios de
/// los firmwares derivados de Rockbox (GPL v2) que embebe (`FirmwareFamily.installable`). La
/// GPL v2 §3 obliga a ofrecer la fuente de lo que se distribuye, y el
/// contrato fija exactamente como se cumple: por cada firmware, la URL
/// de su repositorio, el tag exacto que viene embebido y un enlace a su
/// `MODIFICATIONS.md` (el registro §2a de que se cambio respecto a
/// Rockbox). El contrato lo prometia desde v1 y la pantalla no existia
/// (`DECISIONS.md`, nota de D-290); con un segundo firmware GPL a bordo
/// dejo de ser opcional.
///
/// Todo lo que se muestra sale de lo que de verdad viaja en el bundle
/// (`BundledArtifacts.releaseTag`, que escribe scripts/fetch-firmware.sh)
/// -- nunca de una constante a mano que pueda quedarse vieja respecto a
/// lo que se empaqueto.
struct LicensesView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Licencias").font(.title2.bold())
                Spacer()
                Button("Listo") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Aura Studio es gratuita y se distribuye sin fines comerciales. Trae embebidos, tal cual se publicaron y sin modificarlos, los firmwares instalables para iPod Classic 6G, todos software libre bajo la Licencia Pública General de GNU versión 2 (GPL v2). Cada uno es un derivado de Rockbox; su código fuente completo, la versión exacta incluida aquí y el registro de cambios respecto a Rockbox están en los enlaces de abajo, como exige la sección 3 de esa licencia.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    ForEach(FirmwareFamily.installable, id: \.displayName) { family in
                        FamilyLicenseCard(family: family)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Rockbox").font(.headline)
                        Text("Todos los firmwares, su bootloader dual-boot y la herramienta de flasheo mks5lboot derivan del proyecto Rockbox (GPL v2). Aura Studio no modifica ninguno de esos binarios.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        LinkRow(title: "rockbox.org", url: URL(string: "https://www.rockbox.org/")!)
                        LinkRow(title: "Texto de la GPL v2", url: URL(string: "https://www.gnu.org/licenses/old-licenses/gpl-2.0.html")!)
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 560, idealWidth: 620, minHeight: 480, idealHeight: 600)
    }
}

private struct FamilyLicenseCard: View {
    let family: FirmwareFamily

    private var artifacts: BundledArtifacts { BundledArtifacts.forFamily(family) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(family.displayName).font(.headline)
                Text("GPL v2")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    .foregroundStyle(Color.accentColor)
            }
            if let tag = artifacts.releaseTag {
                Text("Versión incluida: \(tag)")
                    .font(.callout)
            } else {
                // Una build hecha sin scripts/fetch-firmware.sh no trae el
                // marcador: se dice, no se inventa un tag.
                Text("Versión incluida: no registrada en esta build")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let repo = family.repositoryURL {
                LinkRow(title: "Código fuente", url: repo)
                if let tag = artifacts.releaseTag,
                   let source = URL(string: "\(repo.absoluteString)/tree/\(tag)") {
                    LinkRow(title: "Fuente exacta de esta versión (\(tag))", url: source)
                }
                if let tag = artifacts.releaseTag,
                   let mods = URL(string: "\(repo.absoluteString)/releases/download/\(tag)/MODIFICATIONS.md") {
                    LinkRow(title: "Cambios respecto a Rockbox (MODIFICATIONS.md)", url: mods)
                }
                if let tag = artifacts.releaseTag,
                   let notices = URL(string: "\(repo.absoluteString)/releases/download/\(tag)/THIRD-PARTY-NOTICES.txt") {
                    LinkRow(title: "Avisos de terceros (tipografías e iconos)", url: notices)
                }
                // ST-150: los cuatro repos son públicos -- estos enlaces
                // son la oferta de fuente de GPL v2 §3 y cualquiera puede
                // abrirlos, sin cuenta de GitHub ni permiso alguno.
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.06)))
    }
}

private struct LinkRow: View {
    let title: String
    let url: URL

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.forward.square")
                Text(title)
                Spacer()
                Text(url.host ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
        }
        .buttonStyle(.link)
    }
}

#Preview {
    LicensesView()
}
