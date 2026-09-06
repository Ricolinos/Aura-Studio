using System.Diagnostics;
using System.Runtime.InteropServices;
using Microsoft.UI.Dispatching;

namespace AuraStudio.App.Services;

/// <summary>
/// PLAN-studio-rendimiento-2.md W0: vigilante del hilo de UI, solo para
/// diagnóstico en desarrollo (<c>DEBUG</c> + variable de entorno
/// <c>AURA_WATCHDOG=1</c>). Paridad conceptual con
/// <c>MainThreadWatchdog.swift</c> de la Mac: un "corazón" late en el hilo de
/// UI cada <see cref="PollIntervalMs"/> ms (acá, redondeando viajes por el
/// <see cref="DispatcherQueue"/> en vez de una señal Unix — Windows no tiene
/// el equivalente de <c>SIGUSR2</c> hacia un hilo administrado); un hilo
/// aparte lo vigila y, si pasan más de <see cref="ThresholdMs"/> ms sin uno
/// nuevo, asume que el hilo de UI está bloqueado.
///
/// <para>La pila se captura en dos tiempos, igual que en Mac: primero se
/// suspende el hilo de UI lo mínimo posible (<see cref="NativeMethods.SuspendThread"/>
/// + <c>StackWalk64</c> sobre las direcciones nada más) y se lo reanuda de
/// inmediato; symbolizar (<c>SymFromAddr</c>, que sí puede tardar) pasa a
/// después, ya con el hilo de UI corriendo de nuevo.</para>
///
/// <para>Es deliberadamente best-effort: la captura de pila usa structs
/// nativos (<c>CONTEXT</c>, <c>STACKFRAME64</c>) copiados de <c>winnt.h</c> /
/// <c>dbghelp.h</c>, con una variante por arquitectura (x64 y ARM64 — la VM de
/// Windows del dueño resultó ser ARM64, así que esta segunda no es opcional).
/// Si algo falla — arquitectura no reconocida, el hilo ya no existe,
/// <c>dbghelp.dll</c> no puede symbolizar — se registra la duración igual y
/// se dice explícitamente que la pila no se pudo capturar, nunca se lanza.
/// Nunca corre fuera de <c>DEBUG</c> ni sin la variable de entorno: no es
/// parte de lo que ve el usuario.</para>
///
/// <para><b>4.º addendum de ST-200 (hallazgo de W7): la captura podía
/// dejar el hilo de UI suspendido para siempre.</b> <c>StackWalker</c>
/// llamaba <c>SymInitialize(..., invadeProcess: true)</c> la primera vez que
/// hacía falta, <b>con el hilo de UI ya suspendido</b>: invadir el proceso
/// enumera módulos, lo que pide el candado del cargador de Windows -- y si el
/// hilo de UI estaba bloqueado justo <i>cargando un módulo o compilando JIT</i>
/// (el caso más común de un bloqueo al arranque), lo suspendimos con ese
/// candado tomado. Nadie podía soltarlo -- interbloqueo, el hilo de UI nunca
/// vuelve. Dos cambios lo cierran: <see cref="StackWalker.InitializeSymbolsSafely"/>
/// corre una sola vez, al arrancar el vigilante, mucho antes de que exista
/// ningún hilo suspendido; y como red de seguridad (por si algo más bajo
/// <c>dbghelp.dll</c> volviera a tocar el candado), un hilo centinela aparte
/// reanuda el hilo de UI a la fuerza si la captura entera tarda más de
/// <see cref="CaptureGuardMs"/> ms, pase lo que pase adentro.</para>
/// </summary>
public static class UiThreadWatchdog
{
#if DEBUG
    private const int ThresholdMs = 250;
    private const int PollIntervalMs = 50;
    private const int MaxFrames = 64;

    /// <summary>
    /// Si la captura (contexto + desenrollado) no terminó en este tiempo
    /// desde que se suspendió el hilo de UI, el centinela lo reanuda a la
    /// fuerza. 200 ms: bastante para un desenrollado sano (que tarda
    /// microsegundos-milisegundos, medido), muy por debajo de los varios
    /// segundos que costaría dejar al usuario con la app congelada.
    /// </summary>
    private const int CaptureGuardMs = 200;

