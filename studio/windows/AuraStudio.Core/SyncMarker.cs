using System.Diagnostics.CodeAnalysis;
using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace AuraStudio.Core;

/// <summary>
/// Marcador de sincronización pendiente — `docs/contracts/library-layout-v1.md`
/// SS4 (D-293 en el firmware / ST-012 acá). El firmware NO corre mientras el
/// iPod está montado por USB, así que Studio no puede pedirle nada: le deja
/// este archivo en `/.aura/sync-pending.json` al terminar cada sincronización
/// que tocó archivos, y el firmware lo lee al arrancar y al volver de la
/// pantalla USB, reconstruye los índices de las secciones marcadas y lo borra
/// solo al terminar bien.
///
/// `Attempts` lo escribe el FIRMWARE (contador de reintentos, 3 fallos
/// seguidos = deja de reintentar solo); Studio siempre escribe 0.
///
/// Port del `struct SyncPendingMarker` de Swift: el JSON que se escribe usa
/// exactamente las mismas claves (camelCase sintetizado por Codable) que el
/// original, para que el firmware lo lea idéntico.
/// </summary>
public sealed record SyncPendingMarker
{
    /// <summary>Cambios por sección que el marcador anuncia al firmware.</summary>
    public sealed record Changes(bool Music, bool Video, bool Images)
    {
        public bool IsEmpty => !Music && !Video && !Images;
    }

    /// <summary>Versión del esquema que este Studio escribe. Sube junto con la versión de `library-layout-vN.md`.</summary>
    public const int CurrentVersion = 1;

    public const string RelativePath = ".aura/sync-pending.json";

    private static readonly JsonSerializerOptions WriteOptions = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
    };

    private static readonly JsonSerializerOptions ReadOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
    };

    public int Version { get; init; }

    public required string Timestamp { get; init; }

    // La clave JSON del contrato SS4.1 es exactamente "changes" (el firmware
    // la lee tal cual, igual que el `var changes` del Swift original). La
    // propiedad no puede llamarse `Changes` en C# (chocaría con el tipo
    // anidado), así que la clave se fija con el atributo.
    [JsonPropertyName("changes")]
    public required Changes Changeset { get; init; }

    public int Attempts { get; init; }

    /// <summary>Constructor público del modelo: versiona y pone el contador en 0, igual que el `init` de Swift.</summary>
    [SetsRequiredMembers]
    public SyncPendingMarker(Changes changes, DateTimeOffset? date = null)
    {
        Version = CurrentVersion;
        Timestamp = ToIso8601(date ?? DateTimeOffset.UtcNow);
        Changeset = changes;
        Attempts = 0;
    }

    /// <summary>Para la deserialización JSON.</summary>
    public SyncPendingMarker() { }

    /// <summary>
    /// ISO 8601 invariante (UTC, "Z"), el equivalente de
    /// `ISO8601DateFormatter` con `.withInternetDateTime` del Swift.
    /// </summary>
    private static string ToIso8601(DateTimeOffset date)
        => date.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ssZ", CultureInfo.InvariantCulture);

    /// <summary>
    /// Escritura atómica en el volumen montado. Crea `/.aura/` si falta y
    /// escribe a un archivo temporal del MISMO directorio, que luego se
    /// renombra sobre el destino — el equivalente de la opción `.atomic` de
    /// Swift (solo es atómico si el renombrado queda en el mismo volumen).
    /// </summary>
    public void Write(string volumeRoot)
    {
        string dir = Path.Combine(volumeRoot, ".aura");
        Directory.CreateDirectory(dir);

        string dest = Path.Combine(volumeRoot, RelativePath);
        string temp = Path.Combine(dir, Path.GetRandomFileName());
        try
        {
            File.WriteAllText(temp, JsonSerializer.Serialize(this, WriteOptions));
            File.Move(temp, dest, overwrite: true);
        }
        finally
        {
            if (File.Exists(temp)) { try { File.Delete(temp); } catch { /* best effort */ } }
        }
    }

    /// <summary>`null` si el archivo no existe o no es JSON válido (o no decodifica).</summary>
    public static SyncPendingMarker? Read(string volumeRoot)
    {
        string path = Path.Combine(volumeRoot, RelativePath);
        if (!File.Exists(path)) return null;
        try
        {
            return JsonSerializer.Deserialize<SyncPendingMarker>(File.ReadAllText(path), ReadOptions);
        }
        catch (JsonException)
        {
            return null;
        }
    }
}

/// <summary>
/// Qué entiende el firmware instalado en el iPod, leído de `aura.cfg`
/// (claves de SOLO ESCRITURA del lado firmware, misma convención que
/// `theme_format_supported`). Port del `enum FirmwareCapabilities` de Swift.
/// </summary>
public static class FirmwareCapabilities
{
    public const string AuraConfigRelativePath = ".rockbox/aura/aura.cfg";

