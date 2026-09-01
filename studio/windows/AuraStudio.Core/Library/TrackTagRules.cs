using System.Globalization;

namespace AuraStudio.Core.Library;

/// <summary>
/// Las normalizaciones que aplica el lector de etiquetas de macOS
/// (`LocalTagReader.swift`), portadas como funciones puras.
///
/// <para><b>Por qué están acá y no dentro del lector.</b> En macOS el lector se
/// apoya en AVFoundation, que en Windows no existe: la librería que lee los
/// contenedores es necesariamente distinta. Lo que **no** puede ser distinto es
/// el resultado — el mismo archivo tiene que producir la misma metadata en las
/// dos apps, porque de ahí sale el `biblioteca.json` y lo que termina en el
/// iPod. Estas reglas son esa parte, y por eso viven en Core y con pruebas: es
/// donde la fidelidad se puede verificar.</para>
/// </summary>
public static class TrackTagRules
{
    /// <summary>
    /// Año a partir de una fecha en texto: `"2013-05-01"` → `"2013"`.
    ///
    /// Igual que macOS, una cadena de menos de 4 caracteres se devuelve **tal
    /// cual** en vez de descartarse — un `"98"` mal etiquetado se conserva como
    /// estaba y no se convierte en `null`.
    /// </summary>
    public static string? YearPrefix(string? value)
    {
        if (value is null || value.Length < 4) return value;
        return value[..4];
    }

    /// <summary>
    /// `"3/12"` (pista/total, lo que escriben casi todos los etiquetadores) →
    /// `3`.
    ///
    /// Es el bug concreto que perdía el número de pista en macOS: convertir
    /// `"3/12"` a entero directamente da nada, y la pista se perdía incluso en
    /// ID3v2.3.
    /// </summary>
    public static int? TrackNumberFromSlashed(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        string first = value.Split('/')[0].Trim();
        return int.TryParse(first, NumberStyles.Integer, CultureInfo.InvariantCulture, out int number)
            ? number
            : null;
    }

    /// <summary>
    /// Átomo `trkn`/`disk` de iTunes: `[reservado(2)][número(2)][total(2)][reservado(2)]`,
    /// big-endian. Devuelve `null` para cero — en esos átomos, cero significa
    /// "sin número", no "pista cero".
    /// </summary>
    public static int? TrackNumberFromITunesData(byte[]? data)
    {
        if (data is null || data.Length < 4) return null;
        int number = (data[2] << 8) | data[3];
        return number > 0 ? number : null;
    }

    /// <summary>
    /// El primero que llega gana. macOS escribe `metadata.campo ?? nuevo` en
    /// cada asignación: una vez que un campo tiene valor, un item posterior del
    /// mismo archivo no lo pisa. Sin esto, el orden en que la librería entrega
    /// las etiquetas cambiaría el resultado.
    /// </summary>
    public static string? FirstNonEmpty(string? current, string? candidate)
    {
        if (!string.IsNullOrWhiteSpace(current)) return current;
        return string.IsNullOrWhiteSpace(candidate) ? current : candidate.Trim();
    }

    /// <summary>Igual que <see cref="FirstNonEmpty(string?, string?)"/>, para números.</summary>
    public static int? FirstPositive(int? current, int? candidate)
    {
        if (current is > 0) return current;
        return candidate is > 0 ? candidate : current;
    }
}
