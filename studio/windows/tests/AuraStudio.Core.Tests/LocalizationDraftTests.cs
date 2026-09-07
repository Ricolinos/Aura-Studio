using System.Text.RegularExpressions;
using System.Xml.Linq;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// Valida el borrador de B7a (ST-247, ensayo en seco):
/// <c>docs/extraccion-cadenas/</c> — generado por
/// <c>tools/ExtraerCadenasWindows</c>, nunca por esta prueba. Mismo criterio
/// que <c>LocalizationDraftTests.swift</c> (Mac, ST-225/226 addendum): estas
/// tres corren de verdad, hoy, sobre los archivos ya generados — no dependen
/// de ninguna API nueva.
/// </summary>
public class LocalizationDraftTests
{
    private static string RepoRoot()
    {
        DirectoryInfo? dir = new(AppContext.BaseDirectory);
        while (dir is not null)
        {
            if (File.Exists(Path.Combine(dir.FullName, "studio", "windows", "AuraStudio.Windows.slnx")))
                return dir.FullName;

            dir = dir.Parent;
        }

        throw new InvalidOperationException("No se encontró la raíz del repo desde el directorio de pruebas.");
    }

    private static string OutDir() => Path.Combine(RepoRoot(), "studio", "windows", "docs", "extraccion-cadenas");

    /// <summary>
    /// El borrador se commitea (a diferencia de la Mac, que lo gitignora):
    /// es un entregable de B7a, no un archivo de paso. Si no está, algo real
    /// se rompió -- se falla, no se salta.
    /// </summary>
    private static string RequireFile(string relative)
    {
        string path = Path.Combine(OutDir(), relative);
        Assert.True(File.Exists(path), $"{relative} no se encontró -- ¿corriste tools/ExtraerCadenasWindows? (ST-247)");
        return path;
    }

    // MARK: - Claves únicas

    /// <summary>
    /// Un <c>.resw</c> con un <c>name</c> de <c>&lt;data&gt;</c> repetido no
    /// es inválido para el parser XML (a diferencia de una clave de objeto
    /// JSON, que <c>JSONSerialization</c> colapsa en silencio) — pero SÍ
    /// sería un error real del extractor: dos textos distintos peleándose la
    /// misma clave, y uno de los dos se perdería en la práctica al leerlo con
    /// <c>ResourceManager</c>. Se verifica sobre las claves ya parseadas.
    /// </summary>
    [Fact]
    public void LasClavesDelReswSonUnicas()
    {
        XDocument doc = XDocument.Load(RequireFile(Path.Combine("Strings", "es", "Resources.resw")));
        List<string> keys = [.. doc.Root!.Elements("data").Select(e => e.Attribute("name")!.Value)];

        Assert.Equal(keys.Count, keys.Distinct(StringComparer.Ordinal).Count());
        Assert.True(keys.Count > 400, $"se esperaban más de 400 claves (línea base de B0, ~480), hay {keys.Count}");
    }

    [Fact]
    public void NingunaClaveEstaVacia()
    {
        XDocument doc = XDocument.Load(RequireFile(Path.Combine("Strings", "es", "Resources.resw")));

        foreach (XElement data in doc.Root!.Elements("data"))
            Assert.False(string.IsNullOrWhiteSpace(data.Attribute("name")?.Value), "una clave vacía en el .resw");
    }

    /// <summary>
    /// ST-247 (addendum): un brazo <c>_ =&gt; ""</c> de un <c>switch</c>
    /// (<c>LibrarySectionOnlyItsType</c>, <c>MediaGridViewModel</c>) no es un
    /// hueco de traducción -- es "acá no hay texto". Antes de esta corrección
    /// llegaba al borrador con <c>&lt;value&gt;&lt;/value&gt;</c>: la clave
    /// existe, así que ninguna prueba de "clave ausente" lo atrapaba nunca —
    /// hacía falta mirar el VALOR, no la clave.
    /// </summary>
    [Fact]
    public void NingunValorEstaVacio()
    {
        XDocument doc = XDocument.Load(RequireFile(Path.Combine("Strings", "es", "Resources.resw")));

        foreach (XElement data in doc.Root!.Elements("data"))
        {
            string? value = data.Element("value")?.Value;
            Assert.False(string.IsNullOrWhiteSpace(value),
                $"la clave {data.Attribute("name")?.Value} tiene un valor vacío en español");
        }
    }

