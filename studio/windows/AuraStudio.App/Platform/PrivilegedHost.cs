using System.Diagnostics;
using System.Management;
using System.ServiceProcess;
using System.Text;
using Microsoft.Win32.SafeHandles;
using AuraStudio.Core;
using AuraStudio.Core.Installer;

namespace AuraStudio.App.Platform;

/// <summary>
/// Lado elevado: lo que corre cuando Aura Studio se relanza a sí misma con
/// permisos de administrador. Lee la petición, **la vuelve a validar**,
/// **re-verifica el disco**, ejecuta y deja el resultado en un archivo.
///
/// <para><b>Nunca confía en la petición.</b> El archivo JSON lo escribió esta
/// misma app hace un instante, y aun así se valida de nuevo y se comprueba
/// contra el hardware real: entre que el usuario confirmó y que este proceso
/// arranca hubo un diálogo de UAC de por medio, y el disco pudo desconectarse,
/// reconectarse con otro número, o ser otro. Es la misma regla que en macOS
/// hace que el script de formateo re-verifique identidad **dentro** del
/// contexto privilegiado en vez de fiarse del identificador que le pasaron.</para>
///
/// <para><b>Ningún camino escribe sin haber pasado por
/// <see cref="ReverifyDisk"/>.</b> Si algo no coincide, sale con
/// <see cref="PrivilegedOperationResult.Abort"/> y no toca nada.</para>
/// </summary>
internal static class PrivilegedHost
{
    public const int ExitOk = 0;
    public const int ExitFailed = 1;
    public const int ExitCancelled = 1223;   // ERROR_CANCELLED, por simetría con UAC

    /// <summary>
    /// `true` si estos argumentos son una petición privilegiada; entonces la app
    /// **no** abre ninguna ventana: hace el trabajo y termina.
    /// </summary>
    public static bool TryHandle(string[] args, out int exitCode)
    {
        exitCode = ExitOk;
        if (args.Length < 3 || args[0] != PrivilegedRunner.Switch) return false;

        string requestPath = args[1];
        string resultPath = args[2];
        var log = new List<string>();

        PrivilegedOperationResult result;
        try
        {
            string json = File.ReadAllText(requestPath);
            PrivilegedOperation? operation = PrivilegedOperation.FromJson(json);

            if (operation is null)
            {
                result = PrivilegedOperationResult.Failure("La petición no se pudo leer.");
            }
            else if (operation.Validate() is { } invalid)
            {
                result = PrivilegedOperationResult.Abort(invalid);
            }
            else
            {
                result = Execute(operation, log);
            }
        }
        catch (Exception ex)
        {
            result = PrivilegedOperationResult.Failure(ex.Message, log);
        }

        try
        {
            File.WriteAllText(resultPath, (result with { Log = log }).ToJson());
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            // Sin resultado el lado no elevado ya reporta que no puede saber qué pasó.
        }

        exitCode = result.Success ? ExitOk : ExitFailed;
        return true;
    }

    private static PrivilegedOperationResult Execute(PrivilegedOperation operation, List<string> log)
        => operation.Kind switch
        {
            PrivilegedOperationKind.FormatIPodFat32 => FormatIPod(operation, log),
            PrivilegedOperationKind.PauseAppleMobileDeviceService => SetAppleService(start: false, log),
            PrivilegedOperationKind.ResumeAppleMobileDeviceService => SetAppleService(start: true, log),
            _ => PrivilegedOperationResult.Abort("Operación privilegiada desconocida.")
        };

    // MARK: - Re-verificación del disco

    private sealed record DiskFacts(int Number, long SizeBytes, string Model, int BytesPerSector,
                                    string InterfaceType, bool MediaLoaded);

