using System.Text.Json.Serialization;
using AuraStudio.Core.Resources;

namespace AuraStudio.Core;

/// <summary>
/// Categoría FIJA de un video DENTRO de la biblioteca de Aura Studio
/// (encargo del dueño, 2026-08-13: "dividirlos [videos] por Videos, Series,
/// Películas"). Es un dato de organización de la app, no de la carpeta donde
/// termina en el iPod — `LibrarySync` sigue escribiendo `Videos/` plana
/// porque el navegador del firmware todavía no recorre subcarpetas (ver
/// `AppPreferences.organizeVideosByCategory`).
///
/// D-228: las colecciones de FOTOS dejaron de vivir acá — el dueño pidió que
/// esas fueran editables por el usuario (agregar/quitar sin tocar código), así
/// que pasaron a `AppPreferences.photoCollections` (un `[String]` libre).
/// Video se queda con el enum a propósito: su conjunto es fijo, nunca hay una
/// cuarta categoría, y el compilador garantiza que no aparezca un valor
/// inválido.
/// </summary>
public enum MediaCategory
{
    /// <summary>Duración media, sin clasificar como película. Default cuando no hay duración o no aplica ningún otro caso.</summary>
    [JsonStringEnumMemberName("videos")]
    Videos,

    /// <summary>Sin heurística automática (D-228): no hay forma confiable de distinguir "esto es un episodio de una serie" solo por duración, así que el usuario la asigna a mano desde el picker de categoría.</summary>
    [JsonStringEnumMemberName("series")]
    Series,

    /// <summary>Duración larga (&gt; 40 min) — probablemente una película o episodio completo.</summary>
    [JsonStringEnumMemberName("movies")]
    Movies,
}

/// <summary>
/// El nombre de una categoría, que son <b>dos cosas distintas</b> y hay que no
/// confundirlas nunca (ST-247, lección de A7a en la Mac).
///
/// <list type="bullet">
/// <item><b>El dato</b> — lo que se guarda en <c>item.Category</c> del catálogo
/// compartido (D-228, D-283) y contra lo que se compara para agrupar,
/// sincronizar y armar los índices del firmware. Es <b>siempre el español</b>,
/// pase lo que pase con el idioma de la app.</item>
/// <item><b>La etiqueta</b> — lo que el usuario lee en el menú de categoría y
/// en los títulos. Esa sí cambia con el idioma, y sale del archivo de
/// recursos.</item>
/// </list>
///
/// <para><b>Por qué importa tanto.</b> La app de macOS guardaba el nombre en el
/// idioma activo. Con un solo idioma eso no se nota; con seis, el mismo video
/// queda como "Series" en una máquina y "Serien" en otra, el catálogo que
/// viaja entre las dos deja de coincidir consigo mismo y el firmware arma los
/// índices con dos categorías donde hay una. El texto que se ve no puede ser
/// el dato que se guarda.</para>
///
/// <para>El nombre en inglés se sigue reconociendo al <b>leer</b>: un catálogo
/// que escribió la app de macOS cuando guardaba en inglés dice "Movies", y
/// tratarlo como categoría desconocida dejaría esas películas fuera de la vista
/// de Películas. Se reconoce, no se escribe.</para>
/// </summary>
public static class MediaCategoryNames
{
    /// <summary>
    /// El dato: lo que se guarda y lo que se compara. Español siempre.
    /// </summary>
    public static string CatalogName(this MediaCategory category) => category switch
    {
        MediaCategory.Series => "Series",
        MediaCategory.Movies => "Películas",
        _ => "Videos"
    };

    /// <summary>
    /// El nombre que escribía la app de macOS cuando guardaba en inglés. Se
    /// reconoce al leer un catálogo viejo; nunca se escribe.
    /// </summary>
    public static string LegacyEnglishName(this MediaCategory category) => category switch
    {
        MediaCategory.Series => "Series",
        MediaCategory.Movies => "Movies",
        _ => "Videos"
    };

    /// <summary>La etiqueta: lo que el usuario lee, en el idioma de la app.</summary>
    public static string LocalizedName(this MediaCategory category) => category switch
    {
        MediaCategory.Series => Strings.Get("media-category.series"),
        MediaCategory.Movies => Strings.Get("media-category.movies"),
        _ => Strings.Get("media-category.videos")
    };

