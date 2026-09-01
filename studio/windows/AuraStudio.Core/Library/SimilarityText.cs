using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace AuraStudio.Core.Library;

/// <summary>
/// Normalización y comparación de texto para el detector de similares. Está
/// aparte porque es la mitad del detector que se puede afirmar caso por caso:
/// si "01 Amor" y "Amor" no normalizan igual, nada del resto funciona.
/// Port de la primera mitad de <c>SimilarItemsDetector.swift</c>.
/// </summary>
public static partial class SimilarityText
{
    /// <summary>
    /// Palabras que distinguen versiones legítimas de una misma canción. Si
    /// solo una de las dos las tiene, el grupo baja a "posible" en vez de
    /// "probable": un vivo y su versión de estudio no son un duplicado.
    /// </summary>
    public static readonly IReadOnlySet<string> VersionQualifiers = new HashSet<string>(StringComparer.Ordinal)
    {
        "live", "envivo", "vivo", "remix", "mix", "acoustic", "acustico", "acustica", "unplugged",
        "demo", "instrumental", "karaoke", "radioedit", "edit", "version", "cover", "remaster",
        "remastered", "remasterizado", "remasterizada", "extended", "single", "mono", "stereo",
        "bonus", "outtake", "alternate", "alt", "reprise", "intro", "outro", "feat", "ft"
    };

    /// <summary>Sufijos que agrega el Explorador (o el Finder) al duplicar un archivo.</summary>
    [GeneratedRegex(@"(\s*(copia|copy)(\s*\d+)?|\s*\(\d+\)|[\s_-]+\d{1,2})$", RegexOptions.IgnoreCase)]
    private static partial Regex CopySuffix();

    [GeneratedRegex(@"^\s*(\d{1,2}[\s._-]+)?\d{1,3}\s*([.\-_)]\s*|\s+)")]
    private static partial Regex LeadingTrackNumber();

    [GeneratedRegex(@"[\(\[\{][^\)\]\}]*[\)\]\}]")]
    private static partial Regex Bracket();

    [GeneratedRegex(@"\s*[\(\[]?(19|20)\d{2}[\)\]]?\s*$")]
    private static partial Regex YearSuffix();

    /// <summary>Minúsculas, sin acentos, solo letras y números.</summary>
    public static string Alnum(string? value)
    {
        if (string.IsNullOrEmpty(value)) return "";

        var builder = new StringBuilder(value.Length);
        foreach (char c in Fold(value))
            if (char.IsLetterOrDigit(c)) builder.Append(c);
        return builder.ToString();
    }

    /// <summary>
    /// Minúsculas y sin marcas diacríticas — "Canción" y "cancion" tienen que
    /// llegar a lo mismo, que es todo el punto del detector.
    /// </summary>
    private static string Fold(string value)
    {
        string decomposed = value.Normalize(NormalizationForm.FormD);
        var builder = new StringBuilder(decomposed.Length);

        foreach (char c in decomposed)
            if (CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark)
                builder.Append(c);

        return builder.ToString().ToLowerInvariant();
    }

    /// <summary>Quita "01 ", "1. ", "01 - ", "1-01 " del frente de un título.</summary>
    public static string StripLeadingTrackNumber(string title)
    {
        string stripped = LeadingTrackNumber().Replace(title, "", 1);
        // Si el título ERA solo un número ("7", "99"), no lo vacíes.
        return stripped.Trim().Length == 0 ? title : stripped;
    }

    /// <param name="Core">El título comparable, sin nada más.</param>
    /// <param name="Qualifiers">
    /// Los calificadores de versión encontrados (dentro del paréntesis o sueltos
    /// al final), para saber si una es "otra versión" de la otra.
    /// </param>
    public readonly record struct NormalizedTitle(string Core, IReadOnlySet<string> Qualifiers);