    /// <summary>
    /// ST-247 (addendum): <c>NavPhotosAI</c> salía <c>nav-photos-a-i</c> —el
    /// kebab-case partía la sigla letra por letra— en vez de
    /// <c>nav-photos-ai</c>. Cualquier clave con dos o más letras SUELTAS
    /// seguidas, cada una separada por guion, es la misma forma del defecto
    /// resurgiendo (`KeyNaming.PascalToKebab`, corregido en este addendum).
    /// </summary>
    [Fact]
    public void NingunaClaveTieneLetrasSueltasSeparadasPorGuion()
    {
        XDocument doc = XDocument.Load(RequireFile(Path.Combine("Strings", "es", "Resources.resw")));
        var brokenAcronym = new Regex(@"(^|-)[a-z](-[a-z]){1,}(-|$)");

        List<string> rotas = [.. doc.Root!.Elements("data")
            .Select(e => e.Attribute("name")!.Value)
            .Where(key => brokenAcronym.IsMatch(key))];

        Assert.True(rotas.Count == 0,
            "claves con una sigla partida letra por letra: " + string.Join(", ", rotas.Take(10)));
    }

    // MARK: - Frases concatenadas ("a" + "b"), no partidas en dos claves

    /// <summary>
    /// Los únicos <c>app-strings.*</c> con sufijo <c>-N</c> numérico
    /// legítimos son los ternarios de DOS mensajes de verdad distintos
    /// (<c>condición ? "mensaje A" : "mensaje B"</c>) — nunca un párrafo
    /// escrito como <c>"a" + "b"</c> que el extractor no supo unir. Lista
    /// explícita, no un patrón: agregar una clave nueva acá tiene que ser
    /// una decisión consciente ("sí, es un ternario de verdad"), no un
    /// efecto colateral silencioso de una corrida futura.
    /// </summary>
    private static readonly HashSet<string> KnownAppStringsTernaryPairs = new(StringComparer.Ordinal)
    {
        "app-strings.bootloader-update-flashing-1", "app-strings.bootloader-update-flashing-2",
        "app-strings.installer-dfu-found-1", "app-strings.installer-dfu-found-2",
        "app-strings.library-root-missing-1", "app-strings.library-root-missing-2",
        "app-strings.library-season-1", "app-strings.library-season-2",
        "app-strings.library-status-6", "app-strings.library-status-7",
    };

    [Fact]
    public void NingunaClaveAppStringsTerminaEnGuionNumericoSalvoLosTernariosConocidos()
    {
        XDocument doc = XDocument.Load(RequireFile(Path.Combine("Strings", "es", "Resources.resw")));
        var numericSuffix = new Regex(@"^app-strings\..*-\d+$");

        List<string> sospechosas = [.. doc.Root!.Elements("data")
            .Select(e => e.Attribute("name")!.Value)
            .Where(key => numericSuffix.IsMatch(key) && !KnownAppStringsTernaryPairs.Contains(key))];

        Assert.True(sospechosas.Count == 0,
            "claves de AppStrings con sufijo -N fuera de la lista de ternarios conocidos " +
            "(¿un párrafo concatenado que no se unió?): " + string.Join(", ", sospechosas));
    }

    [Fact]
    public void NingunValorTerminaEnEspacio()
    {
        XDocument doc = XDocument.Load(RequireFile(Path.Combine("Strings", "es", "Resources.resw")));

        List<string> rotos = [.. doc.Root!.Elements("data")
            .Where(e => Regex.IsMatch(e.Element("value")?.Value ?? "", @"\s$"))
            .Select(e => e.Attribute("name")!.Value)];

        Assert.True(rotos.Count == 0,
            "valores que terminan en espacio -- mitad de una frase cortada: " + string.Join(", ", rotos.Take(10)));
    }

    /// <summary>
    /// Un valor que empieza en minúscula suele ser la segunda mitad de una
    /// frase cortada a mitad ("...y los " + "sincroniza directo..." daba un
    /// segundo fragmento que empezaba en "sincroniza"). Las excepciones son
    /// reales y conocidas -- "iPod" (la propia Apple lo escribe así), URLs, y
    /// un par de nombres técnicos (ffmpeg, nombres de archivo en el aviso de
    /// licencias) -- así que se excluyen por clave, no por adivinar un patrón
    /// que las distinga del síntoma real.
    /// </summary>
    private static readonly HashSet<string> KnownLowercaseStartExceptions = new(StringComparer.Ordinal)
    {
        "app-strings.installer-dfu-found-1", "app-strings.installer-dfu-found-2", // "iPod detectado..."
        "app-strings.installer-dfu-guide-url", "app-strings.licenses-tag-lib-source", // URLs
        "app-strings.licenses-intro", // "mks5lboot, bootloader-ipod6g.ipod y..."
        "settings-page.ffmpeg", // "ffmpeg"
    };

