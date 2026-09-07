using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace AuraStudio.Tools.ExtraerCadenasWindows;

/// <summary>
/// Mismo criterio de nombres de clave que <c>tools/extraer-cadenas.py</c>
/// (Mac, ST-227): <c>&lt;identificador-en-kebab-case&gt;.&lt;slug-del-texto&gt;</c>,
/// con un contador de más si dos textos DISTINTOS producen el mismo slug.
///
/// <para>Para <c>AppStrings.cs</c>, el "identificador" es el prefijo fijo
/// <c>app-strings</c> y el slug sale del NOMBRE DEL MIEMBRO (p. ej.
/// <c>LibraryRemoveDetail</c> -&gt; <c>app-strings.library-remove-detail</c>),
/// no del texto en español: el miembro ya es un identificador legible y
/// estable, y eslugificar un párrafo largo produciría una clave enorme y
/// frágil ante el más mínimo cambio de redacción. Para todo lo demás
/// (XAML, <c>MenuEntry</c>, <c>StatusMessage</c>, <c>ContentDialog</c>) el
/// identificador es el nombre de archivo en kebab-case y el slug sale del
/// TEXTO, igual que en Mac.</para>
/// </summary>
public sealed class KeyRegistry
{
    private readonly HashSet<string> _used = new(StringComparer.Ordinal);

    private static readonly HashSet<string> StopWords = new(StringComparer.Ordinal)
    {
        "el", "la", "los", "las", "de", "del", "un", "una", "y", "en", "a", "tu", "su", "que", "no"
    };

    public string Unique(string baseKey)
    {
        string key = baseKey;
        int suffix = 2;
        while (!_used.Add(key))
        {
            key = $"{baseKey}-{suffix}";
            suffix++;
        }

        return key;
    }

    public static string FileStemKebab(string filePath) => PascalToKebab(Path.GetFileNameWithoutExtension(filePath));

    public static string MemberKebab(string memberName) => PascalToKebab(memberName);

    /// <summary>
    /// PascalCase -&gt; kebab-case, sin partir una sigla en letras sueltas
    /// (addendum de ST-247, a partir de un hallazgo del Experto: `NavPhotosAI`
    /// salía `nav-photos-a-i` en vez de `nav-photos-ai`). Dos reglas, no una:
    /// un guion antes de una mayúscula que sigue a una minúscula/dígito
    /// (`PhotosAI` -&gt; `Photos-AI`, el borde normal de PascalCase), y un
    /// guion DENTRO de una racha de mayúsculas solo en el borde de salida —
    /// antes de la última mayúscula de la racha si la sigue una minúscula
    /// (`HTTPRequest` -&gt; `HTTP-Request`, no `H-T-T-P-Request`) — nunca entre
    /// dos mayúsculas consecutivas dentro de la misma sigla.
    /// </summary>
    private static string PascalToKebab(string value)
    {
        string withHyphens = Regex.Replace(
            value,
            "(?<=[a-z0-9])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])",
            "-");

        return withHyphens.ToLowerInvariant();
    }

    /// <summary>Texto en español -&gt; slug ascii-kebab-case. Nunca vacío.</summary>
    public static string Slugify(string text, int maxWords = 6, int maxLen = 40)
    {
        string normalized = text.Normalize(NormalizationForm.FormD);
        var ascii = new StringBuilder(normalized.Length);
        foreach (char c in normalized)
        {
            if (CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark)
                ascii.Append(c);
        }

        // Los huecos de interpolación ya vinieron reemplazados por "0"/"1"/...
        // (ver InterpolationHoles): no aportan nada al slug salvo ruido.
        string cleaned = Regex.Replace(ascii.ToString(), @"\{\d+\}", " ");

        List<string> words = [.. Regex.Matches(cleaned.ToLowerInvariant(), "[a-z0-9]+")
            .Select(m => m.Value)
            .Where(w => !StopWords.Contains(w))
            .Take(maxWords)];

        string slug = words.Count == 0 ? "texto" : string.Join("-", words);
        if (slug.Length > maxLen) slug = slug[..maxLen].TrimEnd('-');
        return slug;
    }
}
