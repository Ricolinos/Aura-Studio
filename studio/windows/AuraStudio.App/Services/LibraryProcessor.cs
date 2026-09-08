using AuraStudio.App.Platform;
using AuraStudio.Core;
using AuraStudio.Core.Library;
using AuraStudio.Core.Media;
using AuraStudio.Core.Networking;

using AuraStudio.Core.Resources;

namespace AuraStudio.App.Services;

/// <summary>
/// Lo que le pasa a un elemento recién agregado, <b>antes</b> de tocar la red:
/// leerle las etiquetas, sacarle una categoría, transcodificarlo o
/// redimensionarlo, y dejarlo listo o marcado para revisión.
///
/// <para>Se separa del enriquecimiento en línea a propósito: esto corre siempre
/// y no depende de que haya internet ni de ninguna clave. Lo que falte después
/// de esto es lo que <c>LibraryEnricher</c> puede completar, y eso es del
/// usuario decidir cuándo.</para>
/// </summary>
public interface ILibraryProcessor
{
    /// <summary>Procesa un elemento en su lugar y devuelve si algo cambió.</summary>
    Task<bool> ProcessAsync(LibraryItem item, CancellationToken ct = default);

    /// <summary>
    /// Mete el archivo del elemento adentro de la biblioteca (ST-243), y devuelve
    /// si se puede seguir. Con <paramref name="force"/> se copia aunque el
    /// interruptor esté apagado: es la acción explícita "Convertir referenciados
    /// en copias" (ST-244).
    ///
    /// <para>Está en la interfaz porque esa acción la dispara la biblioteca, no
    /// una importación — y tener dos implementaciones de copiar sería tener dos
    /// formas distintas de tratar los archivos del usuario.</para>
    /// </summary>
    Task<bool> CopyIntoLibraryAsync(LibraryItem item, bool force = false, CancellationToken ct = default);
}

public sealed class LibraryProcessor(IAppPreferences preferences) : ILibraryProcessor
{
    /// <summary>El póster de un video no necesita más que el ancho de la pantalla.</summary>
    private const int VideoPosterMaxDimension = 640;

    public async Task<bool> ProcessAsync(LibraryItem item, CancellationToken ct = default)
    {
        // Solo lo que está esperando: volver a procesar lo que el usuario ya
        // corrigió a mano le borraría el trabajo.
        if (item.Status.State is not (LibraryItemState.Queued or LibraryItemState.Failed)) return false;

        try
        {
            switch (item.Kind)
            {
                case LibraryItemKind.Music:
                    ProcessMusic(item);

                    // Después de leerle las etiquetas y antes de nada más: la
                    // carpeta de destino sale del artista y del álbum, así que
                    // no se puede decidir sin ellos (ST-243).
                    if (!await CopyIntoLibraryAsync(item, ct: ct).ConfigureAwait(false)) return true;

                    // Y si quedó referenciada, el archivo que viaja al iPod
                    // —solo si hace falta uno— se arma acá (ST-244).
                    await EnsurePreparedAsync(item, ct).ConfigureAwait(false);
                    break;

                case LibraryItemKind.Photo:
                    await ProcessPhotoAsync(item, ct).ConfigureAwait(false);
                    break;

                case LibraryItemKind.Video:
                    await ProcessVideoAsync(item, ct).ConfigureAwait(false);
                    break;

                default:
                    item.Status = LibraryItemStatus.Failed(Strings.Get("library-processor.unsupported"));
                    return true;
            }

            return true;
        }
        catch (OperationCanceledException)
        {
            // Cancelar deja el elemento como estaba, esperando: no es un error
            // que haya que mostrarle a nadie.
            item.Status = LibraryItemStatus.Queued;
            return true;
        }
        catch (Exception ex)
        {
            // El elemento se queda en la biblioteca con el motivo a la vista, en
            // vez de desaparecer o dejar la importación a medias.
            item.Status = LibraryItemStatus.Failed(ex.Message);
            return true;
        }
    }

    private static void ProcessMusic(LibraryItem item)
    {
        TrackMetadata metadata = LocalTagReader.Read(item.SourcePath);

        // Lo que no traiga la etiqueta se adivina del nombre del archivo, que es
        // de dónde sale la mitad de la música que la gente tiene suelta.
        FilenameGuesser.Guess guess = FilenameGuesser.For(item.SourcePath);
        metadata.Title ??= guess.Title;
        metadata.Artist ??= guess.Artist;

        // ST-141: la carátula embebida en el archivo (o el `cover.jpg` de su
        // carpeta) entra cuadrada, igual que la que baja de la red.
        if (metadata.CoverArtData is { Length: > 0 } cover)
            metadata.CoverArtData = WicSquareImageEncoder.SharedNormalizer.Normalize(cover);

        item.Metadata = metadata;

        // Sin artista o sin álbum la canción igual sirve, pero en el iPod cae en
        // "Desconocido": se marca para que el usuario lo vea y lo corrija si
        // quiere, no se esconde.
        item.Status = string.IsNullOrEmpty(metadata.Artist) || string.IsNullOrEmpty(metadata.Album)
            ? LibraryItemStatus.NeedsReview
            : LibraryItemStatus.Ready;
    }

