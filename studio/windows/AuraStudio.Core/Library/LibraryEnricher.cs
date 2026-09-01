using AuraStudio.Core.Networking;

namespace AuraStudio.Core.Library;

/// <summary>
/// De dónde puede salir la carátula de un álbum. El usuario elige el orden en
/// Ajustes → Servicios (D-203) y se prueba en ese orden hasta que aparezca una.
/// </summary>
public enum CoverArtProvider { CoverArtArchive, FanartTV, Deezer }

public static class CoverArtProviderInfo
{
    public static readonly IReadOnlyList<CoverArtProvider> DefaultOrder =
        [CoverArtProvider.CoverArtArchive, CoverArtProvider.FanartTV, CoverArtProvider.Deezer];

    public static string DisplayName(this CoverArtProvider provider) => provider switch
    {
        CoverArtProvider.CoverArtArchive => "Cover Art Archive",
        CoverArtProvider.FanartTV => "fanart.tv",
        _ => "Deezer"
    };
}

/// <summary>
/// Qué tanto encontró un enriquecimiento, y si algo falló <b>a nivel de red</b>.
///
/// <para>D-203: no es lo mismo "no había nada que encontrar" que "se cayó la
/// conexión", y tragarse el error hacía que los dos casos se vieran idénticos —
/// la causa más probable de que el dueño reportara que esto "no sirve para
/// nada".</para>
/// </summary>
public sealed record EnrichmentOutcome
{
    public bool AlbumInfoFound { get; set; }
    public bool LyricsFound { get; set; }
    public string? NetworkErrorMessage { get; set; }
}

/// <summary>
/// Adivina artista y título del nombre del archivo cuando no hay etiquetas. El
/// patrón más común con diferencia es "Artista - Título.ext"; si no coincide, el
/// nombre completo se usa como título. Port de <c>FilenameGuesser</c>.
/// </summary>
public static class FilenameGuesser
{
    public readonly record struct Guess(string? Artist, string? Title);

    public static Guess For(string path)
    {
        string baseName = Path.GetFileNameWithoutExtension(path);
        string[] parts = baseName.Split(" - ");

        if (parts.Length >= 2 && !LooksLikeTrackNumberPrefix(parts[0]))
            return new Guess(parts[0].Trim(), string.Join(" - ", parts[1..]).Trim());

        return new Guess(null, baseName.Trim());
    }

    /// <summary>
    /// Si el primer segmento antes de " - " es en realidad el <b>número de
    /// pista</b> pegado al nombre ("1 - Título.m4a"), no el artista.
    ///
    /// <para>Se vio en producción: decenas de canciones sin etiqueta de artista
    /// terminaron en carpetas del iPod llamadas literalmente "1".."20" —una por
    /// número de pista, mezclando artistas distintos— en vez de en
    /// "Desconocido".</para>
    ///
    /// <para>La heurística es imperfecta <b>a propósito</b>: un artista real
    /// como "21 Savage" cae en "Desconocido" en vez de en su nombre, que es
    /// muchísimo mejor que agrupar decenas de artistas bajo una carpeta "1".</para>
    /// </summary>
    public static bool LooksLikeTrackNumberPrefix(string segment)
    {
        string trimmed = segment.Trim();

        int firstNonDigit = -1;
        for (int i = 0; i < trimmed.Length; i++)
            if (!char.IsDigit(trimmed[i])) { firstNonDigit = i; break; }

        // Puramente numérico: "01", "7". No es un nombre de artista plausible.
        if (firstNonDigit < 0) return trimmed.Length > 0;

        if (firstNonDigit is < 1 or > 3) return false;
        return trimmed[firstNonDigit] == ' ';
    }
}

