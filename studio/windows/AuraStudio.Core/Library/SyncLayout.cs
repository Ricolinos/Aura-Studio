using System.Globalization;
using System.Text;

namespace AuraStudio.Core.Library;

/// <summary>
/// Dónde va cada archivo dentro del iPod. Port de la parte de rutas de
/// <c>LibrarySync.swift</c>.
///
/// <para><b>Esto es contrato, no diseño.</b> Todo lo de acá está fijado en
/// <c>docs/contracts/library-layout-v1.md</c> y lo lee el firmware: cambiar una
/// ruta o un nombre sin coordinar el otro lado hace que el iPod deje de
/// encontrar la música, las letras o las carátulas.</para>
/// </summary>
public static class SyncLayout
{
    public const string MusicDirectory = "Music";
    public const string VideosDirectory = "Videos";
    public const string PhotosDirectory = "Photos";
    public const string PlaylistsDirectory = "Playlists";

    /// <summary>Lo que Studio crea al instalar; el firmware también los crea si faltan.</summary>
    public static readonly IReadOnlyList<string> DeviceDirectories =
        [MusicDirectory, VideosDirectory, PhotosDirectory, PlaylistsDirectory];

    /// <summary>Artista o álbum sin resolver. Nunca una carpeta vacía ni "null".</summary>
    public const string UnknownFolder = "Desconocido";

    /// <summary>
    /// Tope de nombre para <c>/Videos/</c> y <c>/Photos/</c>: <b>95 bytes UTF-8
    /// incluyendo la extensión</b> (contrato §1). Los buffers del firmware son
    /// de 96 con el NUL; pasarse trunca el nombre en silencio del otro lado.
    /// </summary>
    public const int DeviceFilenameMaxBytes = 95;

    /// <summary>
    /// La ruta de destino, relativa a la raíz del volumen. Siempre con "/": es
    /// una ruta del iPod, no de Windows.
    /// </summary>
    public static string DestinationRelativePath(
        LibraryItem item,
        MusicOrganization organization = MusicOrganization.ArtistAlbum,
        MusicFilenameFormat filenameFormat = MusicFilenameFormat.TitleOnly)
    {
        string filename = Path.GetFileName(item.PreparedPath ?? item.SourcePath);

        switch (item.Kind)
        {
            case LibraryItemKind.Music:
                return MusicDestinationRelativePath(item, organization, filenameFormat);

            case LibraryItemKind.Video:
                // Un episodio con serie, temporada y episodio resueltos viaja
                // como "<Serie> SxxEyy.<ext>": ese sufijo es lo que el firmware
                // busca para agrupar por temporada en Movie Flow (contrato §1).
                // Cualquier otro video conserva su nombre.
                if (MediaCategoryNames.IsSeriesCategory(item.Category)
                    && item is { SeriesName: { Length: > 0 } series, Season: { } season, Episode: { } episode })
                {
                    string extension = Path.GetExtension(filename).TrimStart('.');
                    return $"{VideosDirectory}/{SeriesEpisodeFilename(series, season, episode, extension)}";
                }

                return $"{VideosDirectory}/{PathSanitizer.SanitizeFilename(filename, DeviceFilenameMaxBytes)}";

            case LibraryItemKind.Photo:
                return $"{PhotosDirectory}/{PathSanitizer.SanitizeFilename(filename, DeviceFilenameMaxBytes)}";

            default:
                // No debería llegar acá: lo no compatible no se sincroniza. Se
                // le da una ruta propia para que, si llegara, quede aislado y
                // visible en vez de mezclado con la música.
                return $"Unsupported/{filename}";
        }
    }

    /// <summary>
    /// <c>Music/&lt;carpetas&gt;/&lt;nombre&gt;.&lt;ext&gt;</c> según lo que
    /// eligió el usuario. El tagcache del firmware indexa el disco entero sin
    /// importar la profundidad, así que el layout es libre (contrato §1).
    /// </summary>
    public static string MusicDestinationRelativePath(
        LibraryItem item,
        MusicOrganization organization = MusicOrganization.ArtistAlbum,
        MusicFilenameFormat filenameFormat = MusicFilenameFormat.TitleOnly)
    {
        string extension = Path.GetExtension(item.PreparedPath ?? item.SourcePath).TrimStart('.');
        TrackMetadata? metadata = item.Metadata;

        // El artista de la CARPETA es el del álbum si lo hay: así una
        // recopilación no se parte en una carpeta por invitado.
        string artist = PathSanitizer.Sanitize(
            Blank(metadata?.AlbumArtist) ?? Blank(metadata?.Artist) ?? UnknownFolder);
        string album = PathSanitizer.Sanitize(Blank(metadata?.Album) ?? UnknownFolder);
        string title = PathSanitizer.Sanitize(
            Blank(metadata?.Title) ?? Path.GetFileNameWithoutExtension(item.SourcePath));

        string folder = organization switch
        {
            MusicOrganization.Album => album,
            MusicOrganization.Artist => artist,
            _ => $"{artist}/{album}"
        };

        string filename = filenameFormat switch
        {
            MusicFilenameFormat.TrackNumberTitle => metadata?.TrackNumber is > 0
                ? $"{metadata.TrackNumber:00} {title}"
                : title,
            MusicFilenameFormat.TitleArtist => $"{title} - {artist}",
            MusicFilenameFormat.TitleAlbum => $"{title} - {album}",
            _ => title
        };

        return extension.Length == 0
            ? $"{MusicDirectory}/{folder}/{filename}"
            : $"{MusicDirectory}/{folder}/{filename}.{extension}";
    }

