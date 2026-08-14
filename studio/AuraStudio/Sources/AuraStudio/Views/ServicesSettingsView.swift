import SwiftUI
import AppKit

/// De donde saca Aura Studio metadata, caratulas y letras -- y como
/// configurarlos (D-203, encargo del dueño: "la pestaña fuentes...
/// debería llamarse 'servicios'... serviría para configurarlos, ya que
/// estén instalados"). Antes esta pestaña ("Fuentes") era puramente
/// informativa y las API keys vivian en una pestaña aparte que ningun
/// cliente de red consumia de verdad -- ahora cada fila de servicio
/// opcional trae su propio control (toggle o campo de key) y hay un
/// orden de prioridad real para resolver caratula, que es lo unico que
/// hoy tiene mas de un proveedor.
///
/// Criterio de eleccion de las fuentes en si (investigacion de agosto
/// 2026, ver D-069): todo lo que se usa por defecto funciona SIN API
/// key ni OAuth, para que la app sirva recien instalada. Lo que pide
/// key es siempre opcional. Y no se lista ninguna fuente cuyos terminos
/// de uso prohiban este caso -- una app personal que descarga y guarda
/// contenido para uso offline.
struct ServicesSettingsView: View {
    @ObservedObject var preferences: AppPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            active
            Divider()
            coverArtPriority
            Divider()
            optional
            Divider()
            rejected
        }
    }

    private var active: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Activos, sin configurar nada").font(.headline)
            SourceRow(
                state: .active,
                name: "MusicBrainz",
                role: "Metadata: artista, album, ano, numero de pista",
                detail: "Base abierta y colaborativa, datos en CC0. Sin key. Limite estricto de 1 pedido por segundo, ya respetado por la app.",
                url: "https://musicbrainz.org"
            )
            SourceRow(
                state: .active,
                name: "Cover Art Archive",
                role: "Caratulas de album",
                detail: "Sin key y sin limite de tasa. Primer intento para caratula (ver orden de busqueda abajo).",
                url: "https://coverartarchive.org"
            )
            SourceRow(
                state: .active,
                name: "LRCLIB",
                role: "Letras sincronizadas",
                detail: "Sin key ni registro. Devuelve LRC real con tiempos. Codigo abierto MIT.",
                url: "https://lrclib.net"
            )
        }
    }

    /// D-203: el unico caso real hoy de "varios servicios compiten por
    /// lo mismo" es la caratula (Cover Art Archive / fanart.tv / Deezer)
    /// -- se prueban en este orden y se usa la primera que encuentre
    /// algo. Reordenar con las flechas persiste de inmediato
    /// (`AppPreferences.coverArtProviderOrder`).
    private var coverArtPriority: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Orden de búsqueda de carátula").font(.headline)
            Text("Cuando a una canción le falta carátula, se prueban estos servicios en orden y se usa la primera imagen que aparezca.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                ForEach(Array(preferences.coverArtProviderOrder.enumerated()), id: \.element) { index, provider in
                    HStack(spacing: 10) {
                        Text("\(index + 1)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                            .frame(width: 16, alignment: .trailing)
                        Image(systemName: isUsable(provider) ? "checkmark.circle.fill" : "circle.dashed")
                            .foregroundStyle(isUsable(provider) ? .green : .secondary)
                        Text(provider.displayName)
                        if !isUsable(provider) {
                            Text(unusableReason(provider))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { move(provider, by: -1) } label: { Image(systemName: "chevron.up") }
                            .disabled(index == 0)
                        Button { move(provider, by: 1) } label: { Image(systemName: "chevron.down") }
                            .disabled(index == preferences.coverArtProviderOrder.count - 1)
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 6)
                    if provider != preferences.coverArtProviderOrder.last { Divider() }
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
        }
    }

    private func isUsable(_ provider: CoverArtProvider) -> Bool {
        switch provider {
        case .coverArtArchive: return true
        case .fanartTV: return APIKeyStore.hasKey(for: .fanartTV)
        case .deezer: return preferences.deezerEnabled
        }
    }

    private func unusableReason(_ provider: CoverArtProvider) -> String {
        switch provider {
        case .coverArtArchive: return ""
        case .fanartTV: return "sin key configurada abajo"
        case .deezer: return "apagado abajo"
        }
    }

    private func move(_ provider: CoverArtProvider, by offset: Int) {
        var order = preferences.coverArtProviderOrder
        guard let index = order.firstIndex(of: provider) else { return }
        let target = index + offset
        guard order.indices.contains(target) else { return }
        order.swapAt(index, target)
        preferences.coverArtProviderOrder = order
    }

    private var optional: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Opcionales").font(.headline)
            Text("Se agregan solo si te faltan caratulas: lo de arriba ya cubre el caso normal.")
                .font(.caption).foregroundStyle(.secondary)

            DeezerRow(preferences: preferences)
            Divider()
            APIKeyServiceRow(service: .fanartTV)
            Divider()
            SourceRow(
                state: .planned,
                name: "Internet Archive",
                role: "Musica, video y audio de dominio publico",
                detail: "Sin key para buscar y descargar. Sirve para ENCONTRAR contenido nuevo de dominio publico, no para completar metadata de tu biblioteca -- todavia no tiene ninguna integracion en Aura Studio.",
                url: "https://archive.org"
            )
            SourceRow(
                state: .planned,
                name: "Openverse / Wikimedia Commons",
                role: "Fotos con licencia libre",
                detail: "Sin registro. Mismo caso que Internet Archive: es para buscar fotos nuevas, no para enriquecer canciones -- todavia sin conectar.",
                url: "https://openverse.org"
            )
        }
    }

    private var rejected: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Descartadas, y por que").font(.headline)
            Text("Se investigaron y NO se van a integrar. Queda escrito para no volver a evaluarlas.")
                .font(.caption).foregroundStyle(.secondary)
            SourceRow(
                state: .rejected,
                name: "Genius",
                role: "Letras",
                detail: "Su API oficial no tiene letras, ni sincronizadas ni planas: la unica via es scrapear la web, contra sus terminos.",
                url: "https://genius.com"
            )
            SourceRow(
                state: .rejected,
                name: "Musixmatch",
                role: "Letras sincronizadas",
                detail: "El plan gratuito solo devuelve un fragmento de vista previa; las letras completas y sincronizadas requieren licencia comercial paga.",
                url: "https://developer.musixmatch.com"
            )
            SourceRow(
                state: .rejected,
                name: "Spotify",
                role: "Metadata y caratulas",
                detail: "Exige OAuth y, desde 2026, cuenta Premium activa del desarrollador con usuarios en lista blanca. Inviable para una app personal.",
                url: "https://developer.spotify.com"
            )
            SourceRow(
                state: .rejected,
                name: "Last.fm",
                role: "Caratulas",
                detail: "Sus terminos excluyen expresamente las imagenes y el arte de album del uso permitido de la API.",
                url: "https://www.last.fm/api"
            )
            SourceRow(
                state: .rejected,
                name: "Jamendo",
                role: "Musica libre",
                detail: "Tecnicamente la mejor opcion de musica libre, pero sus terminos prohiben las apps disenadas para cachear contenido u ofrecer acceso offline -- que es literalmente lo que hace Aura Studio.",
                url: "https://www.jamendo.com"
            )
            SourceRow(
                state: .rejected,
                name: "Unsplash",
                role: "Fotos",
                detail: "Obliga a enlazar las imagenes desde sus servidores en vez de guardarlas. Una biblioteca local rompe esa condicion por definicion.",
                url: "https://unsplash.com"
            )
        }
    }
}

