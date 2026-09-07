using System.Xml.Linq;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// El español que ve el usuario <b>no cambia ni una letra</b> al mover los
/// textos a recursos (ST-247, regla de cierre de B7a).
///
/// <para>B7a es mover, no redactar. Esta prueba compara el archivo de recursos
/// contra el borrador que sacó la herramienta del código —la foto de lo que la
/// app decía antes de tocar nada— y no deja pasar ninguna diferencia que no sea
/// la que se decidió a propósito.</para>
///
/// <para><b>La única diferencia permitida</b>: el borrador parte una frase en
/// fragmentos (<c>…-1</c>, <c>…-2</c>) cuando el código la concatena entre
/// líneas, y el corte cae a mitad de oración. Eso no se puede traducir —quien
/// traduce ve dos trozos que no son frases, y el orden de las palabras cambia
/// con el idioma—, así que en el recurso van reunidas. La prueba lo comprueba
/// carácter por carácter: el texto unido tiene que ser exactamente la
/// concatenación de los fragmentos, sin agregar ni quitar un espacio.</para>
/// </summary>
public class SpanishUnchangedTests
{
    /// <summary>
    /// Las 37 frases que se reúnen, <b>nombradas una por una</b>.
    ///
    /// <para><b>Por qué una lista y no una regla.</b> La primera versión de esta
    /// prueba calculaba la unión esperada con la misma lógica que hacía la
    /// unión, y por eso no vio que cuatro de las "frases partidas" no eran
    /// fragmentos de una concatenación sino <b>las dos ramas de un ternario</b>
    /// —dos mensajes distintos— que quedaron pegados en una sola cadena
    /// ("No hay ninguna carpeta de biblioteca configurada.La biblioteca está en
    /// un disco que no está conectado: {0}"). Una prueba que reimplementa el
    /// defecto no puede detectarlo.</para>
    ///
    /// <para>Con la lista escrita, unir una frase de más falla hasta que alguien
    /// la agregue a mano, que es tanto como decir: hasta que alguien la mire. La
    /// regla que hay que aplicar al mirarla: <b>solo se unen literales
    /// adyacentes pegados con <c>+</c></b>; las ramas de un <c>?:</c> y las de un
    /// <c>switch</c> son mensajes distintos y llevan claves distintas.</para>
    /// </summary>
    private static readonly string[] MergedSentences =
    [
        "app-strings.bootloader-update-done-detail",
        "app-strings.bootloader-update-enter-dfu-when",
        "app-strings.bootloader-update-flash-confirm",
        "app-strings.bootloader-update-not-required",
        "app-strings.bootloader-update-nothing-touched",
        "app-strings.bootloader-update-offer-unknown",
        "app-strings.bootloader-update-what-it-is",
        "app-strings.device-ambiguous",
        "app-strings.dfu-driver-missing",
        "app-strings.dfu-driver-package-missing",
        "app-strings.installer-dfu-detected-detail",
        "app-strings.installer-dfu-not-found",
        "app-strings.installer-dfu-not-seen-by-windows",
        "app-strings.installer-dfu-timing-warning",
        "app-strings.installer-dry-run-ok",
        "app-strings.installer-enter-dfu-when",
        "app-strings.installer-family-change",
        "app-strings.installer-format-danger-detail",
        "app-strings.installer-format-needs-confirmation",
        "app-strings.installer-permissions-detail",
        "app-strings.installer-welcome-detail",
        "app-strings.installer-welcome-warning",
        "app-strings.library-locked-reason",
        "app-strings.library-root-missing-detail",
        "app-strings.licenses-intro",
        "app-strings.licenses-libraries-intro",
        "app-strings.licenses-tag-lib-detail",
        "app-strings.licenses-tool-local-pin",
        "app-strings.licenses-unknown-tag-detail",
        "app-strings.orphans-confirm-message",
        "app-strings.orphans-detail",
        "app-strings.section-pending-detail",
        "app-strings.service-pause-detail",
        "app-strings.settings-language-detail",
        "app-strings.storage-change-only-affects-future",
        "app-strings.storage-copy-explainer",
        "app-strings.storage-reference-explainer"
    ];

    private static string RepoRoot()
    {
        DirectoryInfo? directory = new(AppContext.BaseDirectory);

        while (directory is not null)
        {
            if (File.Exists(Path.Combine(directory.FullName, "studio", "windows", "AuraStudio.Windows.slnx")))
                return directory.FullName;

            directory = directory.Parent;
        }

        throw new InvalidOperationException("No se encontró la raíz del repo desde el directorio de pruebas.");
    }

