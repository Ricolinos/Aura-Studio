using System.Globalization;
using AuraStudio.Core.Resources;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// El selector marca "(beta)" los idiomas que nadie revisó, y lo explica
/// (ST-247, B7c/B7d).
///
/// <para><b>Qué se comprueba y por qué así.</b> Los cuatro idiomas de B7c
/// todavía están <c>Offered: false</c>, así que hoy el selector no los muestra
/// y no hay nada que mirar en pantalla. Lo que sí se puede comprobar —y es lo
/// que importa antes de encenderlos— es que <b>la marca no depende de
/// <c>Offered</c></b>: depende de <c>ReviewedByHumans</c>. Encenderlos no puede,
/// por construcción, encenderlos sin su advertencia.</para>
///
/// <para>Es la prueba "con <c>Offered</c> simulado" que pidió la Maestra: se
/// recorre <see cref="AppLanguages.All"/> —o sea, como si los seis se
/// ofrecieran— y se mira qué marca le tocaría a cada uno.</para>
/// </summary>
public class LanguageBadgeTests
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

    /// <summary>
    /// Con los seis ofrecidos, los cuatro sin revisar llevan marca y los dos
    /// revisados no.
    /// </summary>
    [Fact]
    public void ConLosSeisOfrecidosSoloLosCuatroSinRevisarLlevanMarca()
    {
        Assert.Equal(
            ["de", "fr", "ja", "ru"],
            AppLanguages.All
                .Where(LanguageBadge.ShowsMark)
                .Select(language => language.Culture)
                .Order(StringComparer.Ordinal));

        Assert.Equal(
            ["es", "en"],
            AppLanguages.All
                .Where(language => !LanguageBadge.ShowsMark(language))
                .Select(language => language.Culture));
    }

    /// <summary>
    /// La marca no mira <c>Offered</c>. Es lo que hace que encender los cuatro
    /// sea un cambio de una línea y no una lista de cosas que recordar.
    /// </summary>
    [Fact]
    public void LaMarcaNoDependeDeSiSeOfrece()
    {
        AppLanguage offered = new("de", "Deutsch", Built: true, Offered: true, ReviewedByHumans: false);
        AppLanguage hidden = offered with { Offered = false };

        Assert.True(LanguageBadge.ShowsMark(offered));
        Assert.True(LanguageBadge.ShowsMark(hidden));
        Assert.Equal(LanguageBadge.Mark(offered), LanguageBadge.Mark(hidden));
    }

    /// <summary>
    /// Y la marca y su línea existen en los seis idiomas. Una marca vacía se
    /// dibuja igual —con su espacio— y el usuario ve un paréntesis en blanco
    /// donde tendría que estar la advertencia.
    /// </summary>
    [Theory]
    [InlineData("es")]
    [InlineData("en")]
    [InlineData("de")]
    [InlineData("fr")]
    [InlineData("ru")]
    [InlineData("ja")]
    public void LaMarcaYSuLineaExistenEnCadaIdioma(string culture)
    {
        AppLanguage unreviewed = new("de", "Deutsch", Built: true, Offered: true, ReviewedByHumans: false);

        (string mark, string? detail) = WithUiCulture(culture,
            () => (LanguageBadge.Mark(unreviewed), LanguageBadge.Detail(unreviewed)));

        Assert.False(string.IsNullOrWhiteSpace(mark), $"la marca está vacía en {culture}");
        Assert.False(string.IsNullOrWhiteSpace(detail), $"la línea que la explica está vacía en {culture}");
    }

    /// <summary>
    /// Un idioma revisado no lleva línea, y lleva <c>null</c> y no cadena
    /// vacía: una línea vacía deja un hueco en la pantalla que nadie entiende.
    /// </summary>
    [Fact]
    public void UnIdiomaRevisadoNoLlevaNiMarcaNiLinea()
    {
        AppLanguage reviewed = AppLanguages.All.Single(language => language.Culture == "es");

        Assert.Equal("", LanguageBadge.Mark(reviewed));
        Assert.Null(LanguageBadge.Detail(reviewed));
    }
}
