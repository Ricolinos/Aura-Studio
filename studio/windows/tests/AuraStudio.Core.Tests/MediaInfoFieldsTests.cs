using System.Globalization;
using AuraStudio.Core;
using AuraStudio.Core.Library;
using AuraStudio.Core.Resources;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// La hoja "Más información" identifica sus campos por lo que son, no por cómo
/// se llaman en pantalla (ST-247, B7d).
///
/// <para><b>El bug.</b> Las cajas de texto vivían en un diccionario con la
/// etiqueta de pantalla como llave: <c>Field("Álbum", …)</c> guardaba y
/// <c>Text("Álbum")</c> leía. Con la app en un solo idioma no se nota. Al
/// traducir, cualquiera de estas dos cosas rompe algo y ninguna avisa:</para>
///
/// <list type="number">
/// <item>Las dos puntas dejan de coincidir → <c>Text</c> devuelve cadena vacía
/// → el usuario edita el álbum, guarda, y el álbum se borra.</item>
/// <item>Dos campos caen en la misma etiqueta → el segundo pisa al primero en
/// el diccionario y uno de los dos deja de existir.</item>
/// </list>
///
/// <para>La llave es ahora <see cref="MediaInfoField"/>, así que (1) no puede
/// pasar. Contra (2) hay que mirar los seis idiomas, y eso es lo que hace la
/// primera prueba de acá: es el caso que ninguna otra ve, porque cada etiqueta
/// por separado está perfectamente bien.</para>
/// </summary>
public class MediaInfoFieldsTests
{
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

    public static TheoryData<string> Cultures()
    {
        TheoryData<string> data = [];
        foreach (AppLanguage language in AppLanguages.Translated) data.Add(language.Culture);
        return data;
    }

    /// <summary>
    /// Las formas que la hoja puede tomar. Lo que importa es qué campos se ven
    /// <b>juntos</b>: dos que nunca aparecen en la misma hoja pueden llamarse
    /// igual sin que pase nada.
    /// </summary>
    private static IEnumerable<(string Shape, IReadOnlyList<MediaInfoField> Fields)> Shapes()
    {
        yield return ("una canción", MediaInfoFields.ForMusic);
        yield return ("un episodio de serie", MediaInfoFields.ForVideo(isSeries: true));
        yield return ("una película", MediaInfoFields.ForVideo(isSeries: false));
    }

    [Theory]
    [MemberData(nameof(Cultures))]
    public void DosCamposDeLaMismaHojaNuncaSeLlamanIgual(string culture)
    {
        List<string> problems = [];

        foreach ((string shape, IReadOnlyList<MediaInfoField> fields) in Shapes())
        {
            Dictionary<string, MediaInfoField> seen = new(StringComparer.Ordinal);

            foreach (MediaInfoField field in fields)
            {
                string label = WithUiCulture(culture, () => MediaInfoFields.Label(field));
                if (label.Length == 0) continue;

                if (seen.TryGetValue(label, out MediaInfoField other))
                    problems.Add($"en {shape}, {other} y {field} se llaman «{label}»");
                else
                    seen[label] = field;
            }
        }

        Assert.True(problems.Count == 0,
            $"En {culture} dos campos de la misma hoja comparten etiqueta, y uno de los dos "
            + "dejaría de guardarse:\n" + string.Join("\n", problems));
    }

    /// <summary>
    /// Cada campo con etiqueta la tiene en todos los idiomas. Una que falte no
    /// falla: cae a la cultura neutra y sale en español en medio de un
    /// formulario en ruso.
    /// </summary>
    [Theory]
    [MemberData(nameof(Cultures))]
    public void CadaCampoTieneSuEtiquetaEnEseIdioma(string culture)
    {
        List<string> missing = [];

        foreach (MediaInfoField field in Enum.GetValues<MediaInfoField>())
        {
            if (MediaInfoFields.LabelKey(field) is null) continue;

            string label = WithUiCulture(culture, () => MediaInfoFields.Label(field));
            if (label.Length == 0 || label.StartsWith('!')) missing.Add(field.ToString());
        }

        Assert.True(missing.Count == 0,
            $"En {culture} estos campos se quedaron sin etiqueta: {string.Join(", ", missing)}");
    }

    /// <summary>
    /// La letra es el único campo sin etiqueta propia — la nombra el título de
    /// sección de arriba. Si mañana otro se queda sin la suya, es un olvido y no
    /// una decisión.
    /// </summary>
    [Fact]
    public void LaLetraEsElUnicoCampoSinEtiqueta() =>
        Assert.Equal(
            [MediaInfoField.Lyrics],
            Enum.GetValues<MediaInfoField>().Where(field => MediaInfoFields.LabelKey(field) is null));

    /// <summary>
    /// Todo campo aparece en alguna de las formas de la hoja. Uno que no
    /// apareciera en ninguna sería un identificador que el usuario nunca puede
    /// llenar y que <c>Read()</c> leería siempre vacío.
    /// </summary>
    [Fact]
    public void NingunCampoSeQuedaFueraDeLaHoja()
    {
        HashSet<MediaInfoField> shown = [.. Shapes().SelectMany(shape => shape.Fields)];

        Assert.Equal([], Enum.GetValues<MediaInfoField>().Where(field => !shown.Contains(field)));
    }

