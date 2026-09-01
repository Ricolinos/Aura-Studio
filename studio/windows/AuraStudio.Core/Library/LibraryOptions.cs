namespace AuraStudio.Core.Library;

/// <summary>
/// Cómo se resuelve la carátula de cada canción al preparar la biblioteca.
/// <b>No es cosmético</b>: cambia qué archivos terminan en el iPod y cómo los
/// encuentra el firmware (<c>find_albumart</c>, D-010).
/// </summary>
public enum CoverArtPolicy
{
    /// <summary>
    /// Una sola imagen por álbum, compartida por todas sus pistas
    /// (<c>cover.jpg</c> en la carpeta del álbum). Es lo que el firmware busca
    /// primero y ocupa mucho menos espacio.
    /// </summary>
    AlbumOnly,

    /// <summary>
    /// Cada pista con su propia carátula embebida, para sencillos y
    /// recopilaciones donde una portada por álbum sería incorrecta.
    /// </summary>
    PerTrack
}

/// <summary>
/// Cómo se arma la carpeta de cada canción en el iPod. El tagcache de Rockbox
/// escanea el volumen entero sin importar la profundidad, así que esta elección
/// es libre — a diferencia de fotos y video, que siguen planos.
/// </summary>
public enum MusicOrganization
{
    /// <summary><c>Music/&lt;Artista&gt;/&lt;Álbum&gt;/</c>. El valor por omisión desde D-180.</summary>
    ArtistAlbum,

    /// <summary><c>Music/&lt;Álbum&gt;/</c>, útil para recopilaciones y bandas sonoras.</summary>
    Album,

    /// <summary><c>Music/&lt;Artista&gt;/</c>, todo junto sin carpeta de álbum.</summary>
    Artist
}

/// <summary>El nombre del archivo de cada canción, sin extensión.</summary>
public enum MusicFilenameFormat
{
    /// <summary>Solo el título. El valor por omisión.</summary>
    TitleOnly,
    TrackNumberTitle,
    TitleArtist,
    TitleAlbum
}

/// <summary>
/// Calidad de audio al sincronizar. El iPod con Aura lee FLAC, ALAC y WAV sin
/// problema, así que "mantener el original" es lo seguro por omisión: comprimir
/// es una elección del usuario para ahorrar espacio, no algo que la app imponga.
/// </summary>
public enum AudioQuality
{
    OriginalLossless,

    /// <summary>MP3 256 kbps VBR: buena calidad, una fracción del espacio.</summary>
    Compressed
}

/// <summary>Lado mayor al que se reducen las fotos para el LCD de 320×240.</summary>
public enum PhotoQuality
{
    /// <summary>320 px: el ancho nativo de la pantalla, el mínimo espacio posible.</summary>
    Optimized,

    /// <summary>640 px: se ve más nítida al hacer zoom, a cambio de más espacio.</summary>
    Hd
}

/// <summary>
/// Los textos y las equivalencias de las opciones de la biblioteca. Están en
/// Core y no en la capa de interfaz porque varias —la organización de carpetas,
/// el nombre de archivo, la calidad— <b>deciden qué se escribe en el iPod</b>, y
/// la vista solo las muestra.
/// </summary>
public static class LibraryOptions
{
    // MARK: - Valores persistidos
    //
    // Se guardan como texto y no como número: el valor tiene que sobrevivir a
    // que se agregue una opción en medio del enum. Coinciden con los de macOS
    // para que un mismo criterio se lea igual en las dos apps.

    public static string RawValue(this CoverArtPolicy value) =>
        value == CoverArtPolicy.PerTrack ? "perTrack" : "albumOnly";

    public static CoverArtPolicy ParseCoverArtPolicy(string? raw) =>
        raw == "perTrack" ? CoverArtPolicy.PerTrack : CoverArtPolicy.AlbumOnly;

    public static string RawValue(this MusicOrganization value) => value switch
    {
        MusicOrganization.Album => "album",
        MusicOrganization.Artist => "artist",
        _ => "artistAlbum"
    };

    public static MusicOrganization ParseMusicOrganization(string? raw) => raw switch
    {
        "album" => MusicOrganization.Album,
        "artist" => MusicOrganization.Artist,
        _ => MusicOrganization.ArtistAlbum
    };

    public static string RawValue(this MusicFilenameFormat value) => value switch
    {
        MusicFilenameFormat.TrackNumberTitle => "trackNumberTitle",
        MusicFilenameFormat.TitleArtist => "titleArtist",
        MusicFilenameFormat.TitleAlbum => "titleAlbum",
        _ => "titleOnly"
    };

