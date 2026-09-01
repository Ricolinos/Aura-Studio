using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using AuraStudio.Core;
using AuraStudio.Core.Installer;
using AuraStudio.App.Resources;
using AuraStudio.App.Services;

namespace AuraStudio.App.ViewModels;

/// <summary>
/// Vista "General": identidad del iPod conectado, firmware, almacenamiento y
/// resumen de lo que tiene adentro. Equivale a `DeviceGeneralView` de macOS.
///
/// Ya no consulta al watcher por su cuenta: lee de
/// <see cref="IDeviceSessionService"/>, que es la única fuente del estado del
/// dispositivo en la app. Singleton, como todo ViewModel suscrito a la sesión.
/// </summary>
public sealed partial class DeviceListViewModel : ViewModelBase
{
    private readonly IDeviceSessionService _session;
    private readonly IVolumeService _volumes;
    private readonly IAppPreferences _preferences;
    private readonly IFirmwareArtifactsProvider _artifacts;
    private readonly InstallerViewModel _installer;

    [ObservableProperty]
    public partial IPodDiskInfo? Device { get; set; }

    [ObservableProperty]
    public partial string StatusMessage { get; set; }

    /// <summary>Hay exactamente un iPod identificado y montado.</summary>
    [ObservableProperty]
    public partial bool HasDevice { get; set; }

    /// <summary>
    /// Dos o más discos calificaron. **No** se muestran como candidatos
    /// seleccionables: la app se detiene y explica qué hacer (regla de
    /// seguridad del repo).
    /// </summary>
    [ObservableProperty]
    public partial bool IsAmbiguous { get; set; }

    /// <summary>
    /// Qué firmware tiene el iPod, <b>en una frase</b> (R3-3).
    ///
    /// <para>Reemplaza al par de filas "Firmware que atiende el USB" /
    /// "Familia declarada", que además imprimían el nombre del enum
    /// (<c>RockboxFamily</c>) en pantalla. Los tres hechos de ST-016 siguen
    /// separados por dentro; lo que cambia es que afuera se dicen con
    /// palabras.</para>
    /// </summary>
    public string FirmwareSummary => Device?.FirmwareSummary ?? AppStrings.NotAvailable;

    /// <summary>Los tramos de la barra de capacidad, con "Libre" incluido.</summary>
    public IReadOnlyList<StorageSegment> StorageSegments =>
        Device is { } device ? StorageBreakdown.Segments(device) : [];

    /// <summary>La leyenda: lo que tiene contenido, sin "Libre".</summary>
    public IReadOnlyList<StorageSegment> StorageLegend =>
        Device is { } device ? StorageBreakdown.Legend(device) : [];

    /// <summary>"12.3 GB usados de 125.0 GB — 112.7 GB libres".</summary>
    public string StorageUsageLine =>
        Device is { } device ? StorageBreakdown.UsageLine(device) : "";

    /// <summary>
    /// La línea de estado del firmware cuando NO hay actualización — el caso
    /// normal, que antes no decía nada. Que el silencio signifique "está al
    /// día" obliga a adivinar.
    /// </summary>
    public string FirmwareUpToDateMessage
    {
        get
        {
            if (Device is not { } device || !device.SupportsAuraContract) return "";

            FirmwareFamily family = device.DeclaredFamily ?? FirmwareFamily.Aura;

            return family.IsInstallable
                ? $"{family.DisplayName} está al día con esta versión de Aura Studio."
                : $"{family.DisplayName} está al día.";
        }
    }

    /// <summary>Solo se habla de actualizaciones donde hay un firmware que actualizar.</summary>
    public bool ShowsFirmwareStatus => Device?.SupportsAuraContract == true;

    /// <summary>
    /// Buscar actualizaciones <b>a mano</b>. Antes solo corría solo al
    /// conectar: sin esto, quien deja el iPod conectado no tiene forma de
    /// volver a preguntar.
    /// </summary>
    [RelayCommand]
    private void CheckForUpdates()
    {
        CheckFirmwareUpdate();

        StatusMessage = HasFirmwareUpdate ? FirmwareUpdateMessage : FirmwareUpToDateMessage;

        OnPropertyChanged(nameof(FirmwareUpToDateMessage));
    }

    public string SummaryMessage => Device?.HasLibrarySummary == true
        ? AppStrings.LastSyncSummary
        : AppStrings.NeverSynced;