    /// <summary>
    /// Lee el disco **ahora**, en este proceso, y comprueba que sea el que el
    /// usuario confirmó. Devuelve el motivo del aborto, o los datos del disco.
    /// </summary>
    private static (DiskFacts? Facts, string? Abort) ReverifyDisk(PrivilegedOperation operation, List<string> log)
    {
        DiskFacts? facts;
        try
        {
            using var searcher = new ManagementObjectSearcher(
                "SELECT Index, Size, Model, BytesPerSector, InterfaceType, MediaLoaded FROM Win32_DiskDrive " +
                $"WHERE Index = {operation.DiskNumber}");
            using ManagementObjectCollection disks = searcher.Get();

            facts = disks.Cast<ManagementBaseObject>().Select(d => new DiskFacts(
                Number: Convert.ToInt32(d["Index"]),
                SizeBytes: d["Size"] is not null ? Convert.ToInt64(d["Size"]) : 0,
                Model: d["Model"] as string ?? "",
                BytesPerSector: d["BytesPerSector"] is not null ? Convert.ToInt32(d["BytesPerSector"]) : 512,
                InterfaceType: d["InterfaceType"] as string ?? "",
                MediaLoaded: d["MediaLoaded"] is bool loaded && loaded)).FirstOrDefault();
        }
        catch (ManagementException ex)
        {
            return (null, $"no se pudo volver a consultar el disco ({ex.Message})");
        }

        if (facts is null)
        {
            return (null, $"el disco {operation.DiskNumber} ya no existe");
        }

        log.Add($"disco {facts.Number}: {facts.Model}, {facts.SizeBytes} bytes, " +
                $"sector {facts.BytesPerSector} B, bus {facts.InterfaceType}");

        // El bus tiene que seguir siendo USB: el iPod nunca es un disco interno,
        // y esta es la última barrera antes de borrar.
        if (!facts.InterfaceType.Equals("USB", StringComparison.OrdinalIgnoreCase))
        {
            return (null, $"el disco ya no aparece conectado por USB (bus {facts.InterfaceType})");
        }
        if (!facts.MediaLoaded)
        {
            return (null, "el disco ya no tiene medio montado");
        }

        long difference = Math.Abs(facts.SizeBytes - operation.ExpectedSizeBytes);
        if (difference > operation.SizeToleranceBytes)
        {
            return (null, $"el tamaño del disco ya no coincide ({facts.SizeBytes} bytes)");
        }

        if (operation.ExpectedModel.Length > 0
            && !facts.Model.Equals(operation.ExpectedModel, StringComparison.OrdinalIgnoreCase))
        {
            return (null, $"el modelo del disco cambió (ahora dice «{facts.Model}»)");
        }

        return (facts, null);
    }

    // MARK: - Formateo

