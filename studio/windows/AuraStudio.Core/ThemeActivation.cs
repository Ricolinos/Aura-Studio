using System.Text;

namespace AuraStudio.Core;

/// <summary>
/// Un tema que está en el iPod.
/// </summary>
/// <param name="Loadable">
/// Si el firmware instalado lo va a poder cargar. Un tema que no carga
/// <b>se sigue mostrando</b>, con el motivo: esconderlo dejaría al usuario sin
/// entender por qué el tema que copió no aparece.
/// </param>
public sealed record InstalledTheme(string Id, string Name, bool Loadable, string? Reason = null);

/// <summary>
/// Cuál es el tema activo. Lo dice la clave <c>theme_id</c> de
/// <c>aura.cfg</c>, que el firmware lee al arrancar.
///
/// <para>Puro y sin disco a propósito: escribir en <c>aura.cfg</c> es
/// <b>editar un archivo del firmware</b>, y equivocarse ahí puede dejarlo sin
/// ajustes. Lo que decide qué texto queda se prueba entero acá.</para>
/// </summary>
public static class ThemeActivation
{
    public const string AuraConfigRelativePath = ".rockbox/aura/aura.cfg";

    /// <summary>El tema compilado en el firmware. Siempre existe y no se puede borrar.</summary>
    public const string DefaultThemeId = "default";

    private const string Key = "theme_id:";

    /// <summary>
    /// El tema activo según el texto de <c>aura.cfg</c>. Una clave vacía o
    /// ausente es el tema por omisión, igual que lo interpreta el firmware.
    /// </summary>
    public static string ActiveThemeId(string? auraConfigText)
    {
        if (auraConfigText is null) return DefaultThemeId;

        foreach (string line in auraConfigText.Split('\n'))
        {
            if (!line.StartsWith(Key, StringComparison.Ordinal)) continue;

            string value = line[Key.Length..].Trim();
            return value.Length == 0 ? DefaultThemeId : value;
        }

        return DefaultThemeId;
    }

    /// <summary>
    /// El texto de <c>aura.cfg</c> con el tema cambiado: se edita
    /// <b>solamente esa línea</b> y el resto del archivo queda igual.
    ///
    /// <para>Es una edición transitoria —el firmware reescribe el archivo
    /// entero la próxima vez que guarda sus ajustes— pero tiene que sobrevivir
    /// hasta el <b>próximo arranque</b>, que es justo cuando la lee. Perder de
    /// paso el resto de los ajustes del usuario sería mucho peor que no cambiar
    /// el tema.</para>
    /// </summary>
    public static string WithActiveTheme(string? auraConfigText, string themeId)
    {
        List<string> lines = auraConfigText is null
            ? []
            : [.. auraConfigText.Split('\n')];

        bool replaced = false;

        for (int i = 0; i < lines.Count; i++)
        {
            if (!lines[i].StartsWith(Key, StringComparison.Ordinal)) continue;

            lines[i] = $"theme_id: {themeId}";
            replaced = true;
            break;
        }

        if (!replaced)
        {
            // Un archivo que terminaba con salto de línea dejaría un renglón
            // vacío en medio; el parser del firmware lo tolera, pero el archivo
            // se ensucia un poco más en cada activación.
            if (lines.Count > 0 && lines[^1].Length == 0) lines[^1] = $"theme_id: {themeId}";
            else lines.Add($"theme_id: {themeId}");
        }

        var builder = new StringBuilder();
        foreach (string line in lines) builder.Append(line).Append('\n');

        // El archivo original ya terminaba en salto: no se agrega otro.
        if (auraConfigText is { Length: > 0 } && !auraConfigText.EndsWith('\n') && builder.Length > 0)
            builder.Length--;

        return builder.ToString();
    }

    /// <summary>
    /// Un id a partir del nombre que escribió el usuario: minúsculas, y todo lo
    /// demás colapsado a un solo guion. <b>Es una sugerencia</b>: quien decide
    /// si sirve es <see cref="AuraThemeID.IsValid"/>.
    /// </summary>
    public static string SuggestId(string name)
    {
        var builder = new StringBuilder();
        bool lastWasDash = false;

        foreach (char c in name.ToLowerInvariant())
        {
            if (c is >= 'a' and <= 'z' or >= '0' and <= '9')
            {
                builder.Append(c);
                lastWasDash = false;
            }
            else if (!lastWasDash && builder.Length > 0)
            {
                builder.Append('-');
                lastWasDash = true;
            }
        }

        while (builder.Length > 0 && builder[^1] == '-') builder.Length--;

        return builder.Length > AuraThemeID.MaxLength
            ? builder.ToString(0, AuraThemeID.MaxLength).TrimEnd('-')
            : builder.ToString();
    }
}