/// <summary>
/// Orquesta el "arrastrar y listo" de una canción: parte de lo que ya trae el
/// archivo, completa lo que falte con MusicBrainz / Cover Art Archive / LRCLIB,
/// y devuelve metadata lista para escribir. Port de <c>LibraryEnricher.swift</c>.
///
/// <para><b>Solo llena huecos.</b> Nunca reemplaza un campo que ya tiene valor:
/// eso es lo que protege una corrección que el usuario hizo a mano.</para>
///
/// <para>No copia nada al iPod — eso es de la sincronización, después de que el
/// usuario revise.</para>
/// </summary>
public sealed class LibraryEnricher(
    MusicBrainzClient? musicBrainz = null,
    CoverArtArchiveClient? coverArt = null,
    LRCLIBClient? lrclib = null,
    FanartTVClient? fanartTV = null,
    DeezerClient? deezer = null,
    Func<string, Task<TrackMetadata>>? readTag = null)
{
    private readonly MusicBrainzClient _musicBrainz = musicBrainz ?? new MusicBrainzClient();
    private readonly CoverArtArchiveClient _coverArt = coverArt ?? new CoverArtArchiveClient();
    private readonly LRCLIBClient _lrclib = lrclib ?? new LRCLIBClient();
    private readonly FanartTVClient _fanartTV = fanartTV ?? new FanartTVClient();
    private readonly DeezerClient _deezer = deezer ?? new DeezerClient();

    /// <summary>La lectura local de etiquetas, inyectable para poder probar sin archivos.</summary>
    private readonly Func<string, Task<TrackMetadata>> _readTag =
        readTag ?? (path => Task.FromResult(LocalTagReader.Read(path)));

    /// <summary>
    /// Piso de <c>score</c> de MusicBrainz (0–100) para aceptar una grabación
    /// como fuente de álbum y año.
    ///
    /// <para>La búsqueda siempre devuelve el resultado de mayor puntaje aunque
    /// sea bajo, y usarlo sin piso hacía que dos canciones del mismo álbum real
    /// terminaran con álbumes distintos. Sin etiquetas locales es mejor dejar
    /// "Sin álbum" —que se puede revisar— que inventar uno. Un puntaje ausente
    /// cuenta como 0: se rechaza.</para>
    /// </summary>
    public const int MinimumMusicBrainzScore = 70;

    /// <summary>
    /// <paramref name="online"/> y <paramref name="lyrics"/> salen de las
    /// preferencias: sin conexión no se toca la red y solo se usa lo que trae el
    /// archivo más lo que se adivine del nombre.
    /// </summary>
    public async Task<TrackMetadata> EnrichAsync(
        LibraryItem item, bool online = true, bool lyrics = true,
        IReadOnlyList<CoverArtProvider>? coverArtOrder = null, bool deezerEnabled = true,
        CancellationToken ct = default)
    {
        TrackMetadata metadata = await _readTag(item.SourcePath).ConfigureAwait(false);

        FilenameGuesser.Guess guess = FilenameGuesser.For(item.SourcePath);
        metadata.Title ??= guess.Title;
        metadata.Artist ??= guess.Artist;

        if (!online) return metadata;

        MusicBrainzClient.Recording? recording;
        try
        {
            recording = await _musicBrainz
                .SearchRecordingAsync(metadata.Title, metadata.Artist, ct)
                .ConfigureAwait(false);
        }
        catch (Exception)
        {
            // Este camino corre al importar, en lote: un error de red no puede
            // detener la importación. Quien quiere saber del error usa
            // ReenrichAsync, que sí lo reporta.
            return metadata;
        }

        if (recording is null || (recording.Score ?? 0) < MinimumMusicBrainzScore) return metadata;

        ApplyRecording(metadata, recording);
        await ApplyReleaseAsync(metadata, recording, coverArtOrder, deezerEnabled, ct).ConfigureAwait(false);

        if (lyrics && metadata is { Title: { } title, Artist: { } artist })
        {
            try
            {
                metadata.SyncedLyrics = await _lrclib
                    .FetchSyncedLyricsAsync(title, artist, metadata.Album, ct: ct)
                    .ConfigureAwait(false);
            }
            catch (Exception) { /* ídem: sin letra, pero la canción entra */ }
        }

        return metadata;
    }

    /// <summary>
    /// "Buscar información" / "Buscar letra" del menú contextual (D-198). A
    /// diferencia de <see cref="EnrichAsync"/> —que parte de las etiquetas
    /// crudas del archivo— parte de la metadata <b>ya resuelta</b> del item,
    /// para no pisar una corrección que el usuario hizo en la pantalla de
    /// revisión. Igual que aquélla, solo llena huecos.
    ///
    /// <para>Y a diferencia de aquélla, <b>no se traga los errores de red</b>:
    /// devuelve un <see cref="EnrichmentOutcome"/> para que la pantalla pueda
    /// decir "no se encontró nada" o "falló la conexión", que no son lo
    /// mismo.</para>
    /// </summary>
    public async Task<(TrackMetadata Metadata, EnrichmentOutcome Outcome)> ReenrichAsync(
        LibraryItem item, TrackMetadata currentMetadata, bool fetchAlbumInfo, bool fetchLyrics,
        IReadOnlyList<CoverArtProvider>? coverArtOrder = null, bool deezerEnabled = true,
        CancellationToken ct = default)
    {
        TrackMetadata metadata = currentMetadata;
        var outcome = new EnrichmentOutcome();

        FilenameGuesser.Guess guess = FilenameGuesser.For(item.SourcePath);
        string? seedTitle = metadata.Title ?? guess.Title;
        string? seedArtist = metadata.Artist ?? guess.Artist;

        if (fetchAlbumInfo)
        {
            try
            {
                MusicBrainzClient.Recording? recording = await _musicBrainz
                    .SearchRecordingAsync(seedTitle, seedArtist, ct)
                    .ConfigureAwait(false);

                if (recording is not null && (recording.Score ?? 0) >= MinimumMusicBrainzScore)
                {
                    outcome.AlbumInfoFound = true;
                    ApplyRecording(metadata, recording);
                    await ApplyReleaseAsync(metadata, recording, coverArtOrder, deezerEnabled, ct)
                        .ConfigureAwait(false);
                }
            }
            catch (Exception ex)
            {
                outcome.NetworkErrorMessage = ex.Message;
            }
        }

        if (fetchLyrics && metadata is { Title: { } title, Artist: { } artist })
        {
            try
            {
                metadata.SyncedLyrics = await _lrclib
                    .FetchSyncedLyricsAsync(title, artist, metadata.Album, ct: ct)
                    .ConfigureAwait(false);
                outcome.LyricsFound = metadata.SyncedLyrics is not null;
            }
            catch (Exception ex)
            {
                // El primer error de red es el que se muestra; el segundo no
                // agrega nada útil para el usuario.
                outcome.NetworkErrorMessage ??= ex.Message;
            }
        }

        return (metadata, outcome);
    }

    private static void ApplyRecording(TrackMetadata metadata, MusicBrainzClient.Recording recording)
    {
        metadata.Title ??= recording.Title;
        metadata.Artist ??= recording.ArtistCredit?.FirstOrDefault()?.Name;
        metadata.MusicBrainzRecordingId ??= recording.Id;
    }

    private async Task ApplyReleaseAsync(
        TrackMetadata metadata, MusicBrainzClient.Recording recording,
        IReadOnlyList<CoverArtProvider>? coverArtOrder, bool deezerEnabled, CancellationToken ct)
    {
        if (recording.Releases?.FirstOrDefault() is not { } release) return;

        metadata.Album ??= release.Title;
        metadata.Year ??= release.Date is { Length: >= 4 } date ? date[..4] : null;
        metadata.MusicBrainzReleaseId ??= release.Id;

        if (metadata.CoverArtData is null)
            metadata.CoverArtData = await ResolveCoverArtAsync(
                release.Id, release.ReleaseGroup?.Id, metadata.Title, metadata.Artist,
                coverArtOrder ?? CoverArtProviderInfo.DefaultOrder, deezerEnabled, ct)
                .ConfigureAwait(false);
    }

    /// <summary>
    /// Prueba los proveedores en el orden que eligió el usuario y devuelve la
    /// primera imagen que aparezca. Cada cliente ya devuelve <c>null</c> solo
    /// cuando no corresponde intentarlo (sin clave, o sin resultado); acá solo
    /// hace falta saltear Deezer si el usuario lo apagó, y que un proveedor que
    /// falla no tumbe a los demás.
    /// </summary>
    private async Task<byte[]?> ResolveCoverArtAsync(
        string releaseId, string? releaseGroupId, string? title, string? artist,
        IReadOnlyList<CoverArtProvider> order, bool deezerEnabled, CancellationToken ct)
    {
        foreach (CoverArtProvider provider in order)
        {
            try
            {
                byte[]? data = provider switch
                {
                    CoverArtProvider.CoverArtArchive =>
                        await _coverArt.FetchFrontCoverAsync(releaseId, ct).ConfigureAwait(false),

                    CoverArtProvider.FanartTV when releaseGroupId is not null =>
                        await _fanartTV.FetchAlbumCoverAsync(releaseGroupId, ct).ConfigureAwait(false),

                    CoverArtProvider.Deezer when deezerEnabled && title is not null && artist is not null =>
                        await _deezer.FetchAlbumCoverAsync(title, artist, ct).ConfigureAwait(false),

                    _ => null
                };

                if (data is { Length: > 0 }) return data;
            }
            catch (Exception)
            {
                // Un proveedor caído no puede impedir que se pruebe el siguiente.
            }
        }

        return null;
    }
}
