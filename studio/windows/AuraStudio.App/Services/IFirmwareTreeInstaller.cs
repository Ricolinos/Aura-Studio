using AuraStudio.Core;

namespace AuraStudio.App.Services;

public sealed record FirmwareTreeInstallResult(bool Success, int FilesCopied, string? ErrorMessage = null);

/// <summary>Instala el árbol de firmware en un volumen ya validado.</summary>
public interface IFirmwareTreeInstaller
{
    Task<FirmwareTreeInstallResult> InstallAsync(
        string volumeRoot,
        FirmwareArtifacts artifacts,
        IProgress<string>? progress = null,
        CancellationToken ct = default);
}
