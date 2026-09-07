using System.Text.RegularExpressions;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// ST-245 (addendum, "espejo de A5"): prueba, sobre el código fuente real de
/// <c>AuraStudio.App</c> (no un mock), que TODO punto de entrada de
/// "Eliminar" pasa por <c>DeleteConfirmation.ConfirmAndRemoveAsync</c> — el
/// único lugar que muestra confirmación antes de llamar
/// <c>LibraryViewModel.Remove</c> (que puede mandar archivos a la Papelera
/// en modo copia desde B5, sin aviso si nadie confirma antes).
///
/// <para>Es un "source-grep", no una prueba de integración con un
/// <c>LibraryViewModel</c> real: lee el texto de <c>Views/</c> y
/// <c>ViewModels/</c> y busca la forma sintáctica de la llamada
/// (<c>library.Remove(</c>/<c>_library.Remove(</c>). Elegido así porque
/// tocar <c>Views/</c> o <c>LibraryViewModel</c> está fuera de alcance de
/// esta sesión — el Experto los tiene en B7a ahora mismo (instrucción
/// explícita del coordinador) — así que un arnés que instanciara un
/// <c>LibraryViewModel</c> real (estilo <c>StorageFixtureCheck</c>) no se
/// podía escribir sin ese riesgo de choque. Cubre los cuatro puntos del
/// encargo: cuadrícula (<c>MediaGridPage.xaml.cs:1007</c>), canciones
/// (<c>SongsPage.xaml.cs:502</c>), artistas (<c>ArtistsPage.xaml.cs:314</c>
/// y <c>:443</c>, menú contextual y selección) — los cuatro llaman
/// <c>DeleteConfirmation.ConfirmAndRemoveAsync</c>. La tecla Supr no
/// aparece en ningún <c>Page_KeyDown</c> de <c>SongsPage</c>/
/// <c>MediaGridPage</c>/<c>ArtistsPage</c> (revisados los tres completos):
/// no es un punto que se salte la confirmación, es una función que todavía
/// no existe.</para>
/// </summary>
public class DeleteEntryPointsTests
{
    private static string RepoRoot()
    {
        DirectoryInfo? dir = new(AppContext.BaseDirectory);
        while (dir is not null)
        {
            if (File.Exists(Path.Combine(dir.FullName, "studio", "windows", "AuraStudio.Windows.slnx")))
                return dir.FullName;

            dir = dir.Parent;
        }

        throw new InvalidOperationException("No se encontró la raíz del repo desde el directorio de pruebas.");
    }

    private static readonly Regex LibraryRemoveCall = new(
        @"\b(?:_library|library|Library)\.Remove\(", RegexOptions.Compiled);

    /// <summary>
    /// Bypasses conocidos: sitios que eliminan sin pasar por
    /// <c>DeleteConfirmation</c> y que están documentados en vez de
    /// silenciados. <b>Hoy está vacía, y esa es la idea.</b>
    ///
    /// <para>Tuvo uno: <c>SimilarItemsViewModel.KeepOnly</c> llamaba
    /// <c>_library.Remove</c> directo, sin confirmación en ninguna capa, y el
    /// aviso posterior decía que el archivo "sigue en tu computadora" —cierto
    /// en modo referencia y falso en modo copia, donde ya se había ido a la
    /// Papelera—. Se arregló enrutando <c>KeepOnly_Click</c> por
    /// <c>DeleteConfirmation</c> como las otras tres pantallas (ST-245,
    /// addendum), y la línea salió de esta lista.</para>
    ///
    /// <para>Que quede vacía no la hace inútil: un bypass NUEVO hace fallar la
    /// prueba de abajo, y
    /// <see cref="LosHallazgosConocidosSiguenExistiendoEnLaLineaCitada"/> hace
    /// fallar cualquier renglón que sobre — o sea que tampoco se puede tapar un
    /// hallazgo agregándolo acá y olvidándolo.</para>
    /// </summary>
    private static readonly HashSet<(string File, int Line)> KnownUnconfirmedBypasses = new()
    {
    };

