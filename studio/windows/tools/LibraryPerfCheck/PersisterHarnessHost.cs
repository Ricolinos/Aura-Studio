using AuraStudio.Core.Library;

namespace AuraStudio.Tools.LibraryPerfCheck;

/// <summary>
/// El anfitrión del persistidor (ST-204) para el arnés: acá no hay ventana, así
/// que no hay cola de despacho ni temporizador que salte solo. El temporizador
/// lo hace saltar la medición cuando quiere (<see cref="Fire"/>), y el "segundo
/// plano" es un hilo del grupo de verdad —del que se espera— para que lo que se
/// cronometra sea el trabajo completo y se pueda comprobar que <b>no corrió en
/// el hilo que pidió el guardado</b>.
/// </summary>
internal sealed class PersisterHarnessHost : ICatalogPersisterHost
{
    private Action? _scheduled;

    /// <summary>Cuántas veces se armó el temporizador (los pedidos).</summary>
    public int ScheduleCount { get; private set; }

    /// <summary>En qué hilo corrió la última escritura.</summary>
    public int LastWriteThreadId { get; private set; }

    public void ScheduleAfter(TimeSpan delay, Action work)
    {
        ScheduleCount++;
        _scheduled = work;
    }

    public void CancelScheduled() => _scheduled = null;

    public void RunInBackground(Action work)
    {
        // Se espera a propósito: el arnés mide el costo total del guardado, no
        // cuánto tarda en delegarlo. Lo que se comprueba es el HILO, no que
        // vuelva antes.
        //
        // Y se espera con un evento, NO con Task.Wait/GetResult: esperar la
        // tarea permite que el planificador la ejecute EN EL HILO QUE ESPERA si
        // todavía no arrancó (inlining), y entonces la comprobación del hilo
        // diría "mismo hilo" por culpa de la medición y no de lo medido.
        using var done = new ManualResetEventSlim(false);

        Task.Run(() =>
        {
            LastWriteThreadId = Environment.CurrentManagedThreadId;

            try { work(); }
            finally { done.Set(); }
        });

        done.Wait();
    }

    /// <summary>Hace saltar el temporizador, si hay algo armado.</summary>
    public void Fire()
    {
        Action? work = _scheduled;
        _scheduled = null;
        work?.Invoke();
    }
}
