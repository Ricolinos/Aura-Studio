namespace AuraStudio.Core;

/// <summary>
/// Qué firmware hay EN EL DISCO (archivos), con la evidencia de arranque que
/// cada uno deja. Port de <c>AuraDevice.Firmware</c> del macOS.
///
/// Es el primero de los tres hechos que NUNCA se fusionan (ST-016):
/// 1) qué archivos hay en el disco (esto), 2) qué firmware atiende el USB
/// ahora (<see cref="RunningFirmware"/>, la única lectura real), y 3) qué
/// dice el firmware de sí mismo (<see cref="FirmwareFamily"/>).
/// </summary>
public enum InstalledFirmwareKind
{
    /// <summary>Ni `iPod_Control/` ni rastro de Rockbox: disco recién formateado.</summary>
    Empty,

    /// <summary>`iPod_Control/` y sin rastro de Rockbox: el firmware original de Apple.</summary>
    Stock,

    /// <summary>Un `.rockbox/` sin rastro de Aura: una instalación de Rockbox común.</summary>
    Rockbox,

    /// <summary>Árbol de la familia Aura (Aura, Metro-Aura, moonlit.aura).</summary>
    Aura
}

/// <summary>
/// El firmware instalado en el disco y si dejó rastro de haber arrancado
/// alguna vez ahí. `HasBooted` es evidencia dura: son archivos que SOLO
/// escribe un firmware corriendo (`.rockbox/aura/aura.cfg`,
/// `.rockbox/.resume.cfg`, `.rockbox/config.cfg`) — ninguno viene en el zip
/// que copia el instalador.
/// </summary>
public readonly record struct InstalledFirmware(InstalledFirmwareKind Kind, bool HasBooted)
{
    public static InstalledFirmware Empty { get; } = new(InstalledFirmwareKind.Empty, false);

    /// <summary>Hay un árbol de la familia Rockbox (Aura o Rockbox común) en el disco. Solo habla de archivos.</summary>
    public bool IsRockboxFamilyTree => Kind is InstalledFirmwareKind.Rockbox or InstalledFirmwareKind.Aura;
}

/// <summary>
/// Lo que se puede afirmar del disco mirando SOLO qué archivos hay.
/// </summary>
/// <param name="Firmware">Firmware de la familia Rockbox / original / vacío.</param>
/// <param name="OriginalFirmwarePresent">
/// `iPod_Control/` presente — la mitad en disco de la detección de dual boot
/// (la otra mitad es evidencia de que el firmware de la familia Rockbox
/// corre de verdad, que no sale de archivos).
/// </param>
public readonly record struct FirmwareTreeFacts(InstalledFirmware Firmware, bool OriginalFirmwarePresent)
{
    public static FirmwareTreeFacts None { get; } = new(InstalledFirmware.Empty, false);
}

/// <summary>
/// Clasifica el árbol del volumen montado. Port literal de
/// <c>AuraDeviceProbe.probe</c> (macOS) en lo que toca a archivos: mismas
/// rutas, mismo orden de decisión.
///
/// No lee descriptores USB ni `aura.cfg`: esto responde una sola pregunta
/// ("qué hay copiado acá") y se mantiene aparte de las otras dos a propósito.
/// </summary>
public static class FirmwareTreeProbe
{
    public const string FirmwareBinaryName = "rockbox.ipod";
    public const string RockboxDirName = ".rockbox";
    public const string AuraDirRelativePath = ".rockbox/aura";

    /// <summary>
    /// Marcador de instalación de Aura que Studio SIEMPRE deja (los iconos del
    /// design system viajan en el árbol `.rockbox` desde D-178) — a diferencia
    /// de `.rockbox/aura/`, que lo crea el firmware al arrancar por primera vez.
    /// </summary>
    public const string AuraIconsRelativePath = ".rockbox/icons/aura";

    /// <summary>
    /// Rastro de un Rockbox (Aura incluida) que ya corrió. Ninguno de los dos
    /// viene en `rockbox.zip`: si están, ese firmware arrancó en este disco.
    /// </summary>
    public const string RockboxResumeRelativePath = ".rockbox/.resume.cfg";
    public const string RockboxConfigRelativePath = ".rockbox/config.cfg";

    /// <summary>
    /// Carpeta del firmware original de Apple. Su presencia distingue
    /// "firmware original" de "disco recién formateado".
    /// </summary>
    public const string IPodControlDirName = "iPod_Control";

    /// <summary>
    /// Clasifica el árbol de <paramref name="volumeRoot"/>. Una ruta vacía o
    /// un directorio que no existe devuelve <see cref="FirmwareTreeFacts.None"/>
    /// — nunca se resuelve contra el directorio de trabajo del proceso
    /// (D-070: esa ruta vacía terminó apuntando al disco de arranque).
    /// </summary>
    public static FirmwareTreeFacts Probe(string volumeRoot)
    {
        if (string.IsNullOrWhiteSpace(volumeRoot)) return FirmwareTreeFacts.None;
        if (!Directory.Exists(volumeRoot)) return FirmwareTreeFacts.None;

        bool Exists(string relative)
        {
            string full = Path.Combine(volumeRoot, relative.Replace('/', Path.DirectorySeparatorChar));
            return File.Exists(full) || Directory.Exists(full);
        }

        bool originalPresent = Exists(IPodControlDirName);
        bool rockboxBooted = Exists(RockboxResumeRelativePath) || Exists(RockboxConfigRelativePath);

        InstalledFirmware firmware;
        if (Exists(AuraDirRelativePath) || Exists(AuraIconsRelativePath))
        {
            firmware = new InstalledFirmware(InstalledFirmwareKind.Aura,
                                             Exists(FirmwareCapabilities.AuraConfigRelativePath));
        }
        else if (Exists(FirmwareBinaryName))
        {
            // Binario copiado pero el firmware nunca escribió nada suyo:
            // instalación recién hecha, todavía sin arrancar.
            firmware = new InstalledFirmware(InstalledFirmwareKind.Aura, false);
        }
        else if (Exists(RockboxDirName))
        {
            firmware = new InstalledFirmware(InstalledFirmwareKind.Rockbox, rockboxBooted);
        }
        else if (originalPresent)
        {
            firmware = new InstalledFirmware(InstalledFirmwareKind.Stock, false);
        }
        else
        {
            firmware = InstalledFirmware.Empty;
        }

        return new FirmwareTreeFacts(firmware, originalPresent);
    }
}
