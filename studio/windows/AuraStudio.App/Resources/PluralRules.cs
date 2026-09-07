using System.Globalization;

namespace AuraStudio.App.Resources;

/// <summary>
/// Qué forma plural le toca a un número, según el idioma (ST-247).
///
/// <para><b>Por qué existe.</b> La app tenía cuarenta y ocho ternarios
/// <c>count == 1 ? "1 canción" : $"{count} canciones"</c>. Eso no es una
/// condición: es <b>la regla del plural del español</b> escrita a mano,
/// cuarenta y ocho veces. En ruso hacen falta tres formas y en japonés una
/// sola, así que cada uno de esos ternarios sería un defecto en cuanto la app
/// hable otro idioma — y no uno que se vea al compilar, sino un texto mal
/// escrito en la pantalla de alguien.</para>
///
/// <para><b>Las formas viven en los recursos</b>, no acá: esto solo decide
/// <i>cuál</i> pedir. Es el mismo reparto que usa CLDR, con las tres familias
/// que la ronda necesita.</para>
/// </summary>
public static class PluralRules
{
    /// <summary>La forma que toda cultura tiene. Es el respaldo cuando falta otra.</summary>
    public const string OtherSuffix = ".other";

    public const string OneSuffix = ".one";
    public const string FewSuffix = ".few";
    public const string ManySuffix = ".many";

    /// <summary>
    /// El sufijo de la clave que hay que pedir para <paramref name="count"/>.
    /// </summary>
    public static string SuffixFor(int count, CultureInfo culture)
    {
        int absolute = Math.Abs(count);

        return FamilyOf(culture) switch
        {
            // Japonés, chino, coreano, vietnamita: no distinguen número. Una
            // sola forma, y meterles un plural inventado se lee mal.
            PluralFamily.Single => OtherSuffix,

            // Ruso, ucraniano, polaco: uno, pocos (2-4) y muchos, con la
            // excepción de los terminados en 11-14, que van a "muchos".
            PluralFamily.Slavic => SlavicSuffix(absolute),

            // Francés: el CERO va en singular ("0 chanson"), a diferencia del
            // español ("0 canciones"). Es la trampa de suponer que dos formas
            // significan la misma regla en todos los idiomas.
            PluralFamily.FrenchLike => absolute is 0 or 1 ? OneSuffix : OtherSuffix,

            // Español, inglés, alemán y la mayoría: uno y el resto.
            _ => absolute == 1 ? OneSuffix : OtherSuffix
        };
    }

    /// <summary>
    /// Todos los sufijos que una cultura puede llegar a pedir. Sirve para que
    /// una prueba compruebe que el archivo de recursos los trae todos: la forma
    /// que falta no se nota hasta que alguien cuenta justo ese número.
    /// </summary>
    public static IReadOnlyList<string> SuffixesFor(CultureInfo culture) => FamilyOf(culture) switch
    {
        PluralFamily.Single => [OtherSuffix],
        PluralFamily.Slavic => [OneSuffix, FewSuffix, ManySuffix],
        PluralFamily.FrenchLike => [OneSuffix, OtherSuffix],
        _ => [OneSuffix, OtherSuffix]
    };

    private static string SlavicSuffix(int absolute)
    {
        int lastTwo = absolute % 100;
        int last = absolute % 10;

        if (lastTwo is >= 11 and <= 14) return ManySuffix;
        if (last == 1) return OneSuffix;
        if (last is >= 2 and <= 4) return FewSuffix;

        return ManySuffix;
    }

    private enum PluralFamily { TwoForms, FrenchLike, Slavic, Single }

    /// <summary>
    /// A qué familia pertenece la cultura. Se mira el idioma de dos letras y no
    /// la cultura completa: <c>es-MX</c> y <c>es-ES</c> pluralizan igual, y
    /// enumerar países sería una lista que envejece sola.
    /// </summary>
    private static PluralFamily FamilyOf(CultureInfo culture) =>
        culture.TwoLetterISOLanguageName switch
        {
            "ja" or "zh" or "ko" or "vi" or "th" => PluralFamily.Single,
            "fr" or "pt" => PluralFamily.FrenchLike,
            "ru" or "uk" or "pl" or "cs" or "sk" => PluralFamily.Slavic,
            _ => PluralFamily.TwoForms
        };
}
