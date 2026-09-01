using AuraStudio.Core.Library;

namespace AuraStudio.App.Services;

/// <summary>
/// Sincronización con el iPod — equivalente a <c>LibrarySync</c> de macOS.
/// </summary>
public interface ISyncService
{
    event EventHandler<SyncProgressEventArgs>? ProgressChanged;

    Task<SyncResult> SyncAsync(string volumeRoot, SyncOptions options, CancellationToken ct = default);

    Task<SyncResult> PreviewSyncAsync(string volumeRoot, SyncOptions options, CancellationToken ct = default);

    Task<SyncPlanResult> BuildPlanAsync(string volumeRoot, SyncOptions options, CancellationToken ct = default);
}

public sealed class SyncProgressEventArgs : EventArgs
{
    public int TotalFiles { get; init; }
    public int ProcessedFiles { get; init; }
    public long TotalBytes { get; init; }
    public long ProcessedBytes { get; init; }
    public string CurrentFile { get; init; } = "";
    public SyncPhase Phase { get; init; }
}

public enum SyncPhase
{
    Scanning,
    Comparing,
    Copying,
    WritingManifest,
    WritingSyncMarker,
    Complete
}

public sealed record SyncOptions
{
    public bool SyncMusic { get; init; } = true;
    public bool SyncVideos { get; init; } = true;
    public bool SyncImages { get; init; } = true;
    public bool SyncPlaylists { get; init; } = true;
    public bool SyncLyrics { get; init; } = true;
    public bool SyncArtistImages { get; init; } = true;
    public bool SyncVideoPosters { get; init; } = true;

    /// <summary>Solo calcular el plan, sin escribir nada en el iPod.</summary>
    public bool DryRun { get; init; }

    /// <summary>
    /// Los huérfanos que el usuario confirmó quitar del iPod, por ruta de
    /// origen. <b>Vacío = no se borra ninguno</b>: nada sale del iPod sin que
    /// alguien lo haya pedido.
    /// </summary>
    public IReadOnlyCollection<string> OrphansToRemove { get; init; } = [];

    /// <summary>
    /// «Solo la selección» (R3-4): las rutas de <b>origen</b> a las que se acota
    /// la copia. <c>null</c> o vacío = toda la biblioteca.
    ///
    /// <para>Lo calcula <see cref="AuraStudio.Core.Library.SyncScopeResolver"/>,
    /// que además decide cuándo <b>no</b> se puede sincronizar y con qué
    /// palabras se dice. Acá solo se aplica.</para>
    /// </summary>
    public IReadOnlyCollection<string>? RestrictToSourcePaths { get; init; }
}

public sealed class SyncResult
{
    public bool Success { get; init; }

    /// <summary>Se detuvo a mitad. Lo copiado quedó completo y anunciado al firmware.</summary>
    public bool Cancelled { get; init; }

    public int FilesCopied { get; init; }

    /// <summary>Lugares viejos que se limpiaron porque el archivo cambió de ruta.</summary>
    public int FilesSwept { get; init; }

    /// <summary>Huérfanos que el usuario confirmó y que se quitaron del iPod.</summary>
    public int FilesDeleted { get; init; }

    /// <summary>Huérfanos que siguen en el iPod esperando que el usuario decida.</summary>
    public int OrphansProposed { get; init; }

    public long BytesToCopy { get; init; }

    public TimeSpan Duration { get; init; }

    public string? ErrorMessage { get; init; }

    /// <summary>Archivos que no se pudieron escribir. El resto se copió igual.</summary>
    public IReadOnlyList<string> Failures { get; init; } = [];
}