    /// <summary>
    /// Título comparable: sin número de pista, sin nada entre paréntesis o
    /// corchetes, sin acentos ni puntuación.
    /// </summary>
    public static NormalizedTitle NormalizeTitle(string raw)
    {
        var text = new StringBuilder(StripLeadingTrackNumber(raw));
        var qualifiers = new HashSet<string>(StringComparer.Ordinal);

        // Al revés para que los índices de las coincidencias anteriores sigan
        // siendo válidos mientras se van quitando.
        foreach (Match match in Bracket().Matches(text.ToString()).Reverse())
        {
            string inside = match.Value[1..^1];
            foreach (string word in Tokens(inside))
                if (VersionQualifiers.Contains(word)) qualifiers.Add(word);

            text.Remove(match.Index, match.Length);
        }

        // "Amor - Live" con el calificador suelto al final, no entre paréntesis.
        List<string> words = [.. Tokens(text.ToString())];
        while (words.Count > 1 && VersionQualifiers.Contains(words[^1]))
        {
            qualifiers.Add(words[^1]);
            words.RemoveAt(words.Count - 1);
        }

        return new NormalizedTitle(string.Concat(words), qualifiers);
    }

    /// <summary>Las palabras de un texto, ya plegadas y sin puntuación.</summary>
    public static IReadOnlyList<string> Tokens(string text)
    {
        var tokens = new List<string>();
        var current = new StringBuilder();

        foreach (char c in Fold(text))
        {
            if (char.IsLetterOrDigit(c)) { current.Append(c); continue; }
            if (current.Length > 0) { tokens.Add(current.ToString()); current.Clear(); }
        }

        if (current.Length > 0) tokens.Add(current.ToString());
        return tokens;
    }

    /// <summary>
    /// Nombre de archivo comparable para fotos y videos: sin extensión, sin
    /// " copia"/"(1)"/"-1", sin el año al final.
    /// </summary>
    public static string NormalizeStem(string path)
    {
        string stem = Path.GetFileNameWithoutExtension(path);
        stem = CopySuffix().Replace(stem, "");
        stem = YearSuffix().Replace(stem, "");
        return Alnum(stem);
    }

    /// <summary>1.0 = idénticas, 0.0 = nada que ver (Levenshtein normalizada).</summary>
    public static double Similarity(string a, string b)
    {
        if (string.Equals(a, b, StringComparison.Ordinal)) return 1;
        if (a.Length == 0 || b.Length == 0) return 0;

        // La diferencia de largo ya acota la distancia por debajo: si solo por
        // eso quedan lejos, no vale la pena la programación dinámica completa.
        int longest = Math.Max(a.Length, b.Length);
        if ((double)Math.Abs(a.Length - b.Length) / longest > 0.5) return 0;

        return 1 - (double)Levenshtein(a, b) / longest;
    }

    public static int Levenshtein(string a, string b)
    {
        if (a.Length == 0) return b.Length;
        if (b.Length == 0) return a.Length;

        int[] previous = [.. Enumerable.Range(0, b.Length + 1)];
        int[] current = new int[b.Length + 1];

        for (int i = 1; i <= a.Length; i++)
        {
            current[0] = i;
            for (int j = 1; j <= b.Length; j++)
            {
                int cost = a[i - 1] == b[j - 1] ? 0 : 1;
                current[j] = Math.Min(Math.Min(previous[j] + 1, current[j - 1] + 1), previous[j - 1] + cost);
            }
            (previous, current) = (current, previous);
        }

        return previous[b.Length];
    }

    /// <summary>
    /// El tamaño como lo diría una persona. Es solo para la explicación que ve
    /// el usuario ("Mismo tamaño exacto de archivo (4.2 MB)"), nunca para
    /// comparar: eso se hace con los bytes.
    ///
    /// <para>Unidades de 1000, como el Finder de macOS y el Explorador de
    /// Windows, no de 1024.</para>
    /// </summary>
    public static string FormatBytes(long bytes)
    {
        if (bytes < 1000) return $"{bytes} bytes";

        string[] units = ["kB", "MB", "GB", "TB"];
        double value = bytes;
        int unit = -1;

        do { value /= 1000; unit++; }
        while (value >= 1000 && unit < units.Length - 1);

        // Un decimal a partir de MB; en kB un decimal no aporta nada.
        string text = unit == 0
            ? value.ToString("0", CultureInfo.InvariantCulture)
            : value.ToString("0.#", CultureInfo.InvariantCulture);
        return $"{text} {units[unit]}";
    }

    /// <summary>La duración como "3:24". "--" si no se conoce.</summary>
    public static string Clock(double? seconds)
    {
        if (seconds is null) return "--";
        int total = (int)Math.Round(seconds.Value);
        return $"{total / 60}:{total % 60:00}";
    }
}
