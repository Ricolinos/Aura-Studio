using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using AuraStudio.App.Services;
using AuraStudio.Core;

namespace AuraStudio.App.ViewModels;

/// <param name="Reason">Por qué no carga, cuando no carga. Se muestra siempre que exista.</param>
public sealed partial class ThemeRow : ObservableObject
{
    public required string Id { get; init; }
    public required string Name { get; init; }
    public bool Loadable { get; init; } = true;
    public string? Reason { get; init; }

    /// <summary>El tema integrado del firmware: ni se elimina ni se exporta.</summary>
    public bool IsBuiltIn => Id == ThemeActivation.DefaultThemeId;

    [ObservableProperty] public partial bool IsActive { get; set; }

    public bool CanRemove => !IsBuiltIn;

    public bool HasReason => Reason is { Length: > 0 };

    /// <summary>
    /// ST-003: un tema de uso personal <b>no se comparte</b>. La opción se
    /// deshabilita con la explicación al lado, nunca se esconde: quien armó el
    /// tema tiene que entender por qué no puede compartirlo.
    /// </summary>
    public bool CanShare { get; init; }

    public string ShareBlockedReason => CanShare
        ? ""
        : "Este tema usa material de licencia restringida: es para tu uso personal y no se puede compartir.";

    public string StateText => IsActive ? "Activo" : Loadable ? "" : "No carga";
}

public sealed partial class ThemesViewModel : ViewModelBase
{
    private readonly IThemeService _themes;
    private readonly IDeviceSessionService _session;

    [ObservableProperty] public partial bool IsBusy { get; set; }
    [ObservableProperty] public partial string StatusMessage { get; set; }
    [ObservableProperty] public partial string ErrorMessage { get; set; }

    /// <summary>Datos de la hoja de construir.</summary>
    [ObservableProperty] public partial string NewThemeName { get; set; }
    [ObservableProperty] public partial string NewThemeAuthor { get; set; }
    [ObservableProperty] public partial string NewThemeSourceFolder { get; set; }
    [ObservableProperty] public partial bool NewThemeIsRestricted { get; set; }

    public ObservableCollection<ThemeRow> Themes { get; } = [];

    public ThemesViewModel(IThemeService themes, IDeviceSessionService session)
    {
        _themes = themes;
        _session = session;
        StatusMessage = "";
        ErrorMessage = "";
        NewThemeName = "";
        NewThemeAuthor = "";
        NewThemeSourceFolder = "";
    }

    public bool HasDevice => _session.Device is { SupportsAuraContract: true };

    public string DeviceMessage => _session.Device is { } device
        ? device.SupportsAuraContract
            ? $"Temas de {device.DisplayName}"
            : "El iPod detectado no tiene Aura activo: los temas son de Aura."
        : "Conecta tu iPod con Aura para ver y cambiar sus temas.";

    /// <summary>El id que va a tener el tema que se está construyendo.</summary>
    public string SuggestedId => ThemeActivation.SuggestId(NewThemeName.Trim());

    public bool CanBuild =>
        HasDevice && !IsBusy && NewThemeSourceFolder.Length > 0 && AuraThemeID.IsValid(SuggestedId);

    partial void OnNewThemeNameChanged(string value)
    {
        OnPropertyChanged(nameof(SuggestedId));
        OnPropertyChanged(nameof(CanBuild));
        OnPropertyChanged(nameof(BuildHint));
    }

    partial void OnNewThemeSourceFolderChanged(string value)
    {
        OnPropertyChanged(nameof(CanBuild));
        OnPropertyChanged(nameof(BuildHint));
    }

    /// <summary>Qué falta para poder construir. Un botón gris sin explicación no sirve de nada.</summary>
    public string BuildHint
    {
        get
        {
            if (NewThemeSourceFolder.Length == 0) return "Elige la carpeta con los assets ya generados.";
            if (NewThemeName.Trim().Length == 0) return "Ponle un nombre al tema.";

            return AuraThemeID.IsValid(SuggestedId)
                ? $"Se va a instalar con el id \"{SuggestedId}\"."
                : $"\"{NewThemeName.Trim()}\" no produce un id válido: usa letras, números y espacios.";
        }
    }