    /// <summary>
    /// La foto viaja <b>reducida</b>: el LCD del iPod es de 320x240 y una foto
    /// de teléfono ocupa cien veces lo que hace falta para verse igual.
    /// </summary>
    private async Task ProcessPhotoAsync(LibraryItem item, CancellationToken ct)
    {
        PhotoExif exif = await PhotoExifReader.ReadAsync(item.SourcePath).ConfigureAwait(false);

        // La categoría es una sugerencia: el usuario la puede cambiar, y por eso
        // no se vuelve a calcular si ya tiene una.
        item.Category ??= MediaCategoryHeuristics.ClassifyPhoto(exif.SoftwareTag, exif.HasCameraExif);

        // La copia va después de la categoría, que es de qué carpeta cuelga, y
        // antes de reducirla: lo preparado sale de la copia (ST-243).
        if (!await CopyIntoLibraryAsync(item, ct: ct).ConfigureAwait(false)) return;

        string output = Staging(item, "jpg");
        await ImageResizer.ResizeToLcdOptimalAsync(item.SourcePath, output, preferences.PhotoQuality.MaxDimension())
            .ConfigureAwait(false);

        item.PreparedPath = output;
        item.Status = LibraryItemStatus.Ready;
    }

    /// <summary>
    /// El video se transcodifica al único formato que el aparato reproduce. Sin
    /// ffmpeg no se puede: se dice con todas las letras y el elemento queda
    /// marcado, en vez de aparecer como listo y fallar recién al sincronizar.
    /// </summary>
    private async Task ProcessVideoAsync(LibraryItem item, CancellationToken ct)
    {
        if (FfmpegRunner.Locate(preferences.FfmpegPath) is not { } ffmpeg)
        {
            item.Status = LibraryItemStatus.Failed(FfmpegLocator.NotFoundMessage);
            return;
        }

        VideoInfo info = await ffmpeg.ProbeAsync(item.SourcePath, ct).ConfigureAwait(false);

        // La duración es lo único que separa una película de un video suelto.
        // Series nunca se asigna sola (D-228): esa la pone el usuario o el
        // nombre del archivo.
        VideoTitleParser.Parsed parsed = VideoTitleParser.Parse(Path.GetFileNameWithoutExtension(item.SourcePath));

        item.Category ??= parsed.IsEpisode
            ? MediaCategory.Series.CatalogName()
            : MediaCategoryHeuristics.ClassifyVideo(info.Duration).CatalogName();

        if (MediaCategoryNames.IsSeriesCategory(item.Category) && parsed.IsEpisode)
        {
            item.SeriesName ??= parsed.SeriesName;
            item.Season ??= parsed.Season;
            item.Episode ??= parsed.Episode;
        }

        item.Metadata ??= new TrackMetadata();
        item.Metadata.Title ??= parsed.Title.Length > 0
            ? parsed.Title
            : Path.GetFileNameWithoutExtension(item.SourcePath);
        item.Metadata.DurationSeconds ??= info.Duration;

        // Igual que la foto: después de la categoría —que es de qué carpeta
        // cuelga— y antes de transcodificar, para que el .mpg salga de la copia.
        if (!await CopyIntoLibraryAsync(item, ct: ct).ConfigureAwait(false)) return;

        string output = Staging(item, "mpg");

        string? crop = await ffmpeg.DetectCropAsync(item.SourcePath, info.Duration, ct).ConfigureAwait(false);

        item.Status = LibraryItemStatus.Transcoding(0);

        try
        {
            await ffmpeg.TranscodeVideoAsync(item.SourcePath, output, info.FrameRate, crop,
                fraction => item.Status = LibraryItemStatus.Transcoding(fraction), ct).ConfigureAwait(false);
        }
        catch
        {
            // Un .mpg a medio escribir se copiaría al iPod como si estuviera
            // completo: el aparato lo indexaría y no se podría reproducir.
            TryDelete(output);
            throw;
        }

        item.PreparedPath = output;

        // El póster acompaña al video (`<video>.jpg`) y no tiene entrada propia
        // en el manifiesto. Si no se puede sacar, el video se sincroniza igual.
        await WritePosterAsync(ffmpeg, item, output, info.Duration, ct).ConfigureAwait(false);

        item.Status = LibraryItemStatus.Ready;
    }

