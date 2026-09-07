using System.Text.RegularExpressions;

namespace AuraStudio.Tools.ExtraerCadenasWindows;

/// <summary>
/// Los tres focos de literal en C# fuera de <c>AppStrings</c> que documentó
/// la auditoría de B0 (§1: 103 sitios): <c>MenuEntry(id, "texto", …)</c> en
/// <c>ContextMenu.cs</c> (incluidos sus <c>const string</c> de apoyo, que es
/// donde vive el texto cuando el sitio de la llamada solo pasa un
/// identificador), <c>StatusMessage = "…"</c>, y los literales de
/// <c>ContentDialog</c> (<c>Title</c>/<c>PrimaryButtonText</c>/
/// <c>CloseButtonText</c>/<c>SecondaryButtonText</c>) en código-behind.
/// </summary>
public static class CSharpLiteralExtractor
{
    private static readonly Regex MenuEntryCall = new(
        @"new\s+MenuEntry\(\s*""[^""]*""\s*,\s*(?<arg>.+?)(?=,\s*(?:Role|Enabled)\s*:|,\s*\)|\))",
        RegexOptions.Compiled | RegexOptions.Singleline);

    private static readonly Regex ConstOrLocalString = new(
        @"(?:public|private)?\s*const\s+string\s+(?<name>\w+)\s*=\s*(?<lit>""(?:[^""\\]|\\.)*"")\s*;",
        RegexOptions.Compiled);

    private static readonly Regex StatusMessageAssign = new(
        @"StatusMessage\s*=\s*(?<lit>\$?""(?:[^""\\]|\\.)*"")\s*;",
        RegexOptions.Compiled);

    private static readonly Regex ContentDialogProperty = new(
        @"\b(?:Title|PrimaryButtonText|CloseButtonText|SecondaryButtonText)\s*=\s*(?<lit>\$?""(?:[^""\\]|\\.)*"")\s*,?",
        RegexOptions.Compiled);

    /// <summary>
    /// Ayudantes propios de C# cuyo (único o primer) argumento es texto de
    /// cara al usuario (A7a: encargo del coordinador) -- NUNCA un patrón
    /// genérico sobre toda llamada con un <c>string</c> como primer
    /// parámetro (eso atraparía <c>Path.Combine("...")</c>,
    /// <c>Directory.CreateDirectory("...")</c>, claves de diccionario,
    /// mensajes de log...), sino una lista explícita y curada, verificada a
    /// mano leyendo cada sitio real antes de agregarlo. Hoy:
    /// <c>DeviceSafetyResult.Safe(string message)</c> y
    /// <c>DeviceSafetyResult.Unsafe(string message)</c>
    /// (<c>Services/DeviceSafetyValidator.cs</c>) -- mensajes de seguridad
    /// del dispositivo que no pasan por <c>AppStrings</c>,
    /// <c>StatusMessage</c> ni <c>ContentDialog</c>.
    /// </summary>
    private static readonly Regex HelperCallWithUserTextArgument = new(
        @"\b(?:DeviceSafetyResult\.Safe|DeviceSafetyResult\.Unsafe)\(\s*(?<arg>.+?)\)\s*;",
        RegexOptions.Compiled | RegexOptions.Singleline);

    /// <summary>
    /// <c>ContextMenu.cs</c>: los <c>const string</c>, las llamadas a
    /// <c>MenuEntry</c>, y —de red, por si algo se cuela por otro
    /// camino, como <c>ForVideoCollection(scope, categories, "Eliminar
    /// película", "Eliminar películas")</c>, un texto que viaja como
    /// PARÁMETRO y nunca aparece dentro de un <c>new MenuEntry(...)</c>
    /// ni de un <c>const</c>— cualquier literal del archivo que ninguno
    /// de los dos pasos anteriores haya consumido todavía.
    /// </summary>
    public static List<Site> ExtractMenuEntries(string relativePath, string fileText, KeyRegistry keys)
    {
        var sites = new List<Site>();
        var consumed = new List<(int Start, int End)>();

        foreach (Match match in ConstOrLocalString.Matches(fileText))
        {
            string name = match.Groups["name"].Value;
            int litStart = match.Groups["lit"].Index;
            consumed.Add((litStart, litStart + match.Groups["lit"].Length));

            AddLiteralSite(sites, keys, relativePath, fileText, match.Groups["lit"].Value,
                match.Index, "MenuEntry", KeyRegistry.MemberKebab(name));
        }

        foreach (Match call in MenuEntryCall.Matches(fileText))
        {
            // El primer argumento -- el id ("delete", "album.covers") -- NO
            // es texto de cara al usuario: se marca consumido para que la
            // pasada de red de abajo no lo levante, pero nunca se convierte
            // en sitio.
            Match idMatch = Regex.Match(fileText[call.Index..call.Groups["arg"].Index], @"""[^""]*""");
            if (idMatch.Success)
            {
                int idStart = call.Index + idMatch.Index;
                consumed.Add((idStart, idStart + idMatch.Length));
            }

            string arg = call.Groups["arg"].Value.Trim();
            if (Regex.IsMatch(arg, @"^[\w.]+$") && !arg.StartsWith('"')) continue;

            foreach (RawLiteral literal in StringLiteralScanner.Scan(arg))
            {
                if (literal.RawText.Trim().Length == 0) continue;

                int start = call.Groups["arg"].Index + literal.Start;
                int end = call.Groups["arg"].Index + literal.End;
                consumed.Add((start, end));

                AddLiteralSite(sites, keys, relativePath, fileText, WrapQuotes(literal),
                    start, "MenuEntry", null);
            }
        }

        // Red de por si algo real se cuela por otro camino (un texto que
        // viaja como parámetro de un método propio, nunca dentro de un
        // `new MenuEntry(...)` ni de un `const`). Se excluye lo que tiene
        // toda la forma de un identificador interno y ninguna de un texto en
        // español (sin espacio, sin acento, solo letras/dígitos/`.`/`:`/`_`)
        // -- son los "id" de menú y las claves internas
        // (`"AlbumCount"`, `"filter.all"`), no algo que traducir.
        foreach (RawLiteral literal in StringLiteralScanner.Scan(fileText))
        {
            if (literal.RawText.Trim().Length == 0) continue;
            if (consumed.Any(r => literal.Start < r.End && literal.End > r.Start)) continue;
            if (Regex.IsMatch(literal.RawText, @"^[A-Za-z][A-Za-z0-9_.:]*$")) continue;

            AddLiteralSite(sites, keys, relativePath, fileText, WrapQuotes(literal),
                literal.Start, "MenuEntry", null);
        }

        return sites;
    }

