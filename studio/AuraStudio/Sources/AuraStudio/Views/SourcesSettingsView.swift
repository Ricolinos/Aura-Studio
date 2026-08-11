import SwiftUI
import AppKit

/// De donde saca Aura Studio metadata, caratulas y letras.
///
/// Criterio de eleccion (investigacion de agosto 2026, ver D-069): todo
/// lo que se usa por defecto funciona SIN API key ni OAuth, para que la
/// app sirva recien instalada. Lo que pide key es siempre opcional. Y no
/// se lista ninguna fuente cuyos terminos de uso prohiban este caso --
/// una app personal que descarga y guarda contenido para uso offline.
struct SourcesSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            active
            Divider()
            optional
            Divider()
            rejected
        }
    }

    private var active: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Activas, sin configurar nada").font(.headline)
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
                detail: "Sin key y sin limite de tasa. Devuelve VARIAS imagenes por edicion (frente, dorso, librillo, disco) en 250/500/1200px y original -- es la base para un selector de portadas al estilo SteamGridDB.",
                url: "https://coverartarchive.org"
            )
            SourceRow(
                state: .active,
                name: "LRCLIB",
                role: "Letras sincronizadas",
                detail: "Sin key ni registro. Devuelve LRC real con tiempos, y su busqueda da hasta 20 candidatos, asi que tambien se puede elegir entre varias versiones. Codigo abierto MIT.",
                url: "https://lrclib.net"
            )
        }
    }

    private var optional: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Opcionales, con key propia").font(.headline)
            Text("Todavia no estan conectadas. Se agregan solo si te faltan portadas: lo de arriba ya cubre el caso normal.")
                .font(.caption).foregroundStyle(.secondary)
            SourceRow(
                state: .planned,
                name: "Deezer",
                role: "Caratula alternativa, 1000x1000",
                detail: "Sin key. Es la unica fuente cuyos terminos permiten explicitamente el uso no comercial. Una sola portada por album.",
                url: "https://developers.deezer.com"
            )
            SourceRow(
                state: .planned,
                name: "fanart.tv",
                role: "Caratulas y arte de disco en alta resolucion",
                detail: "Key gratuita, autogestionada. Varias imagenes por album, ~1000px.",
                url: "https://fanart.tv"
            )
            SourceRow(
                state: .planned,
                name: "Internet Archive",
                role: "Musica, video y audio de dominio publico",
                detail: "Sin key para buscar y descargar. Hay que mirar la licencia de cada item; las colecciones etree y Prelinger son seguras.",
                url: "https://archive.org"
            )
            SourceRow(
                state: .planned,
                name: "Openverse / Wikimedia Commons",
                role: "Fotos con licencia libre",
                detail: "Sin registro. Openverse devuelve el texto de atribucion ya armado.",
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
                detail: "Su API oficial no tiene letras, ni sincronizadas ni planas: la unica via es scrapear la web, contra sus terminos. El campo de API key que habia en la app se quito por eso.",
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
