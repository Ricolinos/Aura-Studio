using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// Qué se copia, qué se saltea y qué se propone borrar. Lo que más duele si
/// falla no es copiar de más —eso solo tarda— sino <b>barrer de menos</b>: una
/// canción que se movió y quedó también en su lugar viejo aparece dos veces en
/// el iPod.
/// </summary>
public class SyncPlannerTests
{
    private static readonly DateTimeOffset Ayer = new(2026, 8, 31, 12, 0, 0, TimeSpan.Zero);
    private static readonly DateTimeOffset Hoy = new(2026, 9, 1, 12, 0, 0, TimeSpan.Zero);

    private static SyncSourceFile File(string source, string destination, long size = 100, DateTimeOffset? at = null)
        => new(source, size, at ?? Ayer, destination);

    private static DeviceSyncManifest Manifest(params (string Source, string Destination, long Size, DateTimeOffset At)[] records)
    {
        var manifest = new DeviceSyncManifest();
        foreach (var (source, destination, size, at) in records)
        {
            manifest.Records[source] = new DeviceSyncRecord(
                source, size, DeviceSyncRecord.ToTimeInterval(at), destination);
        }
        return manifest;
    }

    private static DeviceSyncManifest Manifest(string source, string destination, long size = 100, DateTimeOffset? at = null)
        => Manifest((source, destination, size, at ?? Ayer));

    // MARK: - Lo básico

    [Fact]
    public void SomethingNeverCopiedIsCopied()
    {
        SyncPlanResult plan = SyncPlanner.Plan([File(@"C:\m\a.mp3", "Music/A/B/a.mp3")], new DeviceSyncManifest());

        SyncPlanItem item = Assert.Single(plan.Items);
        Assert.Equal(SyncAction.Copy, item.Action);
        Assert.False(item.Moved);
        Assert.True(plan.HasChanges);
    }

    [Fact]
    public void SomethingUnchangedIsSkipped()
    {
        SyncPlanResult plan = SyncPlanner.Plan(
            [File(@"C:\m\a.mp3", "Music/A/B/a.mp3")],
            Manifest(@"C:\m\a.mp3", "Music/A/B/a.mp3"));

        Assert.Equal(SyncAction.Skip, Assert.Single(plan.Items).Action);
        Assert.False(plan.HasChanges);
        Assert.Equal(1, plan.SkipCount);
    }

    [Fact]
    public void AFileThatChangedIsCopiedAgain()
    {
        // Cambió el tamaño o la fecha: se volvió a preparar.
        Assert.Equal(SyncAction.Copy, SyncPlanner.Plan(
            [File(@"C:\m\a.mp3", "Music/A/B/a.mp3", size: 200)],
            Manifest(@"C:\m\a.mp3", "Music/A/B/a.mp3", size: 100)).Items[0].Action);

        Assert.Equal(SyncAction.Copy, SyncPlanner.Plan(
            [File(@"C:\m\a.mp3", "Music/A/B/a.mp3", at: Hoy)],
            Manifest(@"C:\m\a.mp3", "Music/A/B/a.mp3", at: Ayer)).Items[0].Action);
    }

    [Fact]
    public void ASecondOfDifferenceIsNotAChange()
    {
        // ST-090: la carpeta compartida de Parallels redondea la fecha, así que
        // la que ve Windows y la que vio la Mac difieren por menos de un
        // segundo. Sin tolerancia, alternar entre las dos apps recopiaría la
        // biblioteca entera cada vez.
        SyncPlanResult plan = SyncPlanner.Plan(
            [File(@"C:\m\a.mp3", "Music/A/B/a.mp3", at: Ayer.AddMilliseconds(900))],
            Manifest(@"C:\m\a.mp3", "Music/A/B/a.mp3", at: Ayer));

        Assert.Equal(SyncAction.Skip, Assert.Single(plan.Items).Action);
    }

    [Fact]
    public void MoreThanTwoSecondsIsAChange()
    {
        SyncPlanResult plan = SyncPlanner.Plan(
            [File(@"C:\m\a.mp3", "Music/A/B/a.mp3", at: Ayer.AddSeconds(3))],
            Manifest(@"C:\m\a.mp3", "Music/A/B/a.mp3", at: Ayer));

        Assert.Equal(SyncAction.Copy, Assert.Single(plan.Items).Action);
    }

    // MARK: - Lo que se movió

    [Fact]
    public void AFileThatMovedIsCopiedAndItsOldPlaceIsSwept()
    {
        // Sin esto, la canción queda DOS veces en el iPod.
        SyncPlanResult plan = SyncPlanner.Plan(
            [File(@"C:\m\a.mp3", "Music/Soda Stereo/Signos/Amor.mp3")],
            Manifest(@"C:\m\a.mp3", "Music/Signos/Amor.mp3"));

        SyncPlanItem item = Assert.Single(plan.Items);
        Assert.Equal(SyncAction.Copy, item.Action);
        Assert.True(item.Moved);
        Assert.Equal("Music/Signos/Amor.mp3", item.StaleDestinationRelativePath);
        Assert.Contains("Music/Signos/Amor.mp3", plan.ToSweep);
    }