    [Fact]
    public void TodoEliminarPasaPorDeleteConfirmationSalvoHallazgosConocidos()
    {
        string appDir = Path.Combine(RepoRoot(), "studio", "windows", "AuraStudio.App");
        string[] files = [.. Directory.EnumerateFiles(appDir, "*.cs", SearchOption.AllDirectories)
            .Where(path => path.Contains($"{Path.DirectorySeparatorChar}Views{Path.DirectorySeparatorChar}")
                        || path.Contains($"{Path.DirectorySeparatorChar}ViewModels{Path.DirectorySeparatorChar}"))
            .OrderBy(path => path, StringComparer.Ordinal)];

        Assert.True(files.Length > 0, "no se encontraron archivos de Views/ViewModels -- ¿cambió la estructura del repo?");

        string appRoot = Path.Combine(RepoRoot(), "studio", "windows");
        var sinDocumentar = new List<string>();

        foreach (string file in files)
        {
            string relative = Path.GetRelativePath(appRoot, file).Replace('\\', '/');
            string[] lines = File.ReadAllLines(file);

            for (int i = 0; i < lines.Length; i++)
            {
                if (!LibraryRemoveCall.IsMatch(lines[i])) continue;

                int lineNumber = i + 1;
                bool esElUnicoPuntoSancionado = relative == "AuraStudio.App/Views/DeleteConfirmation.cs";
                bool esHallazgoConocido = KnownUnconfirmedBypasses.Contains((relative, lineNumber));

                if (!esElUnicoPuntoSancionado && !esHallazgoConocido)
                    sinDocumentar.Add($"{relative}:{lineNumber}");
            }
        }

        Assert.True(sinDocumentar.Count == 0,
            "llamada a library.Remove(...) fuera de DeleteConfirmation y sin documentar como hallazgo conocido " +
            "(¿un bypass nuevo, o uno viejo que hay que agregar a KnownUnconfirmedBypasses?): " +
            string.Join(", ", sinDocumentar));
    }

    /// <summary>
    /// Y del otro lado: cada pantalla que ofrece eliminar <b>llama</b> a
    /// <see cref="DeleteConfirmation"/>.
    ///
    /// <para>Las dos pruebas de arriba comprueban que nadie elimine <i>por
    /// fuera</i> del diálogo, que es una afirmación negativa: se cumple sola si
    /// alguien borra la funcionalidad, o si una pantalla deja de eliminar por
    /// un camino que este archivo no reconoce. Ésta es la afirmación positiva,
    /// y es la que se habría puesto roja el día que Similares se saltó la
    /// confirmación (ST-245, addendum): entonces esa pantalla ofrecía
    /// "Conservar solo este" y no llamaba al diálogo desde ningún lado.</para>
    ///
    /// <para>La lista es explícita. Una pantalla nueva con un botón de eliminar
    /// no aparece acá sola, y ese renglón que falta es la conversación que hay
    /// que tener antes de que salga.</para>
    /// </summary>
    [Theory]
    [InlineData("AuraStudio.App/Views/SongsPage.xaml.cs")]
    [InlineData("AuraStudio.App/Views/ArtistsPage.xaml.cs")]
    [InlineData("AuraStudio.App/Views/MediaGridPage.xaml.cs")]
    [InlineData("AuraStudio.App/Views/SimilarItemsPage.xaml.cs")]
    public void CadaPantallaQueEliminaLlamaAlDialogoDeConfirmacion(string screen)
    {
        string fullPath = Path.Combine(
            RepoRoot(), "studio", "windows", screen.Replace('/', Path.DirectorySeparatorChar));

        Assert.True(File.Exists(fullPath), $"{screen} no existe -- ¿se movió la pantalla?");

        Assert.Contains(
            "DeleteConfirmation.ConfirmAndRemoveAsync",
            File.ReadAllText(fullPath),
            StringComparison.Ordinal);
    }

    /// <summary>
    /// Cinturón además del tirante: confirma que los hallazgos conocidos
    /// SIGUEN existiendo en el archivo/línea exactos citados arriba -- si
    /// alguien mueve o arregla <c>SimilarItemsViewModel.KeepOnly</c>, esta
    /// prueba obliga a venir a borrar la excepción en vez de dejarla viva y
    /// sin sentido (una excepción que ya no aplica es tan mala como un
    /// bypass sin documentar: los dos esconden el estado real).
    /// </summary>
    [Fact]
    public void LosHallazgosConocidosSiguenExistiendoEnLaLineaCitada()
    {
        string appRoot = Path.Combine(RepoRoot(), "studio", "windows");

        foreach ((string file, int line) in KnownUnconfirmedBypasses)
        {
            string fullPath = Path.Combine(appRoot, file.Replace('/', Path.DirectorySeparatorChar));
            Assert.True(File.Exists(fullPath), $"{file} ya no existe -- actualizar KnownUnconfirmedBypasses");

            string[] lines = File.ReadAllLines(fullPath);
            Assert.True(line - 1 < lines.Length, $"{file}:{line} está fuera de rango -- el archivo cambió, revisar la excepción");
            Assert.True(LibraryRemoveCall.IsMatch(lines[line - 1]),
                $"{file}:{line} ya no tiene la llamada a Remove esperada -- ¿se arregló? borrar esta excepción");
        }
    }
}
