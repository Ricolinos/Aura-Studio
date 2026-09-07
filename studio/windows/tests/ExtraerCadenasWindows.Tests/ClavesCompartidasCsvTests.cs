using AuraStudio.Tools.ExtraerCadenasWindows;
using Xunit;

namespace ExtraerCadenasWindows.Tests;

/// <summary>
/// <c>claves-compartidas.csv</c> es co-propiedad con la Mac (ST-247,
/// addendum): esto prueba que <see cref="ClavesCompartidasCsv.UpdateSitioWindows"/>
/// nunca regenera el archivo entero, solo parchea la columna "sitio Windows"
/// de las claves que ya cita.
/// </summary>
public class ClavesCompartidasCsvTests : IDisposable
{
    private readonly string _path;

    public ClavesCompartidasCsvTests()
    {
        _path = Path.Combine(Path.GetTempPath(), "claves-compartidas-" + Guid.NewGuid().ToString("N") + ".csv");
    }

    public void Dispose()
    {
        try { File.Delete(_path); } catch { /* best effort */ }
    }

    [Fact]
    public void SinCambiosDeVerdadElArchivoQuedaByteAByteIdentico()
    {
        string original =
            "clave,texto es,sitio Mac,sitio Windows,estado\n" +
            "storage-section-title,Cómo guardar tu música,studio/Mac/AppStrings.swift (S.x),studio/windows/AuraStudio.App/Resources/AppStrings.cs:283 (app-strings.storage-section-title),igual\n" +
            "orphans-title,Archivos huérfanos,—,studio/windows/AuraStudio.App/Resources/AppStrings.cs:306 (app-strings.orphans-title),solo Windows\n";
        File.WriteAllText(_path, original);

        var sites = new Dictionary<string, Site>(StringComparer.Ordinal)
        {
            ["app-strings.storage-section-title"] = new Site(
                "app-strings.storage-section-title", "studio/windows/AuraStudio.App/Resources/AppStrings.cs", 283,
                "AppStrings", "Cómo guardar tu música", "Cómo guardar tu música", false),
            ["app-strings.orphans-title"] = new Site(
                "app-strings.orphans-title", "studio/windows/AuraStudio.App/Resources/AppStrings.cs", 306,
                "AppStrings", "Archivos huérfanos", "Archivos huérfanos", false),
        };

        (int updated, List<string> missing) = ClavesCompartidasCsv.UpdateSitioWindows(_path, sites);

        Assert.Equal(0, updated);
        Assert.Empty(missing);
        Assert.Equal(original, File.ReadAllText(_path));
    }

    /// <summary>
    /// Una columna "sitio Mac" con comillas y comas adentro (como las que
    /// escribe la Mac de verdad, p. ej. citando un texto entre comillas)
    /// tiene que sobrevivir intacta, carácter por carácter, aunque la MISMA
    /// fila sí tenga que actualizar su columna "sitio Windows".
    /// </summary>
    [Fact]
    public void UnaColumnaSitioMacConComillasYComasSobreviveALaRegeneracion()
    {
        string sitioMacConComillasYComas =
            "\"studio/Mac/View.swift:10, con una nota que dice \"\"así, con comillas\"\" adentro\"";
        string original =
            "clave,texto es,sitio Mac,sitio Windows,estado\n" +
            $"algo,Texto,{sitioMacConComillasYComas},studio/windows/AuraStudio.App/Resources/AppStrings.cs:100 (app-strings.algo),clave distinta\n";
        File.WriteAllText(_path, original);

        var sites = new Dictionary<string, Site>(StringComparer.Ordinal)
        {
            ["app-strings.algo"] = new Site(
                "app-strings.algo", "studio/windows/AuraStudio.App/Resources/AppStrings.cs", 205,
                "AppStrings", "Texto", "Texto", false),
        };

        (int updated, List<string> missing) = ClavesCompartidasCsv.UpdateSitioWindows(_path, sites);

        Assert.Equal(1, updated);
        Assert.Empty(missing);

        string[] lines = File.ReadAllLines(_path);
        Assert.Contains(sitioMacConComillasYComas, lines[1]); // columna "sitio Mac" intacta
        Assert.Contains("AppStrings.cs:205", lines[1]);       // columna "sitio Windows" sí se actualizó
    }

    [Fact]
    public void UnaFilaSoloMacNuncaSeToca()
    {
        string original =
            "clave,texto es,sitio Mac,sitio Windows,estado\n" +
            "algo-de-mac,Texto,studio/Mac/View.swift:10,—,solo Mac\n";
        File.WriteAllText(_path, original);

        (int updated, List<string> missing) = ClavesCompartidasCsv.UpdateSitioWindows(_path, new Dictionary<string, Site>());

        Assert.Equal(0, updated);
        Assert.Empty(missing);
        Assert.Equal(original, File.ReadAllText(_path));
    }

    [Fact]
    public void UnaCitaMultipleActualizaCadaTramoSinPerderElSeparador()
    {
        string original =
            "clave,texto es,sitio Mac,sitio Windows,estado\n" +
            "buscar-actualizaciones,Buscar actualizaciones,studio/Mac/View.swift:1," +
            "\"studio/windows/AuraStudio.App/Views/SettingsPage.xaml:100 (settings-page.buscar-actualizaciones); " +
            "studio/windows/AuraStudio.App/Views/DeviceListPage.xaml:135 (device-list-page.buscar-actualizaciones)\"," +
            "clave distinta\n";
        File.WriteAllText(_path, original);

        var sites = new Dictionary<string, Site>(StringComparer.Ordinal)
        {
            ["settings-page.buscar-actualizaciones"] = new Site(
                "settings-page.buscar-actualizaciones", "studio/windows/AuraStudio.App/Views/SettingsPage.xaml", 275,
                "XAML", "Buscar actualizaciones", "Buscar actualizaciones", false),
            ["device-list-page.buscar-actualizaciones"] = new Site(
                "device-list-page.buscar-actualizaciones", "studio/windows/AuraStudio.App/Views/DeviceListPage.xaml", 135,
                "XAML", "Buscar actualizaciones", "Buscar actualizaciones", false),
        };

        (int updated, List<string> missing) = ClavesCompartidasCsv.UpdateSitioWindows(_path, sites);

        Assert.Equal(1, updated);
        string[] lines = File.ReadAllLines(_path);
        Assert.Contains("SettingsPage.xaml:275 (settings-page.buscar-actualizaciones); " +
                         "studio/windows/AuraStudio.App/Views/DeviceListPage.xaml:135 (device-list-page.buscar-actualizaciones)",
            lines[1]);
    }

    [Fact]
    public void UnaClaveCitadaQueYaNoExisteSeDejaIntactaYSeReporta()
    {
        string original =
            "clave,texto es,sitio Mac,sitio Windows,estado\n" +
            "algo,Texto,—,studio/windows/AuraStudio.App/Resources/AppStrings.cs:100 (app-strings.ya-no-existe),solo Windows\n";
        File.WriteAllText(_path, original);

        (int updated, List<string> missing) = ClavesCompartidasCsv.UpdateSitioWindows(
            _path, new Dictionary<string, Site>(StringComparer.Ordinal));

        Assert.Equal(0, updated);
        Assert.Equal(["app-strings.ya-no-existe"], missing);
        Assert.Equal(original, File.ReadAllText(_path));
    }
}
