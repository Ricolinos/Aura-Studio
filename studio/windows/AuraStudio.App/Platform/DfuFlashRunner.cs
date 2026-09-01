using System.Diagnostics;
using System.Text;
using AuraStudio.Core;
using AuraStudio.App.Services;

namespace AuraStudio.App.Platform;

/// <summary>
/// Corre `mks5lboot.exe` y traduce su salida. Port de `MKS5LBootRunner` de macOS.
///
/// <para><b>Verificación antes de ejecutar.</b> El binario y el bootloader se
/// verifican con <see cref="FirmwareArtifactVerifier"/> (alcance
/// <see cref="ArtifactScope.Flashing"/>) en cada operación que escribe en el
/// aparato — nunca se graba nada que no haya pasado por ahí. Un `--dfuscan` no
/// escribe y por eso no exige esa verificación: sirve justamente para saber si
/// el iPod está en DFU antes de tener nada más resuelto.</para>
///
/// <para><b>Serialización.</b> Un semáforo garantiza una sola invocación a la
/// vez: dos procesos peleando por el mismo dispositivo USB es la clase de cosa
/// que deja un flasheo a medias.</para>
/// </summary>
public sealed class DfuFlashRunner : IDfuFlashRunner
{
    private readonly SemaphoreSlim _gate = new(1, 1);
    private readonly Func<FirmwareArtifacts> _artifacts;

    public DfuFlashRunner(Func<FirmwareArtifacts> artifacts) => _artifacts = artifacts;

    // MARK: - Sondeo

    public async Task<DfuScanResult> ScanAsync(CancellationToken ct = default)
    {
        FirmwareArtifacts artifacts = _artifacts();
        if (!File.Exists(artifacts.Mks5lboot))
        {
            return new DfuScanResult(false, null, false,
                "No se encontró mks5lboot.exe junto a Aura Studio.", -1);
        }

        ProcessResult result = await RunAsync(artifacts.Mks5lboot, ["--dfuscan"], null, ct);

        // La ÚNICA lectura válida de "hay un iPod en DFU" es el estado que
        // reporta la herramienta. Buscar la palabra "DFU" en la salida daba
        // siempre "presente": el mensaje de "no DFU devices found" la contiene.
        int? state = Mks5lbootOutput.ParseDfuState(result.Output);
        bool noDevice = Mks5lbootOutput.ReportsNoDevice(result.Output);

        return new DfuScanResult(result.ExitCode == 0 && state is not null,
                                 state, noDevice, result.Output, result.ExitCode);
    }

    // MARK: - Operaciones que escriben en el aparato

    public Task<DfuOperationResult> InstallBootloaderAsync(FirmwareArtifacts artifacts, bool single,
                                                           IProgress<string>? progress = null,
                                                           CancellationToken ct = default)
    {
        if (Verify(artifacts) is { } refusal) return Task.FromResult(refusal);

        string bootloader = artifacts.BootloaderImage!;
        // `--single` destruye el arranque NOR original de Apple: solo llega acá
        // con confirmación explícita del usuario, nunca por omisión.
        string[] args = single
            ? ["--bl-inst", bootloader, "--single"]
            : ["--bl-inst", bootloader];

        return ExecuteAsync(artifacts, args, progress, ct);
    }

    public Task<DfuOperationResult> UninstallBootloaderAsync(FirmwareArtifacts artifacts,
                                                             IProgress<string>? progress = null,
                                                             CancellationToken ct = default)
    {
        if (Verify(artifacts) is { } refusal) return Task.FromResult(refusal);
        return ExecuteAsync(artifacts, ["--bl-uninst", "ipod6g"], progress, ct);
    }

    /// <summary>
    /// `null` si se puede ejecutar; si no, el resultado ya explicado. Se
    /// verifica en CADA operación, no una vez al construir: los archivos pueden
    /// cambiar entre una y otra.
    /// </summary>
    private static DfuOperationResult? Verify(FirmwareArtifacts artifacts)
    {
        ArtifactVerificationResult verification =
            FirmwareArtifactVerifier.Verify(artifacts, ArtifactScope.Flashing);
        return verification.IsValid
            ? null
            : new DfuOperationResult(false, string.Join(" ", verification.Errors), -1);
    }

    private async Task<DfuOperationResult> ExecuteAsync(FirmwareArtifacts artifacts, string[] args,
                                                        IProgress<string>? progress, CancellationToken ct)
    {
        ProcessResult result = await RunAsync(artifacts.Mks5lboot, args, progress, ct);
        return new DfuOperationResult(result.ExitCode == 0, result.Output, result.ExitCode);
    }

    // MARK: - Esperas

    public Task<bool> WaitForExitAsync(TimeSpan timeout, IProgress<string>? progress = null,
                                       CancellationToken ct = default)
        => WaitUntilAsync(present: false, timeout,
                          "El iPod todavía está en modo DFU…", progress, ct);

    public Task<bool> WaitForDfuAsync(TimeSpan timeout, IProgress<string>? progress = null,
                                      CancellationToken ct = default)
        => WaitUntilAsync(present: true, timeout,
                          "Esperando a que el iPod entre en modo DFU…", progress, ct);

    private async Task<bool> WaitUntilAsync(bool present, TimeSpan timeout, string waitingMessage,
                                            IProgress<string>? progress, CancellationToken ct)
    {
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(ct);
        deadline.CancelAfter(timeout);
        try
        {
            while (true)
            {
                DfuScanResult scan = await ScanAsync(deadline.Token);
                if (scan.IsPresent == present) return true;
                progress?.Report(waitingMessage);
                await Task.Delay(TimeSpan.FromSeconds(1), deadline.Token);
            }
        }
        catch (OperationCanceledException) when (!ct.IsCancellationRequested)
        {
            // Se agotó el tiempo, no lo canceló el usuario.
            return false;
        }
    }

    // MARK: - Proceso

    private readonly record struct ProcessResult(int ExitCode, string Output);

    private async Task<ProcessResult> RunAsync(string executable, string[] args,
                                               IProgress<string>? progress, CancellationToken ct)
    {
        await _gate.WaitAsync(ct);
        try
        {
            var psi = new ProcessStartInfo(executable)
            {
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true,
                WorkingDirectory = Path.GetDirectoryName(executable) ?? AppContext.BaseDirectory
            };
            foreach (string arg in args) psi.ArgumentList.Add(arg);

            using var process = new Process { StartInfo = psi, EnableRaisingEvents = true };
            var output = new StringBuilder();
            var sync = new object();

            void Capture(string? line)
            {
                if (line is null) return;
                lock (sync) output.AppendLine(line);
                progress?.Report(line);
            }

            process.OutputDataReceived += (_, e) => Capture(e.Data);
            process.ErrorDataReceived += (_, e) => Capture(e.Data);

            try
            {
                if (!process.Start())
                {
                    return new ProcessResult(-1, "No se pudo iniciar mks5lboot.exe.");
                }
            }
            catch (Exception ex) when (ex is System.ComponentModel.Win32Exception or InvalidOperationException)
            {
                return new ProcessResult(-1, $"No se pudo iniciar mks5lboot.exe: {ex.Message}");
            }

            process.BeginOutputReadLine();
            process.BeginErrorReadLine();
            await process.WaitForExitAsync(ct);
            // Deja que lleguen las últimas líneas antes de leer el buffer.
            process.WaitForExit();

            lock (sync) return new ProcessResult(process.ExitCode, output.ToString());
        }
        finally
        {
            _gate.Release();
        }
    }
}
