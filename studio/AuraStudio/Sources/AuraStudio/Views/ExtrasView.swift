import SwiftUI

/// Seccion Extras: lo que el firmware ofrece mas alla de la biblioteca
/// (juegos, temas, utilidades).
///
/// Hoy esta deliberadamente casi vacia y lo dice de frente en vez de
/// inventar filas: los juegos y el cronometro se decidieron NO
/// implementar (D-063) y los temas son dos, fijos, que se eligen en el
/// propio dispositivo. A medida que el firmware gane extras reales, cada
/// uno aparece aca -- pero la seccion no va a mostrar nada que el
/// dispositivo no tenga de verdad.
struct ExtrasView: View {
    let device: AuraDevice?
    @State private var showingThemes = false
    @State private var showingLicenses = false
    /// ST-047: la eleccion de firmware vive aqui (encargo del dueño: "en
    /// la seccion de Extras es donde vamos a poner la opcion para que el
    /// usuario pueda decidir que firmware instalar").
    @ObservedObject private var preferences = AppPreferences.shared

    /// D-289 / ST-003: "Temas" ahora abre la gestión real (instalar,
    /// activar, eliminar, construir) -- necesita un iPod con Aura
    /// montado, mismo criterio que el resto de las acciones que
    /// escriben en el dispositivo.
    private var canManageThemes: Bool {
        guard let device else { return false }
        return device.supportsAuraContract
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                firmwareChoice
                Divider()
                available
                Divider()
                planned
                Divider()
                licenses
            }
            .padding(24)
            .frame(maxWidth: 560, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .navigationTitle("Extras")
        .sheet(isPresented: $showingThemes) {
            if let device, device.supportsAuraContract {
                ThemesView(mountPath: device.mountPath)
            }
        }
        .sheet(isPresented: $showingLicenses) {
            LicensesView()
        }
    }

    /// ST-047: cual de los dos firmwares instala el asistente. Es una
    /// PREFERENCIA, no una accion: elegir aqui no toca el iPod -- el
    /// Instalador (seccion propia, con su flasheo y sus confirmaciones) es
    /// el unico que escribe. Una actualizacion desde General ignora esto y
    /// reinstala la familia que ya esta en el aparato.
    private var firmwareChoice: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Firmware").font(.headline)
            Text("Elige cuál de los dos firmwares instala Aura Studio la próxima vez que uses el Instalador. Los dos son software libre (GPL v2), derivados de Rockbox, y comparten la misma biblioteca: tu música, fotos y videos se sincronizan igual con cualquiera.")
                .font(.callout)
                .foregroundStyle(.secondary)
            FirmwareChoiceCard(
                family: .aura,
                icon: "sparkles",
                explanation: "Lenguaje visual \"Apple 2026\": tipografías SF, temas claro/oscuro y temas instalables, Cover Flow.",
                isSelected: preferences.firmwareFamilyToInstall == .aura
            ) { preferences.firmwareFamilyToInstall = .aura }
            FirmwareChoiceCard(
                family: .metro,
                icon: "square.grid.2x2",
                explanation: "Lenguaje visual Metro (Windows Phone 7 / Zune): tipografía Selawik, hub de tiles, acentos de color, transiciones de pivote.",
                isSelected: preferences.firmwareFamilyToInstall == .metro
            ) { preferences.firmwareFamilyToInstall = .metro }
            if let device, device.supportsAuraContract {
                let installed = device.declaredFamily
                let chosen = preferences.firmwareFamilyToInstall
                Text(installed == chosen
                     ? "Tu iPod ya tiene \(installed.displayName). Instalar de nuevo lo reinstala conservando sus ajustes."
                     : "Tu iPod tiene \(installed.displayName). Instalar \(chosen.displayName) lo reemplaza: tu biblioteca se conserva, los ajustes de \(installed.displayName) no.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// ST-047 / CONTRATO §B: la pantalla que el contrato promete desde
    /// v1 y no existia. Obligatoria en cuanto Studio distribuye un
    /// segundo firmware GPL.
    private var licenses: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Licencias").font(.headline)
            Button {
                showingLicenses = true
            } label: {
                row("Software libre incluido", "doc.text",
                    "Aura y Metro son GPL v2. Aquí están sus fuentes, versiones exactas y cambios.")
            }
            .buttonStyle(.plain)
        }
    }

    private var available: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Disponible en el dispositivo").font(.headline)
            Button {
                showingThemes = true
            } label: {
                row("Temas", "circle.lefthalf.filled",
                    canManageThemes
                        ? "Tema integrado (Claro/Oscuro) más los que instales -- Ajustes > Estilo, en el iPod."
                        : "Conecta tu iPod con Aura instalado para instalar, activar o construir temas.")
            }
            .buttonStyle(.plain)
            .disabled(!canManageThemes)
            row("Animaciones y graficos", "wand.and.rays",
                "Tres niveles cada uno. Se eligen en Ajustes, en el iPod.")
        }
    }

    private var planned: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Todavia no").font(.headline)
            Text("Estos extras del iPod original no estan implementados en Aura. Cuando existan, se van a poder gestionar desde aca.")
                .font(.callout)
                .foregroundStyle(.secondary)
            row("Juegos", "gamecontroller",
                "No implementados.", muted: true)
            row("Cronometro y bloqueo de pantalla", "stopwatch",
                "No implementados.", muted: true)
        }
    }

    private func row(_ title: String, _ symbol: String, _ detail: String,
                     muted: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 22)
                .foregroundStyle(muted ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(muted ? .secondary : .primary)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

/// ST-047: tarjeta-radio del selector de firmware -- la forma que el
/// instalador usaba para una eleccion excluyente con explicacion
/// (`BootModeCard`, retirada en ST-050 junto con el paso de modo de
/// arranque).
private struct FirmwareChoiceCard: View {
    let family: FirmwareFamily
    let icon: String
    let explanation: String
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(family.displayName).font(.headline)
                        if let tag = BundledArtifacts.forFamily(family).releaseTag {
                            Text(tag)
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    Text(explanation)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(isSelected ? 0.12 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}
