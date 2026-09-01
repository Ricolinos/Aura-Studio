using AuraStudio.Core.Library;

namespace AuraStudio.Core.Networking;

public enum AlbumCoverSource
{
    CoverArtArchive,
    Deezer
}

public static class AlbumCoverSourceNames
{
    public static string DisplayName(this AlbumCoverSource source) =>
        source == AlbumCoverSource.Deezer ? "Deezer" : "Cover Art Archive";
}

/// <param name="Detail">
/// De qué edición salió, para poder distinguir dos tapas parecidas
/// ("Signos · 1986"). Puede faltar: no todas las fuentes lo traen.
/// </param>
public sealed record AlbumCoverCandidate(byte[] Data, AlbumCoverSource Source, string? Detail)
{
    public string SourceName => Source.DisplayName();

    /// <summary>De qué edición salió — lo que se puntúa (R2-3).</summary>
    public AlbumCoverEdition Edition { get; init; } = AlbumCoverEdition.Unknown;

    /// <summary>
    /// En qué posición la devolvió su fuente. Es el último desempate, el que
    /// garantiza que dos corridas ordenen igual.
    /// </summary>
    public int DiscoveryOrder { get; init; }

    /// <summary>El puntaje contra el álbum, ya calculado al armar la lista.</summary>
    public int Score { get; init; }

    /// <summary>Si se puede aplicar sin preguntar. Ver <c>docs/caratula-recomendada.md</c>.</summary>
    public bool CanApplyWithoutAsking => AlbumCoverScoring.CanApplyWithoutAsking(Score);
}

