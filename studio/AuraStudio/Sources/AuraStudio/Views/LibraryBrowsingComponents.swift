import SwiftUI

/// Piezas compartidas por Álbumes, Artistas y Canciones (ST-020):
/// portada con placeholder, tarjeta de álbum y campo de búsqueda
/// contextual. Estilo plano (PLAN-studio-ux.md §2.4): relleno sólido
/// `selectionFill`, radio 8, sin bordes ni sombras.

/// Portada cuadrada: miniatura cacheada (`CoverThumbnailCache`) o
/// placeholder sólido con el símbolo que se le pase.
struct CoverArtView: View {
    let data: Data?
    var side: CGFloat = 128
    var cornerRadius: CGFloat = 8
    var placeholderSymbol: String = "music.note"

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let image = CoverThumbnailCache.shared.thumbnail(for: data, side: side) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    palette.selectionFill
                    Image(systemName: placeholderSymbol)
                        .font(.system(size: side * 0.32, weight: .light))
                        .foregroundStyle(palette.textTertiary)
                }
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var palette: AuraColors { colorScheme == .dark ? .dark : .light }
}

/// Avatar circular de artista: foto si hay, si no la portada de un
/// álbum, si no un micrófono sobre relleno sólido (como Music.app).
struct ArtistAvatarView: View {
    let imageData: Data?
    let fallbackCoverData: Data?
    var side: CGFloat = 40

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let image = CoverThumbnailCache.shared.thumbnail(for: imageData ?? fallbackCoverData, side: side) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    palette.selectionFill
                    Image(systemName: "music.mic")
                        .font(.system(size: side * 0.42, weight: .regular))
                        .foregroundStyle(palette.textTertiary)
                }
            }
        }
        .frame(width: side, height: side)
        .clipShape(Circle())
    }

    private var palette: AuraColors { colorScheme == .dark ? .dark : .light }
}

/// Tarjeta de la cuadrícula de Álbumes (captura de referencia del
/// dueño: portada, título en hasta 2 líneas, artista secundario,
/// estrella si alguna canción es favorita).
struct AlbumCardView: View {
    let album: AlbumGroup
    var side: CGFloat = 160
    var showsArtist = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverArtView(data: album.coverArtData, side: side)
            HStack(alignment: .top, spacing: 4) {
                Text(album.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if album.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(AuraColors.light.accent)
                        .padding(.top, 3)
                }
            }
            if showsArtist {
                Text(album.artist)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: side, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// "Buscar en Álbumes" / "Buscar en Artistas" / "Buscar en Canciones":
/// el campo es el mismo, cambia el ámbito -- cada vista filtra lo suyo.
struct LibrarySearchField: View {
    let scopeTitle: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Buscar en \(scopeTitle)", text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Borrar búsqueda")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.secondary.opacity(0.12)))
        .frame(width: 220)
    }
}

/// Coincidencia de búsqueda sin distinguir mayúsculas ni acentos.
enum LibrarySearch {
    static func matches(_ haystack: String?, _ needle: String) -> Bool {
        guard let haystack, !haystack.isEmpty else { return false }
        return haystack.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    /// Canción: título, artista, álbum, artista del álbum, género, compositor.
    static func item(_ item: LibraryItem, matches query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return true }
        let m = item.metadata
        return matches(LibraryGrouping.displayTitle(item), needle)
            || matches(m?.artist, needle)
            || matches(m?.album, needle)
            || matches(m?.albumArtist, needle)
            || matches(m?.genre, needle)
            || matches(m?.composer, needle)
            || matches(item.category, needle)
    }

    static func album(_ album: AlbumGroup, matches query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return true }
        return matches(album.title, needle) || matches(album.artist, needle) || matches(album.year, needle)
    }

    static func artist(_ artist: ArtistGroup, matches query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return true }
        return matches(artist.name, needle)
    }
}