    public static MusicFilenameFormat ParseMusicFilenameFormat(string? raw) => raw switch
    {
        "trackNumberTitle" => MusicFilenameFormat.TrackNumberTitle,
        "titleArtist" => MusicFilenameFormat.TitleArtist,
        "titleAlbum" => MusicFilenameFormat.TitleAlbum,
        _ => MusicFilenameFormat.TitleOnly
    };

    public static string RawValue(this AudioQuality value) =>
        value == AudioQuality.Compressed ? "compressed" : "originalLossless";

    public static AudioQuality ParseAudioQuality(string? raw) =>
        raw == "compressed" ? AudioQuality.Compressed : AudioQuality.OriginalLossless;

    public static string RawValue(this PhotoQuality value) =>
        value == PhotoQuality.Hd ? "hd" : "optimized";

    public static PhotoQuality ParsePhotoQuality(string? raw) =>
        raw == "hd" ? PhotoQuality.Hd : PhotoQuality.Optimized;

    /// <summary>
    /// El lado mayor al que se reduce una foto. Sale de
    /// <see cref="ImageResizePlan"/> para que la preferencia y el
    /// redimensionador no puedan discrepar.
    /// </summary>
    public static int MaxDimension(this PhotoQuality value) => value == PhotoQuality.Hd
        ? ImageResizePlan.FirmwareMaxDimension
        : ImageResizePlan.DefaultMaxDimension;

    // MARK: - Colecciones de fotos (D-228)

    /// <summary>
    /// Los mismos tres nombres que sugiere <c>MediaCategoryHeuristics</c>, para
    /// que "recién instalado, sin tocar nada" clasifique igual.
    /// </summary>
    public static readonly IReadOnlyList<string> DefaultPhotoCollections = ["Imágenes", "Fotos", "IA"];

    /// <summary>
    /// Agrega una colección. Ignora vacíos y repetidos —dos filas idénticas en
    /// el selector no significan nada— y <b>quita las comas</b>: la lista se
    /// persiste separada por comas y es texto libre del usuario, así que una
    /// coma partiría la entrada en dos al releerla.
    /// </summary>
    public static IReadOnlyList<string> AddPhotoCollection(IReadOnlyList<string> current, string name)
    {
        string trimmed = name.Replace(",", "").Trim();
        if (trimmed.Length == 0 || current.Contains(trimmed, StringComparer.Ordinal)) return current;
        return [.. current, trimmed];
    }

    /// <summary>
    /// Quita una colección de la lista. <b>No des-etiqueta</b> las fotos que ya
    /// la tenían asignada — igual que borrar una etiqueta no cambia lo que ya
    /// estaba etiquetado.
    /// </summary>
    public static IReadOnlyList<string> RemovePhotoCollection(IReadOnlyList<string> current, string name)
        => [.. current.Where(collection => collection != name)];

    // MARK: - Orden de proveedores de carátula (D-203)

    /// <summary>
    /// Sube o baja un proveedor en el orden de búsqueda. Fuera de rango no hace
    /// nada, en vez de reordenar algo distinto de lo que el usuario pidió.
    /// </summary>
    public static IReadOnlyList<CoverArtProvider> Move(
        IReadOnlyList<CoverArtProvider> order, CoverArtProvider provider, int offset)
    {
        List<CoverArtProvider> result = [.. order];
        int index = result.IndexOf(provider);
        int target = index + offset;

        if (index < 0 || target < 0 || target >= result.Count) return order;

        (result[index], result[target]) = (result[target], result[index]);
        return result;
    }

    public static string RawValue(this CoverArtProvider value) => value switch
    {
        CoverArtProvider.FanartTV => "fanartTV",
        CoverArtProvider.Deezer => "deezer",
        _ => "coverArtArchive"
    };

    public static CoverArtProvider? ParseCoverArtProvider(string? raw) => raw switch
    {
        "coverArtArchive" => CoverArtProvider.CoverArtArchive,
        "fanartTV" => CoverArtProvider.FanartTV,
        "deezer" => CoverArtProvider.Deezer,
        _ => null
    };

    /// <summary>
    /// Lee el orden guardado. Las entradas inválidas o repetidas de una versión
    /// vieja se filtran, y <b>se completa con las que falten</b>: un orden al que
    /// le falta un proveedor lo dejaría inalcanzable para siempre.
    /// </summary>
    public static IReadOnlyList<CoverArtProvider> ParseCoverArtProviderOrder(string? raw)
    {
        var seen = new HashSet<CoverArtProvider>();
        List<CoverArtProvider> order =
        [
            .. (raw ?? "").Split(',')
                .Select(ParseCoverArtProvider)
                .OfType<CoverArtProvider>()
                .Where(provider => seen.Add(provider))
        ];

        if (order.Count == 0) return CoverArtProviderInfo.DefaultOrder;

        order.AddRange(CoverArtProviderInfo.DefaultOrder.Where(provider => !seen.Contains(provider)));
        return order;
    }
}
