using AuraStudio.Core;

namespace AuraStudio.App.Services;

/// <summary>
/// En qué situación está la detección del iPod. Es lo que la UI pregunta:
/// nunca hay que reconstruirlo mirando listas vacías ni mensajes de texto.
/// </summary>
public enum DeviceSessionState
{
    /// <summary>Todavía no corrió la primera detección.</summary>
    Detecting,

    /// <summary>Ningún disco califica como iPod.</summary>
    NotConnected,

    /// <summary>Exactamente un iPod identificado, con su volumen leído.</summary>
    Connected,

    /// <summary>
    /// Dos o más discos califican. **No hay dispositivo**: la app se detiene y
    /// lo dice — nunca elige "el más probable" ni ofrece los candidatos como
    /// seleccionables (regla de seguridad del repo).
    /// </summary>
    Ambiguous
}

public sealed class DeviceSessionChangedEventArgs(DeviceSessionState state, IPodDiskInfo? device) : EventArgs
{
    public DeviceSessionState State { get; } = state;
    public IPodDiskInfo? Device { get; } = device;
}

/// <summary>
/// Estado de sesión compartido por todas las páginas: qué iPod hay conectado
/// ahora mismo, en qué estado quedó la identificación y qué se puede hacer con
/// él. Es el equivalente del `IPodMonitor` que macOS instancia una sola vez en
/// `ContentView` y le pasa a todas las secciones.
///
/// Antes de esto cada ViewModel refrescaba por su cuenta contra
/// <see cref="IUsbDeviceWatcher"/> y se quedaba con su propia copia del
/// dispositivo: dos pantallas podían discrepar sobre qué iPod está conectado.
/// Acá hay una sola respuesta y un solo evento.
///
/// <para><b>Hilos:</b> <see cref="Changed"/> se dispara en el hilo que llamó a
/// <see cref="Refresh"/>/<see cref="OnDeviceChange"/>. Quien lo dispara desde
/// un mensaje de ventana (WM_DEVICECHANGE) ya lo encola en el hilo de UI, así
/// que los ViewModels pueden tocar propiedades observables sin marshalling
/// propio.</para>
/// </summary>
public interface IDeviceSessionService
{
    DeviceSessionState State { get; }

    /// <summary>El iPod conectado, o `null` en cualquier estado que no sea <see cref="DeviceSessionState.Connected"/>.</summary>
    IPodDiskInfo? Device { get; }

    /// <summary>Resultado bruto de la última identificación, para quien necesite el detalle.</summary>
    DiskIdentificationResult Identification { get; }

    /// <summary>Mensaje de estado listo para mostrar, en español de México.</summary>
    string StatusMessage { get; }

    /// <summary>
    /// La biblioteca se bloquea cuando hay un iPod conectado cuyo firmware NO
    /// habla el contrato de Aura: sincronizar contra el firmware original de
    /// Apple o un Rockbox ajeno no haría nada útil. **Sin dispositivo la
    /// biblioteca queda abierta a propósito** — armarla offline es un caso de
    /// uso real (mismo criterio que `ContentView.libraryLocked` en macOS).
    /// </summary>
    bool LibraryLocked { get; }

    event EventHandler<DeviceSessionChangedEventArgs>? Changed;

    /// <summary>
    /// Dispara el primer sondeo, una sola vez. Lo llama la ventana **cuando ya
    /// está en pantalla**: consultar los discos durante la construcción llegó a
    /// dejar la app sin ventana para siempre si había un disco USB en mal estado.
    /// </summary>
    void StartInitialScan();

    /// <summary>Vuelve a identificar. Inofensivo: solo lee.</summary>
    void Refresh();

    /// <summary>Lo llama la ventana al recibir WM_DEVICECHANGE.</summary>
    void OnDeviceChange(bool deviceArrived);
}
