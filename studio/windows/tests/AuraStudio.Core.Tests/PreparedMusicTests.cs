using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// El preparado de música en modo referencia (ST-244): cuándo hace falta uno,
/// cuándo se rehace y cuándo no se toca nada.
///
/// <para>Lo que se protege es una promesa escrita en Ajustes: en modo referencia
/// "tu disco nunca termina con una copia duplicada de toda tu biblioteca".</para>
/// </summary>
public class PreparedMusicTests : IDisposable
{
    private readonly string _root;
    private readonly string _staging;

    public PreparedMusicTests()
    {
        _root = Path.Combine(Path.GetTempPath(), "AuraPrep-" + Guid.NewGuid().ToString("N"));
        _staging = Path.Combine(_root, ".preparados");
        Directory.CreateDirectory(_staging);
    }

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { /* best effort */ }
    }

    // MARK: - La regla de conversión, en un solo lugar

    /// <summary>
    /// La tabla completa (ST-244). WAV y AIFF nunca se quedan como están —el
    /// disco del iPod no da abasto—, pero con "Original sin pérdida" van a
    /// <b>ALAC</b> y no a MP3: "sin pérdida" tiene que significar sin pérdida, y
    /// convertir a MP3 ahí sería esconder una pérdida debajo de una etiqueta que
    /// promete lo contrario.
    /// </summary>
    [Theory]
    [InlineData("a.wav", AudioQuality.OriginalLossless, AudioCodec.Alac, "m4a")]
    [InlineData("a.aiff", AudioQuality.OriginalLossless, AudioCodec.Alac, "m4a")]
    [InlineData("a.aifc", AudioQuality.OriginalLossless, AudioCodec.Alac, "m4a")]
    [InlineData("a.wav", AudioQuality.Compressed, AudioCodec.Mp3, "mp3")]
    [InlineData("a.aiff", AudioQuality.Compressed, AudioCodec.Mp3, "mp3")]
    [InlineData("a.flac", AudioQuality.OriginalLossless, AudioCodec.None, null)]
    [InlineData("a.m4a", AudioQuality.OriginalLossless, AudioCodec.None, null)]
    [InlineData("a.mp3", AudioQuality.OriginalLossless, AudioCodec.None, null)]
    [InlineData("a.flac", AudioQuality.Compressed, AudioCodec.Mp3, "mp3")]
    [InlineData("a.m4a", AudioQuality.Compressed, AudioCodec.Mp3, "mp3")]
    public void LaTablaDeConversion(
        string name, AudioQuality quality, AudioCodec codec, string? extension)
    {
        AudioConversion conversion = AudioConversionRules.For(name, quality);

        Assert.Equal(codec, conversion.Codec);
        Assert.Equal(extension, conversion.Extension);
        Assert.Equal(codec != AudioCodec.None, AudioConversionRules.Converts(name, quality));
    }

    /// <summary>
    /// Un MP3 con "Comprimido" <b>no</b> se vuelve a codificar: pasarlo otra vez
    /// por el codificador pierde calidad y no gana un solo byte.
    /// </summary>
    [Fact]
    public void UnMp3NoSeRecodificaAMp3()
    {
        Assert.False(AudioConversionRules.Converts("a.mp3", AudioQuality.Compressed));
    }

    // MARK: - Cuándo se rehace

    [Fact]
    public void SiElArchivoYaSirveNoSePreparaNada()
    {
        PreparedMusicDecision decision = PreparedMusicPlan.Decide(
            needed: false, preparedExists: false, catalogSourceSize: 100, currentSourceSize: 100,
            sourceModifiedUtc: Now, preparedModifiedUtc: null);

        Assert.Equal(PreparedMusicAction.None, decision.Action);
    }

    [Fact]
    public void SinPreparadoSeArma()
    {
        Assert.Equal(PreparedMusicAction.Build, Decide(preparedExists: false).Action);
    }

    [Fact]
    public void UnPreparadoAlDiaNoSeRehace()
    {
        PreparedMusicDecision decision = Decide(
            sourceModified: Now, preparedModified: Now.AddMinutes(1));

        Assert.Equal(PreparedMusicAction.Keep, decision.Action);
    }

    /// <summary>
    /// El origen cambió: el usuario lo reemplazó o lo volvió a codificar. El
    /// tamaño sale del catálogo (ST-201), así que no cuesta una consulta extra.
    /// </summary>
    [Fact]
    public void SiElOrigenCambioDeTamanoSeRehace()
    {
        PreparedMusicDecision decision = Decide(catalogSize: 100, currentSize: 250);

        Assert.Equal(PreparedMusicAction.Build, decision.Action);
        Assert.Contains("tamaño", decision.Reason);
    }

    [Fact]
    public void SiElOrigenEsMasNuevoSeRehace()
    {
        PreparedMusicDecision decision = Decide(
            sourceModified: Now.AddHours(1), preparedModified: Now);

        Assert.Equal(PreparedMusicAction.Build, decision.Action);
        Assert.Contains("más nuevo", decision.Reason);
    }

    /// <summary>
    /// Los sistemas de archivos no guardan todos la misma precisión —FAT
    /// redondea a dos segundos—. Sin holgura, un preparado se reharía en cada
    /// pasada, para siempre.
    /// </summary>
    [Fact]
    public void UnaDiferenciaDeFechaDentroDeLaHolguraNoCuenta()
    {
        Assert.Equal(PreparedMusicAction.Keep,
            Decide(sourceModified: Now.AddSeconds(1), preparedModified: Now).Action);
    }

    [Fact]
    public void SinFechasSeRehaceQueEsElLadoSeguro()
    {
        // Directo, sin el ayudante: acá el nulo es el caso, no un "sin especificar".
        PreparedMusicDecision decision = PreparedMusicPlan.Decide(
            needed: true, preparedExists: true, catalogSourceSize: 100, currentSourceSize: 100,
            sourceModifiedUtc: null, preparedModifiedUtc: Now);

        Assert.Equal(PreparedMusicAction.Build, decision.Action);
        Assert.Contains("fecha", decision.Reason);
    }

    /// <summary>Un catálogo viejo no trae el tamaño; entonces decide la fecha.</summary>
    [Fact]
    public void SinTamanoEnElCatalogoDecideLaFecha()
    {
        Assert.Equal(PreparedMusicAction.Keep,
            Decide(catalogSize: null, currentSize: 999, sourceModified: Now, preparedModified: Now).Action);
    }

    // MARK: - De punta a punta

    /// <summary>
    /// <b>La prueba que sostiene la promesa de Ajustes.</b> Una canción
    /// referenciada cuyo archivo ya dice lo que dice el catálogo no genera
    /// ningún preparado: al iPod viaja el original y el disco del usuario no se
    /// llena con una copia de su biblioteca entera.
    /// </summary>
    [Fact]
    public async Task UnaCancionQueYaCoincideNoGeneraPreparado()
    {
        LibraryItem item = Referenced("cancion.mp3", "Ingrata", "Café Tacvba", "Ré");
        Tag(item.SourcePath, item.Metadata!);

        PreparedMusicResult result = await PreparedMusicBuilder.EnsureAsync(item, _staging);

        Assert.Equal(PreparedMusicAction.None, result.Action);
        Assert.Null(result.Path);
        Assert.Empty(Directory.GetFiles(_staging));
    }

    [Fact]
    public async Task UnaCancionCorregidaSiGeneraPreparadoYConSuIdentificador()
    {
        LibraryItem item = Referenced("cancion.mp3", "Ingrata", "Café Tacvba", "Ré");
        Tag(item.SourcePath, new TrackMetadata { Title = "Título viejo" });

        PreparedMusicResult result = await PreparedMusicBuilder.EnsureAsync(item, _staging);

        Assert.Equal(PreparedMusicAction.Build, result.Action);
        Assert.Equal(Path.Combine(_staging, CatalogPath.PreparedFileName(item.Id, "mp3")), result.Path);

        // Y el preparado lleva lo que dice el catálogo, no lo que decía el
        // archivo del usuario.
        Assert.Equal("Ingrata", LocalTagReader.Read(result.Path!).Title);

        // El original del usuario NO se tocó.
        Assert.Equal("Título viejo", LocalTagReader.Read(item.SourcePath).Title);
    }

    [Fact]
    public async Task UnSegundoPasoNoLoVuelveAArmar()
    {
        LibraryItem item = Referenced("cancion.mp3", "Ingrata", "Café Tacvba", "Ré");
        Tag(item.SourcePath, new TrackMetadata { Title = "Título viejo" });

        PreparedMusicResult first = await PreparedMusicBuilder.EnsureAsync(item, _staging);
        item.PreparedPath = first.Path;

        PreparedMusicResult second = await PreparedMusicBuilder.EnsureAsync(item, _staging);

        Assert.Equal(PreparedMusicAction.Keep, second.Action);
        Assert.Equal(first.Path, second.Path);
        Assert.Single(Directory.GetFiles(_staging));
    }

    /// <summary>
    /// La música copiada es su propio preparado (ST-241): prepararla otra vez
    /// sería la copia de la copia que esa invariante vino a evitar.
    /// </summary>
    [Fact]
    public async Task LaMusicaCopiadaNoSePrepara()
    {
        LibraryItem item = Referenced("cancion.mp3", "Ingrata", "Café Tacvba", "Ré");
        item.Storage = ItemStorageRules.CopyValue;

        PreparedMusicResult result = await PreparedMusicBuilder.EnsureAsync(item, _staging);

        Assert.Equal(PreparedMusicAction.None, result.Action);
        Assert.Empty(Directory.GetFiles(_staging));
    }

    /// <summary>
    /// Un original que no está no se borra ni se marca como error: se dice que no
    /// está, y el elemento sigue en el catálogo como no disponible (ST-241).
    /// </summary>
    [Fact]
    public async Task UnOriginalQueNoEstaNoRompeNiSeBorra()
    {
        LibraryItem item = Referenced("fantasma.mp3", "Ingrata", "Café Tacvba", "Ré", write: false);

        PreparedMusicResult result = await PreparedMusicBuilder.EnsureAsync(item, _staging);

        Assert.Equal(PreparedMusicAction.None, result.Action);
        Assert.Contains("no está", result.Reason);
        Assert.Null(item.PreparedPath);
    }

    [Fact]
    public async Task UnWavSiempreSeConvierteYConOriginalVaAAlac()
    {
        LibraryItem item = Referenced("cancion.wav", "Ingrata", "Café Tacvba", "Ré");

        string? convertedFrom = null;
        AudioCodec used = AudioCodec.None;

        PreparedMusicResult result = await PreparedMusicBuilder.EnsureAsync(
            item, _staging,
            transcode: (source, destination, codec, _) =>
            {
                convertedFrom = source;
                used = codec;
                MinimalAudioFiles.WriteM4a(destination);
                return Task.FromResult(new FileInfo(destination).Length);
            });

        Assert.Equal(PreparedMusicAction.Build, result.Action);
        Assert.Equal(item.SourcePath, convertedFrom);
        Assert.Equal(AudioCodec.Alac, used);
        Assert.Equal(Path.Combine(_staging, CatalogPath.PreparedFileName(item.Id, "m4a")), result.Path);
        Assert.Equal("Ingrata", LocalTagReader.Read(result.Path!).Title);
    }

    /// <summary>
    /// Con "Comprimido" también va el FLAC; con "Original sin pérdida" no. Es el
    /// interruptor de Ajustes que hasta ST-244 no leía nadie.
    /// </summary>
    [Theory]
    [InlineData(AudioQuality.Compressed, true)]
    [InlineData(AudioQuality.OriginalLossless, false)]
    public async Task ElFlacSeConvierteSoloConComprimido(AudioQuality quality, bool converted)
    {
        LibraryItem item = Referenced("cancion.flac", "Ingrata", "Café Tacvba", "Ré");
        Tag(item.SourcePath, item.Metadata!);

        bool passedThroughTheEncoder = false;

        PreparedMusicResult result = await PreparedMusicBuilder.EnsureAsync(
            item, _staging, quality,
            transcode: (_, destination, _, _) =>
            {
                passedThroughTheEncoder = true;
                MinimalAudioFiles.WriteMp3(destination);
                return Task.FromResult(new FileInfo(destination).Length);
            });

        Assert.Equal(converted, passedThroughTheEncoder);

        // Sin comprimir, el archivo ya coincide con el catálogo y no hace falta
        // preparado ninguno.
        Assert.Equal(converted ? PreparedMusicAction.Build : PreparedMusicAction.None, result.Action);
    }

    [Fact]
    public async Task SinConvertidorSeDiceQueNoEnVezDeCopiarUnWav()
    {
        LibraryItem item = Referenced("cancion.wav", "Ingrata", "Café Tacvba", "Ré");

        PreparedMusicResult result = await PreparedMusicBuilder.EnsureAsync(item, _staging);

        Assert.Equal(PreparedMusicAction.None, result.Action);
        Assert.Contains("convertidor", result.Reason);
        Assert.Empty(Directory.GetFiles(_staging));
    }

    // MARK: - Fixture

    private static DateTimeOffset Now => new(2026, 9, 7, 12, 0, 0, TimeSpan.Zero);

    private static PreparedMusicDecision Decide(
        bool needed = true,
        bool preparedExists = true,
        long? catalogSize = 100,
        long currentSize = 100,
        DateTimeOffset? sourceModified = null,
        DateTimeOffset? preparedModified = null) =>
        PreparedMusicPlan.Decide(
            needed, preparedExists, catalogSize, currentSize,
            sourceModified ?? Now, preparedModified ?? Now);

    private LibraryItem Referenced(
        string name, string title, string artist, string album, bool write = true)
    {
        string path = Path.Combine(_root, "ajena", name);

        if (write)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);

            switch (Path.GetExtension(name).TrimStart('.'))
            {
                case "mp3": MinimalAudioFiles.WriteMp3(path); break;
                case "flac": MinimalAudioFiles.WriteFlac(path); break;
                default: File.WriteAllBytes(path, new byte[64]); break;
            }
        }

        return new LibraryItem
        {
            Id = Guid.NewGuid(),
            Kind = LibraryItemKind.Music,
            SourcePath = path,
            Storage = ItemStorageRules.ReferenceValue,
            Metadata = new TrackMetadata { Title = title, Artist = artist, Album = album }
        };
    }

    private static void Tag(string path, TrackMetadata metadata) =>
        LocalTagWriter.Write(path, metadata);
}
