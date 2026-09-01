using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace AuraStudio.App.Platform;

/// <summary>
/// Un volumen del disco, bloqueado y desmontado, con su handle vivo.
///
/// <para><b>Por qué hace falta.</b> Desde Windows Vista, una escritura al handle
/// del **disco** se rechaza si toca sectores cubiertos por un volumen
/// **montado** — aunque el proceso sea administrador. Es exactamente el fallo
/// que se vio en hardware: el iPod tenía `E:` (exFAT) montada, y abrir
/// `\\.\PhysicalDrive1` para escribir devolvió "Access to the path is denied".
/// La vía canónica es tomar cada volumen del disco, hacerle
/// <c>FSCTL_LOCK_VOLUME</c> + <c>FSCTL_DISMOUNT_VOLUME</c> y **mantener el
/// handle abierto** durante toda la operación: mientras el bloqueo esté vivo,
/// Windows no lo vuelve a montar y las escrituras al disco pasan.</para>
///
/// <para>El bloqueo se libera al cerrar el handle, así que el <c>Dispose</c> es
/// el desbloqueo. Por eso los locks se sostienen en un <c>using</c> que abarca
/// toda la escritura.</para>
/// </summary>
internal sealed partial class VolumeLock : IDisposable
{
    private readonly SafeFileHandle _handle;

    /// <summary>Nombre del volumen (`\\?\Volume{GUID}`), para poder nombrarlo en la bitácora.</summary>
    public string VolumeName { get; }

    /// <summary>Se logró desmontarlo (no solo bloquearlo).</summary>
    public bool Dismounted { get; }

    private VolumeLock(string volumeName, SafeFileHandle handle, bool dismounted)
    {
        VolumeName = volumeName;
        _handle = handle;
        Dismounted = dismounted;
    }

    public void Dispose() => _handle.Dispose();

    /// <summary>
    /// Bloquea y desmonta **todos** los volúmenes que viven en el disco indicado.
    ///
    /// Se enumeran por sus extensiones reales
    /// (<c>IOCTL_VOLUME_GET_VOLUME_DISK_EXTENTS</c>), no por letra de unidad: un
    /// volumen sin letra, o montado en una carpeta, bloquea las escrituras
    /// exactamente igual que uno con letra.
    /// </summary>
    /// <exception cref="IOException">Algún volumen del disco no se pudo bloquear.</exception>
    public static List<VolumeLock> LockVolumesOnDisk(int diskNumber, List<string> log)
    {
        var locks = new List<VolumeLock>();
        try
        {
            foreach (string volume in EnumerateVolumes())
            {
                // CreateFile no acepta la barra final que devuelve la enumeración.
                string path = volume.TrimEnd('\\');

                // Para preguntar dónde vive el volumen alcanza con acceso cero:
                // menos privilegio, y funciona aunque el volumen esté ocupado.
                using (SafeFileHandle probe = OpenVolumeForQuery(path))
                {
                    if (probe.IsInvalid) continue;
                    if (!VolumeLivesOnDisk(probe, diskNumber)) continue;
                }

                locks.Add(LockOne(path, log));
            }
        }
        catch
        {
            // Si uno falla, se sueltan los que ya se tomaron: dejar volúmenes
            // bloqueados tras un error dejaría el disco inutilizable hasta
            // cerrar la aplicación.
            foreach (VolumeLock taken in locks) taken.Dispose();
            throw;
        }

        if (locks.Count == 0) log.Add("no había volúmenes montados que bloquear");
        return locks;
    }

    /// <summary>
    /// Qué volúmenes viven en el disco, **sin tocarlos**: ni se bloquean ni se
    /// desmontan. Para que el ensayo pueda decir qué haría el formateo real sin
    /// desmontarle el iPod al usuario.
    /// </summary>
    public static List<string> DescribeVolumesOnDisk(int diskNumber)
    {
        var found = new List<string>();
        foreach (string volume in EnumerateVolumes())
        {
            string path = volume.TrimEnd('\\');
            using SafeFileHandle probe = OpenVolumeForQuery(path);
            if (probe.IsInvalid) continue;
            if (VolumeLivesOnDisk(probe, diskNumber)) found.Add(path);
        }
        return found;
    }