    /// <summary>
    /// El póster descargado —TMDB, fanart.tv— manda sobre el fotograma: es la
    /// imagen que el usuario espera ver, no un cuadro cualquiera de la película.
    /// </summary>
    private async Task WritePosterAsync(FfmpegRunner ffmpeg, LibraryItem item, string videoPath,
        double? duration, CancellationToken ct)
    {
        string poster = Path.ChangeExtension(videoPath, ".jpg");

        // ST-208: el póster puede venir en la mano —lo acaba de descargar el
        // enriquecimiento— o estar ya guardado en la biblioteca, y entonces hay
        // que ir a buscarlo. Leerlo solo de la metadata dejaría sin póster a
        // todo lo que se reprocese después de reabrir la app.
        if (new LibraryStore(preferences.LibraryPath).ReadCover(item) is { Length: > 0 } downloaded)
        {
            try
            {
                await ImageResizer.ResizeToLcdOptimalAsync(downloaded, poster, VideoPosterMaxDimension)
                    .ConfigureAwait(false);
                return;
            }
            catch (ImageResizeException)
            {
                // Se cae al fotograma.
            }
        }

        await ffmpeg.GeneratePosterAsync(videoPath, poster, duration, ct).ConfigureAwait(false);
    }

    /// <summary>
    /// Mete el archivo adentro de la biblioteca si el usuario pidió copiar
    /// (ST-243). Devuelve si se puede seguir procesando el elemento.
    ///
    /// <para><b>Esto es lo que el interruptor de Ajustes venía prometiendo y
    /// nadie cumplía.</b> "Cada canción, foto o video que sueltas en Aura Studio
    /// se copia dentro de la carpeta de arriba" decía la pantalla —y viene
    /// encendido de fábrica— mientras la biblioteca referenciaba todo donde
    /// estuviera. Un usuario que le creyó y ordenó su carpeta de descargas se
    /// quedó sin biblioteca.</para>
    ///
    /// <para><b>El original nunca se toca</b>: se copia, y lo que pasa a estar
    /// bajo nuestro mando es la copia. A partir de ahí el elemento es
    /// <c>storage: copy</c> y, si es música, <b>su propio preparado</b>
    /// (ST-241): no hay un segundo archivo en <c>.preparados/</c> que sea copia
    /// de la copia.</para>
    ///
    /// <para><b>WAV y AIFF se convierten a MP3</b> en el camino: el iPod no los
    /// reproduce de forma útil y son enormes. Lo hace el codificador que ya trae
    /// Windows (<see cref="AudioTranscoder"/>), no ffmpeg.</para>
    /// </summary>
    public async Task<bool> CopyIntoLibraryAsync(
        LibraryItem item, bool force = false, CancellationToken ct = default)
    {
        // `force` es la acción explícita "Convertir referenciados en copias":
        // ahí el usuario lo pidió, aunque el interruptor esté apagado (ST-244).
        if (!force && !preferences.CopyMediaIntoLibrary) return true;

        string root = preferences.LibraryPath;

        // Sin biblioteca elegida no hay adónde copiar. No es un error del
        // archivo: se referencia, que es lo que se venía haciendo siempre.
        if (root is not { Length: > 0 } || !Directory.Exists(root)) return true;

        // Ya adentro —el usuario apuntó la biblioteca a su propia carpeta de
        // música, o esto es un reproceso— no se copia sobre sí mismo.
        if (LibraryFileCopier.IsInside(root, item.SourcePath))
        {
            MarkAsCopy(item, item.SourcePath, item.FileSizeBytes);
            return true;
        }

        // ST-244: la regla de conversión sale de UN solo lugar, el mismo que usa
        // el preparador por identificador. Con dos reglas sería cuestión de
        // tiempo que la biblioteca y el iPod terminaran con formatos que no se
        // corresponden sin que nadie lo hubiera decidido.
        AudioConversion conversion = item.Kind == LibraryItemKind.Music
            ? AudioConversionRules.For(item.SourcePath, preferences.AudioQuality)
            : AudioConversion.None;

        bool convert = conversion.Converts;

        string relative = LibraryFileLayout.RelativePath(
            item,
            preferences.MusicOrganization,
            preferences.MusicFilenameFormat,
            preferences.OrganizePhotosByCategory,
            preferences.OrganizeVideosByCategory,
            conversion.Extension);

        try
        {
            if (convert)
            {
                string destination = LibraryFileCopier.Available(root, relative);
                AudioTranscodeResult converted = await AudioTranscoder
                    .ConvertAsync(item.SourcePath, destination, conversion.Codec, ct)
                    .ConfigureAwait(false);

                MarkAsCopy(item, converted.Path, converted.BytesWritten);
                WriteTagsIntoTheCopy(item);
                return true;
            }

            LibraryCopyResult copied = LibraryFileCopier.Copy(item.SourcePath, root, relative);

            if (!copied.Copied)
            {
                // Que la copia falle no se puede tapar quedándose con la
                // referencia: el usuario pidió una copia y podría borrar el
                // original creyendo que ya está adentro.
                item.Status = LibraryItemStatus.Failed(
                    Strings.Format("library-processor.copy-failed", copied.Reason));
                return false;
            }

            MarkAsCopy(item, copied.Path, copied.BytesWritten);
            if (item.Kind == LibraryItemKind.Music) WriteTagsIntoTheCopy(item);

            return true;
        }
        catch (AudioTranscodeException ex)
        {
            item.Status = LibraryItemStatus.Failed(
                Strings.Format("library-processor.mp3-failed", ex.Message));
            return false;
        }
    }