    [RelayCommand]
    public async Task RefreshAsync()
    {
        Themes.Clear();
        OnPropertyChanged(nameof(HasDevice));
        OnPropertyChanged(nameof(DeviceMessage));

        if (!TryGetVolume(out string volume)) return;

        IsBusy = true;
        ErrorMessage = "";

        try
        {
            string active = _themes.ActiveThemeId(volume);
            IReadOnlyList<InstalledTheme> installed = await _themes.ListInstalledAsync(volume);

            // El integrado va siempre primero y siempre disponible: es a donde
            // se vuelve cuando un tema no carga.
            Themes.Add(new ThemeRow
            {
                Id = ThemeActivation.DefaultThemeId,
                Name = "Aura (integrado en el firmware)",
                CanShare = false,
                IsActive = active == ThemeActivation.DefaultThemeId
            });

            foreach (InstalledTheme theme in installed)
            {
                Themes.Add(new ThemeRow
                {
                    Id = theme.Id,
                    Name = theme.Name,
                    Loadable = theme.Loadable,
                    Reason = theme.Reason,
                    CanShare = theme.Loadable && await IsRedistributableAsync(volume, theme.Id),
                    IsActive = active == theme.Id
                });
            }

            StatusMessage = installed.Count == 0
                ? "Todavía no hay temas instalados en este iPod."
                : "";
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ThemeInstallException)
        {
            ErrorMessage = ex.Message;
        }
        finally { IsBusy = false; }
    }

    [RelayCommand]
    private async Task ActivateAsync(ThemeRow? row)
    {
        if (row is null || !TryGetVolume(out string volume)) return;

        // Activar un tema que no carga dejaría al iPod arrancando con el
        // fallback y al usuario sin entender por qué no cambió nada.
        if (!row.Loadable)
        {
            ErrorMessage = $"\"{row.Name}\" no se puede activar: {row.Reason}";
            return;
        }

        await RunAsync(async () =>
        {
            await _themes.ActivateAsync(volume, row.Id);
            foreach (ThemeRow other in Themes) other.IsActive = other.Id == row.Id;
            StatusMessage = $"\"{row.Name}\" se va a aplicar la próxima vez que enciendas el iPod.";
        });
    }

    [RelayCommand]
    private async Task RemoveAsync(ThemeRow? row)
    {
        if (row is null || row.IsBuiltIn || !TryGetVolume(out string volume)) return;

        await RunAsync(async () =>
        {
            // Borrar el tema activo dejaría al firmware buscando una carpeta
            // que no está: primero se vuelve al integrado.
            if (row.IsActive) await _themes.ActivateAsync(volume, ThemeActivation.DefaultThemeId);

            if (await _themes.UninstallAsync(volume, row.Id))
            {
                StatusMessage = $"Se quitó \"{row.Name}\" del iPod.";
                await RefreshAsync();
            }
            else
            {
                ErrorMessage = $"No se pudo quitar \"{row.Name}\" del iPod.";
            }
        });
    }

    /// <summary>Guarda una copia del tema para compartirlo, si su licencia lo permite.</summary>
    public async Task ShareAsync(ThemeRow row, string destinationFolder)
    {
        if (!TryGetVolume(out string volume)) return;

        await RunAsync(async () =>
        {
            string path = await _themes.ExportAsync(volume, row.Id, destinationFolder);
            StatusMessage = $"Se guardó la copia en {path}";
        });
    }

    public async Task BuildAsync()
    {
        if (!TryGetVolume(out string volume)) return;

        string name = NewThemeName.Trim();
        string id = SuggestedId;

        if (!AuraThemeID.IsValid(id))
        {
            ErrorMessage = $"\"{name}\" no produce un id válido: usa letras, números y espacios.";
            return;
        }

        await RunAsync(async () =>
        {
            var manifest = new AuraThemeManifest(
                id: id,
                name: name,
                author: NewThemeAuthor.Trim(),
                license: NewThemeIsRestricted ? ThemeLicense.Personal : ThemeLicense.Open,
                redistributable: !NewThemeIsRestricted);

            AuraThemeManifest installed = await _themes.BuildAndInstallAsync(volume, NewThemeSourceFolder, manifest);

            StatusMessage = $"Se instaló \"{installed.Name}\". Actívalo para verlo en el iPod.";
            NewThemeName = "";
            NewThemeSourceFolder = "";

            await RefreshAsync();
        });
    }

    private async Task<bool> IsRedistributableAsync(string volume, string themeId)
    {
        string path = Path.Combine(volume, ThemeInstaller.ThemesRelativeDir.Replace('/', Path.DirectorySeparatorChar), themeId);

        return await _themes.ValidateAsync(path, volume) is ThemeValidationResult.Success success
               && success.Manifest.Redistributable;
    }

    private async Task RunAsync(Func<Task> action)
    {
        IsBusy = true;
        ErrorMessage = "";

        try { await action(); }
        catch (Exception ex) when (ex is ThemeInstallException or IOException or UnauthorizedAccessException)
        {
            ErrorMessage = ex.Message;
        }
        finally { IsBusy = false; }
    }

    private bool TryGetVolume(out string volume)
    {
        volume = _session.Device?.VolumePath ?? "";

        if (volume.Length > 0 && _session.Device is { SupportsAuraContract: true }) return true;

        ErrorMessage = "";
        return false;
    }
}
