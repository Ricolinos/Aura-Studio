using System.Diagnostics;

namespace AuraStudio.Tools.StorageFixtureCheck;

/// <summary>
/// Audio real y mínimo (no bytes al azar, no material del dueño): dos
/// segundos de un tono generado con el sintetizador de ffmpeg
/// (<c>-f lavfi -i sine</c>), encodeado a los cuatro formatos que pide el
/// arnés. Necesita un ffmpeg instalado en la máquina -- no viene con el
/// repo (D-038) -- así que se resuelve igual que lo haría la app
/// (<see cref="AuraStudio.Core.Media.FfmpegLocator"/>) y, si eso no
/// encuentra nada, se prueba también la carpeta de paquetes de winget
/// directamente (donde queda tras <c>winget install Gyan.FFmpeg</c>, el
/// comando que la propia app recomienda) -- por si la app no lo detectara
/// pero sí esté instalado, que es justo uno de los hallazgos de esta ST.
/// </summary>
internal static class FixtureAudio
{
    /// <summary>
    /// Encuentra ffmpeg para ARMAR el fixture. Esto es una herramienta de
    /// desarrollo, no la app: no le importa si <c>FfmpegLocator</c> (el
    /// camino que sí usa la app) lo encuentra o no -- eso se reporta aparte,
    /// como reconocimiento, no se usa para decidir si el arnés puede correr.
    /// </summary>
    public static string? Locate()
    {
        string? viaLocator = AuraStudio.Core.Media.FfmpegLocator.Locate();
        if (viaLocator is { Length: > 0 }) return viaLocator;

        string packagesRoot = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Microsoft", "WinGet", "Packages");

        if (!Directory.Exists(packagesRoot)) return null;

        foreach (string packageDir in Directory.EnumerateDirectories(packagesRoot, "Gyan.FFmpeg_*"))
        {
            string? found = Directory.EnumerateFiles(packageDir, "ffmpeg.exe", SearchOption.AllDirectories)
                .FirstOrDefault();
            if (found is not null) return found;
        }

        return null;
    }

    /// <param name="ffmpegPath">Resuelto con <see cref="Locate"/>.</param>
    /// <param name="outputPath">Con la extensión ya puesta -- decide el contenedor.</param>
    public static async Task SynthesizeAsync(string ffmpegPath, string outputPath, string codecArgs)
    {
        string? dir = Path.GetDirectoryName(outputPath);
        if (dir is { Length: > 0 }) Directory.CreateDirectory(dir);

        // sine=440:duration=2 -- un tono de 440 Hz (La4), 2 s: silencio puro
        // comprime distinto a un tono de verdad y algunos escritores de
        // etiquetas se comportan distinto con pistas de 0 amplitud.
        string args = $"-y -loglevel error -f lavfi -i \"sine=frequency=440:duration=2\" {codecArgs} \"{outputPath}\"";

        var psi = new ProcessStartInfo(ffmpegPath, args)
        {
            RedirectStandardError = true,
            RedirectStandardOutput = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };

        using Process process = Process.Start(psi) ?? throw new InvalidOperationException("No se pudo iniciar ffmpeg.");
        string stderr = await process.StandardError.ReadToEndAsync().ConfigureAwait(false);
        await process.WaitForExitAsync().ConfigureAwait(false);

        if (process.ExitCode != 0 || !File.Exists(outputPath))
            throw new InvalidOperationException($"ffmpeg falló ({process.ExitCode}) generando {outputPath}:\n{stderr}");
    }

    public static Task SynthesizeMp3Async(string ffmpegPath, string outputPath) =>
        SynthesizeAsync(ffmpegPath, outputPath, "-c:a libmp3lame -b:a 192k");

    public static Task SynthesizeFlacAsync(string ffmpegPath, string outputPath) =>
        SynthesizeAsync(ffmpegPath, outputPath, "-c:a flac");

    public static Task SynthesizeM4aAsync(string ffmpegPath, string outputPath) =>
        SynthesizeAsync(ffmpegPath, outputPath, "-c:a alac");

    public static Task SynthesizeWavAsync(string ffmpegPath, string outputPath) =>
        SynthesizeAsync(ffmpegPath, outputPath, "-c:a pcm_s16le");

    /// <summary>
    /// Etiquetas de partida, como si el archivo viniera de una fuente real --
    /// para que "editar N campos" tenga algo que cambiar de verdad, no un
    /// archivo virgen. Usa TagLib# directo, el mismo lector/escritor que usa
    /// (para leer) <c>LocalTagReader</c>.
    /// </summary>
    public static void WriteBaselineTags(string path, string artist, string album, string title, int track, byte[] cover)
    {
        using var file = TagLib.File.Create(path);

        file.Tag.Performers = [artist];
        file.Tag.AlbumArtists = [artist];
        file.Tag.Album = album;
        file.Tag.Title = title;
        file.Tag.Track = (uint)track;
        file.Tag.Year = 1986;
        file.Tag.Genres = ["Rock"];
        file.Tag.Pictures = [new TagLib.Picture(new TagLib.ByteVector(cover)) { Type = TagLib.PictureType.FrontCover }];

        file.Save();
    }
}
