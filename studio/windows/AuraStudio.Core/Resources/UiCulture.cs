using System.Globalization;

namespace AuraStudio.Core.Resources;

/// <summary>
/// Cómo un proceso le dice a otro en qué idioma contestar (ST-247, B7d).
///
/// <para><b>El problema.</b> Aura Studio se relanza a sí misma con permisos de
/// administrador para formatear el disco del iPod, y ese proceso entra por
/// <c>Program.Main</c> y sale antes de que exista <c>App</c>: nunca corre
/// <c>ApplyLanguage</c>. Se queda con la cultura del sistema.</para>
///
/// <para>Mientras sus mensajes estuvieron en español eso no se veía. Traducidos,
/// alguien con Windows en alemán y la app puesta en inglés recibiría el
/// resultado del formateo en alemán, dentro de una pantalla en inglés. Y no
/// falla nada: son dos idiomas correctos, en la misma frase de la misma
/// operación.</para>
///
/// <para>Así que el idioma viaja con la petición y acá se aplica. Vive en Core
/// —y no junto al proceso elevado— para poder probarlo sin permisos de
/// administrador ni un disco de por medio.</para>
/// </summary>
public static class UiCulture
{
    /// <summary>
    /// Cómo se nombra la cultura actual para mandarla. Cadena vacía si no hay
    /// ninguna que valga la pena mandar (la invariante no tiene nombre), y
    /// entonces el otro lado se queda con la suya.
    /// </summary>
    public static string Current => CultureInfo.CurrentUICulture.Name;

    /// <summary>
    /// Aplica la cultura que mandó el otro proceso. Devuelve si la aplicó.
    ///
    /// <para><b>Un nombre que .NET no conozca no detiene nada.</b> Del otro lado
    /// hay una operación que formatea un disco: abortarla porque el idioma de un
    /// mensaje no se pudo resolver sería cambiar un defecto cosmético por uno
    /// que deja al usuario sin iPod. Se sigue con la cultura del sistema.</para>
    /// </summary>
    public static bool Apply(string? name)
    {
        if (name is not { Length: > 0 }) return false;

        try
        {
            // `predefinedOnly` no es un detalle. Sin él, .NET **acepta
            // cualquier cosa**: `new CultureInfo("no-es-una-cultura")` no lanza,
            // devuelve una cultura inventada, y el `catch` de abajo no se
            // ejecuta nunca. La comprobación se veía escrita y no comprobaba
            // nada — lo descubrió la prueba del nombre inválido, que pasó a rojo
            // señalando el guardián y no la cultura.
            var culture = CultureInfo.GetCultureInfo(name, predefinedOnly: true);

            CultureInfo.DefaultThreadCurrentUICulture = culture;
            CultureInfo.CurrentUICulture = culture;
            return true;
        }
        catch (Exception exception) when (exception is CultureNotFoundException or ArgumentException)
        {
            return false;
        }
    }
}