    [Fact]
    public void NingunValorEmpiezaEnMinusculaSalvoExcepcionesConocidas()
    {
        XDocument doc = XDocument.Load(RequireFile(Path.Combine("Strings", "es", "Resources.resw")));
        var lowercaseStart = new Regex(@"^\p{Ll}");

        List<string> rotos = [.. doc.Root!.Elements("data")
            .Where(e => lowercaseStart.IsMatch(e.Element("value")?.Value ?? ""))
            .Select(e => e.Attribute("name")!.Value)
            .Where(key => !KnownLowercaseStartExceptions.Contains(key))];

        Assert.True(rotos.Count == 0,
            "valores que empiezan en minúscula fuera de las excepciones conocidas " +
            "(¿la segunda mitad de una frase cortada?): " + string.Join(", ", rotos.Take(10)));
    }

    // MARK: - Especificadores consistentes entre es/en

    /// <summary>
    /// Compara los especificadores <c>{0}</c>/<c>{1}</c>... de cada clave
    /// entre los dos <c>.resw</c>. Hoy "en" queda vacío a propósito (borrador,
    /// nunca traducido a mano) — se salta esa clave, no se falla por eso; es
    /// la misma prueba que sí va a fallar el día que B7b llene "en" y alguna
    /// traducción pierda un especificador.
    /// </summary>
    [Fact]
    public void LosEspecificadoresSonConsistentesEntreEsYEn()
    {
        Dictionary<string, string> es = ReadResw(RequireFile(Path.Combine("Strings", "es", "Resources.resw")));
        Dictionary<string, string> en = ReadResw(RequireFile(Path.Combine("Strings", "en", "Resources.resw")));

        Assert.Equal(es.Count, en.Count);

        foreach ((string key, string spanishValue) in es)
        {
            Assert.True(en.ContainsKey(key), $"la clave {key} está en es.resw y no en en.resw");
            string englishValue = en[key];

            if (string.IsNullOrEmpty(englishValue)) continue; // pendiente de traducir, nada que comparar todavía

            Assert.Equal(Specifiers(spanishValue), Specifiers(englishValue));
        }
    }

    private static HashSet<string> Specifiers(string text) =>
        [.. Regex.Matches(text, @"\{\d+\}").Select(m => m.Value)];

    // MARK: - El CSV y el .resw no se desalinean

    /// <summary>
    /// Toda fila TRADUCIBLE del CSV tiene que tener su clave en el
    /// <c>.resw</c> en español — son el mismo borrador, contado dos veces.
    /// Las filas de tipo <c>CulturaFija</c> quedan afuera a propósito: no son
    /// texto para traducir, son un defecto de código para reescribir (una
    /// cultura fija, un patrón de fecha con gramática incrustada), así que
    /// nunca tuvieron por qué entrar al <c>.resw</c>.
    /// </summary>
    [Fact]
    public void TodaFilaTraducibleDelCsvTieneSuClaveEnElResw()
    {
        Dictionary<string, string> resw = ReadResw(RequireFile(Path.Combine("Strings", "es", "Resources.resw")));
        List<string> csvKeys = ReadCsvKeys(RequireFile("revision.csv"), excludeKind: "CulturaFija");

        Assert.True(csvKeys.Count > 0);

        List<string> missing = [.. csvKeys.Where(key => !resw.ContainsKey(key)).Distinct(StringComparer.Ordinal)];
        Assert.True(missing.Count == 0, "claves del CSV ausentes en el .resw: " + string.Join(", ", missing.Take(10)));
    }

