using AuraStudio.Core;

namespace AuraStudio.App.Services;

/// <summary>
/// De dónde salen los artefactos del firmware para la familia elegida.
///
/// Hoy siempre del directorio `artifacts/` junto al ejecutable, poblado por
/// `scripts/FirmwareFetch.ps1` desde el Release fijado en `FIRMWARE_VERSION`
/// (contrato §A/§E). El contrato v17 (ST-077) hace que macOS baje además el
/// Release **más nuevo** y lo instale desde una caché; en Windows eso llega en
/// la Fase 6, junto con el almacén de credenciales que hace falta para los
/// repositorios privados. Cuando llegue, solo cambia esta clase: todo lo demás
/// consume <see cref="FirmwareArtifacts"/> sin saber de dónde vino, que es
/// exactamente el punto.
/// </summary>
public interface IFirmwareArtifactsProvider
{
    /// <summary>Familia que se instalaría hoy. Aura por omisión.</summary>
    FirmwareFamily Family { get; set; }

    FirmwareArtifacts Current();
    FirmwareArtifacts For(FirmwareFamily family);

    /// <summary>
    /// Familias que de verdad se pueden instalar ahora mismo: las que tienen sus
    /// archivos en `artifacts/` y pasan la verificación. Es lo que se le ofrece
    /// al usuario — nunca una lista de familias que después no se pueden
    /// instalar.
    /// </summary>
    IReadOnlyList<FirmwareFamily> AvailableFamilies();
}

public sealed class FirmwareArtifactsProvider : IFirmwareArtifactsProvider
{
    public FirmwareFamily Family { get; set; } = FirmwareFamily.Aura;

    public FirmwareArtifacts Current() => For(Family);

    public FirmwareArtifacts For(FirmwareFamily family)
        => FirmwareArtifacts.Load(FirmwareArtifacts.DirectoryFor(AppContext.BaseDirectory, family), family);

    public IReadOnlyList<FirmwareFamily> AvailableFamilies()
        => FirmwareFamily.Installable
            .Where(family => FirmwareArtifactVerifier
                .Verify(For(family), ArtifactScope.FirmwareTree).IsValid)
            .ToList();
}
