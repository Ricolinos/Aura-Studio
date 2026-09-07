using System.Globalization;
using System.Text.RegularExpressions;
using AuraStudio.Core;
using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// La categoría de un video es <b>dato</b>, no texto de interfaz (ST-247,
/// lección de A7a en la Mac; D-228, D-283).
///
/// <para><b>Qué salió mal allá.</b> La app de macOS guardaba en
/// <c>item.Category</c> el nombre en el idioma activo. Con un solo idioma no se
/// nota. Con seis, el mismo video queda como "Series" en una máquina y
/// "Serien" en otra; el catálogo que viaja entre las dos deja de coincidir
/// consigo mismo, la agrupación parte una categoría en dos y el firmware arma
/// los índices con lo que le llegue. Es de los defectos que no se ven hasta que
/// hay dos máquinas y para entonces el dato ya está escrito.</para>
///
/// <para>La regla, entonces: se guarda y se compara el <b>español</b>; lo que
/// se muestra sale del recurso y no vuelve nunca al catálogo.</para>
///
/// <para><b>Cómo se comprueba sin tener los otros idiomas todavía.</b> Los
/// satélites llegan en B7b, así que hoy pedir el texto en inglés devuelve el
/// español y una prueba que solo mirara el valor no probaría nada — pasaría
/// igual con el código mal escrito. Por eso son dos: una mira el valor con la
/// cultura cambiada, y la otra mira el <b>código</b>, que es donde el defecto
/// se puede ver antes de que exista el idioma que lo revela.</para>
/// </summary>
public class MediaCategoryDataTests
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

    /// <summary>Corre algo con otra cultura de interfaz y deja todo como estaba.</summary>
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

    [Theory]
    [InlineData("en-US")]
    [InlineData("de-DE")]
    [InlineData("ja-JP")]
    public void ElDatoQueSeGuardaEsElEspanolConCualquierIdioma(string culture)
    {
        Assert.Equal("Series", WithUiCulture(culture, () => MediaCategory.Series.CatalogName()));
        Assert.Equal("Películas", WithUiCulture(culture, () => MediaCategory.Movies.CatalogName()));
        Assert.Equal("Videos", WithUiCulture(culture, () => MediaCategory.Videos.CatalogName()));

        Assert.Equal(
            ["Videos", "Series", "Películas"],
            WithUiCulture(culture, () => MediaCategoryNames.VideoCategories));
    }

    [Theory]
    [InlineData("en-US")]
    [InlineData("de-DE")]
    public void LaComparacionSigueReconociendoElDatoConCualquierIdioma(string culture) =>
        WithUiCulture(culture, () =>
        {
            Assert.True(MediaCategoryNames.IsSeriesCategory("Series"));
            Assert.True(MediaCategoryNames.IsMoviesCategory("Películas"));

            // Un catálogo que escribió la app de macOS cuando guardaba en
            // inglés: se reconoce al leer, no se escribe.
            Assert.True(MediaCategoryNames.IsMoviesCategory("Movies"));

            return true;
        });

    /// <summary>
    /// El nombre que el usuario le puso a su colección de fotos no se traduce:
    /// es un dato suyo, no texto de la app (D-228).
    /// </summary>
    [Fact]
    public void LoQueEscribeElUsuarioVuelveTalCual()
    {
        Assert.Equal("Vacaciones 2019", MediaCategoryNames.LocalizedNameOf("Vacaciones 2019"));
        Assert.Equal("Screenshots", MediaCategoryNames.LocalizedNameOf("Screenshots"));
        Assert.Equal("", MediaCategoryNames.LocalizedNameOf(null));
    }

    /// <summary>
    /// Y un video de Series se agrupa igual con la interfaz en otro idioma: si
    /// alguien guardara la etiqueta traducida, la agrupación lo dejaría afuera.
    /// </summary>
    [Theory]
    [InlineData("en-US")]
    [InlineData("de-DE")]
    public void UnEpisodioSeAgrupaIgualConLaInterfazEnOtroIdioma(string culture) =>
        WithUiCulture(culture, () =>
        {
            string stored = MediaCategory.Series.CatalogName();

            Assert.True(MediaCategoryNames.IsSeriesCategory(stored));
            Assert.False(MediaCategoryNames.IsMoviesCategory(stored));
            Assert.Contains(stored, MediaCategoryNames.VideoCategories);

            return true;
        });

    /// <summary>
    /// Nadie guarda ni compara la etiqueta.
    ///
    /// <para>Esta es la que de verdad protege el contrato mientras no existan
    /// los otros idiomas: busca en el código un <c>Category</c> que se asigne o
    /// se compare contra <c>LocalizedName</c>. Si aparece, es el defecto de la
    /// Mac otra vez, y se ve acá años antes de que alguien abra la app en
    /// alemán.</para>
    /// </summary>
    [Fact]
    public void NingunSitioGuardaNiComparaLaEtiqueta()
    {
        Regex suspicious = new(
            @"Category\s*(?:=|==|!=)\s*[^;\r\n]*Localized(?:Name|NameOf)"
            + @"|Localized(?:Name|NameOf)\s*\([^)]*\)\s*(?:==|!=)\s*[^;\r\n]*Category",
            RegexOptions.Compiled);

        List<string> found = [];

        foreach (string project in new[] { "AuraStudio.App", "AuraStudio.Core" })
        {
            string root = Path.Combine(WindowsRoot(), project);
            if (!Directory.Exists(root)) continue;

            foreach (string path in Directory.EnumerateFiles(root, "*.cs", SearchOption.AllDirectories))
            {
                if (path.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}")) continue;
                if (path.Contains($"{Path.DirectorySeparatorChar}bin{Path.DirectorySeparatorChar}")) continue;

                string[] lines = File.ReadAllLines(path);

                for (int index = 0; index < lines.Length; index++)
                {
                    if (lines[index].TrimStart().StartsWith("//", StringComparison.Ordinal)) continue;
                    if (!suspicious.IsMatch(lines[index])) continue;

                    found.Add($"{Path.GetRelativePath(WindowsRoot(), path)}:{index + 1}  {lines[index].Trim()}");
                }
            }
        }

        Assert.True(found.Count == 0,
            "Acá se está guardando o comparando el texto traducido de una categoría en vez del dato.\n"
            + "El dato es CatalogName() y es español siempre; LocalizedName() solo se muestra:\n"
            + string.Join("\n", found));
    }

    /// <summary>
    /// La etiqueta y el dato existen por separado y las tres categorías fijas
    /// tienen su clave. Sin la clave, la etiqueta caería a la clave entre
    /// corchetes y se vería en el menú.
    /// </summary>
    [Fact]
    public void LasTresCategoriasFijasTienenSuEtiqueta()
    {
        foreach (MediaCategory category in Enum.GetValues<MediaCategory>())
        {
            string label = category.LocalizedName();

            Assert.False(label.StartsWith('⟦'), $"{category}: falta su clave de etiqueta ({label})");
            Assert.NotEqual("", label);
        }
    }
}
