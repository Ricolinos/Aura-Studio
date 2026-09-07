using System.Xml.Linq;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// El español que ve el usuario <b>no cambia ni una letra</b> al mover los
/// textos a recursos (ST-247, regla de cierre de B7a).
///
/// <para>B7a es mover, no redactar. La foto de lo que la app decía antes de
/// tocar nada es el borrador que la herramienta del mecánico saca del código;
/// esta prueba compara el archivo de recursos contra él.</para>
///
/// <para><b>Tres cosas pueden pasarle a una clave</b>, y las tres se
/// comprueban:</para>
///
/// <list type="number">
/// <item>Queda igual — el caso normal, y entonces el texto tiene que ser
/// idéntico.</item>
/// <item>Se <b>renombra</b>. Pasa cuando dos claves del borrador resultan ser
/// las dos formas de un plural, o cuando la clave compartida con la Mac se
/// llama distinto. El renombre se declara acá, con nombre viejo y nombre
/// nuevo, y el texto tiene que seguir siendo el mismo: un renombre no es una
/// excusa para reescribir.</item>
/// <item>Es <b>nueva</b>. Pasa donde el borrador no llegó: las formas de
/// plural, que no existían como recurso porque vivían en un ternario, y los
/// archivos que la herramienta no recorrió. Se declaran una por una — no un
/// patrón, no un prefijo — porque una clave nueva es texto que nadie comparó
/// contra nada, y la lista es lo que obliga a mirarla.</item>
/// </list>
///
/// <para><b>Antes había una excepción y ya no hace falta.</b> El borrador
/// partía una frase en fragmentos (<c>…-1</c>, <c>…-2</c>) cuando el código la
/// concatena entre líneas, así que el recurso las reunía y la prueba tenía que
/// permitir esa diferencia. Reunirlas a mano salió mal —cuatro de esos pares no
/// eran fragmentos sino <b>las dos ramas de un ternario</b>, o sea dos mensajes
/// distintos, y quedaron pegados—, y la prueba no lo vio porque calculaba lo
/// esperado con la misma lógica que hacía la unión. <b>Una prueba que
/// reimplementa el defecto no puede detectarlo.</b> La herramienta ya une las
/// concatenaciones ella misma, mirando la sintaxis, que es donde sí se
/// distingue un fragmento de una rama; con eso la excepción desapareció y lo
/// que queda son igualdades y dos listas de datos.</para>
/// </summary>
public class SpanishUnchangedTests
{
    /// <summary>
    /// Claves que cambiaron de nombre: <c>nombre en el borrador → nombre en el
    /// recurso</c>. El texto no cambia; solo cómo se llama.
    /// </summary>
    private static readonly (string Draft, string Resource)[] Renamed =
    [
        // Las dos etiquetas del menú resultaron ser el singular y el plural de
        // la misma acción, elegidas por un `> 1` escrito a mano. Como formas de
        // plural, el ruso y el árabe también las eligen bien.
        ("context-menu.quitar-foto-artista", "context-menu.quitar-foto-artista.one"),
        ("context-menu.quitar-fotos-artistas", "context-menu.quitar-foto-artista.other"),
    ];

