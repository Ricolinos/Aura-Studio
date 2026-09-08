using System.Globalization;
using AuraStudio.Core.Library;
using AuraStudio.Core.Resources;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// La explicación de Ajustes nombra exactamente los separadores que el código
/// usa (ST-247, B7d).
///
/// <para><b>El caso que la trajo.</b> El texto enumeraba los ocho separadores a
/// mano, al lado de una lista de ocho en <c>ArtistNameNormalizer</c>. Dos listas
/// que dicen lo mismo se separan, y ésta ya se había separado: decía que «vs.» y
/// «versus» no agrupan, y se olvidaba de «vs», que también está en la lista de
/// verdad. Nadie lo iba a ver — hay que leer las dos listas a la vez, en un
/// archivo de Ajustes y en uno de Core.</para>
///
/// <para>Y con seis idiomas el problema se multiplica por seis: cada traducción
/// era otra oportunidad de copiar mal ocho términos.</para>
/// </summary>
public class ArtistGroupingTextTests
{
    private static T WithUiCulture<T>(string culture, Func<T> body)
    {
        CultureInfo before = CultureInfo.CurrentUICulture;
        try
        {
            CultureInfo.CurrentUICulture = new CultureInfo(culture);
            return body();
        }
        finally
        {
            CultureInfo.CurrentUICulture = before;
        }
    }

    public static TheoryData<string> Cultures()
    {
        TheoryData<string> data = [];
        foreach (AppLanguage language in AppLanguages.Translated) data.Add(language.Culture);
        return data;
    }

    /// <summary>
    /// Cada término del código aparece <b>entrecomillado</b> en la explicación.
    ///
    /// <para>Entrecomillado y no suelto, y ahí está media prueba: buscar
    /// <c>"vs"</c> a secas lo encuentra dentro de <c>«vs.»</c>, así que la
    /// versión escrita a mano —a la que le faltaba justamente <c>«vs»</c>—
    /// pasaba. Se comprobó: con el texto viejo puesto de vuelta, la prueba en
    /// esta forma falla en los seis idiomas y en la otra no fallaba en
    /// ninguno.</para>
    /// </summary>
    [Theory]
    [MemberData(nameof(Cultures))]
    public void LaExplicacionNombraTodosLosSeparadoresDelCodigo(string culture)
    {
        (string detail, List<string> missing) = WithUiCulture(culture, () =>
        {
            string text = ArtistGroupingText.Detail();

            return (text, ArtistNameNormalizer.Separators
                .Concat(ArtistNameNormalizer.NeverJoined)
                .Select(term => Strings.Format("settings-view-model.quoted-term", term))
                .Where(quoted => !text.Contains(quoted, StringComparison.Ordinal))
                .ToList());
        });

        Assert.True(missing.Count == 0,
            $"En {culture} la explicación no nombra {string.Join(", ", missing)}, "
            + $"y el código sí los usa:\n  {detail}");
    }

    /// <summary>
    /// Cada idioma entrecomilla como entrecomilla ese idioma. Escrito una vez en
    /// el código, el alemán y el japonés habrían salido con comillas españolas.
    /// </summary>
    [Theory]
    [InlineData("es", "«feat.»")]
    [InlineData("en", "\"feat.\"")]
    [InlineData("de", "„feat.“")]
    [InlineData("fr", "« feat. »")]
    [InlineData("ru", "«feat.»")]
    [InlineData("ja", "「feat.」")]
    public void CadaIdiomaEntrecomillaComoLeToca(string culture, string expected) =>
        Assert.Contains(expected, WithUiCulture(culture, ArtistGroupingText.Detail), StringComparison.Ordinal);

    /// <summary>
    /// Y la enumeración lleva los ocho, no siete: es exactamente lo que el texto
    /// escrito a mano había perdido de vista.
    /// </summary>
    [Fact]
    public void LaListaEsLaDelCodigoYNoUnaCopia()
    {
        Assert.Equal(8, ArtistNameNormalizer.Separators.Count);
        Assert.Equal(3, ArtistNameNormalizer.NeverJoined.Count);

        string detail = WithUiCulture("es", ArtistGroupingText.Detail);

        // «vs» suelto es el que faltaba. Está dentro de «vs.», así que se busca
        // entrecomillado: si no, la prueba pasaría por el punto del otro.
        Assert.Contains("«vs»", detail, StringComparison.Ordinal);
    }
}
