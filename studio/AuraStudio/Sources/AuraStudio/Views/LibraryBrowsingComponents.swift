import SwiftUI

/// Piezas compartidas por Álbumes, Artistas y Canciones (ST-031):
/// portada con placeholder, tarjeta de álbum y campo de búsqueda
/// contextual. Estilo plano (PLAN-studio-ux.md §2.4): relleno sólido
/// `selectionFill`, radio 8, sin bordes ni sombras.

/// Portada: miniatura cacheada (`CoverThumbnailCache`) o placeholder
/// sólido con el símbolo que se le pase. Cuadrada por defecto (`side:`);
/// `width`/`height` distintos para un póster 2:3 (Tanda 4 del plan,
/// Películas/Series) -- la caché sigue pidiendo un thumbnail cuadrado
/// del lado mayor (recortado por `aspectRatio(.fill)` al encajar en el
/// marco rectangular), no vale la pena una variante rectangular de la
/// caché solo por esto.
struct CoverArtView: View {
    let data: Data?
    var width: CGFloat
    var height: CGFloat
    var cornerRadius: CGFloat = 8
    var placeholderSymbol: String = "music.note"

    @Environment(\.colorScheme) private var colorScheme

    init(data: Data?, side: CGFloat = 128, cornerRadius: CGFloat = 8, placeholderSymbol: String = "music.note") {
        self.init(data: data, width: side, height: side, cornerRadius: cornerRadius, placeholderSymbol: placeholderSymbol)
    }

    init(data: Data?, width: CGFloat, height: CGFloat, cornerRadius: CGFloat = 8, placeholderSymbol: String = "music.note") {
        self.data = data
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
        self.placeholderSymbol = placeholderSymbol
    }

    var body: some View {
        Group {
            if let image = CoverThumbnailCache.shared.thumbnail(for: data, side: max(width, height)) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    palette.selectionFill
                    Image(systemName: placeholderSymbol)
                        .font(.system(size: min(width, height) * 0.32, weight: .light))
                        .foregroundStyle(palette.textTertiary)
                }
            }
        }
        .frame(width: width, height: height)
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

/// Tarjeta de cuadrícula genérica (PLAN-biblioteca-medios-v2.md §3.4,
/// Tanda 4): portada/póster, título en hasta 2 líneas, subtítulo
/// secundario, estrella opcional. Generalización de la tarjeta de
/// Álbumes (`AlbumCardView` abajo, sin cambio visual: sigue pidiendo un
/// cuadrado) para que Películas/Series puedan pedir un póster 2:3 sin
/// duplicar la vista.
struct MediaCardView: View {
    let imageData: Data?
    let title: String
    var subtitle: String?
    var badge = false
    /// Ancho/alto de la portada -- `.square(side)` (Álbumes) o
    /// `.poster(width:)` (Películas/Series, proporción 2:3 real de un
    /// cartel de cine).
    var aspect: Aspect = .square(160)
    var placeholderSymbol = "music.note"

    struct Aspect: Equatable {
        let width: CGFloat
        let height: CGFloat

