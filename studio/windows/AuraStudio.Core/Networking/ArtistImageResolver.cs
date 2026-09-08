using AuraStudio.Core.Library;

using AuraStudio.Core.Resources;

namespace AuraStudio.Core.Networking;

/// <param name="Reason">Por qué no se consiguió, cuando no se consiguió. Siempre se dice.</param>
public sealed record ArtistImageResult(byte[]? Image, string? Reason)
{
    public bool Found => Image is { Length: > 0 };
}

/// <summary>
/// La foto de un artista (ST-032). Son dos pasos y ninguno se puede saltar:
/// MusicBrainz resuelve el nombre a un identificador, y fanart.tv da la foto
/// para ese identificador.
///
/// <para><b>fanart.tv no busca por nombre</b>, así que sin el paso de
/// MusicBrainz no hay foto; y sin clave de fanart.tv no hay nada que pedir.
/// Cuando falta algo <b>se dice cuál</b>, en vez de devolver un vacío que
/// parece "este artista no tiene foto".</para>
/// </summary>
public sealed class ArtistImageResolver(
    MusicBrainzClient? musicBrainz = null,
    FanartTVClient? fanartTV = null,
    Func<bool>? hasFanartKey = null)
{
    private readonly MusicBrainzClient _musicBrainz = musicBrainz ?? new MusicBrainzClient();
    private readonly FanartTVClient _fanartTV = fanartTV ?? new FanartTVClient();
    private readonly Func<bool> _hasFanartKey = hasFanartKey ?? (() => false);

    public static string MissingKeyReason =>
        Strings.Get("artist-image.missing-key");

    public static string NoMatchReason => Strings.Get("artist-image.no-match");

    public static string NoImageReason => Strings.Get("artist-image.no-image");

    /// <summary>
    /// La foto del artista, o el motivo por el que no la hay.
    ///
    /// <para><paramref name="musicBrainzArtistId"/> se salta el primer paso
    /// cuando ya se conoce —por ejemplo, si vino en las etiquetas.</para>
    /// </summary>
    public async Task<ArtistImageResult> ResolveAsync(
        string artistName, string? musicBrainzArtistId = null, CancellationToken ct = default)
    {
        // Sin clave no se toca la red: fanart.tv devolvería 401 y el usuario se
        // quedaría con un "no se encontró" que no es cierto.
        if (!_hasFanartKey()) return new ArtistImageResult(null, MissingKeyReason);

        string? id = musicBrainzArtistId;

        if (id is not { Length: > 0 })
        {
            if (artistName.Trim().Length == 0) return new ArtistImageResult(null, NoMatchReason);

            MusicBrainzClient.Artist? artist = await _musicBrainz
                .SearchArtistAsync(artistName, ct: ct)
                .ConfigureAwait(false);

            id = artist?.Id;
        }

        if (id is not { Length: > 0 }) return new ArtistImageResult(null, NoMatchReason);

        byte[]? image = await _fanartTV.FetchArtistThumbAsync(id, ct).ConfigureAwait(false);

        return image is { Length: > 0 }
            ? new ArtistImageResult(image, null)
            : new ArtistImageResult(null, NoImageReason);
    }

    /// <summary>
    /// Lo que se le dice al usuario cuando el servicio está saturado. <b>No es
    /// un error de él ni de su biblioteca</b>, y decirlo como "falló la
    /// conexión" lo mandaría a revisar su internet.
    /// </summary>
    public static string SaturatedReason =>
        Strings.Get("artist-image.musicbrainz-busy");

    /// <summary>
    /// Cuántas saturaciones seguidas antes de dejar de insistir. Con el
    /// servicio caído, seguir pidiendo por cada uno de cientos de artistas son
    /// veinte minutos de espera para terminar sin nada.
    /// </summary>
    private const int SaturationsBeforeGivingUp = 3;

    /// <summary>
    /// Resuelve las fotos que falten de una biblioteca y las guarda. Devuelve
    /// cuántas se consiguieron.
    ///
    /// <para><b>No vuelve a pedir la de un artista que ya tiene foto</b>: son
    /// dos llamadas de red por artista, y una biblioteca real tiene cientos.</para>
    /// </summary>
    public async Task<ArtistImageBatch> FetchMissingAsync(
        IReadOnlyList<LibraryItem> items, ArtistImageStore store,
        Action<string, string?>? onArtistDone = null, CancellationToken ct = default,
        ArtistGroupingOptions? grouping = null)
    {
        int found = 0;
        int failed = 0;
        int consecutiveSaturations = 0;
        bool gaveUp = false;

        // Se agrupa con el mismo criterio que las pantallas (R2-4): una sola
        // foto para "Gorillaz", que es el efecto que R2-4 vino a conseguir.
        foreach (ArtistGroup artist in LibraryGrouping.Artists(items, grouping))
        {
            ct.ThrowIfCancellationRequested();

            if (artist.IsUnknown || store.Image(artist.Id) is not null) continue;

            ArtistImageResult result;

            try
            {
                result = await ResolveAsync(artist.Name, ct: ct).ConfigureAwait(false);
                consecutiveSaturations = 0;
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                // Que un artista falle no puede tumbar el lote: el usuario pidió
                // las fotos de su biblioteca, no las de uno.
                failed++;
                onArtistDone?.Invoke(artist.Name, MusicBrainzClient.IsSaturation(ex) ? SaturatedReason : ex.Message);

                if (!MusicBrainzClient.IsSaturation(ex)) continue;

                // Pero si el servicio está caído de verdad, insistir por cada
                // uno de cientos de artistas son veinte minutos para terminar
                // sin nada.
                if (++consecutiveSaturations < SaturationsBeforeGivingUp) continue;

                gaveUp = true;
                break;
            }

            if (result.Image is { Length: > 0 } image)
            {
                store.Save(artist.Id, image);
                found++;
            }

            onArtistDone?.Invoke(artist.Name, result.Reason);
        }

        return new ArtistImageBatch(found, failed, gaveUp);
    }
}

/// <param name="Found">Fotos conseguidas.</param>
/// <param name="Failed">Artistas que fallaron. El lote siguió igual.</param>
/// <param name="StoppedBySaturation">
/// Si se dejó de intentar porque el servicio estaba caído. <b>Es distinto de
/// "no se encontró nada"</b>: acá conviene volver más tarde, y decirlo evita
/// que el usuario crea que su biblioteca no tiene artistas reconocibles.
/// </param>
public readonly record struct ArtistImageBatch(int Found, int Failed, bool StoppedBySaturation)
{
    /// <summary>Lo que se muestra al terminar. Nunca un diálogo: una línea al pie.</summary>
    // Cinco ramas con "foto(s)" y "artista(s)" adentro. Ese paréntesis no es
    // un plural en ningún idioma; ahora cada conteo elige su forma y la frase
    // que junta las dos se arma de las dos (ST-247, B7d).
    public string Summary => this switch
    {
        { StoppedBySaturation: true, Found: 0 } =>
            Strings.Get("artist-image.failed-musicbrainz-busy"),
        { StoppedBySaturation: true } =>
            Strings.Plural("artist-image.summary-stopped-some", Found),
        { Found: 0, Failed: 0 } => Strings.Get("artist-image.none-new"),
        { Found: 0 } => Strings.Plural("artist-image.summary-none-with-failures", Failed),
        { Failed: 0 } => Strings.Plural("artist-image.summary-found", Found),
        _ => Strings.Format(
            "artist-image.summary-found-with-failures",
            Strings.Plural("artist-image.summary-found", Found),
            Strings.Plural("artist-image.summary-failed", Failed))
    };
}
