using System.Text;
using System.Text.RegularExpressions;

namespace AuraStudio.Tools.ExtraerCadenasWindows;

/// <summary>
/// Actualiza <c>docs/extraccion-cadenas/claves-compartidas.csv</c> —
/// co-propiedad con la Mac desde que la Maestra tuvo que fusionarlo a mano
/// una vez (ST-247, addendum). Regla del reparto: Windows edita SOLO la
/// columna "sitio Windows" (y agrega filas "solo Windows" a mano, fuera de
/// esta clase — ver <c>README.md</c> de la carpeta); "sitio Mac" y "estado"
/// son de la Mac. **Ninguna herramienta regenera el archivo entero**: esto
/// es un <b>parche por clave</b>, no una reescritura.
///
/// <para>Para que "correr la herramienta sin cambios en el código deja el
/// archivo byte a byte idéntico" sea cierto de verdad, esto nunca reconstruye
/// una fila desde cero: encuentra el RANGO exacto de la columna "sitio
/// Windows" dentro de la línea cruda (consciente de comillas, sin tocar el
/// resto) y solo esa porción se reemplaza si el contenido cambió. Las otras
/// cuatro columnas —incluida cualquier comilla o espacio que la Mac haya
/// escrito a su manera— quedan intactas carácter por carácter.</para>
/// </summary>
public static class ClavesCompartidasCsv
{
    private const int SitioWindowsColumnIndex = 3; // clave=0, texto es=1, sitio Mac=2, sitio Windows=3, estado=4

    // \S+ para la ruta, no [^:;()]+: una ruta real nunca trae espacios, pero
    // un espacio SÍ puede venir justo antes en el separador "; " entre dos
    // citas -- con una clase que no excluye espacio, ese espacio se cuela
    // dentro del grupo "path" del match y se pierde al reemplazar (bug real,
    // encontrado corriendo la herramienta: "; " se quedaba en ";").
    private static readonly Regex Citation = new(
        @"(?<path>\S+?):(?<line>\d+)\s*\((?<key>[a-z0-9][\w.-]*)(?<note>,[^)]*)?\)",
        RegexOptions.Compiled);

    /// <summary>
    /// <paramref name="currentSitesByKey"/>: todo lo que <c>revision.csv</c>
    /// trae en esta corrida, indexado por clave. Devuelve cuántas citas se
    /// actualizaron y cuáles claves citadas ya no existen (para avisar, sin
    /// tocar la fila -- una clave ausente puede ser un renombre que todavía
    /// no se reconcilió, no algo que este parche deba adivinar).
    /// </summary>
    public static (int Updated, List<string> MissingKeys) UpdateSitioWindows(
        string path, IReadOnlyDictionary<string, Site> currentSitesByKey)
    {
        if (!File.Exists(path)) return (0, []);

        string[] lines = File.ReadAllLines(path);
        int updated = 0;
        var missing = new List<string>();

        for (int i = 1; i < lines.Length; i++) // fila 0 = encabezado, intacto
        {
            if (lines[i].Length == 0) continue;

            (int start, int end) = FindField(lines[i], SitioWindowsColumnIndex);
            if (start < 0) continue; // línea con menos columnas de las esperadas -- no se toca

            string rawField = lines[i][start..end];
            string unquoted = Unquote(rawField);
            if (unquoted == "—") continue; // solo Mac: nada que actualizar

            string newUnquoted = Citation.Replace(unquoted, match =>
            {
                string key = match.Groups["key"].Value;
                if (!currentSitesByKey.TryGetValue(key, out Site? site))
                {
                    missing.Add(key);
                    return match.Value; // se deja tal cual -- no se adivina un renombre
                }

                return $"{site.File}:{site.Line} ({key}{match.Groups["note"].Value})";
            });

            if (newUnquoted == unquoted) continue;

            string newField = Requote(newUnquoted);
            lines[i] = lines[i][..start] + newField + lines[i][end..];
            updated++;
        }

        if (updated > 0) File.WriteAllText(path, string.Join('\n', lines) + "\n", new UTF8Encoding(false));

        return (updated, missing);
    }

    /// <summary>El rango [start, end) del campo <paramref name="fieldIndex"/> (0-based) dentro de una línea CSV cruda.</summary>
    private static (int Start, int End) FindField(string line, int fieldIndex)
    {
        int i = 0, start = 0, field = 0;
        bool inQuotes = false;

        while (i < line.Length)
        {
            char c = line[i];

            if (inQuotes)
            {
                if (c == '"')
                {
                    if (i + 1 < line.Length && line[i + 1] == '"') { i += 2; continue; }
                    inQuotes = false;
                }
                i++;
                continue;
            }

            if (c == '"') { inQuotes = true; i++; continue; }

            if (c == ',')
            {
                if (field == fieldIndex) return (start, i);
                field++;
                start = i + 1;
            }

            i++;
        }

        return field == fieldIndex ? (start, line.Length) : (-1, -1);
    }

    private static string Unquote(string field)
    {
        if (field.Length < 2 || field[0] != '"' || field[^1] != '"') return field;
        return field[1..^1].Replace("\"\"", "\"");
    }

    private static string Requote(string value)
    {
        bool needsQuoting = value.Contains(',') || value.Contains('"') || value.Contains('\n');
        if (!needsQuoting) return value;
        return "\"" + value.Replace("\"", "\"\"") + "\"";
    }
}
