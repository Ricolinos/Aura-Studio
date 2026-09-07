using System.Globalization;

namespace AuraStudio.Core.Resources;

/// <summary>
/// Un idioma que la app puede hablar.
/// </summary>
/// <param name="Culture">
/// El nombre de cultura de .NET (<c>es</c>, <c>en</c>, …). Es también el nombre
/// de la carpeta del satélite, así que no es solo una etiqueta: es la ruta.
/// </param>
/// <param name="Endonym">
/// El nombre del idioma <b>en ese idioma</b>: "Español", "English", "Deutsch".
///
/// <para>No es un recurso y no se traduce nunca, igual que el nombre de una
/// colección de fotos es dato del usuario (ST-247). Un selector de idioma que
/// traduce los nombres es inservible para la única persona que lo necesita: la
/// que abrió la app en un idioma que no lee y busca el suyo en la lista. Si
/// dijera "Spanisch" en alemán, quien busca "Español" no lo encuentra.</para>
/// </param>
/// <param name="Ships">
/// Si hoy existe el archivo de ese idioma. El español es la cultura neutra
/// —va dentro del ensamblado— y los demás son satélites.
/// </param>
/// <param name="ReviewedByHumans">
/// Si una persona que habla el idioma revisó el texto.
///
/// <para>Español e inglés sí. Los cuatro de B7c van a llegar traducidos por una
/// máquina, y hasta que alguien los apruebe la app <b>lo dice</b>: son pantallas
/// que formatean discos y mandan archivos a la Papelera, y una frase que
/// promete algo distinto de lo que hace, en un idioma que nadie del equipo
/// verifica, es peor que no ofrecer ese idioma.</para>
/// </param>
public sealed record AppLanguage(string Culture, string Endonym, bool Ships, bool ReviewedByHumans);

/// <summary>
/// Los idiomas de Aura Studio para Windows (ST-247, B7b).
///
/// <para>La lista está completa desde ya —los seis— y cada uno dice si su
/// archivo existe. Así el selector muestra lo que hay, la comprobación del
/// instalador sabe qué carpetas exigir, y agregar un idioma en B7c es cambiar
/// un <c>false</c> por un <c>true</c> junto con su <c>.resx</c>, no salir a
/// buscar en cuántos lados estaba escrita la lista.</para>
/// </summary>
public static class AppLanguages
{
    /// <summary>
    /// El español va <b>dentro</b> del ensamblado, no en un satélite: si mañana
    /// falta un archivo de idioma, la app cae en español y nunca en blanco.
    /// </summary>
    public const string NeutralCulture = "es";

    public static readonly IReadOnlyList<AppLanguage> All =
    [
        new("es", "Español", Ships: true, ReviewedByHumans: true),
        new("en", "English", Ships: true, ReviewedByHumans: true),

        // B7c: traducidos por una máquina y todavía sin revisar por nadie que
        // hable el idioma. Se ofrecen igual, pero el selector los marca "(beta)"
        // y dice por qué — ofrecer un idioma sin decir que nadie lo revisó, en
        // pantallas que formatean discos, sería justo lo que no se puede hacer.
        new("de", "Deutsch", Ships: true, ReviewedByHumans: false),
        new("fr", "Français", Ships: true, ReviewedByHumans: false),
        new("ja", "日本語", Ships: true, ReviewedByHumans: false),
        new("ru", "Русский", Ships: true, ReviewedByHumans: false),
    ];

    /// <summary>Lo que el selector puede ofrecer hoy.</summary>
    public static IReadOnlyList<AppLanguage> Available => [.. All.Where(language => language.Ships)];

    /// <summary>
    /// Las culturas que tienen que existir como carpeta de satélite junto al
    /// ejecutable. El español no está: va dentro del ensamblado.
    ///
    /// <para>Esta es la lista contra la que se comprueba el publish y el
    /// instalador, y por eso vive acá y no escrita a mano en un script: una
    /// lista que se copia es una lista que se desincroniza.</para>
    /// </summary>
    public static IReadOnlyList<string> RequiredSatelliteCultures =>
        [.. All.Where(language => language.Ships && language.Culture != NeutralCulture)
               .Select(language => language.Culture)];

    /// <summary>
    /// El idioma que le toca a una cultura, o <c>null</c> si no se ofrece.
    ///
    /// <para>Compara por el idioma y no por el país: quien tiene Windows en
    /// <c>en-GB</c> quiere el inglés, no el español porque no exista una
    /// entrada <c>en-GB</c>.</para>
    /// </summary>
    public static AppLanguage? For(CultureInfo culture)
    {
        for (CultureInfo? candidate = culture;
             candidate is not null && candidate != CultureInfo.InvariantCulture;
             candidate = candidate.Parent)
        {
            AppLanguage? found = All.FirstOrDefault(
                language => language.Ships
                            && string.Equals(language.Culture, candidate.Name, StringComparison.OrdinalIgnoreCase));

            if (found is not null) return found;
        }

        return null;
    }
}
