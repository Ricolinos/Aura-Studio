using System.Runtime.InteropServices;
using System.Runtime.Versioning;

namespace AuraStudio.Core.Library;

/// <summary>
/// Mandar un archivo a la Papelera. Existe como interfaz para que
/// <see cref="LibraryDeletion"/> se pueda probar sin tocar la Papelera de
/// verdad (ST-245).
/// </summary>
public interface IRecycleBin
{
    /// <returns><c>true</c> si el archivo se movió a la Papelera.</returns>
    bool MoveToRecycleBin(string path);
}

/// <summary>
/// Ninguna Papelera: no hace nada y dice que no movió nada. Existe solo para
/// que <see cref="AuraStudio.Core"/> —que apunta a un <c>net10.0</c> portable
/// y no a un TFM de Windows— compile y sus pruebas corran sin pedir Windows;
/// la app real es Windows siempre y nunca llega a usar esto (ver
/// <see cref="LibraryDeletion"/>).
/// </summary>
public sealed class NoOpRecycleBin : IRecycleBin
{
    public static readonly NoOpRecycleBin Instance = new();

    public bool MoveToRecycleBin(string path) => false;
}

/// <summary>
/// La Papelera de reciclaje de Windows de verdad, vía <c>SHFileOperationW</c>
/// con <c>FOF_ALLOWUNDO</c> (ST-245, decisión de B5): un archivo eliminado en
/// modo copia <b>nunca es un borrado definitivo</b> — el usuario se tiene que
/// poder arrepentir, igual que <c>trashItem</c> en la Mac.
///
/// <para><b>Por qué <c>SHFileOperationW</c> y no el <c>IFileOperation</c>
/// moderno</b>: hace exactamente lo mismo para este único caso —un archivo, sin
/// interfaz, con deshacer— con una firma plana que no necesita instanciar un
/// objeto COM ni un <c>IFileOperationProgressSink</c>. Sigue siendo la función
/// que documenta Microsoft para mandar algo a la Papelera por código, y no
/// está retirada.</para>
/// </summary>
[SupportedOSPlatform("windows")]
public sealed class WindowsRecycleBin : IRecycleBin
{
    public static readonly WindowsRecycleBin Shared = new();

    public bool MoveToRecycleBin(string path)
    {
        if (path is not { Length: > 0 } || !File.Exists(path)) return false;

        var operation = new SHFILEOPSTRUCT
        {
            wFunc = FO_DELETE,
            // SHFileOperation pide la lista de rutas terminada en DOS nulos.
            pFrom = path + '\0' + '\0',
            fFlags = FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_NOERRORUI | FOF_SILENT
        };

        int result = SHFileOperationW(ref operation);
        return result == 0 && !operation.fAnyOperationsAborted;
    }

    private const uint FO_DELETE = 0x0003;
    private const ushort FOF_ALLOWUNDO = 0x0040;
    private const ushort FOF_NOCONFIRMATION = 0x0010;
    private const ushort FOF_SILENT = 0x0004;
    private const ushort FOF_NOERRORUI = 0x0400;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct SHFILEOPSTRUCT
    {
        public nint hwnd;
        public uint wFunc;
        public string pFrom;
        public string? pTo;
        public ushort fFlags;
        [MarshalAs(UnmanagedType.Bool)] public bool fAnyOperationsAborted;
        public nint hNameMappings;
        public string? lpszProgressTitle;
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern int SHFileOperationW(ref SHFILEOPSTRUCT lpFileOp);
}
