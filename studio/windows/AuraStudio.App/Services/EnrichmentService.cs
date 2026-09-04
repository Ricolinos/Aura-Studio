using AuraStudio.App.Platform;
using AuraStudio.Core.Library;
using AuraStudio.Core.Networking;

namespace AuraStudio.App.Services;

/// <param name="Improved">Cuántos elementos ganaron algo.</param>
/// <param name="Lyrics">Cuántos consiguieron letra.</param>
/// <param name="NetworkError">El primer problema de red, si lo hubo. Se dice; no se traga.</param>
public sealed record EnrichmentReport(int Improved, int Lyrics, int ArtistImages, string? NetworkError)
{
    public string Summary => NetworkError is { Length: > 0 } error
        ? $"Se completaron {Improved} elemento(s), pero hubo un problema de conexión: {error}"
        : $"Se completaron {Improved} elemento(s) y {Lyrics} letra(s).";
}

/// <summary>
/// Completar en línea lo que el archivo no trae: álbum, año, número de pista,
/// carátula, letra y foto de artista.
///
/// <para>Todo lo que decide está en <see cref="LibraryEnricher"/> y
/// <see cref="ArtistImageResolver"/>; acá solo se arman los clientes con las
/// claves reales del Credential Manager y las preferencias del usuario.</para>
/// </summary>
public interface IEnrichmentService
{
    /// <summary>
    /// Completa los elementos dados <b>en su lugar</b> y devuelve qué pasó.
    /// Nunca pisa lo que el usuario editó a mano.
    /// </summary>
    Task<EnrichmentReport> EnrichAsync(
        IReadOnlyList<LibraryItem> items, IProgress<string>? progress = null, CancellationToken ct = default);

    /// <summary>Las fotos de artista que falten, guardadas en la biblioteca.</summary>
    Task<ArtistImageBatch> FetchArtistImagesAsync(
        IReadOnlyList<LibraryItem> items, string libraryRoot,
        IProgress<string>? progress = null, CancellationToken ct = default);

    /// <summary>
    /// Los pósters de los videos que no tengan. Se guardan como
    /// <c>&lt;preparado&gt;.jpg</c>, que es el archivo que la sincronización
    /// copia al lado del video.
    /// </summary>
    Task<int> FetchVideoPostersAsync(
        IReadOnlyList<LibraryItem> items, IProgress<string>? progress = null, CancellationToken ct = default);
}

public sealed class EnrichmentService(IAppPreferences preferences, CredentialStore credentials) : IEnrichmentService
{

    public async Task<EnrichmentReport> EnrichAsync(
        IReadOnlyList<LibraryItem> items, IProgress<string>? progress = null, CancellationToken ct = default)
    {
        // Sin "completar en línea" activo no se toca la red, ni siquiera si
        // alguien llama a esto directamente.
        if (!preferences.EnrichOnline)
        {
            return new EnrichmentReport(0, 0, 0,
                "\"Completar en línea\" está apagado en Ajustes › Servicios.");
        }

        var enricher = new LibraryEnricher(fanartTV: new FanartTVClient(apiKeyStore: credentials));

        int improved = 0, lyrics = 0;
        string? networkError = null;

        foreach (LibraryItem item in items)
        {
            ct.ThrowIfCancellationRequested();

            if (item.Kind != LibraryItemKind.Music) continue;

            progress?.Report(item.DisplayTitle);

            (TrackMetadata metadata, EnrichmentOutcome outcome) = await enricher.ReenrichAsync(
                item, item.Metadata ?? new TrackMetadata(),
                fetchAlbumInfo: true, fetchLyrics: true,
                coverArtOrder: preferences.CoverArtProviderOrder,
                deezerEnabled: preferences.DeezerEnabled,
                ct: ct).ConfigureAwait(false);

            // ST-141: la carátula que entra —de la etiqueta del archivo o de la
            // red— queda cuadrada acá mismo, no al sincronizar.
            metadata.CoverArtData = metadata.CoverArtData is { Length: > 0 } cover
                ? WicSquareImageEncoder.SharedNormalizer.Normalize(cover)
                : metadata.CoverArtData;

            item.Metadata = metadata;

            if (outcome.AlbumInfoFound) improved++;
            if (outcome.LyricsFound) lyrics++;

            // El primero alcanza: repetir el mismo mensaje por cada canción de
            // una biblioteca sin internet no agrega nada.
            networkError ??= outcome.NetworkErrorMessage;

            // Una canción que ya tiene lo que le faltaba pasa a estar lista.
            if (item.Status.State == LibraryItemState.NeedsReview
                && metadata is { Artist.Length: > 0, Album.Length: > 0 })
            {
                item.Status = LibraryItemStatus.Ready;
            }
        }

        return new EnrichmentReport(improved, lyrics, 0, networkError);
    }

