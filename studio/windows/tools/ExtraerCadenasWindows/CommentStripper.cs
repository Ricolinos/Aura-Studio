using System.Text;

namespace AuraStudio.Tools.ExtraerCadenasWindows;

/// <summary>
/// Borra comentarios de C# (<c>//</c>, <c>///</c>, <c>/* */</c>) antes de
/// buscar literales — sin esto, un comentario que cita un texto de ejemplo
/// entre comillas (hay varios en este repo, ST-206 documentando "Aplicar
/// carátula recomendada a N álbumes" como prosa) se cuela como si fuera
/// código de verdad.
///
/// <para><b>Nunca toca lo que hay dentro de una cadena real</b> — reusa
/// <see cref="StringLiteralScanner"/> para reconocerlas y copiarlas intactas,
/// porque una cadena real puede contener <c>//</c> sin ser un comentario
/// (<c>InstallerDfuGuideUrl</c>, una URL con <c>https://</c>).</para>
///
/// <para>Reemplaza el comentario por espacios (conservando los saltos de
/// línea), nunca lo borra: los números de línea de todo lo demás tienen que
/// seguir siendo los mismos.</para>
/// </summary>
public static class CommentStripper
{
    public static string Strip(string text)
    {
        var sb = new StringBuilder(text.Length);
        int i = 0;

        while (i < text.Length)
        {
            RawLiteral? literal = StringLiteralScanner.TrySkip(text, ref i);
            if (literal is not null)
            {
                sb.Append(text, literal.Start, literal.End - literal.Start);
                continue;
            }

            if (text[i] == '/' && i + 1 < text.Length && text[i + 1] == '/')
            {
                while (i < text.Length && text[i] != '\n') { sb.Append(' '); i++; }
                continue;
            }

            if (text[i] == '/' && i + 1 < text.Length && text[i + 1] == '*')
            {
                sb.Append(' ', 2);
                i += 2;
                while (i < text.Length && !(text[i] == '*' && i + 1 < text.Length && text[i + 1] == '/'))
                {
                    sb.Append(text[i] == '\n' ? '\n' : ' ');
                    i++;
                }
                if (i < text.Length) { sb.Append(' ', Math.Min(2, text.Length - i)); i += 2; }
                continue;
            }

            sb.Append(text[i]);
            i++;
        }

        return sb.ToString();
    }
}
