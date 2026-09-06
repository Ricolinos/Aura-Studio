namespace AuraStudio.Core.Library;

/// <summary>
/// La barra de estado de una sección, partida en dos por costo (ST-202;
/// paridad con <c>StatusSummaryModel.swift</c> de ST-153):
///
/// <list type="bullet">
/// <item>Lo que <b>no</b> depende de la selección —cuántos álbumes, cuántos
/// artistas, cuánto dura todo— se calcula una vez por versión del catálogo y se
/// guarda. Es lo caro: recorre la biblioteca entera.</item>
/// <item>Lo que <b>sí</b> depende de la selección se calcula en el momento, y es
/// barato: proporcional a lo seleccionado, no al catálogo.</item>
/// </list>
///
/// <para>Antes de partirlo, macOS recalculaba las dos mitades en cada clic
/// —normalizando cadenas de los 12 000 elementos para poder decir "5
/// seleccionadas"—, y era una de las dos causas del congelamiento que midió
/// ST-152. Acá el total se apoya además en <see cref="LibraryCatalogIndex"/>, que
/// ya tiene los grupos contados: pedirle cuántos álbumes hay es O(1).</para>
///
/// <para>Es puro y no sabe de hilos ni de temporizadores: el rebote —para que
/// mantener apretada Mayús+flecha no recalcule el texto en cada tecla— lo pone
/// la app, que es la que tiene el despachador.</para>
/// </summary>
public sealed class StatusSummaryModel
{
    private int _version = -1;
    private LibraryStatusSection _section;
    private LibraryStatusSummary _total = LibraryStatusSummary.Empty;

    /// <summary>
    /// Cuántas canciones hay, guardado con el total: lo necesita el texto de la
    /// selección ("5 de 12 000"), y contarlas ahí sería recorrer el catálogo en
    /// cada cambio de selección — justo lo que este modelo existe para evitar.
    /// </summary>
    private int _musicCount;

    /// <summary>
    /// La parte que no depende de la selección. Se recalcula solo cuando cambia
    /// la versión del catálogo o la sección.
    /// </summary>
    public LibraryStatusSummary Total(LibraryCatalogIndex index, LibraryStatusSection section, int catalogVersion)
    {
        if (_version == catalogVersion && _section == section) return _total;

        _version = catalogVersion;
        _section = section;
        _total = ComputeTotal(index, section, out _musicCount);
        return _total;
    }

    /// <summary>
    /// El resumen completo: el total guardado más lo que dice la selección.
    /// <paramref name="selected"/> son los ELEMENTOS alcanzados, no las tarjetas
    /// — una tarjeta de Álbumes son sus canciones.
    /// </summary>
    /// <param name="selectedGroupCount">
    /// Cuántas tarjetas/filas hay marcadas, que no es lo mismo que cuántos
    /// elementos alcanzan: en Álbumes se dice "3 de 1 000 seleccionados" con
    /// álbumes, y las canciones van aparte.
    /// </param>
    public LibraryStatusSummary Summary(
        LibraryCatalogIndex index,
        LibraryStatusSection section,
        int catalogVersion,
        IReadOnlyList<LibraryItem> selected,
        int selectedGroupCount)
    {
        LibraryStatusSummary total = Total(index, section, catalogVersion);

        return selected.Count == 0
            ? total
            : total with { Selection = SelectionText(index, section, selected, selectedGroupCount, _musicCount) };
    }

    private static LibraryStatusSummary ComputeTotal(
        LibraryCatalogIndex index, LibraryStatusSection section, out int musicCount)
    {
        IReadOnlyList<LibraryItem> music = [.. index.Items.Where(item => item.Kind == LibraryItemKind.Music)];
        musicCount = music.Count;

        // Del índice, que ya los tiene contados: preguntarle cuántos álbumes hay
        // es O(1), y volver a agrupar la biblioteca para saberlo era justamente
        // lo que la barra hacía en cada clic.
        int albums = index.GroupCount(LibraryGroupKind.Album);
        int artists = index.GroupCount(LibraryGroupKind.Artist);

        string trailing = LibraryStats.Join(
            LibraryStats.DurationText(LibraryStats.TotalDuration(music)),
            LibraryStats.SizeText(LibraryStats.TotalSize(music)));

        string total = section switch
        {
            LibraryStatusSection.Albums => LibraryStats.Join(
                LibraryStats.Count(albums, "álbum", "álbumes"),
                LibraryStats.Count(artists, "artista", "artistas"),
                LibraryStats.Count(music.Count, "canción", "canciones")),

            LibraryStatusSection.Artists => LibraryStats.Join(
                LibraryStats.Count(artists, "artista", "artistas"),
                LibraryStats.Count(albums, "álbum", "álbumes"),
                LibraryStats.Count(music.Count, "canción", "canciones")),

            _ => LibraryStats.Join(
                LibraryStats.Count(music.Count, "canción", "canciones"),
                LibraryStats.Count(artists, "artista", "artistas"),
                LibraryStats.Count(albums, "álbum", "álbumes"))
        };

        return new LibraryStatusSummary(total, "", trailing);
    }

    private static string SelectionText(
        LibraryCatalogIndex index,
        LibraryStatusSection section,
        IReadOnlyList<LibraryItem> selected,
        int selectedGroupCount,
        int musicCount)
    {
        ArtistGroupingOptions? options = index.Grouping;
        string duration = LibraryStats.DurationText(LibraryStats.TotalDuration(selected));

        return section switch
        {
            LibraryStatusSection.Albums => LibraryStats.Join(
                $"{LibraryStats.Formatted(selectedGroupCount)} de "
                + $"{LibraryStats.Formatted(index.GroupCount(LibraryGroupKind.Album))} seleccionados",
                LibraryStats.Count(LibraryStats.ArtistCount(selected, options), "artista", "artistas"),
                LibraryStats.Count(selected.Count, "canción", "canciones"),
                duration),

            LibraryStatusSection.Artists => LibraryStats.Join(
                $"{LibraryStats.Formatted(selectedGroupCount)} de "
                + $"{LibraryStats.Formatted(index.GroupCount(LibraryGroupKind.Artist))} seleccionados",
                LibraryStats.Count(LibraryStats.AlbumCount(selected, options), "álbum", "álbumes"),
                LibraryStats.Count(selected.Count, "canción", "canciones"),
                duration),

            _ => LibraryStats.Join(
                $"{LibraryStats.Formatted(selected.Count)} de {LibraryStats.Formatted(musicCount)} seleccionadas",
                LibraryStats.Count(LibraryStats.ArtistCount(selected, options), "artista", "artistas"),
                LibraryStats.Count(LibraryStats.AlbumCount(selected, options), "álbum", "álbumes"),
                duration)
        };
    }
}
