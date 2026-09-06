#if DEBUG
using System.Runtime.InteropServices;

namespace AuraStudio.App.Services;

/// <summary>
/// P/Invoke crudo para <see cref="UiThreadWatchdog"/>: suspender un hilo del
/// propio proceso, leer su contexto y desenrollar su pila con
/// <c>dbghelp.dll</c>. x64 y ARM64 -- los offsets de <c>CONTEXT</c> vienen de
/// <c>winnt.h</c> (dos variantes, una por arquitectura: los registros no se
/// llaman igual ni ocupan el mismo lugar).
///
/// <para><c>CONTEXT</c> es <c>DECLSPEC_ALIGN(16)</c>: un struct administrado
/// pasado por <c>ref</c> no garantiza esa alineación (la probé sin ella y
/// <c>GetThreadContext</c> devolvía <c>ERROR_NOACCESS</c> en ARM64), así que
/// acá se reserva memoria nativa con <see cref="Marshal.AllocHGlobal"/> —el
/// heap de 64 bits ya alinea a 16— y se lee/escribe por offset fijo con
/// <see cref="Marshal"/>, sin declarar el struct entero: de los cientos de
/// bytes de <c>CONTEXT</c> este vigilante solo necesita <c>Rip</c>/<c>Rsp</c>/
/// <c>Rbp</c> (x64) o <c>Pc</c>/<c>Sp</c>/<c>Fp</c> (ARM64), y dejar el resto
/// sin interpretar no lo corrompe porque nunca se vuelve a escribir con
/// <c>SetThreadContext</c>.</para>
///
/// <para>Todo esto opera sobre un hilo <b>del mismo proceso</b>: no hace
/// falta <c>SeDebugPrivilege</c> ni adjuntarse como depurador (eso sí haría
/// falta para tocar OTRO proceso, y es la razón por la que este vigilante no
/// se puede portar tal cual a una herramienta externa que mida la app desde
/// afuera).</para>
/// </summary>
internal static class NativeMethods
{
    [Flags]
    public enum ThreadAccess : uint
    {
        SuspendResume = 0x0002,
        GetContext = 0x0008,
        QueryInformation = 0x0040
    }

    // sizeof(CONTEXT), documentado en winnt.h.
    public const int ContextSizeAmd64 = 1232;
    public const int ContextSizeArm64 = 912;

    // Offsets de los campos que este vigilante lee/escribe, calculados a mano
    // contra el orden de campos de winnt.h (ver el comentario de la clase).
    public const int Amd64OffsetContextFlags = 48;
    public const int Amd64OffsetRsp = 152;
    public const int Amd64OffsetRbp = 160;
    public const int Amd64OffsetRip = 248;

    public const int Arm64OffsetContextFlags = 0;
    public const int Arm64OffsetFp = 8 + 29 * 8; // X[29]
    public const int Arm64OffsetSp = 8 + 31 * 8;
    public const int Arm64OffsetPc = Arm64OffsetSp + 8;

    /// <c>CONTEXT_AMD64 | CONTEXT_CONTROL | CONTEXT_INTEGER | CONTEXT_SEGMENTS</c>.
    public const uint ContextFullAmd64 = 0x0010000B;

    /// <c>CONTEXT_ARM64 | CONTEXT_CONTROL | CONTEXT_INTEGER | CONTEXT_FLOATING_POINT</c>.
    public const uint ContextFullArm64 = 0x00400007;

    [DllImport("kernel32.dll")]
    public static extern uint GetCurrentThreadId();

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern nint OpenThread(ThreadAccess access, bool inheritHandle, uint threadId);

    [DllImport("kernel32.dll")]
    public static extern uint SuspendThread(nint hThread);

    [DllImport("kernel32.dll")]
    public static extern int ResumeThread(nint hThread);

