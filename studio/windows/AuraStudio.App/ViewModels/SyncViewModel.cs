using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using AuraStudio.App.Services;
using AuraStudio.Core.Library;

namespace AuraStudio.App.ViewModels;

/// <summary>
/// Un archivo que sigue en el iPod y ya no está en la biblioteca.
///
/// <para>Nace <b>sin marcar</b> a propósito: la casilla es una decisión del
/// usuario, no un valor por omisión que se acepta sin leer.</para>
/// </summary>
public sealed partial class OrphanRow : ObservableObject
{
    public required string SourcePath { get; init; }

    public required string DestinationRelativePath { get; init; }

    [ObservableProperty] public partial bool IsSelected { get; set; }
}

public sealed partial class SyncViewModel : ViewModelBase
{
    private readonly ISyncService _syncService;
    private readonly IDeviceSessionService _session;
    private readonly LibraryViewModel _library;
    private CancellationTokenSource? _cancellation;

    /// <summary>
    /// El hilo de la interfaz, capturado al construirse. <c>null</c> si este
    /// modelo se construyera fuera de él: en ese caso se escribe directo, que
    /// es lo que hacía antes — degradar es mejor que no arrancar.
    /// </summary>
    private readonly Microsoft.UI.Dispatching.DispatcherQueue? _dispatcher =
        Microsoft.UI.Dispatching.DispatcherQueue.GetForCurrentThread();

    [ObservableProperty] public partial string StatusMessage { get; set; }
    [ObservableProperty][NotifyPropertyChangedFor(nameof(HasCurrentFile))] public partial string CurrentFile { get; set; }
    [ObservableProperty][NotifyPropertyChangedFor(nameof(CanSync))] public partial bool IsBusy { get; set; }
    [ObservableProperty] public partial bool HasPreview { get; set; }
    [ObservableProperty] public partial bool CanEject { get; set; }
    [ObservableProperty] public partial int CopiedCount { get; set; }
    [ObservableProperty] public partial int SweptCount { get; set; }
    [ObservableProperty] public partial int SkippedCount { get; set; }
    [ObservableProperty] public partial long BytesToTransfer { get; set; }
    [ObservableProperty] public partial double ProgressValue { get; set; }
    [ObservableProperty] public partial bool IsIndeterminate { get; set; }
    [ObservableProperty][NotifyPropertyChangedFor(nameof(HasFailures))] public partial string FailureMessage { get; set; }
    [ObservableProperty] public partial bool SyncMusic { get; set; } = true;
    [ObservableProperty] public partial bool SyncVideos { get; set; } = true;
    [ObservableProperty] public partial bool SyncImages { get; set; } = true;

    /// <summary>Lo que ya no está en la biblioteca. Se muestra siempre, se borra solo si se marca.</summary>
    public ObservableCollection<OrphanRow> Orphans { get; } = [];

    public SyncViewModel(ISyncService syncService, IDeviceSessionService session, LibraryViewModel library)
    {
        _syncService = syncService;
        _session = session;
        _library = library;
        StatusMessage = "Revisa los cambios antes de sincronizar.";
        CurrentFile = "";
        FailureMessage = "";
        _syncService.ProgressChanged += OnProgressChanged;
        _library.PropertyChanged += OnLibraryChanged;

        // ST-202: la selección ya no viaja por PropertyChanged del modelo
        // grande. Esta ficha es hoy el único consumidor real, y ahora es el
        // único que se entera.
        _library.Selection.Changed += OnSelectionChanged;
    }

    public string DeviceMessage => _session.Device is { } device
        ? device.SupportsAuraContract ? $"Destino: {device.DisplayName}" : "El iPod detectado no tiene Aura activo."
        : "Conecta un iPod para sincronizar.";

    public bool HasOrphans => Orphans.Count > 0;

    /// <summary>Un renglón vacío igual ocupa alto: lo que no dice nada se esconde.</summary>
    public bool HasCurrentFile => CurrentFile.Length > 0;