    /// <summary>
    /// La etiqueta de un valor <b>ya guardado</b>.
    ///
    /// <para>Lo que no reconoce lo devuelve tal cual, y eso es a propósito: las
    /// colecciones de fotos las escribe el usuario (D-228) y una categoría que
    /// no es de las tres fijas es un dato suyo. El nombre que alguien le puso a
    /// su colección no se traduce — no es texto de la app.</para>
    /// </summary>
    public static string LocalizedNameOf(string? category) =>
        IsSeriesCategory(category) ? MediaCategory.Series.LocalizedName()
        : IsMoviesCategory(category) ? MediaCategory.Movies.LocalizedName()
        : IsVideosCategory(category) ? MediaCategory.Videos.LocalizedName()
        : category ?? "";

    /// <summary>
    /// Las tres categorías de video, en el orden en que se muestran, <b>como
    /// dato</b>. Conjunto fijo, a diferencia de las colecciones de fotos, que
    /// las edita el usuario (D-228).
    /// </summary>
    public static readonly IReadOnlyList<string> VideoCategories =
    [
        MediaCategory.Videos.CatalogName(),
        MediaCategory.Series.CatalogName(),
        MediaCategory.Movies.CatalogName()
    ];

    public static bool IsSeriesCategory(string? category) =>
        category == MediaCategory.Series.CatalogName()
        || category == MediaCategory.Series.LegacyEnglishName();

    public static bool IsMoviesCategory(string? category) =>
        category == MediaCategory.Movies.CatalogName()
        || category == MediaCategory.Movies.LegacyEnglishName();

    public static bool IsVideosCategory(string? category) =>
        category == MediaCategory.Videos.CatalogName()
        || category == MediaCategory.Videos.LegacyEnglishName();
}

/// <summary>
/// Heurísticas de clasificación automática — solo una sugerencia inicial, el
/// usuario la puede corregir a mano en la biblioteca (Fase 1B). Funciones
/// puras/testables por separado de donde se invocan (ImageIO/ffmpeg necesitan
/// el archivo real en disco).
/// </summary>
public static class MediaCategoryHeuristics
{
    /// <summary>
    /// Nombres de software que identifican una imagen como generada por IA,
    /// buscados sin distinguir mayúsculas dentro del tag EXIF/TIFF "Software"
    /// o "Artist". Lista deliberadamente chica: falsos negativos (una IA no
    /// listada cae en "Fotos" o "Imágenes") son preferibles a falsos positivos.
    /// </summary>
    public static readonly string[] AiGeneratorSoftwareNames =
    {
        "midjourney", "dall-e", "dalle", "stable diffusion", "stablediffusion",
        "firefly", "leonardo.ai", "leonardo ai", "ideogram", "runway",
    };

    /// <summary>
    /// D-228: devuelve un `String` (no `MediaCategory`) porque las colecciones
    /// de foto ahora son la lista libre de `AppPreferences.photoCollections` —
    /// estos tres nombres literales coinciden con el default de esa lista a
    /// propósito, para que "recién instalado, sin tocar nada" clasifique
    /// exactamente igual que antes. No se usa `AppLanguageResolver`/`displayName`
    /// acá: el resto de la app (fuera de Ajustes/barra lateral) sigue en español
    /// fijo (ver AppStrings.swift), y estos nombres tienen que coincidir con el
    /// default de una preferencia que tampoco se traduce.
    /// </summary>
    public static string ClassifyPhoto(string? softwareTag, bool hasCameraExif)
    {
        if (softwareTag is not null)
        {
            string lowered = softwareTag.ToLowerInvariant();
            foreach (string name in AiGeneratorSoftwareNames)
            {
                if (lowered.Contains(name, StringComparison.Ordinal))
                {
                    return "IA";
                }
            }
        }
        return hasCameraExif ? "Fotos" : "Imágenes";
    }

    /// <summary>
    /// D-228: se eliminó el corte de "casero" (&lt;= 3 min) — no hay heurística
    /// confiable para eso por duración sola, así que ya no se intenta: solo
    /// película (larga) vs. video (todo lo demás). El usuario asigna "Series"
    /// a mano.
    /// </summary>
    public static MediaCategory ClassifyVideo(double? durationSeconds)
    {
        if (durationSeconds is null || durationSeconds <= 0)
        {
            return MediaCategory.Videos;
        }
        if (durationSeconds > 2400)
        {
            return MediaCategory.Movies;
        }
        return MediaCategory.Videos;
    }
}
