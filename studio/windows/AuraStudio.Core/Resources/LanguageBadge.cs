namespace AuraStudio.Core.Resources;

/// <summary>
/// La marca "(beta)" del selector de idioma y la línea que la explica
/// (ST-247, B7c/B7d).
///
/// <para><b>Por qué está en Core.</b> Vivía en <c>LanguageOption</c>, en la capa
/// de la app, donde no se puede comprobar sin abrir una ventana. Y es una
/// decisión, no un adorno: dice si la app admite delante del usuario que ese
/// idioma no lo revisó nadie. Ofrecer alemán sin esa línea, en pantallas que
/// formatean discos, es exactamente lo que la Maestra prohibió.</para>
///
/// <para><b>La marca no depende de <c>Offered</c>, y eso es a propósito.</b>
/// Depende solo de <see cref="AppLanguage.ReviewedByHumans"/>. Así, el día que
/// B7d encienda los cuatro, la marca ya está decidida y no hay que acordarse de
/// nada: encender un idioma no puede, por construcción, encenderlo sin su
/// advertencia.</para>
/// </summary>
public static class LanguageBadge
{
    public const string MarkKey = "app-strings.language-beta-mark";

    public const string DetailKey = "app-strings.language-beta-detail";

    /// <summary>Si el selector tiene que marcar este idioma.</summary>
    public static bool ShowsMark(AppLanguage language) => !language.ReviewedByHumans;

    /// <summary>La marca, o cadena vacía si el idioma está revisado.</summary>
    public static string Mark(AppLanguage language) =>
        ShowsMark(language) ? Strings.Get(MarkKey) : "";

    /// <summary>
    /// La línea que dice por qué está marcado, o <c>null</c> si no lo está.
    ///
    /// <para>Es <c>null</c> y no cadena vacía a propósito: una línea vacía se
    /// dibuja igual —con su espacio— y deja un hueco en la pantalla que nadie
    /// entiende.</para>
    /// </summary>
    public static string? Detail(AppLanguage language) =>
        ShowsMark(language) ? Strings.Get(DetailKey) : null;
}
