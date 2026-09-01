using AuraStudio.Core;

namespace AuraStudio.App.Services;

public sealed class DeviceSafetyValidator : IDeviceSafetyValidator
{
    private readonly IUsbDeviceWatcher _watcher;

    public DeviceSafetyValidator(IUsbDeviceWatcher watcher) => _watcher = watcher;

    public DeviceSafetyResult Validate(IPodDiskInfo expected)
    {
        _watcher.Refresh();
        var devices = _watcher.GetConnectedIPods();
        if (devices.Count != 1) return DeviceSafetyResult.Unsafe(
            devices.Count == 0 ? "El iPod desapareció. No se realizó ninguna escritura." : "Hay más de un iPod candidato. Por seguridad no se eligió ninguno.");
        var actual = devices[0];
        if (!string.Equals(actual.DevicePath, expected.DevicePath, StringComparison.OrdinalIgnoreCase) ||
            !string.Equals(actual.VolumePath, expected.VolumePath, StringComparison.OrdinalIgnoreCase) ||
            actual.SizeBytes != expected.SizeBytes)
            return DeviceSafetyResult.Unsafe("El dispositivo cambió desde la confirmación. Por seguridad no se realizó ninguna escritura.");
        if (!actual.IsMounted) return DeviceSafetyResult.Unsafe("El volumen del iPod no está montado.");
        return DeviceSafetyResult.Safe($"Dispositivo verificado: {actual.DisplayName}, {actual.CapacityDisplay}, {actual.VolumePath}");
    }
}