    /// <summary>Cada cuánto se anota "sigue bloqueado" mientras un bloqueo no termina.</summary>
    private const int StillHangingLogIntervalMs = 5000;

    private static long _lastHeartbeatTicks;
    private static DispatcherQueue? _dispatcher;
    private static uint _uiThreadId;
    private static bool _started;
    private static readonly object StartLock = new();
#endif

    /// <summary>
    /// Gancho para que una prueba pueda verificar "cero bloqueos > 250 ms" sin
    /// tener que capturar lo que este archivo escribe a disco. Nunca se usa
    /// fuera de pruebas.
    /// </summary>
    public static Action<int>? OnHangDetectedForTesting { get; set; }

    /// <summary>
    /// Se llama una vez al arrancar la app, desde el hilo de UI. No hace nada
    /// fuera de <c>DEBUG</c> o sin <c>AURA_WATCHDOG=1</c>.
    /// </summary>
    public static void StartIfRequested(DispatcherQueue uiDispatcher)
    {
#if DEBUG
        if (Environment.GetEnvironmentVariable("AURA_WATCHDOG") != "1") return;

        lock (StartLock)
        {
            if (_started) return;
            _started = true;
        }

        _dispatcher = uiDispatcher;
        _uiThreadId = NativeMethods.GetCurrentThreadId();
        _lastHeartbeatTicks = Environment.TickCount64;

        // Acá, y solo acá: mucho antes de que exista ningún hilo suspendido.
        // Ver el addendum de la clase para el porqué exacto.
        StackWalker.InitializeSymbolsSafely();

        BeatHeartbeat();

        var thread = new Thread(Watch) { IsBackground = true, Name = "AuraStudio.UiThreadWatchdog" };
        thread.Start();

        Log($"[UiThreadWatchdog] activo -- avisa de bloqueos del hilo de UI > {ThresholdMs} ms");
#endif
    }

#if DEBUG
    private static void BeatHeartbeat()
    {
        Volatile.Write(ref _lastHeartbeatTicks, Environment.TickCount64);

        // Autorrearme: el próximo latido se encola recién cuando este corrió,
        // así que un hilo de UI bloqueado deja de latir en vez de acumular
        // latidos atrasados en la cola.
        _dispatcher?.TryEnqueue(DispatcherQueuePriority.Normal, () =>
        {
            Thread.Sleep(PollIntervalMs);
            BeatHeartbeat();
        });
    }

    private static void Watch()
    {
        long? hangStartedTicks = null;
        long lastStillHangingLogTicks = 0;

        while (true)
        {
            Thread.Sleep(PollIntervalMs);

            long now = Environment.TickCount64;
            long sinceLastBeat = now - Volatile.Read(ref _lastHeartbeatTicks);

            if (sinceLastBeat > ThresholdMs)
            {
                if (hangStartedTicks is null)
                {
                    hangStartedTicks = now - sinceLastBeat;
                    lastStillHangingLogTicks = now;
                    StartCaptureAsync();
                }
                else if (now - lastStillHangingLogTicks >= StillHangingLogIntervalMs)
                {
                    // Un bloqueo indefinido nunca llega a "Report": sin esto
                    // no queda NADA en el log más que el "activo" inicial,
                    // que es justo lo que pasó en el hallazgo de W7. Nota de
                    // cobertura: si el propio hilo de Watch() se queda sin
                    // CPU durante el bloqueo (ver "Lo no cubierto" del
                    // addendum), este aviso puede no alcanzar a imprimirse a
                    // tiempo -- el reporte final, que usa marcas de tiempo
                    // reales y no cuántas vueltas dio este bucle, sigue
                    // siendo preciso de todos modos.
                    Log($"[UiThreadWatchdog] bloqueo en curso desde hace {now - hangStartedTicks.Value} ms");
                    lastStillHangingLogTicks = now;
                }
            }
            else if (hangStartedTicks is { } startedAt)
            {
                int durationMs = (int)(now - startedAt);
                Report(durationMs, _pendingFrames);
                _pendingFrames = null;
                hangStartedTicks = null;
            }
        }
    }