        static func square(_ side: CGFloat) -> Aspect { Aspect(width: side, height: side) }
        static func poster(width: CGFloat) -> Aspect { Aspect(width: width, height: (width * 3 / 2).rounded()) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverArtView(data: imageData, width: aspect.width, height: aspect.height, placeholderSymbol: placeholderSymbol)
            HStack(alignment: .top, spacing: 4) {
                Text(title)
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if badge {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(AuraColors.light.accent)
                        .padding(.top, 3)
                }
            }
            if let subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: aspect.width, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// Tarjeta de la cuadrícula de Álbumes (captura de referencia del
/// dueño: portada, título en hasta 2 líneas, artista secundario,
/// estrella si alguna canción es favorita). Envoltorio delgado sobre
/// `MediaCardView` -- mismo aspecto cuadrado de siempre, sin cambio
/// visual (Tanda 4 del plan).
struct AlbumCardView: View {
    let album: AlbumGroup
    var side: CGFloat = 160
    var showsArtist = true

    var body: some View {
        #if DEBUG
        let _ = BodyEvaluationCounter.record("AlbumCardView")
        #endif
        MediaCardView(imageData: album.coverArtData, title: album.title,
                      subtitle: showsArtist ? album.artist : nil, badge: album.isFavorite,
                      aspect: .square(side))
    }
}

/// Tarjeta de la cuadrícula de álbumes de Fotos (encargo del dueño,
/// 2026-08-18: "similar en uso a lo que ofrecía el iPod Classic
/// original" -- Álbumes como carpetas con mosaico de portada). Con 4
/// fotos o más: mosaico 2×2 de las primeras 4; con menos, la primera
/// foto sola; sin ninguna, el placeholder de `CoverArtView`.
struct PhotoAlbumCardView: View {
    let album: PhotoAlbumGroup
    var side: CGFloat = 160

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            mosaic
            Text(album.title)
                .font(.callout.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(album.count == 1 ? "1 foto" : "\(album.count) fotos")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(width: side, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var mosaic: some View {
        let previews = album.previewImages
        if previews.count >= 4 {
            let half = ((side - 2) / 2).rounded(.down)
            VStack(spacing: 2) {
                HStack(spacing: 2) {
                    CoverArtView(data: previews[0], side: half, cornerRadius: 0, placeholderSymbol: "photo")
                    CoverArtView(data: previews[1], side: half, cornerRadius: 0, placeholderSymbol: "photo")
                }
                HStack(spacing: 2) {
                    CoverArtView(data: previews[2], side: half, cornerRadius: 0, placeholderSymbol: "photo")
                    CoverArtView(data: previews[3], side: half, cornerRadius: 0, placeholderSymbol: "photo")
                }
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            CoverArtView(data: previews.first, side: side, placeholderSymbol: "photo.on.rectangle")
        }
    }
}

/// Borde de acento para tarjetas/miniaturas seleccionadas en las
/// cuadrículas con selección múltiple (encargo del dueño, 2026-08-19:
/// "seleccionar múltiples álbumes de música, artistas, o películas,
/// series, episodios") -- mismo trazo que ya usaba `photoThumb` de
/// `PhotoAlbumsView` (ST-042), ahora compartido por todas las
/// cuadrículas de `GridSelection`.
extension View {
    func librarySelectionBorder(_ isSelected: Bool, cornerRadius: CGFloat = 10) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(isSelected ? AuraColors.light.accent : .clear, lineWidth: 3)
        )
    }

    /// Selección de una tarjeta de cuadrícula: el borde de acento de
    /// siempre MÁS la casilla, que aparece según la regla de R2-1
    /// (ST-113).
    ///
    /// **Cuándo se ve la casilla** — la misma regla en las dos apps:
    /// - Sin nada seleccionado, la cuadrícula se ve LIMPIA: cero
    ///   casillas. Las portadas son el contenido; una retícula de
    ///   círculos encima de todas, todo el tiempo, compite con ellas.
    /// - Al pasar el cursor por una tarjeta aparece la SUYA. Eso es lo
    ///   que hace descubrible la selección múltiple sin ensuciar nada:
    ///   ST-103 la puso siempre visible justo porque el gesto Cmd+clic
    ///   no se veía, y el hover resuelve lo mismo sin el costo visual.
    /// - Con 1 o más elementos seleccionados aparecen TODAS: ahí el
    ///   usuario ya está en modo selección y necesita ver dónde puede
    ///   sumar o quitar sin ir tanteando tarjeta por tarjeta.
    ///
    /// PLAN-studio-rendimiento-2.md Fase 1, addendum (ST-181): esta
    /// tercera regla se mantiene -- la decidió ST-113/R2-1 porque la
    /// casilla es un modo de selección que el dueño pidió expresamente y
    /// es esa visibilidad la que lo hace descubrible. Lo que se quitó es
    /// su COSTO, no su conducta: `anySelected` es un `Bool` que solo
    /// cambia en la transición vacío↔no vacío (una invalidación de las
    /// tarjetas en cada transición, cero en los clics intermedios), y la
    /// animación de aparición ya NO se dispara con él -- solo con el
    /// hover de la propia tarjeta. Antes, el primer clic hacía aparecer
    /// la casilla ANIMADA en las 1 000 tarjetas de golpe (§0.4).
    ///
    /// La semántica no cambia: la casilla ALTERNA ese elemento
    /// (`GridSelection.toggle`), el clic en la tarjeta REEMPLAZA la
    /// selección.
    func librarySelectionCheckbox(_ isSelected: Bool,
                                  anySelected: Bool,
                                  cornerRadius: CGFloat = 10,
                                  toggle: @escaping () -> Void) -> some View {
        modifier(LibrarySelectionOverlay(isSelected: isSelected,
                                         anySelected: anySelected,
                                         cornerRadius: cornerRadius,
                                         toggle: toggle))
    }
}

/// El borde + la casilla con su regla de visibilidad. Es un
/// `ViewModifier` y no una función suelta porque necesita estado propio:
/// cada tarjeta recuerda si el cursor está encima de ELLA.
private struct LibrarySelectionOverlay: ViewModifier {
    let isSelected: Bool
    let anySelected: Bool
    let cornerRadius: CGFloat
    let toggle: () -> Void

    @State private var isHovering = false

    /// Una tarjeta seleccionada muestra su casilla aunque `anySelected`
    /// llegara en `false` por un desfase de estado: "seleccionada y sin
    /// casilla" sería una contradicción en pantalla.
    private var showsCheckbox: Bool { isSelected || anySelected || isHovering }

    func body(content: Content) -> some View {
        content
            .librarySelectionBorder(isSelected, cornerRadius: cornerRadius)
            .overlay(alignment: .topLeading) {
                LibrarySelectionCheckbox(isSelected: isSelected, toggle: toggle)
                    .padding(6)
                    // Se oculta con opacidad y no quitándola del árbol:
                    // así la tarjeta no cambia de tamaño al aparecer la
                    // casilla y la cuadrícula no da un salto.
                    .opacity(showsCheckbox ? 1 : 0)
                    .allowsHitTesting(showsCheckbox)
                    // ST-181 (addendum): se anima el HOVER, no
                    // `showsCheckbox`. Animar el compuesto hacía que el
                    // primer clic -- el que voltea `anySelected` -- le
                    // disparara una animación a cada tarjeta realizada
                    // de la cuadrícula a la vez. Entrar en modo
                    // selección ahora es instantáneo; el descubrimiento
                    // por hover, que es donde la animación se agradece,
                    // sigue igual.
                    .animation(.easeOut(duration: 0.12), value: isHovering)
            }
            .onHover { isHovering = $0 }
    }
}

/// La casilla para una FILA (los episodios de una serie), donde no hay
/// portada sobre la que flotar. Misma regla de visibilidad que en las
/// tarjetas, pero **siempre ocupa su lugar**: si apareciera y
/// desapareciera del layout, el texto de todas las filas se correría al
/// pasar el mouse.
struct LibraryRowSelectionCheckbox: View {
    let isSelected: Bool
    let anySelected: Bool
    /// El hover lo detecta la FILA, no la casilla: una casilla invisible
    /// no recibe eventos, así que no podría descubrirse sola.
    let isRowHovered: Bool
    let toggle: () -> Void

    private var showsCheckbox: Bool { isSelected || anySelected || isRowHovered }

    var body: some View {
        LibrarySelectionCheckbox(isSelected: isSelected, toggle: toggle, side: 18)
            .opacity(showsCheckbox ? 1 : 0)
            .allowsHitTesting(showsCheckbox)
            // ST-181 (addendum): igual que en las tarjetas, se anima el
            // hover y no el compuesto.
            .animation(.easeOut(duration: 0.12), value: isRowHovered)
    }
}

/// La casilla en sí -- solo el dibujo y el gesto. CUÁNDO se ve lo
/// deciden `LibrarySelectionOverlay` (tarjetas) y
/// `LibraryRowSelectionCheckbox` (filas), según la regla de R2-1.
///
/// Va encima de una portada cualquiera -- clara, oscura, con detalle --
/// así que no puede depender del contraste con la imagen: disco propio
/// (acento si está marcada, negro translúcido si no) y aro blanco.
struct LibrarySelectionCheckbox: View {
    let isSelected: Bool
    let toggle: () -> Void
    var side: CGFloat = 20

    var body: some View {
        ZStack {
            Circle()
                .fill(isSelected ? AuraColors.light.accent : Color.black.opacity(0.38))
            Circle()
                .strokeBorder(Color.white.opacity(0.9), lineWidth: 1.5)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: side * 0.55, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: side, height: side)
        .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
        .contentShape(Circle())
        // Gesto propio, no `Button`: al ser hijo de la tarjeta gana
        // sobre los `onTapGesture` de ella, así que marcar la casilla
        // nunca abre el detalle ni reemplaza la selección.
        .onTapGesture(perform: toggle)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(isSelected ? "Quitar de la selección" : "Agregar a la selección")
        .help(isSelected ? "Quitar de la selección" : "Agregar a la selección")
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