/// D-203: Deezer no pide key -- su unico control es un toggle
/// encendido/apagado, a diferencia de fanart.tv (`APIKeyServiceRow`).
private struct DeezerRow: View {
    @ObservedObject var preferences: AppPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Deezer").bold()
                if preferences.deezerEnabled {
                    Label("Activo", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                }
                Spacer()
                Toggle("", isOn: $preferences.deezerEnabled).labelsHidden()
                Button {
                    if let link = URL(string: "https://developers.deezer.com") { NSWorkspace.shared.open(link) }
                } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            Text("Caratula alternativa, 1000x1000. Sin key -- es la unica fuente cuyos terminos permiten explicitamente el uso no comercial.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// D-203: fusiona lo que antes era `APIKeyRow` (pestaña "Claves API",
/// eliminada) directamente en la fila del servicio -- el dueño pidio
/// que la configuracion viva "ahi mismo", junto a la explicacion de que
/// es cada fuente.
private struct APIKeyServiceRow: View {
    let service: APIKeyService

    @State private var keyText: String = ""
    @State private var isSaved: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(service.displayName).font(.headline)
                if isSaved {
                    Label("Activo", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                }
                Spacer()
                Button {
                    NSWorkspace.shared.open(service.guideURL)
                } label: {
                    Label("Cómo conseguir la key", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.caption)
            }

            Text(service.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(service.guideText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                SecureField("Pega tu API key aquí", text: $keyText)
                    .textFieldStyle(.roundedBorder)
                Button("Guardar") {
                    let trimmed = keyText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    APIKeyStore.save(trimmed, for: service)
                    isSaved = true
                }
                .disabled(keyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if isSaved {
                    Button("Quitar", role: .destructive) {
                        APIKeyStore.delete(for: service)
                        keyText = ""
                        isSaved = false
                    }
                }
            }
        }
        .onAppear {
            isSaved = APIKeyStore.hasKey(for: service)
        }
    }
}

private struct SourceRow: View {
    enum State {
        case active, planned, rejected

        var symbol: String {
            switch self {
            case .active:   return "checkmark.circle.fill"
            case .planned:  return "circle.dashed"
            case .rejected: return "xmark.circle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .active:   return .green
            case .planned:  return .secondary
            case .rejected: return .red
            }
        }
    }

    let state: State
    let name: String
    let role: String
    let detail: String
    let url: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: state.symbol)
                .foregroundStyle(state.tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name).bold()
                    Button {
                        if let link = URL(string: url) { NSWorkspace.shared.open(link) }
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                Text(role).font(.callout)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}
