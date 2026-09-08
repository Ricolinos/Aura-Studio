using System.Net.Http;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using AuraStudio.App.Services;
using AuraStudio.Core;
using AuraStudio.Core.Installer;
using AuraStudio.Core.Resources;

namespace AuraStudio.App.ViewModels;

/// <summary>
/// Una tarjeta del selector de firmware: qué es esa familia, qué versión se
/// instalaría hoy, y si está elegida.
/// </summary>
public sealed partial class FirmwareChoiceCard : ObservableObject
{
    public required FirmwareFamily Family { get; init; }

    public required string Explanation { get; init; }

    public string Name => Family.DisplayName;

    /// <summary>El tag que se instalaría. Vacío solo si no hay ni Release ni marcador local.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(VersionBadge))]
    [NotifyPropertyChangedFor(nameof(HasVersion))]
    public partial string? Tag { get; set; }

    /// <summary>
    /// Si <see cref="Tag"/> salió de GitHub o del artefacto que trae esta copia
    /// de Studio. La pastilla lo dice: una versión sin procedencia no se puede
    /// interpretar (ST-053).
    /// </summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(VersionBadge))]
    public partial bool FromGitHub { get; set; }

    [ObservableProperty] public partial bool IsSelected { get; set; }

    public bool HasVersion => Tag is { Length: > 0 };

    public string VersionBadge => Tag is { Length: > 0 } tag
        ? FromGitHub ? tag : $"{tag} (incluida)"
        : "";
}

/// <summary>
/// La sección «Extras» (R4, ST-133): lo que el firmware ofrece más allá de la
/// biblioteca, y —lo principal— <b>cuál de los firmwares instalará el
/// asistente</b>.
///
/// <para>Port de <c>ExtrasView.swift</c>. Está deliberadamente casi vacía en su
/// mitad de abajo y lo dice de frente en vez de inventar filas: los juegos y el
/// cronómetro se decidieron NO implementar (D-063). La sección no muestra nada
/// que el aparato no tenga de verdad.</para>
/// </summary>
public sealed partial class ExtrasViewModel : ViewModelBase
{
    private readonly IAppPreferences _preferences;
    private readonly IDeviceSessionService _session;
    private readonly IFirmwareArtifactsProvider _artifacts;
    private readonly IReleaseCacheStore _cache;
    private readonly Platform.CredentialStore _credentials;
    private readonly HttpClient _http = new();

    private bool _loaded;

    public ExtrasViewModel(IAppPreferences preferences, IDeviceSessionService session,
                           IFirmwareArtifactsProvider artifacts, IReleaseCacheStore cache,
                           Platform.CredentialStore credentials)
    {
        _preferences = preferences;
        _session = session;
        _artifacts = artifacts;
        _cache = cache;
        _credentials = credentials;

        Cards =
        [
            .. FirmwareFamily.Installable.Select(family => new FirmwareChoiceCard
            {
                Family = family,
                Explanation = ExplanationFor(family),
                IsSelected = Equals(family, preferences.FirmwareFamilyToInstall)
            })
        ];

        _session.Changed += (_, _) => NotifyDeviceChanged();
    }

    /// <summary>
    /// Los textos son los de macOS, palabra por palabra: describen el mismo
    /// firmware, y dos descripciones distintas del mismo producto según la
    /// computadora sería la peor clase de divergencia.
    /// </summary>
    private static string ExplanationFor(FirmwareFamily family)
    {
        if (Equals(family, FirmwareFamily.Metro))
        {
            return Strings.Get("extras-view-model.visual-metro");
        }

        if (Equals(family, FirmwareFamily.Moonlit))
        {
            return Strings.Get("extras-view-model.visual-moonlit");
        }

        return Strings.Get("extras-view-model.visual-aura");
    }

    public IReadOnlyList<FirmwareChoiceCard> Cards { get; }

    public static string FirmwareIntro => Strings.Get("extras-view-model.firmware-intro");

    /// <summary>
    /// Elegir acá <b>no toca el iPod</b>: es una preferencia. El Instalador —con
    /// su flasheo y sus confirmaciones— es el único que escribe.
    /// </summary>
    public void Select(FirmwareChoiceCard card)
    {
        _preferences.FirmwareFamilyToInstall = card.Family;

        foreach (FirmwareChoiceCard other in Cards)
            other.IsSelected = ReferenceEquals(other, card);

        NotifyChoiceChanged();
    }

    // MARK: - Qué significa lo que acaba de elegir (ST-138)

    /// <summary>
    /// Port parcial de `switchControls` de `ExtrasView.swift`.
    ///
    /// <para>Sin esto, elegir una tarjeta no producía <b>ningún</b> efecto
    /// visible más allá del punto del radio: el dueño lo reportó como «desde
    /// Extras no ocurre nada». En macOS, elegir siempre contesta qué implica y
    /// ofrece la acción que sigue; acá no contestaba nada.</para>
    ///
    /// <para><b>Lo que sigue faltando, y por qué:</b> macOS distingue un tercer
    /// caso —la familia elegida está <i>dormida</i> en el disco, y entonces
    /// ofrece «Cambiar a …», que no reinstala nada (ST-056)—. Windows no puede:
    /// <c>IPodDiskInfo</c> no modela las familias dormidas todavía. Por eso los
    /// textos de acá <b>no prometen</b> poder volver desde esta pantalla, que
    /// es lo que sí promete el texto de macOS. Prometer un botón que no existe
    /// sería peor que no decir nada.</para>
    /// </summary>
    public FirmwareFamily ChosenFamily => _preferences.FirmwareFamilyToInstall;

