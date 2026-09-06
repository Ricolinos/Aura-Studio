using System.Net.Http;
using System.Reflection;
using CommunityToolkit.Mvvm.ComponentModel;
using AuraStudio.Core.Networking;

namespace AuraStudio.App.Services;

/// <summary>
/// Si hay una versión nueva de <b>Aura Studio</b> (ST-211, sobre la propuesta de
/// ST-191 y con la decisión de ST-193). El hermano de <c>AuraUpdateChecker</c>,
/// que hace lo mismo para el firmware.
///
/// <para><b>Qué había</b>: nada. Studio sabía avisar de una versión nueva del
/// firmware desde ST-046, pero no sabía nada de sí misma — quien tuviera la
/// 0.2.1 no se enteraba de la 0.2.3 salvo yendo a mirar el repositorio. Y como
/// el firmware que la app instala viaja <b>dentro</b> de la app, una app vieja es
/// también un firmware viejo: las dos cosas se arrastran juntas.</para>
///
/// <para><b>Lo que decide, lo decide Core</b>: <see cref="AppUpdateDecision"/>,
/// portada literal desde Swift (ST-193, que es la referencia). Acá queda lo que
/// no es decisión: cuándo se pregunta, qué se dice y qué pasa al descargar.</para>
///
/// <para><b>Nada modal y nunca dos veces por lo mismo</b> (§4 de la propuesta):
/// el chequeo automático corre como mucho una vez cada 24 h y avisa con una
/// franja que se puede cerrar; cerrada, esa versión no vuelve a avisar. El
/// chequeo a pedido ignora el intervalo <b>y el descarte</b>, y siempre dice
/// algo, incluso "ya tienes la más nueva".</para>
///
/// <para><b>Sin red</b>: el automático calla; el manual distingue "no se pudo
/// preguntar" de "no hay novedades", como ST-210.</para>
/// </summary>
public sealed partial class AppUpdateService : ObservableObject
{
    private readonly IAppPreferences _preferences;
    private readonly Platform.CredentialStore _credentials;
    private readonly HttpClient _http = new();

    public AppUpdateService(IAppPreferences preferences, Platform.CredentialStore credentials)
    {
        _preferences = preferences;
        _credentials = credentials;
    }

    /// <summary>
    /// La versión instalada, como la muestra "Acerca de". Sale del ensamblado,
    /// que es uno de los tres lugares que suben juntos en cada release.
    /// </summary>
    public static string InstalledVersion =>
        Assembly.GetExecutingAssembly().GetName().Version?.ToString(3) ?? "";

