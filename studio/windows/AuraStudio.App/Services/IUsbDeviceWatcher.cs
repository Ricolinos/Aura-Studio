using AuraStudio.Core;

namespace AuraStudio.App.Services;

/// <summary>
/// Interfaz para monitorear cambios de dispositivos USB (iPods).
/// Implementación Windows usa WM_DEVICECHANGE; macOS usaría IOKit/DiskArbitration.
/// </summary>
public interface IUsbDeviceWatcher
{
    event EventHandler? DevicesChanged;

    /// <summary>
    /// Resultado bruto de la última identificación. En NotFound/Ambiguous,
    /// <see cref="GetConnectedIPods"/> devuelve lista vacía (la UI nunca
    /// muestra candidatos ambiguos como seleccionables — regla de seguridad).
    /// </summary>
    DiskIdentificationResult LastIdentification { get; }

    /// <summary>
    /// `false` hasta que corra el primer sondeo. Sirve para distinguir "todavía
    /// no miré" de "miré y no hay nada" — sin eso, la app arranca afirmando que
    /// no hay iPod antes de haber buscado.
    /// </summary>
    bool HasScanned { get; }

    IReadOnlyList<IPodDiskInfo> GetConnectedIPods();

    void OnDeviceChange(bool deviceArrived);

    /// <summary>
    /// Sondeo fuera del hilo de UI y con presupuesto de tiempo. **Es la vía que
    /// debe usar la interfaz**: la enumeración de WMI puede bloquearse en código
    /// nativo si hay un disco USB en mal estado, y nada de eso puede ocurrir en
    /// el hilo de UI ni en el camino de arranque.
    /// </summary>
    Task RefreshAsync(CancellationToken ct = default);

    /// <summary>
    /// Sondeo síncrono. Solo para los caminos que necesitan una lectura recién
    /// hecha y no pueden seguir sin ella — la re-verificación previa a una
    /// operación destructiva. Nunca desde el hilo de UI.
    /// </summary>
    void Refresh();
}
