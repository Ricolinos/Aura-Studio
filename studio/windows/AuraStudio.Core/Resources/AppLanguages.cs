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
/// <param name="Built">
/// Si su archivo de textos existe y se compila. El español es la cultura neutra
/// —va dentro del ensamblado— y los demás salen como satélites.
///
/// <para><b>Que se genere no es que se ofrezca.</b> Son dos hechos distintos y
/// se separaron a propósito (ST-247, B7c): un idioma puede estar traducido,
/// compilado y viajando dentro del instalador sin que el selector lo muestre
/// todavía. Es el estado de los cuatro de B7c: la extracción de B7a está en los
/// seis idiomas, pero unas trescientas frases —instalador, errores de disco,
/// permisos— siguen en español porque quedaron fuera de esa extracción. Ofrecer
/// el idioma así sería prometer una app en alemán que a mitad del formateo
/// habla en español.</para>
///
/// <para>Y se generan igualmente porque el instalador tiene que llevarlos y
/// medirlos: cuando B7d termine, encenderlos es cambiar <c>Offered</c>, no
/// rehacer el paquete.</para>
/// </param>
/// <param name="Offered">
/// Si el selector lo muestra y la app puede arrancar en él.
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
public sealed record AppLanguage(string Culture, string Endonym, bool Built, bool Offered, bool ReviewedByHumans);

/// <summary>
/// Los idiomas de Aura Studio para Windows (ST-247, B7b).
///
/// <para>La lista está completa —los seis— y cada uno dice dos cosas por
/// separado: si su archivo se compila (<c>Built</c>) y si el selector lo
/// muestra (<c>Offered</c>). Así el instalador sabe qué carpetas exigir, el
/// selector sabe qué ofrecer, y encender un idioma cuando termine su
/// traducción es cambiar un <c>false</c>, no salir a buscar en cuántos lados
/// estaba escrita la lista.</para>
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
        new("es", "Español", Built: true, Offered: true, ReviewedByHumans: true),
        new("en", "English", Built: true, Offered: true, ReviewedByHumans: true),

        // B7c los dejó traducidos, compilados y viajando en el instalador, y sin
        // ofrecer. Lo que falta no es la traducción de B7a —esa está en los seis
        // idiomas— sino las ~300 frases que quedaron fuera de esa extracción:
        // instalador, errores de disco, permisos. Encenderlos ahora sería
        // prometer una app en alemán que a mitad del formateo habla en español.
        // Las enciende B7d, cambiando este Offered.
        new("de", "Deutsch", Built: true, Offered: false, ReviewedByHumans: false),
        new("fr", "Français", Built: true, Offered: false, ReviewedByHumans: false),
        new("ja", "日本語", Built: true, Offered: false, ReviewedByHumans: false),
        new("ru", "Русский", Built: true, Offered: false, ReviewedByHumans: false),
    ];

    /// <summary>Lo que el selector puede ofrecer hoy.</summary>
    public static IReadOnlyList<AppLanguage> Available => [.. All.Where(language => language.Offered)];

    /// <summary>
    /// Los idiomas cuyos textos existen y hay que revisar.
    ///
    /// <para>Es lo que enumeran las pruebas que leen los <c>.resx</c>, y no
    /// <see cref="Available"/> a propósito: si apagar <c>Offered</c> apagara
    /// también su verificación, esos cuatro archivos se quedarían meses sin
    /// que nadie los mire y el día que se enciendan se publica lo que haya
    /// quedado. Una prueba que deja de comprobar algo se ve igual que una que
    /// lo comprueba y pasa.</para>
    /// </summary>
    public static IReadOnlyList<AppLanguage> Translated => [.. All.Where(language => language.Built)];

    /// <summary>
    /// Las culturas que tienen que existir como carpeta de satélite junto al
    /// ejecutable. El español no está: va dentro del ensamblado.
    ///
    /// <para>Son las que se <b>generan</b>, no las que se ofrecen. Un idioma
    /// traducido pero todavía sin ofrecer viaja igual dentro del instalador —así
    /// se mide su tamaño y así encenderlo después no obliga a rehacer el
    /// paquete—, y si faltara, el instalador tiene que detenerse igual: el
    /// archivo no está porque algo salió mal, no porque alguien lo decidiera.</para>
    ///
    /// <para>Esta es la lista contra la que se comprueba el publish y el
    /// instalador, y por eso vive acá y no escrita a mano en un script: una
    /// lista que se copia es una lista que se desincroniza.</para>
    /// </summary>
    public static IReadOnlyList<string> RequiredSatelliteCultures =>
        [.. All.Where(language => language.Built && language.Culture != NeutralCulture)
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
                language => language.Offered
                            && string.Equals(language.Culture, candidate.Name, StringComparison.OrdinalIgnoreCase));

            if (found is not null) return found;
        }

        return null;
    }
}