    /// <summary>
    /// Claves que el borrador no tiene. Cada una dice de dónde sale su texto,
    /// porque es lo único que se puede revisar: no hay contra qué compararlo.
    /// </summary>
    private static readonly string[] New =
    [
        // Formas de plural. El texto de cada una es el de la rama del ternario
        // que reemplaza, con el número como hueco {0} en las DOS formas: en
        // ruso `.one` también le toca al 21 y al 101, así que un "1" escrito a
        // mano diría "21 archivo".
        "app-strings.delete-confirm-copy.one", "app-strings.delete-confirm-copy.other",
        "app-strings.delete-confirm-reference.one", "app-strings.delete-confirm-reference.other",
        "app-strings.delete-confirm-title.one", "app-strings.delete-confirm-title.other",
        "app-strings.orphans-cleaned.one", "app-strings.orphans-cleaned.other",
        "app-strings.orphans-confirm-title.one", "app-strings.orphans-confirm-title.other",
        "app-strings.orphans-found.one", "app-strings.orphans-found.other",

        // Un solo texto por cosa contada. "3 canciones" tenía su propio ternario
        // en cinco archivos; ahora se traduce una vez.
        "conteo.albumes.one", "conteo.albumes.other",
        "conteo.artistas.one", "conteo.artistas.other",
        "conteo.canciones.one", "conteo.canciones.other",
        "conteo.dias.one", "conteo.dias.other",
        "conteo.episodios.one", "conteo.episodios.other",
        "conteo.fotos.one", "conteo.fotos.other",
        "conteo.peliculas.one", "conteo.peliculas.other",
        "conteo.seleccionados.one", "conteo.seleccionados.other",
        "conteo.series.one", "conteo.series.other",
        "conteo.temporadas.one", "conteo.temporadas.other",
        "conteo.videoclips.one", "conteo.videoclips.other",
        "conteo.videos.one", "conteo.videos.other",

        // Las mismas formas, para los mensajes de la biblioteca y la
        // sincronización: cada par es el singular y el plural del ternario que
        // reemplaza, palabra por palabra.
        "library-view-model.album-cover-applied.one", "library-view-model.album-cover-applied.other",
        "library-view-model.copied-files.one", "library-view-model.copied-files.other",
        "library-view-model.copy-failed.one", "library-view-model.copy-failed.other",
        "library-view-model.copy-skipped.one", "library-view-model.copy-skipped.other",
        "library-view-model.copying-files.one", "library-view-model.copying-files.other",
        "library-view-model.covers-normalized.one", "library-view-model.covers-normalized.other",
        "library-view-model.covers-removed.one", "library-view-model.covers-removed.other",
        "library-view-model.migration-legacy-prepared.one", "library-view-model.migration-legacy-prepared.other",
        "library-view-model.migration-tagged.one", "library-view-model.migration-tagged.other",
        "library-view-model.migration-without-storage.one", "library-view-model.migration-without-storage.other",
        "library-view-model.not-started.one", "library-view-model.not-started.other",
        "library-view-model.searching-covers.one", "library-view-model.searching-covers.other",
        "library-view-model.tags-reread.one", "library-view-model.tags-reread.other",
        "media-grid-view-model.photos-removed-from-album.one", "media-grid-view-model.photos-removed-from-album.other",
        "similar-items-view-model.groups-found.one", "similar-items-view-model.groups-found.other",
        "similar-items-view-model.items-removed.one", "similar-items-view-model.items-removed.other",
        "sync-view-model.orphan-header.one", "sync-view-model.orphan-header.other",

        // El título del selector de tapas: dos mensajes, no dos formas. Uno
        // dice en qué lugar de la tanda va el álbum y el otro no habla de
        // ninguna tanda.
        "album-cover-picker.title-in-set", "album-cover-picker.title-single",

        // LibraryIngest, LibraryGrouping y LibraryStatusSummary: la herramienta
        // no los recorrió. El texto es el que tenían en el código.
        "library-ingest.added.one", "library-ingest.added.other",
        "library-ingest.already-in-library.one", "library-ingest.already-in-library.other",
        "library-ingest.cover-assets.one", "library-ingest.cover-assets.other",
        "library-ingest.unsupported.one", "library-ingest.unsupported.other",
        "library-ingest.wrong-section.one", "library-ingest.wrong-section.other",
        "library-ingest.nothing-to-add",
        "library-ingest.section-noun-music", "library-ingest.section-noun-video",
        "library-ingest.section-noun-photo", "library-ingest.section-noun-other",

        // Cómo se unen dos partes. No son frases: son la coma y el espacio que
        // separaban dos textos dentro de una interpolación, y en otro idioma
        // pueden no ser una coma ni ir en ese orden.
        "library-grouping.albums-and-songs",
        "library-status-summary.days-and-hours",

        // Un segundo "Completando {0}…" que la herramienta fusionó con el
        // primero: uno lleva una cantidad y el otro el título de lo que se está
        // completando. Son dos mensajes.
        "library-view-model.completando-title",

        // Tooltips y nombres para el lector de pantalla que el borrador no
        // extrajo. Un AutomationProperties.Name en español dentro de una app en
        // alemán es justo el defecto que B7b viene a evitar.
        "artists-page.buscar-fotos-artistas-linea",
        "artists-page.mas-acciones", "artists-page.mas-acciones-2",
        "device-list-page.calcula-que-se-copiaria",
        "library-status-strip.detener-tarea-en-curso",
        "media-grid-page.descarga-posters-que-falten",
        "settings-page.carpeta-nueva-biblioteca-anterior-intacta",
        "songs-page.busca-album-ano-caratula-letra", "songs-page.busca-repetidos",
    ];

    /// <summary>
    /// Claves donde el borrador trae el texto <b>doblemente escapado</b>.
    ///
    /// <para>La herramienta leyó el atributo del XAML sin deshacer las
    /// entidades, así que guardó <c>&amp;amp;quot;</c> donde el usuario ve una
    /// comilla. Copiarlo al pie de la letra habría puesto
    /// <c>&amp;quot;Simon + Garfunkel&amp;quot;</c> en pantalla, con las
    /// entidades a la vista: es el único caso donde ser fiel al borrador
    /// cambiaba lo que el usuario lee. Acá el recurso lleva las comillas de
    /// verdad, y lo que se comprueba es que sea <b>exactamente</b> el borrador
    /// desescapado — no una redacción nueva.</para>
    /// </summary>
    private static readonly string[] Unescaped =
    [
        "settings-page.nombres-grupo-llevan-uno-esos-separadore",
    ];

