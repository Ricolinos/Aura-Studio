using AuraStudio.Core.Resources;

namespace AuraStudio.Core.Library;

/// <summary>
/// Los campos de la hoja "Más información", cada uno con un nombre que no
/// cambia (ST-247, B7d).
/// </summary>
public enum MediaInfoField
{
    Title,
    Artist,
    Album,
    AlbumArtist,
    TrackNumber,
    Year,
    Genre,
    Composer,
    Lyrics,
    SeriesName,
    Season,
    Episode,
}

/// <summary>
/// Qué campos tiene la hoja, cómo se llama cada uno en pantalla, y cuáles hacen
/// falta para poder guardar.
///
/// <para><b>El bug que trajo esto.</b> La hoja guardaba sus cajas de texto en un
/// diccionario <b>con la etiqueta de pantalla como llave</b>: <c>Field("Álbum",
/// …)</c> guardaba y <c>Text("Álbum")</c> leía. Mientras la app habló un solo
/// idioma funcionó. Traducir esas etiquetas lo rompe de dos maneras, y ninguna
/// avisa:</para>
///
/// <list type="bullet">
/// <item>Si las dos puntas no quedan idénticas, <c>Text</c> no encuentra la caja
/// y devuelve cadena vacía. El usuario edita el álbum, guarda, y <b>el álbum se
/// borra</b>.</item>
/// <item>Si dos campos distintos terminan con la misma etiqueta —cosa que pasa
/// al traducir, donde el español distingue con un paréntesis y otro idioma
/// no— el segundo pisa al primero en el diccionario y uno de los dos campos
/// deja de existir.</item>
/// </list>
///
/// <para>Y había un tercer camino, más burdo: la línea que enganchaba la
/// validación usaba <c>fields[llave]</c> sin <c>TryGetValue</c>, así que una
/// etiqueta que no coincidiera no daba cadena vacía sino una excepción al abrir
/// la hoja.</para>
///
/// <para>Por eso la llave ahora es <see cref="MediaInfoField"/> —un valor del
/// programa, que no se traduce— y la etiqueta es solo lo que se pinta. Vive en
/// Core y no en la vista para que se pueda comprobar en los seis idiomas sin
/// abrir una ventana.</para>
/// </summary>
public static class MediaInfoFields
{
    /// <summary>
    /// La clave del recurso con el nombre del campo, o <c>null</c> si el campo
    /// no lleva etiqueta propia.
    ///
    /// <para>La letra es el único caso: su caja va debajo del título de sección
    /// "Letra (opcional)", que ya la nombra, y ponerle además una etiqueta
    /// repetiría la palabra dos veces seguidas.</para>
    /// </summary>
    public static string? LabelKey(MediaInfoField field) => field switch
    {
        MediaInfoField.Title => "media-info-dialog.field-title",
        MediaInfoField.Artist => "media-info-dialog.field-artist",
        MediaInfoField.Album => "media-info-dialog.field-album",
        MediaInfoField.AlbumArtist => "media-info-dialog.field-album-artist",
        MediaInfoField.TrackNumber => "media-info-dialog.field-track-number",
        MediaInfoField.Year => "media-info-dialog.field-year",
        MediaInfoField.Genre => "media-info-dialog.field-genre",
        MediaInfoField.Composer => "media-info-dialog.field-composer",
        MediaInfoField.SeriesName => "media-info-dialog.field-series-name",
        MediaInfoField.Season => "media-info-dialog.field-season",
        MediaInfoField.Episode => "media-info-dialog.field-episode",
        MediaInfoField.Lyrics => null,
        _ => null,
    };

    /// <summary>El nombre del campo en el idioma de la interfaz, o "" si no lleva.</summary>
    public static string Label(MediaInfoField field) =>
        LabelKey(field) is { } key ? Strings.Get(key) : "";

    /// <summary>Los campos de una canción, en el orden en que se muestran.</summary>
    public static IReadOnlyList<MediaInfoField> ForMusic =>
    [
        MediaInfoField.Title,
        MediaInfoField.Artist,
        MediaInfoField.Album,
        MediaInfoField.AlbumArtist,
        MediaInfoField.TrackNumber,
        MediaInfoField.Year,
        MediaInfoField.Genre,
        MediaInfoField.Composer,
        MediaInfoField.Lyrics,
    ];

    /// <summary>
    /// Los campos de un video. Los tres de serie solo aparecen cuando el
    /// elemento está en la categoría Series: en una película no significan nada.
    /// </summary>
    public static IReadOnlyList<MediaInfoField> ForVideo(bool isSeries) => isSeries
        ?
        [
            MediaInfoField.Title,
            MediaInfoField.SeriesName,
            MediaInfoField.Season,
            MediaInfoField.Episode,
        ]
        : [MediaInfoField.Title];

    /// <summary>
    /// Los campos sin los que no se puede guardar una canción.
    ///
    /// <para>Está acá, y no escrito otra vez en la vista, porque la vista lo
    /// necesita para saber a cuáles engancharle la revalidación mientras se
    /// escribe. Ese arreglo estaba copiado a mano —tres cadenas sueltas— y una
    /// prueba comprueba que esta lista es exactamente la que
    /// <see cref="MediaInfoEdit.IsCompleteForSync"/> exige: si un día se agrega
    /// un obligatorio y nadie toca la vista, el aviso de "falta algo" no
    /// aparecería hasta cerrar la hoja.</para>
    /// </summary>
    public static IReadOnlyList<MediaInfoField> RequiredForMusic =>
    [
        MediaInfoField.Title,
        MediaInfoField.Artist,
        MediaInfoField.Album,
    ];
}
