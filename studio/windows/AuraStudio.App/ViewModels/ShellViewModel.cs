using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using AuraStudio.App.Resources;
using AuraStudio.App.Services;

namespace AuraStudio.App.ViewModels;

/// <summary>
/// El armazón: barra de navegación y encabezado de dispositivo. Equivale a lo
/// que `ContentView`/`SidebarView` resuelven en macOS.
///
/// Singleton (como todo ViewModel que observa la sesión): la ventana es una
/// sola y su suscripción a <see cref="IDeviceSessionService"/> tiene que vivir
/// tanto como ella.
/// </summary>
public sealed partial class ShellViewModel : ViewModelBase
{
    private readonly IDeviceSessionService _session;

    /// <summary>Nombre del iPod conectado, o "Sin dispositivo".</summary>
    [ObservableProperty]
    public partial string DeviceTitle { get; set; }

    /// <summary>
    /// La biblioteca (Música/Video/Fotos) se bloquea con un iPod conectado que
    /// no habla el contrato de Aura; **sin dispositivo queda abierta**, porque
    /// armar la biblioteca offline es un caso de uso real (igual que macOS).
    /// General y Extras nunca se bloquean: ahí se explica qué firmware hay y
    /// qué hacer con él (ST-047).
    /// </summary>
    [ObservableProperty]
    public partial bool LibraryEnabled { get; set; }

    /// <summary>Por qué está bloqueada — un elemento deshabilitado siempre explica qué falta (ST-053).</summary>
    [ObservableProperty]
    public partial bool ShowLibraryLockedNote { get; set; }

    public string LibraryLockedReason => AppStrings.LibraryLockedReason;

    public ShellViewModel(IDeviceSessionService session, AppUpdateService updates)
    {
        _session = session;
        _session.Changed += OnSessionChanged;
        Updates = updates;

        DeviceTitle = AppStrings.NoDevice;
        LibraryEnabled = true;
        Apply();
    }

    /// <summary>
    /// El aviso de que hay una versión nueva de Aura Studio (ST-211). Vive en el
    /// armazón porque la franja es de la ventana entera, no de una pantalla, y
    /// el mismo estado se ve además en Ajustes › Acerca de.
    /// </summary>
    public AppUpdateService Updates { get; }

    private void OnSessionChanged(object? sender, DeviceSessionChangedEventArgs e) => Apply();

    private void Apply()
    {
        DeviceTitle = _session.Device?.VolumeName is { Length: > 0 } name
            ? name
            : _session.Device is null ? AppStrings.NoDevice : _session.Device.DisplayName;

        LibraryEnabled = !_session.LibraryLocked;
        ShowLibraryLockedNote = _session.LibraryLocked;
    }

    /// <summary>Refresco inofensivo: vuelve a leer el estado del iPod, no escribe nada.</summary>
    [RelayCommand]
    private void Refresh() => _session.Refresh();
}
