namespace AuraStudio.App.Services;

/// <summary>
/// Operaciones no destructivas sobre el volumen del iPod (abrir, expulsar).
///
/// Existe como interfaz para que los ViewModels no llamen a `Platform/`
/// directamente: la regla de capas dice que las APIs de Windows viven en
/// `Platform/` y que todo servicio con dependencia externa se consume detrás
/// de una interfaz, para poder probar el ViewModel sin un volumen real.
/// </summary>
public interface IVolumeService
{
    bool OpenInExplorer(string volumePath);

    /// <summary>
    /// Pide la expulsión lógica. `true` significa que Windows aceptó la
    /// solicitud, no que el disco ya se pueda desconectar.
    /// </summary>
    bool Eject(string volumePath);
}
