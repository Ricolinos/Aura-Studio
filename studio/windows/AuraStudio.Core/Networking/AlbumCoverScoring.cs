using AuraStudio.Core.Library;

namespace AuraStudio.Core.Networking;

/// <summary>
/// Los hechos del álbum en la biblioteca, contra los que se puntúa cada
/// candidata: su título, su año y cuántas pistas tiene realmente.
/// </summary>
public sealed record AlbumFacts(string? Title, string? Year, int TrackCount);

/// <summary>
/// Lo que se sabe de la <b>edición</b> de la que salió una tapa.
///
/// <para>Deezer no es una edición: no trae año, ni número de pistas, ni
/// estatus, ni país. Por construcción solo puede sumar el puntaje del título —
/// y por eso su techo es 50, debajo del umbral.</para>
/// </summary>
public sealed record AlbumCoverEdition(
    string? Title = null,
    string? Year = null,
    int TrackCount = 0,
    string? Status = null,
    string? Country = null,
    bool IsFrontCover = false)
{
    public static readonly AlbumCoverEdition Unknown = new();

    public bool IsOfficial => string.Equals(Status, "Official", StringComparison.OrdinalIgnoreCase);
}

/// <summary>
/// Con qué criterio se recomienda una tapa entre varias candidatas (R2-3).
///
/// <para>La especificación vinculante es <c>docs/caratula-recomendada.md</c> y
/// la implementación de referencia es <c>AlbumCoverScoring.swift</c>.
/// <b>"Parecido" no sirve</b>: si las dos apps recomiendan tapas distintas para
/// el mismo disco, el dueño ve la biblioteca cambiar sola según desde qué
/// máquina la abrió. Si cambia un número, cambia en los tres lugares —
/// documento, macOS y Windows— en el mismo cambio.</para>
/// </summary>
public static class AlbumCoverScoring
{
    public const int TitlePoints = 50;
    public const int YearPoints = 25;
    public const int TrackCountPoints = 15;
    public const int OfficialPoints = 6;
    public const int CountryPoints = 2;
    public const int PreferredCountryPoints = 2;
    public const int FrontCoverPoints = 10;

    /// <summary>50 + 25 + 15 + 6 + 2 + 2 + 10.</summary>
    public const int MaximumScore = 110;

    /// <summary>
    /// El puntaje mínimo para aplicar <b>sin preguntar</b>.
    ///
    /// <para>Las dos combinaciones mínimas que llegan son título + año + tapa
    /// frontal (85) y título + nº de pistas + oficial + país preferido + tapa
    /// frontal (85). Lo que deliberadamente NO alcanza: solo el título (50) —
    /// que es el caso que el umbral existe para frenar, porque "Greatest Hits"
    /// coincide de título con el de cualquier otro artista.</para>
    /// </summary>
    public const int AutoApplyThreshold = 85;

    /// <summary><c>XW</c> es "mundial" en MusicBrainz.</summary>
    public static readonly IReadOnlySet<string> PreferredCountries =
        new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "XW", "MX", "US", "GB" };

    /// <summary>
    /// El puntaje de una candidata. Los pesos están elegidos para que el orden
    /// de importancia <b>se respete siempre</b>: todo lo que está debajo del
    /// título suma 62, menos que título + año (75), así que una edición con
    /// título distinto nunca le gana a una con título y año iguales.
    /// </summary>
    public static int Score(AlbumCoverEdition edition, AlbumFacts album)
    {
        int score = 0;

        if (Matches(edition.Title, album.Title)) score += TitlePoints;
        if (Matches(edition.Year, album.Year)) score += YearPoints;

        // Un conteo de 0 nunca coincide: "no sé cuántas pistas tiene" no es
        // una coincidencia con "el álbum no tiene pistas".
        if (edition.TrackCount > 0 && edition.TrackCount == album.TrackCount) score += TrackCountPoints;

        if (edition.IsOfficial) score += OfficialPoints;

        if (edition.Country is { Length: > 0 } country)
        {
            score += CountryPoints;
            if (PreferredCountries.Contains(country.Trim())) score += PreferredCountryPoints;
        }

        if (edition.IsFrontCover) score += FrontCoverPoints;

        return score;
    }

    public static bool CanApplyWithoutAsking(int score) => score >= AutoApplyThreshold;

    /// <summary>
    /// Las candidatas en el orden en que hay que mostrarlas — <b>la recomendada
    /// es siempre la primera</b>.
    ///
    /// <para>Los desempates se agotan hasta el orden de descubrimiento, que es
    /// el que garantiza un orden total: sin él, dos candidatas empatadas hasta
    /// ahí quedarían en orden indefinido y las dos apps (o dos corridas de la
    /// misma) podrían recomendar distinto.</para>
    /// </summary>
    public static IReadOnlyList<AlbumCoverCandidate> Rank(
        IEnumerable<AlbumCoverCandidate> candidates, AlbumFacts album)
    {
        // El orden de descubrimiento es la posición en que llegaron: la lista
        // se acumula tal como la devolvieron las fuentes.
        List<AlbumCoverCandidate> scored =
            [.. candidates.Select((candidate, index) => candidate with
            {
                DiscoveryOrder = index,
                Score = Score(candidate.Edition, album)
            })];

        scored.Sort(Compare);
        return scored;
    }

    /// <summary>
    /// La recomendada, o <c>null</c> si no hay candidatas. <b>Que exista una
    /// recomendada no autoriza a aplicarla</b>: eso lo decide
    /// <see cref="CanApplyWithoutAsking"/> sobre su puntaje.
    /// </summary>
    public static AlbumCoverCandidate? Recommended(
        IEnumerable<AlbumCoverCandidate> candidates, AlbumFacts album) =>
        Rank(candidates, album).FirstOrDefault();

    /// <summary>Menor que cero si <paramref name="a"/> va antes.</summary>
    public static int Compare(AlbumCoverCandidate a, AlbumCoverCandidate b)
    {
        int byScore = b.Score.CompareTo(a.Score);
        if (byScore != 0) return byScore;

        int byFront = b.Edition.IsFrontCover.CompareTo(a.Edition.IsFrontCover);
        if (byFront != 0) return byFront;

        int byOfficial = b.Edition.IsOfficial.CompareTo(a.Edition.IsOfficial);
        if (byOfficial != 0) return byOfficial;

        // La edición original antes que las reediciones: es la tapa que la
        // gente reconoce como la del disco. Una edición sin año va al final —
        // no se puede afirmar que sea la original.
        int byYear = YearRank(a.Edition.Year).CompareTo(YearRank(b.Edition.Year));
        if (byYear != 0) return byYear;

        int bySource = SourceRank(a.Source).CompareTo(SourceRank(b.Source));
        if (bySource != 0) return bySource;

        return a.DiscoveryOrder.CompareTo(b.DiscoveryOrder);
    }

    private static int YearRank(string? year) =>
        int.TryParse((year ?? "").Trim(), out int parsed) ? parsed : int.MaxValue;

    private static int SourceRank(AlbumCoverSource source) =>
        source == AlbumCoverSource.CoverArtArchive ? 0 : 1;

    /// <summary>
    /// Normalizar = recortar espacios extremos e ignorar mayúsculas y acentos —
    /// la misma normalización con la que se agrupa la biblioteca. <b>Dos
    /// títulos vacíos no son coincidencia.</b>
    /// </summary>
    private static bool Matches(string? one, string? other)
    {
        string a = LibraryGrouping.Normalize(one);
        string b = LibraryGrouping.Normalize(other);

        return a.Length > 0 && a == b;
    }
}
