namespace AuraStudio.Core;

/// <summary>
/// Información del iPod detectado para mostrar en la UI.
/// Agrega al DiskCandidateInfo los campos derivados (firmware, familia, etc.)
/// que se obtienen leyendo el volumen montado.
/// </summary>
public sealed record IPodDiskInfo
{
    public string DevicePath { get; init; } = "";           // p.ej. "\.\PhysicalDrive2" o "/dev/disk2"
    public string VolumePath { get; init; } = "";           // p.ej. "E:\" o "/Volumes/IPOD"
    public string VolumeName { get; init; } = "";
    public long SizeBytes { get; init; }
    /// <summary>Bytes usados y libres del volumen, cuando Windows pudo montarlo.</summary>
    public long UsedBytes { get; init; }
    public long FreeBytes { get; init; }
    public string FileSystem { get; init; } = "";
    public CatalogSummary? LibrarySummary { get; init; }
    public USBDeviceIdentity? USBIdentity { get; init; }
    public RunningFirmware RunningFirmware { get; init; } = RunningFirmware.Unknown;
    public FirmwareFamily? DeclaredFamily { get; init; }
    public bool HasAuraConfig { get; init; }
    public int? SupportedSyncMarkerVersion { get; init; }
    public int? SupportedThemeFormat { get; init; }

    /// <summary>
    /// Qué firmware hay EN EL DISCO (archivos), con su evidencia de arranque.
    /// Hecho separado de <see cref="RunningFirmware"/> a propósito (ST-016).
    /// </summary>
    public InstalledFirmware Firmware { get; init; } = InstalledFirmware.Empty;

    /// <summary>`iPod_Control/` presente: el firmware original de Apple está en el disco.</summary>
    public bool OriginalFirmwarePresent { get; init; }

    /// <summary>
    /// Cómo se llama este iPod en pantalla: "iPod Classic (IPOD)".
    ///
    /// <para><b>Sin el firmware pegado atrás.</b> Antes terminaba en
    /// <c>- {RunningFirmware}</c>, y eso imprimía el nombre del enum
    /// —"RockboxFamily"— en el título de General, en la barra de estado y en el
    /// destino de la sincronización. Qué firmware corre se dice con palabras, y
    /// eso es trabajo de <see cref="FirmwareSummary"/> (R3-3).</para>
    /// </summary>
    public string DisplayName => $"iPod Classic ({(string.IsNullOrWhiteSpace(VolumeName) ? VolumePath : VolumeName)})";

    /// <summary>La frase que explica qué firmware tiene, en español y sin jerga.</summary>
    public string FirmwareSummary => DeviceFirmwareLabel.For(this);

    public bool IsMounted => !string.IsNullOrWhiteSpace(VolumePath);
    public string CapacityDisplay => FormatBytes(SizeBytes);
    public string UsedDisplay => FormatBytes(UsedBytes);
    public string FreeDisplay => FormatBytes(FreeBytes);
    public bool HasLibrarySummary => LibrarySummary.HasValue;
    public string FirmwareDisplay => DeclaredFamily is null
        ? (HasAuraConfig ? "Archivos Aura detectados (familia no declarada)" : "No se detectó una instalación Aura")
        : DeclaredFamily.DisplayName;
    public string SummaryMusicDisplay => SummaryValue(LibrarySummary?.Music);
    public string SummaryVideoDisplay => SummaryValue(LibrarySummary?.Video);
    public string SummaryPhotoDisplay => SummaryValue(LibrarySummary?.Photo);
    public string SummaryPlaylistsDisplay => LibrarySummary?.PlaylistCount.ToString() ?? "—";

    private static string SummaryValue(CatalogTypeSummary? value) => value is null
        ? "—"
        : $"{value.Value.Count} ({FormatBytes(value.Value.Bytes)})";

    private static string FormatBytes(long bytes) => bytes <= 0 ? "0 B" :
        bytes switch
        {
            >= 1_000_000_000_000 => $"{bytes / 1_000_000_000_000d:0.0} TB",
            >= 1_000_000_000 => $"{bytes / 1_000_000_000d:0.0} GB",
            >= 1_000_000 => $"{bytes / 1_000_000d:0.0} MB",
            >= 1_000 => $"{bytes / 1_000d:0.0} KB",
            _ => $"{bytes} B"
        };

