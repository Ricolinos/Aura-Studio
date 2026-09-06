using AuraStudio.App.Platform;
using AuraStudio.Core;
using AuraStudio.Core.Library;
using AuraStudio.Core.Media;
using AuraStudio.Core.Networking;

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
                    break;

                case LibraryItemKind.Photo:
                    await ProcessPhotoAsync(item).ConfigureAwait(false);
                    break;

                case LibraryItemKind.Video:
                    await ProcessVideoAsync(item, ct).ConfigureAwait(false);
                    break;

                default:
                    item.Status = LibraryItemStatus.Failed("Este tipo de archivo no es compatible.");
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
    private async Task ProcessPhotoAsync(LibraryItem item)
    {
        PhotoExif exif = await PhotoExifReader.ReadAsync(item.SourcePath).ConfigureAwait(false);

        // La categoría es una sugerencia: el usuario la puede cambiar, y por eso
        // no se vuelve a calcular si ya tiene una.
        item.Category ??= MediaCategoryHeuristics.ClassifyPhoto(exif.SoftwareTag, exif.HasCameraExif);

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
            ? MediaCategory.Series.DisplayName()
            : MediaCategoryHeuristics.ClassifyVideo(info.Duration).DisplayName();

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

    private string Staging(LibraryItem item, string extension)
    {
        string directory = Path.Combine(preferences.LibraryPath, PersistedLibrary.PreparedDirName);
        Directory.CreateDirectory(directory);

        return StagingPaths.Resolve(directory, Path.GetFileNameWithoutExtension(item.SourcePath), extension,
            item.PreparedPath);
    }

    private static void TryDelete(string path)
    {
        try { if (File.Exists(path)) File.Delete(path); }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { }
    }
}
