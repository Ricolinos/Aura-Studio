namespace AuraStudio.Core.Library;

/// <summary>
/// Con qué reglas se agrupan las colaboraciones bajo el artista principal.
///
/// <para>Viaja como parámetro y no como estado global a propósito: la
/// agrupación depende de un ajuste del usuario, y una función de agrupación
/// que lee configuración por su cuenta no se puede probar ni razonar.</para>
/// </summary>
/// <param name="Enabled">
/// El ajuste «Agrupar las colaboraciones bajo el artista principal». Apagado,
/// la agrupación vuelve a ser exactamente la de antes de R2-4 — y como la
/// homologación nunca escribe nada, no hay nada que migrar.
/// </param>
/// <param name="Exceptions">
/// Nombres que <b>no se recortan</b> aunque traigan un separador, porque el
/// separador es parte del nombre del grupo ("Simon + Garfunkel", "Café con
/// Leche"). Se comparan contra el crédito COMPLETO, sin distinguir mayúsculas
/// ni acentos.
/// </param>
public sealed record ArtistGroupingOptions(bool Enabled, IReadOnlyList<string> Exceptions)
{
    /// <summary>Encendida y sin excepciones: lo que aplica mientras nadie configure nada.</summary>
    public static readonly ArtistGroupingOptions Default = new(true, []);

    /// <summary>Apagada: cada crédito es su propio artista, como antes de R2-4.</summary>
    public static readonly ArtistGroupingOptions Off = new(false, []);
}

/// <summary>
/// El <b>artista principal</b> de un crédito: lo que precede al primer
/// separador de colaboración. «Gorillaz feat. De La Soul» → «Gorillaz».
///
/// <para>La especificación vinculante es <c>docs/normalizacion-artistas.md</c>,
/// y la implementación de referencia es <c>ArtistNameNormalizer.swift</c> en la
/// app de macOS. <b>Misma regla, mismos separadores, mismo resultado</b>: una
/// diferencia acá parte la vista Artistas en dos según desde qué máquina se
/// abrió la biblioteca compartida, y le manda dos fotos distintas al iPod para
/// el mismo artista.</para>
///
/// <para>Es una función de <b>lectura</b>: jamás reescribe el artista de la
/// pista. Los créditos completos se conservan en la metadata, viajan en el
/// archivo y se siguen viendo en la tabla de canciones.</para>
/// </summary>
public static class ArtistNameNormalizer
{
    /// <summary>
    /// Lista <b>cerrada</b>. No se amplía "porque parece": cada entrada nueva
    /// reagrupa la biblioteca de alguien de un día para el otro.
    ///
    /// <para><c>feat.</c> y <c>feat</c> son entradas distintas a propósito (y
    /// <c>ft.</c> y <c>ft</c> también): como se comparan tokens completos,
    /// <c>feat.</c> no alcanzaría a un token <c>feat</c>.</para>
    /// </summary>
    public static readonly IReadOnlyList<string> Separators =
        ["feat.", "feat", "ft.", "ft", "featuring", "+", "with", "con"];

    /// <summary>
    /// Lo que <b>nunca</b> homologa, por decisión explícita del dueño: una
    /// colaboración con identidad propia es otro artista, no el principal con
    /// invitados. "Spacemonkeyz vs. Gorillaz" es un proyecto con nombre y
    /// discografía propios.
    ///
    /// <para>Se documenta como lista —y no como ausencia— para que se lea como
    /// decisión y no como olvido.</para>
    /// </summary>
    public static readonly IReadOnlyList<string> NeverJoined = ["vs.", "vs", "versus"];

    private static readonly HashSet<string> SeparatorSet =
        new(Separators.Select(LibraryGrouping.Normalize), StringComparer.Ordinal);

    /// <summary>
    /// El artista principal del crédito, o el crédito recortado cuando no hay
    /// nada que homologar. <b>Nunca devuelve cadena vacía si la entrada no lo
    /// era.</b>
    /// </summary>
    public static string PrincipalArtist(string? credit, ArtistGroupingOptions? options = null)
    {
        ArtistGroupingOptions rules = options ?? ArtistGroupingOptions.Default;
        string trimmed = (credit ?? "").Trim();

        if (!rules.Enabled || trimmed.Length == 0) return trimmed;
        if (IsException(trimmed, rules.Exceptions)) return trimmed;

        int cut = FirstSeparatorStart(trimmed);

        // Un separador en primera posición no deja artista principal
        // ("feat. Alguien"): recortarlo daría cadena vacía y esa pista caería
        // bajo "Artista desconocido", que es peor que no hacer nada.
        return cut <= 0 ? trimmed : trimmed[..cut].TrimEnd();
    }

    /// <summary>
    /// Lo mismo, pero ya normalizado para usar como clave de agrupación.
    /// </summary>
    public static string PrincipalKey(string? credit, ArtistGroupingOptions? options = null) =>
        LibraryGrouping.Normalize(PrincipalArtist(credit, options));

    /// <summary>
    /// Dónde empieza el primer separador, o -1 si no hay ninguno.
    ///
    /// <para>Se recorre el texto por tokens delimitados por espacios en vez de
    /// buscar la subcadena: <c>ft</c> vive dentro de "Daft Punk" y <c>con</c>
    /// dentro de "Confeti de Odio", y ninguno de los dos es un separador. Por
    /// lo mismo, <c>+</c> pegado ("Blink+182") no es un token suelto.</para>
    ///
    /// <para>Devuelve el índice sobre la cadena original —no sobre una versión
    /// normalizada— para poder cortar conservando la grafía exacta, acentos y
    /// espacios internos incluidos.</para>
    /// </summary>
    private static int FirstSeparatorStart(string credit)
    {
        int index = 0;

        while (index < credit.Length)
        {
            while (index < credit.Length && char.IsWhiteSpace(credit[index])) index++;
            if (index >= credit.Length) break;

            int start = index;
            while (index < credit.Length && !char.IsWhiteSpace(credit[index])) index++;

            if (SeparatorSet.Contains(LibraryGrouping.Normalize(credit[start..index]))) return start;
        }

        return -1;
    }

    private static bool IsException(string credit, IReadOnlyList<string> exceptions)
    {
        if (exceptions.Count == 0) return false;

        string key = LibraryGrouping.Normalize(credit);
        return exceptions.Any(exception => LibraryGrouping.Normalize(exception) == key);
    }
}