    /// <summary>
    /// ST-247 (addendum): cotejo clave por clave contra el borrador de la
    /// Mac. Toda fila de <c>claves-compartidas.csv</c> marcada
    /// <c>"igual"</c> —la clave ya coincide entre las dos plataformas— tiene
    /// que existir de verdad en el <c>.resw</c> de Windows; si no, la fila
    /// miente sobre el estado.
    ///
    /// <para>Decisión del coordinador (addendum sobre huecos/formato): el CSV
    /// es la autoridad del nombre compartido, pero la herramienta de Windows
    /// SIGUE emitiendo sus propias claves (<c>app-strings.storage-section-title</c>,
    /// no <c>storage-section-title</c>). Por eso "existe en el .resw" admite
    /// DOS caminos: (1) la clave del CSV coincide tal cual con una clave del
    /// <c>.resw</c>, o (2) la columna "sitio Windows" trae, entre paréntesis
    /// al final de la cita, la clave de Windows de la que viene —formato
    /// oficial "archivo:línea (clave.de.windows)", el mismo que escribe
    /// <c>ClavesCompartidasCsv.UpdateSitioWindows</c> (tools/ExtraerCadenasWindows)—
    /// y esa clave
    /// existe en el <c>.resw</c> con EL MISMO TEXTO que la columna "texto es"
    /// del CSV (si el texto no coincide, la fila quedó desalineada de verdad,
    /// no es solo un nombre distinto).</para>
    ///
    /// <para><b>Hallazgo real, no un ajuste de la prueba:</b> <c>orphans-confirm-message</c>
    /// falla la comparación exacta -- <c>AppStrings.OrphansConfirmMessage</c>
    /// (AppStrings.cs:324-326) antepone <c>{OrphansFound(scan)}</c> (el conteo
    /// dinámico de huérfanos) al texto compartido, así que el valor real del
    /// <c>.resw</c> es <c>"{0} " + texto de la Mac</c>, nunca el texto solo.
    /// "sitio Windows" y "texto es" no son de Windows (la Mac los edita), así
    /// que esto NO se corrige acá con una reescritura silenciosa: se deja
    /// como excepción explícita, documentada, y se avisa en el addendum para
    /// que la Mac decida si el estado real es "clave distinta".</para>
    /// </summary>
    private static readonly HashSet<string> KnownIgualSuffixExceptions = new(StringComparer.Ordinal)
    {
        "orphans-confirm-message",
    };

    [Fact]
    public void TodaClaveCompartidaMarcadaIgualExisteEnElReswDeWindows()
    {
        Dictionary<string, string> resw = ReadResw(RequireFile(Path.Combine("Strings", "es", "Resources.resw")));
        string sharedPath = RequireFile("claves-compartidas.csv");
        var windowsKeyInParens = new Regex(@"\((?<key>[a-z0-9][\w.-]*)(?:,[^)]*)?\)");

        List<(string CsvKey, string TextoEs, string SitioWindows)> igualRows = [.. File.ReadAllLines(sharedPath)
            .Skip(1)
            .Where(line => line.Length > 0)
            .Select(ParseCsvLine)
            .Where(fields => fields[^1] == "igual")
            .Select(fields => (fields[0], fields[1], fields[3]))];

        List<string> sinCorrespondencia = [];
        foreach ((string csvKey, string textoEs, string sitioWindows) in igualRows)
        {
            if (resw.ContainsKey(csvKey)) continue; // camino 1: la clave del CSV coincide tal cual

            bool esSufijoConocido = KnownIgualSuffixExceptions.Contains(csvKey);

            // camino 2: alguna clave entre paréntesis de "sitio Windows" existe
            // en el .resw con el mismo texto que "texto es" -- o, para una
            // excepción conocida y documentada arriba, con "texto es" como
            // cola del valor real (un prefijo interpolado que Windows antepone).
            bool matched = windowsKeyInParens.Matches(sitioWindows)
                .Select(m => m.Groups["key"].Value)
                .Any(windowsKey => resw.TryGetValue(windowsKey, out string? value) &&
                    (value == textoEs || (esSufijoConocido && value.EndsWith(textoEs, StringComparison.Ordinal))));

            if (!matched) sinCorrespondencia.Add(csvKey);
        }

        Assert.True(sinCorrespondencia.Count == 0,
            "claves-compartidas.csv marca 'igual' una clave sin correspondencia en el .resw de Windows " +
            "(ni por su propia clave, ni por el paréntesis \"(clave.de.windows)\" de 'sitio Windows' con el mismo texto): " +
            string.Join(", ", sinCorrespondencia.Take(10)));
    }

    // MARK: - Huecos de interpolación: sin duplicados para la misma expresión

