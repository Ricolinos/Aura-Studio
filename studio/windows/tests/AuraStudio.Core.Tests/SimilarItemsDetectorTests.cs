using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// El detector de similares (ST-063). Lo que estos casos protegen es tanto que
/// encuentre lo que debe como que <b>no</b> junte lo que no debe: proponer
/// borrar una versión en vivo como si fuera un duplicado es el error caro.
/// </summary>
public class SimilarItemsDetectorTests
{
    private static LibraryItem Song(
        string path, string? title = null, string? artist = null, string? album = null,
        double? duration = null, bool editedByUser = false, byte[]? cover = null,
        string? lyrics = null, int? track = null, DateTimeOffset? addedAt = null)
        => new()
        {
            SourcePath = path,
            Kind = LibraryItemKind.Music,
            Status = LibraryItemStatus.Ready,
            AddedAt = addedAt,
            MetadataEditedByUser = editedByUser,
            Metadata = new TrackMetadata
            {
                Title = title,
                Artist = artist,
                Album = album,
                DurationSeconds = duration,
                CoverArtData = cover,
                SyncedLyrics = lyrics,
                TrackNumber = track
            }
        };

    private static LibraryItem Photo(string path) =>
        new() { SourcePath = path, Kind = LibraryItemKind.Photo, Status = LibraryItemStatus.Ready };

    private static LibraryItem Video(
        string path, string? title = null, double? duration = null,
        string? series = null, int? season = null, int? episode = null, string? category = null)
        => new()
        {
            SourcePath = path,
            Kind = LibraryItemKind.Video,
            Status = LibraryItemStatus.Ready,
            SeriesName = series,
            Season = season,
            Episode = episode,
            Category = category,
            Metadata = new TrackMetadata { Title = title, DurationSeconds = duration }
        };

    /// <summary>Tamaños fijos por ruta: el detector nunca toca el disco en estas pruebas.</summary>
    private static Func<string, long> Sizes(params (string Path, long Size)[] sizes)
    {
        var map = sizes.ToDictionary(entry => entry.Path, entry => entry.Size, StringComparer.OrdinalIgnoreCase);
        return path => map.GetValueOrDefault(path);
    }

    private static readonly Func<string, long> NoSizes = _ => 0;

    // MARK: - El caso que motivó el detector

    [Fact]
    public void TheSameSongWrittenTwoWaysIsFound()
    {
        // ST-063, textual del encargo: "01 Amor"/"SodaStereo" contra
        // "Amor"/"Soda-Stereo" tiene que aparecer como posible duplicado.
        LibraryItem a = Song(@"C:\m\01 Amor.mp3", "01 Amor", "SodaStereo", "Nada Personal", 214);
        LibraryItem b = Song(@"C:\m\Amor.mp3", "Amor", "Soda-Stereo", "Nada Personal", 215);

        SimilarItemsGroup group = Assert.Single(SimilarItemsDetector.Detect([a, b], fileSize: NoSizes));

        Assert.Equal(2, group.Items.Count);
        Assert.Equal(LibraryItemKind.Music, group.Kind);
        Assert.Contains(group.Reasons, reason => reason.Contains("Mismo título"));
        Assert.Contains(group.Reasons, reason => reason.Contains("Artista escrito distinto"));
    }

    [Fact]
    public void TheGroupProposesTheSpellingUsedMostInTheLibrary()
    {
        // "Soda Stereo" está escrito así en el resto de la biblioteca, así que
        // es el nombre al que se propone unificar — nunca se aplica solo.
        LibraryItem a = Song(@"C:\m\01 Amor.mp3", "01 Amor", "SodaStereo", "Nada Personal", 214);
        LibraryItem b = Song(@"C:\m\Amor.mp3", "Amor", "Soda Stereo", "Nada Personal", 215);
        LibraryItem otra = Song(@"C:\m\Persiana.mp3", "Persiana Americana", "Soda Stereo", "Signos", 300);

        SimilarItemsGroup group = SimilarItemsDetector.Detect([a, b, otra], fileSize: NoSizes)[0];

        SimilarityProposedEdit edit = Assert.Single(
            group.ProposedEdits, e => e.Field == SimilarityField.Artist);
        Assert.Equal("SodaStereo", edit.CurrentValue);
        Assert.Equal("Soda Stereo", edit.ProposedValue);
        Assert.Contains("Soda Stereo", group.Suggestion);
    }