    private static VolumeLock LockOne(string path, List<string> log)
    {
        SafeFileHandle handle = OpenVolume(path);
        if (handle.IsInvalid)
        {
            throw new IOException($"No se pudo abrir el volumen {path} (error {Marshal.GetLastWin32Error()}).");
        }

        // El bloqueo falla si otro proceso tiene archivos abiertos ahí. Se
        // reintenta un poco: el Explorador o un antivirus suelen soltar solos.
        const int attempts = 10;
        for (int i = 1; ; i++)
        {
            if (DeviceIoControl(handle, FsctlLockVolume, IntPtr.Zero, 0, IntPtr.Zero, 0, out _, IntPtr.Zero))
            {
                break;
            }
            if (i == attempts)
            {
                int error = Marshal.GetLastWin32Error();
                handle.Dispose();
                throw new IOException(
                    $"No se pudo bloquear el volumen {path} tras {attempts} intentos (error {error}). " +
                    "Cierra las ventanas del Explorador y las aplicaciones que estén usando el iPod.");
            }
            Thread.Sleep(300);
        }

        bool dismounted = DeviceIoControl(handle, FsctlDismountVolume, IntPtr.Zero, 0, IntPtr.Zero, 0, out _, IntPtr.Zero);
        log.Add($"volumen {path}: bloqueado{(dismounted ? " y desmontado" : " (no se pudo desmontar)")}");
        return new VolumeLock(path, handle, dismounted);
    }

    /// <summary>`true` si alguna extensión del volumen cae en el disco indicado.</summary>
    private static bool VolumeLivesOnDisk(SafeFileHandle volume, int diskNumber)
    {
        const int bufferSize = 4096;
        IntPtr buffer = Marshal.AllocHGlobal(bufferSize);
        try
        {
            if (!DeviceIoControl(volume, IoctlVolumeGetVolumeDiskExtents,
                                 IntPtr.Zero, 0, buffer, bufferSize, out _, IntPtr.Zero))
            {
                return false;   // sin medio, o no es un volumen simple
            }

            int count = Marshal.ReadInt32(buffer);
            // VOLUME_DISK_EXTENTS: DWORD + relleno, después DISK_EXTENT de 24 bytes
            // cada uno, con DiskNumber al principio.
            for (int i = 0; i < count; i++)
            {
                int diskOfExtent = Marshal.ReadInt32(buffer, 8 + i * 24);
                if (diskOfExtent == diskNumber) return true;
            }
            return false;
        }
        finally
        {
            Marshal.FreeHGlobal(buffer);
        }
    }

    private static IEnumerable<string> EnumerateVolumes()
    {
        var name = new char[260];
        IntPtr find = FindFirstVolumeW(name, name.Length);
        if (find == InvalidHandle) yield break;

        try
        {
            do
            {
                // Cortar en el primer nulo, no recortar los del final: la API no
                // limpia el resto del búfer, así que un nombre corto después de
                // uno largo dejaría cola del anterior.
                int end = Array.IndexOf(name, '\0');
                yield return new string(name, 0, end < 0 ? name.Length : end);
            }
            while (FindNextVolumeW(find, name, name.Length));
        }
        finally
        {
            FindVolumeClose(find);
        }
    }

    // MARK: - Win32

    private static readonly IntPtr InvalidHandle = new(-1);

    private const uint GenericRead = 0x80000000;
    private const uint GenericWrite = 0x40000000;
    private const uint ShareReadWrite = 0x00000003;
    private const uint OpenExisting = 3;