    /// <summary>
    /// Un firmware que habla el contrato de biblioteca de Aura está instalado
    /// DE VERDAD: su árbol está en el disco Y hay evidencia de que corre acá
    /// — o está atendiendo el USB ahora mismo (lectura real), o ya arrancó
    /// alguna vez y dejó su rastro. Es lo que habilita biblioteca, sync,
    /// temas y nombre del iPod. Archivos copiados a mano sin ninguna de las
    /// dos cosas NO cuentan (ST-016).
    ///
    /// **CAPACIDAD, no identidad** (ST-046): es `true` también para
    /// Metro-Aura, que implementa el mismo §D del contrato. Para preguntar
    /// "¿es Aura?" está <see cref="IsAuraFirmware"/>. La propiedad anterior
    /// se llamaba `IsAura` y era justo esa trampa.
    /// </summary>
    public bool SupportsAuraContract =>
        Firmware.Kind == InstalledFirmwareKind.Aura
        && (Firmware.HasBooted || RunningFirmware == RunningFirmware.RockboxFamily);

    /// <summary>
    /// Aura, la de verdad: habla el contrato Y se declara Aura. Condición
    /// para ofrecerle actualizaciones del Release de Aura-Firmware y para
    /// llamarlo "Aura" en la interfaz.
    /// </summary>
    public bool IsAuraFirmware => SupportsAuraContract && Equals(DeclaredFamily, FirmwareFamily.Aura);

    /// <summary>
    /// Evidencia de que un firmware de la familia Rockbox CORRE en este
    /// aparato (y por lo tanto de que hay un bootloader de esa familia en la
    /// NOR): atiende el USB ahora, o dejó rastro de haber arrancado. La NOR
    /// en sí no se puede leer desde una PC.
    /// </summary>
    public bool RockboxFamilyVerified =>
        RunningFirmware == RunningFirmware.RockboxFamily || Firmware.HasBooted;

    /// <summary>
    /// Ambos firmwares conviven Y el de la familia Rockbox tiene evidencia de
    /// arrancar. Sin esa evidencia no se afirma "dual boot" (ST-016).
    /// </summary>
    public bool IsDualBoot => RockboxFamilyVerified && OriginalFirmwarePresent;

    /// <summary>
    /// ST-065: el firmware activo anuncia `theme_format_supported` en
    /// `aura.cfg` — tiene sistema de temas (Aura, Metro). moonlit.aura no lo
    /// publica. Capacidad, no identidad (misma regla que
    /// <see cref="SupportsAuraContract"/>).
    /// </summary>
    public bool ThemeFormatSupported => SupportedThemeFormat is not null;

    /// <summary>True si es un iPod Classic válido (VID/PID correcto).</summary>
    public bool IsValidIPod => USBIdentity?.IsIPodClassicUSB == true;

    /// <summary>
    /// Con qué nombre se anota este iPod en el registro de arranques
    /// verificados (ST-166). <c>null</c> cuando no hay con qué identificarlo:
    /// entonces no se anota nada y tampoco se ofrece actualizar el arranque
    /// (ver <see cref="BootloaderRegistry.CanTrack"/>).
    ///
    /// <para><b>El serial USB, y no el volumen.</b> Es una divergencia
    /// deliberada con macOS, que usa <c>volumeUUID ?? serial</c>: acá el serial
    /// ya se lee del <c>PNPDeviceID</c> (<see cref="PnpDeviceId"/>), identifica
    /// al aparato y —a diferencia del volumen— <b>sobrevive a un formateo</b>,
    /// que es justo lo que hace una instalación. Con el UUID del volumen
    /// primero, la clave de un iPod cambiaría justo después de grabarle el
    /// arranque que se acaba de anotar.</para>
    /// </summary>
    public string? DiskRecordKey =>
        USBIdentity?.SerialNumber?.Trim() is { Length: > 0 } serial ? serial : null;
}