    /// <summary>El póster no necesita más que el ancho de la pantalla del iPod.</summary>
    private const int PosterMaxDimension = 640;

    public async Task<int> FetchVideoPostersAsync(
        IReadOnlyList<LibraryItem> items, IProgress<string>? progress = null, CancellationToken ct = default)
    {
        var resolver = new VideoArtworkResolver(
            tmdb: new TMDBClient(apiKeyStore: credentials),
            fanart: new FanartTVClient(apiKeyStore: credentials),
            hasFanartKey: () => credentials.HasKey(ApiKeyService.FanartTV.Key));

        int found = 0;

        foreach (LibraryItem item in items)
        {
            ct.ThrowIfCancellationRequested();

            if (item.Kind != LibraryItemKind.Video) continue;

            // El póster viaja como `<video>.jpg` junto al preparado: sin
            // preparado todavía no hay dónde ponerlo.
            if (item.PreparedPath is not { Length: > 0 } prepared) continue;

            string poster = Path.ChangeExtension(prepared, ".jpg");

            // Uno que ya está no se vuelve a pedir: son dos llamadas de red por
            // video, y el usuario pudo haberlo puesto a mano.
            if (File.Exists(poster)) continue;

            string title = item.Metadata?.Title is { Length: > 0 } t
                ? t
                : Path.GetFileNameWithoutExtension(item.SourcePath);

            VideoArtworkOutcome outcome = await resolver
                .ResolveWithReasonAsync(title, VideoArtworkResolver.KindOf(item.Category), ct)
                .ConfigureAwait(false);

            if (outcome.Poster is not { Data.Length: > 0 } art)
            {
                progress?.Report($"{title}: {outcome.Reason}");

                // Sin clave no tiene sentido seguir pidiendo: serían cientos de
                // vueltas para el mismo mensaje.
                if (outcome.Reason == VideoArtworkResolver.MissingKeyReason) break;

                continue;
            }

            try
            {
                await Platform.ImageResizer
                    .ResizeToLcdOptimalAsync(art.Data, poster, PosterMaxDimension)
                    .ConfigureAwait(false);

                // También en la metadata: es de donde salen la vista de la
                // biblioteca y el póster de temporada.
                (item.Metadata ??= new TrackMetadata()).CoverArtData = art.Data;

                found++;
                progress?.Report($"{title}: {art.MatchedTitle}");
            }
            catch (Exception ex) when (ex is Platform.ImageResizeException or IOException)
            {
                progress?.Report($"{title}: no se pudo guardar el póster ({ex.Message})");
            }
        }

        return found;
    }

    public async Task<ArtistImageBatch> FetchArtistImagesAsync(
        IReadOnlyList<LibraryItem> items, string libraryRoot,
        IProgress<string>? progress = null, CancellationToken ct = default)
    {
        var resolver = new ArtistImageResolver(
            fanartTV: new FanartTVClient(apiKeyStore: credentials),
            hasFanartKey: () => credentials.HasKey(ApiKeyService.FanartTV.Key));

        return await resolver.FetchMissingAsync(
            // ST-141: la foto de artista se guarda cuadrada (§D.3 la exige
            // cuadrada en el iPod, y hasta v18 viajaba con su proporción).
            items, new ArtistImageStore(libraryRoot, WicSquareImageEncoder.SharedNormalizer),
            onArtistDone: (name, reason) => progress?.Report(reason is null ? name : $"{name}: {reason}"),
            ct: ct,
            // Una sola foto para "Gorillaz" — el efecto que R2-4 vino a
            // conseguir. Con el mismo criterio que las pantallas.
            grouping: preferences.ArtistGrouping).ConfigureAwait(false);
    }
}
