using System.Globalization;
using System.Text;

namespace AuraStudio.Core.Library;

/// <param name="DestinationByItemId">
/// Dónde quedó cada elemento en el iPod. Solo lo que está acá se considera
/// presente: un índice que apunte a un archivo que nunca se copió le hace
/// mostrar al firmware entradas que no se pueden abrir.
/// </param>
/// <param name="Downscale">
/// Reduce una imagen a un lado máximo. Lo pone la app (usa el codificador de
/// Windows); sin esto, las fotos de artista no viajan.
/// </param>
/// <param name="PlaylistArt">Genera el mosaico de una lista a partir de las carátulas de sus pistas.</param>
public sealed record SyncFinalizeInput
{
    public required IReadOnlyList<LibraryItem> Items { get; init; }

    public required IReadOnlyDictionary<Guid, string> DestinationByItemId { get; init; }

    public IReadOnlyList<Playlist> Playlists { get; init; } = [];

    public string? LibraryRoot { get; init; }

    public CoverArtPolicy CoverArtPolicy { get; init; } = CoverArtPolicy.AlbumOnly;

    public Func<byte[], int, byte[]?>? Downscale { get; init; }

    /// <summary>
    /// ST-142 / contrato v18: recorta una imagen a un cuadrado del lado dado
    /// (fill + center-crop). Lo pone la app (WIC); sin esto, ni la carátula de
    /// álbum ni la foto de artista viajan — antes que mandar al iPod algo que
    /// incumple el contrato, no se manda nada.
    /// </summary>
    public Func<byte[], int, byte[]?>? SquareCrop { get; init; }

    public Func<IReadOnlyList<byte[]>, byte[]?>? PlaylistArt { get; init; }

    /// <summary>
    /// De dónde salen los bytes de una carátula (ST-208). Lo pone la app, que es
    /// la que tiene el almacén de la biblioteca.
    ///
    /// <para>Antes se leían de <c>Metadata.CoverArtData</c>, porque cargar la
    /// biblioteca traía las mil carátulas a memoria. Desde ST-208 no las trae, y
    /// seguir leyéndolas de ahí habría devuelto <c>null</c> para todas: <b>el
    /// iPod se habría quedado sin una sola tapa sin que nada fallara</b>. Por eso
    /// es explícito y no un valor por omisión.</para>
    ///
    /// <para>Sin esta función no viaja ninguna carátula, igual que sin
    /// <see cref="SquareCrop"/>: antes que mandar al iPod algo que incumple el
    /// contrato, no se manda nada.</para>
    /// </summary>
    public Func<LibraryItem, byte[]?>? CoverBytes { get; init; }

    /// <summary>
    /// Con qué criterio se agrupan los artistas al escribir sus fotos (R2-4).
    /// <b>Tiene que ser el mismo que usan las pantallas</b>: si acá se agrupa
    /// distinto, el iPod recibe dos fotos para el mismo artista que en Studio
    /// se ve como uno solo.
    /// </summary>
    public ArtistGroupingOptions? ArtistGrouping { get; init; }
}

/// <param name="ArtistImagesChanged">
/// Si cambió algo en las fotos de artista — el firmware las lee al armar la
/// vista de Música, así que hay que pedirle que reconstruya esa sección.
/// </param>
/// <param name="AlbumCoversChanged">
/// ST-142: alguna <c>cover.jpg</c> se escribió o cambió. Importa para el
/// marcador: desde v18 el firmware rehace su caché maestra por la clave que
/// incluye el <c>mtime</c> de <c>cover.jpg</c>, así que un sync que solo cambió
/// carátulas <b>sí</b> tocó la sección Música, aunque no haya copiado audio.
/// </param>
public sealed record SyncFinalizeResult(int PlaylistsWritten, bool ArtistImagesChanged,
                                        bool AlbumCoversChanged = false);