    public bool HasFailures => FailureMessage.Length > 0;

    public string OrphanHeader => Orphans.Count == 1
        ? "1 archivo del iPod ya no está en tu biblioteca"
        : $"{Orphans.Count} archivos del iPod ya no están en tu biblioteca";

    [RelayCommand]
    private async Task PreviewAsync()
    {
        if (!TryGetVolume(out string volume)) return;
        if (!TryResolveScope(out SyncScopeResolution scope)) return;

        IsBusy = true;
        IsIndeterminate = true;
        FailureMessage = "";
        _cancellation = new CancellationTokenSource();

        try
        {
            SyncPlanResult plan = await _syncService.BuildPlanAsync(volume, Options(scope), _cancellation.Token);

            CopiedCount = plan.ToCopy.Count();
            SweptCount = plan.ToSweep.Count;
            SkippedCount = plan.SkipCount;
            BytesToTransfer = 0;

            Orphans.Clear();
            foreach (SyncOrphan orphan in plan.Orphans)
            {
                Orphans.Add(new OrphanRow
                {
                    SourcePath = orphan.SourcePath,
                    DestinationRelativePath = orphan.DestinationRelativePath
                });
            }

            OnPropertyChanged(nameof(HasOrphans));
            OnPropertyChanged(nameof(OrphanHeader));

            HasPreview = true;
            StatusMessage = plan.HasChanges
                ? $"Se van a copiar {plan.ToCopy.Count()} archivo(s); {plan.SkipCount} ya están al día."
                : "El iPod ya está al día con tu biblioteca.";
        }
        catch (OperationCanceledException) { StatusMessage = "Revisión cancelada."; }
        finally { Done(); }
    }

    [RelayCommand]
    private async Task SyncAsync()
    {
        if (!TryGetVolume(out string volume)) return;
        if (!TryResolveScope(out SyncScopeResolution scope)) return;

        IsBusy = true;
        ProgressValue = 0;
        IsIndeterminate = true;
        FailureMessage = "";
        CanEject = false;
        _cancellation = new CancellationTokenSource();

        try
        {
            SyncResult result = await _syncService.SyncAsync(volume, Options(scope), _cancellation.Token);

            CopiedCount = result.FilesCopied;
            SweptCount = result.FilesSwept;
            BytesToTransfer = result.BytesToCopy;
            StatusMessage = Describe(result);
            FailureMessage = result.Failures.Count == 0 ? "" : string.Join("\n", result.Failures.Take(10));

            // Solo con el sync cerrado: expulsar antes de que se escriba el
            // marcador dejaría al firmware sin saber que tiene que reindexar.
            CanEject = result.Success;

            if (result.Success) await RefreshOrphansAsync(volume);
        }
        catch (OperationCanceledException) { StatusMessage = "Sincronización cancelada."; }
        finally { HasPreview = false; Done(); }
    }

    [RelayCommand]
    private void Cancel() => _cancellation?.Cancel();

    /// <summary>
    /// Expulsar antes de desconectar: el iPod acaba de recibir archivos y
    /// Windows todavía puede tener escrituras en cola.
    /// </summary>
    [RelayCommand]
    private void Eject()
    {
        if (_session.Device?.VolumePath is not { Length: > 0 } volume) return;

        StatusMessage = Platform.VolumeManager.Eject(volume)
            ? "Ya puedes desconectar el iPod."
            : "No se pudo expulsar el iPod. Ciérralo desde el Explorador antes de desconectarlo.";

        CanEject = false;
    }

    private async Task RefreshOrphansAsync(string volume)
    {
        try
        {
            SyncPlanResult plan = await _syncService.BuildPlanAsync(volume, Options(), CancellationToken.None);

            Orphans.Clear();
            foreach (SyncOrphan orphan in plan.Orphans)
            {
                Orphans.Add(new OrphanRow
                {
                    SourcePath = orphan.SourcePath,
                    DestinationRelativePath = orphan.DestinationRelativePath
                });
            }

            SkippedCount = plan.SkipCount;
            OnPropertyChanged(nameof(HasOrphans));
            OnPropertyChanged(nameof(OrphanHeader));
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            // Que no se pueda releer el plan no invalida el sync que acaba de
            // terminar bien.
        }
    }

