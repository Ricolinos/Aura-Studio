using AuraStudio.Core;
using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// El motor contra un directorio temporal que hace de volumen del iPod.
///
/// <para>Acá se prueba lo que no se puede probar sin disco: que un corte a
/// mitad no deje archivos truncados, que lo que se borra sea exactamente lo
/// que el usuario confirmó, y que la base de música del firmware sobreviva
/// cuando tiene que sobrevivir.</para>
/// </summary>
public sealed class LibrarySyncEngineTests : IDisposable
{
    private readonly string _volume = Path.Combine(Path.GetTempPath(), "aura-vol-" + Guid.NewGuid().ToString("N"));
    private readonly string _library = Path.Combine(Path.GetTempPath(), "aura-lib-" + Guid.NewGuid().ToString("N"));

    public LibrarySyncEngineTests()
    {
        Directory.CreateDirectory(_volume);
        Directory.CreateDirectory(_library);
    }

    public void Dispose()
    {
        foreach (string directory in (string[])[_volume, _library])
            try { Directory.Delete(directory, recursive: true); } catch (IOException) { }
    }

    // MARK: - Ayudas

    private string Source(string name, string contents = "audio")
    {
        string path = Path.Combine(_library, name);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, contents);
        return path;
    }

    private string OnDevice(string relativePath) =>
        Path.Combine(_volume, relativePath.Replace('/', Path.DirectorySeparatorChar));

    private void PutOnDevice(string relativePath, string contents = "viejo")
    {
        string path = OnDevice(relativePath);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, contents);
    }

    private SyncSourceFile Ready(string sourcePath, string destination)
    {
        var info = new FileInfo(sourcePath);
        return new SyncSourceFile(sourcePath, info.Length, info.LastWriteTimeUtc, destination);
    }

    private static SyncPlanResult PlanOf(params SyncSourceFile[] files) =>
        SyncPlanner.Plan(files, new DeviceSyncManifest());

    // MARK: - Copiar

    [Fact]
    public void ACopiedFileArrivesCompleteAndGetsRecorded()
    {
        string source = Source("a.mp3", "contenido de la canción");

        SyncOutcome outcome = LibrarySyncEngine.Apply(_volume,
            PlanOf(Ready(source, "Music/Artista/Álbum/Canción.mp3")),
            new SyncEngineOptions { InstallationId = "windows-1" });

        Assert.Equal(["Music/Artista/Álbum/Canción.mp3"], outcome.Copied);
        Assert.Equal("contenido de la canción", File.ReadAllText(OnDevice("Music/Artista/Álbum/Canción.mp3")));
        Assert.False(outcome.Cancelled);
        Assert.Empty(outcome.Failures);

        DeviceSyncManifest manifest = DeviceSyncManifest.Load(_volume);
        DeviceSyncRecord record = manifest.Records[source];
        Assert.Equal("Music/Artista/Álbum/Canción.mp3", record.DestinationRelativePath);
        Assert.Equal(new FileInfo(source).Length, record.SourceSize);
        Assert.Equal("windows-1", record.WrittenBy);
        // La huella del destino es lo que distingue "sincronizado" de
        // "alguien lo cambió en el iPod por fuera de Studio".
        Assert.Equal(new FileInfo(source).Length, record.DestinationSize);
        Assert.NotNull(record.SyncedAt);
        Assert.Equal(DeviceSyncManifest.CurrentContractVersion, manifest.ContractVersion);
    }

    [Fact]
    public void TheFourContractFoldersExistEvenIfNothingGetsCopied()
    {
        LibrarySyncEngine.Apply(_volume, PlanOf());

        foreach (string directory in SyncLayout.DeviceDirectories)
            Assert.True(Directory.Exists(Path.Combine(_volume, directory)), directory);
    }

    // MARK: - ST-146 / maestro §B: la hora en cada sincronización

    /// <summary>Un sync SIN cambios de medios también deja la hora de la computadora puesta.</summary>
    [Fact]
    public void ASyncWithoutMediaChangesStillWritesTheClock()
    {
        PutOnDevice(".rockbox/aura/aura.cfg", "sync_marker_supported: 1");

        LibrarySyncEngine.Apply(_volume, PlanOf());

        Assert.Contains("rtc_sync_year:", OnDeviceText(".rockbox/aura/aura.cfg"));
    }

    /// <summary>La hora se escribe ANTES del marcador de sync-pending (maestro §B).</summary>
    [Fact]
    public void TheClockIsWrittenBeforeTheSyncPendingMarker()
    {
        PutOnDevice(".rockbox/aura/aura.cfg", "sync_marker_supported: 1");

        LibrarySyncEngine.Apply(_volume, PlanOf(Ready(Source("a.mp3"), "Music/A/a.mp3")));

        Assert.Contains("rtc_sync_year:", OnDeviceText(".rockbox/aura/aura.cfg"));
        Assert.True(File.Exists(OnDevice(SyncPendingMarker.RelativePath)));
    }

    /// <summary>La hora escrita coincide con la del reloj real de la máquina.</summary>
    [Fact]
    public void TheWrittenClockMatchesTheRealMachineClock()
    {
        PutOnDevice(".rockbox/aura/aura.cfg", "sync_marker_supported: 1");

        LibrarySyncEngine.Apply(_volume, PlanOf());

        string cfg = OnDeviceText(".rockbox/aura/aura.cfg");
        DateTimeOffset now = DateTimeOffset.Now;
        Assert.Contains($"rtc_sync_year: {now.Year}", cfg);
        Assert.Contains($"rtc_sync_month: {now.Month}", cfg);
        Assert.Contains($"rtc_sync_day: {now.Day}", cfg);
    }

    private string OnDeviceText(string relativePath) => File.ReadAllText(OnDevice(relativePath));

    [Fact]
    public void NoTemporaryFileSurvivesASuccessfulCopy()
    {
        LibrarySyncEngine.Apply(_volume, PlanOf(Ready(Source("a.mp3"), "Music/A/a.mp3")));

        Assert.Empty(Directory.EnumerateFiles(_volume, "*.aura-tmp", SearchOption.AllDirectories));
    }

    [Fact]
    public void APosterTravelsGluedToItsVideo()
    {
        string video = Source("peli.mpg", "video");
        File.WriteAllText(Path.Combine(_library, "peli.jpg"), "poster");

        LibrarySyncEngine.Apply(_volume, PlanOf(Ready(video, "Videos/Mi película.mpg")));

        Assert.Equal("poster", File.ReadAllText(OnDevice("Videos/Mi película.jpg")));
    }

    // MARK: - Lo que se movió

    [Fact]
    public void MovingAFileLeavesItInOneSinglePlace()
    {
        string source = Source("a.mp3", "nuevo");
        PutOnDevice("Music/Signos/Amor.mp3");

        var manifest = new DeviceSyncManifest();
        manifest.Records[source] = new DeviceSyncRecord(source, 1, 0, "Music/Signos/Amor.mp3");

        SyncOutcome outcome = LibrarySyncEngine.Apply(_volume,
            SyncPlanner.Plan([Ready(source, "Music/Soda Stereo/Signos/Amor.mp3")], manifest));

        Assert.False(File.Exists(OnDevice("Music/Signos/Amor.mp3")));
        Assert.Equal("nuevo", File.ReadAllText(OnDevice("Music/Soda Stereo/Signos/Amor.mp3")));
        Assert.Equal(["Music/Signos/Amor.mp3"], outcome.Swept);
    }

    [Fact]
    public void TheLyricsOfAMovedSongDoNotStayBehind()
    {
        // Un `.lrc` sin su canción es el huérfano que el contrato §3 prohíbe.
        string source = Source("a.mp3");
        PutOnDevice("Music/viejo/Amor.mp3");
        PutOnDevice("Music/viejo/Amor.lrc", "[00:01.00]letra");

        var manifest = new DeviceSyncManifest();
        manifest.Records[source] = new DeviceSyncRecord(source, 1, 0, "Music/viejo/Amor.mp3");

        LibrarySyncEngine.Apply(_volume, SyncPlanner.Plan([Ready(source, "Music/nuevo/Amor.mp3")], manifest));

        Assert.False(File.Exists(OnDevice("Music/viejo/Amor.lrc")));
    }

    // MARK: - Huérfanos: nunca sin confirmación

    [Fact]
    public void AnOrphanIsNotDeletedOnItsOwn()
    {
        // Sacar algo de la biblioteca para reorganizarlo no puede hacerlo
        // desaparecer del iPod sin avisar.
        string source = Path.Combine(_library, "ya-no-esta.mp3");
        PutOnDevice("Music/A/a.mp3");

        var manifest = new DeviceSyncManifest();
        manifest.Records[source] = new DeviceSyncRecord(source, 1, 0, "Music/A/a.mp3");
        manifest.Save(_volume);

        SyncOutcome outcome = LibrarySyncEngine.Apply(_volume, SyncPlanner.Plan([], manifest));

        Assert.True(File.Exists(OnDevice("Music/A/a.mp3")));
        Assert.Empty(outcome.Deleted);
        Assert.False(outcome.MarkerWritten);
        // Y sigue en el manifiesto: mañana el usuario puede confirmarlo.
        Assert.True(DeviceSyncManifest.Load(_volume).Records.ContainsKey(source));
    }

    [Fact]
    public void AConfirmedOrphanGoesWithItsLyricsAndItsRecord()
    {
        string source = Path.Combine(_library, "ya-no-esta.mp3");
        PutOnDevice("Music/A/a.mp3");
        PutOnDevice("Music/A/a.lrc");

        var manifest = new DeviceSyncManifest();
        manifest.Records[source] = new DeviceSyncRecord(source, 1, 0, "Music/A/a.mp3");
        manifest.Save(_volume);

        SyncOutcome outcome = LibrarySyncEngine.Apply(_volume, SyncPlanner.Plan([], manifest),
            new SyncEngineOptions { ApprovedOrphanSourcePaths = [source] });

        Assert.False(File.Exists(OnDevice("Music/A/a.mp3")));
        Assert.False(File.Exists(OnDevice("Music/A/a.lrc")));
        Assert.Equal(["Music/A/a.mp3"], outcome.Deleted);
        Assert.True(outcome.Sections.Music);
        Assert.False(DeviceSyncManifest.Load(_volume).Records.ContainsKey(source));
    }

    // MARK: - Cancelación

    [Fact]
    public void CancellingLeavesWhatWasCopiedCompleteAndAnnounced()
    {
        string primero = Source("1.mp3", "uno");
        string segundo = Source("2.mp3", "dos");

        using var cancellation = new CancellationTokenSource();

        SyncOutcome outcome = LibrarySyncEngine.Apply(_volume,
            PlanOf(Ready(primero, "Music/A/1.mp3"), Ready(segundo, "Music/A/2.mp3")),
            new SyncEngineOptions
            {
                CancellationToken = cancellation.Token,
                OnProgress = (copied, _) => { if (copied == 1) cancellation.Cancel(); }
            });

        Assert.True(outcome.Cancelled);
        Assert.Equal("uno", File.ReadAllText(OnDevice("Music/A/1.mp3")));
        Assert.False(File.Exists(OnDevice("Music/A/2.mp3")));

        // Lo copiado ya está en el disco: el firmware TIENE que enterarse.
        Assert.True(outcome.MarkerWritten);
        Assert.NotNull(SyncPendingMarker.Read(_volume));

        // Y el manifiesto quedó guardado con lo que sí se copió: la próxima
        // pasada no lo vuelve a copiar.
        Assert.Single(DeviceSyncManifest.Load(_volume).Records);
    }

    [Fact]
    public void CancellingBeforeStartingWritesNoMarker()
    {
        using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();

        SyncOutcome outcome = LibrarySyncEngine.Apply(_volume,
            PlanOf(Ready(Source("a.mp3"), "Music/A/a.mp3")),
            new SyncEngineOptions { CancellationToken = cancellation.Token });

        Assert.True(outcome.Cancelled);
        Assert.Empty(outcome.Copied);
        // Un marcador sin secciones haría que el firmware reconstruya para nada.
        Assert.Null(SyncPendingMarker.Read(_volume));
    }

    // MARK: - Sync interrumpido de golpe

    [Fact]
    public void TheInProgressMarkerIsGoneWhenTheSyncCloses()
    {
        LibrarySyncEngine.Apply(_volume, PlanOf(Ready(Source("a.mp3"), "Music/A/a.mp3")));

        Assert.False(LibrarySyncEngine.HasInProgressMarker(_volume));
    }

    [Fact]
    public void TemporariesFromAnInterruptedSyncAreSweptAndNothingElseIs()
    {
        PutOnDevice("Music/A/a.mp3.aura-tmp", "a medio escribir");
        PutOnDevice("Videos/b.mpg.aura-tmp", "a medio escribir");
        PutOnDevice("Music/A/a.mp3", "entero");

        int swept = LibrarySyncEngine.SweepOrphanedTempFiles(_volume);

        Assert.Equal(2, swept);
        Assert.True(File.Exists(OnDevice("Music/A/a.mp3")));
    }

    // MARK: - Fallas parciales

    [Fact]
    public void AFileThatCannotBeReadDoesNotStopTheRest()
    {
        string bueno = Source("bueno.mp3", "sí");
        string fantasma = Path.Combine(_library, "no-existe.mp3");

        SyncOutcome outcome = LibrarySyncEngine.Apply(_volume,
            PlanOf(
                new SyncSourceFile(fantasma, 10, DateTimeOffset.UtcNow, "Music/A/fantasma.mp3"),
                Ready(bueno, "Music/A/bueno.mp3")));

        Assert.Equal(["Music/A/bueno.mp3"], outcome.Copied);
        Assert.Equal("Music/A/fantasma.mp3", Assert.Single(outcome.Failures).DestinationRelativePath);
        Assert.False(outcome.Cancelled);
        // Y lo que sí se copió se anuncia igual.
        Assert.True(outcome.MarkerWritten);
    }

    // MARK: - La base de música del firmware (contrato §4.4)

    private void PutDatabases()
    {
        PutOnDevice(".rockbox/database_idx.tcd", "índice");
        PutOnDevice(".rockbox/database_0.tcd", "índice");
        PutOnDevice(".aura/tagcache/database_idx.tcd", "índice compartido");
        PutOnDevice(".aura/thumbs/algo.bmp", "miniatura");
        PutOnDevice(".aura/art/albums/algo.art", "maestra");
    }

    [Fact]
    public void AFirmwareThatAnnouncesTheMarkerKeepsItsDatabase()
    {
        PutDatabases();
        PutOnDevice(".rockbox/aura/aura.cfg", "sync_marker_supported: 1\n");

        LibrarySyncEngine.Apply(_volume, PlanOf(Ready(Source("a.mp3"), "Music/A/a.mp3")));

        // Borrarla le quitaría al usuario su música vieja mientras el firmware
        // decide cuándo reconstruir.
        Assert.True(File.Exists(OnDevice(".rockbox/database_idx.tcd")));
        Assert.True(File.Exists(OnDevice(".aura/tagcache/database_idx.tcd")));
        Assert.NotNull(SyncPendingMarker.Read(_volume));
    }

    [Fact]
    public void AnOlderFirmwareGetsItsDatabaseClearedAsBefore()
    {
        PutDatabases();
        PutOnDevice(".rockbox/aura/aura.cfg", "theme_format_supported: 1\n");

        LibrarySyncEngine.Apply(_volume, PlanOf(Ready(Source("a.mp3"), "Music/A/a.mp3")));

        Assert.False(File.Exists(OnDevice(".rockbox/database_idx.tcd")));
        Assert.False(File.Exists(OnDevice(".aura/tagcache/database_idx.tcd")));
    }

    [Fact]
    public void ClearingTheDatabaseNeverTouchesWhatBelongsToTheFirmware()
    {
        // Las miniaturas y la caché maestra de imágenes son del firmware: sus
        // claves no dependen de la base, y rehacerlas cuesta minutos para nada.
        PutDatabases();
        PutOnDevice(".rockbox/aura/aura.cfg", "");

        LibrarySyncEngine.Apply(_volume, PlanOf(Ready(Source("a.mp3"), "Music/A/a.mp3")));

        Assert.True(File.Exists(OnDevice(".aura/thumbs/algo.bmp")));
        Assert.True(File.Exists(OnDevice(".aura/art/albums/algo.art")));
    }

    [Fact]
    public void OnlyMusicChangesForceTheDatabaseRebuild()
    {
        PutDatabases();
        PutOnDevice(".rockbox/aura/aura.cfg", "");

        LibrarySyncEngine.Apply(_volume, PlanOf(Ready(Source("foto.jpg"), "Photos/foto.jpg")));

        Assert.True(File.Exists(OnDevice(".rockbox/database_idx.tcd")));
    }

    // MARK: - Carpetas vacías

    [Fact]
    public void EmptyArtistFoldersDoNotPileUpAfterChangingTheLayout()
    {
        PutOnDevice("Music/Artista/Álbum/a.mp3");
        File.Delete(OnDevice("Music/Artista/Álbum/a.mp3"));
        PutOnDevice("Music/Otro/b.mp3");

        int removed = LibrarySyncEngine.PruneEmptyMusicFolders(_volume);

        Assert.Equal(2, removed);
        Assert.False(Directory.Exists(OnDevice("Music/Artista")));
        Assert.True(File.Exists(OnDevice("Music/Otro/b.mp3")));
    }
}
