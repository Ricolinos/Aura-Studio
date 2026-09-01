using AuraStudio.Core;

namespace AuraStudio.App.Platform;

/// <summary>
/// Enriquece el candidato ya identificado con lo que se lee del volumen
/// montado (equivalente del AuraDeviceProbe de macOS). Dos hechos que NUNCA
/// se fusionan (ST-016): qué firmware atiende el USB ahora (sale SOLO de los
/// descriptores USB) y qué archivos hay en el disco (aura.cfg y capacidades).
/// </summary>
internal static class VolumeProbe
{
    public static IPodDiskInfo Build(WindowsDiskCandidate disk)
    {
        var candidate = disk.Candidate;

        // La única lectura real de "qué corre": los descriptores USB.
        RunningFirmware running = candidate.USB?.RunningFirmware
            ?? RunningFirmware.Classify(candidate.Vendor, candidate.Model);

        bool hasAuraConfig = false;
        int? syncMarkerVersion = null;
        int? themeFormat = null;
        FirmwareFamily? declaredFamily = null;
        FirmwareTreeFacts tree = FirmwareTreeFacts.None;
        long totalBytes = 0;
        long freeBytes = 0;
        string fileSystem = "";
        CatalogSummary? librarySummary = null;

        if (disk.VolumePath is string root && root.Length > 0)
        {
            try
            {
                var drive = new DriveInfo(root);
                if (drive.IsReady)
                {
                    totalBytes = drive.TotalSize;
                    freeBytes = drive.AvailableFreeSpace;
                    fileSystem = drive.DriveFormat;
                }

                string summaryPath = Path.Combine(root, ".rockbox", "aura", "sync_summary.cfg");
                if (File.Exists(summaryPath))
                {
                    string summaryText = File.ReadAllText(summaryPath);
                    librarySummary = CatalogSummaryReader.Parse(summaryText);
                }

                // Qué archivos hay en el disco: hecho aparte del USB (ST-016).
                tree = FirmwareTreeProbe.Probe(root);

                hasAuraConfig = File.Exists(Path.Combine(root, FirmwareCapabilities.AuraConfigRelativePath));
                if (hasAuraConfig)
                {
                    // Solo con aura.cfg presente: sin él, DeclaredFamily
                    // devolvería Aura por contrato (la ausencia de la clave es
                    // la firma de Aura) y un volumen vacío reportaría familia.
                    syncMarkerVersion = FirmwareCapabilities.SupportedSyncMarkerVersion(root);
                    themeFormat = FirmwareCapabilities.SupportedThemeFormat(root);
                    declaredFamily = FirmwareCapabilities.DeclaredFamily(root);
                }
            }
            catch
            {
                // El volumen puede desmontarse a mitad de la lectura: se
                // reporta el disco sin capacidades en vez de fallar.
            }
        }

        return new IPodDiskInfo
        {
            DevicePath = disk.DevicePath,
            VolumePath = disk.VolumePath ?? "",
            VolumeName = candidate.VolumeName ?? "",
            SizeBytes = totalBytes > 0 ? totalBytes : candidate.SizeBytes,
            UsedBytes = Math.Max(0, totalBytes - freeBytes),
            FreeBytes = freeBytes,
            FileSystem = fileSystem,
            LibrarySummary = librarySummary,
            USBIdentity = candidate.USB,
            RunningFirmware = running,
            DeclaredFamily = declaredFamily,
            HasAuraConfig = hasAuraConfig,
            Firmware = tree.Firmware,
            OriginalFirmwarePresent = tree.OriginalFirmwarePresent,
            SupportedSyncMarkerVersion = syncMarkerVersion,
            SupportedThemeFormat = themeFormat
        };
    }
}
