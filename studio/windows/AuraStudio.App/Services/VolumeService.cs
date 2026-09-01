using AuraStudio.App.Platform;

namespace AuraStudio.App.Services;

/// <summary>Puente a <see cref="VolumeManager"/> (Win32/Shell) detrás de <see cref="IVolumeService"/>.</summary>
public sealed class VolumeService : IVolumeService
{
    public bool OpenInExplorer(string volumePath) => VolumeManager.OpenInExplorer(volumePath);

    public bool Eject(string volumePath) => VolumeManager.Eject(volumePath);
}
