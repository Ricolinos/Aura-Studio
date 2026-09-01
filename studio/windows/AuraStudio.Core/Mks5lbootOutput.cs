namespace AuraStudio.Core;

/// <summary>
/// Lo que dijo `mks5lboot` en su salida de texto. Parser puro, sin procesos ni
/// USB, para poder probarlo con las cadenas reales que emite el binario.
///
/// Aura Studio **no reimplementa** el protocolo DFU/USB del S5L8702 — ya existe,
/// probado, en C dentro del propio fork del firmware. Solo lo invoca y lee su
/// salida (misma decisión que en macOS, `MKS5LBootRunner`).
/// </summary>
public static class Mks5lbootOutput
{
    /// <summary>
    /// El estado DFU que reporta `--dfuscan`, o `null` si la salida no lo trae.
    ///
    /// **Es la única lectura válida de "hay un iPod en DFU"**: buscar la palabra
    /// "DFU" en la salida no sirve — cuando NO hay dispositivo, el binario
    /// imprime `no DFU devices found`, que también la contiene.
    /// </summary>
    public static int? ParseDfuState(string output)
    {
        const string marker = "DFU device state: ";
        foreach (string line in output.Split('\n'))
        {
            int index = line.IndexOf(marker, StringComparison.Ordinal);
            if (index < 0) continue;

            string rest = line[(index + marker.Length)..].Trim();
            // El número puede venir seguido de más texto; se toma el prefijo numérico.
            int end = 0;
            while (end < rest.Length && char.IsAsciiDigit(rest[end])) end++;
            if (end == 0) continue;
            if (int.TryParse(rest[..end], out int state)) return state;
        }
        return null;
    }

    /// <summary>
    /// `true` si la salida dice explícitamente que no encontró dispositivos.
    /// Se distingue de "no se pudo leer el estado" para poder dar mensajes
    /// distintos: falta el iPod, o falta el driver.
    /// </summary>
    public static bool ReportsNoDevice(string output)
        => output.Contains("no DFU devices found", StringComparison.OrdinalIgnoreCase)
        || output.Contains("DFU device not found", StringComparison.OrdinalIgnoreCase);
}
