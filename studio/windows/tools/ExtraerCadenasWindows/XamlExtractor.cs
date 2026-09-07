using System.Text.RegularExpressions;

namespace AuraStudio.Tools.ExtraerCadenasWindows;

/// <summary>
/// Literales de interfaz en atributos XAML (§1 de la auditoría de B0: 146
/// sitios, 13 archivos): <c>Text=</c>, <c>Content=</c>, <c>Header=</c>,
/// <c>PlaceholderText=</c>, <c>Title=</c>, <c>Description=</c> con un texto
/// literal entre comillas — nunca <c>{x:Bind ...}</c> ni
/// <c>{StaticResource ...}</c>, que se descartan porque no son texto fijo.
/// </summary>
public static class XamlExtractor
{
    private static readonly Regex Attribute = new(
        @"\b(?<attr>Text|Content|Header|PlaceholderText|Title|Description)=""(?<value>[^""]*)""",
        RegexOptions.Compiled);

    public static List<Site> Extract(string relativePath, string fileText, KeyRegistry keys)
    {
        var sites = new List<Site>();

        foreach (Match match in Attribute.Matches(fileText))
        {
            string value = match.Groups["value"].Value;

            // Un enlace ({x:Bind ...}) o un recurso ({StaticResource ...})
            // no es texto fijo: nada que traducir acá.
            if (value.TrimStart().StartsWith('{')) continue;
            if (value.Trim().Length == 0) continue;

            int line = MemberBodyFinder.LineOf(fileText, match.Index);
            string baseKey = KeyRegistry.FileStemKebab(relativePath) + "." + KeyRegistry.Slugify(value);
            string key = keys.Unique(baseKey);

            sites.Add(new Site(key, relativePath, line, "XAML", value, value, false));
        }

        return sites;
    }
}
