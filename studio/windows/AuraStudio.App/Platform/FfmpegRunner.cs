using System.Diagnostics;
using System.Text;
using AuraStudio.Core.Media;

namespace AuraStudio.App.Platform;

public sealed class FfmpegException(string message) : Exception(message);

/// <param name="Duration">Segundos, o <c>null</c> si el contenedor no lo declara.</param>
public readonly record struct VideoInfo(double? Duration, double? FrameRate);

/// <summary>
/// Corre ffmpeg. Todo lo que se le manda y todo lo que se le lee está en Core
/// (<see cref="FfmpegArguments"/>, <see cref="FfmpegOutput"/>) y ya probado;
/// acá solo queda lanzar el proceso y juntar su salida.
/// </summary>
public sealed class FfmpegRunner
{
    public string ExecutablePath { get; }

    private FfmpegRunner(string executablePath) => ExecutablePath = executablePath;

    /// <summary>
    /// <c>null</c> si no hay ffmpeg en la computadora. <b>No lanza</b>: quién
    /// llama decide si eso es un error o solo una función menos, y el mensaje
    /// para el usuario ya está escrito en
    /// <see cref="FfmpegLocator.NotFoundMessage"/>.
    /// </summary>
    public static FfmpegRunner? Locate(string? configuredPath = null) =>
        FfmpegLocator.Locate(configuredPath) is { } path ? new FfmpegRunner(path) : null;

    /// <summary>
    /// Duración y cuadros por segundo, de una sola pasada: los dos salen del
    /// mismo volcado de cabecera. ffmpeg termina con error porque no se le pidió
    /// ninguna salida, y está bien — para entonces ya imprimió lo que hacía
    /// falta.
    /// </summary>
    public async Task<VideoInfo> ProbeAsync(string inputPath, CancellationToken ct = default)
    {
        string output = await RunAsync(FfmpegArguments.ForProbe(inputPath), ct).ConfigureAwait(false);
        return new VideoInfo(FfmpegOutput.ParseDuration(output), FfmpegOutput.ParseFrameRate(output));
    }

    /// <summary>
    /// El recorte de franjas horneadas, si vale la pena. <c>null</c> es la
    /// respuesta normal para casi todo video.
    /// </summary>
    public async Task<string?> DetectCropAsync(string inputPath, double? durationSeconds, CancellationToken ct = default)
    {
        string output = await RunAsync(FfmpegArguments.ForCropDetect(inputPath, durationSeconds), ct)
            .ConfigureAwait(false);

        return FfmpegOutput.CropFilterWorthApplying(output);
    }

    /// <param name="onProgress">Fracción de 0 a 1. Se llama desde un hilo de fondo.</param>
    public Task TranscodeVideoAsync(string inputPath, string outputPath,
        double? sourceFrameRate = null, string? cropFilter = null,
        Action<double>? onProgress = null, CancellationToken ct = default)
    {
        List<string> arguments =
        [
            .. FfmpegArguments.ForVideo(inputPath, outputPath, sourceFrameRate: sourceFrameRate, cropFilter: cropFilter),
            "-progress", "pipe:1"
        ];

        return RunToCompletionAsync(arguments, onProgress, ct);
    }

    public Task TranscodeAudioAsync(string inputPath, string outputPath, CancellationToken ct = default) =>
        RunToCompletionAsync(FfmpegArguments.ForAudio(inputPath, outputPath), onProgress: null, ct);

    /// <summary>
    /// Un fotograma como póster, tomado donde ya empezó el contenido. Falla
    /// suave: un video sin póster se sincroniza igual.
    /// </summary>
    public async Task<bool> GeneratePosterAsync(string inputPath, string outputPath, double? durationSeconds,
        CancellationToken ct = default)
    {
        double seek = Math.Clamp((durationSeconds ?? 0) * 0.1, 0, Math.Max((durationSeconds ?? 0) - 1, 0));

        try
        {
            await RunToCompletionAsync(FfmpegArguments.ForPoster(inputPath, outputPath, seek), null, ct)
                .ConfigureAwait(false);
            return File.Exists(outputPath);
        }
        catch (FfmpegException)
        {
            return false;
        }
    }

    // MARK: - El proceso

    /// <summary>Toda la salida de ffmpeg, sin importar cómo haya terminado.</summary>
    private async Task<string> RunAsync(IReadOnlyList<string> arguments, CancellationToken ct)
    {
        using Process process = Start(arguments);

        Task<string> error = process.StandardError.ReadToEndAsync(ct);
        Task<string> standard = process.StandardOutput.ReadToEndAsync(ct);

        await process.WaitForExitAsync(ct).ConfigureAwait(false);

        // ffmpeg escribe la cabecera por stderr; el progreso, por stdout.
        return await error.ConfigureAwait(false) + await standard.ConfigureAwait(false);
    }

    /// <summary>
    /// Igual, pero exigiendo que haya terminado bien. Cancelar mata el proceso:
    /// quien llama borra el archivo a medio escribir.
    /// </summary>
    private async Task RunToCompletionAsync(IReadOnlyList<string> arguments, Action<double>? onProgress,
        CancellationToken ct)
    {
        using Process process = Start(arguments);

        var errorBuffer = new StringBuilder();
        double? duration = null;

        process.ErrorDataReceived += (_, e) =>
        {
            if (e.Data is null) return;
            errorBuffer.AppendLine(e.Data);
            duration ??= FfmpegOutput.ParseDuration(errorBuffer.ToString());
        };

        process.OutputDataReceived += (_, e) =>
        {
            if (e.Data is null || onProgress is null) return;
            if (duration is not { } total || total <= 0) return;
            if (FfmpegOutput.ParseOutTimeMicroseconds(e.Data) is not { } microseconds) return;

            onProgress(Math.Clamp(microseconds / 1_000_000 / total, 0, 1));
        };

        process.BeginErrorReadLine();
        process.BeginOutputReadLine();

        try
        {
            await process.WaitForExitAsync(ct).ConfigureAwait(false);
        }
        catch (OperationCanceledException)
        {
            try { process.Kill(entireProcessTree: true); } catch (InvalidOperationException) { }
            throw;
        }

        if (process.ExitCode != 0)
        {
            throw new FfmpegException($"ffmpeg falló: {errorBuffer.ToString().Trim()}");
        }
    }

    private Process Start(IReadOnlyList<string> arguments)
    {
        var info = new ProcessStartInfo(ExecutablePath)
        {
            RedirectStandardError = true,
            RedirectStandardOutput = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };

        // Uno por uno, nunca concatenados: una ruta con espacios o comillas
        // —que en una biblioteca real las hay— se rompería al armar la línea a
        // mano.
        foreach (string argument in arguments) info.ArgumentList.Add(argument);

        return Process.Start(info) ?? throw new FfmpegException("No se pudo iniciar ffmpeg.");
    }
}
