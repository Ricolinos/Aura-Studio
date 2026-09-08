using System.Text.RegularExpressions;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// Todo <c>{StaticResource}</c> y <c>{ThemeResource}</c> del XAML resuelve a
/// algo (ST-247, a raíz del defecto de Ajustes).
///
/// <para><b>El defecto que la trajo.</b> <c>SettingsPage.xaml</c> usaba
/// <c>{StaticResource InvertBool}</c> en el botón de «Buscar actualizaciones» y
/// <b>nunca declaró ese recurso</b>: sus <c>Page.Resources</c> solo traían
/// <c>BoolToVisibility</c>. Abrir Ajustes lanzaba «Cannot find a resource with
/// the given key: InvertBool.» y la página quedaba a medio cargar, en los seis
/// idiomas. Entró con ST-211 y estuvo así en 0.3.0 y en los instalables 0.4.0:
/// no es una regresión de B7, es que nadie volvió a abrir Ajustes con ese botón
/// desde entonces.</para>
///
/// <para><b>Por qué el compilador no lo vio.</b> Un <c>x:Key</c> se resuelve al
/// <b>cargar</b> la página, no al compilar. El proyecto compila sin una sola
/// advertencia y la app arranca bien; el error aparece cuando alguien navega a
/// esa pantalla concreta. Doce páginas declaraban <c>InvertBool</c> en sus
/// propios <c>Page.Resources</c> y una se olvidó — es el modo de falla exacto de
/// una lista repetida trece veces.</para>
///
/// <para><b>Cómo se resuelve una clave</b>, y por eso qué mira esta prueba: el
/// XAML busca la clave en los recursos del elemento, sube por los
/// <c>ResourceDictionary</c> que ese archivo fusiona, y termina en
/// <c>Application.Resources</c> —con lo que <c>App.xaml</c> fusiona, de forma
/// transitiva—. Lo que no está en ninguno de esos lados tiene que ser una clave
/// del tema Fluent, y ésas están enumeradas abajo una por una: si alguien usa
/// una clave del tema que no está en la lista, esto se pone rojo y hay que
/// agregarla a mano. Preferible a aceptar cualquier nombre que parezca de
/// Fluent, que es como este agujero se vuelve a abrir.</para>
/// </summary>
public class XamlResourceTests
{
    /// <summary>
    /// Claves que pone WinUI/Fluent y que este proyecto usa. Escritas a mano a
    /// propósito: es la única forma de que una clave inventada no se confunda
    /// con una del tema.
    /// </summary>
    private static readonly HashSet<string> ThemeKeys = new(StringComparer.Ordinal)
    {
        // Estilos de texto y de botón del tema.
        "AccentButtonStyle", "BodyStrongTextBlockStyle", "BodyTextBlockStyle",
        "CaptionTextBlockStyle", "TitleTextBlockStyle",

        // Pinceles de relleno y de texto.
        "AccentFillColorDefaultBrush", "AccentFillColorSecondaryBrush",
        "AcrylicBackgroundFillColorDefaultBrush", "ApplicationPageBackgroundThemeBrush",
        "CardBackgroundFillColorDefaultBrush", "CardBackgroundFillColorSecondaryBrush",
        "CardStrokeColorDefaultBrush", "ControlAltFillColorSecondaryBrush",
        "DividerStrokeColorDefaultBrush", "TextFillColorSecondaryBrush",
        "TextFillColorTertiaryBrush",

        // Semáforo del sistema.
        "SystemFillColorCautionBrush", "SystemFillColorCriticalBrush",

        // Colores del sistema, para el modo de alto contraste (AuraPalette).
        "SystemColorHighlightColor", "SystemColorWindowColor", "SystemColorWindowTextColor",
    };

    private static readonly Regex KeyDeclaration = new(@"x:Key=""([^""]+)""", RegexOptions.Compiled);
    private static readonly Regex Merge = new(@"ResourceDictionary\s+Source=""ms-appx:///([^""]+)""", RegexOptions.Compiled);
    private static readonly Regex Usage =
        new(@"\{(?:Static|Theme)Resource\s+([A-Za-z0-9_.]+)\}", RegexOptions.Compiled);

    private static string AppRoot()
    {
        DirectoryInfo? directory = new(AppContext.BaseDirectory);

        while (directory is not null)
        {
            string candidate = Path.Combine(directory.FullName, "studio", "windows");
            if (File.Exists(Path.Combine(candidate, "AuraStudio.Windows.slnx")))
                return Path.Combine(candidate, "AuraStudio.App");

            directory = directory.Parent;
        }

        throw new InvalidOperationException("No se encontró la raíz del repo desde el directorio de pruebas.");
    }

