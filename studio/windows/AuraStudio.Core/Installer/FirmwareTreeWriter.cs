using System.IO.Compression;

namespace AuraStudio.Core.Installer;

/// <summary>Avance de la escritura del firmware, para la barra de progreso y el texto de estado.</summary>
/// <param name="Message">Qué está pasando, en español, listo para mostrar.</param>
/// <param name="Fraction">0…1 cuando hay una medición útil; <c>null</c> = indeterminado (la UI muestra un anillo).</param>
public readonly record struct FirmwareWriteProgress(string Message, double? Fraction);

/// <summary>Cómo terminó la escritura.</summary>
/// <param name="FilesWritten">Archivos realmente escritos en el iPod.</param>
/// <param name="UsedSelectiveUpdate">Se aplicó el delta del manifiesto (v11) en vez de extraer el zip completo.</param>
/// <param name="ParkedFamily">Familia que se estacionó como árbol dormido, si hubo cambio de familia.</param>
public sealed record FirmwareWriteResult(int FilesWritten, bool UsedSelectiveUpdate, FirmwareFamily? ParkedFamily);

/// <summary>
/// Escribe el firmware en el volumen del iPod: <c>rockbox.ipod</c> en la raíz (lo
/// que el bootloader arranca) y el árbol <c>.rockbox/</c> completo del zip
/// (fuentes, iconos/máscaras, códecs, plugins — D-045, cerrado en D-178: sin ese
/// árbol el firmware arranca pero sin tipografías ni iconos, confirmado en
/// hardware real). Port de <c>InstallerViewModel.copyFirmwareFiles</c> (macOS), sin
/// la parte de UI.
///
/// La extracción es un <b>merge</b> (nunca borra lo que ya está): reinstalar
/// encima NO pierde <c>aura.cfg</c> ni la caché de carátulas. Vive en Core y no en
/// <c>Platform/</c> porque no usa ninguna API de Windows: es I/O de archivos y
/// zip, y así se puede probar entero contra directorios temporales.
///
/// macOS extrae con <c>/usr/bin/ditto -xkV</c> y cuenta las líneas que el
/// subproceso escribe a stderr para la barra de progreso. Acá se usa
/// <c>ZipArchive</c> directo: el progreso sale de contar entradas escritas, que es
/// la misma medida (D-191: con 7 800 archivos chicos cada uno cuesta casi lo mismo
/// —una ida y vuelta USB— sin importar su tamaño, así que medir bytes hacía que la
/// barra llegara a 99 % en los primeros segundos y se quedara quieta minutos).
/// </summary>
public static class FirmwareTreeWriter
{
    /// <summary>
    /// Carpetas de medios que se crean vacías al instalar (D-194). Reporte del
    /// dueño en hardware real: podía copiar música/fotos/video al iPod en modo
    /// disco y el firmware no los reconocía, porque la carpeta con el nombre
    /// exacto que el firmware busca no existía y él la creaba a mano con otro
    /// nombre. Crearlas de antemano hace el destino obvio en el Explorador.
    /// </summary>
    public static readonly IReadOnlyList<string> MediaFolders = ["Music", "Photos", "Videos", "Playlists"];

    /// <summary>
    /// Umbral de sensatez del delta (v11): con más de un cuarto del zip por
    /// escribir, la extracción completa es igual de rápida y más simple de razonar.
    /// </summary>
    public static bool DeltaIsWorthIt(InstallManifestDelta delta, int totalEntries) =>
        delta.ToExtract.Count + delta.ToDelete.Count <= Math.Max(50, totalEntries / 4);