    /// <summary>
    /// Versión de esquema del marcador que el firmware entiende, o `null` si
    /// el firmware es anterior a D-293 (no escribe la clave) — en ese caso
    /// `LibrarySync` conserva su mecanismo previo (borrar la base de tagcache
    /// para forzar la reconstrucción al arrancar), contrato SS4.4.
    /// </summary>
    public static int? SupportedSyncMarkerVersion(string volumeRoot)
        => ReadIntKey(volumeRoot, "sync_marker_supported:");

    /// <summary>
    /// ST-065: versión del formato de tema que el firmware entiende
    /// (`theme_format_supported`), o `null` si no publica la clave: o es un
    /// firmware anterior a D-289, o una familia SIN sistema de temas
    /// (moonlit.aura).
    /// </summary>
    public static int? SupportedThemeFormat(string volumeRoot)
        => ReadIntKey(volumeRoot, "theme_format_supported:");

    /// <summary>
    /// ST-046 / contrato v8: qué familia dice ser el firmware instalado
    /// (`firmware_family`). **La ausencia de la clave devuelve Aura** — no es
    /// un fallback defensivo sino el contrato: Aura-Firmware nunca escribió
    /// esta clave ni la escribirá. Cuando la clave NO está, antes de concluir
    /// "Aura" se mira el centinela de árbol instalado de cada familia que sí
    /// escribe la clave (ST-067: cubre el árbol recién copiado que todavía no
    /// arrancó y cuyo `aura.cfg` no tiene familia propia).
    /// </summary>
    public static FirmwareFamily DeclaredFamily(string volumeRoot)
    {
        string cfgPath = Path.Combine(volumeRoot, AuraConfigRelativePath);
        if (File.Exists(cfgPath))
        {
            const string key = "firmware_family:";
            foreach (string line in File.ReadAllText(cfgPath).Split('\n'))
            {
                if (line.StartsWith(key, StringComparison.Ordinal))
                {
                    return FirmwareFamily.Parse(line[key.Length..]);
                }
            }
        }
        return FamilyBySentinel(volumeRoot) ?? FirmwareFamily.Aura;
    }

    /// <summary>
    /// ST-067: familia de un árbol que nunca arrancó, por su centinela de
    /// árbol instalado. Solo familias que declaran `firmware_family`
    /// (`ConfigValue != null`); Aura se reconoce por ausencia, nunca por
    /// centinela. `null` si ningún centinela está.
    /// </summary>
    public static FirmwareFamily? FamilyBySentinel(string volumeRoot)
    {
        foreach (FirmwareFamily family in FirmwareFamily.Installable)
        {
            if (family.ConfigValue is null) continue;
            if (family.InstalledTreeSentinel is null) continue;
            if (File.Exists(Path.Combine(volumeRoot, family.InstalledTreeSentinel)))
            {
                return family;
            }
        }
        return null;
    }

    /// <summary>
    /// ST-067: deja `firmware_family: &lt;valor&gt;` en `aura.cfg` del árbol activo
    /// justo después de instalarlo, para que el árbol tenga identidad desde
    /// antes del primer arranque. Para Aura no escribe nada (su firma es la
    /// ausencia, ST-046). Upsert: respeta las demás líneas (la hora que
    /// `ClockSyncWriter` acaba de dejar).
    /// </summary>
    public static void SeedDeclaredFamily(string volumeRoot, FirmwareFamily family)
    {
        string? value = family.ConfigValue;
        if (value is null) return;

        string cfgPath = Path.Combine(volumeRoot, AuraConfigRelativePath);
        const string key = "firmware_family:";

        var lines = new List<string>();
        if (File.Exists(cfgPath))
        {
            // split(omittingEmptySubsequences: false) del Swift: conserva las
            // líneas vacías tal cual.
            lines.AddRange(File.ReadAllText(cfgPath).Split('\n'));
        }
        if (lines.Count > 0 && lines[^1].Length == 0) lines.RemoveAt(lines.Count - 1);
        lines.RemoveAll(l => l.StartsWith(key, StringComparison.Ordinal));
        lines.Insert(0, $"{key} {value}");

        Directory.CreateDirectory(Path.GetDirectoryName(cfgPath)!);
        File.WriteAllText(cfgPath, string.Join('\n', lines) + "\n");
    }

    private static int? ReadIntKey(string volumeRoot, string key)
    {
        string cfgPath = Path.Combine(volumeRoot, AuraConfigRelativePath);
        if (!File.Exists(cfgPath)) return null;
        foreach (string line in File.ReadAllText(cfgPath).Split('\n'))
        {
            if (line.StartsWith(key, StringComparison.Ordinal))
            {
                string value = line[key.Length..].Trim();
                return int.TryParse(value, NumberStyles.None, CultureInfo.InvariantCulture, out int parsed)
                    ? parsed
                    : null;
            }
        }
        return null;
    }
}
