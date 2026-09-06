using System.Diagnostics;
using AuraStudio.Core.Library;

namespace AuraStudio.Tools.LibraryPerfCheck;

/// <summary>
/// 2.º addendum de ST-200 (pedido del coordinador): <c>Thread.Sleep(N)</c> en
/// Windows no duerme N ms -- duerme lo que permita la resolución del
/// temporizador del sistema. Medido en la corrida de W3: <c>Sleep(3)</c>
/// tardaba ~18-19 ms de verdad (228 150 ms / 12 000 llamadas), así que
/// "3 ms/llamada" en la salida del arnés era una etiqueta que mentía.
///
/// <para>Acá se espera con <see cref="Stopwatch"/> + <see cref="SpinWait"/>
/// hasta cumplir los milisegundos pedidos, en vez de <c>Thread.Sleep</c>: un
/// spin-wait no depende de la resolución del temporizador del sistema
/// operativo, así que "3" en el arnés vuelve a significar 3. Se imprime
/// además el retardo efectivo medido por llamada, para no volver a
/// confundirse si algo lo desvía otra vez.</para>
/// </summary>
internal static class SlowDiskReplica
{
    public static long Run(string what, IReadOnlyList<LibraryItem> items, int delayMs, Func<LibraryItem, bool> perItem)
    {
        var watch = Stopwatch.StartNew();
        double delaySumMs = 0;

        foreach (LibraryItem item in items)
        {
            delaySumMs += PreciseWaitMs(delayMs);
            _ = perItem(item);
        }

        watch.Stop();

        double effectiveMsPerCall = items.Count == 0 ? 0 : delaySumMs / items.Count;
        Console.WriteLine(
            $"{watch.ElapsedMilliseconds,6} ms  {what} ({items.Count} ítems x {delayMs} ms pedidos, {effectiveMsPerCall:0.00} ms/llamada efectivos medidos)");

        return watch.ElapsedMilliseconds;
    }

    /// <summary>
    /// Espera al menos <paramref name="milliseconds"/>, con la precisión de
    /// <see cref="Stopwatch"/> (microsegundos), no la de <c>Thread.Sleep</c>
    /// (la resolución del temporizador del sistema, ~15,6 ms por omisión en
    /// Windows).
    ///
    /// <para><b>A propósito NO usa <see cref="System.Threading.SpinWait"/>:</b>
    /// se probó primero con esa struct y el retardo efectivo medido seguía
    /// saliendo en ~17-18 ms, igual que <c>Thread.Sleep</c> -- `SpinWait`
    /// está pensada para esperar un lock, y tras un puñado de vueltas
    /// escala sola a `Thread.Yield()`/`Thread.Sleep(0)`/`Thread.Sleep(1)`
    /// para no acaparar el núcleo, reintroduciendo la misma resolución del
    /// temporizador que esto existe para evitar. Un giro puro, sin ceder el
    /// hilo, sí ocupa un núcleo entero mientras espera -- aceptable acá
    /// porque son unos pocos milisegundos por ítem, no una espera larga.</para>
    /// </summary>
    private static double PreciseWaitMs(int milliseconds)
    {
        var watch = Stopwatch.StartNew();
        while (watch.Elapsed.TotalMilliseconds < milliseconds) { }
        return watch.Elapsed.TotalMilliseconds;
    }
}
