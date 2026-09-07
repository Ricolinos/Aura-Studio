using System.Text;
using System.Xml;
using System.Xml.Linq;

namespace AuraStudio.Tools.ExtraerCadenasWindows;

/// <summary>
/// Escribe los tres borradores de revisión, en <c>docs/extraccion-cadenas/</c>
/// de Windows: el CSV, el <c>.resw</c> en español (con el texto real) y el
/// <c>.resw</c> en inglés (marcado como pendiente — nunca traducido a mano
/// acá, ver encargo). No toca nada de <c>AuraStudio.App</c>: estos archivos
/// no están cableados a la app todavía.
/// </summary>
public static class ResourceWriter
{
    public static void WriteRevisionCsv(string path, IReadOnlyList<Site> sites, IReadOnlyList<Site> fixedCulture)
    {
        var sb = new StringBuilder();
        // \n a mano, nunca AppendLine: el repo pide LF, y AppendLine usa
        // Environment.NewLine (\r\n en esta VM).
        sb.Append("clave,tipo,archivo,linea,texto_original,texto_con_marcadores,tiene_interpolacion,nota").Append('\n');

        foreach (Site site in sites.OrderBy(s => s.Key, StringComparer.Ordinal))
            AppendRow(sb, site);

        foreach (Site site in fixedCulture)
            AppendRow(sb, site);

        File.WriteAllText(path, sb.ToString(), new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
    }

    private static void AppendRow(StringBuilder sb, Site site)
    {
        sb.Append(Csv(site.Key)).Append(',')
          .Append(Csv(site.Kind)).Append(',')
          .Append(Csv(site.File)).Append(',')
          .Append(site.Line).Append(',')
          .Append(Csv(site.TextOriginal)).Append(',')
          .Append(Csv(site.TextWithMarkers)).Append(',')
          .Append(site.HasInterpolation ? "sí" : "no").Append(',')
          .Append(Csv(site.Note ?? ""))
          .Append('\n');
    }

    public static void WritePluralsCsv(string path, IReadOnlyList<PluralSite> plurals)
    {
        var sb = new StringBuilder();
        sb.Append("archivo,linea,singular,plural").Append('\n');

        foreach (PluralSite plural in plurals)
        {
            sb.Append(Csv(plural.File)).Append(',')
              .Append(plural.Line).Append(',')
              .Append(Csv(plural.Singular)).Append(',')
              .Append(Csv(plural.Plural))
              .Append('\n');
        }

        File.WriteAllText(path, sb.ToString(), new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
    }

    /// <summary>
    /// <paramref name="spanish"/>: clave -&gt; texto real (una entrada por
    /// clave única; si una clave se repite entre sitios, el primer texto
    /// gana — es la misma regla de "mismo texto, misma clave" del extractor).
    /// <paramref name="english"/>: <c>true</c> escribe el <c>.resw</c> en
    /// inglés con el valor VACÍO y un comentario "pendiente de traducir" —
    /// nunca una traducción a mano de lo que no sea trivial (encargo,
    /// punto 3).
    /// </summary>
    public static void WriteResw(string path, IReadOnlyDictionary<string, string> spanish, bool english)
    {
        XElement root = new("root",
            new XElement("resheader", new XAttribute("name", "resmimetype"),
                new XElement("value", "text/microsoft-resx")),
            new XElement("resheader", new XAttribute("name", "version"),
                new XElement("value", "2.0")),
            new XElement("resheader", new XAttribute("name", "reader"),
                new XElement("value", "System.Resources.ResXResourceReader, System.Windows.Forms, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089")),
            new XElement("resheader", new XAttribute("name", "writer"),
                new XElement("value", "System.Resources.ResXResourceWriter, System.Windows.Forms, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089")));

        foreach ((string key, string value) in spanish.OrderBy(kv => kv.Key, StringComparer.Ordinal))
        {
            XElement data = new("data", new XAttribute("name", key), new XAttribute(XNamespace.Xml + "space", "preserve"));

            if (english)
            {
                data.Add(new XElement("value", ""));
                data.Add(new XComment(" pendiente de traducir -- borrador de B7a, ver docs/extraccion-cadenas/revision.csv "));
            }
            else
            {
                data.Add(new XElement("value", value));
            }

            root.Add(data);
        }

        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        XDocument doc = new(new XDeclaration("1.0", "utf-8", null), root);

        var settings = new XmlWriterSettings
        {
            Indent = true,
            NewLineChars = "\n", // LF, no Environment.NewLine (\r\n en esta VM) -- regla del repo
            Encoding = new UTF8Encoding(encoderShouldEmitUTF8Identifier: false)
        };
        using XmlWriter writer = XmlWriter.Create(path, settings);
        doc.Save(writer);
    }

    private static string Csv(string value)
    {
        string normalized = value.Replace("\r\n", " ").Replace("\n", " ").Replace("\r", " ");
        bool needsQuoting = normalized.Contains(',') || normalized.Contains('"') || normalized.Contains('\n');
        if (!needsQuoting) return normalized;

        return "\"" + normalized.Replace("\"", "\"\"") + "\"";
    }
}
