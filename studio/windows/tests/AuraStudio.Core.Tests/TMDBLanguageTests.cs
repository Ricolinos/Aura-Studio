using System.Globalization;
using System.Net;
using AuraStudio.Core.Networking;
using AuraStudio.Core.Resources;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// TMDB devuelve el título y la sinopsis en el idioma que se le pida, y hay que
/// pedirle el de la interfaz (ST-247, B7c).
///
/// <para><b>Lo que estaba mal.</b> El idioma estaba fijo en <c>"es-MX"</c>. Con
/// la app en un solo idioma era correcto; con seis, la app en japonés le
/// mostraba al usuario títulos y sinopsis en español, recién traídos de la red.
/// No hay forma de que una prueba de extracción de cadenas lo vea: no es una
/// cadena de interfaz, es un parámetro de una consulta. Se encontró leyendo el
/// triaje de lo que B7a había dejado fuera, entre cosas que sí eran texto.</para>
///
/// <para>Vale la pena la prueba porque el error no se ve desde el código —dice
/// "es-MX" y eso parece una decisión— sino desde la pantalla de alguien que
/// puso la app en otro idioma.</para>
/// </summary>
public class TMDBLanguageTests
{
    private const string MovieJson =
        """{"results":[{"id":603,"title":"The Matrix","release_date":"1999-03-30","poster_path":"/m.jpg"}]}""";

    /// <summary>Sin clave el cliente no toca la red y no habría consulta que mirar.</summary>
    private sealed class KeyStore(string? key) : IApiKeyStore
    {
        public string? Load(string service) => key;
    }

    /// <summary>
    /// Corre algo con la interfaz en una cultura y la deja como estaba. Sin el
    /// finally, una prueba que fallara dejaría a las siguientes corriendo en
    /// japonés y el desastre se vería en cualquier lado menos acá.
    /// </summary>
    private static async Task<List<string>> RequestsWithUiCulture(string culture, string? language = null)
    {
        CultureInfo previous = CultureInfo.CurrentUICulture;
        CultureInfo.CurrentUICulture = new CultureInfo(culture);

        try
        {
            var handler = new ImageStubHandler(_ => (HttpStatusCode.OK, MovieJson), [1, 2, 3]);
            var client = new TMDBClient(new HttpClient(handler), new KeyStore("clave"), language: language);

            await client.SearchMovieAsync("The Matrix", "1999");
            return handler.Requests;
        }
        finally
        {
            CultureInfo.CurrentUICulture = previous;
        }
    }

    [Theory]
    [InlineData("ja")]
    [InlineData("de")]
    [InlineData("fr")]
    [InlineData("ru")]
    [InlineData("en")]
    [InlineData("es")]
    public async Task LePideLosDatosEnElIdiomaDeLaInterfaz(string culture)
    {
        List<string> requests = await RequestsWithUiCulture(culture);

        Assert.Contains(requests, url => url.Contains($"language={culture}", StringComparison.Ordinal));
    }

    /// <summary>
    /// Una cultura regional viaja entera: TMDB tiene traducciones distintas para
    /// <c>es-MX</c> y <c>es-ES</c>, y quedarse con "es" las perdería.
    /// </summary>
    [Fact]
    public async Task UnaCulturaConRegionViajaConSuRegion()
    {
        List<string> requests = await RequestsWithUiCulture("es-MX");

        Assert.Contains(requests, url => url.Contains("language=es-MX", StringComparison.Ordinal));
    }

    /// <summary>
    /// La cultura invariante no tiene nombre; ahí la interfaz se ve en español,
    /// que es la cultura neutra, y eso es lo que se pide. Sin este caso el
    /// parámetro viajaría vacío (<c>&amp;language=</c>) y TMDB decidiría por su
    /// cuenta.
    /// </summary>
    [Fact]
    public async Task SinCulturaSePideLaNeutra()
    {
        List<string> requests = await RequestsWithUiCulture("");

        Assert.Contains(requests,
            url => url.Contains($"language={AppLanguages.NeutralCulture}", StringComparison.Ordinal));
    }

    /// <summary>
    /// Quien construye el cliente puede fijar el idioma —lo hacen las pruebas—
    /// y eso gana sobre la cultura de la interfaz.
    /// </summary>
    [Fact]
    public async Task ElIdiomaExplicitoGanaSobreLaInterfaz()
    {
        List<string> requests = await RequestsWithUiCulture("ja", language: "fr-CA");

        Assert.Contains(requests, url => url.Contains("language=fr-CA", StringComparison.Ordinal));
        Assert.DoesNotContain(requests, url => url.Contains("language=ja", StringComparison.Ordinal));
    }
}
