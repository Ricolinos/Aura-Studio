using AuraStudio.Core;
using AuraStudio.Core.Resources;

namespace AuraStudio.App.Services;

public sealed class DeviceSafetyValidator : IDeviceSafetyValidator
{
    private readonly IUsbDeviceWatcher _watcher;

    public DeviceSafetyValidator(IUsbDeviceWatcher watcher) => _watcher = watcher;

    public DeviceSafetyResult Validate(IPodDiskInfo expected)
    {
        _watcher.Refresh();
        var devices = _watcher.GetConnectedIPods();
        if (devices.Count != 1)
            return DeviceSafetyResult.Unsafe(Strings.Get(devices.Count == 0
                ? "device-safety-validator.ipod-desaparecio-se-realizo-ninguna-escr"
                : "device-safety-validator.hay-mas-ipod-candidato-por-seguridad"));
        var actual = devices[0];
        if (!string.Equals(actual.DevicePath, expected.DevicePath, StringComparison.OrdinalIgnoreCase) ||
            !string.Equals(actual.VolumePath, expected.VolumePath, StringComparison.OrdinalIgnoreCase) ||
            actual.SizeBytes != expected.SizeBytes)
            return DeviceSafetyResult.Unsafe(Strings.Get("device-safety-validator.dispositivo-cambio-desde-confirmacion-po"));
        if (!actual.IsMounted) return DeviceSafetyResult.Unsafe(Strings.Get("device-safety-validator.volumen-ipod-esta-montado"));
        return DeviceSafetyResult.Safe(Strings.Format(
            "device-safety-validator.dispositivo-verificado-actual-displaynam",
            actual.DisplayName, actual.CapacityDisplay, actual.VolumePath));
    }
}