/// <summary>
/// Todo lo que se escribe <b>después</b> de copiar los archivos: letras,
/// carátulas, listas, pósters, y los índices que el firmware lee para armar sus
/// pantallas. Port de la parte final de <c>LibrarySync.swift</c>.
///
/// <para>Dos reglas se repiten en cada método y valen para todos:</para>
/// <list type="bullet">
/// <item>Se escribe el <b>estado completo</b> en cada pasada, no un
/// diferencial: una letra que llegó por enriquecimiento después de que la
/// canción ya estaba en el iPod tiene que llegar igual.</item>
/// <item>Sin nada que escribir, el archivo <b>se borra</b>. Un índice viejo
/// apuntando a archivos que ya no están es peor que no tener índice.</item>
/// </list>
/// </summary>
public static class LibrarySyncFinalizer
{
    public const string SummaryRelativePath = ".rockbox/aura/sync_summary.cfg";
    public const string RatingsRelativePath = ".rockbox/aura/ratings.cfg";
    public const string VideoCategoriesRelativePath = ".rockbox/aura/video_categories.cfg";
    public const string PhotoCategoriesRelativePath = ".rockbox/aura/photo_categories.cfg";
    public const string ArtistImagesDirRelativePath = ".rockbox/aura/artists";
    public const string ArtistImagesIndexRelativePath = ".rockbox/aura/artist_images.cfg";

    /// <summary>Lado máximo de una foto de artista en el iPod (contrato §D.3).</summary>
    /// <summary>
    /// Contrato v18 §A.1: el lado con el que la carátula llega al iPod. 320 no
    /// es caprichoso — es el consumidor más exigente que hay (CoverDrift
    /// decodifica el JPEG directo a 320); con 120 se veía borroso, y con los
    /// ~1000 px de la biblioteca la fase de fotos del constructor del firmware
    /// se hacía lenta para nada.
    /// </summary>
    public const int DeviceCoverSide = 320;

    /// <summary>
    /// §D.3, contrato v20 (ST-159/ST-163): la foto de artista, <b>cuadrada</b> y
    /// de 320 — antes de v20 era 128, mismo lado que <c>cover.jpg</c>
    /// (<see cref="DeviceCoverSide"/>) desde v1.5 del contrato de biblioteca. Los
    /// firmwares siguen aceptando fotos viejas de ≤128 px (§D.5, fill-crop y
    /// ampliación); no hay ruptura hacia atrás, solo más resolución de origen
    /// para las que se sincronicen desde ahora. La comparación por bytes de
    /// <see cref="WriteArtistImages"/> hace sola la migración: una foto vieja de
    /// 128 nunca coincide con la nueva de 320, así que la primera sincronización
    /// tras este cambio la reescribe sin ningún código de migración aparte.
    /// </summary>
    public const int ArtistImageMaxDimension = 320;

    public static SyncFinalizeResult Run(string volumeRoot, SyncFinalizeInput input)
    {
        WriteLyricsSidecars(volumeRoot, input);

        bool albumCovers = input.CoverArtPolicy == CoverArtPolicy.AlbumOnly
                           && WriteAlbumCovers(volumeRoot, input);

        int playlists = WritePlaylists(volumeRoot, input);
        WriteSeasonPosters(volumeRoot, input);
        WriteSummary(volumeRoot, input, playlists);
        WriteRatings(volumeRoot, input);
        WriteCategoryIndexes(volumeRoot, input);

        bool artistImages = WriteArtistImages(volumeRoot, input);

        return new SyncFinalizeResult(playlists, artistImages, albumCovers);
    }

    // MARK: - Letras (contrato §3)

    /// <summary>
    /// La letra va <b>junto al audio, mismo nombre base, extensión
    /// <c>.lrc</c></b>: es la única ruta que el firmware intenta. Sin letra en
    /// Studio no hay archivo — y si había uno de una pasada anterior, se borra.
    /// </summary>
    private static void WriteLyricsSidecars(string volumeRoot, SyncFinalizeInput input)
    {
        foreach (LibraryItem item in input.Items)
        {
            if (item.Kind != LibraryItemKind.Music) continue;
            if (!input.DestinationByItemId.TryGetValue(item.Id, out string? relative)) continue;

            // Sin la canción en el iPod no se deja un .lrc suelto.
            if (!File.Exists(Path.Combine(volumeRoot, ToNative(relative)))) continue;

            string path = Path.Combine(volumeRoot, ToNative(SyncLayout.LyricsRelativePath(relative)));
            string lyrics = item.Metadata?.SyncedLyrics?.Trim() ?? "";

            if (lyrics.Length == 0)
            {
                TryDelete(path);
                continue;
            }

            string contents = lyrics.Replace("\r\n", "\n") + "\n";

            // No se rehace el archivo en cada sync si no cambió: sobre USB 2.0
            // eso son miles de escrituras para nada.
            if (ReadTextOrNull(path) == contents) continue;

            WriteTextAtomically(path, contents);
        }
    }