    /// <param name="volumeRoot">Raíz del volumen del iPod, ya re-verificada por quien llama.</param>
    /// <param name="artifacts">Artefactos del firmware; se re-verifican acá antes de escribir nada.</param>
    /// <param name="targetFamily">Familia que se está instalando.</param>
    /// <param name="installedFamily">
    /// Familia que el iPod tiene instalada de verdad (<c>SupportsAuraContract</c>),
    /// o <c>null</c> si no hay ninguna con evidencia. Decide si esto es una
    /// actualización de la misma familia (delta posible) o un cambio de familia
    /// (se estaciona el árbol saliente y se extrae completo).
    /// </param>
    public static async Task<FirmwareWriteResult> WriteAsync(
        string volumeRoot,
        FirmwareArtifacts artifacts,
        FirmwareFamily targetFamily,
        FirmwareFamily? installedFamily,
        IProgress<FirmwareWriteProgress>? progress = null,
        CancellationToken ct = default)
    {
        string firmwarePath = artifacts.Find("rockbox.ipod")
            ?? throw new InstallerException(new InstallerError.MissingArtifact("rockbox.ipod"));
        string zipPath = artifacts.Find("rockbox.zip")
            ?? throw new InstallerException(new InstallerError.MissingArtifact("rockbox.zip"));

        if (!Directory.Exists(volumeRoot))
        {
            throw new InstallerException(new InstallerError.DeviceDisconnectedDuringCopy());
        }

        progress?.Report(new("Verificando integridad de los archivos…", null));
        ArtifactVerificationResult verification =
            FirmwareArtifactVerifier.Verify(artifacts, ArtifactScope.FirmwareTree);
        if (!verification.IsValid)
        {
            throw new InstallerException(
                new InstallerError.ChecksumMismatch(string.Join(" ", verification.Errors)));
        }

        // ST-056 / contrato v10: CAMBIO de familia. El árbol activo NO se borra ni
        // se pisa — se ESTACIONA como /.firmware-<saliente>/, entero y con sus
        // ajustes, listo para despertarlo. Reinstalar la MISMA familia sigue siendo
        // un merge sobre el árbol activo, que conserva los ajustes como siempre.
        FirmwareFamily? parked = null;
        bool sameFamilyUpdate = installedFamily is not null && Equals(installedFamily, targetFamily);
        if (installedFamily is { } detected && !Equals(detected, targetFamily) && detected.IsInstallable)
        {
            progress?.Report(new($"Guardando {detected.DisplayName} para poder volver a él…", null));
            FirmwareSwitcher.ParkActiveTree(detected, volumeRoot);
            parked = detected;
        }

        progress?.Report(new("Copiando el firmware al iPod…", null));
        string rootBinary = Path.Combine(volumeRoot, FirmwareSwitcher.RootFirmwareBinaryName);
        File.Copy(firmwarePath, rootBinary, overwrite: true);
        if (!File.Exists(rootBinary))
        {
            throw new InstallerException(new InstallerError.ProcessFailed(-1, "no se pudo verificar rockbox.ipod tras copiarlo"));
        }

        var newEntries = InstallManifest.EntriesFromZip(zipPath);

        // ST-058 / contrato v11: actualización SELECTIVA — comparar el manifiesto
        // del zip nuevo contra el que quedó instalado y escribir solo la
        // diferencia. Cualquier duda (sin manifiesto, delta enorme, error a mitad)
        // cae a la extracción completa de siempre.
        int written = 0;
        bool usedDelta = false;
        if (sameFamilyUpdate && InstallManifest.Read(volumeRoot) is { Entries.Count: > 0 } installed)
        {
            var delta = InstallManifest.Delta(installed.Entries, newEntries);
            if (DeltaIsWorthIt(delta, newEntries.Count))
            {
                progress?.Report(new(
                    $"Actualizando {targetFamily.DisplayName}: {delta.ToExtract.Count} archivo(s) por escribir, {delta.ToDelete.Count} por quitar…",
                    0));
                try
                {
                    written = await ApplySelectiveUpdateAsync(delta, zipPath, volumeRoot, progress, ct).ConfigureAwait(false);
                    usedDelta = true;
                }
                catch (OperationCanceledException)
                {
                    throw;
                }
                catch (Exception)
                {
                    // Ni idea de en qué quedó el árbol: extracción completa encima
                    // (merge), que lo repara todo.
                    progress?.Report(new("La actualización selectiva no pudo; instalando completo…", null));
                    usedDelta = false;
                }
            }
        }

        if (!usedDelta)
        {
            progress?.Report(new(
                $"Instalando {targetFamily.DisplayName} en el iPod (tipografías, iconos, códecs)… Puede tardar varios minutos por USB — no desconectes el iPod.",
                0));
            written = await ExtractFullAsync(zipPath, volumeRoot, newEntries.Count, progress, ct).ConfigureAwait(false);
        }

        // Centinela: un archivo que el firmware carga al arrancar — si está, el
        // árbol se extrajo bien. Por familia (ST-047): cada una trae el suyo.
        string sentinelRelative = targetFamily.InstalledTreeSentinel ?? ".rockbox/rockbox.ipod";
        string sentinel = Path.Combine(volumeRoot, sentinelRelative.Replace('/', Path.DirectorySeparatorChar));
        if (!File.Exists(sentinel))
        {
            throw new InstallerException(new InstallerError.ProcessFailed(
                -1, $"el árbol .rockbox no quedó completo tras extraerlo (falta {Path.GetFileName(sentinel)})"));
        }

        // ST-056: la familia recién instalada es la activa; un árbol dormido SUYO
        // que hubiera quedado de antes ya no tiene sentido (contrato v10: nunca un
        // dormido de la familia activa). Y el respaldo de la raíz apunta al activo.
        TryIgnoringIo(() => FirmwareSwitcher.RemoveDormantTree(targetFamily, volumeRoot));
        TryIgnoringIo(() => FirmwareSwitcher.RefreshRootBinary(volumeRoot));
        // ST-061: el árbol recién extraído hereda los archivos del contrato del
        // dormido, así el firmware nuevo arranca con contadores, fotos de artista y
        // categorías sin esperar otro sync.
        TryIgnoringIo(() => FirmwareSwitcher.SeedContractFilesToActiveTree(volumeRoot));

        // v11: dejar anotado lo que quedó instalado, para que la PRÓXIMA
        // actualización pueda ser selectiva.
        TryIgnoringIo(() => new InstallManifest { Tag = artifacts.ReleaseTag, Entries = newEntries }.Write(volumeRoot));

        foreach (string folder in MediaFolders)
        {
            TryIgnoringIo(() => Directory.CreateDirectory(Path.Combine(volumeRoot, folder)));
        }

        // ST-067: identidad del árbol antes del primer arranque — sin esto un
        // Metro/moonlit recién copiado se lee como Aura y un cambio de familia lo
        // estacionaría con el nombre equivocado.
        TryIgnoringIo(() => FirmwareCapabilities.SeedDeclaredFamily(volumeRoot, targetFamily));

        // ST-165: la tercera pata de la hora del iPod (contrato §D.4) — al
        // conectar (DeviceSessionService.SyncClockIfConnected) y al cambiar de
        // familia (FirmwareSwitcher.SwitchActiveFirmware) ya se sembraba en
        // aura.cfg; acá faltaba lo mismo justo después de instalar o
        // actualizar el árbol, simétrico a InstallerViewModel.swift de macOS.
        // Sin efecto si aura.cfg todavía no existe (nunca arrancó): no es un
        // fallo, DeviceSessionService la siembra en la próxima conexión igual.
        ClockSyncWriter.WriteToDisk(volumeRoot);

        progress?.Report(new("Listo.", 1));
        return new FirmwareWriteResult(written, usedDelta, parked);
    }

