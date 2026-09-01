using AuraStudio.Core;
using AuraStudio.Core.Installer;

namespace AuraStudio.App.Services;

/// <summary>
/// Escribe el árbol del firmware en el iPod delegando en
/// <see cref="FirmwareTreeWriter"/> (Core), que implementa el contrato:
/// actualización selectiva por manifiesto (v11, ST-058) y estacionamiento del
/// árbol saliente al cambiar de familia (v10, ST-056).
///
/// <para>La versión anterior de este servicio extraía el zip completo a
/// <c>/.aura/install-staging</c> **dentro del iPod** y después copiaba archivo
/// por archivo: el doble de escrituras sobre el medio más lento, sin delta, y
/// encima dentro de <c>/.aura/</c>, que por contrato v16 es territorio del
/// firmware. Nada de eso queda.</para>
/// </summary>
public sealed class FirmwareTreeInstaller : IFirmwareTreeInstaller
{
    public async Task<FirmwareTreeInstallResult> InstallAsync(
        string volumeRoot,
        FirmwareArtifacts artifacts,
        IProgress<string>? progress = null,
        CancellationToken ct = default)
    {
        if (!Directory.Exists(volumeRoot))
        {
            return new FirmwareTreeInstallResult(false, 0, "El volumen del iPod ya no está disponible.");
        }

        // Qué familia hay instalada DE VERDAD (no qué archivos hay sueltos):
        // decide si esto es una actualización de la misma familia (delta) o un
        // cambio de familia (se estaciona la saliente y se extrae completo).
        FirmwareTreeFacts facts = FirmwareTreeProbe.Probe(volumeRoot);
        FirmwareFamily? installedFamily = facts.Firmware.Kind == InstalledFirmwareKind.Aura
            ? FirmwareCapabilities.DeclaredFamily(volumeRoot)
            : null;

        var relay = progress is null
            ? null
            : new Progress<FirmwareWriteProgress>(p => progress.Report(p.Message));

        try
        {
            FirmwareWriteResult result = await FirmwareTreeWriter.WriteAsync(
                volumeRoot, artifacts, artifacts.Family, installedFamily, relay, ct);

            return new FirmwareTreeInstallResult(true, result.FilesWritten);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (InstallerException ex)
        {
            return new FirmwareTreeInstallResult(false, 0, ex.Message);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or InvalidDataException)
        {
            return new FirmwareTreeInstallResult(false, 0, ex.Message);
        }
    }
}
