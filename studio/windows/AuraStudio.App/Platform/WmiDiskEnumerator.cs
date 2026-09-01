using System.Management;
using AuraStudio.Core;

namespace AuraStudio.App.Platform;

/// <summary>
/// Un disco USB real tal como lo reporta Windows, con los datos de plataforma
/// (ruta física y letra de volumen) junto al snapshot puro que consume
/// <see cref="IPodDiskIdentifier"/>. Equivale al par IOMedia+descripción del
/// DiskArbitration de macOS.
/// </summary>
internal sealed record WindowsDiskCandidate(
    string DevicePath,           // "\\.\PHYSICALDRIVE2"
    string? VolumePath,          // "E:\" — null si el volumen aún no montó
    DiskCandidateInfo Candidate);

/// <summary>
/// Enumera los discos USB conectados vía WMI y arma los candidatos para la
/// lógica pura de identificación. Toda la dependencia de System.Management
/// vive aquí, deliberadamente sin lógica de decisión: decidir cuál es "el
/// iPod" es trabajo exclusivo de <see cref="IPodDiskIdentifier.Identify"/>.
///
/// Correlaciones (ver el plan de detección):
///  - Vendor/producto SCSI: tokens Ven_/Prod_ del PNPDeviceID USBSTOR. Sirven
///    para describir el disco, y <b>NO</b> para saber qué firmware corre: con un
///    adaptador iFlash de por medio las reporta el adaptador, no el iPod.
///  - VID/PID y las cadenas que el aparato reporta por el bus: el nodo USB
///    (USB\VID_xxxx&amp;PID_xxxx\serial) comparte serial con el USBSTOR ID; se
///    casan por serial. Solo el iPod Classic usa 0x05AC/0x1261, y su
///    <c>BusReportedDeviceDesc</c> es la lectura real de qué firmware atiende el
///    USB (ST-016): "iPod" con el de Apple, "Rockbox media player" con
///    Rockbox/Aura.
///  - Letra de unidad: cadena de asociaciones DiskDrive → Partition → LogicalDisk.
/// </summary>
internal static class WmiDiskEnumerator
{
    /// <summary>
    /// Cuánto se espera a WMI antes de darlo por perdido.
    ///
    /// **No es una optimización, es lo que evita que la app no arranque.** Un
    /// disco USB en mal estado (visto en vivo: el iPod a medio morir en el
    /// passthrough de Parallels, con `E:` registrada pero sin responder) deja al
    /// proveedor de discos de WMI atorado enumerándolo. Sin límite, `MoveNext()`
    /// se bloquea en código nativo para siempre, y con él todo lo que esté
    /// esperando esa enumeración. Peor: mientras el proceso siga vivo y atorado,
    /// WMI se queda atorado **para todo el sistema**.
    /// </summary>
    private static readonly TimeSpan QueryTimeout = TimeSpan.FromSeconds(5);

    /// <summary>
    /// Enumeración semi-síncrona (`ReturnImmediately`) y de una sola pasada
    /// (`Rewindable = false`): es la combinación con la que WMI respeta
    /// `Timeout` y lanza `ManagementException` en vez de quedarse esperando.
    /// </summary>
    private static System.Management.EnumerationOptions TimeLimited() => new()
    {
        Timeout = QueryTimeout,
        ReturnImmediately = true,
        Rewindable = false
    };

