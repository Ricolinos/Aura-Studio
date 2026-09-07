namespace AuraStudio.Core.Resources;

/// <summary>
/// Qué se le ofrece al usuario después de cambiar el idioma.
/// </summary>
/// <param name="CanCloseNow">
/// Si se le puede ofrecer el botón de cerrar. Falso cuando hay trabajo en
/// curso.
/// </param>
/// <param name="DetailKey">
/// La clave del texto que explica qué va a pasar. Cambia con el caso: no es lo
/// mismo "ciérrala cuando quieras" que "no la cierres ahora".
/// </param>
public sealed record LanguageChangeAdvice(bool CanCloseNow, string DetailKey);

/// <summary>
/// El aviso que sigue a cambiar el idioma (ST-247, B7b).
///
/// <para><b>Con trabajo en curso no se ofrece cerrar.</b> El centro de tareas
/// puede estar sincronizando el iPod, convirtiendo un video, migrando una
/// biblioteca o instalando firmware. Cerrar en medio de cualquiera de esas deja
/// algo a medias en el disco de alguien — y lo dejaría por un cambio de idioma,
/// que es lo más prescindible que hay. Así que el botón desaparece y el aviso
/// dice la verdad: el ajuste ya está guardado y vale la próxima vez.</para>
///
/// <para>Desaparece, no se deshabilita. Un botón gris invita a preguntarse qué
/// falta para que se encienda; que no esté, con una frase que explica por qué,
/// no deja esa duda.</para>
///
/// <para>Vive en Core y no en la pantalla porque es una <b>decisión</b>, y una
/// decisión se puede probar sin abrir una ventana. La pantalla solo la
/// obedece.</para>
/// </summary>
public static class LanguageChangePrompt
{
    /// <summary>Se puede cerrar: el ajuste vale al volver a abrir.</summary>
    public const string SafeToCloseKey = "app-strings.language-restart-detail";

    /// <summary>Hay trabajo en curso: el ajuste queda guardado y ya.</summary>
    public const string BusyKey = "app-strings.language-restart-busy";

    /// <param name="runningTasks">
    /// Cuántas tareas hay en el centro. Cero es "ninguna"; cualquier otra cosa
    /// es trabajo que puede estar tocando archivos.
    /// </param>
    public static LanguageChangeAdvice For(int runningTasks) =>
        runningTasks > 0
            ? new LanguageChangeAdvice(CanCloseNow: false, DetailKey: BusyKey)
            : new LanguageChangeAdvice(CanCloseNow: true, DetailKey: SafeToCloseKey);
}
