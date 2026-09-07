using System.Text.RegularExpressions;
using System.Xml.Linq;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// ST-247: dos cosas de naturaleza distinta viven en este archivo desde que
/// B7a cerró y movió las cadenas de código a
/// <c>AuraStudio.Core/Strings/Resources.resx</c> (el recurso real, el que
/// usa la app).
///
/// <para><b>Foto histórica</b> (sección de arriba): pruebas contra
/// <c>docs/extraccion-cadenas/</c> -- el borrador que generaba
/// <c>tools/ExtraerCadenasWindows</c> antes de B7a. Esa carpeta quedó
/// CONGELADA (ver su <c>README.md</c>): con el texto fuera del código, la
/// herramienta ya no tiene nada que extraer, así que volver a correrla
/// dejaría la foto vacía en vez de actualizada. Estas pruebas verifican esa
/// foto tal cual quedó, no el estado actual de la app.</para>
///
/// <para><b>Estado actual</b> (sección de abajo): pruebas contra
/// <c>AuraStudio.Core/Strings/Resources.resx</c> de verdad -- claves
/// compartidas con la Mac, sin claves vacías, plurales con su hueco
/// adentro. Estas SÍ pueden fallar si algo real cambia en la app.</para>
/// </summary>
public class LocalizationDraftTests
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

    private static string OutDir() => Path.Combine(RepoRoot(), "studio", "windows", "docs", "extraccion-cadenas");

    private static string CoreResxPath() =>
        Path.Combine(RepoRoot(), "studio", "windows", "AuraStudio.Core", "Strings", "Resources.resx");

    /// <summary>
    /// El borrador se commitea (a diferencia de la Mac, que lo gitignora):
    /// es un entregable de B7a, no un archivo de paso. Si no está, algo real
    /// se rompió -- se falla, no se salta.
    /// </summary>
    private static string RequireFile(string relative)
    {
        string path = Path.Combine(OutDir(), relative);
        Assert.True(File.Exists(path), $"{relative} no se encontró -- ¿corriste tools/ExtraerCadenasWindows? (ST-247)");
        return path;
    }

    // ======================================================================
    // MARK: FOTO HISTÓRICA -- docs/extraccion-cadenas/, congelado desde el
    // cierre de B7a (ver README.md de la carpeta). Verifica cómo quedó la
    // extracción, no el estado actual de la app.
    // ======================================================================

    // MARK: - Claves únicas

    /// <summary>
    /// Un <c>.resw</c> con un <c>name</c> de <c>&lt;data&gt;</c> repetido no
    /// es inválido para el parser XML (a diferencia de una clave de objeto
    /// JSON, que <c>JSONSerialization</c> colapsa en silencio) — pero SÍ
    /// sería un error real del extractor: dos textos distintos peleándose la
    /// misma clave, y uno de los dos se perdería en la práctica al leerlo con
    /// <c>ResourceManager</c>. Se verifica sobre las claves ya parseadas.
    /// </summary>
    [Fact]
    public void LasClavesDelReswSonUnicas()
    {
        XDocument doc = XDocument.Load(RequireFile(Path.Combine("Strings", "es", "Resources.resw")));
        List<string> keys = [.. doc.Root!.Elements("data").Select(e => e.Attribute("name")!.Value)];

        Assert.Equal(keys.Count, keys.Distinct(StringComparer.Ordinal).Count());
        Assert.True(keys.Count > 400, $"se esperaban más de 400 claves (línea base de B0, ~480), hay {keys.Count}");
    }

    [Fact]
    public void NingunaClaveEstaVacia()
    {
        XDocument doc = XDocument.Load(RequireFile(Path.Combine("Strings", "es", "Resources.resw")));

        foreach (XElement data in doc.Root!.Elements("data"))
            Assert.False(string.IsNullOrWhiteSpace(data.Attribute("name")?.Value), "una clave vacía en el .resw");
    }

    /// <summary>
    /// ST-247 (addendum): un brazo <c>_ =&gt; ""</c> de un <c>switch</c>
    /// (<c>LibrarySectionOnlyItsType</c>, <c>MediaGridViewModel</c>) no es un
    /// hueco de traducción -- es "acá no hay texto". Antes de esta corrección
    /// llegaba al borrador con <c>&lt;value&gt;&lt;/value&gt;</c>: la clave
    /// existe, así que ninguna prueba de "clave ausente" lo atrapaba nunca —
    /// hacía falta mirar el VALOR, no la clave.
    /// </summary>
    [Fact]
    public void NingunValorEstaVacio()
    {
        XDocument doc = XDocument.Load(RequireFile(Path.Combine("Strings", "es", "Resources.resw")));

        foreach (XElement data in doc.Root!.Elements("data"))
        {
            string? value = data.Element("value")?.Value;
            Assert.False(string.IsNullOrWhiteSpace(value),
                $"la clave {data.Attribute("name")?.Value} tiene un valor vacío en español");
        }
    }

    /// <summary>
    /// ST-247 (addendum): <c>NavPhotosAI</c> salía <c>nav-photos-a-i</c> —el
    /// kebab-case partía la sigla letra por letra— en vez de
    /// <c>nav-photos-ai</c>. Cualquier clave con dos o más letras SUELTAS
    /// seguidas, cada una separada por guion, es la misma forma del defecto
    /// resurgiendo (`KeyNaming.PascalToKebab`, corregido en este addendum).
    /// </summary>
    [Fact]
    public void NingunaClaveTieneLetrasSueltasSeparadasPorGuion()
    {
        XDocument doc = XDocument.Load(RequireFile(Path.Combine("Strings", "es", "Resources.resw")));
        var brokenAcronym = new Regex(@"(^|-)[a-z](-[a-z]){1,}(-|$)");

        List<string> rotas = [.. doc.Root!.Elements("data")
            .Select(e => e.Attribute("name")!.Value)
            .Where(key => brokenAcronym.IsMatch(key))];

        Assert.True(rotas.Count == 0,
            "claves con una sigla partida letra por letra: " + string.Join(", ", rotas.Take(10)));
    }

    // MARK: - Frases concatenadas ("a" + "b"), no partidas en dos claves

    /// <summary>
    /// Los únicos <c>app-strings.*</c> con sufijo <c>-N</c> numérico
    /// legítimos son los ternarios de DOS mensajes de verdad distintos
    /// (<c>condición ? "mensaje A" : "mensaje B"</c>) — nunca un párrafo
    /// escrito como <c>"a" + "b"</c> que el extractor no supo unir. Lista
    /// explícita, no un patrón: agregar una clave nueva acá tiene que ser
    /// una decisión consciente ("sí, es un ternario de verdad"), no un
    /// efecto colateral silencioso de una corrida futura.
    /// </summary>
    private static readonly HashSet<string> KnownAppStringsTernaryPairs = new(StringComparer.Ordinal)
    {
        "app-strings.bootloader-update-flashing-1", "app-strings.bootloader-update-flashing-2",
        "app-strings.installer-dfu-found-1", "app-strings.installer-dfu-found-2",
        "app-strings.library-root-missing-1", "app-strings.library-root-missing-2",
        "app-strings.library-season-1", "app-strings.library-season-2",
        "app-strings.library-status-6", "app-strings.library-status-7",
    };

    [Fact]
    public void NingunaClaveAppStringsTerminaEnGuionNumericoSalvoLosTernariosConocidos()
    {
        XDocument doc = XDocument.Load(RequireFile(Path.Combine("Strings", "es", "Resources.resw")));
        var numericSuffix = new Regex(@"^app-strings\..*-\d+$");

        List<string> sospechosas = [.. doc.Root!.Elements("data")
            .Select(e => e.Attribute("name")!.Value)
            .Where(key => numericSuffix.IsMatch(key) && !KnownAppStringsTernaryPairs.Contains(key))];

        Assert.True(sospechosas.Count == 0,
            "claves de AppStrings con sufijo -N fuera de la lista de ternarios conocidos " +
            "(¿un párrafo concatenado que no se unió?): " + string.Join(", ", sospechosas));
    }

    [Fact]
    public void NingunValorTerminaEnEspacio()
    {
        XDocument doc = XDocument.Load(RequireFile(Path.Combine("Strings", "es", "Resources.resw")));

        List<string> rotos = [.. doc.Root!.Elements("data")
            .Where(e => Regex.IsMatch(e.Element("value")?.Value ?? "", @"\s$"))
            .Select(e => e.Attribute("name")!.Value)];

        Assert.True(rotos.Count == 0,
            "valores que terminan en espacio -- mitad de una frase cortada: " + string.Join(", ", rotos.Take(10)));
    }

    /// <summary>
    /// Un valor que empieza en minúscula suele ser la segunda mitad de una
    /// frase cortada a mitad ("...y los " + "sincroniza directo..." daba un
    /// segundo fragmento que empezaba en "sincroniza"). Las excepciones son
    /// reales y conocidas -- "iPod" (la propia Apple lo escribe así), URLs, y
    /// un par de nombres técnicos (ffmpeg, nombres de archivo en el aviso de
    /// licencias) -- así que se excluyen por clave, no por adivinar un patrón
    /// que las distinga del síntoma real.
    /// </summary>
    private static readonly HashSet<string> KnownLowercaseStartExceptions = new(StringComparer.Ordinal)
    {
        "app-strings.installer-dfu-found-1", "app-strings.installer-dfu-found-2", // "iPod detectado..."
        "app-strings.installer-dfu-guide-url", "app-strings.licenses-tag-lib-source", // URLs
        "app-strings.licenses-intro", // "mks5lboot, bootloader-ipod6g.ipod y..."
        "settings-page.ffmpeg", // "ffmpeg"
    };

    [Fact]
    public void NingunValorEmpiezaEnMinusculaSalvoExcepcionesConocidas()
    {
        XDocument doc = XDocument.Load(RequireFile(Path.Combine("Strings", "es", "Resources.resw")));
        var lowercaseStart = new Regex(@"^\p{Ll}");

        List<string> rotos = [.. doc.Root!.Elements("data")
            .Where(e => lowercaseStart.IsMatch(e.Element("value")?.Value ?? ""))
            .Select(e => e.Attribute("name")!.Value)
            .Where(key => !KnownLowercaseStartExceptions.Contains(key))];

        Assert.True(rotos.Count == 0,
            "valores que empiezan en minúscula fuera de las excepciones conocidas " +
            "(¿la segunda mitad de una frase cortada?): " + string.Join(", ", rotos.Take(10)));
    }

    // MARK: - Especificadores consistentes entre es/en

    /// <summary>
    /// Compara los especificadores <c>{0}</c>/<c>{1}</c>... de cada clave
    /// entre los dos <c>.resw</c>. Hoy "en" queda vacío a propósito (borrador,
    /// nunca traducido a mano) — se salta esa clave, no se falla por eso; es
    /// la misma prueba que sí va a fallar el día que B7b llene "en" y alguna
    /// traducción pierda un especificador.
    /// </summary>
    [Fact]
    public void LosEspecificadoresSonConsistentesEntreEsYEn()
    {
        Dictionary<string, string> es = ReadResw(RequireFile(Path.Combine("Strings", "es", "Resources.resw")));
        Dictionary<string, string> en = ReadResw(RequireFile(Path.Combine("Strings", "en", "Resources.resw")));

        Assert.Equal(es.Count, en.Count);

        foreach ((string key, string spanishValue) in es)
        {
            Assert.True(en.ContainsKey(key), $"la clave {key} está en es.resw y no en en.resw");
            string englishValue = en[key];

            if (string.IsNullOrEmpty(englishValue)) continue; // pendiente de traducir, nada que comparar todavía

            Assert.Equal(Specifiers(spanishValue), Specifiers(englishValue));
        }
    }

    private static HashSet<string> Specifiers(string text) =>
        [.. Regex.Matches(text, @"\{\d+\}").Select(m => m.Value)];

    // MARK: - El CSV y el .resw no se desalinean

    /// <summary>
    /// Toda fila TRADUCIBLE del CSV tiene que tener su clave en el
    /// <c>.resw</c> en español — son el mismo borrador, contado dos veces.
    /// Las filas de tipo <c>CulturaFija</c> quedan afuera a propósito: no son
    /// texto para traducir, son un defecto de código para reescribir (una
    /// cultura fija, un patrón de fecha con gramática incrustada), así que
    /// nunca tuvieron por qué entrar al <c>.resw</c>.
    /// </summary>
    [Fact]
    public void TodaFilaTraducibleDelCsvTieneSuClaveEnElResw()
    {
        Dictionary<string, string> resw = ReadResw(RequireFile(Path.Combine("Strings", "es", "Resources.resw")));
        // "CulturaFija": no es texto para traducir, es un defecto de código.
        // "Dato" (A7b): dato de catálogo que se compara por igualdad
        // (MediaCategoryNames.IsMoviesCategory/IsSeriesCategory) -- tampoco
        // entra al .resw, ver CatalogDataExtractor.
        List<string> csvKeys = ReadCsvKeys(RequireFile("revision.csv"), "CulturaFija", "Dato");

        Assert.True(csvKeys.Count > 0);

        List<string> missing = [.. csvKeys.Where(key => !resw.ContainsKey(key)).Distinct(StringComparer.Ordinal)];
        Assert.True(missing.Count == 0, "claves del CSV ausentes en el .resw: " + string.Join(", ", missing.Take(10)));
    }

    /// <summary>
    /// A7b (encargo del coordinador): las categorías de video son dato del
    /// catálogo, no texto de interfaz -- <c>CatalogDataExtractor</c> las
    /// marca <c>Kind = "Dato"</c> con una nota explicando por qué, en vez de
    /// dejarlas colar como una clave traducible más. Ninguna fila "Dato"
    /// puede terminar en el <c>.resw</c> -- si apareciera ahí, alguien la
    /// estaría tratando como texto vivo, exactamente lo que esto evita.
    /// </summary>
    [Fact]
    public void NingunaFilaDeDatoDeCatalogoTerminaEnElResw()
    {
        Dictionary<string, string> resw = ReadResw(RequireFile(Path.Combine("Strings", "es", "Resources.resw")));
        string[] lines = File.ReadAllLines(RequireFile("revision.csv"));

        List<string> datoKeys = [.. lines.Skip(1)
            .Where(line => line.Length > 0)
            .Select(ParseCsvLine)
            .Where(fields => fields[1] == "Dato")
            .Select(fields => fields[0])];

        List<string> filtradas = [.. datoKeys.Where(key => resw.ContainsKey(key))];
        Assert.True(filtradas.Count == 0,
            "clave de dato de catálogo colada en el .resw como si fuera texto traducible: " + string.Join(", ", filtradas));
    }

    /// <summary>
    /// ST-247 (cierre de B7a): cotejo clave por clave contra el borrador de
    /// la Mac -- pero YA CONTRA <c>Resources.resx</c>, el recurso real, no
    /// el borrador congelado (ver el <c>Skip</c> que esta prueba reemplaza,
    /// abajo en el historial de <c>DECISIONS.md</c>).
    ///
    /// <para>Toda fila <c>"igual"</c> de <c>claves-compartidas.csv</c> --la
    /// clave ya coincide entre las dos plataformas-- tiene que existir en el
    /// <c>.resx</c> CON EL MISMO TEXTO que "texto es"; toda fila
    /// <c>"clave distinta"</c> tiene que existir (el texto difiere a
    /// propósito, así que solo se comprueba que la clave esté, no el
    /// texto). El CSV es la autoridad del NOMBRE compartido, pero la
    /// herramienta de Windows no siempre renombra su propia clave para
    /// calzar con él -- por eso "existe" admite DOS caminos: (1) la clave
    /// del CSV coincide tal cual con una clave del <c>.resx</c>, o (2) el
    /// paréntesis al final de "sitio Windows" -- formato oficial
    /// "archivo:línea (clave.de.windows)" -- trae la clave real.</para>
    ///
    /// <para><b>orphans-confirm-message ya no es un caso aparte</b>: B7a
    /// compuso <c>AppStrings.OrphansConfirmMessage</c> desde
    /// <c>app-strings.orphans-found.{0,other}</c> (el conteo) más
    /// <c>orphans-confirm-message</c> (el texto compartido, palabra por
    /// palabra) -- pasa por el camino 1 como cualquier otra fila "igual".
    /// El <c>Skip</c> que existía para esta fila mientras se esperaba la
    /// composición ya no hace falta -- coordinador, ST-247.</para>
    /// </summary>
    [Fact]
    public void TodaClaveCompartidaExisteEnResourcesResx()
    {
        Dictionary<string, string> resx = ReadResw(CoreResxPath());
        string sharedPath = RequireFile("claves-compartidas.csv");
        var windowsKeyInParens = new Regex(@"\((?<key>[a-z0-9][\w.-]*)(?:,[^)]*)?\)");

        string[] sharedLines = File.ReadAllLines(sharedPath);
        int textoEsIndex = SharedCsvColumnIndex(sharedLines[0], "texto es");
        int sitioWindowsIndex = SharedCsvColumnIndex(sharedLines[0], "sitio Windows");
        int estadoIndex = SharedCsvColumnIndex(sharedLines[0], "estado");

        List<(string CsvKey, string TextoEs, string SitioWindows, string Estado)> rows = [.. sharedLines
            .Skip(1)
            .Where(line => line.Length > 0)
            .Select(ParseCsvLine)
            .Where(fields => fields[estadoIndex] is "igual" or "clave distinta")
            .Select(fields => (fields[0], fields[textoEsIndex], fields[sitioWindowsIndex], fields[estadoIndex]))];

        Assert.True(rows.Count > 0);

        List<string> problemas = [];
        foreach ((string csvKey, string textoEs, string sitioWindows, string estado) in rows)
        {
            bool exigeMismoTexto = estado == "igual";

            if (resx.TryGetValue(csvKey, out string? directValue)) // camino 1: la clave del CSV coincide tal cual
            {
                if (exigeMismoTexto && directValue != textoEs)
                    problemas.Add($"{csvKey}: existe pero el texto no coincide (\"{directValue}\" vs \"{textoEs}\")");
                continue;
            }

            // camino 2: alguna clave entre paréntesis de "sitio Windows" existe
            // en el .resx -- con el mismo texto que "texto es" si es "igual"
            bool matched = windowsKeyInParens.Matches(sitioWindows)
                .Select(m => m.Groups["key"].Value)
                .Any(windowsKey => resx.TryGetValue(windowsKey, out string? value) && (!exigeMismoTexto || value == textoEs));

            if (!matched) problemas.Add($"{csvKey} ({estado}): sin correspondencia en Resources.resx");
        }

        Assert.True(problemas.Count == 0,
            "claves-compartidas.csv marca una fila sin correspondencia correcta en Resources.resx: " +
            string.Join("; ", problemas.Take(10)));
    }

    // MARK: - Huecos de interpolación: sin duplicados para la misma expresión

    /// <summary>
    /// Coordinador (addendum sobre huecos): la conversión a <c>{0}</c>/<c>{1}</c>...
    /// tiene que REUSAR el índice cuando la misma expresión interpolada
    /// (<c>{installed}</c>, por ejemplo) aparece más de una vez en el mismo
    /// texto — caso real: <c>app-strings.installer-family-change</c>. Esta
    /// prueba lee <c>revision.csv</c> y compara, fila por fila, las
    /// expresiones de <c>texto_original</c> contra los marcadores de
    /// <c>texto_con_marcadores</c>, en orden de aparición: la misma expresión
    /// nunca puede traer dos marcadores distintos, y el mismo marcador nunca
    /// puede representar dos expresiones distintas (eso sería peor: dos datos
    /// reales fundidos en un solo hueco).
    /// </summary>
    [Fact]
    public void NingunaExpresionInterpoladaRepetidaTieneHuecosDistintos()
    {
        string path = RequireFile("revision.csv");
        var expressionPattern = new Regex(@"\{[^{}]*\}");
        var markerPattern = new Regex(@"\{(\d+)\}");

        foreach (string line in File.ReadAllLines(path).Skip(1))
        {
            if (line.Length == 0) continue;
            List<string> fields = ParseCsvLine(line);
            if (fields.Count < 7 || fields[6] != "sí") continue; // solo filas con interpolación

            string key = fields[0];
            List<string> expressions = [.. expressionPattern.Matches(fields[4]).Select(m => m.Value[1..^1])];
            List<string> markers = [.. markerPattern.Matches(fields[5]).Select(m => m.Groups[1].Value)];

            Assert.True(expressions.Count == markers.Count,
                $"clave {key}: {expressions.Count} expresión(es) en texto_original vs. {markers.Count} marcador(es) en texto_con_marcadores");

            var markerByExpression = new Dictionary<string, string>(StringComparer.Ordinal);
            var expressionByMarker = new Dictionary<string, string>(StringComparer.Ordinal);

            for (int i = 0; i < expressions.Count; i++)
            {
                string expression = expressions[i];
                string marker = markers[i];

                if (markerByExpression.TryGetValue(expression, out string? expectedMarker))
                    Assert.True(marker == expectedMarker,
                        $"clave {key}: la expresión {{{expression}}} aparece con huecos distintos ({{{expectedMarker}}} y {{{marker}}})");
                else
                    markerByExpression[expression] = marker;

                if (expressionByMarker.TryGetValue(marker, out string? expectedExpression))
                    Assert.True(expression == expectedExpression,
                        $"clave {key}: el hueco {{{marker}}} representa dos expresiones distintas ({{{expectedExpression}}} y {{{expression}}})");
                else
                    expressionByMarker[marker] = expression;
            }
        }
    }

    // MARK: - Los 9+ plurales por ternario tienen dos formas distintas

    /// <summary>
    /// Mismo hallazgo que la Mac tuvo que corregir en su propia prueba: no
    /// alcanza con "las dos formas no vacías" — puede haber un sufijo
    /// legítimamente vacío (p. ej. un plural que agrega una "s" sola en vez
    /// de repetir la palabra). Lo que sí tiene que ser cierto siempre es que
    /// las dos formas sean DISTINTAS entre sí.
    /// </summary>
    [Fact]
    public void LosPluralesPorTernarioTienenDosFormasDistintas()
    {
        string path = RequireFile("plurales-ternario.csv");
        string[] lines = File.ReadAllLines(path);
        Assert.True(lines.Length > 1, "plurales-ternario.csv no tiene filas de datos");

        foreach (string line in lines.Skip(1))
        {
            List<string> fields = ParseCsvLine(line);
            Assert.True(fields.Count >= 4, $"fila de plurales-ternario.csv con menos de 4 campos: {line}");

            string singular = fields[2];
            string plural = fields[3];
            Assert.NotEqual(singular, plural);
        }
    }

    /// <summary>
    /// A7a (encargo del coordinador): toda forma "plural" tiene que traer un
    /// hueco <c>{...}</c> ADENTRO -- el número nunca puede ir pegado por
    /// fuera, sin hueco (eso rompería el día que <c>PluralRules</c>
    /// necesite reordenar el número dentro de la frase para otro idioma).
    ///
    /// <para>Hoy hay 6 filas sin ninguna llave en "plural", documentadas
    /// como excepción conocida en vez de forzadas a pasar en silencio:
    /// cinco son declinaciones de UNA palabra sola (<c>artista</c>/<c>artistas</c>,
    /// <c>álbum</c>/<c>álbumes</c>, <c>canción</c>/<c>canciones</c> x2,
    /// <c>día</c>/<c>días</c>) -- piezas sueltas que el código arma con el
    /// número aparte en otro lado, no una oración completa con el número
    /// adentro; la sexta (<c>ContextMenu.cs:210</c>, "Quitar fotos de los
    /// artistas"/"Quitar foto del artista") ni siquiera es un plural de
    /// verdad -- es una etiqueta de menú distinta según cuántos artistas
    /// están seleccionados, sin ningún número que interpolar. Cualquier fila
    /// NUEVA sin hueco sigue haciendo fallar la prueba.</para>
    /// </summary>
    private static readonly HashSet<(string File, int Line)> KnownPluralFormsWithoutHole = new()
    {
        ("studio/windows/AuraStudio.Core/Library/ContextMenu.cs", 210),
        ("studio/windows/AuraStudio.App/ViewModels/ArtistsViewModel.cs", 251),
        ("studio/windows/AuraStudio.App/ViewModels/ArtistsViewModel.cs", 252),
        ("studio/windows/AuraStudio.App/ViewModels/ArtistsViewModel.cs", 253),
        ("studio/windows/AuraStudio.Core/Library/LibraryGrouping.cs", 41),
        ("studio/windows/AuraStudio.Core/Library/LibraryStatusSummary.cs", 93),
    };

    [Fact]
    public void TodaFormaPluralTraeUnHuecoAdentroSalvoExcepcionesConocidas()
    {
        string path = RequireFile("plurales-ternario.csv");
        string[] lines = File.ReadAllLines(path);
        Assert.True(lines.Length > 1, "plurales-ternario.csv no tiene filas de datos");

        List<string> sinHueco = [];

        foreach (string line in lines.Skip(1))
        {
            List<string> fields = ParseCsvLine(line);
            Assert.True(fields.Count >= 4, $"fila de plurales-ternario.csv con menos de 4 campos: {line}");

            string file = fields[0];
            if (!int.TryParse(fields[1], out int fileLine)) continue;
            string plural = fields[3];

            if (plural.Contains('{')) continue;
            if (KnownPluralFormsWithoutHole.Contains((file, fileLine))) continue;

            sinHueco.Add($"{file}:{fileLine} ({plural})");
        }

        Assert.True(sinHueco.Count == 0,
            "forma plural sin ningún hueco {...} adentro, fuera de las excepciones conocidas: " +
            string.Join(", ", sinHueco.Take(10)));
    }

    // ======================================================================
    // MARK: ESTADO ACTUAL -- AuraStudio.Core/Strings/Resources.resx, el
    // recurso real que usa la app. A diferencia de la sección de arriba,
    // estas pruebas SÍ pueden fallar si algo real cambia (ST-247, cierre
    // de B7a, encargo del coordinador).
    // ======================================================================

    /// <summary>Mismo motivo que su análoga histórica -- un hueco vacío es "acá no hay texto", nunca algo que traducir.</summary>
    [Fact]
    public void NingunaClaveEstaVaciaEnResourcesResx()
    {
        XDocument doc = XDocument.Load(CoreResxPath());

        foreach (XElement data in doc.Root!.Elements("data"))
            Assert.False(string.IsNullOrWhiteSpace(data.Attribute("name")?.Value), "una clave vacía en Resources.resx");
    }

    /// <summary>Mismo motivo que su análoga histórica -- un valor vacío es un hueco en pantalla que ninguna prueba de "clave ausente" atrapa.</summary>
    [Fact]
    public void NingunValorEstaVacioEnResourcesResx()
    {
        XDocument doc = XDocument.Load(CoreResxPath());

        foreach (XElement data in doc.Root!.Elements("data"))
        {
            string? value = data.Element("value")?.Value;
            Assert.False(string.IsNullOrWhiteSpace(value),
                $"la clave {data.Attribute("name")?.Value} tiene un valor vacío en Resources.resx");
        }
    }

    /// <summary>
    /// Las formas de plural viven en <c>Resources.resx</c> como
    /// <c>&lt;clave&gt;.zero</c>/<c>.one</c>/<c>.two</c>/<c>.few</c>/<c>.many</c>/<c>.other</c>
    /// (ver <c>Strings.Plural</c>, <c>PluralRules.SuffixFor</c>) -- toda
    /// forma tiene que traer <c>{0}</c> adentro, el número nunca pegado por
    /// fuera (mismo encargo que ya se comprobó contra el borrador para A7a;
    /// esta es la versión que corre contra el recurso real). La mayoría de
    /// las formas <c>.one</c> SÍ traen <c>{0}</c> ("1 canción", "1 archivo
    /// ({1}) va a la Papelera") -- no se exceptúa la categoría entera, solo
    /// los casos reales, verificados a mano.
    /// </summary>
    private static readonly HashSet<string> KnownResxPluralFormsWithoutHole = new(StringComparer.Ordinal)
    {
        // No es un plural de verdad -- una etiqueta de menú distinta según
        // cuántos artistas están seleccionados, sin ningún número que
        // interpolar (mismo caso que ContextMenu.cs:210 en la foto histórica).
        "context-menu.quitar-foto-artista.one",
        "context-menu.quitar-foto-artista.other",
        // La forma singular no necesita decir "1": "Buscando carátula…" es la
        // frase completa para un solo álbum; ".other" (">1", con {0}) sí lo dice.
        "library-view-model.searching-covers.one",
    };

    [Fact]
    public void TodaFormaPluralEnResourcesResxTraeUnHuecoAdentroSalvoExcepcionesConocidas()
    {
        XDocument doc = XDocument.Load(CoreResxPath());
        var pluralSuffix = new Regex(@"^(?<baseKey>.+)\.(zero|one|two|few|many|other)$");

        List<string> sinHueco = [.. doc.Root!.Elements("data")
            .Select(e => (Key: e.Attribute("name")!.Value, Value: e.Element("value")?.Value ?? ""))
            .Where(entry => pluralSuffix.IsMatch(entry.Key) && !entry.Value.Contains("{0}")
                         && !KnownResxPluralFormsWithoutHole.Contains(entry.Key))
            .Select(entry => $"{entry.Key} ({entry.Value})")];

        Assert.True(sinHueco.Count == 0,
            "forma plural en Resources.resx sin {0} adentro, fuera de las excepciones conocidas: " +
            string.Join(", ", sinHueco.Take(10)));
    }

    private static Dictionary<string, string> ReadResw(string path)
    {
        XDocument doc = XDocument.Load(path);
        return doc.Root!.Elements("data")
            .ToDictionary(
                e => e.Attribute("name")!.Value,
                e => e.Element("value")?.Value ?? "",
                StringComparer.Ordinal);
    }

    private static List<string> ReadCsvKeys(string path, params string[] excludeKinds)
    {
        string[] lines = File.ReadAllLines(path);
        return [.. lines.Skip(1)
            .Where(line => line.Length > 0)
            .Select(ParseCsvLine)
            .Where(fields => !excludeKinds.Contains(fields[1]))
            .Select(fields => fields[0])];
    }

    /// <summary>
    /// El índice de una columna de <c>claves-compartidas.csv</c>, leído del
    /// ENCABEZADO -- nunca un índice fijo (ST-247, addendum A7b): la Mac
    /// agregó "texto en" entre "texto es" y "sitio Mac" sin avisar de la
    /// posición, corriendo el índice de todo lo que venía después. Mismo
    /// criterio que <c>ClavesCompartidasCsv.UpdateSitioWindows</c>
    /// (tools/ExtraerCadenasWindows), que ya lo hacía así desde el principio.
    /// </summary>
    private static int SharedCsvColumnIndex(string headerLine, string columnName)
    {
        int index = ParseCsvLine(headerLine).IndexOf(columnName);
        Assert.True(index >= 0, $"claves-compartidas.csv no tiene una columna \"{columnName}\" en su encabezado");
        return index;
    }

    /// <summary>Un parser de CSV mínimo: comillas dobles, con <c>""</c> como escape adentro.</summary>
    private static List<string> ParseCsvLine(string line)
    {
        var fields = new List<string>();
        var current = new System.Text.StringBuilder();
        bool inQuotes = false;

        for (int i = 0; i < line.Length; i++)
        {
            char c = line[i];

            if (inQuotes)
            {
                if (c == '"' && i + 1 < line.Length && line[i + 1] == '"') { current.Append('"'); i++; }
                else if (c == '"') inQuotes = false;
                else current.Append(c);
            }
            else
            {
                if (c == '"') inQuotes = true;
                else if (c == ',') { fields.Add(current.ToString()); current.Clear(); }
                else current.Append(c);
            }
        }

        fields.Add(current.ToString());
        return fields;
    }
}