    [Fact]
    public void ATitleWithItsTrackNumberGetsACleanOneProposed()
    {
        LibraryItem a = Song(@"C:\m\01 Amor.mp3", "01 Amor", "Soda Stereo", "Nada Personal", 214);
        LibraryItem b = Song(@"C:\m\Amor.mp3", "Amor", "Soda Stereo", "Nada Personal", 215);

        SimilarItemsGroup group = SimilarItemsDetector.Detect([a, b], fileSize: NoSizes)[0];

        SimilarityProposedEdit edit = Assert.Single(
            group.ProposedEdits, e => e.Field == SimilarityField.Title);
        Assert.Equal("01 Amor", edit.CurrentValue);
        Assert.Equal("Amor", edit.ProposedValue);
    }

    // MARK: - Lo que NO se debe juntar

    [Fact]
    public void ALiveVersionIsNotADuplicateOfTheStudioOne()
    {
        // Si esto se marcara como duplicado, la sugerencia sería borrar una de
        // las dos: exactamente el error que no se puede cometer.
        LibraryItem estudio = Song(@"C:\m\Amor.mp3", "Amor", "Soda Stereo", "Nada Personal", 214);
        LibraryItem vivo = Song(@"C:\m\Amor vivo.mp3", "Amor (En vivo)", "Soda Stereo", "Ruido Blanco", 240);

        IReadOnlyList<SimilarItemsGroup> groups = SimilarItemsDetector.Detect([estudio, vivo], fileSize: NoSizes);

        Assert.All(groups, group => Assert.NotEqual(SimilarityConfidence.Duplicate, group.Confidence));
        if (groups.Count > 0)
            Assert.Contains(groups[0].Reasons, reason => reason.Contains("otra versión"));
    }

    [Fact]
    public void TwoDifferentSongsAreNotGrouped()
    {
        LibraryItem a = Song(@"C:\m\Amor.mp3", "Amor", "Soda Stereo", "Nada Personal", 214);
        LibraryItem b = Song(@"C:\m\Persiana.mp3", "Persiana Americana", "Soda Stereo", "Signos", 300);

        Assert.Empty(SimilarItemsDetector.Detect([a, b], fileSize: NoSizes));
    }

    [Fact]
    public void TheSameTitleByDifferentArtistsIsNotGrouped()
    {
        // Hay muchas canciones llamadas "Amor". Sin artista ni duración en
        // común, no son la misma.
        LibraryItem a = Song(@"C:\m\a.mp3", "Amor", "Soda Stereo", "Nada Personal", 214);
        LibraryItem b = Song(@"C:\m\b.mp3", "Amor", "Café Tacvba", "Re", 190);

        Assert.Empty(SimilarItemsDetector.Detect([a, b], fileSize: NoSizes));
    }

    [Fact]
    public void TwoConsecutivePhotosAreNotDuplicates()
    {
        // IMG_0001 e IMG_0002 son tomas distintas.
        Assert.Empty(SimilarItemsDetector.Detect(
            [Photo(@"C:\f\IMG_0001.jpg"), Photo(@"C:\f\IMG_0002.jpg")], fileSize: NoSizes));
    }

    [Fact]
    public void ASingleItemNeverFormsAGroup()
        => Assert.Empty(SimilarItemsDetector.Detect([Song(@"C:\m\a.mp3", "Amor")], fileSize: NoSizes));

    // MARK: - Duplicados de verdad

    [Fact]
    public void TheSameFileTwiceWithDifferentNamesIsADuplicate()
    {
        // Mismo tamaño exacto: se encuentran aunque el nombre no coincida.
        LibraryItem a = Song(@"C:\m\Amor.mp3", "Amor", "Soda Stereo", "Nada Personal", 214);
        LibraryItem b = Song(@"C:\m\pista01.mp3", "Amor", "Soda Stereo", "Nada Personal", 214);

        SimilarItemsGroup group = Assert.Single(SimilarItemsDetector.Detect(
            [a, b], fileSize: Sizes((@"C:\m\Amor.mp3", 4_200_000), (@"C:\m\pista01.mp3", 4_200_000))));

        Assert.Equal(SimilarityConfidence.Duplicate, group.Confidence);
        Assert.Contains(group.Reasons, reason => reason.Contains("Mismo tamaño exacto") && reason.Contains("4.2 MB"));
        Assert.Contains("eliminar el resto", group.Suggestion);
    }