/// <summary>
/// Las tapas posibles de un álbum, para que el usuario <b>elija</b> (ST-104).
///
/// <para>"Completar en línea" baja una y la aplica sin preguntar, y está bien
/// para cientos de canciones de un tirón. Pero mirando un álbum concreto con la
/// tapa equivocada, la única salida era quitarla y quedarse sin ninguna.</para>
///
/// <para>La diferencia con el póster de una película es deliberada: TMDB
/// identifica una película con bastante certeza, mientras que <b>dos ediciones
/// del mismo disco tienen tapas distintas y las dos son correctas</b>. Ahí
/// elegir no es un lujo, es la única forma de acertar — por eso esto nunca
/// aplica nada solo, ni siquiera cuando encuentra una sola.</para>
/// </summary>
public sealed class AlbumCoverSearch(
    MusicBrainzClient? musicBrainz = null,
    CoverArtArchiveClient? coverArtArchive = null,
    DeezerClient? deezer = null)
{
    private readonly MusicBrainzClient _musicBrainz = musicBrainz ?? new MusicBrainzClient();
    private readonly CoverArtArchiveClient _coverArtArchive = coverArtArchive ?? new CoverArtArchiveClient();
    private readonly DeezerClient _deezer = deezer ?? new DeezerClient();

    /// <summary>Cuántas ediciones pedirle a MusicBrainz — una llamada al archivo de tapas por cada una.</summary>
    public int ReleasesToTry { get; init; } = 5;

    public int MaximumCandidates { get; init; } = 10;

    public const string NoResultsReason =
        "No se encontraron tapas para este álbum. Revisa que el título y el artista estén bien escritos.";

    public const string NoResultsWithoutDeezerHint =
        "También puedes activar Deezer en Ajustes › Servicios para buscar en más lugares.";

    /// <summary>
    /// Las candidatas, en el orden en que conviene mostrarlas: primero Cover Art
    /// Archive —la fuente alineada con MusicBrainz, de donde sale el resto de la
    /// metadata— y después Deezer.
    ///
    /// <para>Mejor esfuerzo de punta a punta: <b>MusicBrainz caído no puede
    /// dejar sin resultados una búsqueda que Deezer sí podía contestar</b>.</para>
    /// </summary>
    public async Task<IReadOnlyList<AlbumCoverCandidate>> CandidatesAsync(
        string album, string? artist, bool deezerEnabled = true, CancellationToken ct = default,
        AlbumFacts? facts = null)
    {
        string title = (album ?? "").Trim();

        // "Sin álbum" no es un disco sino el cajón de lo que no tiene uno: no
        // hay tapa que buscarle.
        if (title.Length == 0 || title == LibraryGrouping.UnknownAlbumTitle) return [];

        string? artistName = artist?.Trim() is { Length: > 0 } name && name != LibraryGrouping.UnknownArtistName
            ? name
            : null;

        var result = new List<AlbumCoverCandidate>();
        var seen = new List<byte[]>();

        void Append(byte[]? data, AlbumCoverSource source, string? detail, AlbumCoverEdition edition)
        {
            if (data is not { Length: > 0 } || result.Count >= MaximumCandidates) return;

            // Dos ediciones que comparten la misma imagen se muestran una sola
            // vez: ofrecer dos veces lo mismo solo obliga a comparar dos
            // imágenes idénticas.
            if (seen.Any(other => other.AsSpan().SequenceEqual(data))) return;

            seen.Add(data);
            result.Add(new AlbumCoverCandidate(data, source, detail) { Edition = edition });
        }

        // Puntuadas y ordenadas: la recomendada es siempre la primera, y la
        // lista que ve el usuario va en ese mismo orden (R2-3). Sin hechos del
        // álbum solo se puede puntuar el título — es lo que había antes.
        IReadOnlyList<AlbumCoverCandidate> Ranked() =>
            AlbumCoverScoring.Rank(result, facts ?? new AlbumFacts(title, null, 0));

        try
        {
            IReadOnlyList<MusicBrainzClient.Release> releases = await _musicBrainz
                .SearchReleasesAsync(title, artistName, ReleasesToTry, ct)
                .ConfigureAwait(false);

            foreach (MusicBrainzClient.Release release in releases)
            {
                if (result.Count >= MaximumCandidates) break;

                try
                {
                    (byte[]? data, bool isFront) = await _coverArtArchive
                        .FetchCoverAsync(release.Id, ct).ConfigureAwait(false);

                    Append(data, AlbumCoverSource.CoverArtArchive,
                        Detail(release.Title, Year(release.Date)),
                        new AlbumCoverEdition(
                            Title: release.Title,
                            Year: Year(release.Date),
                            TrackCount: release.TrackCount ?? 0,
                            Status: release.Status,
                            Country: release.Country,
                            IsFrontCover: isFront));
                }
                catch (Exception ex) when (ex is not OperationCanceledException)
                {
                    // Una edición sin tapa no puede cortar la búsqueda de las demás.
                }
            }
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            // MusicBrainz caído: se sigue con Deezer.
        }

        if (!deezerEnabled || result.Count >= MaximumCandidates) return Ranked();

        try
        {
            IReadOnlyList<DeezerClient.AlbumMatch> matches = await _deezer
                .SearchAlbumCoversAsync(title, artistName, ct: ct)
                .ConfigureAwait(false);

            foreach (DeezerClient.AlbumMatch match in matches)
            {
                if (result.Count >= MaximumCandidates) break;

                byte[]? data = await _deezer.FetchImageAsync(match.CoverUrl, ct).ConfigureAwait(false);

                // Deezer no es una edición: solo puede sumar el puntaje del
                // título, así que su techo queda debajo del umbral.
                Append(data, AlbumCoverSource.Deezer, Detail(match.Title, match.Artist),
                    new AlbumCoverEdition(Title: match.Title));
            }
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            // Deezer caído: quedan las de Cover Art Archive.
        }

        return Ranked();
    }

    /// <summary>
    /// Qué decir cuando no se encontró nada. <b>Se dice en pantalla</b>: no se
    /// cierra sola ni deja la tapa vieja sin explicación.
    /// </summary>
    public static string NoResultsMessage(bool deezerEnabled) =>
        deezerEnabled ? NoResultsReason : NoResultsReason + " " + NoResultsWithoutDeezerHint;

    /// <summary>"Signos · 1986" — las dos partes son opcionales.</summary>
    public static string? Detail(string? title, string? extra)
    {
        string[] parts = [.. new[] { title, extra }.Where(part => part is { Length: > 0 })!];

        return parts.Length == 0 ? null : string.Join(" · ", parts);
    }

    /// <summary>MusicBrainz da la fecha completa (<c>1986-11-25</c>) o solo el año.</summary>
    public static string? Year(string? date)
    {
        if (date is not { Length: >= 4 }) return null;

        string year = date[..4];
        return year.All(char.IsAsciiDigit) ? year : null;
    }
}
