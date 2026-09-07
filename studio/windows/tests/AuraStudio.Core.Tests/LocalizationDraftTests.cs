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
    /// miente sobre el estado. Hoy no hay ninguna fila así (los dos
    /// borradores nombran claves por archivo/miembro de forma independiente,
    /// así que ninguna coincide todavía sin alinearlas a mano) — la prueba
    /// pasa vacía, y empieza a verificar de verdad en cuanto B7a/A7a alineen
    /// la primera.
    /// </summary>
    [Fact]
    public void TodaClaveCompartidaMarcadaIgualExisteEnElReswDeWindows()
    {
        Dictionary<string, string> resw = ReadResw(RequireFile(Path.Combine("Strings", "es", "Resources.resw")));
        string sharedPath = RequireFile("claves-compartidas.csv");

        List<string> igualKeys = [.. File.ReadAllLines(sharedPath)
            .Skip(1)
            .Where(line => line.Length > 0)
            .Select(ParseCsvLine)
            .Where(fields => fields[^1] == "igual")
            .Select(fields => fields[0])];

        List<string> missing = [.. igualKeys.Where(key => !resw.ContainsKey(key)).Distinct(StringComparer.Ordinal)];
        Assert.True(missing.Count == 0,
            "claves-compartidas.csv marca 'igual' una clave que no está en el .resw de Windows: " +
            string.Join(", ", missing.Take(10)));
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
