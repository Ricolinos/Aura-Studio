using AuraStudio.Core.Resources;

namespace AuraStudio.Core.Library;

/// <summary>
/// La explicación de Ajustes sobre cómo se agrupan las colaboraciones
/// (ST-247, B7d).
///
/// <para><b>Por qué no es una frase suelta.</b> El texto enumeraba los ocho
/// separadores a mano —«feat.», «feat», «ft.»…— al lado de una lista de ocho en
/// el código. Dos listas que dicen lo mismo son dos listas que se van a
/// separar, y la de Ajustes ya se había separado: decía que «vs.» y «versus» no
/// agrupan, y se olvidaba de «vs», que también está en la lista de verdad.</para>
///
/// <para>Ahora la enumeración se arma desde <see cref="ArtistNameNormalizer"/>,
/// así que no puede quedar vieja. Y las comillas y el separador de la lista son
/// claves, no caracteres escritos acá: en alemán se abre abajo, en francés
/// llevan espacio adentro y en japonés son otras.</para>
/// </summary>
public static class ArtistGroupingText
{
    public static string Detail() => Strings.Format(
        "settings-view-model.group-collaborations-detail",
        Enumerated(ArtistNameNormalizer.Separators),
        Enumerated(ArtistNameNormalizer.NeverJoined));

    /// <summary>Los términos entrecomillados como los entrecomilla ese idioma, y unidos.</summary>
    public static string Enumerated(IReadOnlyList<string> terms) =>
        string.Join(
            Strings.Get("settings-view-model.term-joiner"),
            terms.Select(term => Strings.Format("settings-view-model.quoted-term", term)));
}
