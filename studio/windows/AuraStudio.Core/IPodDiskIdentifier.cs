namespace AuraStudio.Core;

/// <summary>
/// Snapshot de un disco candidato, con solo los campos que hacen falta
/// para decidir si es "el iPod" — deliberadamente un tipo de datos plano
/// (no atado a ninguna API de disco del sistema) para que la lógica de
/// coincidencia sea una función pura, testeable con datos sintéticos sin
/// necesitar hardware real ni permisos en los tests.
/// </summary>
public sealed record DiskCandidateInfo(
    string BSDName,
    string Vendor,
    string Model,
    bool IsRemovable,
    bool IsInternal,
    long SizeBytes,
    string? VolumeName,
    USBDeviceIdentity? USB = null)
{
    /// <summary>
    /// Criterios de seguridad para decidir si un disco es "el iPod".
    ///
    /// Obligatorios siempre: removible y externo — el SSD interno del propio
    /// Mac reporta "APPLE SSD" en su modelo, así que sin esto se confundiría
    /// con el disco de arranque (paso de verdad, ver D-070).
    ///
    /// Además hace falta UNA de estas señales de dispositivo:
    ///  - que el par VID/PID USB sea el del iPod Classic (0x05AC/0x1261) — la
    ///    señal exacta: la única que sigue valiendo cuando el USB lo atiende
    ///    Aura/Rockbox, donde el INQUIRY SCSI ya no dice "Apple"/"iPod".
    ///  - que el modelo diga "iPod" — alcanza por sí sola, sin exigir vendor
    ///    "Apple" (el bootloader en "Bootloader USB mode" NO reporta vendor).
    ///  - que el vendor sea Apple Y el tamaño caiga en el rango del 120GB de
    ///    fábrica, para el caso donde el nombre de media era el del disco
    ///    duro interno ("HS12YHA") y no decía "iPod".
    ///
    /// El tamaño NUNCA puede ser el único criterio duro: los iPod Classic con
    /// el disco cambiado por flash (iFlash + SD) van de 32GB a 2TB.
    /// </summary>
    public bool MatchesIPodCriteria
    {
        get
        {
            if (!IsRemovable || IsInternal) return false;
            if (SizeBytes < IPodDiskIdentifier.MinPlausibleSize || SizeBytes > IPodDiskIdentifier.MaxPlausibleSize)
                return false;

            if (USB?.IsIPodClassicUSB == true) return true;
            if (Model.Contains("iPod", StringComparison.OrdinalIgnoreCase)) return true;

            if (!Vendor.Contains("Apple", StringComparison.OrdinalIgnoreCase)) return false;
            long diff = Math.Abs(SizeBytes - IPodDiskIdentifier.NominalSizeBytes);
            return diff <= IPodDiskIdentifier.SizeToleranceBytes;
        }
    }
}

/// <summary>
/// Resultado de la identificación. Un disco valido, ninguno, o dos o más a
/// la vez — la regla de seguridad es no elegir "el más probable" nunca, sino
/// negarse a continuar y que el usuario desconecte los demás.
/// </summary>
public abstract record DiskIdentificationResult
{
    public sealed record NotFound : DiskIdentificationResult;
    public sealed record Found(DiskCandidateInfo Candidate) : DiskIdentificationResult;
    public sealed record Ambiguous(IReadOnlyList<DiskCandidateInfo> Candidates) : DiskIdentificationResult;
}

public static class IPodDiskIdentifier
{
    /// <summary>
    /// iPod Classic 6G de 120GB: el tamaño reportado real es
    /// 120,034,123,776 bytes — se usa 120GB decimal como nominal con margen
    /// generoso, porque el tamaño exacto puede variar unos MB según el
    /// firmware del propio disco.
    /// </summary>
    public const long NominalSizeBytes = 120_000_000_000;
    public const long SizeToleranceBytes = 5_000_000_000;

    /// <summary>
    /// Rango de tamaños que puede tener un iPod Classic 6G real, de fábrica o
    /// con el disco cambiado por flash. Sirve de cota de cordura, no de
    /// identificación por sí sola.
    /// </summary>
    public const long MinPlausibleSize = 8_000_000_000;
    public const long MaxPlausibleSize = 2_100_000_000_000;

    /// <summary>
    /// Lógica pura: dado el snapshot actual de discos externos, decide si hay
    /// exactamente un candidato válido, ninguno, o más de uno (ambiguo). No
    /// toca disco, no hace I/O — 100% testeable.
    /// </summary>
    public static DiskIdentificationResult Identify(IReadOnlyList<DiskCandidateInfo> candidates)
    {
        var matches = candidates.Where(c => c.MatchesIPodCriteria).ToList();
        return matches.Count switch
        {
            0 => new DiskIdentificationResult.NotFound(),
            1 => new DiskIdentificationResult.Found(matches[0]),
            _ => new DiskIdentificationResult.Ambiguous(matches)
        };
    }
}