    /// <summary>Barra de almacenamiento: 0 cuando el volumen todavía no se pudo leer.</summary>
    public double UsedPercent => Device is { SizeBytes: > 0 } device
        ? (double)device.UsedBytes / device.SizeBytes * 100
        : 0;

    // MARK: - Actualización del firmware

    /// <summary>
    /// Si el firmware del iPod es más viejo que el que trae esta copia de
    /// Studio. <b>Nunca se concluye a ciegas</b>: cuando no se puede saber, no
    /// se ofrece nada.
    /// </summary>
    [ObservableProperty]
    public partial bool HasFirmwareUpdate { get; set; }

    [ObservableProperty]
    public partial string FirmwareUpdateMessage { get; set; }

    /// <summary>
    /// Se compara siempre <b>contra la familia instalada</b> (ST-046): medir el
    /// binario de Metro contra el de Aura daría "hay actualización" para
    /// siempre, o sea ofrecerle al usuario sobrescribir Metro con Aura.
    /// </summary>
    private void CheckFirmwareUpdate()
    {
        HasFirmwareUpdate = false;
        FirmwareUpdateMessage = "";

        if (Device is not { VolumePath.Length: > 0 } device || !device.SupportsAuraContract) return;

        FirmwareFamily family = device.DeclaredFamily ?? FirmwareFamily.Aura;
        FirmwareArtifacts artifacts = _artifacts.For(family);

        UpdateVerdict verdict = AuraUpdateChecker.Check(device.VolumePath, artifacts, artifacts.ReleaseTag);

        HasFirmwareUpdate = verdict.UpdateAvailable;

        FirmwareUpdateMessage = verdict switch
        {
            { UpdateAvailable: true, Reason: UpdateVerdictReason.InstalledBinaryMissing } =>
                $"El árbol de {family.DisplayName} en el iPod está incompleto. Reinstálalo desde el Instalador.",
            { UpdateAvailable: true, LatestTag: { Length: > 0 } tag } =>
                $"Hay una versión más nueva de {family.DisplayName} ({tag}).",
            { UpdateAvailable: true } =>
                $"Hay una versión más nueva de {family.DisplayName}.",
            _ => ""
        };
    }

    /// <summary>
    /// Actualiza el firmware sin mandar al usuario al asistente (D-222): el
    /// botón está donde se le avisó que hay versión nueva, y lo único que ve es
    /// el avance.
    /// </summary>
    [RelayCommand]
    private async Task UpdateFirmwareAsync()
    {
        if (Device is not { } device || !HasFirmwareUpdate) return;

        IsUpdatingFirmware = true;

        try
        {
            await _installer.UpdateInPlaceAsync(device.DeclaredFamily ?? FirmwareFamily.Aura);

            StatusMessage = _installer.Step == InstallerStep.Done
                ? "El firmware quedó actualizado. Expulsa el iPod y enciéndelo."
                : _installer.DetailMessage;

            CheckFirmwareUpdate();
        }
        finally { IsUpdatingFirmware = false; }
    }

    [ObservableProperty]
    public partial bool IsUpdatingFirmware { get; set; }

    /// <summary>Lo que va pasando durante la actualización, para no dejar la pantalla muda.</summary>
    public string UpdateProgressMessage => _installer.DetailMessage;

    // MARK: - Nombre del iPod (CONTRATO-dispositivo.md v2)

    /// <summary>
    /// El nombre editable del iPod. Sale de <c>device.cfg</c>, que es un
    /// archivo propio de Studio: en <c>aura.cfg</c> se perdería en el primer
    /// ajuste que guarde el firmware.
    /// </summary>
    [ObservableProperty]
    public partial string DeviceName { get; set; }

    /// <summary>
    /// Solo la instalación que nombró el iPod la primera vez puede cambiarle el
    /// nombre. Las demás lo <b>muestran</b>, con la explicación: esconder el
    /// campo parecería un error de la app.
    /// </summary>
    [ObservableProperty]
    public partial bool CanEditDeviceName { get; set; }

    public string DeviceNameExplanation =>
        CanEditDeviceName ? "" : DeviceNameStore.NotOwnerExplanation;

