using AuraStudio.Core.Networking;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// ST-211: port de <c>AppUpdateDecisionTests.swift</c> de <b>ST-193</b>, que es
/// la referencia de esta funcionalidad (acuerdo de la sesión maestra: se escribe
/// primero en Swift y Windows la porta citando la ST).
///
/// <para>Estos casos son la <b>especificación ejecutable</b> de las reglas: son
/// los mismos trece de allá, con los mismos nombres traducidos y las mismas
/// entradas. Si Windows se comporta distinto en cualquiera de ellos, uno de los
/// dos está mal.</para>
///
/// <para>Todo acá es puro: no hay red, ni reloj, ni disco.</para>
/// </summary>
public class AppUpdateDecisionTests
{
    private static GitHubRelease Release(
        string tag,
        bool draft = false,
        bool prerelease = false,
        string[]? assets = null,
        string? htmlUrl = null) => new()
    {
        TagName = tag,
        Draft = draft,
        Prerelease = prerelease,
        HtmlUrl = htmlUrl,
        Assets =
        [
            .. (assets ?? []).Select(name => new GitHubReleaseAsset
            {
                Name = name,
                Url = "https://api.github.com/assets/1",
                Size = 1,
                BrowserDownloadUrl = $"https://github.com/descarga/{name}"
            })
        ]
    };

    // MARK: - El patrón de nombres (el único contrato nuevo)

    /// <summary>
    /// Congelado por la sesión maestra y verificado contra los Releases v0.2.2 y
    /// v0.2.3 reales. Cambiarlo rompe la actualización de todas las versiones ya
    /// instaladas, así que este caso es un <b>candado</b>.
    /// </summary>
    [Fact]
    public void LosNombresDeLosAssetsSiguenElPatronCongelado()
    {
        var version = new SemVer(0, 3, 0);

        Assert.Equal("AuraStudio-0.3.0.dmg", AppUpdatePlatform.Mac.AssetName(version));
        Assert.Equal("AuraStudioSetup-0.3.0-arm64.exe", AppUpdatePlatform.WindowsArm64.AssetName(version));
        Assert.Equal("AuraStudioSetup-0.3.0-x64.exe", AppUpdatePlatform.WindowsX64.AssetName(version));
    }

    [Fact]
    public void ElNombreConservaElSufijoDePrerelease()
    {
        var version = new SemVer(0, 3, 0, "beta");

        Assert.Equal("AuraStudio-0.3.0-beta.dmg", AppUpdatePlatform.Mac.AssetName(version));
    }

    // MARK: - Cuándo hay novedad

    [Fact]
    public void OfreceUnaVersionMasNuevaConSuAsset()
    {
        AppUpdateAvailable? decision = AppUpdateDecision.Decide(
            "0.2.3",
            [Release("v0.3.0", assets: ["AuraStudio-0.3.0.dmg"])],
            includePrereleases: true,
            AppUpdatePlatform.Mac);

        AppUpdateAvailable update = Assert.NotNull(decision);

        Assert.Equal("v0.3.0", update.Tag);
        Assert.Equal(new SemVer(0, 3, 0), update.Version);
        Assert.Equal("AuraStudio-0.3.0.dmg", update.AssetName);
        Assert.Equal("https://github.com/descarga/AuraStudio-0.3.0.dmg", update.DownloadUrl);
    }

    /// <summary>Nunca se ofrece "actualizar" hacia atrás, ni a la misma.</summary>
    [Fact]
    public void NoDiceNadaCuandoLoInstaladoEsLoMasNuevoOMas()
    {
        Assert.Null(AppUpdateDecision.Decide(
            "0.3.0", [Release("v0.3.0", assets: ["AuraStudio-0.3.0.dmg"])],
            includePrereleases: true, AppUpdatePlatform.Mac));

        Assert.Null(AppUpdateDecision.Decide(
            "0.4.0", [Release("v0.3.0", assets: ["AuraStudio-0.3.0.dmg"])],
            includePrereleases: true, AppUpdatePlatform.Mac));
    }

    [Fact]
    public void EligeLaVersionMasAltaNoLaPrimera()
    {
        AppUpdateAvailable? decision = AppUpdateDecision.Decide(
            "0.2.0",
            [Release("v0.2.1"), Release("v0.3.0"), Release("v0.2.9")],
            includePrereleases: true, AppUpdatePlatform.Mac);

        Assert.Equal("v0.3.0", Assert.NotNull(decision).Tag);
    }

    [Fact]
    public void LosDraftsNuncaCuentan()
    {
        Assert.Null(AppUpdateDecision.Decide(
            "0.2.3", [Release("v0.3.0", draft: true)],
            includePrereleases: true, AppUpdatePlatform.Mac));
    }

    [Fact]
    public void LasPrereleasesCuentanSoloSiSePiden()
    {
        GitHubRelease[] releases = [Release("v0.3.0", prerelease: true)];

        Assert.Null(AppUpdateDecision.Decide(
            "0.2.3", releases, includePrereleases: false, AppUpdatePlatform.Mac));

        AppUpdateAvailable? withBetas = AppUpdateDecision.Decide(
            "0.2.3", releases, includePrereleases: true, AppUpdatePlatform.Mac);

        Assert.Equal("v0.3.0", Assert.NotNull(withBetas).Tag);
    }

    /// <summary>Un tag que no es SemVer se ignora sin romper el resto.</summary>
    [Fact]
    public void IgnoraLosTagsQueNoSonVersiones()
    {
        AppUpdateAvailable? decision = AppUpdateDecision.Decide(
            "0.2.3", [Release("nightly"), Release("v0.3.0")],
            includePrereleases: true, AppUpdatePlatform.Mac);

        Assert.Equal("v0.3.0", Assert.NotNull(decision).Tag);
    }