    private static CapturedFrames? _pendingFrames;
    private static long _captureGeneration;

    /// <summary>
    /// La captura corre en su <b>propio hilo</b>, nunca en el de <see cref="Watch"/>:
    /// si queda atascada (el centinela de <see cref="TryCaptureUiThreadFrames"/>
    /// no alcanza a salvarla, o algo nuevo y no previsto la cuelga de verdad),
    /// el vigilante sigue vivo y detecta el próximo bloqueo igual -- antes,
    /// una captura atascada se llevaba consigo al vigilante entero.
    ///
    /// <para>La "generación" descarta una captura vieja que termina tarde,
    /// después de que ya arrancó un bloqueo nuevo: sin esto, un resultado
    /// atrasado podría pisarle la pila al bloqueo equivocado.</para>
    /// </summary>
    private static void StartCaptureAsync()
    {
        long generation = Interlocked.Increment(ref _captureGeneration);
        _pendingFrames = null;

        var thread = new Thread(() =>
        {
            CapturedFrames? frames = TryCaptureUiThreadFrames();
            if (Interlocked.Read(ref _captureGeneration) == generation) _pendingFrames = frames;
        })
        { IsBackground = true, Name = "AuraStudio.UiThreadWatchdog.Capture" };
        thread.Start();
    }

    private static void Report(int durationMs, CapturedFrames? frames)
    {
        OnHangDetectedForTesting?.Invoke(durationMs);
        Log($"[UiThreadWatchdog] bloqueo de ~{durationMs} ms en el hilo de UI");

        if (frames is null || frames.Addresses.Count == 0)
        {
            Log("    (no se alcanzó a capturar la pila -- el bloqueo terminó antes de que se pudiera suspender el hilo, la captura tardó demasiado, o la arquitectura no está soportada)");
            return;
        }

        foreach (string line in StackSymbolizer.Symbolize(frames.Addresses)) Log("    " + line);
    }

    private sealed record CapturedFrames(IReadOnlyList<ulong> Addresses);

    /// <summary>
    /// Suspende el hilo de UI lo mínimo posible: solo lo que tarda leer su
    /// contexto y desenrollar las direcciones de retorno con
    /// <c>StackWalk64</c>. Symbolizar viene después, con el hilo ya corriendo.
    ///
    /// <para>Un hilo centinela aparte garantiza que el hilo de UI se reanuda
    /// pase lo que pase adentro, en <see cref="CaptureGuardMs"/> ms como
    /// mucho -- ver el addendum de la clase. Si la captura de verdad se
    /// queda pegada más allá de eso (no debería, ya con
    /// <see cref="StackWalker.InitializeSymbolsSafely"/> corrida de
    /// antemano), el hilo de UI ya está libre y el único costo es que esta
    /// llamada (que corre en su propio hilo, ver <see cref="StartCaptureAsync"/>)
    /// puede tardar en volver o no volver nunca -- sin llevarse la app.</para>
    /// </summary>
    private static CapturedFrames? TryCaptureUiThreadFrames()
    {
        Architecture arch = RuntimeInformation.ProcessArchitecture;
        if (arch != Architecture.X64 && arch != Architecture.Arm64)
        {
            Log($"    (captura de pila no soportada en {arch})");
            return null;
        }

        nint hThread = NativeMethods.OpenThread(
            NativeMethods.ThreadAccess.SuspendResume | NativeMethods.ThreadAccess.GetContext
            | NativeMethods.ThreadAccess.QueryInformation,
            false, _uiThreadId);

        if (hThread == 0)
        {
            Log($"    (OpenThread falló, error {Marshal.GetLastWin32Error()})");
            return null;
        }

        try
        {
            if (NativeMethods.SuspendThread(hThread) == unchecked((uint)-1))
            {
                Log($"    (SuspendThread falló, error {Marshal.GetLastWin32Error()})");
                return null;
            }

            int resumed = 0; // 0 = pendiente, 1 = ya se reanudó (por cualquiera de los dos caminos, ver ResumeOnce)

            void ResumeOnce()
            {
                if (Interlocked.Exchange(ref resumed, 1) == 0) NativeMethods.ResumeThread(hThread);
            }

            using var captureDone = new ManualResetEventSlim(false);

            var guard = new Thread(() =>
            {
                if (!captureDone.Wait(CaptureGuardMs) && Interlocked.CompareExchange(ref resumed, 1, 0) == 0)
                {
                    NativeMethods.ResumeThread(hThread);
                    Log($"    (pila no capturada: la captura tardó más de {CaptureGuardMs} ms -- se reanudó el hilo de UI a la fuerza para no colgar la app)");
                }
            })
            { IsBackground = true, Name = "AuraStudio.UiThreadWatchdog.CaptureGuard" };
            guard.Start();

            try
            {
                IReadOnlyList<ulong> addresses = arch == Architecture.X64
                    ? CaptureAmd64(hThread)
                    : CaptureArm64(hThread);

                if (addresses.Count == 0) Log("    (StackWalk64 no devolvió direcciones)");
                return new CapturedFrames(addresses);
            }
            finally
            {
                captureDone.Set();
                ResumeOnce();
            }
        }
        finally
        {
            NativeMethods.CloseHandle(hThread);
        }
    }

