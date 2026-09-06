using AuraStudio.Core;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// La decisión de "¿hay actualización del firmware?" (ST-210), sin red.
///
/// <para>Lo que se protege son tres cosas que la versión anterior hacía mal:
/// que <b>nunca</b> se diga "está al día" sin haber preguntado, que no se ofrezca
/// instalar un Release que esta copia de Studio no tiene, y que todo se compare
/// contra la familia instalada (ST-046).</para>
/// </summary>
public class FirmwareUpdateDecisionTests
{
    private static readonly UpdateVerdict NoHashVerdict =
        new(false, UpdateVerdictReason.BinaryHash);

    private static readonly UpdateVerdict HashSaysNewer =
        new(true, UpdateVerdictReason.BinaryHash);

    private static readonly UpdateVerdict NothingToCompare = UpdateVerdict.Unknown;

    private static FirmwareUpdateReport Decide(
        string? installed, string? published, string? bundled,
        UpdateVerdict? hash = null, bool networkFailed = false,
        FirmwareFamily? family = null) =>
        FirmwareUpdateDecision.Decide(
            family ?? FirmwareFamily.Aura, installed, published, bundled,
            hash ?? NoHashVerdict, networkFailed);

    // MARK: - Lo publicado contra lo instalado

    [Fact]
    public void ConLoMasNuevoInstaladoEstaAlDia()
    {
        FirmwareUpdateReport report = Decide("v0.4.6-beta", "v0.4.6-beta", "v0.4.6-beta");

        Assert.Equal(FirmwareUpdateOutcome.UpToDate, report.Outcome);
        Assert.False(report.CanInstallNow);
        Assert.Contains("v0.4.6-beta", report.Message);
    }

    [Fact]
    public void UnIPodMasNuevoQueLoPublicadoNoEsUnaActualizacion()
    {
        // Pasa con una beta instalada a mano. Ofrecer "actualizar" acá sería
        // ofrecer volver atrás.
        FirmwareUpdateReport report = Decide("v0.5.0-beta", "v0.4.6-beta", "v0.4.6-beta");

        Assert.Equal(FirmwareUpdateOutcome.UpToDate, report.Outcome);
        Assert.False(report.CanInstallNow);
    }

    [Fact]
    public void ConElPinMasNuevoQueElIPodSeOfreceInstalar()
    {
        FirmwareUpdateReport report = Decide("v0.4.4-beta", "v0.4.6-beta", "v0.4.6-beta");

        Assert.Equal(FirmwareUpdateOutcome.UpdateAvailable, report.Outcome);
        Assert.True(report.CanInstallNow);
        Assert.Contains("v0.4.6-beta", report.Message);
    }

    // MARK: - Lo publicado contra lo que Studio TRAE

    [Fact]
    public void UnReleaseMasNuevoQueElPinSeAvisaPeroNoSeOfrece()
    {
        // Studio instala lo que hay en Vendor\firmware-dist\: no descarga
        // Releases. Ofrecer el botón sería ofrecer algo que no puede cumplir.
        FirmwareUpdateReport report = Decide("v0.4.6-beta", "v0.5.0-beta", "v0.4.6-beta");

        Assert.Equal(FirmwareUpdateOutcome.NewerThanBundled, report.Outcome);
        Assert.False(report.CanInstallNow);
        Assert.Contains("v0.5.0-beta", report.Message);
        Assert.Contains("Aura Studio", report.Message);
    }

    [Fact]
    public void ConElPinEnElMedioSeDicenLasDosCosas()
    {
        // El iPod tiene la vieja, Studio trae una intermedia y hay una más nueva
        // publicada: se puede instalar YA la intermedia, y se dice que existe la
        // otra.
        FirmwareUpdateReport report = Decide("v0.4.0-beta", "v0.5.0-beta", "v0.4.6-beta");

        Assert.Equal(FirmwareUpdateOutcome.UpdateAvailable, report.Outcome);
        Assert.True(report.CanInstallNow);
        Assert.Contains("v0.4.6-beta", report.Message);
        Assert.Contains("v0.5.0-beta", report.Message);
    }

    // MARK: - Sin red

    [Fact]
    public void SinRedNoSeDiceQueEstaAlDia()
    {
        FirmwareUpdateReport report = Decide(
            "v0.4.6-beta", published: null, bundled: "v0.4.6-beta", networkFailed: true);

        Assert.Equal(FirmwareUpdateOutcome.Unknown, report.Outcome);
        Assert.False(report.CanInstallNow);
        Assert.Contains("No se pudo consultar GitHub", report.Message);
    }

