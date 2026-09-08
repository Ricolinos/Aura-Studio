using System.Reflection;
using System.Text.RegularExpressions;
using AuraStudio.Core.Resources;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// Apagar los idiomas sin revisar es una propiedad de compilación, y las dos
/// posiciones se prueban (ST-247, encargo de la Maestra para el release 0.4.0).
///
/// <para><b>Para qué.</b> 0.4.0 va a salir de un solo commit para las dos
/// plataformas, posterior al cierre de B7d. Si el dueño decide que salga con
/// español e inglés nada más, Windows tiene que poder construirse desde ese
/// mismo commit sin ofrecer los cuatro: <c>-p:OfferMachineTranslations=false</c>,
/// o <c>-OfferMachineTranslations $false</c> en <c>Make-Installer.ps1</c>.</para>
///
/// <para><b>El problema de probar algo que se decide al compilar.</b> Este
/// ensamblado se compiló con un valor, así que por sí solo únicamente puede
/// ejercitar ese camino — y el otro es justamente el que se va a usar una sola
/// vez, el día del release, sin nadie mirando. Por eso la regla vive en
/// <see cref="AppLanguages.Offering"/>, que es una función pura y se prueba con
/// los dos valores en la misma corrida; y aparte se comprueba que la
/// compilación de verdad esté conectada a esa función y no a otra cosa.</para>
/// </summary>
public class OfferMachineTranslationsTests
{
    private static string WindowsRoot()
    {
        DirectoryInfo? directory = new(AppContext.BaseDirectory);

        while (directory is not null)
        {
            string candidate = Path.Combine(directory.FullName, "studio", "windows");
            if (File.Exists(Path.Combine(candidate, "AuraStudio.Windows.slnx"))) return candidate;

            directory = directory.Parent;
        }

        throw new InvalidOperationException("No se encontró la raíz del repo desde el directorio de pruebas.");
    }

    /// <summary>Con la propiedad apagada, el selector ofrece español e inglés.</summary>
    [Fact]
    public void ApagadaElSelectorOfreceEspanolEIngles() =>
        Assert.Equal(
            ["es", "en"],
            AppLanguages.Offering(AppLanguages.All, offerMachineTranslations: false)
                .Select(language => language.Culture));

    /// <summary>Y encendida, los seis.</summary>
    [Fact]
    public void EncendidaElSelectorOfreceLosSeis() =>
        Assert.Equal(
            ["es", "en", "de", "fr", "ja", "ru"],
            AppLanguages.Offering(AppLanguages.All, offerMachineTranslations: true)
                .Select(language => language.Culture));

    /// <summary>
    /// Apagarla no toca los satélites: los cinco se siguen generando y el
    /// instalador los sigue exigiendo.
    ///
    /// <para>Es la mitad que se olvida. Si apagar el ofrecimiento sacara los
    /// archivos del paquete, volver a encenderlos dejaría de ser una decisión de
    /// una línea y habría que rehacer y volver a medir el instalador.</para>
    /// </summary>
    [Fact]
    public void ApagarlaNoSacaNingunSateliteDelPaquete()
    {
        Assert.Equal(
            ["en", "de", "fr", "ja", "ru"],
            AppLanguages.RequiredSatelliteCultures);

        // Y la lista no depende de esta decisión, ni siquiera indirectamente:
        // sale de `Built`, que la propiedad no toca.
        Assert.All(AppLanguages.All, language => Assert.True(language.Built));
    }

    /// <summary>
    /// Un idioma apagado no se ofrece <b>ni por el selector ni por la cultura
    /// del sistema</b>.
    ///
    /// <para>Es la trampa que tiene esta clase de interruptor: se apaga la lista
    /// que se dibuja y se olvida la resolución automática. Alguien con Windows
    /// en alemán abriría la app en alemán, en un paquete que decidió no ofrecer
    /// alemán, con el selector mostrando dos idiomas y ninguna forma de entender
    /// qué pasó.</para>
    /// </summary>
    [Fact]
    public void ApagadaLaCulturaDelSistemaTampocoLosTrae()
    {
        IReadOnlyList<AppLanguage> offered =
            AppLanguages.Offering(AppLanguages.All, offerMachineTranslations: false);

        Assert.DoesNotContain(offered, language => language.Culture == "de");

        // `For` resuelve sobre lo que esta compilación ofrece. En una compilación
        // normal —la de main— alemán sí resuelve; lo que se comprueba acá es que
        // `For` mire esa lista y no la tabla entera, porque es el único punto
        // donde las dos podrían separarse.
        Assert.Equal(
            AppLanguages.Available.Any(language => language.Culture == "de"),
            AppLanguages.For(new System.Globalization.CultureInfo("de-DE")) is not null);
    }

    /// <summary>
    /// La compilación está conectada a la regla: <see cref="AppLanguages.Available"/>
    /// es exactamente lo que <see cref="AppLanguages.Offering"/> da para el valor
    /// con el que se compiló este ensamblado.
    ///
    /// <para>Sin esto, las dos pruebas de arriba comprobarían una función que
    /// podría no estar enchufada a nada.</para>
    /// </summary>
    [Fact]
    public void LaCompilacionUsaLaMismaRegla() =>
        Assert.Equal(
            AppLanguages.Offering(AppLanguages.All, AppLanguages.OffersMachineTranslations),
            AppLanguages.Available);