    public static List<Site> ExtractStatusMessages(string relativePath, string fileText, KeyRegistry keys)
    {
        var sites = new List<Site>();

        foreach (Match match in StatusMessageAssign.Matches(fileText))
        {
            string lit = match.Groups["lit"].Value;
            if (lit is "\"\"" or "$\"\"") continue; // limpiar el estado no es un mensaje que traducir

            AddLiteralSite(sites, keys, relativePath, fileText, lit, match.Index, "StatusMessage", null);
        }

        return sites;
    }

    public static List<Site> ExtractContentDialogText(string relativePath, string fileText, KeyRegistry keys)
    {
        var sites = new List<Site>();

        foreach (Match match in ContentDialogProperty.Matches(fileText))
        {
            AddLiteralSite(sites, keys, relativePath, fileText, match.Groups["lit"].Value,
                match.Index, "ContentDialog", null);
        }

        return sites;
    }

    /// <summary>
    /// Un argumento puede ser un solo literal, o un ternario de dos (como
    /// <c>DeviceSafetyResult.Unsafe(count == 0 ? "..." : "...")</c>): se
    /// escanea con <see cref="StringLiteralScanner"/>, igual que la red de
    /// <see cref="ExtractMenuEntries"/>, para levantar cada literal por
    /// separado en vez de asumir que todo el argumento es uno solo.
    /// </summary>
    public static List<Site> ExtractHelperFirstArgument(string relativePath, string fileText, KeyRegistry keys)
    {
        var sites = new List<Site>();

        foreach (Match call in HelperCallWithUserTextArgument.Matches(fileText))
        {
            string arg = call.Groups["arg"].Value;
            int argOffset = call.Groups["arg"].Index;

            foreach (RawLiteral literal in StringLiteralScanner.Scan(arg))
            {
                if (literal.RawText.Trim().Length == 0) continue;

                int start = argOffset + literal.Start;
                AddLiteralSite(sites, keys, relativePath, fileText, WrapQuotes(literal), start, "HelperArgument", null);
            }
        }

        return sites;
    }

    private static void AddLiteralSite(
        List<Site> sites, KeyRegistry keys, string relativePath, string fileText,
        string quotedLiteral, int offset, string kind, string? labelHint)
    {
        bool interpolated = quotedLiteral.StartsWith('$');
        string raw = Strip(quotedLiteral);
        string unescaped = StringLiteralScanner.Unescape(raw);

        // Un literal vacío (o solo espacios) no es texto de interfaz -- es un
        // brazo de switch tipo `_ => ""` (LibrarySectionOnlyItsType,
        // MediaGridViewModel) o un `StatusMessage = ""` que limpia el
        // estado. Sin este corte, la clave llega al borrador con
        // <value></value>: un hueco en pantalla que nunca dispara el aviso
        // de "clave ausente" porque la clave SÍ está, solo que vacía.
        if (unescaped.Trim().Length == 0) return;

        (string converted, bool hasInterpolation) = interpolated
            ? InterpolationHoles.Convert(unescaped)
            : (unescaped, false);

        int line = MemberBodyFinder.LineOf(fileText, offset);
        string slug = labelHint ?? KeyRegistry.Slugify(unescaped);
        string baseKey = KeyRegistry.FileStemKebab(relativePath) + "." + slug;
        string key = keys.Unique(baseKey);

        sites.Add(new Site(key, relativePath, line, kind, unescaped, converted, hasInterpolation));
    }

    private static string WrapQuotes(RawLiteral literal) =>
        (literal.IsInterpolated ? "$\"" : "\"") + literal.RawText + "\"";

    private static string Strip(string quoted)
    {
        string s = quoted.StartsWith('$') ? quoted[1..] : quoted;
        return s.Length >= 2 ? s[1..^1] : "";
    }
}
