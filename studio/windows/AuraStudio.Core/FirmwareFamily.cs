namespace AuraStudio.Core;

/// <summary>
/// Qué familia de firmware dice ser la que está instalada, leída de la
/// clave `firmware_family` de `.rockbox/aura/aura.cfg` (contrato v8, ST-046).
///
/// Es un TERCER hecho, deliberadamente separado de los dos que ya distingue
/// <c>USBDeviceIdentity</c>/<c>RunningFirmware</c> (ST-016):
/// 1) qué ARCHIVOS hay en el disco, 2) quién atiende el USB ahora, y 3) qué
/// dice el firmware DE SÍ MISMO. Hace falta un tercero porque Metro-Aura
/// escribe en `.rockbox/aura/` exactamente igual que Aura y por USB ambos se
/// anuncian como "Rockbox.org" — sin una clave declarada Studio trataría a
/// Metro como Aura.
///
/// **La ausencia de la clave significa Aura** y eso hace el cambio
/// retrocompatible: todo iPod con Aura (incluidos los instalados antes de
/// esta versión de Studio) cae en el caso correcto sin tocar el firmware.
///
/// El Swift original es un <c>enum</c> con valor asociado para la familia
/// desconocida (<c>unknown(String)</c>, que conserva el texto crudo). Por eso
/// acá no puede ser un <c>enum</c> plano de C#: se modela como una clase con
/// instancias singleton, el mismo patrón que <c>RunningFirmware</c> ya usa en
/// este proyecto. Una familia desconocida se crea con <see cref="Unknown"/>.
/// </summary>
public sealed class FirmwareFamily : IEquatable<FirmwareFamily>
{
    /// <summary>Firmware original de Aura. Su firma es la AUSENCIA de la clave (ST-046).</summary>
    public static FirmwareFamily Aura { get; } = new("aura", null, "Aura", "Ricolinos/Aura-Firmware", ".rockbox/fonts/a26-title-20.fnt");

    /// <summary>Metro-Aura (`Ricolinos/Metro-Aura`, M-004).</summary>
    public static FirmwareFamily Metro { get; } = new("metro", "metro", "Metro", "Ricolinos/Metro-Aura", ".rockbox/fonts/metro-list-20.fnt");

    /// <summary>ST-065: tercera familia, moonlit.aura (`Ricolinos/moonlit-aura`).</summary>
    public static FirmwareFamily Moonlit { get; } = new("moonlit", "moonlit", "moonlit.aura", "Ricolinos/moonlit-aura", ".rockbox/fonts/moonlit-body-18.fnt");

    /// <summary>
    /// Las familias que esta versión de Studio trae EMBEBIDAS y por lo tanto
    /// puede instalar (ST-047/ST-065). Una familia desconocida se detecta pero
    /// no se instala. Es la ÚNICA lista de familias: todo lo que las enumera
    /// itera sobre esto.
    /// </summary>
    public static readonly IReadOnlyList<FirmwareFamily> Installable = new[] { Aura, Metro, Moonlit };

    private readonly string _raw;

    /// <summary>Valor tal como aparece en `aura.cfg`. `null` para Aura: la clave simplemente no existe.</summary>
    public string? ConfigValue { get; }

    /// <summary>Nombre de producto, para la UI.</summary>
    public string DisplayName { get; }

    /// <summary>
    /// Repositorio de GitHub (`owner/repo`) donde esta familia publica sus
    /// Releases. `null` para una familia desconocida: sin repo no hay a
    /// donde preguntar (ST-046).
    /// </summary>
    public string? ReleaseRepository { get; }

    /// <summary>
    /// Un archivo del árbol `.rockbox/` que el firmware carga al arrancar —
    /// el instalador lo usa como centinela de "el zip se extrajo completo".
    /// Cada familia trae sus propias fuentes, así que el centinela es por
    /// familia. `null` para Aura/unknown (Aura se reconoce por ausencia, no
    /// por centinela).
    /// </summary>
    public string? InstalledTreeSentinel { get; }

    public bool IsInstallable => Installable.Contains(this);

    /// <summary>
    /// Nombre del árbol dormido de esta familia en la raíz del volumen
    /// (`/.firmware-aura/`, `/.firmware-metro/`, `/.firmware-moonlit/` —
    /// contrato v10/v14 §A bis). `null` para una familia desconocida: no se
    /// estaciona ni se despierta lo que no se sabe qué es.
    /// </summary>
    public string? DormantTreeName => IsInstallable ? $".firmware-{_raw}" : null;

    private FirmwareFamily(string raw, string? configValue, string displayName, string? releaseRepository, string? sentinel)
    {
        _raw = raw;
        ConfigValue = configValue;
        DisplayName = displayName;
        ReleaseRepository = releaseRepository;
        InstalledTreeSentinel = sentinel;
    }

    /// <summary>Una familia que esta versión de Studio no conoce. Conserva el texto crudo para poder mostrarlo y para no fingir que es Aura.</summary>
    public static FirmwareFamily Unknown(string raw) => new(raw, raw, raw, null, null);

    /// <summary>
    /// Interpreta el valor crudo de la clave. Insensible a mayúsculas y
    /// espacios porque el parser del firmware (`settings_parseline()`) no
    /// normaliza nada: lo que se escriba es lo que se lee. `null`/vacío =
    /// Aura.
    /// </summary>
    public static FirmwareFamily Parse(string? raw)
    {
        if (raw is null) return Aura;
        string value = raw.Trim().ToLowerInvariant();
        return value switch
        {
            "" => Aura,
            "aura" => Aura,
            "metro" => Metro,
            "moonlit" => Moonlit,
            _ => Unknown(value),
        };
    }

    public bool Equals(FirmwareFamily? other) => other is not null && _raw == other._raw;

    public override bool Equals(object? obj) => obj is FirmwareFamily other && Equals(other);

    public override int GetHashCode() => _raw.GetHashCode();

    public override string ToString() => DisplayName;
}
