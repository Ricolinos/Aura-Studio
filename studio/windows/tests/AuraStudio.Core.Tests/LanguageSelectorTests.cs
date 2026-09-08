using AuraStudio.Core.Resources;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// El selector ofrece los seis idiomas, y los cuatro sin revisar salen
/// marcados (ST-247, cierre de B7d).
///
/// <para><b>Qué pasó acá.</b> B7c dejó alemán, francés, japonés y ruso
/// traducidos, compilados y viajando en el instalador, pero <c>Offered:
/// false</c>: se generaban y no se ofrecían. B7d sacó a recurso lo que faltaba
/// —instalador, errores de disco, permisos— y esta es la línea que los
/// enciende.</para>
///
/// <para><b>Por qué la marca se comprueba acá otra vez.</b>
/// <see cref="LanguageBadgeTests"/> ya comprobaba que la marca depende de
/// <c>ReviewedByHumans</c> y no de <c>Offered</c>, pero lo hacía sobre
/// <see cref="AppLanguages.All"/> —con <c>Offered</c> simulado— porque los
/// cuatro todavía no se ofrecían. Ahora la misma promesa se comprueba sobre lo
/// que el selector muestra <b>de verdad</b>. Son dos pruebas de la misma cosa a
/// propósito: la de allá seguirá valiendo si mañana alguien apaga uno.</para>
/// </summary>
public class LanguageSelectorTests
{
    /// <summary>
    /// Los seis se ofrecen, y ninguno se ofrece sin estar compilado.
    ///
    /// <para>La lista esperada depende de <c>OfferMachineTranslations</c>, la
    /// propiedad con la que se compiló esto (ST-247). Sigue siendo exacta en las
    /// dos posiciones: no se afloja a "los que haya", porque entonces dejaría de
    /// avisar el día que se caiga uno. Se escribe así para que la compilación
    /// del release —la que apaga los cuatro— tenga su suite en verde: nueve
    /// pruebas rojas ahí obligarían a adivinar cuáles son esperadas.</para>
    /// </summary>
    [Fact]
    public void ElSelectorMuestraLosIdiomasQueEstaCompilacionOfrece()
    {
        string[] expected = AppLanguages.OffersMachineTranslations
            ? ["es", "en", "de", "fr", "ja", "ru"]
            : ["es", "en"];

        Assert.Equal(expected, AppLanguages.Available.Select(language => language.Culture));

        // Ofrecer un idioma que no se compiló es la falla silenciosa que
        // `Built`/`Offered` existen para evitar: el usuario lo elige, no hay
        // satélite, la app cae al español y no dice nada.
        Assert.All(AppLanguages.Available, language => Assert.True(language.Built,
            $"Se ofrece «{language.Culture}» y no está compilado: el usuario lo elegiría "
            + "y la app se quedaría en español sin avisar."));
    }

    /// <summary>
    /// Los cuatro de B7c salen con su marca y su línea; los dos revisados, sin
    /// nada. Se mira sobre lo que el selector ofrece, no sobre la tabla entera.
    /// </summary>
    [Fact]
    public void LosCuatroSinRevisarSeOfrecenMarcados()
    {
        // Si esta compilación no los ofrece, no hay ninguno marcado — y eso
        // también hay que comprobarlo: un paquete que dice ofrecer dos idiomas
        // y muestra un "(beta)" en alguna parte tiene un problema peor.
        string[] expected = AppLanguages.OffersMachineTranslations ? ["de", "fr", "ja", "ru"] : [];

        Assert.Equal(
            expected,
            AppLanguages.Available
                .Where(LanguageBadge.ShowsMark)
                .Select(language => language.Culture));

        foreach (AppLanguage language in AppLanguages.Available.Where(LanguageBadge.ShowsMark))
        {
            Assert.False(string.IsNullOrWhiteSpace(LanguageBadge.Mark(language)),
                $"«{language.Culture}» se ofrece sin revisar y su marca está vacía: "
                + "el usuario vería un paréntesis en blanco donde va la advertencia.");

            Assert.False(string.IsNullOrWhiteSpace(LanguageBadge.Detail(language)),
                $"«{language.Culture}» se ofrece sin revisar y no trae la línea que lo explica.");
        }

        Assert.Equal(
            ["es", "en"],
            AppLanguages.Available
                .Where(language => !LanguageBadge.ShowsMark(language))
                .Select(language => language.Culture));
    }

    /// <summary>
    /// «Se genera» y «se ofrece» siguen siendo dos cosas, aunque hoy coincidan.
    ///
    /// <para>Hoy los seis se generan y los seis se ofrecen, así que las dos
    /// listas dan lo mismo y una prueba que solo comparara sus contenidos no
    /// probaría nada. Lo que se comprueba es la <b>relación</b>: el instalador
    /// pide satélites por <c>Built</c>, nunca por <c>Offered</c>, para que apagar
    /// un idioma del selector no lo saque del instalador — y volver a
    /// encenderlo sea otra vez una línea.</para>
    /// </summary>
    [Fact]
    public void GenerarYOfrecerSiguenSiendoDosCosas()
    {
        AppLanguage hidden = new("de", "Deutsch", Built: true, Offered: false, ReviewedByHumans: false);

        Assert.Contains(hidden, new[] { hidden }.Where(language => language.Built));
        Assert.DoesNotContain(hidden, new[] { hidden }.Where(language => language.Offered));

        // Y en la tabla de verdad: los satélites exigidos son los compilados
        // menos el neutro, sin mirar si se ofrecen.
        Assert.Equal(
            AppLanguages.All
                .Where(language => language.Built && language.Culture != AppLanguages.NeutralCulture)
                .Select(language => language.Culture)
                .Order(StringComparer.Ordinal),
            AppLanguages.RequiredSatelliteCultures.Order(StringComparer.Ordinal));
    }
}