    // CTL_CODE(FILE_DEVICE_FILE_SYSTEM, 6|8, METHOD_BUFFERED, FILE_ANY_ACCESS)
    private const uint FsctlLockVolume = 0x00090018;
    private const uint FsctlDismountVolume = 0x00090020;
    // CTL_CODE(IOCTL_VOLUME_BASE, 0, METHOD_BUFFERED, FILE_ANY_ACCESS)
    private const uint IoctlVolumeGetVolumeDiskExtents = 0x00560000;

    /// <summary>Handle con lectura y escritura: hace falta para bloquear y desmontar.</summary>
    internal static SafeFileHandle OpenVolume(string path) =>
        CreateFileW(path, GenericRead | GenericWrite, ShareReadWrite, IntPtr.Zero, OpenExisting, 0, IntPtr.Zero);

    /// <summary>
    /// Handle solo para preguntar (acceso cero). Alcanza para
    /// <c>IOCTL_VOLUME_GET_VOLUME_DISK_EXTENTS</c> y no pide permisos que no
    /// hacen falta.
    /// </summary>
    internal static SafeFileHandle OpenVolumeForQuery(string path) =>
        CreateFileW(path, 0, ShareReadWrite, IntPtr.Zero, OpenExisting, 0, IntPtr.Zero);

    [LibraryImport("kernel32.dll", EntryPoint = "CreateFileW", SetLastError = true,
                   StringMarshalling = StringMarshalling.Utf16)]
    internal static partial SafeFileHandle CreateFileW(string fileName, uint access, uint share,
                                                       IntPtr security, uint creationDisposition,
                                                       uint flags, IntPtr template);

    [LibraryImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static partial bool DeviceIoControl(SafeFileHandle device, uint controlCode,
                                                 IntPtr inBuffer, uint inSize,
                                                 IntPtr outBuffer, uint outSize,
                                                 out uint bytesReturned, IntPtr overlapped);

    [LibraryImport("kernel32.dll", EntryPoint = "FindFirstVolumeW", SetLastError = true,
                   StringMarshalling = StringMarshalling.Utf16)]
    private static partial IntPtr FindFirstVolumeW([Out] char[] volumeName, int bufferLength);

    [LibraryImport("kernel32.dll", EntryPoint = "FindNextVolumeW", SetLastError = true,
                   StringMarshalling = StringMarshalling.Utf16)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool FindNextVolumeW(IntPtr findVolume, [Out] char[] volumeName, int bufferLength);

    [LibraryImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool FindVolumeClose(IntPtr findVolume);
}

/// <summary>Acceso crudo al disco físico, una vez que sus volúmenes están bloqueados.</summary>
internal static class RawDisk
{
    /// <summary>
    /// Le dice a Windows que vuelva a leer la tabla de particiones. Sin esto, el
    /// sistema sigue creyendo en el diseño viejo hasta que se desconecte el
    /// disco, y el volumen nuevo no aparece.
    /// </summary>
    private const uint IoctlDiskUpdateProperties = 0x00070140;

    /// <summary>
    /// Permite escribir en toda la superficie del disco, incluidos los sectores
    /// que un sistema de archivos consideraría suyos.
    /// </summary>
    private const uint FsctlAllowExtendedDasdIo = 0x00090083;

    public static SafeFileHandle Open(int diskNumber)
    {
        SafeFileHandle handle = VolumeLock.OpenVolume($@"\\.\PhysicalDrive{diskNumber}");
        if (handle.IsInvalid)
        {
            int error = Marshal.GetLastWin32Error();
            throw new IOException(
                $"No se pudo abrir el disco {diskNumber} para escritura (error {error}).");
        }
        VolumeLock.DeviceIoControl(handle, FsctlAllowExtendedDasdIo, IntPtr.Zero, 0, IntPtr.Zero, 0, out _, IntPtr.Zero);
        return handle;
    }

    public static bool UpdateProperties(SafeFileHandle disk) =>
        VolumeLock.DeviceIoControl(disk, IoctlDiskUpdateProperties, IntPtr.Zero, 0, IntPtr.Zero, 0, out _, IntPtr.Zero);
}
