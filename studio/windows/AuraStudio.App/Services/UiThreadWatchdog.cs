using System.Diagnostics;
using System.Runtime.InteropServices;
using Microsoft.UI.Dispatching;

namespace AuraStudio.App.Services;

/// <summary>
/// PLAN-studio-rendimiento-2.md W0: vigilante del hilo de UI, solo para
/// diagnóstico en desarrollo (<c>DEBUG</c> + variable de entorno
/// <c>AURA_WATCHDOG=1</c>). Paridad conceptual con
/// <c>MainThreadWatchdog.swift</c> de la Mac: un "corazón" late en el hilo de
/// UI cada <see cref="PollIntervalMs"/> ms; un hilo aparte lo vigila y, si
/// pasan más de <see cref="ThresholdMs"/> ms sin uno nuevo, asume que el hilo
/// de UI está bloqueado.
///
/// <para><b>5.º addendum de ST-200: el vigilante colgaba la app que venía a
/// vigilar.</b> W7 midió con ventana que, con <c>AURA_WATCHDOG=1</c>, la app
/// mostraba ventana a 1.6 s y quedaba en blanco y sin responder a los 10 y a
/// los 30 s; sin la variable, la misma compilación pintaba y respondía. Había
/// dos causas, y la primera es la que explica el síntoma entero:</para>
///
/// <list type="number">
/// <item><b>El latido dormía EN el hilo de UI.</b> Cada latido se encolaba a
/// sí mismo con un <c>Thread.Sleep(50)</c> <i>dentro</i> del trabajo encolado,
/// así que el hilo de UI pasaba cincuenta milisegundos dormido de cada
/// cincuenta: no le quedaba tiempo para pintar ni para responder. Y como el
/// latido igual se registraba a tiempo, el vigilante no veía ningún bloqueo
/// que reportar — la app estaba congelada y el log, en silencio. Ahora el
/// latido es un <see cref="DispatcherQueueTimer"/>: el temporizador espera,
/// no el hilo.</item>
/// <item><b>La captura de pila podía colgarse en ARM64.</b>
/// <c>StackWalk64</c> llama a <c>SymFunctionTableAccess64</c> y
/// <c>SymGetModuleBase64</c> en <b>cada cuadro</b>, con el hilo de UI todavía
/// suspendido; si el desenrollado topa con un módulo que <c>dbghelp</c> aún no
/// tiene registrado —muy probable justo cuando el bloqueo <i>es</i> un módulo
/// cargándose— esas llamadas pueden volver a pedir el candado del cargador que
/// el hilo suspendido tiene tomado. El 4.º addendum sacó
/// <c>SymInitialize</c> de esa ventana y agregó un centinela, y con eso mejoró
/// pero no cerró.</item>
/// </list>
///
/// <para><b>Cómo queda</b> (decisión de la Maestra, alternativa mínima):</para>
///
/// <list type="bullet">
/// <item><c>AURA_WATCHDOG=1</c> mide <b>solo duraciones</b>. Escribe "bloqueo
/// de N ms" al terminar y "bloqueo en curso desde hace N ms" cada cinco
/// segundos mientras dura. No suspende nada, no toca <c>dbghelp</c>, no
/// captura pilas. Es lo que hace falta para responder "¿se bloqueó, cuánto?",
/// que es la pregunta de la ronda.</item>
/// <item><c>AURA_WATCHDOG_STACKS=1</c> —además de la primera— enciende la
/// captura de pila con el mecanismo del 4.º addendum. <b>Puede colgar la app
/// en ARM64</b>: úsese para un diagnóstico puntual y sabiendo eso, nunca de
/// forma habitual.</item>
/// <item><b>El latido nunca espera al vigilante.</b> Lo único que hace en el
/// hilo de UI es escribir una marca de tiempo con
/// <see cref="Volatile.Write(ref long, long)"/>; no toma candados, no escribe
/// a disco y no comparte nada con el hilo que registra. Un vigilante que puede
/// hacer esperar a lo que vigila mide su propia sombra.</item>
/// </list>
///
/// <para>Nunca corre fuera de <c>DEBUG</c> ni sin la variable: no es parte de
/// lo que ve el usuario.</para>
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
    private static uint _uiThreadId;
    private static bool _started;
    private static bool _stacksEnabled;
    private static readonly object StartLock = new();

    /// <summary>
    /// El temporizador del latido. Se guarda porque un
    /// <see cref="DispatcherQueueTimer"/> sin referencias vivas se puede
    /// recolectar y dejar de latir — y un vigilante que deja de latir reporta
    /// un bloqueo eterno que no existe.
    /// </summary>
    private static DispatcherQueueTimer? _heartbeat;
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
    ///
    /// <para>Lo único que corre acá, en el hilo de UI, es armar el
    /// temporizador del latido y lanzar el hilo vigilante. Todo lo demás
    /// —incluido escribir la primera línea del log y, si se pidieron pilas,
    /// preparar los símbolos— pasa en el hilo vigilante: arrancar el
    /// diagnóstico no puede costarle tiempo al arranque que se quiere
    /// medir.</para>
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

        _stacksEnabled = Environment.GetEnvironmentVariable("AURA_WATCHDOG_STACKS") == "1";
        _uiThreadId = NativeMethods.GetCurrentThreadId();
        _lastHeartbeatTicks = Environment.TickCount64;

        // El latido: un temporizador que ESPERA en vez de un trabajo encolado
        // que duerme. Si el hilo de UI se bloquea, el tick no corre y la marca
        // de tiempo deja de moverse, que es exactamente lo que hay que
        // detectar; si no se bloquea, no le cuesta nada.
        _heartbeat = uiDispatcher.CreateTimer();
        _heartbeat.Interval = TimeSpan.FromMilliseconds(PollIntervalMs);
        _heartbeat.IsRepeating = true;
        _heartbeat.Tick += (_, _) => Volatile.Write(ref _lastHeartbeatTicks, Environment.TickCount64);
        _heartbeat.Start();

        var thread = new Thread(Watch) { IsBackground = true, Name = "AuraStudio.UiThreadWatchdog" };
        thread.Start();
