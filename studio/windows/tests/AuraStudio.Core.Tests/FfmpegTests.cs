using AuraStudio.Core.Media;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// Lo que se le manda a ffmpeg y lo que se le lee de vuelta.
///
/// <para>Los argumentos son <b>contrato con el aparato</b>: el iPod reproduce
/// video por <c>mpegplayer</c>, y un archivo fuera de ese perfil se copia
/// perfecto y no se ve. Por eso se fijan acá uno por uno, sin ffmpeg instalado
/// y sin un video de verdad.</para>
/// </summary>
public class FfmpegArgumentsTests
{
    private static string Line(IReadOnlyList<string> arguments) => string.Join(" ", arguments);

    [Fact]
    public void TheVideoProfileIsTheOneTheDeviceCanPlay()
    {
        string line = Line(FfmpegArguments.ForVideo(@"C:\in.mp4", @"C:\out.mpg"));

        Assert.Contains("-c:v mpeg2video", line);
        Assert.Contains("-c:a mp2", line);
        Assert.Contains("-f mpeg", line);
        // libmad solo entiende las frecuencias estándar: sin esto, un video de
        // teléfono a 48 kHz queda sin sonido.
        Assert.Contains("-ar 44100", line);
    }

    [Fact]
    public void TheVideoIsScaledToFitAndNeverPaddedWithBlackBars()
    {
        // Rellenar con barras dejaba todo en 320x240 exactos y el firmware no
        // podía distinguir "video angosto" de "video con barras" — su lógica de
        // ajustar/cubrir quedaba sin nada que hacer.
        string line = Line(FfmpegArguments.ForVideo(@"C:\in.mp4", @"C:\out.mpg"));

        Assert.Contains("scale=320:240:force_original_aspect_ratio=decrease:force_divisible_by=2", line);
        Assert.DoesNotContain("pad=", line);
    }

    [Fact]
    public void AFastSourceIsSlowedToWhatTheDeviceCanDecode()
    {
        Assert.Contains("-r 24", Line(FfmpegArguments.ForVideo(@"C:\in.mp4", @"C:\out.mpg", sourceFrameRate: 60)));
    }

    [Fact]
    public void ASlowSourceIsLeftAlone()
    {
        // Forzar 24 en un timelapse a 10 fps duplicaría cuadros y agrandaría el
        // archivo sin ganar absolutamente nada.
        Assert.DoesNotContain("-r 24", Line(FfmpegArguments.ForVideo(@"C:\in.mp4", @"C:\out.mpg", sourceFrameRate: 10)));
    }

    [Fact]
    public void AnUnknownFrameRateIsLeftAlone()
    {
        Assert.DoesNotContain("-r 24", Line(FfmpegArguments.ForVideo(@"C:\in.mp4", @"C:\out.mpg")));
    }

    [Fact]
    public void TheCropGoesBeforeTheScaleOrItWouldCropTheAlreadyShrunkImage()
    {
        string filter = FfmpegArguments
            .ForVideo(@"C:\in.mp4", @"C:\out.mpg", cropFilter: "crop=720:404:0:38")
            .SkipWhile(argument => argument != "-vf").Skip(1).First();

        Assert.Equal("crop=720:404:0:38," + FfmpegArguments.ScaleFilter, filter);
    }

