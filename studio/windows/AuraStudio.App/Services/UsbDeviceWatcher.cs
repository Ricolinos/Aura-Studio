using AuraStudio.Core;
using AuraStudio.App.Platform;

namespace AuraStudio.App.Services;

/// <summary>
/// Monitor real de iPods en Windows: WM_DEVICECHANGE notifica el cambio,
/// este watcher enumera discos USB por WMI, aplica la identificación pura
/// (IPodDiskIdentifier) y enriquece con datos del volumen montado.
///
/// <para><b>El constructor no consulta nada.</b> Lo hacía, y eso colgaba la app
/// entera: al resolverse por DI desde el constructor de la ventana, la
/// enumeración de WMI corría en el hilo de UI **antes** de `Activate()`, así que
/// con un disco USB en mal estado —el iPod a medio morir en el passthrough— la
/// ventana se creaba con la geometría correcta y no aparecía nunca. Un
/// constructor que resuelve DI tiene que ser trivial; el primer sondeo lo
/// dispara la ventana cuando ya está en pantalla, con
/// <see cref="RefreshAsync"/>.</para>
/// </summary>
public sealed class UsbDeviceWatcher : IUsbDeviceWatcher
{
    public event EventHandler? DevicesChanged;

    private readonly List<IPodDiskInfo> _devices = [];
    private readonly object _lock = new();
    private DiskIdentificationResult _lastIdentification = new DiskIdentificationResult.NotFound();

    /// <summary>
    /// Tope duro por si la consulta se atora igual pese al timeout de WMI. Si se
    /// agota, el sondeo se abandona: el hilo del pool queda perdido, pero la app
    /// sigue viva y respondiendo, que es lo que importa.
    /// </summary>
    private static readonly TimeSpan ScanBudget = TimeSpan.FromSeconds(12);

    /// <summary>Ya corrió al menos un sondeo — hasta entonces el estado es "buscando".</summary>
    public bool HasScanned { get; private set; }

    public DiskIdentificationResult LastIdentification
    {
        get { lock (_lock) return _lastIdentification; }
    }

    public IReadOnlyList<IPodDiskInfo> GetConnectedIPods()
    {
        lock (_lock) return _devices.ToList();
    }

    /// <summary>
    /// Sondeo fuera del hilo de UI y con presupuesto de tiempo. Es la única vía
    /// que debe usarse desde la interfaz.
    /// </summary>
    public async Task RefreshAsync(CancellationToken ct = default)
    {
        try
        {
            Task scan = Task.Run(Scan, ct);
            Task finished = await Task.WhenAny(scan, Task.Delay(ScanBudget, ct));

            if (finished != scan)
            {
                // WMI no volvió a tiempo. Se reporta "no encontrado" en vez de
                // esperar: un disco que no responde no puede congelar la app.
                lock (_lock)
                {
                    _devices.Clear();
                    _lastIdentification = new DiskIdentificationResult.NotFound();
                }
            }
            else
            {
                await scan;   // propaga una excepción real del sondeo
            }
        }
        catch (OperationCanceledException)
        {
            return;
        }
        catch (Exception ex) when (ex is not OutOfMemoryException)
        {
            lock (_lock)
            {
                _devices.Clear();
                _lastIdentification = new DiskIdentificationResult.NotFound();
            }
        }

        HasScanned = true;
        DevicesChanged?.Invoke(this, EventArgs.Empty);
    }

    /// <summary>
    /// Refresco síncrono. Se conserva para los caminos que **necesitan** una
    /// lectura recién hecha y no pueden seguir sin ella — sobre todo
    /// <see cref="IDeviceSafetyValidator"/>, que re-verifica el disco justo antes
    /// de una operación destructiva y jamás puede usar un valor cacheado. No se
    /// llama desde el hilo de UI.
    /// </summary>
    public void Refresh()
    {
        Scan();
        HasScanned = true;
        DevicesChanged?.Invoke(this, EventArgs.Empty);
    }

    public void OnDeviceChange(bool deviceArrived) => _ = RefreshAsync();

    private void Scan()
    {
        var candidates = WmiDiskEnumerator.EnumerateUsbDisks();
        var result = IPodDiskIdentifier.Identify(candidates.Select(c => c.Candidate).ToList());

        IPodDiskInfo? found = null;
        if (result is DiskIdentificationResult.Found foundResult)
        {
            var match = candidates.FirstOrDefault(c => c.Candidate == foundResult.Candidate);
            if (match != default) found = VolumeProbe.Build(match);
        }

        lock (_lock)
        {
            _devices.Clear();
            _lastIdentification = result;
            // NotFound/Ambiguous → la lista queda vacía: la UI nunca ve
            // candidatos ambiguos como seleccionables.
            if (found is not null) _devices.Add(found);
        }
    }
}