    private FirmwareFamily? ActiveFamily =>
        Device is { SupportsAuraContract: true } device ? device.DeclaredFamily : null;

    /// <summary>La elegida ya es la que está corriendo: no hay nada que hacer, y se dice.</summary>
    public bool ChoiceIsAlreadyActive => ActiveFamily is { } active && Equals(active, ChosenFamily);

    public string ChoiceNote
    {
        get
        {
            if (ChoiceIsAlreadyActive)
            {
                return Strings.Format(
                    "extras-view-model.choice-already-active", ChosenFamily.DisplayName);
            }

            if (ActiveFamily is { } active)
            {
                return Strings.Format(
                    "extras-view-model.choice-adds", active.DisplayName, ChosenFamily.DisplayName);
            }

            return Strings.Format(
                "extras-view-model.choice-will-install", ChosenFamily.DisplayName);
        }
    }

    /// <summary>«Instalar Metro» — el mismo texto que macOS pone en su botón.</summary>
    public string InstallActionLabel => $"Instalar {ChosenFamily.DisplayName}";

    /// <summary>
    /// El botón se ofrece salvo cuando no hay nada que instalar. Lleva al
    /// Instalador; **no instala desde acá**: el flasheo y sus confirmaciones
    /// son suyos y de nadie más.
    /// </summary>
    public bool CanOpenInstaller => !ChoiceIsAlreadyActive;

    private void NotifyChoiceChanged()
    {
        OnPropertyChanged(nameof(ChosenFamily));
        OnPropertyChanged(nameof(ChoiceIsAlreadyActive));
        OnPropertyChanged(nameof(ChoiceNote));
        OnPropertyChanged(nameof(InstallActionLabel));
        OnPropertyChanged(nameof(CanOpenInstaller));
    }

    // MARK: - De dónde salen las versiones (ST-077)

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(VersionSourceNote))]
    public partial bool IsRefreshing { get; set; }

    private bool AnyFromGitHub => Cards.Any(card => card.FromGitHub);

    /// <summary>
    /// Sin esto, "v0.4.4-beta" no distingue "lo último publicado" de "lo que
    /// traigo adentro" — y esa diferencia es justo la que el dueño necesitaba
    /// ver.
    /// </summary>
    public string VersionSourceNote => Strings.Get(IsRefreshing
        ? "extras-view-model.checking-github"
        : AnyFromGitHub
            ? "extras-view-model.versions-from-github"
            : "extras-view-model.versions-bundled");

    /// <summary>Se carga una vez por aparición de la pantalla.</summary>
    public Task LoadAsync() => _loaded ? Task.CompletedTask : RefreshAsync(force: false);

    /// <summary>
    /// «Revisar de nuevo»: salta el caché de 24 h. Una revisión manual del
    /// usuario tiene que ser una consulta en vivo — si no, un caché que se llenó
    /// justo antes de publicarse el Release nuevo lo esconde hasta que el TTL
    /// venza solo (D-300).
    /// </summary>
    [RelayCommand]
    private Task CheckAgainAsync() => RefreshAsync(force: true);

    private async Task RefreshAsync(bool force)
    {
        _loaded = true;
        IsRefreshing = true;

        try
        {
            string? token = _credentials.Load(Platform.ApiKeyService.GitHub.Key);

            foreach (FirmwareChoiceCard card in Cards)
            {
                FirmwareVersionEntry entry = await FirmwareVersionResolver.ResolveAsync(
                    card.Family, _artifacts.For(card.Family), _http, _cache, token, force);

                card.Tag = entry.Tag;
                card.FromGitHub = entry.FromGitHub;
            }
        }
        finally
        {
            IsRefreshing = false;
        }
    }

    // MARK: - Disponible en el dispositivo

    private IPodDiskInfo? Device => _session.Device;

    /// <summary>
    /// Temas necesita un iPod con un firmware del contrato montado <b>y</b> que
    /// ese firmware anuncie su formato de temas: moonlit.aura no tiene sistema
    /// de temas y no publica la clave.
    /// </summary>
    public bool CanManageThemes =>
        Device is { SupportsAuraContract: true, SupportedThemeFormat: not null };

    /// <summary>
    /// Por qué está deshabilitado. Un botón deshabilitado siempre explica qué
    /// falta (ST-053) — nunca se esconde y nunca se queda callado.
    /// </summary>
    public string ThemesDetail
    {
        get
        {
            if (Device is not { SupportsAuraContract: true } device)
                return Strings.Get("extras-view-model.themes-need-aura");

            if (device.SupportedThemeFormat is null)
            {
                string name = device.DeclaredFamily?.DisplayName
                    ?? Strings.Get("extras-view-model.this-firmware");
                return Strings.Format("extras-view-model.themes-unsupported", name);
            }

            return Strings.Get("extras-view-model.themes-detail");
        }
    }

    public static string AnimationsDetail => Strings.Get("extras-view-model.animations-detail");

    // MARK: - Todavía no

    public static string PlannedIntro => Strings.Get("extras-view-model.planned-intro");

    public static string NotImplemented => Strings.Get("extras-view-model.not-implemented");

    // MARK: - Licencias

    public static string LicensesDetail => Strings.Get("extras-view-model.licenses-detail");

    private void NotifyDeviceChanged()
    {
        OnPropertyChanged(nameof(CanManageThemes));
        OnPropertyChanged(nameof(ThemesDetail));

        // Conectar o desconectar el iPod cambia lo que la elección significa:
        // «se instalará la próxima vez» no es lo mismo que «tu iPod tiene Aura».
        NotifyChoiceChanged();
    }
}
