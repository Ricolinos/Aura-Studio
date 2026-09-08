using System.Text.RegularExpressions;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// Que no quede texto de la app escrito en el código (ST-247).
///
/// <para><b>Por qué hace falta una prueba y no basta la disciplina.</b> Un
/// texto en español dentro de un archivo <c>.cs</c> o <c>.xaml</c> compila
/// igual de bien que uno que sale del recurso. No hay error, no hay aviso: la
/// app en alemán simplemente muestra una frase en español, y eso se descubre
/// cuando alguien la ve. Esta prueba lo descubre antes.</para>
///
/// <para><b>Qué mira y qué no.</b> Mira los sitios que B7a se llevó: los
/// atributos de texto del XAML —incluidos los que el extractor no cubría:
/// <c>AutomationProperties.Name</c>, <c>ToolTipService.ToolTip</c>,
/// <c>PlaceholderText</c>, <c>Header</c>— y la fachada
/// <c>AppStrings</c>. Ahí exige <b>cero</b>.</para>
///
/// <para>Fuera de eso queda una parte del programa que B7a no alcanzó: los
/// mensajes de excepción, los de registro y los errores que se arman en
/// servicios y en la capa de plataforma. Son doscientos cincuenta, el extractor no
/// los tomó y meterlos en B7a sería duplicar el bloque sin nada contra qué
/// comparar el texto. Para que eso no se convierta en una puerta abierta, lo
/// que se comprueba ahí es que <b>no crezca</b>: hay un número, y subirlo es
/// un acto deliberado que alguien tiene que escribir.</para>
///
/// <para>La señal de "esto es español" es léxica y no los acentos: palabras
/// que existen en español y no en inglés ni en un identificador. No pretende
/// ser perfecta —no puede serlo—; pretende no dejar pasar una frase de
/// pantalla, que es lo que importa.</para>
/// </summary>
public class HardcodedSpanishTests
{
    private static readonly Regex Spanish = new(
        @"\b(?:el|la|los|las|un|una|unos|unas|del|que|se|no|con|por|para|tu|tus|su|sus|" +
        @"al|es|son|está|están|hay|ya|más|como|pero|esta|este|esto|estos|estas|" +
        @"todo|toda|todos|todas|cuando|donde|porque|desde|hasta|entre|sobre|sin|" +
        @"archivo|archivos|canción|canciones|álbum|álbumes|foto|fotos|carátula|carátulas|" +
        @"biblioteca|disco|elemento|elementos|nada|puedes|vas|van|tiene|tienen)\b",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    /// <summary>
    /// Los atributos del XAML que llevan texto que alguien lee o escucha. Los
    /// cuatro últimos son los que el extractor no cubría y por los que se
    /// quedaron nueve frases sin mover hasta que esta prueba los miró.
    /// </summary>
    private static readonly Regex XamlText = new(
        @"\b(?:Text|Content|Header|Description|Title|Message|" +
        @"PrimaryButtonText|SecondaryButtonText|CloseButtonText|" +
        @"PlaceholderText|ToolTipService\.ToolTip|AutomationProperties\.Name)" +
        @"\s*=\s*""([^""{}]+)""",
        RegexOptions.Compiled);

    private static readonly Regex CsLiteral = new(@"(?<!\$)""((?:[^""\\]|\\.)*)""", RegexOptions.Compiled);

    /// <summary>
    /// Una clave de recurso no es texto de pantalla, aunque tenga palabras del
    /// español adentro: <c>conteo.canciones</c> y <c>app-strings.no-device</c>
    /// se ven como español y son justamente lo contrario — la prueba de que ese
    /// texto ya se movió.
    /// </summary>
    private static readonly Regex ResourceKey = new(@"^[a-z0-9]+[a-z0-9.\-]*$", RegexOptions.Compiled);

    /// <summary>
    /// Cuánto texto en español queda fuera del alcance de B7a. Es un tope, no
    /// una meta: baja cuando alguien mueva alguno, y subirlo hay que escribirlo
    /// a mano y explicar por qué.
    /// </summary>
    private const int OutsideB7aCeiling = 250;

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

    private static IEnumerable<string> SourceFiles(string extension) =>
        new[] { "AuraStudio.App", "AuraStudio.Core" }
            .Select(project => Path.Combine(WindowsRoot(), project))
            .Where(Directory.Exists)
            .SelectMany(root => Directory.EnumerateFiles(root, extension, SearchOption.AllDirectories))
            .Where(path => !path.Contains($"{Path.DirectorySeparatorChar}bin{Path.DirectorySeparatorChar}")
                           && !path.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}"));

    private static IEnumerable<(string File, int Line, string Text)> Hits(
        string extension, Regex pattern, Func<string, bool> skipLine)
    {
        foreach (string path in SourceFiles(extension))
        {
            string[] lines = File.ReadAllLines(path);

            for (int index = 0; index < lines.Length; index++)
            {
                if (skipLine(lines[index])) continue;

                foreach (Match match in pattern.Matches(lines[index]))
                {
                    string text = match.Groups[1].Value;
                    if (text.Length <= 3) continue;
                    if (ResourceKey.IsMatch(text)) continue;
                    if (!Spanish.IsMatch(text)) continue;

                    yield return (Path.GetRelativePath(WindowsRoot(), path), index + 1, text);
                }
            }
        }
    }

    private static bool IsComment(string line) => line.TrimStart().StartsWith("//", StringComparison.Ordinal);

    /// <summary>
    /// Archivos cuyo español no es texto de pantalla.
    ///
    /// <para>Uno solo, y es una tabla de documentación: <c>CriticalStrings</c>
    /// guarda, al lado de cada familia de claves, la razón por la que es
    /// crítica —"formatea el iPod y graba su arranque"—. Eso lo lee quien
    /// mantiene la lista, nunca un usuario. Contarlo como texto sin traducir
    /// haría subir el trinquete por escribir documentación, que es al revés de
    /// lo que se quiere premiar.</para>
    /// </summary>
    private static readonly string[] NotUserFacingFiles =
    [
        "CriticalStrings.cs",
    ];

    /// <summary>
    /// Cero frases en español en las vistas. Es donde vive el texto que el
    /// usuario lee, y donde una que se escape se ve en la primera pantalla que
    /// se abra en otro idioma.
    /// </summary>
    [Fact]
    public void NoQuedaTextoEnEspanolEnLasVistas()
    {
        List<string> found =
        [
            .. Hits("*.xaml", XamlText, line => line.TrimStart().StartsWith("<!--", StringComparison.Ordinal))
                .Select(hit => $"{hit.File}:{hit.Line}  {hit.Text}")
        ];

        Assert.True(found.Count == 0,
            "Estos textos siguen escritos en el XAML en vez de salir del recurso:\n" + string.Join("\n", found));
    }

    /// <summary>
    /// Y cero en la fachada: <c>AppStrings</c> es de donde salen los textos,
    /// así que un literal ahí es un texto que nunca va a llegar a traducirse.
    /// </summary>
    [Fact]
    public void NoQuedaTextoEnEspanolEnLaFachada()
    {
        string facade = Path.Combine(WindowsRoot(), "AuraStudio.App", "Resources", "AppStrings.cs");

        List<string> found = [];
        string[] lines = File.ReadAllLines(facade);

        for (int index = 0; index < lines.Length; index++)
        {
            if (IsComment(lines[index])) continue;

            foreach (Match match in CsLiteral.Matches(lines[index]))
            {
                string text = match.Groups[1].Value;
                if (text.Length <= 3) continue;
                if (ResourceKey.IsMatch(text)) continue;
                if (!Spanish.IsMatch(text)) continue;

                found.Add($"AppStrings.cs:{index + 1}  {text}");
            }
        }

        Assert.True(found.Count == 0,
            "Estos textos siguen escritos en AppStrings en vez de salir del recurso:\n"
            + string.Join("\n", found));
    }

    /// <summary>
    /// Lo que B7a no alcanzó —excepciones, registro, errores de plataforma— no
    /// crece. No es una meta cumplida: es una puerta cerrada mientras se decide
    /// qué hacer con ello.
    /// </summary>
    [Fact]
    public void ElTextoFueraDeAlcanceNoCrece()
    {
        int outside = OutOfScope().Count();

        Assert.True(outside <= OutsideB7aCeiling,
            $"Hay {outside} textos en español fuera del alcance de B7a y el tope es {OutsideB7aCeiling}. "
            + "Si agregaste uno, sácalo al recurso; si de verdad hay que subir el tope, "
            + "súbelo a mano y di por qué. Están acá, por archivo:\n" + Inventory());
    }

    /// <summary>
    /// Dónde están los que quedan, agrupados por archivo. Es la lista de
    /// trabajo de B7c.
    ///
    /// <para>Sale en el mensaje del fallo y no en un archivo aparte a
    /// propósito: un inventario que hay que regenerar a mano envejece en
    /// silencio, y este se calcula solo, justo cuando alguien lo necesita.</para>
    ///
    /// <para>Lo que <b>no</b> hace es decidir cuáles se traducen. Ese corte —lo
    /// que ve el usuario sí; el registro y las excepciones internas no— hay que
    /// hacerlo mirando cada uno, y una expresión regular que lo adivinara
    /// entregaría una lista con aire de autoridad y errores adentro.</para>
    /// </summary>
    private static IEnumerable<(string File, int Line, string Text)> OutOfScope() =>
        Hits("*.cs", CsLiteral, IsComment)
            .Where(hit => !hit.File.EndsWith("AppStrings.cs", StringComparison.Ordinal))
            .Where(hit => !NotUserFacingFiles.Any(name => hit.File.EndsWith(name, StringComparison.Ordinal)));

    private static string Inventory() =>
        string.Join("\n", OutOfScope()
            .GroupBy(hit => hit.File)
            .OrderByDescending(group => group.Count())
            .ThenBy(group => group.Key, StringComparer.Ordinal)
            .Select(group => $"{group.Count(),4}  {group.Key}"));
}