    [Fact]
    public void ChangingTheLayoutMovesEverythingEvenIfNoFileChanged()
    {
        // El archivo es el mismo; lo que cambió es la preferencia. Si el destino
        // no entrara en la comparación, no se copiaría nada y el iPod quedaría
        // con el layout viejo.
        SyncPlanResult plan = SyncPlanner.Plan(
            [File(@"C:\m\a.mp3", "Music/Artista/a.mp3"), File(@"C:\m\b.mp3", "Music/Artista/b.mp3")],
            Manifest(
                (@"C:\m\a.mp3", "Music/Artista/Álbum/a.mp3", 100, Ayer),
                (@"C:\m\b.mp3", "Music/Artista/Álbum/b.mp3", 100, Ayer)));

        Assert.All(plan.Items, item => Assert.Equal(SyncAction.Copy, item.Action));
        Assert.Equal(2, plan.ToSweep.Count);
    }

    // MARK: - Lo que salió de la biblioteca

    [Fact]
    public void SomethingRemovedFromTheLibraryIsProposedNotDeleted()
    {
        // El plan lo reporta; borrarlo exige que el usuario lo confirme.
        SyncPlanResult plan = SyncPlanner.Plan([], Manifest(@"C:\m\a.mp3", "Music/A/B/a.mp3"));

        Assert.Empty(plan.Items);
        Assert.Equal(new SyncOrphan(@"C:\m\a.mp3", "Music/A/B/a.mp3"), Assert.Single(plan.Orphans));
        Assert.False(plan.HasChanges);
        Assert.True(plan.HasAnythingToDo);
        Assert.Empty(plan.ToSweep);
    }

    [Fact]
    public void AnEmptyLibraryAndAnEmptyDeviceIsNoWork()
    {
        SyncPlanResult plan = SyncPlanner.Plan([], new DeviceSyncManifest());

        Assert.False(plan.HasAnythingToDo);
        Assert.Empty(plan.ToSweep);
    }

    // MARK: - Secciones tocadas (contrato §4)

    [Fact]
    public void OnlyTheSectionsThatReallyChangedAreMarked()
    {
        // El firmware reconstruye solo lo marcado: marcar de más le cuesta al
        // usuario un arranque largo sin motivo.
        SyncPendingSections sections = SyncPlanner.SectionsTouched(
            SyncPlanner.Plan([File(@"C:\m\a.mp3", "Music/A/a.mp3")], new DeviceSyncManifest()));

        Assert.True(sections.Music);
        Assert.False(sections.Video);
        Assert.False(sections.Images);
        Assert.False(sections.IsEmpty);
    }

    [Fact]
    public void AnUnconfirmedOrphanMarksNothing()
    {
        // Todavía no se borró nada: no hay nada que reconstruir.
        SyncPendingSections sections = SyncPlanner.SectionsTouched(
            SyncPlanner.Plan([], Manifest(@"C:\f\a.jpg", "Photos/a.jpg")));

        Assert.True(sections.IsEmpty);
    }

    [Fact]
    public void ASyncThatChangedNothingMarksNoSection()
    {
        // Un marcador sin ninguna sección hace que el firmware lo borre sin
        // actuar: mejor no escribirlo.
        SyncPendingSections sections = SyncPlanner.SectionsTouched(
            SyncPlanner.Plan(
                [File(@"C:\m\a.mp3", "Music/A/a.mp3")],
                Manifest(@"C:\m\a.mp3", "Music/A/a.mp3")));

        Assert.True(sections.IsEmpty);
    }

    [Fact]
    public void EachSectionIsRecognizedByItsFolder()
    {
        SyncPendingSections sections = SyncPlanner.SectionsTouched(
            SyncPlanner.Plan(
            [
                File(@"C:\m\a.mp3", "Music/A/a.mp3"),
                File(@"C:\v\b.mpg", "Videos/b.mpg"),
                File(@"C:\f\c.jpg", "Photos/c.jpg")
            ], new DeviceSyncManifest()));

        Assert.True(sections.Music);
        Assert.True(sections.Video);
        Assert.True(sections.Images);
    }

    [Fact]
    public void APlaylistIsNotASectionOfTheMarker()
    {
        // El firmware lee /Playlists/ del directorio al entrar; no lo indexa.
        SyncPendingSections sections = SyncPlanner.SectionsTouched(
            SyncPlanner.Plan([File(@"C:\l\a.m3u8", "Playlists/a.m3u8")], new DeviceSyncManifest()));

        Assert.True(sections.IsEmpty);
    }

    // MARK: - Robustez

    [Fact]
    public void TheOrderOfTheLibraryIsThePlanOrder()
    {
        SyncPlanResult plan = SyncPlanner.Plan(
            [File(@"C:\m\z.mp3", "Music/z.mp3"), File(@"C:\m\a.mp3", "Music/a.mp3")], new DeviceSyncManifest());

        Assert.Equal([@"C:\m\z.mp3", @"C:\m\a.mp3"], plan.Items.Select(item => item.SourcePath));
    }

    [Fact]
    public void PathsAreComparedWithoutCaringAboutCaseBecauseFat32DoesNot()
    {
        SyncPlanResult plan = SyncPlanner.Plan(
            [File(@"C:\m\a.mp3", "Music/A/Amor.mp3")],
            Manifest(@"c:\m\A.MP3", "music/a/amor.mp3"));

        Assert.Equal(SyncAction.Skip, Assert.Single(plan.Items).Action);
        Assert.Empty(plan.Orphans);
    }
}