    public DeviceListViewModel(IDeviceSessionService session, IVolumeService volumes,
        IAppPreferences preferences, IFirmwareArtifactsProvider artifacts, InstallerViewModel installer)
    {
        _session = session;
        _volumes = volumes;
        _preferences = preferences;
        _artifacts = artifacts;
        _installer = installer;

        // El avance de la copia lo publica el instalador; esta pantalla solo lo
        // repite para no dejar al usuario mirando un botón mudo.
        _installer.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName == nameof(InstallerViewModel.DetailMessage))
                OnPropertyChanged(nameof(UpdateProgressMessage));
        };
        DeviceName = "";
        FirmwareUpdateMessage = "";
        CanEditDeviceName = true;
        _session.Changed += OnSessionChanged;
        StatusMessage = session.StatusMessage;
        Apply();
    }

    /// <summary>
    /// Lee el nombre del iPod y, si nunca tuvo, le pone uno. Es la única
    /// escritura automática al conectar, y está en el contrato: un iPod sin
    /// nombre no tiene cómo mostrarse en "Acerca de" del firmware.
    /// </summary>
    private void LoadDeviceName()
    {
        if (Device is not { VolumePath.Length: > 0 } device || !device.SupportsAuraContract)
        {
            DeviceName = "";
            CanEditDeviceName = true;
            OnPropertyChanged(nameof(DeviceNameExplanation));
            return;
        }

        DeviceConfig config = DeviceNameStore.EnsureNamed(
            device.VolumePath, DefaultDeviceName, _preferences.InstallationId);

        DeviceName = config.Name ?? "";
        CanEditDeviceName = DeviceNameStore.CanEdit(config, _preferences.InstallationId);
        OnPropertyChanged(nameof(DeviceNameExplanation));
    }

    private static string DefaultDeviceName
    {
        get
        {
            string user = Environment.UserName.Trim();
            return user.Length == 0 ? "Mi iPod" : $"iPod de {user}";
        }
    }

    [RelayCommand]
    private void SaveDeviceName()
    {
        if (Device is not { VolumePath.Length: > 0 } device) return;

        DeviceConfig saved = DeviceNameStore.Save(device.VolumePath, DeviceName, _preferences.InstallationId);

        // Se vuelve a mostrar lo que de verdad quedó: el nombre pudo recortarse
        // (32 caracteres, 48 bytes) o perder emoji, y el usuario tiene que ver
        // el resultado, no lo que escribió.
        DeviceName = saved.Name ?? "";
        CanEditDeviceName = DeviceNameStore.CanEdit(saved, _preferences.InstallationId);
        StatusMessage = $"El iPod se llama \"{DeviceName}\".";
        OnPropertyChanged(nameof(DeviceNameExplanation));
    }

    private void OnSessionChanged(object? sender, DeviceSessionChangedEventArgs e) => Apply();

    private void Apply()
    {
        Device = _session.Device;
        HasDevice = _session.State == DeviceSessionState.Connected && Device is not null;
        IsAmbiguous = _session.State == DeviceSessionState.Ambiguous;
        StatusMessage = _session.StatusMessage;

        OnPropertyChanged(nameof(FirmwareSummary));
        OnPropertyChanged(nameof(SummaryMessage));
        OnPropertyChanged(nameof(UsedPercent));
        OnPropertyChanged(nameof(StorageSegments));
        OnPropertyChanged(nameof(StorageLegend));
        OnPropertyChanged(nameof(StorageUsageLine));
        OnPropertyChanged(nameof(FirmwareUpToDateMessage));
        OnPropertyChanged(nameof(ShowsFirmwareStatus));

        LoadDeviceName();
        CheckFirmwareUpdate();
    }

    /// <summary>Refresco inofensivo: vuelve a leer el estado del iPod, nunca escribe.</summary>
    [RelayCommand]
    private void Refresh() => _session.Refresh();

    [RelayCommand(CanExecute = nameof(HasMountedVolume))]
    private void OpenInExplorer() => _volumes.OpenInExplorer(Device!.VolumePath);

    [RelayCommand(CanExecute = nameof(HasMountedVolume))]
    private async Task EjectAsync()
    {
        bool requested = _volumes.Eject(Device!.VolumePath);
        StatusMessage = requested ? AppStrings.EjectRequested : AppStrings.EjectFailed;

        if (!requested) return;

        // Windows tarda en soltar la unidad: se le da margen antes de volver a
        // preguntar, para no reportar "sigue conectado" en el mismo instante.
        await Task.Delay(TimeSpan.FromSeconds(1.5));
        _session.Refresh();
    }

    private bool HasMountedVolume() => Device is { VolumePath.Length: > 0 };

    partial void OnDeviceChanged(IPodDiskInfo? value)
    {
        OpenInExplorerCommand.NotifyCanExecuteChanged();
        EjectCommand.NotifyCanExecuteChanged();
    }
}