    /// <summary>
    /// Claves del borrador que ya no existen porque eran una copia de más del
    /// mismo texto. No se pierde ninguna frase: la misma sigue en otra clave.
    /// </summary>
    private static readonly string[] Duplicates =
    [
        // El borrador traía "Marcar como favorito" tres veces y el código tiene
        // dos sitios. Una clave de más es una traducción de más.
        "context-menu.marcar-como-favorito-3",
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

    /// <summary>
    /// Deshace un escapado de XML. Solo las cinco entidades que la herramienta
    /// puede haber dejado; nada más, para que no se convierta en un traductor
    /// que arregla cualquier diferencia.
    /// </summary>
    private static string Unescape(string text) => text
        .Replace("&quot;", "\"", StringComparison.Ordinal)
        .Replace("&apos;", "'", StringComparison.Ordinal)
        .Replace("&lt;", "<", StringComparison.Ordinal)
        .Replace("&gt;", ">", StringComparison.Ordinal)
        .Replace("&amp;", "&", StringComparison.Ordinal);

    private static Dictionary<string, string> Resources() => ValuesOf(Path.Combine(
        RepoRoot(), "studio", "windows", "AuraStudio.Core", "Strings", "Resources.resx"));

    private static Dictionary<string, string> Draft() => ValuesOf(Path.Combine(
        RepoRoot(), "studio", "windows", "docs", "extraccion-cadenas", "Strings", "es", "Resources.resw"));

    /// <summary>
    /// Cada texto del recurso es exactamente el que la app decía antes: el de
    /// su propia clave, o el de la clave de la que se renombró.
    /// </summary>
    [Fact]
    public void CadaTextoEsElQueLaAppDeciaAntes()
    {
        Dictionary<string, string> resources = Resources();
        Dictionary<string, string> draft = Draft();

        Dictionary<string, string> origin = Renamed.ToDictionary(pair => pair.Resource, pair => pair.Draft);
        HashSet<string> declaredNew = [.. New];

        List<string> problems = [];

        foreach ((string key, string text) in resources)
        {
            if (declaredNew.Contains(key)) continue;

            string source = origin.GetValueOrDefault(key, key);

            if (!draft.TryGetValue(source, out string? original))
            {
                problems.Add(source == key
                    ? $"{key}: no está en el borrador y no está declarada como nueva — o es texto redactado en B7a, que es lo que no toca, o falta declararla"
                    : $"{key}: dice venir de «{source}», que no está en el borrador");
                continue;
            }

            if (Unescaped.Contains(key)) original = Unescape(original);

            if (original != text)
                problems.Add($"{key}: el texto cambió\n  antes: {original}\n  ahora: {text}");
        }

        Assert.True(problems.Count == 0, string.Join("\n\n", problems));
    }

    /// <summary>
    /// Y al revés: ningún texto del borrador se perdió. Un texto que desaparece
    /// del recurso es una pantalla que se queda sin su frase.
    /// </summary>
    [Fact]
    public void NingunTextoSePerdioEnElCamino()
    {
        Dictionary<string, string> resources = Resources();

        HashSet<string> accountedFor =
        [
            .. resources.Keys,
            .. Renamed.Select(pair => pair.Draft),
            .. Duplicates,
        ];

        List<string> lost = [.. Draft().Keys.Where(key => !accountedFor.Contains(key))];

        Assert.True(lost.Count == 0,
            "Estos textos estaban en el borrador y no están en el recurso:\n" + string.Join("\n", lost));
    }

    /// <summary>
    /// Una clave quitada por duplicada tiene que seguir diciendo lo mismo desde
    /// otra clave. Si no, no era un duplicado: era una frase que se perdió.
    /// </summary>
    [Fact]
    public void LoQuitadoPorDuplicadoSigueDichoEnOtraClave()
    {
        Dictionary<string, string> draft = Draft();
        HashSet<string> texts = [.. Resources().Values];

        List<string> gone =
        [
            .. Duplicates
                .Where(key => draft.TryGetValue(key, out string? text) && !texts.Contains(text))
        ];

        Assert.True(gone.Count == 0,
            "Se quitaron por duplicadas, pero su texto ya no está en ninguna clave:\n"
            + string.Join("\n", gone));
    }

    /// <summary>
    /// Un renombre no puede inventar ni perder claves: la vieja se fue, la nueva
    /// está.
    /// </summary>
    [Fact]
    public void CadaRenombreVaDeUnaClaveQueEstabaAUnaQueEsta()
    {
        Dictionary<string, string> resources = Resources();
        Dictionary<string, string> draft = Draft();

        List<string> problems = [];

        foreach ((string from, string to) in Renamed)
        {
            if (!draft.ContainsKey(from)) problems.Add($"{from}: no está en el borrador, así que no hay de qué renombrar");
            if (!resources.ContainsKey(to)) problems.Add($"{to}: no está en el recurso, así que el renombre dejó el texto en la nada");
            if (resources.ContainsKey(from)) problems.Add($"{from}: se declaró renombrada pero sigue en el recurso");
        }

        Assert.True(problems.Count == 0, string.Join("\n", problems));
    }
}