    public static IReadOnlyList<WindowsDiskCandidate> EnumerateUsbDisks()
    {
        var result = new List<WindowsDiskCandidate>();

        // 1. Nodos USB con el VID/PID del iPod Classic: mapa serial → (vid, pid).
        //    Si esta consulta falla entera, se sigue sin identidad USB — el
        //    candidato aún puede calificar por modelo "iPod".
        var vidPidBySerial = new Dictionary<string, UsbNodeFacts>(StringComparer.OrdinalIgnoreCase);
        try
        {
            using var usbSearcher = new ManagementObjectSearcher(
                "SELECT DeviceID FROM Win32_PnPEntity WHERE DeviceID LIKE 'USB\\\\VID_05AC&PID_1261%'")
            { Options = TimeLimited() };
            foreach (ManagementBaseObject usb in usbSearcher.Get())
            {
                string deviceId = usb["DeviceID"] as string ?? "";

                // El nodo de INTERFAZ (`&MI_00`) es el de almacenamiento masivo
                // y se reporta a sí mismo como "USB Mass Storage Device": no
                // dice nada del firmware. El que sirve es el nodo del aparato.
                if (deviceId.Contains("&MI_", StringComparison.OrdinalIgnoreCase)) continue;

                if (!PnpDeviceId.TryParseUsbDeviceId(deviceId, out int vid, out int pid, out string? serial)
                    || serial is null)
                {
                    continue;
                }

                (string? product, string? manufacturer) = usb is ManagementObject node
                    ? ReadUsbDescriptorStrings(node)
                    : (null, null);

                vidPidBySerial[serial] = new UsbNodeFacts(vid, pid, product, manufacturer);
            }
        }
        catch
        {
            // Sin acceso a WMI de PnP: se continúa solo con USBSTOR.
        }

        // 2. Discos físicos por USB. InterfaceType='USB' implica removible y
        //    externo; el criterio duro se re-aplica igual en MatchesIPodCriteria.
        try
        {
            using var diskSearcher = new ManagementObjectSearcher(
                "SELECT DeviceID, Index, PNPDeviceID, Model, Size FROM Win32_DiskDrive WHERE InterfaceType='USB'")
            { Options = TimeLimited() };

            foreach (ManagementObject disk in diskSearcher.Get())
            {
                try
                {
                    result.Add(BuildCandidate(disk, vidPidBySerial));
                }
                catch
                {
                    // Un disco que se desconecta a mitad de la consulta, o que no
                    // responde, no debe tumbar la enumeración de los demás — ni
                    // impedir que la app arranque.
                }
            }
        }
        catch (ManagementException)
        {
            // WMI no respondió a tiempo (disco en mal estado atorando al
            // proveedor). Se devuelve lo que se haya alcanzado a leer: mejor
            // "no veo ningún iPod" que una app colgada.
        }

        return result;
    }

    /// <summary>
    /// Lo que el nodo USB del aparato dice de sí mismo.
    /// </summary>
    /// <param name="BusReportedProduct">
    /// <c>DEVPKEY_Device_BusReportedDeviceDesc</c>: la cadena de producto que
    /// <b>el aparato reporta por el bus</b>. Es el equivalente exacto de lo que
    /// macOS lee del descriptor USB, y la única que distingue quién atiende el
    /// USB: "iPod" con el firmware de Apple, "Rockbox media player" con
    /// Rockbox/Aura. <c>null</c> si no se pudo leer.
    /// </param>
    /// <param name="Manufacturer">
    /// <c>DEVPKEY_Device_Manufacturer</c>. Ojo: <b>lo pone el INF, no el
    /// aparato</b> — con Aura corriendo sigue diciendo "Apple". Se pasa igual
    /// porque el clasificador la usa solo como refuerzo del caso Apple.
    /// </param>
    private readonly record struct UsbNodeFacts(
        int Vid, int Pid, string? BusReportedProduct, string? Manufacturer);

    private const string BusReportedDeviceDescKey = "DEVPKEY_Device_BusReportedDeviceDesc";
    private const string ManufacturerKey = "DEVPKEY_Device_Manufacturer";

    /// <summary>
    /// Lee las cadenas del nodo USB con <c>GetDeviceProperties</c> de
    /// <c>Win32_PnPEntity</c> — el mismo camino que usa <c>Get-PnpDeviceProperty</c>,
    /// así que no hace falta interop nuevo.
    ///
    /// <para>Falla en silencio a <c>null</c>: sin esta lectura el firmware que
    /// corre queda en "desconocido", que es la respuesta honesta. <b>Nunca se
    /// inventa una identidad</b> (ST-016).</para>
    /// </summary>
    private static (string? Product, string? Manufacturer) ReadUsbDescriptorStrings(ManagementObject node)
    {
        try
        {
            ManagementBaseObject arguments = node.GetMethodParameters("GetDeviceProperties");
            arguments["devicePropertyKeys"] = new[] { BusReportedDeviceDescKey, ManufacturerKey };

            ManagementBaseObject result = node.InvokeMethod("GetDeviceProperties", arguments, null);

            string? product = null;
            string? manufacturer = null;

            if (result["deviceProperties"] is ManagementBaseObject[] properties)
            {
                foreach (ManagementBaseObject property in properties)
                {
                    string key = property["KeyName"] as string ?? "";
                    string? value = property["Data"] as string;

                    if (key == BusReportedDeviceDescKey) product = value;
                    else if (key == ManufacturerKey) manufacturer = value;
                }
            }

            return (product, manufacturer);
        }
        catch (Exception)
        {
            return (null, null);
        }
    }

