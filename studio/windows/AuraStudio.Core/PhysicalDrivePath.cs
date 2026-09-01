using System.Globalization;

namespace AuraStudio.Core;

/// <summary>
/// El número de disco físico de Windows, sacado de la ruta de dispositivo
/// (<c>\\.\PhysicalDrive2</c>).
///
/// Existe como función pura y probada porque ese número es lo que recibe la
/// operación privilegiada de formateo: si se parsea mal, se formatea otro
/// disco. No es un detalle de conveniencia.
/// </summary>
public static class PhysicalDrivePath
{
    private const string Prefix = @"\\.\PHYSICALDRIVE";

    /// <summary>
    /// `true` y el número si la ruta es exactamente la de un disco físico.
    /// Cualquier otra forma se rechaza — nunca se adivina un número a partir de
    /// una ruta que no se entiende.
    /// </summary>
    public static bool TryGetNumber(string? devicePath, out int number)
    {
        number = -1;
        if (string.IsNullOrWhiteSpace(devicePath)) return false;

        string trimmed = devicePath.Trim();
        if (!trimmed.StartsWith(Prefix, StringComparison.OrdinalIgnoreCase)) return false;

        string digits = trimmed[Prefix.Length..];
        if (digits.Length == 0 || !digits.All(char.IsAsciiDigit)) return false;

        return int.TryParse(digits, NumberStyles.None, CultureInfo.InvariantCulture, out number)
            && number is >= 0 and <= 99;
    }
}