    private SyncOptions Options(SyncScopeResolution scope = default) => new()
    {
        SyncMusic = SyncMusic,
        SyncVideos = SyncVideos,
        SyncImages = SyncImages,
        RestrictToSourcePaths = scope.RestrictToSourcePaths,
        OrphansToRemove = [.. Orphans.Where(orphan => orphan.IsSelected).Select(orphan => orphan.SourcePath)]
    };

    // MARK: - Alcance (R3-4)

    /// <summary>
    /// «Solo la selección» en vez de toda la biblioteca. Se apaga solo cuando
    /// la selección se vacía: dejar el alcance en una selección que ya no
    /// existe es la forma de sincronizar nada sin entender por qué.
    /// </summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(CanSync))]
    public partial bool ScopeIsSelection { get; set; }

    /// <summary>Cuántos elementos hay seleccionados en la vista activa.</summary>
    public int SelectionCount => _library?.SelectionForSyncCount ?? 0;

    public bool HasSelection => SelectionCount > 0;

    public string SelectionScopeLabel =>
        HasSelection ? $"Solo la selección ({SelectionCount})" : "Solo la selección";

    /// <summary>
    /// Lo que está listo para viajar, dicho antes de comparar contra el iPod.
    /// Es una <b>aproximación</b> —alguno puede estar ya sincronizado con ese
    /// aparato— y por eso se redacta como "listo(s) para sincronizar" y no
    /// como "se van a copiar", que es lo que dice «Revisar cambios».
    /// </summary>
    public string PendingLabel
    {
        get
        {
            int pending = _library?.PendingCount ?? 0;

            return pending switch
            {
                0 => "No hay nada listo para sincronizar.",
                1 => "1 archivo listo para sincronizar.",
                _ => $"{pending} archivos listos para sincronizar."
            };
        }
    }

    /// <summary>
    /// El botón nunca lleva a un camino que falla: sin iPod con Aura, o con el
    /// alcance en una selección vacía, no se puede sincronizar y se ve.
    /// </summary>
    public bool CanSync =>
        !IsBusy
        && _session.Device?.SupportsAuraContract == true
        && (!ScopeIsSelection || HasSelection);

    private SyncScope CurrentScope() => ScopeIsSelection
        ? new SyncScope.Selection(_library?.SelectionForSync ?? [])
        : SyncScope.Everything;

    /// <summary>
    /// Resuelve el alcance y, si no hay nada que sincronizar, <b>lo dice y se
    /// detiene</b>. Los tres mensajes salen de Core, no de acá: son los mismos
    /// que los de macOS.
    /// </summary>
    private bool TryResolveScope(out SyncScopeResolution resolution)
    {
        resolution = SyncScopeResolver.Resolve(
            _library?.Items ?? [], CurrentScope());

        if (resolution.CanSync) return true;

        StatusMessage = resolution.Refusal ?? SyncScopeResolver.NothingReady;
        return false;
    }