    // MARK: - Carátulas de álbum (contrato §2)

    /// <summary>
    /// <c>cover.jpg</c> en la carpeta del álbum: el lugar que comparten todas
    /// las pistas y donde <c>find_albumart()</c> mira. Desde el contrato v18 es
    /// <b>320×320</b>, recortada al centro desde la copia local — que desde
    /// ST-141 ya es cuadrada, así que acá es solo un reescalado.
    ///
    /// <para><b>Se escribe solo si cambió.</b> No es una micro-optimización:
    /// desde v18 la clave de la caché maestra del firmware incluye el
    /// <c>mtime</c> de <c>cover.jpg</c>, así que reescribirla en cada sync
    /// —como se hacía hasta acá— le tiraría al firmware toda su caché de
    /// carátulas en cada sincronización, aunque nada hubiera cambiado.</para>
    /// </summary>
    /// <returns><c>true</c> si alguna carátula se escribió o cambió.</returns>
    private static bool WriteAlbumCovers(string volumeRoot, SyncFinalizeInput input)
    {
        if (input.SquareCrop is null || input.CoverBytes is null) return false;

        bool changed = false;
        var written = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (LibraryItem item in input.Items)
        {
            if (item.Kind != LibraryItemKind.Music) continue;
            if (!item.HasCover) continue;
            if (!input.DestinationByItemId.TryGetValue(item.Id, out string? relative)) continue;

            string? folder = Path.GetDirectoryName(Path.Combine(volumeRoot, ToNative(relative)));
            if (folder is null || !written.Add(folder)) continue;

            // ST-208: la carátula se lee del disco recién acá — una vez por
            // CARPETA, no por canción. Las otras once pistas del álbum ni
            // llegan, porque `written` ya reservó su carpeta.
            if (input.CoverBytes(item) is not { Length: > 0 } cover) continue;

            try
            {
                if (input.SquareCrop(cover, DeviceCoverSide) is not { Length: > 0 } square) continue;

                string path = Path.Combine(folder, "cover.jpg");
                if (SameBytesOnDisk(path, square)) continue;

                Directory.CreateDirectory(folder);
                WriteBytesAtomically(path, square);
                changed = true;
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { }
        }

        return changed;
    }

    // MARK: - Listas

    /// <summary>
    /// Las listas se escriben siempre: son unos pocos KB de texto y no vale la
    /// pena un diferencial solo para ellas. Una pista sin destino resuelto se
    /// omite en silencio en vez de tirar abajo la lista entera.
    /// </summary>
    private static int WritePlaylists(string volumeRoot, SyncFinalizeInput input)
    {
        if (input.Playlists.Count == 0) return 0;

        string directory = Path.Combine(volumeRoot, SyncLayout.PlaylistsDirectory);
        Directory.CreateDirectory(directory);

        var itemsById = input.Items.ToDictionary(item => item.Id);
        int written = 0;

        foreach (Playlist playlist in input.Playlists)
        {
            // ST-062: las rutas van en NFC — el firmware las abre byte a byte
            // contra los nombres largos del FAT.
            List<string> paths =
            [
                .. playlist.TrackItemIds
                    .Select(id => input.DestinationByItemId.TryGetValue(id, out string? path) ? Normalized(path) : null)
                    .OfType<string>()
            ];

            if (paths.Count == 0) continue;

            try
            {
                WriteTextAtomically(Path.Combine(directory, PlaylistExporter.FileName(playlist.Name)),
                    PlaylistExporter.M3u8Contents(paths));
                written++;
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                continue;
            }

            WritePlaylistArt(directory, playlist, itemsById, input);
        }

        return written;
    }

    /// <summary>
    /// La portada de una lista: mismo nombre base que el <c>.m3u8</c>, con
    /// <c>.jpg</c>. La imagen que eligió el usuario si hay una; si no, un
    /// mosaico con las carátulas de sus pistas.
    ///
    /// <para>Todo esto es best-effort: que falle la portada no puede tirar
    /// abajo una lista cuyo <c>.m3u8</c> ya se escribió bien — el firmware
    /// tiene su propio respaldo genérico.</para>
    /// </summary>
    private static void WritePlaylistArt(string directory, Playlist playlist,
        Dictionary<Guid, LibraryItem> itemsById, SyncFinalizeInput input)
    {
        string destination = Path.Combine(directory, PlaylistExporter.ImageFileName(playlist.Name));

        if (playlist.ImageRelativePath is { Length: > 0 } relative && input.LibraryRoot is { Length: > 0 } root)
        {
            string source = Path.Combine(root, ToNative(relative));
            if (File.Exists(source))
            {
                try { File.Copy(source, destination, overwrite: true); return; }
                catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { }
            }
        }

        if (input.PlaylistArt is null) return;

        List<byte[]> covers =
        [
            .. playlist.TrackItemIds
                .Select(id => itemsById.TryGetValue(id, out LibraryItem? item) ? input.CoverBytes?.Invoke(item) : null)
                .OfType<byte[]>()
                .Where(data => data.Length > 0)
        ];

        try
        {
            if (input.PlaylistArt(covers) is { Length: > 0 } art) WriteBytesAtomically(destination, art);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { }
    }

    // MARK: - Pósters de temporada (D-318)

    /// <summary>
    /// Un <c>Videos/&lt;Serie&gt; S0N.jpg</c> por temporada presente, con la
    /// carátula del primer episodio que tenga una. El firmware concatena el
    /// nombre de programa que ya parseó con <c>" S%02d.jpg"</c>, así que el
    /// nombre tiene que salir del mismo saneo que usaron los episodios.
    /// </summary>
    private static void WriteSeasonPosters(string volumeRoot, SyncFinalizeInput input)
    {
        IEnumerable<IGrouping<(string Series, int Season), LibraryItem>> seasons = input.Items
            .Where(item => item.Kind == LibraryItemKind.Video
                           && MediaCategoryNames.IsSeriesCategory(item.Category)
                           && item.SeriesName is { Length: > 0 }
                           && item.Season is not null
                           && input.DestinationByItemId.ContainsKey(item.Id))
            .GroupBy(item => (item.SeriesName!, item.Season!.Value));

        foreach (var season in seasons)
        {
            byte[]? poster = season
                .OrderBy(item => item.Episode ?? int.MaxValue)
                .Select(item => item.HasCover ? input.CoverBytes?.Invoke(item) : null)
                .FirstOrDefault(data => data is { Length: > 0 });

            if (poster is null) continue;

            string path = Path.Combine(volumeRoot,
                ToNative(SyncLayout.SeasonPosterRelativePath(season.Key.Series, season.Key.Season)));

            // Solo si cambió: reescribir un JPEG idéntico en cada sync gasta
            // minutos de USB 2.0 sin cambiar nada.
            try
            {
                if (File.Exists(path) && File.ReadAllBytes(path).AsSpan().SequenceEqual(poster)) continue;
                WriteBytesAtomically(path, poster);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { }
        }
    }

    // MARK: - Resumen para "Acerca de" (D-283)

    /// <summary>
    /// Formato plano <c>clave: valor</c>, no JSON, a propósito: el firmware ya
    /// sabe leer ese formato para <c>aura.cfg</c> y no tiene parser de JSON.
    /// </summary>
    private static void WriteSummary(string volumeRoot, SyncFinalizeInput input, int playlists)
    {
        var summary = new CatalogSummary { PlaylistCount = playlists };

        foreach (LibraryItem item in input.Items)
        {
            if (!input.DestinationByItemId.TryGetValue(item.Id, out string? relative)) continue;

            long bytes = SizeOnDevice(volumeRoot, relative);

            switch (item.Kind)
            {
                case LibraryItemKind.Music:
                    summary.Music.Count++;
                    summary.Music.Bytes += bytes;
                    break;

                case LibraryItemKind.Video:
                    summary.Video.Count++;
                    summary.Video.Bytes += bytes;
                    if (MediaCategoryNames.IsMoviesCategory(item.Category)) summary.VideoMovies++;
                    else if (MediaCategoryNames.IsSeriesCategory(item.Category)) summary.VideoSeries++;
                    else summary.VideoClips++;
                    break;

                case LibraryItemKind.Photo:
                    summary.Photo.Count++;
                    summary.Photo.Bytes += bytes;
                    if (item.Category == "IA") summary.PhotoAI++;
                    else if (item.Category == "Fotos") summary.PhotoPhotos++;
                    else summary.PhotoImages++;
                    break;
            }
        }

        WriteTextAtomically(Path.Combine(volumeRoot, ToNative(SummaryRelativePath)),
            CatalogSummaryWriter.Serialize(summary));
    }

    private static long SizeOnDevice(string volumeRoot, string relativePath)
    {
        try
        {
            var info = new FileInfo(Path.Combine(volumeRoot, ToNative(relativePath)));
            return info.Exists ? info.Length : 0;
        }
        catch (IOException)
        {
            return 0;
        }
    }

    // MARK: - Calificaciones (D-199/D-200)

    /// <summary>
    /// La calificación no vive en ninguna etiqueta del archivo: es un dato de
    /// tagcache que se pierde cada vez que el índice se reconstruye. Este
    /// sidecar es lo único que la conserva.
    ///
    /// <para>La clave es la ruta <b>absoluta</b> en el dispositivo, para que
    /// calce con <c>tag_filename</c>, y el valor va en la escala nativa de
    /// Rockbox (0-10): la estrella de 1 a 5 de Studio se multiplica por dos.</para>
    ///
    /// <para>Es sincronización de <b>una vía</b>: leer de vuelta una
    /// calificación puesta en el aparato exigiría parsear el formato binario de
    /// tagcache, y eso se descartó por el riesgo de corromper la base entera. Si
    /// las dos difieren, gana la de Studio — limitación conocida, no un bug.</para>
    /// </summary>
    private static void WriteRatings(string volumeRoot, SyncFinalizeInput input)
    {
        List<string> lines = [];

        foreach (LibraryItem item in input.Items)
        {
            if (item.Kind != LibraryItemKind.Music) continue;
            if (item.Metadata?.Rating is not { } rating || rating <= 0) continue;
            if (!input.DestinationByItemId.TryGetValue(item.Id, out string? relative)) continue;

            lines.Add($"/{Normalized(relative)}: {Math.Clamp(rating * 2, 0, 10)}");
        }

        WriteLinesOrDelete(Path.Combine(volumeRoot, ToNative(RatingsRelativePath)), header: null, lines);
    }

    // MARK: - Índices de categoría (contrato §D.2, D-316)

    /// <summary>
    /// La categoría de cada archivo de <c>/Videos</c> y <c>/Photos</c>: es lo
    /// que le da contenido a las filas Películas/Series/Videoclips y
    /// Fotos/Imágenes/IA del firmware. Solo elementos realmente presentes en el
    /// iPod, nunca el catálogo entero.
    /// </summary>
    private static void WriteCategoryIndexes(string volumeRoot, SyncFinalizeInput input)
    {
        List<string> videos = [];
        List<string> photos = [];

        foreach (LibraryItem item in input.Items)
        {
            if (!input.DestinationByItemId.TryGetValue(item.Id, out string? relative)) continue;

            string name = Normalized(relative[(relative.LastIndexOf('/') + 1)..]);

            if (item.Kind == LibraryItemKind.Video)
            {
                videos.Add($"{name}: {(MediaCategoryNames.IsMoviesCategory(item.Category) ? "movie"
                    : MediaCategoryNames.IsSeriesCategory(item.Category) ? "series" : "clip")}");
            }
            else if (item.Kind == LibraryItemKind.Photo)
            {
                photos.Add($"{name}: {(item.Category == "IA" ? "ai" : item.Category == "Fotos" ? "photo" : "image")}");
            }
        }

        WriteLinesOrDelete(Path.Combine(volumeRoot, ToNative(VideoCategoriesRelativePath)),
            "# aura-video-categories v1", videos);
        WriteLinesOrDelete(Path.Combine(volumeRoot, ToNative(PhotoCategoriesRelativePath)),
            "# aura-photo-categories v1", photos);
    }

    // MARK: - Fotos de artista (contrato §D.3, D-322)

    /// <summary>
    /// Las fotos de artista reducidas a 128 px, con el mismo nombre de archivo
    /// que en la biblioteca local, más el índice que las asocia a cada valor
    /// crudo de la etiqueta de artista.
    ///
    /// <para>El índice lleva una línea por cada valor <b>crudo</b> distinto —
    /// solo recortando espacios, sin normalizar nada más: el firmware compara
    /// byte a byte contra la etiqueta real.</para>
    /// </summary>
    /// <returns><c>true</c> si escribió o borró algo.</returns>
    private static bool WriteArtistImages(string volumeRoot, SyncFinalizeInput input)
    {
        string indexPath = Path.Combine(volumeRoot, ToNative(ArtistImagesIndexRelativePath));
        bool existedBefore = File.Exists(indexPath);

        if (input.LibraryRoot is not { Length: > 0 } root || input.Downscale is null)
        {
            return false;
        }

        var store = new ArtistImageStore(root);
        string artistsDirectory = Path.Combine(volumeRoot, ToNative(ArtistImagesDirRelativePath));

        List<string> lines = [];
        var writtenFiles = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (ArtistGroup artist in LibraryGrouping.Artists([.. input.Items], input.ArtistGrouping))
        {
            if (store.Image(artist.Id) is not { Length: > 0 } image) continue;

            string fileName = ArtistImageStore.FileName(artist.Id);

            if (writtenFiles.Add(fileName))
            {
                try
                {
                    Directory.CreateDirectory(artistsDirectory);
                    // §D.3 las exige CUADRADAS y hasta v18 esto mandaba el lado
                    // mayor a 128 con la proporción original — lo que el
                    // contrato prohibía desde v6. Mismo criterio que
                    // `cover.jpg`: solo se escribe si cambió.
                    byte[]? square = input.SquareCrop?.Invoke(image, ArtistImageMaxDimension);
                    string path = Path.Combine(artistsDirectory, fileName);
                    if (square is { Length: > 0 } && !SameBytesOnDisk(path, square))
                        WriteBytesAtomically(path, square);
                }
                catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { }
            }

            var seen = new HashSet<string>(StringComparer.Ordinal);

            foreach (LibraryItem item in artist.Albums.SelectMany(album => album.Items))
            {
                if (item.Metadata?.Artist?.Trim() is not { Length: > 0 } raw) continue;
                if (!seen.Add(raw)) continue;

                lines.Add($"{fileName}: {raw}");
            }
        }

        if (lines.Count == 0)
        {
            if (existedBefore) TryDelete(indexPath);
            return existedBefore;
        }

        WriteLinesOrDelete(indexPath, "# aura-artist-images v1", lines);
        return true;
    }

    // MARK: - Escritura

    private static void WriteLinesOrDelete(string path, string? header, IReadOnlyList<string> lines)
    {
        if (lines.Count == 0)
        {
            TryDelete(path);
            return;
        }

        var builder = new StringBuilder();
        if (header is { Length: > 0 }) builder.Append(header).Append('\n');
        foreach (string line in lines) builder.Append(line).Append('\n');

        WriteTextAtomically(path, builder.ToString());
    }

    private static void WriteTextAtomically(string path, string contents)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);

        // UTF-8 sin BOM y saltos "\n": lo lee el firmware, no Windows.
        string temporary = path + ".tmp";
        File.WriteAllText(temporary, contents, new UTF8Encoding(false));
        File.Move(temporary, path, overwrite: true);
    }

