using System.Globalization;
using AuraStudio.Core.Library;
using AuraStudio.Core.Resources;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// La frase del final de una sincronización, leída entera (ST-247, B7d).
///
/// <para>Se armaba con cinco pedazos dentro de la vista y ninguno se podía leer
/// desde una prueba. Al mudarla acá se vio lo que escondía: los conteos estaban
/// pluralizados con paréntesis —«{0} archivo(s) copiado(s)», «no se
/// pudo(ieron) copiar»—, un truco que ya en español se lee mal y que en los
/// otros cinco idiomas no existe.</para>
/// </summary>
public class SyncSummaryTextTests
{
    private static string Describe(
        string culture, int copied, int removed = 0, int failures = 0, bool cancelled = false)
    {
        CultureInfo before = CultureInfo.CurrentUICulture;
        try
        {
            CultureInfo.CurrentUICulture = new CultureInfo(culture);
            return SyncSummaryText.Describe(true, null, copied, removed, failures, cancelled);
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
    /// Ningún paréntesis de plural sobrevive en ningún idioma. Es lo que se
    /// vino a quitar, y buscarlo es barato.
    /// </summary>
    [Theory]
    [MemberData(nameof(Cultures))]
    public void NoQuedaNingunPluralConParentesis(string culture)
    {
        foreach (int count in (int[])[0, 1, 2, 5, 21, 101])
        {
            string summary = Describe(culture, copied: count, removed: count, failures: count);

            Assert.DoesNotContain("(s)", summary, StringComparison.Ordinal);
            Assert.DoesNotContain("(ieron)", summary, StringComparison.Ordinal);
        }
    }

    /// <summary>
    /// Un archivo y muchos se leen distinto — que es lo que el paréntesis
    /// tapaba.
    /// </summary>
    [Theory]
    [MemberData(nameof(Cultures))]
    public void UnoYVariosNoSeDicenIgual(string culture)
    {
        string one = Describe(culture, copied: 1);
        string seven = Describe(culture, copied: 7);

        // La misma frase con el número cambiado. Si eso es lo que sale, el
        // idioma no está distinguiendo singular de plural.
        string justTheNumber = one.Replace("1", "7", StringComparison.Ordinal);

        if (culture == "ja")
        {
            // El japonés no distingue número, así que aquí eso es lo correcto —
            // y se comprueba, no se saltea. Un `return` temprano habría dejado
            // al japonés sin ninguna aserción, que es la forma más fácil de
            // tener una prueba en verde que no mira nada.
            Assert.Equal(justTheNumber, seven);
            return;
        }

        Assert.NotEqual(justTheNumber, seven);
    }

    /// <summary>
    /// El 21 va con la forma del uno en ruso, y el 11 no.
    ///
    /// <para>Es la regla que un <c>1 =&gt;</c> escrito a mano no puede
    /// cumplir, y la que hacía decir "21 архив" donde va "21 файл".</para>
    /// </summary>
    [Fact]
    public void ElRusoUsaLaFormaDelUnoParaElVeintiuno()
    {
        string one = Describe("ru", copied: 1);
        string twentyOne = Describe("ru", copied: 21);
        string eleven = Describe("ru", copied: 11);

        Assert.Equal(one.Replace("1", "21", StringComparison.Ordinal), twentyOne);
        Assert.NotEqual(one.Replace("1", "11", StringComparison.Ordinal), eleven);
    }

    /// <summary>
    /// Lo que se quitó del iPod solo se menciona cuando se quitó algo. Cero
    /// borrados no es «y 0 quitados»: es no decirlo.
    /// </summary>
    [Fact]
    public void SinBorradosNoSeHablaDeBorrados()
    {
        string summary = Describe("es", copied: 3);

        Assert.DoesNotContain("quitad", summary, StringComparison.Ordinal);
        Assert.Contains("3 archivos copiados", summary, StringComparison.Ordinal);
    }

    /// <summary>Y los fallos solo aparecen si hubo alguno.</summary>
    [Fact]
    public void LosFallosSoloAparecenSiLosHubo()
    {
        Assert.DoesNotContain("no se pudieron copiar", Describe("es", copied: 3),
            StringComparison.Ordinal);
        Assert.Contains("no se pudieron copiar", Describe("es", copied: 3, failures: 2),
            StringComparison.Ordinal);
    }

    /// <summary>
    /// Cancelar cuenta lo que sí se copió: cancelar no pierde nada, y la frase
    /// tiene que decirlo.
    /// </summary>
    [Fact]
    public void CancelarCuentaLoQueSeAlcanzoACopiar()
    {
        string summary = Describe("es", copied: 4, cancelled: true);

        Assert.Contains("Cancelaste", summary, StringComparison.Ordinal);
        Assert.Contains("4 archivos copiados", summary, StringComparison.Ordinal);
    }

    /// <summary>
    /// Un fallo sin explicación no deja al usuario con una frase vacía. Y si
    /// viene explicado desde más abajo, se respeta esa explicación.
    /// </summary>
    [Fact]
    public void UnFalloSiempreDiceAlgo()
    {
        Assert.Equal("El disco se llenó.",
            SyncSummaryText.Describe(false, "El disco se llenó.", 0, 0, 0, false));

        Assert.NotEmpty(SyncSummaryText.Describe(false, null, 0, 0, 0, false));
        Assert.NotEmpty(SyncSummaryText.Describe(false, "", 0, 0, 0, false));
    }
}