    /// <summary>
    /// <c>&lt;Serie&gt; SxxEyy.&lt;ext&gt;</c>, saneado y acotado <b>sin tocar
    /// el sufijo</b>.
    ///
    /// <para>Acotar el nombre completo desde el final mutilaría justo el
    /// <c>SxxEyy</c> que el firmware necesita para agrupar por temporada, así
    /// que el presupuesto de bytes se calcula antes y solo se recorta el nombre
    /// de la serie.</para>
    /// </summary>
    public static string SeriesEpisodeFilename(
        string seriesName, int season, int episode, string extension,
        int maxBytes = DeviceFilenameMaxBytes)
    {
        string suffix = string.Format(CultureInfo.InvariantCulture, " S{0:00}E{1:00}", season, episode);
        string extensionSuffix = extension.Length == 0 ? "" : "." + extension;

        int budget = Math.Max(1,
            maxBytes - Encoding.UTF8.GetByteCount(suffix) - Encoding.UTF8.GetByteCount(extensionSuffix));

        return TruncateToBytes(PathSanitizer.Sanitize(seriesName, int.MaxValue), budget) + suffix + extensionSuffix;
    }

    /// <summary>
    /// El póster de temporada: <c>Videos/&lt;Serie&gt; S0N.jpg</c> (contrato
    /// §1, D-318). <b>Sin <c>ExY</c></b> — es un archivo por temporada, no de un
    /// episodio.
    ///
    /// <para>Usa el mismo saneo que el nombre del episodio: el firmware
    /// concatena el nombre de programa que ya parseó con <c>" S%02d.jpg"</c>, así
    /// que tiene que dar exactamente el archivo que Studio escribió.</para>
    /// </summary>
    public static string SeasonPosterRelativePath(string seriesName, int season, int maxBytes = DeviceFilenameMaxBytes)
    {
        string suffix = string.Format(CultureInfo.InvariantCulture, " S{0:00}.jpg", season);
        int budget = Math.Max(1, maxBytes - Encoding.UTF8.GetByteCount(suffix));

        return $"{VideosDirectory}/{TruncateToBytes(PathSanitizer.Sanitize(seriesName, int.MaxValue), budget)}{suffix}";
    }

    /// <summary>
    /// El póster de un video: <b>el mismo nombre base con <c>.jpg</c></b>, al
    /// lado del archivo. Es la única forma en que el firmware lo encuentra.
    /// </summary>
    public static string PosterRelativePath(string videoDestinationRelativePath) =>
        ReplaceExtension(videoDestinationRelativePath, ".jpg");

    /// <summary>
    /// La letra: <b>junto al audio, mismo nombre base, extensión
    /// <c>.lrc</c></b> (contrato §3). El firmware no busca en ningún otro lado
    /// — ni en <c>/Lyrics/</c>, ni por etiquetas, ni <c>.txt</c>.
    /// </summary>
    public static string LyricsRelativePath(string musicDestinationRelativePath) =>
        ReplaceExtension(musicDestinationRelativePath, ".lrc");

    /// <summary>
    /// La carátula del álbum con la política por omisión: <c>cover.jpg</c> en la
    /// carpeta del álbum, que es el tercer lugar donde mira <c>find_albumart()</c>
    /// y el que comparten todas las pistas (contrato §2).
    /// </summary>
    public static string? AlbumCoverRelativePath(string musicDestinationRelativePath)
    {
        int lastSlash = musicDestinationRelativePath.LastIndexOf('/');
        return lastSlash <= 0 ? null : musicDestinationRelativePath[..lastSlash] + "/cover.jpg";
    }

    /// <summary>La lista y su portada, con el mismo nombre base (contrato §1).</summary>
    public static string PlaylistRelativePath(string playlistName) =>
        $"{PlaylistsDirectory}/{PlaylistExporter.FileName(playlistName)}";

    public static string PlaylistCoverRelativePath(string playlistName) =>
        $"{PlaylistsDirectory}/{PlaylistExporter.ImageFileName(playlistName)}";

    /// <summary>
    /// Recorta a <paramref name="maxBytes"/> en UTF-8 <b>sin partir un
    /// carácter</b> y sin dejar punto ni espacio al final, que FAT32 no admite.
    /// </summary>
    private static string TruncateToBytes(string value, int maxBytes)
    {
        var builder = new StringBuilder();
        int bytes = 0;

        foreach (char c in value)
        {
            int size = Encoding.UTF8.GetByteCount([c]);
            if (bytes + size > maxBytes) break;
            builder.Append(c);
            bytes += size;
        }

        while (builder.Length > 0 && (builder[^1] == '.' || builder[^1] == ' '))
            builder.Length--;

        return builder.Length == 0 ? "_" : builder.ToString();
    }

    private static string ReplaceExtension(string relativePath, string newExtension)
    {
        int lastSlash = relativePath.LastIndexOf('/');
        int lastDot = relativePath.LastIndexOf('.');

        return lastDot > lastSlash
            ? relativePath[..lastDot] + newExtension
            : relativePath + newExtension;
    }

    private static string? Blank(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value;
}
