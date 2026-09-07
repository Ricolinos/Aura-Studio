using System.Text.RegularExpressions;

namespace AuraStudio.Tools.ExtraerCadenasWindows;

/// <summary>
/// Encargo del coordinador (A7b): las categorías de video
/// (<c>MediaCategoryNames.DisplayNameSpanish</c>/<c>DisplayNameEnglish</c>,
/// "Películas"/"Series"/"Videos") son DATO del catálogo -- se guardan
/// literalmente en el JSON y <c>MediaCategoryNames.IsMoviesCategory</c>/
/// <c>IsSeriesCategory</c> las compara por igualdad contra esos dos
/// literales fijos (es/en), nunca contra un recurso localizado en vivo. Si
/// alguien las migrara a un recurso normal, un catálogo en otro idioma
/// (ja/de/ru/fr) dejaría de reconocerse -- por eso se marcan "dato, no
/// traducir" en vez de colarse como una clave más. No hay ningún caso así
/// hoy en el borrador (<c>AuraStudio.Core</c> no entra al escaneo general
/// de literales), pero si algún día se amplía el escaneo a Core, esto evita
/// que se migren por error.
/// </summary>
public static class CatalogDataExtractor
{
    // El brazo `_ => "Videos"` (el default de las dos) no trae
    // `MediaCategory.` delante -- se captura aparte, pero SOLO en un
    // archivo ya confirmado como el de `MediaCategoryNames` (el `if
    // (!fileText.Contains(...))` de abajo), nunca como patrón suelto en
    // cualquier archivo: un `_ => "algo"` es un brazo de switch de lo más
    // común, y fuera de este archivo específico no tiene por qué ser dato
    // de catálogo.
    private static readonly Regex CategoryDisplayNameLiteral = new(
        @"(?:MediaCategory\.\w+|_)\s*=>\s*(?<lit>""[^""]*"")",
        RegexOptions.Compiled);

    public static List<Site> Extract(string relativePath, string fileText, KeyRegistry keys)
    {
        var sites = new List<Site>();
        if (!fileText.Contains("MediaCategoryNames")) return sites;

        foreach (Match match in CategoryDisplayNameLiteral.Matches(fileText))
        {
            string raw = StringLiteralScanner.Unescape(match.Groups["lit"].Value[1..^1]);
            int line = MemberBodyFinder.LineOf(fileText, match.Index);
            string key = keys.Unique(KeyRegistry.FileStemKebab(relativePath) + ".dato-categoria-" + KeyRegistry.Slugify(raw));

            sites.Add(new Site(key, relativePath, line, "Dato", raw, raw, false,
                Note: "dato del catálogo, no traducir -- MediaCategoryNames.IsMoviesCategory/IsSeriesCategory " +
                      "lo compara por igualdad contra estos literales fijos (es/en); un recurso localizado en vivo " +
                      "dejaría de reconocer un catálogo en otro idioma"));
        }

        return sites;
    }
}
