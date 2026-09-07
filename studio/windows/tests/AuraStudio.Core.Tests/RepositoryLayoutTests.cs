using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// La raíz de <c>studio/windows/</c> tiene lo que tiene que tener y nada más.
///
/// <para><b>Por qué existe esta prueba.</b> En B7a (ST-247) aparecieron siete
/// archivos con nombres absurdos en la raíz —trozos de frases en español, con
/// líneas de código adentro—: un bucle de clasificación pasaba texto sin
/// comillas como <i>guion</i> de <c>sed</c>, y cuando ese texto traía una
/// <c>w</c>, <c>sed</c> la leyó como su comando de escribir y guardó el resto
/// de la frase como nombre de archivo. Entraron al commit sin que nadie los
/// viera: <c>git add</c> sobre un directorio no distingue lo que uno escribió
/// de lo que una herramienta dejó tirado.</para>
///
/// <para>El defecto real fue pasar texto sin comillas a un comando que lo
/// interpreta —eso se arregla escribiendo mejor—, pero la lección que sobrevive
/// es la otra: <b>ningún par de ojos revisó la lista de archivos del commit</b>,
/// y con setenta archivos cambiados nadie la va a revisar la próxima vez
/// tampoco. Así que la revisa esto.</para>
///
/// <para>La lista es <b>explícita</b> a propósito. Un patrón —"nada con
/// espacios", "nada sin extensión"— habría dejado pasar seis de los siete y
/// habría dado la sensación de estar cubierto. Agregar algo legítimo a la raíz
/// es un renglón acá, y ese renglón es justamente la revisión que faltó.</para>
/// </summary>
public class RepositoryLayoutTests
{
    /// <summary>
    /// Lo que vive legítimamente en la raíz de <c>studio/windows/</c>. Carpetas
    /// y archivos por separado: una carpeta nueva es una decisión de estructura
    /// y un archivo suelto casi nunca lo es.
    /// </summary>
    private static readonly string[] AllowedFiles =
    [
        ".gitignore",
        "AuraStudio.Windows.slnx",
    ];

    private static readonly string[] AllowedDirectories =
    [
        "AuraStudio.App",
        "AuraStudio.Core",
        "artifacts",
        "docs",
        "icono",
        "installer",
        "scripts",
        "tests",
        "tools",
    ];

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

    [Fact]
    public void LaRaizDeStudioWindowsNoTieneArchivosSueltos()
    {
        List<string> unexpected =
        [
            .. Directory.EnumerateFiles(WindowsRoot())
                .Select(Path.GetFileName)
                .OfType<string>()

                // .DS_Store lo deja macOS al mirar la carpeta desde el Finder —
                // el repo se comparte por red con una Mac. Está en .gitignore y
                // no llega a ningún commit.
                .Where(name => name != ".DS_Store")
                .Where(name => !AllowedFiles.Contains(name, StringComparer.Ordinal))
                .Order(StringComparer.Ordinal)
        ];

        Assert.True(unexpected.Count == 0,
            "Hay archivos sueltos en la raíz de studio/windows/ que nadie declaró.\n"
            + "Si alguno es legítimo, agrégalo a AllowedFiles; si no, bórralo —"
            + " y mira si lo dejó ahí una herramienta:\n" + string.Join("\n", unexpected));
    }

    [Fact]
    public void LaRaizDeStudioWindowsNoTieneCarpetasNuevasSinDeclarar()
    {
        List<string> unexpected =
        [
            .. Directory.EnumerateDirectories(WindowsRoot())
                .Select(Path.GetFileName)
                .OfType<string>()
                .Where(name => !AllowedDirectories.Contains(name, StringComparer.Ordinal))
                .Order(StringComparer.Ordinal)
        ];

        Assert.True(unexpected.Count == 0,
            "Hay carpetas en la raíz de studio/windows/ que nadie declaró:\n"
            + string.Join("\n", unexpected));
    }

    /// <summary>
    /// Y lo declarado sigue estando: una lista que envejece sin que nadie la
    /// mire deja de proteger nada.
    /// </summary>
    [Fact]
    public void LoDeclaradoSigueExistiendo()
    {
        string root = WindowsRoot();

        List<string> missing =
        [
            .. AllowedFiles.Where(name => !File.Exists(Path.Combine(root, name))),
            .. AllowedDirectories.Where(name => !Directory.Exists(Path.Combine(root, name))),
        ];

        Assert.True(missing.Count == 0,
            "Esto está declarado como parte de la raíz y ya no existe — o se movió, "
            + "y entonces sobra el renglón:\n" + string.Join("\n", missing));
    }
}
