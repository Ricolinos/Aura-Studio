namespace AuraStudio.Core.Resources;

/// <summary>
/// Qué textos son <b>críticos</b>: los que, mal traducidos, hacen que alguien
/// pierda archivos o rompa su iPod (ST-247, decisión de la Maestra para B7c).
///
/// <para><b>Para qué sirve esta lista.</b> B7c trae japonés, alemán, ruso y
/// francés traducidos por una máquina, y nadie en el proyecto lee esos cuatro
/// idiomas. La verificación acordada es retrotraducir al español —el mecánico,
/// sin ver el original— y comparar el sentido. Retrotraducir seiscientas frases
/// cuatro veces no es realista; retrotraducir <b>estas</b> sí, y son
/// exactamente aquellas donde una traducción torcida cuesta caro.</para>
///
/// <para><b>El criterio</b>, tal como quedó fijado: todo lo que borra, mueve,
/// instala firmware, migra o convierte, más los ajustes de almacenamiento y de
/// calidad. Un botón de menú mal traducido molesta; un diálogo de confirmación
/// mal traducido hace que alguien apriete "sí" creyendo otra cosa.</para>
///
/// <para>La lista es de <b>prefijos</b> y no de claves una por una a propósito:
/// una clave nueva en una familia crítica —otro mensaje del instalador, otra
/// rama de la confirmación de borrado— entra sola. Al revés sería peor: la
/// clave nueva quedaría fuera en silencio, que es justo lo que no se puede
/// permitir en este grupo.</para>
/// </summary>
public static class CriticalStrings
{
    /// <summary>
    /// Familias de claves críticas, con el porqué de cada una. Basta que la
    /// clave empiece con uno de estos prefijos.
    /// </summary>
    public static readonly IReadOnlyList<(string Prefix, string Reason)> Families =
    [
        // Borra archivos, o los manda a la Papelera.
        ("app-strings.delete-confirm", "el diálogo que decide si un archivo se borra"),
        ("app-strings.orphans", "borra archivos del disco del usuario"),
        ("orphans-", "borra archivos del disco del usuario"),
        ("similar-items-view-model.items-removed", "dice qué pasó con lo que se quitó"),
        ("context-menu.eliminar", "acciones de borrado del menú"),
        ("context-menu.quitar", "acciones de quitar del menú"),

        // Instala firmware: formatea el disco y reescribe el arranque.
        ("app-strings.installer-", "formatea el iPod y graba su arranque"),
        ("app-strings.bootloader-update-", "reescribe el arranque del iPod"),
        ("app-strings.dfu-driver-", "condiciona entrar en modo DFU"),
        ("device-safety-validator.", "las razones por las que NO se escribe en el disco"),
        ("installer-page.", "pantalla del instalador"),

        // B7d: lo que hasta ahora vivía como literal dentro del código del
        // instalador. Entran acá el mismo día que salen a recursos — una
        // familia crítica que se extrae y no se declara crítica es una que se
        // traduce sin que nadie la retrotraduzca.
        ("installer-error.", "los errores del asistente que formatea y graba el arranque"),
        ("privileged.", "lo que hace y responde el proceso con permisos de administrador"),
        ("firmware-artifacts.", "decide si los archivos del firmware son de fiar"),
        ("dfu-flash.", "el grabado del arranque por DFU"),

        // Encontradas por la segunda barrida, que no usa el léxico del
        // trinquete. Las nueve de `disk-abort.` estaban clasificadas como
        // bitácora y son justamente lo contrario: son el motivo que el usuario
        // lee cuando el formateo SE DETIENE, o sea la familia que esta misma
        // tabla ya nombra dos renglones más arriba.
        ("disk-abort.", "las razones por las que NO se escribe en el disco"),
        ("firmware-tree.", "escribe el árbol del firmware en el iPod"),
        ("firmware-switcher.", "estaciona y despierta el firmware del iPod"),

        // Mueve, migra o convierte archivos del usuario.
        ("library-view-model.copy", "copia archivos a la biblioteca"),
        ("library-view-model.copying-files", "copia archivos a la biblioteca"),
        ("library-view-model.copied-files", "copia archivos a la biblioteca"),
        ("library-view-model.migration-", "migra una biblioteca anterior"),
        ("settings-page.migrar-", "migra una biblioteca anterior"),
        ("shell-page.migrar-", "migra una biblioteca anterior"),
        ("shell-page.esta-biblioteca-viene", "avisa de que hay que migrar"),

        // Ajustes de almacenamiento y de calidad: deciden si Aura se queda con
        // una copia de los archivos del usuario y en qué formato.
        ("storage-", "decide si Aura copia los archivos del usuario o los referencia"),
        ("settings-page.copiar-medios", "decide si Aura copia los archivos del usuario"),
        ("settings-page.carpeta-biblioteca", "dónde vive la biblioteca"),
        ("settings-page.carpeta-nueva", "qué pasa al cambiar de carpeta"),
        ("settings-page.cambiar-carpeta", "qué pasa al cambiar de carpeta"),
        ("settings-page.carpetas-externas", "qué pasa al quitar una carpeta vinculada"),
        ("music-settings-view.calidad", "decide en qué formato queda la música"),
        ("music-settings-view.comprimir", "decide en qué formato queda la música"),
        ("settings-page.calidad-imagen", "decide en qué calidad quedan las fotos"),
        ("settings-page.mantener-formato", "decide en qué formato queda la música"),
        ("settings-page.wav-aiff", "decide en qué formato queda la música"),
        ("settings-page.optimizar-espacio", "decide en qué calidad quedan las fotos"),
        ("settings-page.version-hd", "decide en qué calidad quedan las fotos"),
    ];

    /// <summary>Si una clave es crítica.</summary>
    public static bool IsCritical(string key) =>
        Families.Any(family => key.StartsWith(family.Prefix, StringComparison.Ordinal));

    /// <summary>Por qué lo es, o <c>null</c> si no lo es.</summary>
    public static string? ReasonFor(string key) =>
        Families.FirstOrDefault(family => key.StartsWith(family.Prefix, StringComparison.Ordinal)).Reason;
}