    [Fact]
    public void ACopiedPhotoIsFoundByItsName()
    {
        SimilarItemsGroup group = Assert.Single(SimilarItemsDetector.Detect(
            [Photo(@"C:\f\IMG_0001.jpg"), Photo(@"C:\f\IMG_0001 copia.jpg")], fileSize: NoSizes));

        Assert.Equal(LibraryItemKind.Photo, group.Kind);
        Assert.Contains(group.Reasons, reason => reason.Contains("copia"));
    }

    [Fact]
    public void TheSameEpisodeTwiceIsFoundWithoutLookingAtTheTitle()
    {
        // Serie, temporada y episodio iguales: ya se sabe qué es, el título no
        // hace falta. Acá comparten tamaño exacto, que es lo que los pone en el
        // mismo bloque de comparación (ver la prueba de abajo).
        LibraryItem a = Video(@"C:\v\cap1.mkv", "Capítulo uno", 1300, "Chespirito", 1, 1);
        LibraryItem b = Video(@"C:\v\S01E01.mp4", "S01E01", 1300, "Chespirito", 1, 1);

        SimilarItemsGroup group = Assert.Single(SimilarItemsDetector.Detect(
            [a, b], fileSize: Sizes((@"C:\v\cap1.mkv", 700_000_000), (@"C:\v\S01E01.mp4", 700_000_000))));

        Assert.Equal(SimilarityConfidence.Duplicate, group.Confidence);
        Assert.Contains(group.Reasons, reason => reason.Contains("Mismo episodio"));
    }

    [Fact]
    public void TwoCopiesOfAnEpisodeWithUnrelatedNamesAndSizesAreNotCompared()
    {
        // **Límite conocido, igual que en macOS.** El detector no compara todos
        // contra todos: agrupa por las 3 primeras letras del título y del nombre
        // de archivo, y por tamaño exacto. Dos copias del mismo episodio que no
        // coinciden en ninguna de esas tres cosas nunca llegan a compararse, así
        // que la regla de "mismo episodio" no alcanza a aplicarse.
        //
        // Se deja documentado en vez de corregirlo acá: arreglarlo solo en
        // Windows haría que las dos apps mostraran duplicados distintos sobre la
        // misma biblioteca, que es justo lo que ST-082 se propuso evitar. Ver
        // ST-084 — corresponde coordinarlo con la app de macOS.
        LibraryItem a = Video(@"C:\v\cap1.mkv", "Capítulo uno", 1300, "Chespirito", 1, 1);
        LibraryItem b = Video(@"C:\v\S01E01.mp4", "S01E01", 1300, "Chespirito", 1, 1);

        Assert.Empty(SimilarItemsDetector.Detect([a, b], fileSize: NoSizes));
    }

    [Fact]
    public void TwoCopiesOfAnEpisodeWithSimilarNamesAreFound()
    {
        // El caso frecuente sí funciona: los nombres comparten prefijo.
        LibraryItem a = Video(@"C:\v\Chespirito S01E01.mkv", "Chespirito S01E01", 1300, "Chespirito", 1, 1);
        LibraryItem b = Video(@"C:\v\Chespirito S01E01 (copia).mp4", "Chespirito S01E01", 1300, "Chespirito", 1, 1);

        SimilarItemsGroup group = Assert.Single(SimilarItemsDetector.Detect([a, b], fileSize: NoSizes));

        Assert.Contains(group.Reasons, reason => reason.Contains("Mismo episodio"));
    }

    [Fact]
    public void ThreeCopiesEndUpInOneGroupNotThree()
    {
        // Se agrupan transitivamente: si A≈B y B≈C, los tres son un solo grupo
        // y el usuario decide una vez, no tres.
        LibraryItem a = Song(@"C:\m\Amor.mp3", "Amor", "Soda Stereo", "Nada Personal", 214);
        LibraryItem b = Song(@"C:\m\01 Amor.mp3", "01 Amor", "Soda Stereo", "Nada Personal", 214);
        LibraryItem c = Song(@"C:\m\Amor (1).mp3", "Amor", "Soda Stereo", "Nada Personal", 215);

        SimilarItemsGroup group = Assert.Single(SimilarItemsDetector.Detect([a, b, c], fileSize: NoSizes));
        Assert.Equal(3, group.Items.Count);
    }