    private static PrivilegedOperationResult FormatIPod(PrivilegedOperation operation, List<string> log)
    {
        (DiskFacts? facts, string? abort) = ReverifyDisk(operation, log);
        if (facts is null) return PrivilegedOperationResult.Abort(abort!, log);

        int bytesPerSector = facts.BytesPerSector is 512 or 1024 or 2048 or 4096 ? facts.BytesPerSector : 512;
        uint firstLba = MasterBootRecord.AlignedFirstLba(bytesPerSector);
        long totalSectors = facts.SizeBytes / bytesPerSector;
        long partitionSectors = totalSectors - firstLba;

        if (partitionSectors <= 0 || partitionSectors > uint.MaxValue)
        {
            return PrivilegedOperationResult.Abort(
                "el disco no entra en el direccionamiento de 32 bits del MBR", log);
        }

        Fat32Layout layout;
        try
        {
            layout = Fat32Formatter.ComputeLayout((uint)partitionSectors, bytesPerSector, firstLba);
        }
        catch (ArgumentOutOfRangeException ex)
        {
            return PrivilegedOperationResult.Abort($"no se puede armar un FAT32 en este disco: {ex.Message}", log);
        }

        log.Add($"plan: partición en LBA {firstLba}, {partitionSectors} sectores, " +
                $"clúster {layout.BytesPerCluster} B, {layout.CountOfClusters} clústeres, " +
                $"{layout.SectorsPerFat} sectores por FAT");
        log.Add($"etiqueta: {Fat32Formatter.NormalizeLabel(operation.VolumeLabel).TrimEnd()}");

        if (operation.DryRun)
        {
            // Se listan los volúmenes que habría que bloquear, pero NO se
            // bloquean: desmontar el iPod en un ensayo sería un efecto que el
            // usuario no pidió. Solo se leen sus extensiones.
            foreach (string volume in VolumeLock.DescribeVolumesOnDisk(facts.Number))
            {
                log.Add($"se bloquearía y desmontaría: {volume}");
            }
            log.Add("ENSAYO: no se escribió nada.");
            return PrivilegedOperationResult.Ok(
                "Ensayo completo: el disco se volvió a verificar y el plan de formateo es válido. " +
                "No se escribió nada.", log);
        }

        // Re-verificar OTRA VEZ, ya sin nada entre medias: es la última lectura
        // antes de abrir el disco para escribir.
        (DiskFacts? again, string? abortAgain) = ReverifyDisk(operation, log);
        if (again is null) return PrivilegedOperationResult.Abort(abortAgain!, log);

        // Bloquear y desmontar TODOS los volúmenes del disco, y sostener esos
        // handles durante toda la escritura.
        //
        // Sin esto, Windows rechaza escribir en los sectores que cubre un
        // volumen montado aunque el proceso sea administrador: es el fallo real
        // que se vio en hardware ("Access to the path '\\.\PhysicalDrive1' is
        // denied", con el iPod montado como exFAT en E:).
        List<VolumeLock> locks;
        try
        {
            locks = VolumeLock.LockVolumesOnDisk(facts.Number, log);
        }
        catch (IOException ex)
        {
            return PrivilegedOperationResult.Failure(ex.Message, log);
        }

        try
        {
            WriteTableAndFilesystem(facts.Number, firstLba, layout, operation.VolumeLabel, log);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return PrivilegedOperationResult.Failure(
                $"No se pudo escribir en el disco: {ex.Message}", log);
        }
        finally
        {
            // Cerrar el handle libera el bloqueo; recién ahí Windows puede
            // volver a montar, y monta lo que acabamos de escribir.
            foreach (VolumeLock held in locks) held.Dispose();
        }

        // Recién ahora se le pide a Windows releer el diseño. Hacerlo con los
        // volúmenes todavía bloqueados y desmontados no sirve de nada: el
        // sistema no puede montar lo nuevo mientras el bloqueo esté vivo, y
        // después de soltarlo nada le pide que vuelva a mirar.
        try
        {
            using SafeFileHandle rescan = RawDisk.Open(facts.Number);
            log.Add(RawDisk.UpdateProperties(rescan)
                ? "Windows releyó la tabla de particiones"
                : "Windows no releyó la tabla (se verá al reconectar el iPod)");
        }
        catch (IOException ex)
        {
            // El formateo ya está hecho y verificado; que el sistema no lo relea
            // solo significa reconectar el iPod.
            log.Add($"no se pudo pedir la relectura del diseño: {ex.Message}");
        }

        log.Add("listo");
        return PrivilegedOperationResult.Ok("El iPod quedó formateado en FAT32.", log);
    }