    private static IReadOnlyList<ulong> CaptureAmd64(nint hThread) => CaptureWith(
        hThread, NativeMethods.ContextSizeAmd64, NativeMethods.Amd64OffsetContextFlags,
        NativeMethods.ContextFullAmd64, StackWalker.WalkAmd64);

    private static IReadOnlyList<ulong> CaptureArm64(nint hThread) => CaptureWith(
        hThread, NativeMethods.ContextSizeArm64, NativeMethods.Arm64OffsetContextFlags,
        NativeMethods.ContextFullArm64, StackWalker.WalkArm64);

    /// <summary>
    /// El contexto se reserva en el heap nativo (<see cref="Marshal.AllocHGlobal"/>)
    /// y no en la pila administrada: <c>CONTEXT</c> exige alinearse a 16 bytes
    /// y un <c>ref</c> a un local no lo garantiza -- sin esto,
    /// <c>GetThreadContext</c> devuelve <c>ERROR_NOACCESS</c> en ARM64 (se
    /// probó a mano contra este mismo vigilante).
    /// </summary>
    private static IReadOnlyList<ulong> CaptureWith(
        nint hThread, int contextSize, int contextFlagsOffset, uint contextFullFlags,
        Func<nint, nint, int, IReadOnlyList<ulong>> walk)
    {
        nint context = Marshal.AllocHGlobal(contextSize);
        try
        {
            for (int i = 0; i < contextSize; i++) Marshal.WriteByte(context, i, 0);
            Marshal.WriteInt32(context, contextFlagsOffset, unchecked((int)contextFullFlags));

            if (!NativeMethods.GetThreadContext(hThread, context))
            {
                Log($"    (GetThreadContext falló, error {Marshal.GetLastWin32Error()})");
                return [];
            }

            return walk(hThread, context, MaxFrames);
        }
        finally
        {
            Marshal.FreeHGlobal(context);
        }
    }

    /// <summary>
    /// <c>print</c>/<c>Debug.WriteLine</c> no alcanzan solos: la app suele
    /// correr sin consola adjunta, y un bloqueo real puede llevarse la sesión
    /// de depuración antes de que el usuario mire la ventana de Output. Se
    /// escribe a las dos partes, y el archivo se abre en modo <i>append</i>
    /// para no perder bloqueos anteriores de la misma sesión.
    /// </summary>
    private static void Log(string message)
    {
        Debug.WriteLine(message);
        try
        {
            string dir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Aura Studio");
            Directory.CreateDirectory(dir);
            File.AppendAllText(Path.Combine(dir, "watchdog.log"), $"{DateTimeOffset.Now:O} {message}{Environment.NewLine}");
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            // Un archivo de log que no se puede escribir no puede tumbar el
            // vigilante: ya escribió a Debug.WriteLine.
        }
    }
#endif
}