    [Fact]
    public void SinRedPeroConElBinarioMasViejoSiSeOfrece()
    {
        // El respaldo por hash es una conclusión de verdad: el iPod tiene algo
        // distinto de lo que Studio trae, y Studio lo tiene para instalar.
        FirmwareUpdateReport report = Decide(
            installed: null, published: null, bundled: "v0.4.6-beta",
            hash: HashSaysNewer, networkFailed: true);

        Assert.Equal(FirmwareUpdateOutcome.UpdateAvailable, report.Outcome);
        Assert.True(report.CanInstallNow);
    }

    [Fact]
    public void SinRedYConElBinarioIgualSeDiceExactamenteEso()
    {
        FirmwareUpdateReport report = Decide(
            installed: null, published: null, bundled: "v0.4.6-beta", networkFailed: true);

        Assert.Equal(FirmwareUpdateOutcome.Unknown, report.Outcome);
        Assert.Contains("No se pudo consultar GitHub", report.Message);
        Assert.Contains("coincide", report.Message);
    }

    // MARK: - Sin poder leer la versión del iPod

    [Fact]
    public void SinVersionEnElIPodDecideElHash()
    {
        FirmwareUpdateReport report = Decide(
            installed: null, published: "v0.5.0-beta", bundled: "v0.4.6-beta", hash: HashSaysNewer);

        Assert.Equal(FirmwareUpdateOutcome.UpdateAvailable, report.Outcome);
        Assert.Contains("v0.4.6-beta", report.Message);
        Assert.Contains("v0.5.0-beta", report.Message);
    }

    [Fact]
    public void SinVersionYConElBinarioIgualPeroReleaseMasNuevoSeAvisa()
    {
        FirmwareUpdateReport report = Decide(
            installed: null, published: "v0.5.0-beta", bundled: "v0.4.6-beta");

        Assert.Equal(FirmwareUpdateOutcome.NewerThanBundled, report.Outcome);
        Assert.False(report.CanInstallNow);
    }

    [Fact]
    public void UnTagIlegibleNoRompeNiConcluyeDeMas()
    {
        FirmwareUpdateReport report = Decide("no-es-una-version", "v0.5.0-beta", "v0.4.6-beta");

        // No se puede comparar por versión: manda el respaldo, que acá no
        // encontró nada, y el Release es más nuevo que el pin.
        Assert.Equal(FirmwareUpdateOutcome.NewerThanBundled, report.Outcome);
        Assert.False(report.CanInstallNow);
    }

    // MARK: - Familia (ST-046)

    [Fact]
    public void UnaFamiliaSinRepositorioNoOfreceNada()
    {
        // Nunca se compara Metro contra Aura: sin repo no hay a quién preguntar
        // ni binario propio con qué comparar.
        FirmwareUpdateReport report = Decide(
            "v1.0.0", "v2.0.0", "v2.0.0", hash: HashSaysNewer, family: FirmwareFamily.Unknown("rockbox"));

        Assert.Equal(FirmwareUpdateOutcome.Unknown, report.Outcome);
        Assert.False(report.CanInstallNow);
    }

    [Fact]
    public void CadaFamiliaSeNombraPorSuNombre()
    {
        FirmwareUpdateReport report = Decide(
            "v0.7.0", "v0.7.4", "v0.7.4", family: FirmwareFamily.Metro);

        Assert.Contains(FirmwareFamily.Metro.DisplayName, report.Message);
        Assert.DoesNotContain(FirmwareFamily.Aura.DisplayName, report.Message);
    }

    // MARK: - Árbol incompleto

    [Fact]
    public void UnArbolIncompletoSeArreglaReinstalando()
    {
        FirmwareUpdateReport report = Decide(
            "v0.4.6-beta", "v0.4.6-beta", "v0.4.6-beta",
            hash: new UpdateVerdict(true, UpdateVerdictReason.InstalledBinaryMissing));

        Assert.Equal(FirmwareUpdateOutcome.UpdateAvailable, report.Outcome);
        Assert.Contains("incompleto", report.Message);
    }

    // MARK: - Sin nada que decir

    [Fact]
    public void SinNadaConQueCompararNoSeConcluye()
    {
        FirmwareUpdateReport report = Decide(
            installed: null, published: null, bundled: null, hash: NothingToCompare);

        Assert.Equal(FirmwareUpdateOutcome.Unknown, report.Outcome);
        Assert.False(report.CanInstallNow);
    }

    [Fact]
    public void LasTresVersionesViajanEnElInforme()
    {
        // La pantalla las necesita para poder decir cuál es cuál sin volver a
        // decidir nada.
        FirmwareUpdateReport report = Decide("v0.4.0-beta", "v0.5.0-beta", "v0.4.6-beta");

        Assert.Equal("v0.4.0-beta", report.InstalledTag);
        Assert.Equal("v0.5.0-beta", report.PublishedTag);
        Assert.Equal("v0.4.6-beta", report.BundledTag);
    }
}
