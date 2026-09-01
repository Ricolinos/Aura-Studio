namespace AuraStudio.Core;

/// <summary>
/// Lo que el firmware que está CORRIENDO en el iPod anuncia en sus
/// descriptores USB (ST-016). Es la única lectura real que hay: en modo
/// disco el firmware que atiende el USB es el que responde. El modo disco
/// de Apple se presenta como "Apple Inc."/"iPod"; Rockbox (y Aura, que no
/// cambia estas cadenas) como "Rockbox.org"/"Rockbox media player". VID/PID
/// son los MISMOS en los dos casos (0x05AC/0x1261), así que no distinguen
/// firmware, pero sí identifican el aparato: ningún otro dispositivo Apple
/// usa ese PID.
/// </summary>
public sealed record USBDeviceIdentity(
    string VendorName,
    string ProductName,
    string? SerialNumber,
    int VendorID,
    int ProductID)
{
    public const int AppleVendorID = 0x05AC;

    /// <summary>iPod Classic (6G/7G) en modo disco de Apple — y Rockbox reutiliza exactamente el mismo par al correr en el ipod6g.</summary>
    public const int IPodClassicProductID = 0x1261;

    /// <summary>
    /// El par VID/PID que solo tiene un iPod Classic. Un iPhone/iPad también
    /// es 0x05AC pero con otro PID; un disco USB cualquiera no es 0x05AC.
    /// </summary>
    public bool IsIPodClassicUSB => VendorID == AppleVendorID && ProductID == IPodClassicProductID;

    public RunningFirmware RunningFirmware =>
        RunningFirmware.Classify(VendorName, ProductName);
}