    /// <summary>
    /// Escribe la tabla de particiones y el sistema de archivos con **un solo
    /// handle** al disco físico, ya con sus volúmenes bloqueados.
    ///
    /// <para>Ya no se usa `diskpart clean`. Se probó y falló en hardware: el
    /// `clean` no limpió nada y **diskpart salió con código 0 igual**, así que
    /// el código lo dio por bueno y siguió hasta chocar con el "acceso
    /// denegado" al escribir. Una herramienta cuyo código de salida miente no
    /// sirve como paso previo de algo destructivo. Lo que hacía `clean` —dejar
    /// el disco sin diseño de particiones— se hace acá directamente: se ponen en
    /// cero el primer y el último mebibyte (que es donde viven la tabla, los
    /// restos de GPT y su copia de respaldo) y se escribe la tabla nueva.</para>
    /// </summary>
    private static void WriteTableAndFilesystem(int diskNumber, uint firstLba, Fat32Layout layout,
                                                string label, List<string> log)
    {
        using SafeFileHandle handle = RawDisk.Open(diskNumber);
        using var disk = new FileStream(handle, FileAccess.ReadWrite);

        long diskBytes = (long)layout.TotalSectors * layout.BytesPerSector
                       + (long)firstLba * layout.BytesPerSector;

        // 1) Borrar el diseño anterior: primer y último MiB. Un respaldo de GPT
        //    olvidado al final del disco basta para que Windows siga viendo el
        //    disco como GPT y desconozca la tabla MBR que estamos por escribir.
        long head = Math.Min(1024L * 1024, diskBytes);
        Zero(disk, 0, head);
        long tail = Math.Min(1024L * 1024, diskBytes);
        Zero(disk, diskBytes - tail, tail);
        log.Add("diseño de particiones anterior borrado (primer y último MiB)");

        // 2) Tabla de particiones: una sola primaria, tipo FAT32-LBA.
        byte[] sector = new byte[layout.BytesPerSector];
        MasterBootRecord.BuildSinglePartition(sector.AsSpan(0, MasterBootRecord.Size),
                                              firstLba, layout.TotalSectors);
        disk.Position = 0;
        disk.Write(sector, 0, sector.Length);
        disk.Flush();
        log.Add($"tabla MBR escrita (1 partición, tipo 0x{MasterBootRecord.Fat32LbaType:X2})");

        // 3) Sistema de archivos, sobre una vista del disco desplazada al inicio
        //    de la partición: Fat32Formatter escribe siempre desde el byte 0 de
        //    lo que le den.
        var partition = new OffsetStream(disk, (long)firstLba * layout.BytesPerSector);
        Fat32Formatter.WriteStructures(partition, layout, label, VolumeId());
        disk.Flush(flushToDisk: true);
        log.Add("estructuras FAT32 escritas");

        // 4) Releer y comprobar lo que quedó escrito.
        //
        //    La lección del fallo en hardware: `diskpart` dijo que había
        //    limpiado el disco, salió con código 0, y no había limpiado nada —
        //    el código siguió adelante creyéndole. No se vuelve a dar por hecho
        //    que un paso destructivo funcionó: se relee y se comprueba, y si no
        //    cuadra se dice que el disco quedó en un estado desconocido en vez
        //    de reportar éxito.
        VerifyWritten(disk, firstLba, layout, log);

        // La relectura del diseño NO va acá: mientras los volúmenes sigan
        // bloqueados y desmontados, Windows no puede montar el volumen nuevo.
        // Se hace en FormatIPod, después de soltar los bloqueos.
    }

    /// <summary>
    /// Relee del disco lo que se acaba de escribir. Lanza si no coincide: un
    /// formateo que no se puede confirmar no es un formateo correcto.
    /// </summary>
    private static void VerifyWritten(FileStream disk, uint firstLba, Fat32Layout layout, List<string> log)
    {
        byte[] sector = new byte[layout.BytesPerSector];

        disk.Position = 0;
        disk.ReadExactly(sector);
        if (!MasterBootRecord.HasValidSignature(sector))
        {
            throw new IOException("la tabla de particiones no quedó escrita (falta su firma)");
        }
        MbrPartitionEntry entry = MasterBootRecord.ReadEntry(sector, 0);
        if (entry.Type != MasterBootRecord.Fat32LbaType
            || entry.FirstLba != firstLba
            || entry.SectorCount != layout.TotalSectors)
        {
            throw new IOException("la tabla de particiones que quedó en el disco no es la que se escribió");
        }
        if (MasterBootRecord.UsedEntryCount(sector) != 1)
        {
            throw new IOException("quedó más de una partición en la tabla");
        }

        disk.Position = (long)firstLba * layout.BytesPerSector;
        disk.ReadExactly(sector);
        if (sector[510] != 0x55 || sector[511] != 0xAA)
        {
            throw new IOException("el sector de arranque del FAT32 no quedó escrito");
        }

        log.Add("relectura: tabla de particiones y sector de arranque FAT32 verificados en el disco");
    }

    /// <summary>Pone en cero una región del disco, en bloques para no hacer una escritura enorme.</summary>
    private static void Zero(FileStream disk, long offset, long length)
    {
        if (offset < 0 || length <= 0) return;
        byte[] zeros = new byte[64 * 1024];
        disk.Position = offset;
        long written = 0;
        while (written < length)
        {
            int chunk = (int)Math.Min(zeros.Length, length - written);
            disk.Write(zeros, 0, chunk);
            written += chunk;
        }
        disk.Flush();
    }