    // MARK: - Cuál conservar

    [Fact]
    public void TheLosslessCopyIsTheOneToKeep()
    {
        LibraryItem mp3 = Song(@"C:\m\Amor.mp3", "Amor", "Soda Stereo", "Nada Personal", 214);
        LibraryItem flac = Song(@"C:\m\Amor.flac", "Amor", "Soda Stereo", "Nada Personal", 214);

        SimilarItemsGroup group = SimilarItemsDetector.Detect([mp3, flac], fileSize: NoSizes)[0];

        Assert.Equal(flac.Id, group.SuggestedKeepId);
        Assert.Equal(flac.Id, group.Items[0].Id);           // el sugerido va primero
        Assert.Contains("FLAC sin pérdida", group.Suggestion);
    }

    [Fact]
    public void WhatTheUserCorrectedByHandWinsOverWhatWasReadAutomatically()
    {
        LibraryItem automatica = Song(@"C:\m\a.mp3", "Amor", "Soda Stereo", "Nada Personal", 214);
        LibraryItem corregida = Song(@"C:\m\b.mp3", "Amor", "Soda Stereo", "Nada Personal", 214,
            editedByUser: true);

        SimilarItemsGroup group = SimilarItemsDetector.Detect([automatica, corregida], fileSize: NoSizes)[0];

        Assert.Equal(corregida.Id, group.SuggestedKeepId);
        Assert.Contains("corregido a mano", group.Suggestion);
    }

    [Fact]
    public void TheCopyWithCoverAndLyricsBeatsTheBareOne()
    {
        LibraryItem pelada = Song(@"C:\m\a.mp3", "Amor", "Soda Stereo", "Nada Personal", 214);
        LibraryItem completa = Song(@"C:\m\b.mp3", "Amor", "Soda Stereo", "Nada Personal", 214,
            cover: [1, 2, 3], lyrics: "[00:01.00] hola");

        SimilarItemsGroup group = SimilarItemsDetector.Detect([pelada, completa], fileSize: NoSizes)[0];

        Assert.Equal(completa.Id, group.SuggestedKeepId);
        Assert.Contains("con carátula", group.Suggestion);
        Assert.Contains("con letra", group.Suggestion);
    }

    [Fact]
    public void TheKeepScoreRewardsWhatTheUserWouldMiss()
    {
        LibraryItem pelada = Song(@"C:\m\a.mp3", "Amor");
        LibraryItem rica = Song(@"C:\m\b.flac", "Amor", "Soda Stereo", "Nada Personal",
            cover: [1], lyrics: "x", track: 3, editedByUser: true);

        Assert.True(
            SimilarItemsDetector.KeepScore(rica, 100, 100) >
            SimilarItemsDetector.KeepScore(pelada, 100, 100));
    }

    [Fact]
    public void AtEqualScoreTheOneAddedFirstWins()
    {
        var older = DateTimeOffset.Parse("2026-01-01T00:00:00Z");
        LibraryItem primera = Song(@"C:\m\a.mp3", "Amor", "Soda Stereo", "Nada Personal", 214, addedAt: older);
        LibraryItem segunda = Song(@"C:\m\b.mp3", "Amor", "Soda Stereo", "Nada Personal", 214,
            addedAt: older.AddDays(30));

        SimilarItemsGroup group = SimilarItemsDetector.Detect([segunda, primera], fileSize: NoSizes)[0];
        Assert.Equal(primera.Id, group.SuggestedKeepId);
    }

    // MARK: - Grupos ignorados

    [Fact]
    public void AGroupTheUserDismissedDoesNotComeBack()
    {
        LibraryItem a = Song(@"C:\m\01 Amor.mp3", "01 Amor", "Soda Stereo", "Nada Personal", 214);
        LibraryItem b = Song(@"C:\m\Amor.mp3", "Amor", "Soda Stereo", "Nada Personal", 215);

        SimilarItemsGroup group = SimilarItemsDetector.Detect([a, b], fileSize: NoSizes)[0];

        Assert.Empty(SimilarItemsDetector.Detect(
            [a, b], ignoredGroupIds: new HashSet<string> { group.Id }, fileSize: NoSizes));
    }