    private static MediaInfoDraft Blanking(MediaInfoDraft draft, MediaInfoField field) => field switch
    {
        MediaInfoField.Title => draft with { Title = "" },
        MediaInfoField.Artist => draft with { Artist = "" },
        MediaInfoField.Album => draft with { Album = "" },
        MediaInfoField.AlbumArtist => draft with { AlbumArtist = "" },
        MediaInfoField.TrackNumber => draft with { TrackNumber = "" },
        MediaInfoField.Year => draft with { Year = "" },
        MediaInfoField.Genre => draft with { Genre = "" },
        MediaInfoField.Composer => draft with { Composer = "" },
        MediaInfoField.Lyrics => draft with { Lyrics = "" },
        MediaInfoField.SeriesName => draft with { SeriesName = "" },
        MediaInfoField.Season => draft with { Season = "" },
        MediaInfoField.Episode => draft with { Episode = "" },
        _ => draft,
    };

    /// <summary>
    /// <c>RequiredForMusic</c> es exactamente lo que <c>IsCompleteForSync</c>
    /// exige, y se comprueba vaciando cada campo y viendo qué pasa — no
    /// comparando dos listas escritas a mano, que es lo que había: la vista
    /// llevaba `["Título", "Artista", "Álbum"]` copiado.
    ///
    /// <para>Lo que se rompía era discreto: si se agregara un obligatorio y
    /// nadie tocara la vista, el aviso de "falta algo" no aparecería mientras se
    /// escribe, solo al intentar guardar.</para>
    /// </summary>
    [Fact]
    public void LosObligatoriosSonLosQueDeVerdadImpidenGuardar()
    {
        MediaInfoDraft full = new()
        {
            Title = "Song", Artist = "Band", Album = "Record", AlbumArtist = "Band",
            TrackNumber = "3", Year = "1999", Genre = "Rock", Composer = "Someone",
            Lyrics = "…"
        };

        Assert.True(MediaInfoEdit.IsCompleteForSync(full, LibraryItemKind.Music),
            "el borrador de prueba tendría que estar completo; si no, esta prueba no comprueba nada");

        List<MediaInfoField> blocking =
        [
            .. MediaInfoFields.ForMusic.Where(field =>
                !MediaInfoEdit.IsCompleteForSync(Blanking(full, field), LibraryItemKind.Music))
        ];

        Assert.Equal(MediaInfoFields.RequiredForMusic, blocking);
    }

    /// <summary>
    /// Y el aviso de "falta algo" nombra esos tres campos igual que sus
    /// etiquetas.
    ///
    /// <para>Sin comparar mayúsculas: en francés la frase dice "le titre" donde
    /// la caja dice "Titre", y eso está bien. Lo que no puede pasar es que el
    /// aviso hable de un "intérprete" al lado de una caja rotulada "Artista" —
    /// ahí el usuario busca un campo que no está en la hoja.</para>
    /// </summary>
    [Theory]
    [MemberData(nameof(Cultures))]
    public void ElAvisoNombraLosCamposComoSeLlamanEnLaHoja(string culture)
    {
        (string reason, List<string> labels) = WithUiCulture(culture, () => (
            MediaInfoEdit.IncompleteReason,
            MediaInfoFields.RequiredForMusic.Select(MediaInfoFields.Label).ToList()));

        List<string> unnamed =
        [
            .. labels.Where(label => !reason.Contains(label, StringComparison.CurrentCultureIgnoreCase))
        ];

        Assert.True(unnamed.Count == 0,
            $"En {culture} el aviso no nombra {string.Join(", ", unnamed)} como los rotula la hoja:\n  {reason}");
    }

    /// <summary>
    /// La frase que manda a elegir la categoría Series deja un hueco para el
    /// nombre de la categoría en vez de escribirlo.
    ///
    /// <para>Escrito, en japonés diría "Series" y el selector de abajo diría
    /// 「シリーズ」: la frase mandaría a elegir algo que con ese nombre no está
    /// en la lista. Es el mismo fallo que vigila <c>SectionNamesTests</c>, y se
    /// evita de raíz pidiendo el nombre en vez de repetirlo.</para>
    /// </summary>
    [Theory]
    [MemberData(nameof(Cultures))]
    public void LaPistaDeLaCategoriaPideElNombreEnVezDeEscribirlo(string culture)
    {
        string template = WithUiCulture(culture, () => Strings.Get("media-info-dialog.series-hint"));

        Assert.Contains("{0}", template, StringComparison.Ordinal);

        string hint = WithUiCulture(culture,
            () => Strings.Format("media-info-dialog.series-hint", MediaCategory.Series.LocalizedName()));

        string category = WithUiCulture(culture, () => MediaCategory.Series.LocalizedName());

        Assert.Contains(category, hint, StringComparison.Ordinal);
    }
}
