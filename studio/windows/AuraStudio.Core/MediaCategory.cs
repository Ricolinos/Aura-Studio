using System.Text.Json.Serialization;

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
/// Los nombres con los que una categoría aparece en pantalla y, desde D-228, se
/// <b>guarda</b> en el catálogo — por eso hay que reconocer también el nombre en
/// inglés: un catálogo escrito por la app de macOS en inglés dice "Movies", y
/// tratarlo como una categoría desconocida dejaría esas películas fuera de la
/// vista de Películas.
/// </summary>
public static class MediaCategoryNames
{
    public static string DisplayNameSpanish(this MediaCategory category) => category switch
    {
        MediaCategory.Series => "Series",
        MediaCategory.Movies => "Películas",
        _ => "Videos"
    };

    public static string DisplayNameEnglish(this MediaCategory category) => category switch
    {
        MediaCategory.Series => "Series",
        MediaCategory.Movies => "Movies",
        _ => "Videos"
    };

    /// <summary>
    /// Aura Studio para Windows muestra un solo idioma (regla del repo), así que
    /// el nombre visible es siempre el español.
    /// </summary>
    public static string DisplayName(this MediaCategory category) => category.DisplayNameSpanish();

    /// <summary>
    /// Las tres categorías de video, en el orden en que se muestran. Conjunto
    /// fijo, a diferencia de las colecciones de fotos, que las edita el usuario
    /// (D-228).
    /// </summary>
    public static readonly IReadOnlyList<string> VideoCategories =
    [
        MediaCategory.Videos.DisplayNameSpanish(),
        MediaCategory.Series.DisplayNameSpanish(),
        MediaCategory.Movies.DisplayNameSpanish()
    ];

    public static bool IsSeriesCategory(string? category) =>
        category == MediaCategory.Series.DisplayNameSpanish()
        || category == MediaCategory.Series.DisplayNameEnglish();

    public static bool IsMoviesCategory(string? category) =>
        category == MediaCategory.Movies.DisplayNameSpanish()
        || category == MediaCategory.Movies.DisplayNameEnglish();
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
