using AuraStudio.Tools.ExtraerCadenasWindows;
using Xunit;

namespace ExtraerCadenasWindows.Tests;

/// <summary>
/// A7a (encargo del coordinador): <c>AutomationProperties.Name</c> (el
/// nombre para el lector de pantalla) y <c>ToolTipService.ToolTip</c> se
/// suman a <c>Header</c>/<c>PlaceholderText</c>, que ya estaban cubiertos.
/// </summary>
public class XamlExtractorTests
{
    [Fact]
    public void UnXamlDeEjemploConLosCuatroAtributosProduceCuatroSitios()
    {
        const string xaml = """
            <Page>
                <TextBox PlaceholderText="Buscar canciones" />
                <TextBlock Header="Nombre del dispositivo" />
                <Button AutomationProperties.Name="Cerrar" ToolTipService.ToolTip="Cerrar esta ventana" />
            </Page>
            """;

        List<Site> sites = XamlExtractor.Extract("AuraStudio.App/Views/Ejemplo.xaml", xaml, new KeyRegistry());

        Assert.Equal(4, sites.Count);
        Assert.Contains(sites, s => s.TextOriginal == "Buscar canciones");
        Assert.Contains(sites, s => s.TextOriginal == "Nombre del dispositivo");
        Assert.Contains(sites, s => s.TextOriginal == "Cerrar");
        Assert.Contains(sites, s => s.TextOriginal == "Cerrar esta ventana");
    }

    /// <summary>
    /// <c>AutomationProperties.AutomationId</c> es un identificador estable
    /// para pruebas (capturas por idioma, ST-227), no texto de cara al
    /// usuario -- nunca tiene que producir un sitio, aunque el atributo
    /// también empiece con <c>AutomationProperties.</c>.
    /// </summary>
    [Fact]
    public void AutomationIdNuncaProduceUnSitio()
    {
        const string xaml = """<Button AutomationProperties.AutomationId="ajustes.pestana.almacenamiento" />""";

        List<Site> sites = XamlExtractor.Extract("AuraStudio.App/Views/Ejemplo.xaml", xaml, new KeyRegistry());

        Assert.Empty(sites);
    }

    [Fact]
    public void UnXBindEnAutomationPropertiesNameOToolTipSeDescarta()
    {
        const string xaml = """
            <Button AutomationProperties.Name="{x:Bind Title}" ToolTipService.ToolTip="{x:Bind Title}" />
            """;

        List<Site> sites = XamlExtractor.Extract("AuraStudio.App/Views/Ejemplo.xaml", xaml, new KeyRegistry());

        Assert.Empty(sites);
    }
}