    /// <summary>
    /// El atributo existe en el ensamblado y dice lo mismo que
    /// <see cref="AppLanguages.OffersMachineTranslations"/>.
    ///
    /// <para>Si el <c>AssemblyAttribute</c> del <c>.csproj</c> dejara de
    /// emitirse, la propiedad caería a su valor por omisión —<c>true</c>— y todo
    /// seguiría pasando en verde mientras <c>-p:OfferMachineTranslations=false</c>
    /// no hace nada. Sería un interruptor que no está conectado, y el día que se
    /// use nadie se enteraría hasta ver el instalador ya hecho.</para>
    /// </summary>
    [Fact]
    public void ElAtributoViajaEnElEnsamblado()
    {
        OfferMachineTranslationsAttribute? attribute = typeof(AppLanguages).Assembly
            .GetCustomAttribute<OfferMachineTranslationsAttribute>();

        Assert.True(attribute is not null,
            "AuraStudio.Core no trae OfferMachineTranslationsAttribute. Se emite desde el .csproj "
            + "(AssemblyAttribute); si se cayó de ahí, -p:OfferMachineTranslations=false pasa a no "
            + "hacer nada y el paquete sale ofreciendo los seis sin que nada avise.");

        Assert.Equal(attribute!.Offered, AppLanguages.OffersMachineTranslations);
    }

    /// <summary>
    /// Por omisión se ofrecen: es el estado de <c>main</c>, y apagarlos tiene que
    /// ser un acto deliberado.
    ///
    /// <para>Al revés —apagados salvo que alguien los encienda— un error de
    /// compilación se vería igual que una decisión: la app saldría con dos
    /// idiomas y nadie sabría si alguien lo pidió.</para>
    /// </summary>
    [Fact]
    public void ElValorPorOmisionEsOfrecerlos()
    {
        string csproj = File.ReadAllText(Path.Combine(
            WindowsRoot(), "AuraStudio.Core", "AuraStudio.Core.csproj"));

        Assert.Matches(
            new Regex(@"<OfferMachineTranslations Condition=""'\$\(OfferMachineTranslations\)' == ''"">true</OfferMachineTranslations>"),
            csproj);
    }

    /// <summary>
    /// El guion del instalador expone la propiedad, se la pasa al publish e
    /// informa las <b>dos</b> listas.
    ///
    /// <para>La de idiomas incluidos y la de ofrecidos dejaron de ser la misma;
    /// imprimir solo una deja al que lee el log sin forma de distinguir una
    /// decisión de un satélite perdido.</para>
    /// </summary>
    [Fact]
    public void ElGuionDelInstaladorLaExponeYLaInforma()
    {
        string script = File.ReadAllText(Path.Combine(
            WindowsRoot(), "scripts", "Make-Installer.ps1"));

        Assert.Contains("[bool] $OfferMachineTranslations = $true", script, StringComparison.Ordinal);
        Assert.Contains("-p:OfferMachineTranslations=", script, StringComparison.Ordinal);
        Assert.Contains("Idiomas incluidos:", script, StringComparison.Ordinal);
        Assert.Contains("Idiomas ofrecidos:", script, StringComparison.Ordinal);

        // Y no se puede combinar con -SkipPublish: la decisión se graba al
        // publicar, así que saltarse el publish empaquetaría otra cosa de la
        // que el log informa.
        Assert.Contains("-SkipPublish", script, StringComparison.Ordinal);
        Assert.Matches(
            new Regex(@"if \(-not \$OfferMachineTranslations\) \{\s*throw", RegexOptions.Singleline),
            script);
    }

    /// <summary>
    /// La partición que el guion escribe a mano —revisados y sin revisar— es la
    /// de la tabla de verdad.
    ///
    /// <para>PowerShell no lee C#, así que la lista está escrita dos veces; lo
    /// que impide que se separen es esta prueba, igual que con los satélites.
    /// Una lista copiada es una lista que se desincroniza, y acá el síntoma
    /// sería un log que informa idiomas que el paquete no ofrece.</para>
    /// </summary>
    [Fact]
    public void LaParticionDelGuionEsLaDeLaTabla()
    {
        string script = File.ReadAllText(Path.Combine(
            WindowsRoot(), "scripts", "Make-Installer.ps1"));

        Assert.Equal(
            AppLanguages.All.Where(language => language.ReviewedByHumans)
                .Select(language => language.Culture).Order(StringComparer.Ordinal),
            CulturesIn(script, "culturasRevisadas").Order(StringComparer.Ordinal));

        Assert.Equal(
            AppLanguages.All.Where(language => !language.ReviewedByHumans)
                .Select(language => language.Culture).Order(StringComparer.Ordinal),
            CulturesIn(script, "culturasSinRevisar").Order(StringComparer.Ordinal));
    }

    private static string[] CulturesIn(string script, string variable)
    {
        Match declaration = Regex.Match(script, @"\$" + variable + @"\s*=\s*@\(([^)]*)\)");

        Assert.True(declaration.Success,
            $"No se encontró ${variable} en Make-Installer.ps1 — ¿se renombró? Si el guion dejó de "
            + "declarar esa lista, esta prueba no está comprobando nada.");

        return [.. Regex.Matches(declaration.Groups[1].Value, @"'([^']+)'").Select(m => m.Groups[1].Value)];
    }
}
