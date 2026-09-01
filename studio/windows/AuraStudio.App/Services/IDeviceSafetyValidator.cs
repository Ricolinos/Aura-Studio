using AuraStudio.Core;

namespace AuraStudio.App.Services;

public sealed record DeviceSafetyResult(bool IsSafe, string Message)
{
    public static DeviceSafetyResult Unsafe(string message) => new(false, message);
    public static DeviceSafetyResult Safe(string message) => new(true, message);
}

/// <summary>Reenumera el dispositivo y evita escribir sobre otro disco.</summary>
public interface IDeviceSafetyValidator
{
    DeviceSafetyResult Validate(IPodDiskInfo expected);
}