    /// <summary>
    /// ST-243: ffmpeg es <b>solo para video</b>. El audio lo convierte el
    /// codificador que ya trae Windows (<c>AudioTranscoder</c>), así que no hay
    /// que meter ffmpeg —con su peso y sus licencias— en el instalador por algo
    /// que el sistema resuelve de fábrica.
    ///
    /// <para>La prueba existe para que el perfil de audio por ffmpeg no vuelva
    /// solo: había uno completo, sin un solo llamador, esperando a que alguien
    /// lo usara.</para>
    /// </summary>
    [Fact]
    public void NoHayPerfilDeAudioPorFfmpeg()
    {
        Assert.DoesNotContain(
            typeof(FfmpegArguments).GetMethods(),
            method => method.Name.Contains("Audio", StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public void TheCropSampleStartsAfterTheIntro()
    {
        // Al 20%: las intros y los logos son negros de verdad, no franjas.
        Assert.Contains("-ss 120.00", Line(FfmpegArguments.ForCropDetect(@"C:\in.mp4", 600)));
    }

    [Fact]
    public void AVideoWithoutKnownDurationIsSampledFromTheStart()
    {
        Assert.Contains("-ss 0.00", Line(FfmpegArguments.ForCropDetect(@"C:\in.mp4", null)));
    }
}

/// <summary>Lo que se le lee a ffmpeg de su volcado de cabecera.</summary>
public class FfmpegOutputTests
{
    private const string Header = """
        Input #0, mov,mp4,m4a,3gp,3g2,mj2, from 'video.mp4':
          Duration: 00:01:23.45, start: 0.000000, bitrate: 2034 kb/s
          Stream #0:0(und): Video: h264 (High), yuv420p(tv, bt709, progressive), 1920x1080 [SAR 1:1 DAR 16:9], 1900 kb/s, 59.94 fps, 60 tbr, 90k tbn
          Stream #0:1(und): Audio: aac (LC), 48000 Hz, stereo, fltp, 128 kb/s
        """;

    [Fact]
    public void TheDurationComesOutInSeconds()
    {
        Assert.Equal(83.45, FfmpegOutput.ParseDuration(Header)!.Value, 2);
    }

    [Fact]
    public void TheFrameRateIsRead()
    {
        Assert.Equal(59.94, FfmpegOutput.ParseFrameRate(Header)!.Value, 2);
    }

    [Fact]
    public void TheResolutionSurvivesTheCommasInsideThePixelFormat()
    {
        // "yuv420p(tv, bt709, progressive)" trae comas propias: partir la línea
        // por comas daría pedazos equivocados.
        Assert.Equal(new VideoResolution(1920, 1080), FfmpegOutput.ParseResolution(Header));
    }

    [Fact]
    public void AFileWithoutVideoHasNoFrameRateOrResolution()
    {
        const string audioOnly = """
            Input #0, mp3, from 'a.mp3':
              Duration: 00:03:00.00, start: 0.000000, bitrate: 320 kb/s
              Stream #0:0: Audio: mp3, 44100 Hz, stereo, fltp, 320 kb/s
            """;

        Assert.Null(FfmpegOutput.ParseFrameRate(audioOnly));
        Assert.Null(FfmpegOutput.ParseResolution(audioOnly));
        Assert.Equal(180, FfmpegOutput.ParseDuration(audioOnly)!.Value, 2);
    }

    [Fact]
    public void GarbageIsNotADuration()
    {
        Assert.Null(FfmpegOutput.ParseDuration("no hay nada acá"));
        Assert.Null(FfmpegOutput.ParseDuration("Duration: N/A, start: 0"));
    }

    // MARK: - Recorte

    [Fact]
    public void TheLastCropOfTheSampleIsTheOneThatCounts()
    {
        // cropdetect afina cuadro a cuadro, ampliando lo justo para cubrir todo
        // lo visto: el último valor es el único seguro.
        const string output = """
            [Parsed_cropdetect_0 @ 0x1] x1:0 x2:1919 y1:140 y2:939 w:1920 h:800 x:0 y:140 crop=1920:800:0:140
            [Parsed_cropdetect_0 @ 0x1] x1:0 x2:1919 y1:130 y2:949 w:1920 h:820 x:0 y:130 crop=1920:820:0:130
            """;

        Assert.Equal("crop=1920:820:0:130", FfmpegOutput.ParseCropFilter(output));
    }

    [Fact]
    public void ARealBlackBarIsWorthCropping()
    {
        const string output = """
              Stream #0:0: Video: h264, yuv420p, 1920x1080, 25 fps
            [Parsed_cropdetect_0 @ 0x1] crop=1920:800:0:140
            """;

        Assert.Equal("crop=1920:800:0:140", FfmpegOutput.CropFilterWorthApplying(output));
    }

    [Fact]
    public void TheNoiseOfAnEdgeIsNotWorthCropping()
    {
        // cropdetect encuentra 2-3% hasta en fuentes sin ninguna franja:
        // aplicarlo recortaría un poco de TODOS los videos sin necesidad.
        const string output = """
              Stream #0:0: Video: h264, yuv420p, 1920x1080, 25 fps
            [Parsed_cropdetect_0 @ 0x1] crop=1912:1076:4:2
            """;

        Assert.Null(FfmpegOutput.CropFilterWorthApplying(output));
    }

    [Fact]
    public void WithoutTheSourceResolutionCropdetectIsTrusted()
    {
        Assert.Equal("crop=100:50:0:0",
            FfmpegOutput.CropFilterWorthApplying("[cropdetect] crop=100:50:0:0"));
    }

    [Fact]
    public void AnImpossibleCropIsIgnoredInsteadOfPassedToFfmpeg()
    {
        Assert.Null(FfmpegOutput.ParseCropFilter("[cropdetect] crop=0:0:0:0"));
        Assert.Null(FfmpegOutput.ParseCropFilter("[cropdetect] crop=nada"));
        Assert.Null(FfmpegOutput.ParseCropFilter("sin recorte"));
    }

    // MARK: - Avance

    [Fact]
    public void TheProgressIsTheLastReportedTime()
    {
        Assert.Equal(4000000, FfmpegOutput.ParseOutTimeMicroseconds("out_time_ms=2000000\nspeed=1x\nout_time_ms=4000000\n"));
        Assert.Null(FfmpegOutput.ParseOutTimeMicroseconds("frame=10\nfps=25\n"));
    }
}

/// <summary>Encontrar ffmpeg sin obligar al usuario a moverlo de lugar.</summary>
public class FfmpegLocatorTests
{
    private static string? Env(string name) => name switch
    {
        "LOCALAPPDATA" => @"C:\Users\r\AppData\Local",
        "ProgramFiles" => @"C:\Program Files",
        "ProgramData" => @"C:\ProgramData",
        "USERPROFILE" => @"C:\Users\r",
        "PATH" => @"C:\herramientas;C:\otra carpeta",
        _ => null
    };

    [Fact]
    public void WhatTheUserChoseByHandWinsOverEverythingElse()
    {
        // Alguien que tiene ffmpeg en una carpeta propia no tiene por qué
        // moverlo para que Studio lo encuentre.
        Assert.Equal(@"D:\mis cosas\ffmpeg.exe", FfmpegLocator.Locate(
            @"D:\mis cosas\ffmpeg.exe",
            path => path is @"D:\mis cosas\ffmpeg.exe" or @"C:\herramientas\ffmpeg.exe",
            Env));
    }

    [Fact]
    public void TheOneFromWingetIsFoundWithoutConfiguringAnything()
    {
        Assert.Equal(@"C:\Users\r\AppData\Local\Microsoft\WinGet\Links\ffmpeg.exe",
            FfmpegLocator.Locate(null,
                path => path.Contains("WinGet", StringComparison.Ordinal), Env));
    }

    [Fact]
    public void OneOnThePathIsFoundToo()
    {
        Assert.Equal(@"C:\otra carpeta\ffmpeg.exe",
            FfmpegLocator.Locate(null, path => path == @"C:\otra carpeta\ffmpeg.exe", Env));
    }

    [Fact]
    public void WithoutFfmpegItSaysSoInsteadOfGuessing()
    {
        Assert.Null(FfmpegLocator.Locate(null, _ => false, Env));
    }

    [Fact]
    public void AConfiguredPathThatNoLongerExistsFallsBackToLookingAround()
    {
        // El usuario desinstaló y reinstaló: no puede quedar trabado.
        Assert.Equal(@"C:\herramientas\ffmpeg.exe",
            FfmpegLocator.Locate(@"D:\ya no está\ffmpeg.exe",
                path => path == @"C:\herramientas\ffmpeg.exe", Env));
    }

    [Fact]
    public void TheMessageSaysExactlyHowToInstallIt()
    {
        Assert.Contains("winget install", FfmpegLocator.NotFoundMessage);
    }

    // MARK: - El paquete desempaquetado de winget (addendum de ST-243)

    /// <summary>
    /// Un árbol simulado como el que deja winget: una carpeta por paquete, y
    /// adentro una por versión con el nombre que trae el zip.
    /// </summary>
    private static readonly Dictionary<string, string[]> WinGetTree = new(StringComparer.OrdinalIgnoreCase)
    {
        [@"C:\Users\r\AppData\Local\Microsoft\WinGet\Packages"] =
        [
            @"C:\Users\r\AppData\Local\Microsoft\WinGet\Packages\Microsoft.PowerToys_Microsoft.Winget.Source_8wekyb3d8bbwe",
            @"C:\Users\r\AppData\Local\Microsoft\WinGet\Packages\Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe"
        ],
        [@"C:\Users\r\AppData\Local\Microsoft\WinGet\Packages\Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe"] =
        [
            @"C:\Users\r\AppData\Local\Microsoft\WinGet\Packages\Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe\ffmpeg-7.1-full_build",
            @"C:\Users\r\AppData\Local\Microsoft\WinGet\Packages\Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe\ffmpeg-10.0-full_build"
        ]
    };

    private static IEnumerable<string> Directories(string path) =>
        WinGetTree.TryGetValue(path, out string[]? children) ? children : [];

    /// <summary>
    /// Instalado con winget pero <b>sin el atajo</b> en <c>WinGet\Links</c>:
    /// pasa cuando el paquete no declara alias o la instalación fue de máquina.
    /// Antes de esto, Studio decía que no había ffmpeg y mandaba al usuario a
    /// instalar de nuevo algo que ya tenía.
    /// </summary>
    [Fact]
    public void ElDeWingetSeEncuentraAunqueNoHayaAtajoEnLinks()
    {
        const string esperado =
            @"C:\Users\r\AppData\Local\Microsoft\WinGet\Packages\Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe\ffmpeg-10.0-full_build\bin\ffmpeg.exe";

        Assert.Equal(esperado, FfmpegLocator.Locate(
            null,
            path => path == esperado,
            Env,
            Directories));
    }

    /// <summary>
    /// Con dos versiones instaladas gana la más nueva, y "más nueva" se decide
    /// comparando los números como números: alfabéticamente, `ffmpeg-10` iría
    /// antes que `ffmpeg-7` y Studio elegiría la vieja.
    /// </summary>
    [Fact]
    public void ConDosVersionesGanaLaMasNuevaDeVerdad()
    {
        // Las dos están en disco: la que se devuelva es la que se prefiere.
        string? encontrado = FfmpegLocator.Locate(
            null,
            path => path.EndsWith(@"full_build\bin\ffmpeg.exe", StringComparison.Ordinal),
            Env,
            Directories);

        Assert.Contains("ffmpeg-10.0", encontrado);
    }

    /// <summary>
    /// El atajo de <c>Links</c> sigue ganando: es más barato de comprobar y es
    /// lo que winget mantiene apuntando a la versión vigente.
    /// </summary>
    [Fact]
    public void ElAtajoDeLinksSigueGanandoleAlPaquete()
    {
        Assert.Equal(@"C:\Users\r\AppData\Local\Microsoft\WinGet\Links\ffmpeg.exe",
            FfmpegLocator.Locate(null, path => path.Contains("WinGet", StringComparison.Ordinal),
                Env, Directories));
    }

    /// <summary>
    /// Solo se mira dentro de los paquetes que hablan de ffmpeg. Y aunque se
    /// mirara de más, no pasa nada: solo se devuelve lo que existe.
    /// </summary>
    [Fact]
    public void NoSeProponeNadaDeUnPaqueteAjeno()
    {
        Assert.DoesNotContain(
            FfmpegLocator.WinGetPackagePaths(Env, Directories),
            candidate => candidate.Contains("PowerToys", StringComparison.OrdinalIgnoreCase));
    }

    /// <summary>
    /// Sin winget instalado, la carpeta no existe: no es un error que tenga que
    /// ver nadie, y la búsqueda sigue con el PATH.
    /// </summary>
    [Fact]
    public void SinCarpetaDePaquetesNoPasaNada()
    {
        Assert.Empty(FfmpegLocator.WinGetPackagePaths(Env, _ => []));

        Assert.Equal(@"C:\otra carpeta\ffmpeg.exe",
            FfmpegLocator.Locate(null, path => path == @"C:\otra carpeta\ffmpeg.exe", Env, _ => []));
    }
}