    private static WindowsDiskCandidate BuildCandidate(
        ManagementObject disk,
        IReadOnlyDictionary<string, UsbNodeFacts> vidPidBySerial)
    {
        string devicePath = disk["DeviceID"] as string ?? "";
        string model = disk["Model"] as string ?? "";
        long sizeBytes = disk["Size"] is ulong s ? (long)s : 0;
        uint diskIndex = disk["Index"] is uint idx ? idx : Convert.ToUInt32(disk["Index"] ?? 0);
        string pnpId = disk["PNPDeviceID"] as string ?? "";

        // Vendor/producto SCSI desde el USBSTOR ID; si no parsea, se queda el
        // Model plano de WMI (que concatena "vendor product").
        string vendor = "";
        string product = model;
        string? serial = null;
        if (PnpDeviceId.TryParseUsbStorageId(pnpId, out var storageId))
        {
            vendor = storageId.Vendor;
            product = storageId.Product;
            serial = storageId.Serial;
        }

        USBDeviceIdentity? usbIdentity = null;
        // Búsqueda directa por serial o contención en el PNPDeviceID
        foreach (var (knownSerial, usb) in vidPidBySerial)
        {
            if ((serial is not null && serial.Contains(knownSerial, StringComparison.OrdinalIgnoreCase))
                || pnpId.Contains(knownSerial, StringComparison.OrdinalIgnoreCase))
            {
                // Qué firmware atiende el USB sale de lo que reporta el APARATO
                // (ST-016), no de las cadenas SCSI del disco. Con un adaptador
                // iFlash el SCSI dice "iFlash-P"/"latform iPod Ada" —el
                // adaptador, no el firmware—, y por eso el iPod del dueño con
                // Aura corriendo quedaba en "desconocido" y sin sincronizar.
                // Verificado contra su aparato: el nodo USB reporta
                // "Rockbox media player".
                string usbProduct = usb.BusReportedProduct is { Length: > 0 } reported ? reported : product;
                string usbVendor = usb.Manufacturer is { Length: > 0 } maker ? maker : vendor;

                usbIdentity = new USBDeviceIdentity(usbVendor, usbProduct, knownSerial, usb.Vid, usb.Pid);
                break;
            }
        }

        (string? volumePath, string? volumeName) = FindMountedVolume(diskIndex);

        // "PHYSICALDRIVE2" como equivalente del BSDName ("disk2" en macOS).
        string diskName = devicePath.StartsWith(@"\\.\", StringComparison.Ordinal)
            ? devicePath[4..]
            : devicePath;

        var candidate = new DiskCandidateInfo(
            BSDName: diskName,
            Vendor: vendor,
            Model: product,
            IsRemovable: true,   // InterfaceType='USB' del WHERE de la consulta
            IsInternal: false,
            SizeBytes: sizeBytes,
            VolumeName: volumeName,
            USB: usbIdentity);

        return new WindowsDiskCandidate(devicePath, volumePath, candidate);
    }

    /// <summary>
    /// Letra y etiqueta del primer volumen montado del disco, o (null, null)
    /// si todavía no hay ninguno (el iPod puede tardar unos segundos en
    /// montar tras el WM_DEVICECHANGE — el reintento de MainWindow lo cubre).
    /// </summary>
    private static (string? VolumePath, string? VolumeName) FindMountedVolume(uint diskIndex)
    {
        try
        {
            using var partitionSearcher = new ManagementObjectSearcher(
                $"SELECT DeviceID FROM Win32_DiskPartition WHERE DiskIndex = {diskIndex}")
            { Options = TimeLimited() };
            foreach (ManagementBaseObject partition in partitionSearcher.Get())
            {
                if (partition["DeviceID"] is not string partId) continue;

                using var assocSearcher = new ManagementObjectSearcher(
                    "SELECT Antecedent, Dependent FROM Win32_LogicalDiskToPartition")
                { Options = TimeLimited() };
                foreach (ManagementBaseObject assoc in assocSearcher.Get())
                {
                    string? ante = assoc["Antecedent"] as string;
                    string? dep = assoc["Dependent"] as string;

                    if (ante is not null && ante.Contains(partId, StringComparison.OrdinalIgnoreCase) && dep is not null)
                    {
                        int eqIdx = dep.IndexOf("DeviceID=\"", StringComparison.OrdinalIgnoreCase);
                        if (eqIdx >= 0)
                        {
                            int start = eqIdx + 10;
                            int end = dep.IndexOf('"', start);
                            string letter = end > start ? dep[start..end] : dep[start..];
                            if (letter.Length > 0)
                            {
                                string volName = "";
                                try
                                {
                                    using var logDiskSearcher = new ManagementObjectSearcher(
                                        $"SELECT VolumeName FROM Win32_LogicalDisk WHERE DeviceID = '{letter}'")
                                    { Options = TimeLimited() };
                                    foreach (ManagementBaseObject logDisk in logDiskSearcher.Get())
                                    {
                                        volName = logDisk["VolumeName"] as string ?? "";
                                        break;
                                    }
                                }
                                catch { }

                                return (letter.TrimEnd('\\') + @"\", volName);
                            }
                        }
                    }
                }
            }
        }
        catch
        {
            // Sin particiones o fallo en WMI
        }

        return (null, null);
    }
}
