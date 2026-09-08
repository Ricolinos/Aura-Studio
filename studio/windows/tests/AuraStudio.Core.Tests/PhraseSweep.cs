using System.Text.RegularExpressions;

namespace AuraStudio.Core.Tests;

/// <summary>Un literal con pinta de frase, y dónde está hoy.</summary>
public readonly record struct SweptPhrase(string File, int Line, string Text);

/// <summary>
/// La segunda barrida, en C# (ST-247, B7d).
///
/// <para><b>Por qué existe dos veces.</b> El original es
/// <c>docs/extraccion-cadenas/barrida-frases.pl</c> y se sigue corriendo a mano:
/// imprime archivo y renglón, que es lo que sirve para leer. Pero el trinquete
/// no puede depender de que haya <c>perl</c> en la máquina — la prueba que corría
/// el guion se saltaba sola cuando no lo había, y un trinquete que se salta solo
/// es indistinguible de uno que no encuentra nada.</para>
///
/// <para>Así que la detección vive acá, y <see cref="PhraseSweepRatchetTests"/>
/// comprueba que las dos implementaciones ven exactamente lo mismo cuando sí hay
/// perl. Dos copias de una regla se separan; lo que impide que se separen no es
/// la buena intención, es esa tercera prueba.</para>
/// </summary>
public static class PhraseSweep
{
    private static readonly string[] Roots = ["AuraStudio.App", "AuraStudio.Core"];

    private static readonly Regex Literal = new(@"""((?:[^""\\]|\\.)*)""", RegexOptions.Compiled);
    private static readonly Regex Comment = new(@"^\s*//", RegexOptions.Compiled);
    private static readonly Regex AlreadyResource = new(@"Strings\.(Get|Format|Plural)\(""", RegexOptions.Compiled);
    private static readonly Regex Escape = new(@"\\[nrt0""'\\]", RegexOptions.Compiled);

    private static readonly Regex ResourceKey = new(@"^[a-z0-9.\-]+$", RegexOptions.Compiled);
    private static readonly Regex PathLike = new(@"[\\/]", RegexOptions.Compiled);
    private static readonly Regex Blank = new(@"^\s*$", RegexOptions.Compiled);
    private static readonly Regex ProperNoun = new(@"^[A-Z][A-Za-z]+ [A-Z][A-Za-z]+$", RegexOptions.Compiled);
    private static readonly Regex Accented = new(@"[áéíóúñ]", RegexOptions.Compiled);
    private static readonly Regex TwoRealWords =
        new(@"[a-záéíóúñ]{3,}\s+[a-záéíóúñ]{2,}", RegexOptions.Compiled | RegexOptions.IgnoreCase);

    /// <summary>Todo lo que la barrida señala, en el árbol que cuelga de <paramref name="windowsRoot"/>.</summary>
    public static IReadOnlyList<SweptPhrase> Run(string windowsRoot)
    {
        List<SweptPhrase> found = [];

        foreach (string root in Roots)
        {
            string directory = Path.Combine(windowsRoot, root);
            if (!Directory.Exists(directory)) continue;

            foreach (string path in Directory.EnumerateFiles(directory, "*.cs", SearchOption.AllDirectories).Order(StringComparer.Ordinal))
            {
                if (Skipped(windowsRoot, path)) continue;

                string relative = Path.GetRelativePath(windowsRoot, path).Replace('\\', '/');

                int number = 0;
                foreach (string line in File.ReadLines(path))
                {
                    number++;
                    if (Comment.IsMatch(line) || AlreadyResource.IsMatch(line)) continue;

                    foreach (Match match in Literal.Matches(line))
                    {
                        string value = match.Groups[1].Value;
                        if (IsPhrase(value)) found.Add(new SweptPhrase(relative, number, value));
                    }
                }
            }
        }

        return found;
    }

    /// <summary>
    /// Lo compilado y lo oculto no cuenta. Se compara segmento por segmento y no
    /// con <c>Contains("bin")</c>: una carpeta llamada "binarios" —o un usuario
    /// llamado "obj"— no tiene por qué desaparecer del barrido.
    /// </summary>
    private static bool Skipped(string windowsRoot, string path) =>
        Path.GetRelativePath(windowsRoot, path)
            .Split(['/', '\\'])
            .Any(segment => segment is "bin" or "obj" || segment.StartsWith('.'));

    /// <summary>
    /// El mismo criterio que el guion, en el mismo orden: dos o más palabras que
    /// no parezcan ruta, identificador ni clave.
    /// </summary>
    private static bool IsPhrase(string value)
    {
        // Las secuencias de escape se quitan ANTES de mirar si parece una ruta:
        // un "\n" es una barra invertida y descartaría toda frase de varios
        // renglones. Es el agujero por el que se coló el aviso de "algo salió
        // mal", que estaba en pantalla y en español.
        string bare = Escape.Replace(value, "");

        if (!bare.Any(char.IsWhiteSpace)) return false;
        if (ResourceKey.IsMatch(bare)) return false;
        if (PathLike.IsMatch(bare)) return false;
        if (Blank.IsMatch(bare)) return false;
        if (ProperNoun.IsMatch(bare) && !Accented.IsMatch(bare)) return false;

        return TwoRealWords.IsMatch(bare);
    }
}
