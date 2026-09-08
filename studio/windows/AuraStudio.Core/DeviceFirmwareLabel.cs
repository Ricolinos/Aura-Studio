using AuraStudio.Core.Resources;

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
        string dual = device.IsDualBoot ? Strings.Get("device-firmware.dual-suffix") : "";

        return device.Firmware.Kind switch
        {
            InstalledFirmwareKind.Aura => AuraLabel(device, dual),
            InstalledFirmwareKind.Rockbox => RockboxLabel(device, dual),

            InstalledFirmwareKind.Stock => Strings.Get(
                device.RunningFirmware == RunningFirmware.RockboxFamily
                    ? "device-firmware.stock-usb-rockbox"
                    : "device-firmware.stock"),

            _ => Strings.Get(
                device.RunningFirmware == RunningFirmware.RockboxFamily
                    ? "device-firmware.empty-usb-rockbox"
                    : "device-firmware.empty")
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
                ? Strings.Format("device-firmware.aura-booted-from-firmware", name, dual)
                : Strings.Format("device-firmware.aura-not-configured", dual);
        }

        if (device.RunningFirmware == RunningFirmware.Apple)
        {
            return booted
                ? Strings.Format("device-firmware.aura-booted-from-apple-disk", name, dual)
                : Strings.Get("device-firmware.aura-files-apple-running");
        }

        return booted
            ? Strings.Format("device-firmware.aura-installed", name, dual)
            : Strings.Get("device-firmware.aura-files-not-booted");
    }

    private static string RockboxLabel(IPodDiskInfo device, string dual)
    {
        if (device.RunningFirmware == RunningFirmware.RockboxFamily)
            return Strings.Format("device-firmware.rockbox-from-rockbox", dual);

        if (device.Firmware.HasBooted)
            return Strings.Format("device-firmware.rockbox-installed", dual);

        return Strings.Get(device.RunningFirmware == RunningFirmware.Apple
            ? "device-firmware.rockbox-files-apple-running"
            : "device-firmware.rockbox-files-not-booted");
    }
}
