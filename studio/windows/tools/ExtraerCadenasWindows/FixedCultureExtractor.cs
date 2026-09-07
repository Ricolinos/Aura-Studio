using System.Text.RegularExpressions;

namespace AuraStudio.Tools.ExtraerCadenasWindows;

/// <summary>
/// El caso que el encargo pide marcar aparte: una cultura fija
/// (<c>CultureInfo.GetCultureInfo("es-MX")</c>) o un patrón de fecha con
/// palabras de un idioma escritas a mano dentro del formato
/// (<c>"d 'de' MMMM 'de' yyyy"</c> — <c>MediaTableRow.cs:53</c>,
/// documentado en <c>docs/auditoria-idiomas.md</c> §4). No busca la línea a
/// ciegas por número: la encuentra por patrón, para seguir encontrándola si
/// el archivo se mueve o cambia de línea.
/// </summary>
public static class FixedCultureExtractor
{
    private static readonly Regex FixedCulture = new(
        @"CultureInfo\.GetCultureInfo\(\s*""(?<culture>[^""]+)""\s*\)",
        RegexOptions.Compiled);

    private static readonly Regex ToStringCall = new(@"\.ToString\(\s*", RegexOptions.Compiled);

    public static List<Site> Extract(string relativePath, string fileText, KeyRegistry keys)
    {
        var sites = new List<Site>();

        foreach (Match match in FixedCulture.Matches(fileText))
        {
            int line = MemberBodyFinder.LineOf(fileText, match.Index);
            string culture = match.Groups["culture"].Value;
            string key = keys.Unique(KeyRegistry.FileStemKebab(relativePath) + ".cultura-fija");

            sites.Add(new Site(key, relativePath, line, "CulturaFija", culture, culture, false,
                Note: $"cultura fija ({culture}) -- tiene que volverse la cultura activa (CultureInfo.CurrentCulture o el selector de idioma), no un valor fijo"));
        }

        // El primer argumento de .ToString(...), tomado con el mismo
        // escaneo consciente de cadenas que usa todo lo demás -- NUNCA con
        // una sola expresión regular con [^"]* suelto: eso puede "no
        // cerrar" cerca y arrastrar cientos de líneas de código real hasta
        // la próxima comilla-apóstrofe-comilla que encuentre, muy lejos de
        // ahí (pasó de verdad al escribir esto: se descubrió mirando la
        // salida, no adivinando).
        foreach (Match call in ToStringCall.Matches(fileText))
        {
            int i = call.Index + call.Length;
            if (i >= fileText.Length) continue;

            RawLiteral? literal = StringLiteralScanner.TrySkip(fileText, ref i);
            if (literal is null) continue;

            string raw = StringLiteralScanner.Unescape(literal.RawText);
            if (!raw.Contains('\'')) continue; // sin comillas simples adentro, no hay palabra fija que marcar

            // Un timestamp ISO-8601 (yyyy-MM-dd'T'...'Z') es una marca de
            // tiempo técnica -- JSON, nombres de archivo, bitácora -- nunca
            // algo que el usuario vea (confirmado en la auditoría de B0,
            // §4: "los ToString("yyyy...") del resto del código son
            // timestamps internos"). Las comillas simples ahí delimitan
            // literales de formato ISO, no palabras de un idioma.
            if (Regex.IsMatch(raw, @"^y+-M+-d+")) continue;

            int line = MemberBodyFinder.LineOf(fileText, literal.Start);
            string key = keys.Unique(KeyRegistry.FileStemKebab(relativePath) + ".formato-fecha-fijo");

            sites.Add(new Site(key, relativePath, line, "CulturaFija", raw, raw, false,
                Note: "formato con gramática fija -- las palabras entre comillas simples son literales del patrón, no las traduce .NET solo; necesita reescribirse (formato estándar \"D\"/\"d\" o uno por cultura), no solo confirmarse"));
        }

        return sites;
    }
}