    /// <summary>
    /// Lo que cambia cuando cambia el contenido de la biblioteca.
    ///
    /// <para>La <b>selección</b> ya no llega por acá (ST-202): la avisa el
    /// <see cref="SelectionStore"/>, y solo lo escucha quien la consume.</para>
    /// </summary>
    private void OnLibraryChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e)
    {
        if (e.PropertyName != nameof(LibraryViewModel.Items)) return;

        SelectionOrLibraryChanged();
    }

    private void OnSelectionChanged(object? sender, EventArgs e) => SelectionOrLibraryChanged();

    private void SelectionOrLibraryChanged()
    {
        // Con la selección vacía, el alcance vuelve a "toda la biblioteca": un
        // alcance que apunta a nada no es un estado en el que dejar al usuario.
        if (ScopeIsSelection && !HasSelection) ScopeIsSelection = false;

        OnPropertyChanged(nameof(SelectionCount));
        OnPropertyChanged(nameof(HasSelection));
        OnPropertyChanged(nameof(SelectionScopeLabel));
        OnPropertyChanged(nameof(PendingLabel));
        OnPropertyChanged(nameof(CanSync));
    }

    private void Done()
    {
        _cancellation?.Dispose();
        _cancellation = null;
        IsBusy = false;
        IsIndeterminate = false;
        CurrentFile = "";
    }

    private bool TryGetVolume(out string volume)
    {
        volume = _session.Device?.VolumePath ?? "";

        if (_session.Device is null || string.IsNullOrWhiteSpace(volume))
        {
            StatusMessage = "Conecta y selecciona un iPod antes de continuar.";
            return false;
        }

        if (!_session.Device.SupportsAuraContract)
        {
            StatusMessage = "Este iPod no está ejecutando Aura. Instala Aura antes de sincronizar.";
            return false;
        }

        return true;
    }

    private static string Describe(SyncResult result)
    {
        if (!result.Success) return result.ErrorMessage ?? "La sincronización no se completó.";

        string copied = $"{result.FilesCopied} archivo(s) copiado(s)";
        string removed = result.FilesDeleted == 0 ? "" : $" y {result.FilesDeleted} quitado(s) del iPod";
        string failures = result.Failures.Count == 0
            ? ""
            : $" {result.Failures.Count} no se pudo(ieron) copiar.";

        // Cancelar no pierde nada: lo copiado ya está completo en el iPod y el
        // firmware ya sabe que tiene que reconstruir sus índices.
        return result.Cancelled
            ? $"Cancelaste la sincronización. {copied}{removed} antes de detenerla.{failures}"
            : $"Listo: {copied}{removed}.{failures}";
    }

    /// <summary>
    /// El avance llega desde <b>otro hilo</b>: el servicio de sincronización
    /// corre en un <c>Task.Run</c> y dispara este evento desde ahí. Escribir
    /// las propiedades acá mismo hace que los enlaces de XAML toquen el árbol
    /// visual desde fuera del hilo de la interfaz, y Windows contesta
    /// <c>RPC_E_WRONG_THREAD</c> — "la aplicación llamó a una interfaz que se
    /// aplanó para un diferente subproceso"—, que aborta la sincronización a
    /// media copia (ST-131).
    ///
    /// <para>Por eso hay que cruzar al hilo de la interfaz a mano. Un
    /// <c>IProgress&lt;T&gt;</c> lo haría solo —captura el contexto de
    /// sincronización al construirse, que es justamente por lo que el
    /// instalador nunca tuvo este problema—, pero un <c>event</c> no captura
    /// nada: corre donde lo disparen.</para>
    /// </summary>
    private void OnProgressChanged(object? sender, SyncProgressEventArgs e)
    {
        if (_dispatcher is { HasThreadAccess: false })
        {
            _dispatcher.TryEnqueue(() => Apply(e));
            return;
        }

        Apply(e);
    }

    private void Apply(SyncProgressEventArgs e)
    {
        CurrentFile = e.CurrentFile;

        if (e.Phase == SyncPhase.Copying && e.TotalFiles > 0)
        {
            IsIndeterminate = false;
            ProgressValue = (double)e.ProcessedFiles / e.TotalFiles * 100;
        }

        StatusMessage = e.Phase switch
        {
            SyncPhase.Scanning => "Analizando la biblioteca…",
            SyncPhase.Comparing => "Comparando cambios…",
            SyncPhase.Copying => $"Copiando {e.ProcessedFiles} de {e.TotalFiles}…",
            SyncPhase.WritingManifest => "Guardando letras, carátulas e índices…",
            SyncPhase.WritingSyncMarker => "Preparando la actualización del iPod…",
            _ => StatusMessage
        };
    }
}