    /// <summary>
    /// ST-058: extrae del zip solo lo nuevo/cambiado y borra lo que desapareció.
    /// Lanza al primer fallo; el llamador cae a la extracción completa.
    /// </summary>
    private static async Task<int> ApplySelectiveUpdateAsync(
        InstallManifestDelta delta, string zipPath, string volumeRoot,
        IProgress<FirmwareWriteProgress>? progress, CancellationToken ct)
    {
        using var archive = ZipFile.OpenRead(zipPath);
        var byName = archive.Entries.ToDictionary(e => e.FullName, StringComparer.Ordinal);

        int total = Math.Max(1, delta.ToExtract.Count + delta.ToDelete.Count);
        int done = 0;

        foreach (string path in delta.ToExtract)
        {
            ct.ThrowIfCancellationRequested();
            if (!byName.TryGetValue(path, out var entry))
            {
                throw new InstallerException(new InstallerError.ProcessFailed(-1, $"el zip no trae {path}"));
            }
            await WriteEntryAsync(entry, volumeRoot, ct).ConfigureAwait(false);
            done++;
            progress?.Report(new($"Actualizando… ({done}/{total})", Math.Min(0.99, (double)done / total)));
        }

        foreach (string path in delta.ToDelete)
        {
            ct.ThrowIfCancellationRequested();
            string target = SafeTargetPath(volumeRoot, path);
            TryIgnoringIo(() => { if (File.Exists(target)) File.Delete(target); });
            done++;
            progress?.Report(new($"Actualizando… ({done}/{total})", Math.Min(0.99, (double)done / total)));
        }

        return delta.ToExtract.Count;
    }

