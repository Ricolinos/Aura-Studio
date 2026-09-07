using System.Text.RegularExpressions;

namespace AuraStudio.Tools.ExtraerCadenasWindows;

/// <summary>
/// Convierte los huecos de una cadena interpolada (<c>{expr}</c>, o
/// <c>{expr:formato}</c>) a especificadores numerados <c>{0}</c>, <c>{1}</c>...
/// como pide el encargo (ítem 4). No son <c>%@</c>/<c>%lld</c> como en el
/// borrador de la Mac: son plataformas distintas, con convenciones de formato
/// distintas (<c>string.Format</c>/<c>ResourceManager</c> usa índices, no
/// especificadores de tipo).
///
/// <para>Heurística, no un parser de C# completo: asume huecos simples sin
/// llaves anidadas (<c>{name}</c>, <c>{count}</c>,
/// <c>{status.Progress * 100:0}</c>) — es lo único que aparece hoy en el
/// código real (verificado leyendo <c>AppStrings.cs</c> entero antes de
/// escribir esto). Una <c>{{</c>/<c>}}</c> literal se conserva tal cual.</para>
/// </summary>
public static class InterpolationHoles
{
    private static readonly Regex Hole = new(@"\{[^{}]*\}", RegexOptions.Compiled);

    /// <summary>
    /// Reemplaza cada hueco por <c>{0}</c>, <c>{1}</c>... en orden de
    /// aparición. Devuelve el texto convertido y si hubo al menos un hueco.
    /// </summary>
    public static (string Converted, bool HasInterpolation) Convert(string text)
    {
        int index = 0;
        bool found = false;

        string converted = Hole.Replace(text, match =>
        {
            // `{{`/`}}` ya vienen colapsados por el escaneo de la cadena
            // (ver StringLiteralScanner): acá todo lo que llega es un hueco de
            // verdad.
            found = true;
            return "{" + index++ + "}";
        });

        return (converted, found);
    }
}
