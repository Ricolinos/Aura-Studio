namespace AuraStudio.Core;

/// <summary>
/// Identidad extraída de un ID de dispositivo USBSTOR de Windows
/// (<c>USBSTOR\Disk&amp;Ven_…&amp;Prod_…&amp;Rev_…\&lt;serial&gt;&amp;0</c>).
/// Las cadenas vendor/producto son las del INQUIRY SCSI del dispositivo:
/// en un iPod con el modo disco de Apple son "Apple"/"iPod"; con Rockbox o
/// Aura atendiendo el USB son "Rockbox"/"media player" — la lectura real de
/// qué firmware responde (ST-016).
/// </summary>
public sealed record UsbStorageIdentity(string Vendor, string Product, string? Serial);

/// <summary>
/// Parser puro de los IDs de dispositivo Plug&amp;Play de Windows que usan
/// los discos USB. Es deliberadamente una función pura (sin WMI, sin I/O)
/// para testearse con cadenas sintéticas sin hardware.
/// </summary>
public static class PnpDeviceId
{
    /// <summary>
    /// Parsea un ID USBSTOR de disco:
    /// <c>USBSTOR\Disk&amp;Ven_Apple&amp;Prod_iPod&amp;Rev_2.70\000A2700123ABCD&amp;0</c>
    /// → vendor "Apple", product "iPod", serial "000A2700123ABCD".
    /// Dentro de <c>Ven_</c>/<c>Prod_</c> el guion bajo codifica espacio.
    /// El serial es el último segmento, sin el sufijo <c>&amp;0</c>.
    /// Devuelve false si la cadena no tiene la forma esperada.
    /// </summary>
    public static bool TryParseUsbStorageId(string? pnpDeviceId, out UsbStorageIdentity identity)
    {
        identity = new UsbStorageIdentity("", "", null);
        if (string.IsNullOrWhiteSpace(pnpDeviceId)) return false;

        var segments = pnpDeviceId.Split('\\');
        if (segments.Length < 2) return false;
        if (!segments[0].Equals("USBSTOR", StringComparison.OrdinalIgnoreCase)) return false;

        // El segmento "Disk&Ven_X&Prod_Y&Rev_Z"
        var diskSeg = segments[1];
        string? vendor = ExtractToken(diskSeg, "Ven_");
        string? product = ExtractToken(diskSeg, "Prod_");
        if (vendor is null || product is null) return false;

        // Serial: último segmento no vacío. Si termina con "&0" (o similar),
        // se recorta solo ese sufijo final preservando el resto de la cadena.
        string? serial = null;
        if (segments.Length >= 3)
        {
            var last = segments[^1];
            if (last.EndsWith("&0", StringComparison.Ordinal))
            {
                serial = last[..^2];
            }
            else
            {
                int amp = last.IndexOf('&');
                serial = (amp >= 0 ? last[..amp] : last);
            }
            if (serial.Length == 0) serial = null;
        }

        identity = new UsbStorageIdentity(Decode(vendor), Decode(product), serial);
        return true;
    }

    /// <summary>
    /// Parsea un ID de dispositivo USB:
    /// <c>USB\VID_05AC&amp;PID_1261\000A2700123ABCD</c> → vid 0x05AC, pid 0x1261,
    /// serial "000A2700123ABCD". Devuelve false si no tiene la forma esperada.
    /// </summary>
    public static bool TryParseUsbDeviceId(string? deviceId, out int vid, out int pid, out string? serial)
    {
        vid = 0; pid = 0; serial = null;
        if (string.IsNullOrWhiteSpace(deviceId)) return false;

        var segments = deviceId.Split('\\');
        if (segments.Length < 2) return false;
        if (!segments[0].Equals("USB", StringComparison.OrdinalIgnoreCase)) return false;

        var idSeg = segments[1];
        string? vidTok = ExtractToken(idSeg, "VID_", StringComparison.OrdinalIgnoreCase);
        string? pidTok = ExtractToken(idSeg, "PID_", StringComparison.OrdinalIgnoreCase);
        if (vidTok is null || pidTok is null) return false;

        if (!int.TryParse(vidTok, System.Globalization.NumberStyles.HexNumber,
                System.Globalization.CultureInfo.InvariantCulture, out vid))
            return false;
        if (!int.TryParse(pidTok, System.Globalization.NumberStyles.HexNumber,
                System.Globalization.CultureInfo.InvariantCulture, out pid))
            return false;

        if (segments.Length >= 3)
        {
            var last = segments[^1];
            int amp = last.IndexOf('&');
            serial = (amp >= 0 ? last[..amp] : last);
            if (serial.Length == 0) serial = null;
        }
        return true;
    }

    /// <summary>Extrae el valor de un token <c>Clave_valor</c> hasta el siguiente '&amp;'.</summary>
    private static string? ExtractToken(string segment, string key,
        StringComparison comparison = StringComparison.Ordinal)
    {
        int idx = segment.IndexOf(key, comparison);
        if (idx < 0) return null;
        int start = idx + key.Length;
        int end = segment.IndexOf('&', start);
        var value = end < 0 ? segment[start..] : segment[start..end];
        return value.Length == 0 ? null : value;
    }

    /// <summary>Decodifica el guion bajo de las cadenas INQUIRY a espacio.</summary>
    private static string Decode(string raw) => raw.Replace('_', ' ').Trim();
}