    /// <summary>
    /// Mientras Studio siga en <c>0.x</c> todo lo publicado es beta: excluir las
    /// prereleases dejaría la consulta sin nada que devolver, nunca. El
    /// interruptor importa el día que exista un canal estable.
    /// </summary>
    private const bool IncludePrereleases = true;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(HasUpdate))]
    [NotifyPropertyChangedFor(nameof(AnnouncementMessage))]
    [NotifyPropertyChangedFor(nameof(CanDownload))]
    public partial AppUpdateAvailable? Available { get; private set; }

    public bool HasUpdate => Available is not null;

    /// <summary>
    /// Si se puede ofrecer "Descargar". Sin el instalador de esta arquitectura
    /// se anuncia igual la versión, pero con el enlace a la página del Release.
    /// </summary>
    public bool CanDownload => Available?.CanDownload == true;

    /// <summary>El texto de la franja, el mismo que la de macOS.</summary>
    public string AnnouncementMessage => Available is { } update
        ? $"Hay una versión nueva de Aura Studio: {update.Version.ReleaseString}. "
          + $"Tienes la {InstalledVersion}."
        : "";

    /// <summary>
    /// Si la franja está a la vista. Se apaga al cerrarla, y esa versión no
    /// vuelve a encenderla sola.
    /// </summary>
    [ObservableProperty]
    public partial bool IsAnnouncing { get; set; }

    /// <summary>Lo que se dice en Ajustes › Acerca de. Vacío hasta que se pregunte.</summary>
    [ObservableProperty]
    public partial string StatusMessage { get; set; } = "";

    [ObservableProperty]
    public partial bool IsChecking { get; set; }

    /// <summary>
    /// El chequeo del arranque: en segundo plano, como mucho una vez cada 24 h,
    /// y <b>callado</b> si no hay red o no hay novedades. Nunca bloquea nada.
    /// </summary>
    public async Task CheckOnLaunchAsync(CancellationToken ct = default)
    {
        if (!AppUpdateSchedule.ShouldCheckAutomatically(_preferences.AppUpdateLastCheck, DateTimeOffset.Now))
            return;

        (IReadOnlyList<GitHubRelease>? releases, bool failed) = await FetchAsync(ct);

        // Sin red, el automático calla: el usuario no preguntó nada. Y la fecha
        // NO se anota: si se anotara, un rato sin conexión al arrancar dejaría a
        // la app sin volver a preguntar en 24 h.
        if (failed || releases is null) return;

        _preferences.AppUpdateLastCheck = DateTimeOffset.Now;

        Available = AppUpdateDecision.Decide(
            InstalledVersion, releases, IncludePrereleases, AppUpdatePlatformNames.Current);

        // Un aviso por versión. Cerrar la franja de la 0.3.0 no calla la 0.3.1.
        IsAnnouncing = Available is { } update
                       && AppUpdateSchedule.ShouldAnnounce(update.Tag, _preferences.AppUpdateAnnouncedVersion);
    }

    /// <summary>
    /// "Buscar actualizaciones de Aura Studio": ignora el intervalo <b>y el
    /// descarte</b>, y siempre dice algo. Consultar a mano y que no pase nada
    /// visible es lo mismo que un botón roto.
    /// </summary>
    public async Task CheckNowAsync(CancellationToken ct = default)
    {
        IsChecking = true;
        StatusMessage = "Buscando actualizaciones de Aura Studio…";

        try
        {
            (IReadOnlyList<GitHubRelease>? releases, bool failed) = await FetchAsync(ct);

            if (failed || releases is null)
            {
                // ST-210: "no se pudo preguntar" no es "no hay novedades".
                StatusMessage = "No se pudo consultar GitHub para saber si hay una versión más nueva. " +
                                "Revisa tu conexión y vuelve a intentar.";
                return;
            }

            _preferences.AppUpdateLastCheck = DateTimeOffset.Now;

            Available = AppUpdateDecision.Decide(
                InstalledVersion, releases, IncludePrereleases, AppUpdatePlatformNames.Current);

            if (Available is not { } update)
            {
                StatusMessage = $"Aura Studio {InstalledVersion} es la versión más nueva publicada.";
                IsAnnouncing = false;
                return;
            }

            // A pedido se muestra aunque ya se hubiera descartado: el usuario
            // acaba de preguntar por esto.
            IsAnnouncing = true;

            StatusMessage = update.CanDownload
                ? AnnouncementMessage
                : AnnouncementMessage + $" Este Release no trae {update.AssetName}: " +
                  "ábrelo en GitHub para descargarlo a mano.";
        }
        catch (OperationCanceledException)
        {
            StatusMessage = "Se detuvo la búsqueda de actualizaciones.";
        }
        finally
        {
            IsChecking = false;
        }
    }

    /// <summary>Cerrar la franja: esa versión no vuelve a avisar sola.</summary>
    public void DismissAnnouncement()
    {
        if (Available is { } update) _preferences.AppUpdateAnnouncedVersion = update.Tag;

        IsAnnouncing = false;
    }

    /// <summary>Cuánto va de la descarga, de 0 a 1.</summary>
    [ObservableProperty]
    public partial double DownloadProgress { get; set; }

    [ObservableProperty]
    public partial bool IsDownloading { get; set; }

    /// <summary>
    /// "Descargar": baja el instalador de <b>la arquitectura de este proceso</b>
    /// (ST-135) y lo ejecuta.
    ///
    /// <para>Es la diferencia deliberada con macOS, donde solo se abre la URL:
    /// acá el instalador se ejecuta, así que <b>se verifica antes</b> —el
    /// SHA-256 que publica la propia API si viene, y si no el tamaño exacto—.
    /// Al arrancar el instalador se cierra la ventana, no se mata el proceso,
    /// para que el guardado pendiente del catálogo salga primero (ST-204).</para>
    /// </summary>
    public async Task DownloadAndInstallAsync(CancellationToken ct = default)
    {
        if (Available is not { Asset: { } asset }) return;

        IsDownloading = true;
        DownloadProgress = 0;
        StatusMessage = $"Descargando Aura Studio {Available.Value.Version.ReleaseString}…";

        try
        {
            var progress = new Progress<double>(fraction => DownloadProgress = fraction);

            Platform.AppUpdateDownloadResult result = await Platform.AppUpdateInstaller.DownloadAndRunAsync(
                _http, asset, _credentials.Load(Platform.ApiKeyService.GitHub.Key), progress, ct);

            StatusMessage = result.Message;

            if (result.Outcome != Platform.AppUpdateDownloadOutcome.Started) return;

            // El instalador ya arrancó: cerrar la ventana deja que se guarde lo
            // pendiente y que la app se vaya sola.
            (Microsoft.UI.Xaml.Application.Current as App)?.MainWindow?.Close();
        }
        finally
        {
            IsDownloading = false;
        }
    }

    /// <summary>La página del Release, para "Ver qué hay de nuevo".</summary>
    public string? PageUrl => Available?.ReleasePageUrl;

    /// <summary>
    /// Los Releases del repositorio de la app. <c>null</c> con
    /// <c>failed: false</c> no existe: o se trajeron, o no se pudo.
    /// </summary>
    private async Task<(IReadOnlyList<GitHubRelease>? Releases, bool Failed)> FetchAsync(CancellationToken ct)
    {
        try
        {
            string? token = _credentials.Load(Platform.ApiKeyService.GitHub.Key);

            List<GitHubRelease> releases = await GitHubReleaseChecker.FetchReleasesAsync(
                _http, AppUpdateDecision.Repository, token, ct).ConfigureAwait(false);

            // ST-074: con el token rechazado la lista viene vacía y sin
            // excepción. Eso es "no se pudo preguntar", no "no hay novedades".
            if (releases.Count == 0 && GitHubReleaseChecker.LastAuthFailure)
                return (null, true);

            return (releases, false);
        }
        catch (Exception ex) when (ex is HttpRequestException or GitHubReleaseCheckerError or TaskCanceledException)
        {
            return (null, true);
        }
    }
}