    [Fact]
    public void TheGroupIdDoesNotDependOnTheOrderOfItsMembers()
    {
        // Si cambiara, un grupo que el usuario ya descartó reaparecería.
        Guid x = Guid.NewGuid(), y = Guid.NewGuid();
        Assert.Equal(SimilarItemsGroup.KeyFor([x, y]), SimilarItemsGroup.KeyFor([y, x]));
    }

    // MARK: - Orden y alcance

    [Fact]
    public void TheMostCertainGroupsComeFirst()
    {
        LibraryItem dupA = Song(@"C:\m\a.mp3", "Amor", "Soda Stereo", "Nada Personal", 214);
        LibraryItem dupB = Song(@"C:\m\b.mp3", "Amor", "Soda Stereo", "Nada Personal", 214);
        LibraryItem posA = Song(@"C:\m\z1.mp3", "Zamba", "Mercedes Sosa", "Uno", 200);
        LibraryItem posB = Song(@"C:\m\z2.mp3", "Zamba (En vivo)", "Mercedes Sosa", "Vivo", 205);

        IReadOnlyList<SimilarItemsGroup> groups = SimilarItemsDetector.Detect(
            [posA, posB, dupA, dupB],
            fileSize: Sizes((@"C:\m\a.mp3", 4_000_000), (@"C:\m\b.mp3", 4_000_000)));

        Assert.True(groups.Count >= 2);
        Assert.Equal(SimilarityConfidence.Duplicate, groups[0].Confidence);
        Assert.True(groups[0].Confidence >= groups[^1].Confidence);
    }

    [Fact]
    public void MusicPhotosAndVideosNeverMixInTheSameGroup()
    {
        LibraryItem cancion = Song(@"C:\m\Amor.mp3", "Amor", "Soda Stereo", "Nada Personal", 214);
        LibraryItem foto = Photo(@"C:\f\Amor.jpg");
        LibraryItem video = Video(@"C:\v\Amor.mp4", "Amor", 214);

        Assert.Empty(SimilarItemsDetector.Detect([cancion, foto, video], fileSize: NoSizes));
    }

    [Fact]
    public void AnUnsupportedFileIsIgnoredEntirely()
    {
        var a = new LibraryItem { SourcePath = @"C:\x\a.pdf", Kind = LibraryItemKind.Unsupported };
        var b = new LibraryItem { SourcePath = @"C:\x\a copia.pdf", Kind = LibraryItemKind.Unsupported };

        Assert.Empty(SimilarItemsDetector.Detect([a, b], fileSize: NoSizes));
    }

    [Fact]
    public void AnEmptyLibraryGivesNothing()
        => Assert.Empty(SimilarItemsDetector.Detect([], fileSize: NoSizes));

    // MARK: - Ortografía canónica

    [Fact]
    public void TheCanonicalSpellingIsTheMostFrequentOne()
    {
        List<LibraryItem> library =
        [
            Song(@"C:\m\1.mp3", artist: "Soda Stereo"),
            Song(@"C:\m\2.mp3", artist: "Soda Stereo"),
            Song(@"C:\m\3.mp3", artist: "SodaStereo")
        ];

        Assert.Equal("Soda Stereo",
            SimilarItemsDetector.CanonicalSpelling("SodaStereo", library, SimilarityField.Artist));
    }

    [Fact]
    public void AtEqualFrequencyTheLongerSpellingWins()
    {
        // "Soda Stereo" contra "SodaStereo": los espacios y los acentos son
        // información, no ruido.
        List<LibraryItem> library =
        [
            Song(@"C:\m\1.mp3", artist: "Soda Stereo"),
            Song(@"C:\m\2.mp3", artist: "SodaStereo")
        ];

        Assert.Equal("Soda Stereo",
            SimilarItemsDetector.CanonicalSpelling("SodaStereo", library, SimilarityField.Artist));
    }

    [Fact]
    public void WithoutAnyMatchTheValueIsLeftAsItIs()
        => Assert.Equal("Nadie",
            SimilarItemsDetector.CanonicalSpelling("Nadie", [], SimilarityField.Artist));
}
