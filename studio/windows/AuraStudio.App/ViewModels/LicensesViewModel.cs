using CommunityToolkit.Mvvm.ComponentModel;
using AuraStudio.Core;
using AuraStudio.App.Resources;

namespace AuraStudio.App.ViewModels;

/// <summary>
/// Lo que hay que declarar por CADA familia embebida (contrato §B): repositorio,
/// tag exacto, y los documentos del Release.
/// </summary>
public sealed record FamilyLicenseEntry(
    string DisplayName,
    string RepositoryUrl,
    string ReleaseTagText,
    bool TagIsKnown,
    string ModificationsText,
    string ThirdPartyText);

/// <summary>
/// Pantalla de Licencias — **restricción crítica del proyecto**, no una cortesía.
///
/// `mks5lboot`, `bootloader-ipod6g.ipod`, `rockbox.ipod` y `rockbox.zip` son
/// derivados de Rockbox (GPL v2). Aura Studio es software cerrado y los
/// distribuye embebidos como **agregación**; cumple el §3 de la GPL v2 ofreciendo
/// la fuente, y la vía para ofrecerla es esta pantalla: por cada familia
/// embebida, la URL de su repositorio, el tag exacto que trae, y el enlace a
/// `MODIFICATIONS.md` y `THIRD-PARTY-NOTICES.txt` de ese Release
/// (`CONTRATO-firmware-studio.md` §B).
///
/// <para><b>Nunca inventa un tag.</b> Si los artefactos de una familia no traen
/// `firmware-version.txt`, se dice que no se conoce, y la pantalla explica cómo
/// obtenerlo. Citar una versión equivocada sería peor que no citar ninguna: la
/// obligación es señalar la fuente EXACTA de lo que se distribuyó.</para>
///
/// <para><b>En Windows hay un binario de más.</b> `mks5lboot.exe` no viene del
/// Release (§A publica el `mks5lboot` de Unix), así que su procedencia se
/// declara aparte y con el nivel de confianza que se le pudo comprobar.</para>
/// </summary>
public sealed partial class LicensesViewModel : ViewModelBase
{
    [ObservableProperty]
    public partial IReadOnlyList<FamilyLicenseEntry> Families { get; set; }

    /// <summary>Qué se pudo acreditar del `mks5lboot.exe` que esta copia ejecutaría.</summary>
    [ObservableProperty]
    public partial string ToolProvenanceText { get; set; }

    public string Intro => AppStrings.LicensesIntro;
    public string ToolHeading => AppStrings.LicensesToolHeading;

    public LicensesViewModel()
    {
        var entries = new List<FamilyLicenseEntry>();
        var provenanceLines = new List<string>();

        foreach (FirmwareFamily family in FirmwareFamily.Installable)
        {
            string directory = FirmwareArtifacts.DirectoryFor(AppContext.BaseDirectory, family);
            FirmwareArtifacts artifacts = FirmwareArtifacts.Load(directory, family);

            entries.Add(new FamilyLicenseEntry(
                DisplayName: family.DisplayName,
                RepositoryUrl: family.ReleaseRepository is { Length: > 0 } repo
                    ? $"https://github.com/{repo}"
                    : AppStrings.NotAvailable,
                ReleaseTagText: artifacts.ReleaseTag ?? AppStrings.LicensesUnknownTag,
                TagIsKnown: artifacts.IsRelease,
                ModificationsText: artifacts.Modifications is null
                    ? AppStrings.LicensesDocumentMissing("MODIFICATIONS.md")
                    : AppStrings.LicensesDocumentPresent("MODIFICATIONS.md"),
                ThirdPartyText: artifacts.ThirdPartyNotices is null
                    ? AppStrings.LicensesDocumentMissing("THIRD-PARTY-NOTICES.txt")
                    : AppStrings.LicensesDocumentPresent("THIRD-PARTY-NOTICES.txt")));

            // Solo tiene sentido informar de la herramienta de la familia cuyo
            // directorio la trae; hoy es una sola, pero se recorre igual.
            if (!File.Exists(artifacts.Mks5lboot)) continue;

            ArtifactVerificationResult verification =
                FirmwareArtifactVerifier.Verify(artifacts, ArtifactScope.Flashing);

            provenanceLines.Add(verification.Provenance switch
            {
                ToolProvenance.ReleaseChecksums =>
                    AppStrings.LicensesToolFromRelease(verification.ToolOriginTag ?? AppStrings.LicensesUnknownTag),
                ToolProvenance.LocalPin =>
                    AppStrings.LicensesToolLocalPin(verification.ToolOriginTag ?? AppStrings.LicensesUnknownTag),
                _ => AppStrings.LicensesToolUnverified
            });
        }

        Families = entries;
        ToolProvenanceText = provenanceLines.Count > 0
            ? string.Join("\n", provenanceLines.Distinct())
            : AppStrings.LicensesToolMissing;
    }
}