    /// <summary>
    /// <c>true</c> si el archivo ya tiene exactamente esos bytes. Sirve para no
    /// reescribir una imagen idéntica: desde v18 el <c>mtime</c> de
    /// <c>cover.jpg</c> forma parte de la clave de caché del firmware.
    /// </summary>
    private static bool SameBytesOnDisk(string path, byte[] contents)
    {
        try
        {
            return File.Exists(path) && File.ReadAllBytes(path).AsSpan().SequenceEqual(contents);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return false;
        }
    }

    private static void WriteBytesAtomically(string path, byte[] contents)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);

        string temporary = path + ".tmp";
        File.WriteAllBytes(temporary, contents);
        File.Move(temporary, path, overwrite: true);
    }

    private static string? ReadTextOrNull(string path)
    {
        try { return File.Exists(path) ? File.ReadAllText(path) : null; }
        catch (IOException) { return null; }
    }

    private static void TryDelete(string path)
    {
        try { if (File.Exists(path)) File.Delete(path); }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { }
    }

    /// <summary>
    /// ST-062: NFC. Windows y macOS no normalizan igual los acentos, y el
    /// firmware compara las rutas byte a byte contra los nombres del FAT.
    /// </summary>
    private static string Normalized(string value) =>
        value.IsNormalized(NormalizationForm.FormC) ? value : value.Normalize(NormalizationForm.FormC);

    private static string ToNative(string relativePath) =>
        relativePath.Replace('/', Path.DirectorySeparatorChar);
}