    private static Dictionary<string, string> ValuesOf(string path) =>
        XDocument.Load(path)
            .Root!
            .Elements("data")
            .ToDictionary(
                data => data.Attribute("name")!.Value,
                data => data.Element("value")?.Value ?? "");

    private static Dictionary<string, string> Resources() => ValuesOf(
        Path.Combine(RepoRoot(), "studio", "windows", "AuraStudio.Core", "Strings", "Resources.resx"));

    private static Dictionary<string, string> Draft() => ValuesOf(Path.Combine(
        RepoRoot(), "studio", "windows", "docs", "extraccion-cadenas", "Strings", "es", "Resources.resw"));

    /// <summary>
    /// Cada texto del recurso es el del borrador, o la unión exacta de sus
    /// fragmentos. Ni una letra distinta.
    /// </summary>
    [Fact]
    public void CadaTextoEsElQueLaAppDeciaAntes()
    {
        Dictionary<string, string> resources = Resources();
        Dictionary<string, string> draft = Draft();

        List<string> problems = [];

        foreach ((string key, string text) in resources)
        {
            if (draft.TryGetValue(key, out string? original))
            {
                if (original != text) problems.Add($"{key}: el texto cambió\n  antes: {original}\n  ahora: {text}");
                continue;
            }

            if (JoinedFragments(draft, key) is { } joined)
            {
                if (joined != text)
                {
                    problems.Add($"{key}: la unión de los fragmentos no coincide\n  unión: {joined}\n  ahora: {text}");
                }

                continue;
            }

            problems.Add($"{key}: no está en el borrador — es un texto nuevo, y B7a es mover, no redactar");
        }

        Assert.True(problems.Count == 0, string.Join("\n\n", problems));
    }

    /// <summary>
    /// Y al revés: ningún texto del borrador se perdió. Un texto que
    /// desaparece del recurso es una pantalla que se queda sin su frase.
    /// </summary>
    [Fact]
    public void NingunTextoSePerdioEnElCamino()
    {
        Dictionary<string, string> resources = Resources();
        Dictionary<string, string> draft = Draft();

        List<string> lost = [];

        foreach (string key in draft.Keys)
        {
            if (resources.ContainsKey(key)) continue;

            // Un fragmento cuya frase entera sí está: es de los que se
            // reunieron a propósito.
            if (key.Length > 2 && char.IsDigit(key[^1]) && key[^2] == '-'
                && resources.ContainsKey(key[..^2]))
            {
                continue;
            }

            // Las dos claves vacías del borrador viejo salían del brazo `_ => ""`
            // de un `switch`: texto que no existe, no texto sin traducir. La
            // herramienta ya no las genera; la excepción queda por si vuelven.
            if (string.IsNullOrWhiteSpace(draft[key])) continue;

            lost.Add(key);
        }

        Assert.True(lost.Count == 0,
            "Estos textos estaban en el borrador y no están en el recurso:\n" + string.Join("\n", lost));
    }

    /// <summary>
    /// Las frases reunidas son <b>exactamente</b> las de la lista: ni una más.
    ///
    /// <para>Unir una de más es lo que pasó con cuatro ternarios, y lo que la
    /// versión anterior de esta prueba no vio por calcular lo esperado con la
    /// misma lógica del defecto. Ahora una unión nueva falla hasta que alguien
    /// la escriba en la lista, o sea hasta que alguien la mire.</para>
    /// </summary>
    [Fact]
    public void SeReunenExactamenteLasFrasesDeLaLista()
    {
        Dictionary<string, string> resources = Resources();
        Dictionary<string, string> draft = Draft();

        List<string> merged =
            [.. resources.Keys.Where(key => !draft.ContainsKey(key)).Order(StringComparer.Ordinal)];

        Assert.Equal(MergedSentences.Order(StringComparer.Ordinal), merged);
    }


    /// <summary>
    /// Los fragmentos <c>clave-1</c>, <c>clave-2</c>… unidos en orden, o
    /// <c>null</c> si esa clave no está partida en el borrador.
    /// </summary>
    private static string? JoinedFragments(Dictionary<string, string> draft, string key)
    {
        if (!draft.ContainsKey($"{key}-1") || !draft.ContainsKey($"{key}-2")) return null;

        var parts = new List<string>();

        for (int index = 1; draft.TryGetValue($"{key}-{index}", out string? part); index++)
            parts.Add(part);

        return string.Concat(parts);
    }
}
