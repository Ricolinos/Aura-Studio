namespace AuraStudio.Core.Networking;

/// <summary>
/// Orchestrates poster lookup for a video (ST-033): TMDB resolves the
/// title; fanart.tv contributes the curated poster if available; if not,
/// TMDB poster is used as fallback. Best effort, never throws.
/// </summary>
public sealed class VideoArtworkResolver
{
    /// <summary>Kind of video content.</summary>
    public enum Kind { Movie, Series, Unknown }

    /// <summary>Source of the poster image.</summary>
    public enum Source { FanartTV, TMDB }

    /// <summary>Result of artwork resolution.</summary>
    public readonly struct ArtworkResult
    {
        public byte[] Data { get; init; }
        public Source Source { get; init; }
        public string MatchedTitle { get; init; }
        public string? Year { get; init; }
    }

    /// <summary>Possible failure reasons.</summary>
    public enum Failure { MissingTMDBKey, NoMatch, NoPoster }

    private readonly TMDBClient _tmdb;
    private readonly FanartTVClient _fanart;
    private readonly Func<bool> _hasFanartKey;

    public VideoArtworkResolver(
        TMDBClient? tmdb = null,
        FanartTVClient? fanart = null,
        Func<bool>? hasFanartKey = null)
    {
        _tmdb = tmdb ?? new TMDBClient();
        _fanart = fanart ?? new FanartTVClient();
        _hasFanartKey = hasFanartKey ?? (() => false);
    }

    /// <summary>
    /// Resolves the best available poster for a video.
    /// <paramref name="kind"/> comes from the video category in Studio
    /// (Movies/Series/Videos). With <c>Unknown</c>, we try movie then series
    /// (or vice versa if the name contains SxxEyy).
    /// </summary>
    public async Task<ArtworkResult?> ResolveAsync(string rawTitle, Kind kind, CancellationToken ct = default)
    {
        if (!_tmdb.HasAPIKey)
            return null;

        var parsed = VideoTitleParser.Parse(rawTitle);
        var order = kind switch
        {
            Kind.Movie => new[] { Kind.Movie },
            Kind.Series => new[] { Kind.Series },
            Kind.Unknown => parsed.IsEpisode
                ? new[] { Kind.Series, Kind.Movie }
                : new[] { Kind.Movie, Kind.Series },
            _ => throw new ArgumentOutOfRangeException(nameof(kind), kind, null),
        };

        foreach (var candidate in order)
        {
            switch (candidate)
            {
                case Kind.Movie:
                    var movie = await _tmdb.SearchMovieAsync(parsed.Title, parsed.Year, ct).ConfigureAwait(false);
                    if (movie == null) continue;

                    if (_hasFanartKey())
                    {
                        var fanartData = await _fanart.FetchMoviePosterAsync(movie.Id.ToString(), ct).ConfigureAwait(false);
                        if (fanartData?.Length > 0)
                            return new ArtworkResult
                            {
                                Data = fanartData,
                                Source = Source.FanartTV,
                                MatchedTitle = movie.Title,
                                Year = movie.Year
                            };
                    }
                    var tmdbData = await _tmdb.DownloadPosterAsync(movie.PosterPath, ct).ConfigureAwait(false);
                    if (tmdbData?.Length > 0)
                        return new ArtworkResult
                        {
                            Data = tmdbData,
                            Source = Source.TMDB,
                            MatchedTitle = movie.Title,
                            Year = movie.Year
                        };
                    break;

                case Kind.Series:
                    var name = parsed.SeriesName ?? parsed.Title;
                    var show = await _tmdb.SearchTVAsync(name, parsed.IsEpisode ? null : parsed.Year, ct).ConfigureAwait(false);
                    if (show == null) continue;

                    if (_hasFanartKey())
                    {
                        var tvdbId = await _tmdb.GetTvdbIDAsync(show.Id, ct).ConfigureAwait(false);
                        if (tvdbId.HasValue)
                        {
                            var fanartData = await _fanart.FetchTVPosterAsync(tvdbId.Value.ToString(), ct).ConfigureAwait(false);
                            if (fanartData?.Length > 0)
                                return new ArtworkResult
                                {
                                    Data = fanartData,
                                    Source = Source.FanartTV,
                                    MatchedTitle = show.Name,
                                    Year = show.Year
                                };
                        }
                    }
                    var tmdbData2 = await _tmdb.DownloadPosterAsync(show.PosterPath, ct).ConfigureAwait(false);
                    if (tmdbData2?.Length > 0)
                        return new ArtworkResult
                        {
                            Data = tmdbData2,
                            Source = Source.TMDB,
                            MatchedTitle = show.Name,
                            Year = show.Year
                        };
                    break;
            }
        }
        return null;
    }

    /// <summary>
    /// Mensaje para cuando no hay clave de TMDB. <b>fanart.tv no busca por
    /// título</b>: hace falta el identificador, y el único que lo resuelve es
    /// TMDB. Sin esa clave no hay póster por ningún camino, y decirlo es
    /// distinto de decir "no se encontró".
    /// </summary>
    public const string MissingKeyReason =
        "Para los pósters de video hace falta una clave de TMDB (Ajustes › Servicios).";

    public const string NoMatchReason = "No se encontró un póster para este video.";

    /// <summary>
    /// El póster, o el motivo por el que no lo hay.
    ///
    /// <para>Existe además de <see cref="ResolveAsync"/> porque un <c>null</c>
    /// suelto no le sirve a nadie: la pantalla necesita distinguir "te falta la
    /// clave" de "no está", y esas dos cosas mandan al usuario a lugares
    /// distintos.</para>
    /// </summary>
    public async Task<VideoArtworkOutcome> ResolveWithReasonAsync(
        string rawTitle, Kind kind, CancellationToken ct = default)
    {
        if (!_tmdb.HasAPIKey) return new VideoArtworkOutcome(null, MissingKeyReason);

        ArtworkResult? result = await ResolveAsync(rawTitle, kind, ct).ConfigureAwait(false);

        return result is { Data.Length: > 0 } found
            ? new VideoArtworkOutcome(found, null)
            : new VideoArtworkOutcome(null, NoMatchReason);
    }

    /// <summary>De qué categoría de Studio viene el video.</summary>
    public static Kind KindOf(string? category) =>
        MediaCategoryNames.IsMoviesCategory(category) ? Kind.Movie
        : MediaCategoryNames.IsSeriesCategory(category) ? Kind.Series
        : Kind.Unknown;
}

/// <param name="Reason">Por qué no hay póster, cuando no lo hay. Siempre se dice.</param>
public readonly record struct VideoArtworkOutcome(VideoArtworkResolver.ArtworkResult? Poster, string? Reason)
{
    public bool Found => Poster is { Data.Length: > 0 };
}