    /// <summary>
    /// Coordinador (addendum sobre huecos): la conversión a <c>{0}</c>/<c>{1}</c>...
    /// tiene que REUSAR el índice cuando la misma expresión interpolada
    /// (<c>{installed}</c>, por ejemplo) aparece más de una vez en el mismo
    /// texto — caso real: <c>app-strings.installer-family-change</c>. Esta
    /// prueba lee <c>revision.csv</c> y compara, fila por fila, las
    /// expresiones de <c>texto_original</c> contra los marcadores de
    /// <c>texto_con_marcadores</c>, en orden de aparición: la misma expresión
    /// nunca puede traer dos marcadores distintos, y el mismo marcador nunca
    /// puede representar dos expresiones distintas (eso sería peor: dos datos
    /// reales fundidos en un solo hueco).
    /// </summary>
    [Fact]
    public void NingunaExpresionInterpoladaRepetidaTieneHuecosDistintos()
    {
        string path = RequireFile("revision.csv");
        var expressionPattern = new Regex(@"\{[^{}]*\}");
        var markerPattern = new Regex(@"\{(\d+)\}");

        foreach (string line in File.ReadAllLines(path).Skip(1))
        {
            if (line.Length == 0) continue;
            List<string> fields = ParseCsvLine(line);
            if (fields.Count < 7 || fields[6] != "sí") continue; // solo filas con interpolación

            string key = fields[0];
            List<string> expressions = [.. expressionPattern.Matches(fields[4]).Select(m => m.Value[1..^1])];
            List<string> markers = [.. markerPattern.Matches(fields[5]).Select(m => m.Groups[1].Value)];

            Assert.True(expressions.Count == markers.Count,
                $"clave {key}: {expressions.Count} expresión(es) en texto_original vs. {markers.Count} marcador(es) en texto_con_marcadores");

            var markerByExpression = new Dictionary<string, string>(StringComparer.Ordinal);
            var expressionByMarker = new Dictionary<string, string>(StringComparer.Ordinal);

            for (int i = 0; i < expressions.Count; i++)
            {
                string expression = expressions[i];
                string marker = markers[i];

                if (markerByExpression.TryGetValue(expression, out string? expectedMarker))
                    Assert.True(marker == expectedMarker,
                        $"clave {key}: la expresión {{{expression}}} aparece con huecos distintos ({{{expectedMarker}}} y {{{marker}}})");
                else
                    markerByExpression[expression] = marker;

                if (expressionByMarker.TryGetValue(marker, out string? expectedExpression))
                    Assert.True(expression == expectedExpression,
                        $"clave {key}: el hueco {{{marker}}} representa dos expresiones distintas ({{{expectedExpression}}} y {{{expression}}})");
                else
                    expressionByMarker[marker] = expression;
            }
        }
    }

    // MARK: - Los 9+ plurales por ternario tienen dos formas distintas

    /// <summary>
    /// Mismo hallazgo que la Mac tuvo que corregir en su propia prueba: no
    /// alcanza con "las dos formas no vacías" — puede haber un sufijo
    /// legítimamente vacío (p. ej. un plural que agrega una "s" sola en vez
    /// de repetir la palabra). Lo que sí tiene que ser cierto siempre es que
    /// las dos formas sean DISTINTAS entre sí.
    /// </summary>
    [Fact]
    public void LosPluralesPorTernarioTienenDosFormasDistintas()
    {
        string path = RequireFile("plurales-ternario.csv");
        string[] lines = File.ReadAllLines(path);
        Assert.True(lines.Length > 1, "plurales-ternario.csv no tiene filas de datos");

        foreach (string line in lines.Skip(1))
        {
            List<string> fields = ParseCsvLine(line);
            Assert.True(fields.Count >= 4, $"fila de plurales-ternario.csv con menos de 4 campos: {line}");

            string singular = fields[2];
            string plural = fields[3];
            Assert.NotEqual(singular, plural);
        }
    }

    private static Dictionary<string, string> ReadResw(string path)
    {
        XDocument doc = XDocument.Load(path);
        return doc.Root!.Elements("data")
            .ToDictionary(
                e => e.Attribute("name")!.Value,
                e => e.Element("value")?.Value ?? "",
                StringComparer.Ordinal);
    }

    private static List<string> ReadCsvKeys(string path, string? excludeKind = null)
    {
        string[] lines = File.ReadAllLines(path);
        return [.. lines.Skip(1)
            .Where(line => line.Length > 0)
            .Select(ParseCsvLine)
            .Where(fields => excludeKind is null || fields[1] != excludeKind)
            .Select(fields => fields[0])];
    }

    /// <summary>Un parser de CSV mínimo: comillas dobles, con <c>""</c> como escape adentro.</summary>
    private static List<string> ParseCsvLine(string line)
    {
        var fields = new List<string>();
        var current = new System.Text.StringBuilder();
        bool inQuotes = false;

        for (int i = 0; i < line.Length; i++)
        {
            char c = line[i];

            if (inQuotes)
            {
                if (c == '"' && i + 1 < line.Length && line[i + 1] == '"') { current.Append('"'); i++; }
                else if (c == '"') inQuotes = false;
                else current.Append(c);
            }
            else
            {
                if (c == '"') inQuotes = true;
                else if (c == ',') { fields.Add(current.ToString()); current.Clear(); }
                else current.Append(c);
            }
        }

        fields.Add(current.ToString());
        return fields;
    }
}