    private static IEnumerable<string> XamlFiles(string appRoot) =>
        Directory.EnumerateFiles(appRoot, "*.xaml", SearchOption.AllDirectories)
            .Where(path => !Path.GetRelativePath(appRoot, path)
                .Split(['/', '\\'])
                .Any(segment => segment is "bin" or "obj"))
            .Order(StringComparer.Ordinal);

    /// <summary>
    /// Las claves que un archivo aporta: las suyas más las de todo lo que
    /// fusiona, de forma transitiva. <paramref name="seen"/> corta los ciclos —
    /// dos diccionarios que se fusionen entre sí colgarían esto.
    /// </summary>
    private static HashSet<string> KeysOf(string appRoot, string relative, HashSet<string>? seen = null)
    {
        seen ??= new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        HashSet<string> keys = new(StringComparer.Ordinal);

        string path = Path.Combine(appRoot, relative.Replace('/', Path.DirectorySeparatorChar));
        if (!File.Exists(path) || !seen.Add(relative)) return keys;

        string text = File.ReadAllText(path);

        foreach (Match match in KeyDeclaration.Matches(text)) keys.Add(match.Groups[1].Value);
        foreach (Match match in Merge.Matches(text))
            keys.UnionWith(KeysOf(appRoot, match.Groups[1].Value, seen));

        return keys;
    }

    [Fact]
    public void TodoRecursoQueElXamlPideEstaDefinidoEnAlgunLado()
    {
        string appRoot = AppRoot();

        HashSet<string> global = KeysOf(appRoot, "App.xaml");

        Assert.True(global.Count > 0,
            "App.xaml no aporta ninguna clave. Fusiona Resources/Styles.xaml; si esa cadena se "
            + "rompió, esta prueba estaría dando por bueno todo lo global sin comprobar nada.");

        List<string> problems = [];

        foreach (string path in XamlFiles(appRoot))
        {
            string relative = Path.GetRelativePath(appRoot, path).Replace('\\', '/');
            string text = File.ReadAllText(path);

            HashSet<string> available = KeysOf(appRoot, relative);
            available.UnionWith(global);
            available.UnionWith(ThemeKeys);

            foreach (string key in Usage.Matches(text)
                         .Select(match => match.Groups[1].Value)
                         .Distinct(StringComparer.Ordinal)
                         .Order(StringComparer.Ordinal))
            {
                if (available.Contains(key)) continue;

                int line = text[..text.IndexOf(key, StringComparison.Ordinal)].Count(c => c == '\n') + 1;
                problems.Add($"  {relative}:{line}  «{key}»");
            }
        }

        Assert.True(problems.Count == 0,
            $"Hay {problems.Count} recursos que el XAML pide y nadie define:\n"
            + string.Join("\n", problems)
            + "\n\nEsto NO falla al compilar: un x:Key se resuelve al cargar la página, así que la app "
            + "arranca bien y revienta cuando alguien navega a esa pantalla, con «Cannot find a resource "
            + "with the given key». Define la clave donde corresponda —lo compartido va en "
            + "Resources/Converters.xaml, que App.xaml fusiona— o, si es una clave del tema Fluent, "
            + "agrégala a ThemeKeys en esta prueba explicando de dónde sale.");
    }

    /// <summary>
    /// Ninguna página vuelve a declararse por su cuenta los convertidores
    /// compartidos.
    ///
    /// <para>Trece copias de la misma línea fueron lo que dejó a Ajustes sin
    /// <c>InvertBool</c>. Con una sola definición en <c>App.xaml</c> el olvido
    /// deja de ser posible; esta prueba impide que vuelvan a aparecer copias, que
    /// es la única forma de que la de arriba siga siendo suficiente.</para>
    /// </summary>
    [Fact]
    public void LosConvertidoresCompartidosSeDeclaranUnaSolaVez()
    {
        string appRoot = AppRoot();
        const string shared = "Resources/Converters.xaml";

        List<string> duplicates = [];

        foreach (string path in XamlFiles(appRoot))
        {
            string relative = Path.GetRelativePath(appRoot, path).Replace('\\', '/');
            if (relative == shared) continue;

            foreach (Match match in Regex.Matches(File.ReadAllText(path), @"<conv:(\w+)\s+x:Key=""(\w+)"""))
            {
                // `BoolToVisibilityOverlay` es la excepción declarada: mismo
                // convertidor con otra clave, para una superposición concreta.
                if (match.Groups[2].Value == "BoolToVisibilityOverlay") continue;

                duplicates.Add($"  {relative}: {match.Groups[1].Value} como «{match.Groups[2].Value}»");
            }
        }

        Assert.True(duplicates.Count == 0,
            $"Hay {duplicates.Count} convertidores declarados por página:\n"
            + string.Join("\n", duplicates)
            + $"\n\nVan en {shared}, que App.xaml fusiona. Trece copias de la misma línea fueron lo "
            + "que dejó a Ajustes usando InvertBool sin declararlo.");
    }
}