    /// <summary>Número de serie del volumen, como lo hace todo formateador: de la hora actual.</summary>
    private static uint VolumeId()
    {
        DateTime now = DateTime.Now;
        return (uint)((now.Month << 24) | (now.Day << 16) | (now.Hour << 8) | now.Minute)
             ^ (uint)((now.Year << 16) | (now.Second << 8) | now.Millisecond / 10);
    }

    // MARK: - Servicio de Apple

    private static PrivilegedOperationResult SetAppleService(bool start, List<string> log)
    {
        try
        {
            using var service = new ServiceController(AppleDeviceSupport.ServiceName);
            ServiceControllerStatus status = service.Status;
            log.Add($"servicio «{AppleDeviceSupport.ServiceName}»: {status}");

            if (start)
            {
                if (status is ServiceControllerStatus.Running or ServiceControllerStatus.StartPending)
                {
                    // Se borra igual: puede haber quedado programada de una
                    // corrida anterior que sí lo detuvo.
                    RemoveResumeGuard(log);
                    return PrivilegedOperationResult.Ok("El servicio de Apple ya estaba en marcha.", log);
                }
                service.Start();
                service.WaitForStatus(ServiceControllerStatus.Running, TimeSpan.FromSeconds(20));
                RemoveResumeGuard(log);
                return PrivilegedOperationResult.Ok("Se volvió a arrancar el servicio de Apple.", log);
            }

            if (status is ServiceControllerStatus.Stopped or ServiceControllerStatus.StopPending)
            {
                return PrivilegedOperationResult.Ok("El servicio de Apple ya estaba detenido.", log);
            }
            if (!service.CanStop)
            {
                return PrivilegedOperationResult.Failure("El servicio de Apple no se puede detener.", log);
            }

            // ST-169: PRIMERO la red, DESPUÉS el salto. Si no se pudo programar
            // la reactivación, no se detiene nada: dejar el servicio caído sin
            // forma de que vuelva —si esta app se muere entre una cosa y la
            // otra— le quita al usuario iTunes y Dispositivos Apple sin que
            // tenga forma de adivinar por qué.
            if (!AppleServiceGuard.CanPause(ScheduleResumeGuard(log)))
            {
                return PrivilegedOperationResult.Failure(
                    "No se pudo preparar la reactivación automática, así que no se detuvo ningún servicio.",
                    log);
            }

            service.Stop();
            service.WaitForStatus(ServiceControllerStatus.Stopped, TimeSpan.FromSeconds(20));
            return PrivilegedOperationResult.Ok("Se detuvo el servicio de Apple durante el grabado.", log);
        }
        catch (InvalidOperationException)
        {
            // El servicio no existe: sin iTunes ni "Dispositivos Apple" instalados.
            // No es un fallo — no hay nada que pausar.
            log.Add("el servicio de Apple no está instalado");
            return PrivilegedOperationResult.Ok("No hay servicio de Apple que pausar en este equipo.", log);
        }
        catch (System.ServiceProcess.TimeoutException)
        {
            return PrivilegedOperationResult.Failure(
                "El servicio de Apple no respondió a tiempo.", log);
        }
    }

    // MARK: - La red de ST-169