#endif
    }

#if DEBUG
    private static void Watch()
    {
        Log($"[UiThreadWatchdog] activo -- avisa de bloqueos del hilo de UI > {ThresholdMs} ms");

        if (_stacksEnabled)
        {
            Log("[UiThreadWatchdog] AURA_WATCHDOG_STACKS=1: se capturarán pilas. " +
                "Puede colgar la app en ARM64 -- solo para diagnóstico puntual.");

            // Acá, y solo acá: mucho antes de que exista ningún hilo
            // suspendido, y fuera del hilo de UI. Ver el 4.º addendum.
            StackWalker.InitializeSymbolsSafely();
        }

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
                    if (_stacksEnabled) StartCaptureAsync();
                }
                else if (now - lastStillHangingLogTicks >= StillHangingLogIntervalMs)
                {
                    // Un bloqueo indefinido nunca llega a "Report": sin esto
                    // no queda NADA en el log más que el "activo" inicial,
                    // que es justo lo que pasó en el hallazgo de W7.
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

        // Sin AURA_WATCHDOG_STACKS no hay pila que echar en falta: decir que no
        // se capturó sería ruido sobre algo que nadie pidió.
        if (!_stacksEnabled) return;

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
    /// <para><b>Solo bajo <c>AURA_WATCHDOG_STACKS=1</c>, y puede colgar la app en
    /// ARM64</b> (5.º addendum de ST-200): <c>StackWalk64</c> llama a
    /// <c>SymFunctionTableAccess64</c> y <c>SymGetModuleBase64</c> en cada
    /// cuadro, con el hilo de UI todavía suspendido, y esas llamadas pueden
    /// volver a pedir el candado del cargador que ese mismo hilo tiene tomado
    /// si el bloqueo es justo un módulo cargándose. El centinela de
    /// <see cref="CaptureGuardMs"/> ms tapa el caso frecuente, no el peor. Es
    /// para un diagnóstico puntual, nunca para dejarlo puesto.</para>
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
