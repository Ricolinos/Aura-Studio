using AuraStudio.Core;

namespace AuraStudio.App.Services;

/// <param name="IsPresent">Hay un iPod en modo DFU atendido por un driver que responde.</param>
/// <param name="DfuState">Estado DFU reportado, cuando se pudo leer.</param>
/// <param name="ReportedNoDevice">
/// La herramienta dijo explícitamente que no encontró dispositivos — se
/// distingue de "no se pudo leer" para poder decir si falta el iPod o el driver.
/// </param>
public sealed record DfuScanResult(bool IsPresent, int? DfuState, bool ReportedNoDevice, string Output, int ExitCode);

public sealed record DfuOperationResult(bool Success, string Output, int ExitCode);

/// <summary>
/// Frontera con `mks5lboot.exe`; la UI nunca invoca procesos directamente.
///
/// Aura Studio no reimplementa el protocolo DFU del S5L8702 — lo corre y lee su
/// salida (misma decisión que `MKS5LBootRunner` en macOS).
/// </summary>
public interface IDfuFlashRunner
{
    /// <summary>Una pasada de `--dfuscan`. Inofensivo: solo lee.</summary>
    Task<DfuScanResult> ScanAsync(CancellationToken ct = default);

    /// <summary>
    /// Graba el bootloader (`--bl-inst`).
    ///
    /// <paramref name="single"/> destruye el arranque NOR original de Apple
    /// (`--single`): solo se pasa cuando el usuario confirmó explícitamente que
    /// no le interesa conservar el firmware original.
    /// </summary>
    Task<DfuOperationResult> InstallBootloaderAsync(FirmwareArtifacts artifacts, bool single,
                                                    IProgress<string>? progress = null,
                                                    CancellationToken ct = default);

    /// <summary>Quita el bootloader y restaura el arranque original (`--bl-uninst ipod6g`).</summary>
    Task<DfuOperationResult> UninstallBootloaderAsync(FirmwareArtifacts artifacts,
                                                      IProgress<string>? progress = null,
                                                      CancellationToken ct = default);

    /// <summary>Espera a que el iPod SALGA de DFU (tras un flasheo). `false` si se agotó el tiempo.</summary>
    Task<bool> WaitForExitAsync(TimeSpan timeout, IProgress<string>? progress = null, CancellationToken ct = default);

    /// <summary>Espera a que el iPod ENTRE en DFU. `false` si se agotó el tiempo.</summary>
    Task<bool> WaitForDfuAsync(TimeSpan timeout, IProgress<string>? progress = null, CancellationToken ct = default);
}
