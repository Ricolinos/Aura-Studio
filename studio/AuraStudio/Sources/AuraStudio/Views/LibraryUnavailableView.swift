import AppKit
import SwiftUI

/// ST-189 (paridad con Windows ST-171): lo que se ve cuando el disco de
/// la biblioteca no está conectado.
///
/// **Va encima de la sección, no en su lugar.** Cuando el disco vuelve,
/// esto se apaga y debajo está todo como estaba. Y no lo llevan el
/// Instalador ni Extras ni Ajustes, a propósito: no necesitan la
/// biblioteca, y son justamente lo que alguien puede querer usar con el
/// disco desconectado. Eso es lo que evita que un disco ausente
/// convierta la app en un cartel.
///
/// Dice **la ruta completa** (para reconocer CUÁL biblioteca falta, si
/// se usa más de una) y responde de entrada la pregunta que se hace
/// cualquiera al ver una biblioteca vacía: no se perdió nada.
struct LibraryUnavailableView: View {
    let libraryPath: String
    let onRetry: () -> Void
    let onChooseAnother: () -> Void
    let onCreateNew: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var volumeName: String? {
        LibraryRoot.expectedVolumeName(of: URL(fileURLWithPath: libraryPath, isDirectory: true))
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "externaldrive.badge.questionmark")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)

            Text(volumeName.map { "El disco «\($0)» no está conectado" }
                 ?? "La biblioteca está en un disco que no está conectado")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)

            Text("No se perdió nada: tu catálogo y tus archivos siguen en ese disco. "
                 + "Aura Studio no va a tocar nada hasta que vuelva a estar disponible.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)

            Text(libraryPath)
                .font(.callout.monospaced())
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.secondary.opacity(0.10)))

            HStack(spacing: 10) {
                Button("Reintentar", action: onRetry)
                    .keyboardShortcut(.defaultAction)
                Button("Elegir otra biblioteca...", action: onChooseAnother)
                Button("Crear una nueva", action: onCreateNew)
            }
            .padding(.top, 4)

            Text("El Instalador y Extras siguen funcionando sin la biblioteca.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}

extension View {
    /// Pone `LibraryUnavailableView` encima mientras falte el disco.
    ///
    /// ST-189: la vista de abajo se sigue construyendo -- eso es lo que
    /// hace que al volver el disco no haya que rearmar nada, solo dejar
    /// de tapar.
    func libraryUnavailableOverlay(_ availability: LibraryAvailability,
                                   libraryPath: String,
                                   onRetry: @escaping () -> Void,
                                   onChooseAnother: @escaping () -> Void,
                                   onCreateNew: @escaping () -> Void) -> some View {
        overlay {
            if availability == .volumeMissing {
                LibraryUnavailableView(libraryPath: libraryPath,
                                       onRetry: onRetry,
                                       onChooseAnother: onChooseAnother,
                                       onCreateNew: onCreateNew)
            }
        }
    }
}
