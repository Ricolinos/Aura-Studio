namespace AuraStudio.Core;

/// <summary>
/// La frase que le dice al usuario qué firmware tiene su iPod, en español y sin
/// jerga (R3-3, port de <c>DeviceGeneralView.firmwareLabel</c>).
///
/// <para><b>Existe porque la interfaz estaba mostrando el nombre del enum.</b>
/// "RockboxFamily" aparecía en el título de la ficha, en la barra de estado y en
/// el destino de la sincronización. Eso no es una etiqueta: es el identificador
/// interno de uno de los tres hechos de ST-016, y no significa nada para quien
/// solo quiere saber si su iPod está listo.</para>
///
/// <para>La frase se arma con los <b>tres hechos separados</b> —qué archivos hay
/// en el disco, si dejaron rastro de haber arrancado, y qué firmware atiende el
/// USB ahora— sin fusionarlos: cada combinación tiene su texto, y las que no
/// son evidencia de instalación lo dicen con todas las letras en vez de
/// redondear a "instalado".</para>
/// </summary>
public static class DeviceFirmwareLabel
{
    /// <summary>Lo que se lee bajo el nombre del iPod en General.</summary>
    public static string For(IPodDiskInfo device)
    {
        string dual = device.IsDualBoot ? " (dual boot con Apple)" : "";

        return device.Firmware.Kind switch
        {
            InstalledFirmwareKind.Aura => AuraLabel(device, dual),
            InstalledFirmwareKind.Rockbox => RockboxLabel(device, dual),

            InstalledFirmwareKind.Stock => device.RunningFirmware == RunningFirmware.RockboxFamily
                ? "Firmware original de Apple en el disco — pero el USB lo atiende el bootloader de Aura/Rockbox (modo USB del bootloader)"
                : "Firmware original de Apple",

            _ => device.RunningFirmware == RunningFirmware.RockboxFamily
                ? "Disco vacío — el USB lo atiende el bootloader de Aura/Rockbox (modo USB del bootloader)"
                : "Disco vacío, sin firmware"
        };
    }

    /// <summary>
    /// El nombre sale de lo que el firmware <b>declara</b> (ST-046), no de que
    /// exista el árbol: Metro-Aura escribe el mismo <c>.rockbox/aura/</c> y
    /// llamarlo "Aura" sería mentir. Sin arrancar todavía no hay
    /// <c>aura.cfg</c> que leer, así que ahí se dice "de la familia Aura" en
    /// vez de arriesgar un nombre.
    /// </summary>
    private static string AuraLabel(IPodDiskInfo device, string dual)
    {
        string name = device.DeclaredFamily?.DisplayName ?? FirmwareFamily.Aura.DisplayName;
        bool booted = device.Firmware.HasBooted;

        if (device.RunningFirmware == RunningFirmware.RockboxFamily)
        {
            return booted
                ? $"Firmware {name} instalado — conectado desde {name}{dual}"
                : "Firmware de la familia Aura instalado — conectado desde el firmware, todavía sin escribir su configuración" + dual;
        }

        if (device.RunningFirmware == RunningFirmware.Apple)
        {
            return booted
                ? $"Firmware {name} instalado — conectado desde el modo disco de Apple{dual}"
                : "Archivos de la familia Aura en el disco, pero el iPod está corriendo el firmware de Apple y ese firmware nunca ha arrancado aquí — no hay evidencia de que esté instalado";
        }

        return booted
            ? $"Firmware {name} instalado{dual}"
            : "Archivos de la familia Aura en el disco — todavía sin arrancar (sin evidencia de que el bootloader esté instalado)";
    }

    private static string RockboxLabel(IPodDiskInfo device, string dual)
    {
        if (device.RunningFirmware == RunningFirmware.RockboxFamily)
            return "Rockbox instalado (no es Aura) — conectado desde Rockbox" + dual;

        if (device.Firmware.HasBooted)
            return "Rockbox instalado (no es Aura)" + dual;

        return device.RunningFirmware == RunningFirmware.Apple
            ? "Archivos de Rockbox en el disco (no es Aura), pero el iPod está corriendo el firmware de Apple y Rockbox nunca ha arrancado aquí"
            : "Archivos de Rockbox en el disco (no es Aura) — sin evidencia de arranque";
    }
}