    /// <summary>
    /// El elemento pasa a ser de la biblioteca: su archivo es la copia, su
    /// <c>storage</c> es <c>copy</c> y —si es música— su preparado es él mismo
    /// (ST-241).
    /// </summary>
    private static void MarkAsCopy(LibraryItem item, string path, long? bytes)
    {
        item.SourcePath = path;
        item.Storage = ItemStorageRules.CopyValue;

        // Asignar la ruta olvida el tamaño (ST-201): se repone acá, con lo que
        // de verdad se escribió, en vez de dejar que alguien lo vuelva a medir.
        item.FileSizeBytes = bytes;

        if (item.Kind == LibraryItemKind.Music) item.PreparedPath = item.SourcePath;
    }

    /// <summary>
    /// Deja en la copia las etiquetas del catálogo. Se escribe <b>en la copia,
    /// nunca en el original</b>: el archivo del usuario no se toca ni siquiera
    /// para mejorarlo.
    /// </summary>
    private void WriteTagsIntoTheCopy(LibraryItem item)
    {
        byte[]? cover = preferences.CoverArtPolicy == CoverArtPolicy.PerTrack
            ? item.Metadata?.CoverArtData
            : null;

        LocalTagWriter.Write(item.SourcePath, item.Metadata, preferences.CoverArtPolicy, cover);
    }

    /// <summary>
    /// Arma el archivo que viaja al iPod por una canción referenciada —y solo si
    /// hace falta uno— (ST-244). Con la música copiada no hace nada: esa es su
    /// propio preparado (ST-241).
    ///
    /// <para>Que falle no tumba la importación: la canción queda en la
    /// biblioteca con el motivo a la vista y se puede reintentar.</para>
    /// </summary>
    private async Task EnsurePreparedAsync(LibraryItem item, CancellationToken ct)
    {
        string staging = StagingDirectory();

        PreparedMusicResult result = await PreparedMusicBuilder.EnsureAsync(
            item,
            staging,
            preferences.AudioQuality,
            preferences.CoverArtPolicy,
            preferences.CoverArtPolicy == CoverArtPolicy.PerTrack ? item.Metadata?.CoverArtData : null,
            AudioTranscoder.ForPreparedAsync,
            ct: ct).ConfigureAwait(false);

        // `null` es una respuesta legítima y la más común: la canción ya dice lo
        // que dice el catálogo, así que al iPod viaja el original y no se
        // duplica nada.
        if (result.Path is { Length: > 0 }) item.PreparedPath = result.Path;
    }

    private string StagingDirectory()
    {
        string directory = Path.Combine(preferences.LibraryPath, PersistedLibrary.PreparedDirName);
        Directory.CreateDirectory(directory);

        return directory;
    }

    /// <summary>
    /// Dónde va lo preparado de una foto o un video. <b>Por identificador</b>
    /// desde ST-244: la carpeta es plana y compartida, y nombrarlo por el
    /// archivo de origen hacía que dos archivos con el mismo nombre se pelearan
    /// el mismo preparado (ST-064). Lo que ya está con el nombre viejo se
    /// conserva — cargar la biblioteca no renombra archivos.
    ///
    /// <para>Que el preparado se llame por identificador <b>no</b> cambia el
    /// nombre que el usuario ve en el iPod: ese sale del original
    /// (<see cref="SyncLayout.DeviceFilename"/>).</para>
    /// </summary>
    private string Staging(LibraryItem item, string extension) =>
        StagingPaths.ForItem(StagingDirectory(), item.Id, extension, item.PreparedPath);

    private static void TryDelete(string path)
    {
        try { if (File.Exists(path)) File.Delete(path); }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { }
    }
}
