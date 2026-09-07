using System.Text.RegularExpressions;

namespace AuraStudio.Tools.ExtraerCadenasWindows;

/// <summary>
/// Extrae los literales de <c>AppStrings.cs</c>, miembro por miembro
/// (§1 de la auditoría de B0: 231 miembros). Por cada miembro:
///
/// <list type="number">
/// <item>Ternarios de plural (<c>n == 1 ? "singular" : "..."</c>): van a
/// <see cref="Plurals"/>, nunca a <see cref="Sites"/> — es la misma regla
/// que <c>tools/extraer-cadenas.py</c>: no se "resuelven" con una clave más,
/// necesitan el mecanismo real de plurales de B7c.</item>
/// <item>Brazos de <c>switch</c> (<c>Kind.Music =&gt; "Música"</c>): una
/// clave por brazo, con el nombre del caso como sufijo legible.</item>
/// <item>Lo que quede (ternarios de dos mensajes reales, concatenaciones,
/// literales sueltos en un cuerpo con más código): una clave por literal,
/// numerada si hay más de una en el mismo miembro.</item>
/// </list>
/// </summary>
public static class AppStringsExtractor
{
    public static readonly Regex PluralTernary = new(
        @"[><=!]?=?\s*1\s*\?\s*(?<a>\$?""(?:[^""\\]|\\.)*"")\s*:\s*(?<b>\$?""(?:[^""\\]|\\.)*"")",
        RegexOptions.Compiled);

    private static readonly Regex SwitchArm = new(
        @"(?<label>[\w.]+(?:\s+is\s*\{[^}]*\}\s*\w+)?)\s*=>\s*(?<lit>\$?""(?:[^""\\]|\\.)*"")",
        RegexOptions.Compiled);

    public static (List<Site> Sites, List<PluralSite> Plurals) Extract(
        string relativePath, string fileText, KeyRegistry keys)
    {
        var sites = new List<Site>();
        var plurals = new List<PluralSite>();

        foreach (Member member in MemberBodyFinder.FindAll(fileText))
        {
            var consumed = new List<(int Start, int End)>();
            var memberSites = new List<(int Start, string Label, RawLiteral Literal)>();

            foreach (Match plural in PluralTernary.Matches(member.BodyText))
            {
                string a = StringLiteralScanner.Unescape(Strip(plural.Groups["a"].Value));
                string b = StringLiteralScanner.Unescape(Strip(plural.Groups["b"].Value));
                int line = MemberBodyFinder.LineOf(fileText, member.BodyStartOffset + plural.Index);
                plurals.Add(new PluralSite(relativePath, line, a, b));

                consumed.Add((plural.Groups["a"].Index, plural.Groups["a"].Index + plural.Groups["a"].Length));
                consumed.Add((plural.Groups["b"].Index, plural.Groups["b"].Index + plural.Groups["b"].Length));
            }

            foreach (Match arm in SwitchArm.Matches(member.BodyText))
            {
                int litStart = arm.Groups["lit"].Index;
                int litEnd = litStart + arm.Groups["lit"].Length;
                if (Overlaps(consumed, litStart, litEnd)) continue;

                string rawLiteral = Strip(arm.Groups["lit"].Value);

                // `_ => ""` (LibrarySectionOnlyItsType, MediaGridViewModel):
                // el brazo por omisión que no muestra nada no es un hueco de
                // traducción, es "no hay texto acá". Sin este corte, la
                // clave llegaba al borrador con <value></value> -- vacía,
                // pero presente, así que ningún aviso de "clave ausente" la
                // atrapa nunca.
                if (StringLiteralScanner.Unescape(rawLiteral).Trim().Length == 0)
                {
                    consumed.Add((litStart, litEnd));
                    continue;
                }

                string label = arm.Groups["label"].Value.Trim();
                var literal = new RawLiteral(litStart, litEnd, rawLiteral, arm.Groups["lit"].Value.StartsWith('$'));
                memberSites.Add((litStart, label, literal));
                consumed.Add((litStart, litEnd));
            }

            // Los que sobran se funden ANTES de convertirse en sitio: "a" +
            // "b" (con saltos de línea entre medio, el estilo real de los
            // párrafos largos de AppStrings.cs) es UNA frase, no dos medias
            // frases con clave propia -- no se puede traducir un corte a
            // mitad de oración, y la Mac ya la tiene como una sola clave.
            List<RawLiteral> remaining = [.. StringLiteralScanner.Scan(member.BodyText)
                .Where(literal => !Overlaps(consumed, literal.Start, literal.End))
                .Where(literal => literal.RawText.Trim().Length > 0)];

            foreach (RawLiteral literal in LiteralCoalescer.Coalesce(member.BodyText, remaining))
            {
                memberSites.Add((literal.Start, "", literal));
                consumed.Add((literal.Start, literal.End));
            }

            memberSites.Sort((x, y) => x.Start.CompareTo(y.Start));

            for (int index = 0; index < memberSites.Count; index++)
            {
                (int start, string label, RawLiteral literal) = memberSites[index];

                string suffix = memberSites.Count == 1 ? ""
                    : label.Length > 0 ? "-" + KeyRegistry.Slugify(label, maxWords: 3, maxLen: 24)
                    : "-" + (index + 1);

                string baseKey = "app-strings." + KeyRegistry.MemberKebab(member.Name) + suffix;
                string key = keys.Unique(baseKey);

                string unescaped = StringLiteralScanner.Unescape(literal.RawText);
                (string converted, bool hasInterpolation) = literal.IsInterpolated
                    ? InterpolationHoles.Convert(unescaped)
                    : (unescaped, false);

                int line = MemberBodyFinder.LineOf(fileText, member.BodyStartOffset + start);
                sites.Add(new Site(key, relativePath, line, "AppStrings", unescaped, converted, hasInterpolation));
            }
        }

        return (sites, plurals);
    }

    private static bool Overlaps(List<(int Start, int End)> ranges, int start, int end) =>
        ranges.Any(r => start < r.End && end > r.Start);

    private static string Strip(string quoted)
    {
        string s = quoted.StartsWith('$') ? quoted[1..] : quoted;
        return s.Length >= 2 ? s[1..^1] : "";
    }
}
