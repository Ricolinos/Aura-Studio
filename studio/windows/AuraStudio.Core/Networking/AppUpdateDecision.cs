namespace AuraStudio.Core.Networking;

/// <summary>
/// Para qué plataforma se busca el instalador (ST-193, port literal de
/// <c>AppUpdatePlatform</c> de Swift).
///
/// <para>Las tres están acá aunque Windows solo use dos, y es deliberado: el
/// patrón de nombres de los assets es <b>el único contrato nuevo</b> de esta
/// funcionalidad, lo congeló la sesión maestra para las dos plataformas, y
/// tenerlo escrito en un solo lugar por lado es lo que hace que los dos digan lo
/// mismo.</para>
///
/// <para>El patrón, tal como quedó fijado (y tal como ya lo cumplen los Releases
/// v0.2.2 y v0.2.3):</para>
/// <code>
/// tag:  v&lt;versión&gt;
/// mac:  AuraStudio-&lt;versión&gt;.dmg
/// win:  AuraStudioSetup-&lt;versión&gt;-arm64.exe
///       AuraStudioSetup-&lt;versión&gt;-x64.exe
/// </code>
///
/// <para><b>Ningún otro asset cuenta.</b> En Windows, elegir mal la arquitectura
/// es peor que no ofrecer nada: ST-135 documenta que el Setup x64 en una máquina
/// ARM avisa y deja continuar, así que ofrecerlo por defecto sería empujar al
/// usuario a la versión lenta.</para>
/// </summary>
public enum AppUpdatePlatform
{
    Mac,
    WindowsArm64,
    WindowsX64
}

public static class AppUpdatePlatformNames
{
    /// <summary>
    /// La de este proceso. Se mira la arquitectura del <b>proceso</b> y no la de
    /// la máquina: un Aura Studio x64 corriendo bajo emulación en un Windows ARM
    /// tiene que ofrecerse su propio instalador.
    /// </summary>
    public static AppUpdatePlatform Current =>
        System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture
            == System.Runtime.InteropServices.Architecture.Arm64
            ? AppUpdatePlatform.WindowsArm64
            : AppUpdatePlatform.WindowsX64;

    /// <summary>El nombre EXACTO del asset. La versión va sin la <c>v</c> del tag.</summary>
    public static string AssetName(this AppUpdatePlatform platform, SemVer version) => platform switch
    {
        AppUpdatePlatform.Mac => $"AuraStudio-{version.ReleaseString}.dmg",
        AppUpdatePlatform.WindowsArm64 => $"AuraStudioSetup-{version.ReleaseString}-arm64.exe",
        _ => $"AuraStudioSetup-{version.ReleaseString}-x64.exe"
    };
}

/// <summary>Lo que hay que mostrar cuando hay una versión más nueva de la app.</summary>
/// <param name="Version">La versión publicada, ya parseada.</param>
/// <param name="Tag">
/// El tag tal cual lo publicó GitHub (<c>v0.3.0</c>) — es lo que se persiste para
/// no repetir el aviso.
/// </param>
/// <param name="ReleasePageUrl">La página del Release, para "Ver novedades".</param>
/// <param name="Asset">
/// El asset a bajar para ESTA plataforma, o <c>null</c> si el Release no lo trae.
/// </param>
/// <param name="AssetName">El nombre del asset esperado, para poder decirlo si falta.</param>
public readonly record struct AppUpdateAvailable(
    SemVer Version,
    string Tag,
    string ReleasePageUrl,
    GitHubReleaseAsset? Asset,
    string AssetName)
{
    /// <summary>La URL pública de descarga, o <c>null</c> si el asset no está.</summary>
    public string? DownloadUrl => Asset?.BrowserDownloadUrl is { Length: > 0 } url ? url : null;

    /// <summary>
    /// Si se puede ofrecer el botón de descargar. Sin asset se anuncia igual la
    /// versión, pero con el enlace a la página: un botón "Descargar" que falla es
    /// peor que no tenerlo.
    /// </summary>
    public bool CanDownload => Asset is not null;
}

/// <summary>
/// ST-193 (port literal desde Swift, que es la referencia por acuerdo de la
/// sesión maestra): decidir si hay una versión más nueva <b>de Aura Studio</b> y
/// cuál archivo le corresponde a esta plataforma.
///
/// <para>Es <b>pura a propósito</b>: no consulta la red, no lee el ensamblado, no
/// toca disco. Se le dan la versión instalada y los Releases ya traídos, y
/// devuelve una decisión. Por eso se prueba entera sin red, y por eso las dos
/// plataformas pueden compartir exactamente las mismas reglas.</para>
///
/// <para><b>Las reglas, en orden:</b></para>
/// <list type="number">
/// <item>Un <b>draft</b> nunca cuenta: no es instalable.</item>
/// <item>Una <b>prerelease</b> cuenta solo si se piden. Hoy todo lo publicado es
/// beta, así que en la práctica cuenta siempre; el interruptor importa el día
/// que exista un canal estable.</item>
/// <item>El tag se lee como SemVer (<c>v0.3.0</c> → <c>0.3.0</c>). Un tag que no
/// parsea <b>se ignora</b>, no rompe nada.</item>
/// <item>De los que quedan, gana el <b>mayor</b>, no el primero.</item>
/// <item>Solo hay novedad si ese mayor es <b>estrictamente mayor</b> que lo
/// instalado. Nunca se ofrece "actualizar" hacia atrás.</item>
/// <item>El asset se busca por <b>nombre exacto</b>. Si no está, igual se avisa
/// de la versión nueva, pero sin botón de descarga.</item>
/// </list>
/// </summary>
public static class AppUpdateDecision
{
    /// <summary>
    /// El repositorio donde se publican los instaladores de la app — distinto
    /// del del firmware (<c>Aura-Firmware</c> y hermanos).
    /// </summary>
    public const string Repository = "Ricolinos/Aura-Studio";

    /// <summary>
    /// Decide. <paramref name="installedVersion"/> es la versión de la app
    /// corriendo; <paramref name="releases"/> es lo que devolvió GitHub.
    ///
    /// <para>Devuelve <c>null</c> cuando no hay nada que ofrecer — incluido el
    /// caso de una versión instalada que no parsea, donde lo prudente es callar:
    /// sin saber qué hay instalado no se puede afirmar que algo sea más
    /// nuevo.</para>
    /// </summary>
    public static AppUpdateAvailable? Decide(
        string installedVersion,
        IReadOnlyList<GitHubRelease> releases,
        bool includePrereleases,
        AppUpdatePlatform platform)
    {
        if (SemVer.Parse(installedVersion) is not { } installed) return null;

        if (GitHubReleaseChecker.PickLatest(releases, includePrereleases) is not { } latest) return null;
        if (SemVer.Parse(latest.TagName) is not { } latestVersion) return null;
        if (installed >= latestVersion) return null;

        string assetName = platform.AssetName(latestVersion);

        return new AppUpdateAvailable(
            latestVersion,
            latest.TagName,
            ReleasePageUrl(latest),
            latest.Asset(assetName),
            assetName);
    }

    /// <summary>
    /// La página del Release. Se prefiere la que da GitHub; si no vino
    /// (respuesta recortada, caché viejo), se arma con el repo y el tag — es una
    /// URL estable y documentada de GitHub.
    /// </summary>
    public static string ReleasePageUrl(GitHubRelease release) =>
        release.HtmlUrl is { Length: > 0 } html
            ? html
            : $"https://github.com/{Repository}/releases/tag/{release.TagName}";
}
