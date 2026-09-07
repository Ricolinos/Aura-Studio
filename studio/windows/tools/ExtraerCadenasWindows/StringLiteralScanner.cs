namespace AuraStudio.Tools.ExtraerCadenasWindows;

/// <summary>Un literal encontrado dentro de un fragmento de C#: su posición y si venía interpolado.</summary>
public sealed record RawLiteral(int Start, int End, string RawText, bool IsInterpolated);

/// <summary>
/// Encuentra literales de cadena (<c>"..."</c> y <c>$"..."</c>) dentro de un
/// fragmento de C#, sin depender de una sola expresión regular: hace falta
/// saber exactamente dónde empieza y termina cada cadena para no confundir
/// una comilla escapada (<c>\"</c>) con el cierre, y para no contar como
/// "literal de más" lo que hay DENTRO de un hueco de interpolación
/// (<c>{status.Progress * 100:0}</c> no es una cadena) ni sus llaves como
/// código real (para eso lo usa <see cref="MemberBodyFinder"/>).
///
/// <para>No es un lexer de C# completo — no necesita serlo para este borrador:
/// solo tiene que distinguir código de literales, y dentro de un hueco de
/// interpolación asume que no hay más literales anidados (cierto en todo el
/// código real de <c>AppStrings.cs</c> hoy, verificado a mano).</para>
/// </summary>
public static class StringLiteralScanner
{
    /// <summary>
    /// Si <paramref name="text"/>[<paramref name="i"/>] empieza un literal,
    /// avanza <paramref name="i"/> hasta justo después de su cierre y
    /// devuelve el literal. <c>null</c> si ahí no empieza ninguno —
    /// <paramref name="i"/> queda sin tocar.
    /// </summary>
    public static RawLiteral? TrySkip(string text, ref int i)
    {
        bool interpolated = text[i] == '$' && i + 1 < text.Length && text[i + 1] == '"';
        bool plain = !interpolated && text[i] == '"';
        if (!interpolated && !plain) return null;

        int start = i;
        i += interpolated ? 2 : 1;
        int contentStart = i;

        while (i < text.Length)
        {
            char c = text[i];

            if (c == '\\' && i + 1 < text.Length) { i += 2; continue; }

            if (interpolated && c == '{')
            {
                if (i + 1 < text.Length && text[i + 1] == '{') { i += 2; continue; } // {{ literal
                i++;
                int depth = 1;
                while (i < text.Length && depth > 0)
                {
                    if (text[i] == '{') depth++;
                    else if (text[i] == '}') depth--;
                    i++;
                }
                continue;
            }

            if (interpolated && c == '}' && i + 1 < text.Length && text[i + 1] == '}') { i += 2; continue; }

            if (c == '"') break;

            i++;
        }

        string raw = text[contentStart..Math.Min(i, text.Length)];
        int end = Math.Min(i + 1, text.Length);
        i = end;
        return new RawLiteral(start, end, raw, interpolated);
    }

    public static List<RawLiteral> Scan(string text)
    {
        var result = new List<RawLiteral>();
        int i = 0;

        while (i < text.Length)
        {
            RawLiteral? literal = TrySkip(text, ref i);
            if (literal is not null) { result.Add(literal); continue; }
            i++;
        }

        return result;
    }

    public static string Unescape(string raw) =>
        raw.Replace("\\\"", "\"").Replace("\\n", "\n").Replace("\\t", "\t").Replace("\\\\", "\\");
}