    /// <summary>
    /// Extracción completa como merge: escribe todo el zip encima sin borrar nada
    /// de lo que ya hay. Un reintento automático (D-189): repetirla tras una falla
    /// transitoria es seguro y retoma justo donde quedó. Si el volumen ya no
    /// responde en absoluto, reintentar es inútil — eso se reporta como
    /// desconexión real, no como error genérico.
    /// </summary>
    private static async Task<int> ExtractFullAsync(
        string zipPath, string volumeRoot, int totalEntries,
        IProgress<FirmwareWriteProgress>? progress, CancellationToken ct)
    {
        Exception? last = null;
        for (int attempt = 1; attempt <= 2; attempt++)
        {
            try
            {
                return await ExtractOnceAsync(zipPath, volumeRoot, totalEntries, progress, ct).ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
                throw;
            }
            catch (InstallerException)
            {
                throw;
            }
            catch (Exception ex)
            {
                last = ex;
                if (!Directory.Exists(volumeRoot)) break;
                if (attempt == 2) break;
                progress?.Report(new("La copia se interrumpió — reintentando…", null));
            }
        }

        if (!Directory.Exists(volumeRoot))
        {
            throw new InstallerException(new InstallerError.DeviceDisconnectedDuringCopy());
        }
        throw new InstallerException(new InstallerError.ProcessFailed(-1, last?.Message ?? "no se pudo extraer el árbol"));
    }

    private static async Task<int> ExtractOnceAsync(
        string zipPath, string volumeRoot, int totalEntries,
        IProgress<FirmwareWriteProgress>? progress, CancellationToken ct)
    {
        using var archive = ZipFile.OpenRead(zipPath);
        int written = 0;
        int report = 0;
        foreach (var entry in archive.Entries)
        {
            ct.ThrowIfCancellationRequested();
            if (entry.FullName.EndsWith('/') || entry.Name.Length == 0)
            {
                Directory.CreateDirectory(SafeTargetPath(volumeRoot, entry.FullName.TrimEnd('/')));
                continue;
            }
            await WriteEntryAsync(entry, volumeRoot, ct).ConfigureAwait(false);
            written++;
            // Reportar cada archivo sobre 7 800 satura el hilo de UI sin aportar
            // nada visible: una de cada 25 ya se ve como una barra continua.
            if (++report % 25 == 0 && totalEntries > 0)
            {
                progress?.Report(new($"Instalando… ({written}/{totalEntries})",
                                     Math.Min(0.99, (double)written / totalEntries)));
            }
        }
        return written;
    }

    private static async Task WriteEntryAsync(ZipArchiveEntry entry, string volumeRoot, CancellationToken ct)
    {
        string target = SafeTargetPath(volumeRoot, entry.FullName);
        Directory.CreateDirectory(Path.GetDirectoryName(target)!);
        await using var input = entry.Open();
        await using var output = new FileStream(target, FileMode.Create, FileAccess.Write, FileShare.None);
        await input.CopyToAsync(output, ct).ConfigureAwait(false);
    }

    /// <summary>
    /// Una ruta del zip jamás se concatena a ciegas: se rechaza cualquier entrada
    /// absoluta o con <c>..</c>. <see cref="FirmwareArtifactVerifier"/>
    /// ya lo comprueba antes de escribir, pero el chequeo se repite en el punto
    /// exacto donde se compone la ruta — es donde importa.
    /// </summary>
    private static string SafeTargetPath(string volumeRoot, string relative)
    {
        string normalized = relative.Replace('/', Path.DirectorySeparatorChar);
        if (!FirmwareTreePlanner.IsSafeRelativePath(normalized))
        {
            throw new InstallerException(new InstallerError.ProcessFailed(
                -1, $"rockbox.zip contiene una ruta insegura ({relative})"));
        }
        return Path.Combine(volumeRoot, normalized);
    }

    private static void TryIgnoringIo(Action action)
    {
        try
        {
            action();
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or FirmwareSwitcher.SwitchException)
        {
            // Estos pasos son mejoras (sello, espejo, carpetas, identidad): que
            // fallen no invalida un firmware ya escrito y verificado por centinela.
        }
    }
}
