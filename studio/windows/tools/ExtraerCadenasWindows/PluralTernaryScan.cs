namespace AuraStudio.Tools.ExtraerCadenasWindows;

/// <summary>
/// Ternarios de plural (<c>n == 1 ? "singular" : "plural"</c>) FUERA de
/// <c>AppStrings.cs</c> — la auditoría de B0 ya decía que "una buena parte"
/// vive en <c>AppStrings</c>, no toda: hay más sueltos en los ViewModels
/// (<c>LibraryViewModel.SummaryOf</c>, <c>ArtistsViewModel</c>,
/// <c>MediaGridViewModel</c>...). <see cref="AppStringsExtractor"/> ya hace
/// esto mismo para los cuerpos de miembro de <c>AppStrings.cs</c>; acá es la
/// misma expresión regular, aplicada al archivo entero sin necesidad de
/// partirlo en miembros primero.
/// </summary>
public static class PluralTernaryScan
{
    public static List<PluralSite> Extract(string relativePath, string fileText)
    {
        var plurals = new List<PluralSite>();

        foreach (System.Text.RegularExpressions.Match match in AppStringsExtractor.PluralTernary.Matches(fileText))
        {
            string a = StringLiteralScanner.Unescape(Strip(match.Groups["a"].Value));
            string b = StringLiteralScanner.Unescape(Strip(match.Groups["b"].Value));
            int line = MemberBodyFinder.LineOf(fileText, match.Index);
            plurals.Add(new PluralSite(relativePath, line, a, b));
        }

        return plurals;
    }

    private static string Strip(string quoted)
    {
        string s = quoted.StartsWith('$') ? quoted[1..] : quoted;
        return s.Length >= 2 ? s[1..^1] : "";
    }
}
