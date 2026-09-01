using System.Text.RegularExpressions;

namespace AuraStudio.Core.Networking;

/// <summary>
/// Saca título, año y (si es serie) nombre de la serie del nombre de
/// archivo o del título que ya tenga el video (ST-033). Los nombres
/// reales vienen como <c>The.Matrix.1999.1080p.BluRay.x264.mkv</c> o
/// <c>Breaking Bad - S01E02 - Cat's in the Bag.mp4</c>; sin limpiar eso,
/// la búsqueda en TMDB no encuentra nada.
/// </summary>
public static class VideoTitleParser
{
    /// <summary>Resultado del parseo de un título de video.</summary>
    public readonly struct Parsed : IEquatable<Parsed>
    {
        public string Title { get; init; }
        public string? Year { get; init; }
        public string? SeriesName { get; init; }
        public int? Season { get; init; }
        public int? Episode { get; init; }

        public bool IsEpisode => SeriesName != null;

        public bool Equals(Parsed other) =>
            Title == other.Title && Year == other.Year && SeriesName == other.SeriesName &&
            Season == other.Season && Episode == other.Episode;

        public override bool Equals(object? obj) => obj is Parsed other && Equals(other);

        public override int GetHashCode() => HashCode.Combine(Title, Year, SeriesName, Season, Episode);
    }

    private static readonly HashSet<string> NoiseTokens = new(StringComparer.OrdinalIgnoreCase)
    {
        "1080p", "720p", "480p", "2160p", "4k", "uhd", "hdr", "hdr10", "dv", "x264", "x265", "h264", "h265", "hevc",
        "avc", "aac", "ac3", "dts", "bluray", "bdrip", "brrip", "webrip", "web-dl", "webdl", "web", "hdtv", "dvdrip",
        "dvd", "remux", "proper", "repack", "extended", "unrated", "remastered", "multi", "dual", "latino", "castellano",
        "subs", "sub", "esp", "eng", "spa", "lat", "amzn", "nf", "dsnp", "hmax", "atvp", "yify", "yts", "rarbg", "10bit",
        "5.1", "7.1", "ddp5.1", "dd5.1", "atmos", "imax", "hq", "xvid", "divx", "mkv", "mp4", "avi",
    };

    // Expresiones regulares compiladas (se usan en cada llamada a Parse)
    private static readonly Regex BracketRegex = new(@"\[([^\]]*)\]", RegexOptions.Compiled);
    private static readonly Regex EpisodeRegex = new(@"(?i)\bS(\d{1,2})\s?E(\d{1,3})\b|\b(\d{1,2})x(\d{2,3})\b", RegexOptions.Compiled);
    private static readonly Regex YearRegex = new(@"\(?\b(19\d{2}|20\d{2})\b\)?", RegexOptions.Compiled);
    private static readonly Regex SpaceRegex = new(@"\s+", RegexOptions.Compiled);

    /// <summary>Parsea un título de video en sus componentes.</summary>
    public static Parsed Parse(string raw)
    {
        var text = raw.Replace("_", " ").Replace(".", " ");
        // Quitar etiquetas entre corchetes ([1080p], [Latino], [grupo])
        text = BracketRegex.Replace(text, " ");

        var parsed = new Parsed { Title = text };

        // Serie: "S01E02", "s1e2", "1x02"
        var epMatch = EpisodeRegex.Match(text);
        if (epMatch.Success)
        {
            var numbers = Regex.Split(epMatch.Value, @"\D+").Where(s => !string.IsNullOrEmpty(s)).ToArray();
            if (numbers.Length >= 2 && int.TryParse(numbers[0], out var season) && int.TryParse(numbers[1], out var ep))
            {
                parsed = parsed with { Season = season, Episode = ep };
                var before = text[..epMatch.Index];
                var seriesName = CleanTitle(before);
                if (!string.IsNullOrEmpty(seriesName))
                    parsed = parsed with { SeriesName = seriesName };
                text = before;
            }
        }

        // Año entre 1900 y 2099, con o sin paréntesis; el ÚLTIMO que aparezca
        var yearMatches = YearRegex.Matches(text);
        if (yearMatches.Count > 0)
        {
            var last = yearMatches[^1];
            var yearGroup = last.Groups[1];
            // Si el "año" es lo único que hay (película que se llama "2012"), no se lo quites al título
            var before = text[..last.Index];
            var remainder = CleanTitle(before);
            if (!string.IsNullOrEmpty(remainder))
            {
                parsed = parsed with { Year = yearGroup.Value };
                text = before;
            }
        }

        var cleaned = CleanTitle(text);
        parsed = parsed with { Title = string.IsNullOrEmpty(cleaned) ? CleanTitle(raw) : cleaned };
        return parsed;
    }

    /// <summary>Quita tokens de ruido (calidad, códec, grupo), guiones sueltos y espacios repetidos.</summary>
    public static string CleanTitle(string text)
    {
        var tokens = SpaceRegex.Replace(text, " ").Split(' ', StringSplitOptions.RemoveEmptyEntries);
        var kept = new List<string>();
        foreach (var token in tokens)
        {
            var lower = token.ToLowerInvariant().Trim('-', '–', '(', ')');
            if (string.IsNullOrEmpty(lower)) continue;
            if (NoiseTokens.Contains(lower)) break; // lo que sigue al primer token de ruido es más ruido
            kept.Add(token.Trim('(', ')'));
        }
        var result = string.Join(" ", kept);
        return result.Trim(' ', '-', '–');
    }
}