using AuraStudio.Core.Library;
using Microsoft.UI.Dispatching;

namespace AuraStudio.App.Services;

/// <summary>
/// El temporizador y el hilo de fondo que necesita <see cref="CatalogPersister"/>
/// (ST-204), atados a la cola de despacho de la app.
///
/// <para>Existe aparte para que la lógica de coalescencia viva en Core y se
/// pueda probar sin esperar medio segundo de reloj real, y para que Core no
/// dependa de WinUI.</para>
///
/// <para>Sin cola de despacho —una prueba, el arnés— el temporizador no existe:
/// lo programado corre <b>al instante y en el mismo hilo</b>. Es degradar, no
/// romper: el guardado sigue ocurriendo, sin coalescer.</para>
/// </summary>
public sealed class DispatcherPersisterHost(DispatcherQueue? dispatcher) : ICatalogPersisterHost
{
    private readonly DispatcherQueueTimer? _timer = dispatcher?.CreateTimer();

    public void ScheduleAfter(TimeSpan delay, Action work)
    {
        if (_timer is null)
        {
            work();
            return;
        }

        // Reiniciarlo en cada pedido es la coalescencia: mientras sigan llegando
        // cambios, el guardado no sale.
        _timer.Stop();
        _timer.Interval = delay;
        _timer.IsRepeating = false;

        _timer.Tick -= OnTick;
        _pending = work;
        _timer.Tick += OnTick;

        _timer.Start();
    }

    private Action? _pending;

    private void OnTick(DispatcherQueueTimer sender, object args)
    {
        Action? work = _pending;
        _pending = null;
        work?.Invoke();
    }

    public void CancelScheduled()
    {
        _timer?.Stop();
        _pending = null;
    }

    public void RunInBackground(Action work)
    {
        if (dispatcher is null)
        {
            work();
            return;
        }

        _ = Task.Run(work);
    }
}