    /// <summary>
    /// Programa la reactivación del servicio para dentro de
    /// <see cref="AppleServiceGuard.ResumeAfterMinutes"/> minutos. Devuelve si
    /// quedó programada — y quien llama <b>no debe pausar</b> si no.
    ///
    /// <para>Corre acá, dentro de la operación elevada que va a pausar, y no en
    /// una segunda: registrar una tarea que corre como SYSTEM necesita permisos
    /// de administrador, y pedirlos aparte sería un segundo diálogo por lo
    /// mismo. Que sea la misma elevación es lo que hace que "primero la red"
    /// sea literal.</para>
    /// </summary>
    private static bool ScheduleResumeGuard(List<string> log)
    {
        string xmlPath = Path.Combine(Path.GetTempPath(),
            $"aura-guardian-{Guid.NewGuid():N}.xml");

        try
        {
            // El Programador espera el XML en UTF-16, que es lo que declara la
            // propia definición.
            File.WriteAllText(
                xmlPath,
                AppleServiceGuard.TaskXml(AppleServiceGuard.FiresAt(DateTimeOffset.Now),
                                          AppleDeviceSupport.ServiceName),
                new UnicodeEncoding(bigEndian: false, byteOrderMark: true));

            (int exitCode, string output) = RunSchtasks(AppleServiceGuard.CreateArguments(xmlPath));
            log.Add($"programar la reactivación: código {exitCode}");
            if (output.Length > 0) log.Add(output);

            return exitCode == 0;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException
                                      or System.ComponentModel.Win32Exception)
        {
            log.Add($"no se pudo programar la reactivación: {ex.Message}");
            return false;
        }
        finally
        {
            try { if (File.Exists(xmlPath)) File.Delete(xmlPath); }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { }
        }
    }

    /// <summary>
    /// Borra la tarea al reanudar por el camino normal. Que falle no puede
    /// tapar el resultado real —el servicio ya volvió, que es lo que importa—;
    /// queda en la bitácora.
    /// </summary>
    private static void RemoveResumeGuard(List<string> log)
    {
        try
        {
            (int exitCode, string output) = RunSchtasks(AppleServiceGuard.DeleteArguments());
            // Código 1 con "no existe" es lo normal: nadie la había programado.
            log.Add($"borrar la reactivación programada: código {exitCode}");
            if (output.Length > 0) log.Add(output);
        }
        catch (Exception ex) when (ex is IOException or System.ComponentModel.Win32Exception)
        {
            log.Add($"no se pudo borrar la reactivación programada: {ex.Message}");
        }
    }

    private static (int ExitCode, string Output) RunSchtasks(string arguments)
    {
        var psi = new ProcessStartInfo("schtasks.exe", arguments)
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        };

        using Process? process = Process.Start(psi);
        if (process is null) return (-1, "no se pudo ejecutar schtasks.exe");

        string output = process.StandardOutput.ReadToEnd() + process.StandardError.ReadToEnd();
        process.WaitForExit(TimeSpan.FromSeconds(30));

        return (process.HasExited ? process.ExitCode : -1, output.Trim());
    }
}

/// <summary>
/// Vista de un <see cref="Stream"/> desplazada: la posición 0 de esta es la
/// posición <c>offset</c> de la de abajo.
///
/// Existe para que <c>Fat32Formatter</c> no tenga que saber nada de particiones
/// ni de discos: escribe siempre desde el byte 0 de lo que le den, y acá se le
/// da la partición. Solo escritura y posicionamiento — es todo lo que hace falta.
/// </summary>
internal sealed class OffsetStream : Stream
{
    private readonly Stream _inner;
    private readonly long _offset;

    public OffsetStream(Stream inner, long offset)
    {
        if (offset < 0) throw new ArgumentOutOfRangeException(nameof(offset));
        _inner = inner;
        _offset = offset;
    }

    public override bool CanRead => _inner.CanRead;
    public override bool CanSeek => _inner.CanSeek;
    public override bool CanWrite => _inner.CanWrite;
    public override long Length => Math.Max(0, _inner.Length - _offset);

    public override long Position
    {
        get => _inner.Position - _offset;
        set => _inner.Position = checked(_offset + value);
    }

    public override void Flush() => _inner.Flush();
    public override int Read(byte[] buffer, int offset, int count) => _inner.Read(buffer, offset, count);
    public override void Write(byte[] buffer, int offset, int count) => _inner.Write(buffer, offset, count);
    public override void SetLength(long value) => throw new NotSupportedException();

    public override long Seek(long offset, SeekOrigin origin) => origin switch
    {
        SeekOrigin.Begin => _inner.Seek(_offset + offset, SeekOrigin.Begin) - _offset,
        SeekOrigin.Current => _inner.Seek(offset, SeekOrigin.Current) - _offset,
        SeekOrigin.End => _inner.Seek(offset, SeekOrigin.End) - _offset,
        _ => throw new ArgumentOutOfRangeException(nameof(origin))
    };
}