    /// <summary>
    /// Sin saber qué hay instalado no se puede afirmar que algo sea más nuevo:
    /// lo prudente es callar.
    /// </summary>
    [Fact]
    public void NoDiceNadaSiLaVersionInstaladaNoSePuedeLeer()
    {
        Assert.Null(AppUpdateDecision.Decide(
            "no-es-una-version", [Release("v0.3.0", assets: ["AuraStudio-0.3.0.dmg"])],
            includePrereleases: true, AppUpdatePlatform.Mac));
    }

    // MARK: - El asset que falta

    /// <summary>
    /// Se avisa igual de la versión nueva, pero SIN descarga: un botón
    /// "Descargar" que falla es peor que no tenerlo.
    /// </summary>
    [Fact]
    public void AnunciaLaVersionAunqueFalteElInstalador()
    {
        AppUpdateAvailable? decision = AppUpdateDecision.Decide(
            "0.2.3", [Release("v0.3.0", assets: ["AuraStudioSetup-0.3.0-arm64.exe"])],
            includePrereleases: true, AppUpdatePlatform.Mac);

        AppUpdateAvailable update = Assert.NotNull(decision);

        Assert.Null(update.DownloadUrl);
        Assert.False(update.CanDownload);
        Assert.Equal("AuraStudio-0.3.0.dmg", update.AssetName);
        Assert.NotEmpty(update.ReleasePageUrl);
    }

    /// <summary>Cada plataforma se lleva SU archivo, no el primero que haya.</summary>
    [Fact]
    public void CadaPlataformaSeLlevaSuPropioAsset()
    {
        GitHubRelease[] releases =
        [
            Release("v0.3.0", assets:
            [
                "AuraStudio-0.3.0.dmg",
                "AuraStudioSetup-0.3.0-arm64.exe",
                "AuraStudioSetup-0.3.0-x64.exe"
            ])
        ];

        (AppUpdatePlatform Platform, string Expected)[] cases =
        [
            (AppUpdatePlatform.Mac, "AuraStudio-0.3.0.dmg"),
            (AppUpdatePlatform.WindowsArm64, "AuraStudioSetup-0.3.0-arm64.exe"),
            (AppUpdatePlatform.WindowsX64, "AuraStudioSetup-0.3.0-x64.exe")
        ];

        foreach ((AppUpdatePlatform platform, string expected) in cases)
        {
            AppUpdateAvailable? decision = AppUpdateDecision.Decide(
                "0.2.3", releases, includePrereleases: true, platform);

            Assert.Equal($"https://github.com/descarga/{expected}",
                         Assert.NotNull(decision).DownloadUrl);
        }
    }

    // MARK: - La página del Release

    [Fact]
    public void PrefiereLaPaginaQueDaGitHub()
    {
        AppUpdateAvailable? decision = AppUpdateDecision.Decide(
            "0.2.3", [Release("v0.3.0", htmlUrl: "https://github.com/otro/sitio")],
            includePrereleases: true, AppUpdatePlatform.Mac);

        Assert.Equal("https://github.com/otro/sitio", Assert.NotNull(decision).ReleasePageUrl);
    }

    /// <summary>
    /// Sin <c>html_url</c> (respuesta recortada, caché viejo) se arma con el repo
    /// y el tag, que es una URL estable de GitHub.
    /// </summary>
    [Fact]
    public void CaeALaPaginaCanonicaDelRelease()
    {
        AppUpdateAvailable? decision = AppUpdateDecision.Decide(
            "0.2.3", [Release("v0.3.0")], includePrereleases: true, AppUpdatePlatform.Mac);

        Assert.Equal("https://github.com/Ricolinos/Aura-Studio/releases/tag/v0.3.0",
                     Assert.NotNull(decision).ReleasePageUrl);
    }

    // MARK: - Cuándo se pregunta y cuándo se avisa (ST-211, lado Windows)

    [Fact]
    public void SinHaberPreguntadoNuncaTocaPreguntar()
    {
        Assert.True(AppUpdateSchedule.ShouldCheckAutomatically(null, DateTimeOffset.Now));
    }

    [Fact]
    public void ElAutomaticoNoPreguntaDosVecesEnVeinticuatroHoras()
    {
        DateTimeOffset now = new(2026, 9, 6, 12, 0, 0, TimeSpan.Zero);

        Assert.False(AppUpdateSchedule.ShouldCheckAutomatically(now.AddHours(-23), now));
        Assert.True(AppUpdateSchedule.ShouldCheckAutomatically(now.AddHours(-24), now));
        Assert.True(AppUpdateSchedule.ShouldCheckAutomatically(now.AddDays(-3), now));
    }

    [Fact]
    public void UnRelojQueFueHaciaAtrasNoDejaALaAppSinPreguntarParaSiempre()
    {
        DateTimeOffset now = new(2026, 9, 6, 12, 0, 0, TimeSpan.Zero);

        Assert.True(AppUpdateSchedule.ShouldCheckAutomatically(now.AddDays(30), now));
    }

    [Fact]
    public void NoSeAvisaDosVecesDeLaMismaVersion()
    {
        Assert.False(AppUpdateSchedule.ShouldAnnounce("v0.3.0", "v0.3.0"));
    }

    [Fact]
    public void HaberCalladoUnaVersionNoCallaLaSiguiente()
    {
        Assert.True(AppUpdateSchedule.ShouldAnnounce("v0.3.1", "v0.3.0"));
        Assert.True(AppUpdateSchedule.ShouldAnnounce("v0.3.0", null));
    }

    [Fact]
    public void ElIntervaloEsDeVeinticuatroHorasFijas()
    {
        Assert.Equal(TimeSpan.FromHours(24), AppUpdateSchedule.Interval);
    }
}