    [DllImport("kernel32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool CloseHandle(nint handle);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GetThreadContext(nint hThread, nint context);

    [DllImport("kernel32.dll")]
    public static extern nint GetCurrentProcess();

    [DllImport("dbghelp.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool SymInitialize(nint hProcess, string? userSearchPath, [MarshalAs(UnmanagedType.Bool)] bool invadeProcess);

    [DllImport("dbghelp.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool SymCleanup(nint hProcess);

    [DllImport("dbghelp.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool StackWalk64(
        uint machineType, nint hProcess, nint hThread,
        ref STACKFRAME64 stackFrame, nint context,
        nint readMemoryRoutine, nint functionTableAccessRoutine,
        nint getModuleBaseRoutine, nint translateAddressRoutine);

    [DllImport("dbghelp.dll")]
    public static extern nint SymFunctionTableAccess64(nint hProcess, ulong addrBase);

    [DllImport("dbghelp.dll")]
    public static extern ulong SymGetModuleBase64(nint hProcess, ulong addr);

    [DllImport("dbghelp.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool SymFromAddr(nint hProcess, ulong address, out ulong displacement, nint symbolInfo);

    [DllImport("kernel32.dll")]
    public static extern nint GetModuleHandle(string? moduleName);

    [DllImport("kernel32.dll")]
    public static extern nint GetProcAddress(nint hModule, string procName);

    public const uint ImageFileMachineAmd64 = 0x8664;
    public const uint ImageFileMachineArm64 = 0xAA64;

    [StructLayout(LayoutKind.Sequential)]
    public struct ADDRESS64
    {
        public ulong Offset;
        public ushort Segment;
        public uint Mode;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct STACKFRAME64
    {
        public ADDRESS64 AddrPC;
        public ADDRESS64 AddrReturn;
        public ADDRESS64 AddrFrame;
        public ADDRESS64 AddrStack;
        public ADDRESS64 AddrBStore;
        public nint FuncTableEntry;
        public ulong Param0, Param1, Param2, Param3;
        [MarshalAs(UnmanagedType.Bool)] public bool Far;
        [MarshalAs(UnmanagedType.Bool)] public bool Virtual;
        public ulong Reserved0, Reserved1, Reserved2;
    }
}

/// <summary>
/// Desenrolla las direcciones de retorno de un hilo suspendido con
/// <c>StackWalk64</c>. No symboliza -- eso es <see cref="StackSymbolizer"/>,
/// aparte a propósito: esto corre con el hilo de UI todavía suspendido y
/// tiene que ser rápido; symbolizar puede tardar (carga de PDBs) y pasa
/// después, con el hilo ya corriendo.
/// </summary>
internal static class StackWalker
{
    private static bool _symInitialized;
    private static readonly object InitLock = new();
    private const uint AddrModeFlat = 3;

    /// <param name="context">
    /// Puntero nativo ya lleno por <c>GetThreadContext</c> (ver
    /// <see cref="NativeMethods.ContextSizeAmd64"/>/<see cref="NativeMethods.ContextSizeArm64"/>
    /// para el tamaño esperado). <c>StackWalk64</c> lo actualiza en cada
    /// vuelta -- por eso es el mismo puntero durante todo el desenrollado, no
    /// una copia.
    /// </param>
    public static IReadOnlyList<ulong> WalkAmd64(nint hThread, nint context, int maxFrames) => Walk(
        hThread, context, maxFrames, NativeMethods.ImageFileMachineAmd64,
        Marshal.ReadInt64(context, NativeMethods.Amd64OffsetRip),
        Marshal.ReadInt64(context, NativeMethods.Amd64OffsetRbp),
        Marshal.ReadInt64(context, NativeMethods.Amd64OffsetRsp));

    public static IReadOnlyList<ulong> WalkArm64(nint hThread, nint context, int maxFrames) => Walk(
        hThread, context, maxFrames, NativeMethods.ImageFileMachineArm64,
        Marshal.ReadInt64(context, NativeMethods.Arm64OffsetPc),
        Marshal.ReadInt64(context, NativeMethods.Arm64OffsetFp),
        Marshal.ReadInt64(context, NativeMethods.Arm64OffsetSp));

    private static IReadOnlyList<ulong> Walk(
        nint hThread, nint context, int maxFrames, uint machineType, long pc, long frame, long stack)
    {
        (nint hProcess, nint functionTableAccess, nint getModuleBase) = PrepareSymbols();

        var stackFrame = new NativeMethods.STACKFRAME64
        {
            AddrPC = new NativeMethods.ADDRESS64 { Offset = unchecked((ulong)pc), Mode = AddrModeFlat },
            AddrFrame = new NativeMethods.ADDRESS64 { Offset = unchecked((ulong)frame), Mode = AddrModeFlat },
            AddrStack = new NativeMethods.ADDRESS64 { Offset = unchecked((ulong)stack), Mode = AddrModeFlat }
        };

        var addresses = new List<ulong>();

        for (int i = 0; i < maxFrames; i++)
        {
            bool ok = NativeMethods.StackWalk64(
                machineType, hProcess, hThread,
                ref stackFrame, context, 0, functionTableAccess, getModuleBase, 0);

            if (!ok || stackFrame.AddrPC.Offset == 0) break;

            addresses.Add(stackFrame.AddrPC.Offset);
        }

        return addresses;
    }

    private static (nint hProcess, nint functionTableAccess, nint getModuleBase) PrepareSymbols()
    {
        nint hProcess = NativeMethods.GetCurrentProcess();
        EnsureSymInitialized(hProcess);

        nint dbghelp = NativeMethods.GetModuleHandle("dbghelp.dll");
        nint functionTableAccess = dbghelp == 0 ? 0 : NativeMethods.GetProcAddress(dbghelp, "SymFunctionTableAccess64");
        nint getModuleBase = dbghelp == 0 ? 0 : NativeMethods.GetProcAddress(dbghelp, "SymGetModuleBase64");

        return (hProcess, functionTableAccess, getModuleBase);
    }

    private static void EnsureSymInitialized(nint hProcess)
    {
        lock (InitLock)
        {
            if (_symInitialized) return;
            _symInitialized = NativeMethods.SymInitialize(hProcess, null, true);
        }
    }
}

/// <summary>
/// Le pone nombre a cada dirección, ya con el hilo de UI corriendo de nuevo.
/// Sin PDBs a mano da "(sin símbolo)" -- sigue siendo la dirección exacta,
/// suficiente para buscarla a mano con el <c>.pdb</c> de esa build.
/// </summary>
internal static class StackSymbolizer
{
    private const int MaxNameChars = 256;

    // offsetof(SYMBOL_INFO, Name) en x64, redondeado a 8 -- mismo criterio que
    // los offsets de CONTEXT arriba: no hace falta declarar el struct entero
    // porque solo se lee/escribe por offset fijo.
    private const int NameOffset = 88;

    public static IEnumerable<string> Symbolize(IReadOnlyList<ulong> addresses)
    {
        nint hProcess = NativeMethods.GetCurrentProcess();
        int bufferSize = NameOffset + MaxNameChars;
        nint buffer = Marshal.AllocHGlobal(bufferSize);

        try
        {
            foreach (ulong address in addresses) yield return SymbolizeOne(hProcess, buffer, bufferSize, address);
        }
        finally
        {
            Marshal.FreeHGlobal(buffer);
        }
    }

    private static string SymbolizeOne(nint hProcess, nint buffer, int bufferSize, ulong address)
    {
        try
        {
            for (int i = 0; i < bufferSize; i++) Marshal.WriteByte(buffer, i, 0);
            Marshal.WriteInt32(buffer, 0, NameOffset); // SYMBOL_INFO.SizeOfStruct
            Marshal.WriteInt32(buffer, 80, MaxNameChars); // SYMBOL_INFO.MaxNameLen

            if (NativeMethods.SymFromAddr(hProcess, address, out ulong displacement, buffer))
            {
                string name = Marshal.PtrToStringAnsi(buffer + NameOffset) ?? "";
                if (name.Length > 0) return $"0x{address:X} {name}+0x{displacement:X}";
            }
        }
        catch (Exception ex) when (ex is DllNotFoundException or EntryPointNotFoundException or SEHException)
        {
            // Best effort: sin símbolo, se informa igual la dirección cruda.
        }

        return $"0x{address:X} (sin símbolo)";
    }
}
#endif
