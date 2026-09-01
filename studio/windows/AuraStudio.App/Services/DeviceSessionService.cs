using AuraStudio.Core;
using AuraStudio.App.Resources;

namespace AuraStudio.App.Services;

/// <summary>
/// <see cref="IDeviceSessionService"/> sobre <see cref="IUsbDeviceWatcher"/>.
/// Singleton: es el único dueño del estado del dispositivo en la app.
///
/// No enumera discos ni lee volúmenes — de eso se encarga el watcher (WMI +
/// `IPodDiskIdentifier` + `VolumeProbe`). Acá se traduce ese resultado a la
/// situación que la UI necesita, y se conserva **sin fusionar** los tres
/// hechos del contrato (ST-016): qué archivos hay, quién atiende el USB y qué
/// familia declara el firmware siguen viviendo en <see cref="IPodDiskInfo"/>.
///
/// <para><b>El constructor no dispara ningún sondeo.</b> Arranca en
/// <see cref="DeviceSessionState.Detecting"/> y el primer sondeo lo pide la
/// ventana con <see cref="StartInitialScan"/> **después** de estar en pantalla.
/// Consultar WMI durante la resolución de DI llegó a dejar la app sin ventana
/// para siempre con un disco USB en mal estado.</para>
/// </summary>
public sealed class DeviceSessionService : IDeviceSessionService
{
    private readonly IUsbDeviceWatcher _watcher;
    private int _initialScanStarted;

    public event EventHandler<DeviceSessionChangedEventArgs>? Changed;

    public DeviceSessionState State { get; private set; } = DeviceSessionState.Detecting;
    public IPodDiskInfo? Device { get; private set; }
    public DiskIdentificationResult Identification { get; private set; } = new DiskIdentificationResult.NotFound();
    public string StatusMessage { get; private set; } = AppStrings.DeviceDetecting;

    public bool LibraryLocked => Device is { } device && !device.SupportsAuraContract;

    public DeviceSessionService(IUsbDeviceWatcher watcher)
    {
        _watcher = watcher;
        _watcher.DevicesChanged += (_, _) => ReevaluateOnUiThread();
        // Nada más: ni sondeo, ni WMI, ni disco. Ver el comentario de la clase.
    }

    /// <summary>
    /// **El sondeo termina en un hilo del grupo, y desde ahí NO se puede tocar
    /// nada que esté enlazado a la interfaz.**
    ///
    /// <para>Este es el crash que la app tenía al instalar Metro después de
    /// Aura: <c>Scan()</c> corre en <c>Task.Run</c> y dispara
    /// <c>DevicesChanged</c> ahí mismo; desde ahí se actualizaban propiedades
    /// observables y WinUI reventaba dentro de <c>combase.dll</c>
    /// (0xC000027B / E_FAIL / E_POINTER) cerrando la app <b>sin ningún
    /// mensaje</b>. Aparecía justo en ese flujo porque el cambio de familia hace
    /// que el iPod se re-enumere varias veces por USB —DFU, bootloader, modo
    /// disco—, y cada una es otro sondeo en segundo plano.</para>
    ///
    /// <para>Por eso todo el <see cref="Reevaluate"/> —no solo el evento— vuelve
    /// al hilo de la interfaz antes de mutar nada.</para>
    /// </summary>
    private void ReevaluateOnUiThread()
    {
        Microsoft.UI.Dispatching.DispatcherQueue? dispatcher = App.UiDispatcher;

        if (dispatcher is not null && !dispatcher.HasThreadAccess)
        {
            dispatcher.TryEnqueue(Reevaluate);
            return;
        }

        Reevaluate();
    }

    /// <summary>
    /// Primer sondeo, idempotente. Lo llama la ventana una vez activa; si se
    /// llamara dos veces (por una reactivación), la segunda no hace nada.
    /// </summary>
    public void StartInitialScan()
    {
        if (Interlocked.Exchange(ref _initialScanStarted, 1) != 0) return;
        _ = _watcher.RefreshAsync();
    }

    public void Refresh() => _ = _watcher.RefreshAsync();   // dispara DevicesChanged → Reevaluate

    public void OnDeviceChange(bool deviceArrived) => _watcher.OnDeviceChange(deviceArrived);

    private void Reevaluate()
    {
        // Si esto salta, algún camino nuevo volvió a llamar desde otro hilo y
        // hay que hacerlo pasar por ReevaluateOnUiThread. Falla ruidosamente en
        // depuración en vez de matar la app en producción, que es lo que hacía
        // antes.
        System.Diagnostics.Debug.Assert(
            App.UiDispatcher is null || App.UiDispatcher.HasThreadAccess,
            "Reevaluate() fuera del hilo de interfaz: actualizar algo enlazado desde aquí cierra la app sin aviso.");

        // Antes del primer sondeo no se afirma nada: "no hay iPod" y "todavía no
        // busqué" son cosas distintas y el usuario merece ver la correcta.
        if (!_watcher.HasScanned)
        {
            State = DeviceSessionState.Detecting;
            StatusMessage = AppStrings.DeviceDetecting;
            Changed?.Invoke(this, new DeviceSessionChangedEventArgs(State, null));
            return;
        }

        Identification = _watcher.LastIdentification;

        switch (Identification)
        {
            case DiskIdentificationResult.Found:
                // El watcher solo publica el volumen del único `Found`.
                Device = _watcher.GetConnectedIPods().FirstOrDefault();
                State = Device is null ? DeviceSessionState.NotConnected : DeviceSessionState.Connected;
                StatusMessage = Device is null
                    ? AppStrings.DeviceNotConnected
                    : AppStrings.DeviceConnected(Device.DisplayName);
                break;

            case DiskIdentificationResult.Ambiguous ambiguous:
                Device = null;
                State = DeviceSessionState.Ambiguous;
                StatusMessage = AppStrings.DeviceAmbiguous(ambiguous.Candidates.Count);
                break;

            default:
                Device = null;
                State = DeviceSessionState.NotConnected;
                StatusMessage = AppStrings.DeviceNotConnected;
                break;
        }

        SyncClockIfConnected();

        Changed?.Invoke(this, new DeviceSessionChangedEventArgs(State, Device));
    }

    /// <summary>
    /// Le pone la hora al iPod al conectarlo (contrato §D.4): el aparato no
    /// tiene forma de saberla solo, y configurarla a mano en una rueda de clic
    /// es de lo más molesto que tiene.
    ///
    /// <para>Va en segundo plano y sin avisar de nada: es una cortesía, no un
    /// paso del que dependa nada. Un iPod donde el firmware nunca arrancó no
    /// tiene <c>aura.cfg</c> y simplemente no se toca.</para>
    /// </summary>
    private void SyncClockIfConnected()
    {
        if (Device is not { SupportsAuraContract: true, VolumePath.Length: > 0 } device) return;

        string volume = device.VolumePath;
        _ = Task.Run(() => ClockSyncWriter.WriteToDisk(volume));
    }
}
