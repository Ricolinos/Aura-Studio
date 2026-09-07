using System.Text.RegularExpressions;

namespace AuraStudio.Tools.ExtraerCadenasWindows;

/// <summary>
/// Une los fragmentos de una misma expresión de concatenación
/// (<c>"a" + "b"</c>, con saltos de línea entre medio) en UN solo literal,
/// antes de que se les asigne clave (ST-247, addendum del Experto).
///
/// <para>Sin esto, un párrafo escrito como dos literales por legibilidad —
/// <c>"Copiar a la Biblioteca de Aura: ... y los " + "sincroniza directo;
/// ... después."</c>, el patrón real de <c>AppStrings.cs</c>— salía como DOS
/// claves, cada una con medio pensamiento cortado a mitad de oración: no se
/// puede traducir (el orden de palabras cambia por idioma) y no coincide con
/// el borrador de la Mac, que la tiene como una sola frase.</para>
///
/// <para>La regla: dos literales adyacentes se funden si TODO lo que hay
/// entre el cierre del primero y la apertura del segundo es, recortado,
/// exactamente un <c>+</c> — nada de código real de por medio. Los
/// comentarios ya están en blanco a esa altura (<see cref="CommentStripper"/>
/// corre antes), así que un <c>+</c> con un comentario al lado entre los dos
/// literales también cuenta.</para>
/// </summary>
public static class LiteralCoalescer
{
    private static readonly Regex OnlyPlusBetween = new(@"^\s*\+\s*$", RegexOptions.Compiled);

    /// <summary>
    /// <paramref name="literalsInOrder"/> tiene que venir ordenada por
    /// posición y ya sin los literales que otro paso (ternario de plural,
    /// brazo de <c>switch</c>) haya consumido — este método no filtra nada,
    /// solo funde lo que le llega.
    /// </summary>
    public static List<RawLiteral> Coalesce(string text, IReadOnlyList<RawLiteral> literalsInOrder)
    {
        var result = new List<RawLiteral>();
        int i = 0;

        while (i < literalsInOrder.Count)
        {
            RawLiteral current = literalsInOrder[i];
            string combinedRaw = current.RawText;
            bool anyInterpolated = current.IsInterpolated;
            int end = current.End;

            int j = i + 1;
            while (j < literalsInOrder.Count)
            {
                RawLiteral next = literalsInOrder[j];
                string between = text[end..next.Start];
                if (!OnlyPlusBetween.IsMatch(between)) break;

                combinedRaw += next.RawText;
                anyInterpolated |= next.IsInterpolated;
                end = next.End;
                j++;
            }

            result.Add(new RawLiteral(current.Start, end, combinedRaw, anyInterpolated));
            i = j;
        }

        return result;
    }
}
