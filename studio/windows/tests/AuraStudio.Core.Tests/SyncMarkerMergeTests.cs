using AuraStudio.Core;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// ST-142: el marcador se escribe en dos momentos de un mismo sync (al copiar,
/// y al final si cambiaron las carátulas), así que el segundo no puede borrar
/// lo que anunció el primero — el firmware reconstruiría de menos.
/// </summary>
public class SyncMarkerMergeTests : IDisposable
{
    private readonly string _volume =
        Path.Combine(Path.GetTempPath(), "aura-marker-" + Guid.NewGuid().ToString("N"));

    public SyncMarkerMergeTests() => Directory.CreateDirectory(_volume);

    public void Dispose()
    {
        try { Directory.Delete(_volume, recursive: true); } catch (IOException) { }
    }

    private SyncPendingMarker.Changes? Written() => SyncPendingMarker.Read(_volume)?.Changeset;

    [Fact]
    public void SectionsAddUpInsteadOfReplacingEachOther()
    {
        new SyncPendingMarker(new SyncPendingMarker.Changes(Music: false, Video: true, Images: false)).Write(_volume);

        SyncPendingMarker.Merge(_volume, new SyncPendingMarker.Changes(Music: true, Video: false, Images: false));

        SyncPendingMarker.Changes? changes = Written();
        Assert.NotNull(changes);
        Assert.True(changes!.Music);
        Assert.True(changes.Video);    // lo que ya estaba anunciado no se pierde
        Assert.False(changes.Images);
    }

    [Fact]
    public void WithoutAMarkerItWritesTheOneItWasGiven()
    {
        SyncPendingMarker.Merge(_volume, new SyncPendingMarker.Changes(Music: true, Video: false, Images: false));

        Assert.True(Written()?.Music);
    }

    [Fact]
    public void NothingToAnnounceWritesNothing()
    {
        SyncPendingMarker.Merge(_volume, new SyncPendingMarker.Changes(false, false, false));

        Assert.False(File.Exists(Path.Combine(_volume, SyncPendingMarker.RelativePath)));
    }

    [Fact]
    public void AnUnreadableMarkerIsNotAReasonToLoseTheNewOne()
    {
        Directory.CreateDirectory(Path.Combine(_volume, ".aura"));
        File.WriteAllText(Path.Combine(_volume, SyncPendingMarker.RelativePath), "esto no es JSON");

        SyncPendingMarker.Merge(_volume, new SyncPendingMarker.Changes(Music: true, Video: false, Images: false));

        Assert.True(Written()?.Music);
    }
}
