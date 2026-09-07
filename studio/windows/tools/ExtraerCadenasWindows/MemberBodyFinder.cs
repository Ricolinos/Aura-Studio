using System.Text.RegularExpressions;

namespace AuraStudio.Tools.ExtraerCadenasWindows;

public sealed record Member(string Name, string BodyText, int BodyStartOffset);

/// <summary>
/// Parte <c>AppStrings.cs</c> en miembros (<c>public static string X => ...;</c>
/// o <c>public static string X(...) { ... }</c>), con el texto exacto de cada
/// cuerpo — para poder buscar literales adentro sin que un <c>;</c> o una
/// <c>}</c> que resulten estar DENTRO de una cadena interpolada corten el
/// cuerpo a la mitad.
/// </summary>
public static class MemberBodyFinder
{
    public static List<Member> FindAll(string fileText)
    {
        var members = new List<Member>();

        foreach (Match match in Regex.Matches(fileText,
            @"public\s+static\s+string\??\s+(?<name>\w+)\s*(?:\([^)]*\))?\s*"))
        {
            int afterSignature = match.Index + match.Length;
            int i = afterSignature;

            // Salta espacio/comentarios hasta encontrar `=>` o `{`.
            while (i < fileText.Length && char.IsWhiteSpace(fileText[i])) i++;

            bool isExpressionBodied = i + 1 < fileText.Length && fileText[i] == '=' && fileText[i + 1] == '>';
            bool isBlockBodied = i < fileText.Length && fileText[i] == '{';

            // No es un miembro de verdad (p. ej. quedó adentro de un
            // comentario, o el patrón alcanzó algo que no es una declaración) --
            // se salta en vez de adivinar.
            if (!isExpressionBodied && !isBlockBodied) continue;

            int bodyStart = isExpressionBodied ? i + 2 : i + 1;
            int bodyEnd = isExpressionBodied
                ? FindExpressionBodyEnd(fileText, bodyStart)
                : FindBlockBodyEnd(fileText, bodyStart);

            if (bodyEnd < 0) continue; // no se pudo cerrar limpio -- se descarta, no se adivina

            string bodyText = fileText[bodyStart..bodyEnd];
            members.Add(new Member(match.Groups["name"].Value, bodyText, bodyStart));
        }

        return members;
    }

    /// <summary>El índice justo DESPUÉS del <c>;</c> que cierra la expresión, a profundidad 0.</summary>
    private static int FindExpressionBodyEnd(string text, int start)
    {
        int depth = 0;
        int i = start;

        while (i < text.Length)
        {
            RawLiteral? literal = StringLiteralScanner.TrySkip(text, ref i);
            if (literal is not null) continue;

            char c = text[i];
            if (c == '{') depth++;
            else if (c == '}') depth--;
            else if (c == ';' && depth == 0) return i;

            i++;
        }

        return -1;
    }

    /// <summary>El índice justo DESPUÉS de la <c>}</c> que cierra el bloque (ya adentro de él).</summary>
    private static int FindBlockBodyEnd(string text, int start)
    {
        int depth = 1;
        int i = start;

        while (i < text.Length)
        {
            RawLiteral? literal = StringLiteralScanner.TrySkip(text, ref i);
            if (literal is not null) continue;

            char c = text[i];
            if (c == '{') depth++;
            else if (c == '}')
            {
                depth--;
                if (depth == 0) return i; // el propio '}' no forma parte del cuerpo
            }

            i++;
        }

        return -1;
    }

    public static int LineOf(string fileText, int offset)
    {
        int line = 1;
        for (int i = 0; i < offset && i < fileText.Length; i++)
            if (fileText[i] == '\n') line++;
        return line;
    }
}
