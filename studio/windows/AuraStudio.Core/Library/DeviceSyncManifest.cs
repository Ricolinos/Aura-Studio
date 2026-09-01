using System.Text.Json;
using System.Text.Json.Serialization;

namespace AuraStudio.Core.Library;

/// <summary>
/// Un archivo ya sincronizado a ESTE iPod. Se compara por tamaño + fecha (como
/// rsync) en vez de hashear: con miles de canciones, hashear todo en cada
/// pasada tardaría demasiado para algo que casi nunca cambió.
///
/// <para><b>Las claves son las del <c>SyncRecord</c> de Swift, exactas.</b> El
/// dueño sincroniza el mismo iPod desde la Mac y desde Windows: si este
/// manifiesto no decodifica del otro lado, macOS lo descarta entero y vuelve a
/// copiar la biblioteca completa.</para>
/// </summary>
/// <param name="SourceModifiedAt">Segundos desde 1970 — <c>TimeInterval</c> de Swift, no una fecha ISO.</param>
/// <param name="DestinationSize">Huella del archivo <b>tal como quedó en el iPod</b>. Ausente en manifiestos v1.</param>
/// <param name="WrittenBy">
/// Qué instalación escribió el registro. Dos equipos sincronizando el mismo
/// iPod no se pisan: cada uno solo considera propios los suyos.
/// </param>
public sealed record DeviceSyncRecord(
    [property: JsonPropertyName("sourcePath")] string SourcePath,
    [property: JsonPropertyName("sourceSize")] long SourceSize,
    [property: JsonPropertyName("sourceModifiedAt")] double SourceModifiedAt,
    [property: JsonPropertyName("destinationRelativePath")] string DestinationRelativePath)
{
    [JsonPropertyName("destinationSize")]
    public long? DestinationSize { get; init; }

    [JsonPropertyName("destinationModifiedAt")]
    public double? DestinationModifiedAt { get; init; }

    [JsonPropertyName("writtenBy")]
    public string? WrittenBy { get; init; }

    [JsonPropertyName("syncedAt")]
    public double? SyncedAt { get; init; }

    public static double ToTimeInterval(DateTimeOffset value) =>
        value.ToUnixTimeMilliseconds() / 1000.0;
}

/// <summary>
/// El estado del último sync, en <c>/.rockbox/aura/sync_manifest.json</c>.
/// <b>El firmware nunca lo lee</b> (contrato §D) — es de Studio, y de los dos
/// Studios: el de la Mac y el de Windows.
/// </summary>
public sealed class DeviceSyncManifest
{
    public const string RelativePath = ".rockbox/aura/sync_manifest.json";

    /// <summary>v2 = el registro trae huella del destino, autor y fecha.</summary>
    public const int CurrentContractVersion = 2;

    /// <summary>Indexado por <c>sourcePath</c>, igual que el diccionario de Swift.</summary>
    [JsonPropertyName("records")]
    public Dictionary<string, DeviceSyncRecord> Records { get; init; } = [];

    /// <summary>
    /// <c>null</c> = manifiesto v1, de antes del campo — sus registros no traen
    /// huella del destino ni autor. <b>Sin valor por omisión a propósito</b>:
    /// así, leer un archivo sin la clave lo dice, en vez de hacerlo pasar por
    /// uno nuevo.
    /// </summary>
    [JsonPropertyName("contractVersion")]
    public int? ContractVersion { get; set; }

    private static readonly JsonSerializerOptions Options = new()
    {
        // Sin indentar y con las claves tal cual: es lo que produce
        // JSONEncoder() de Swift sin opciones.
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };

    /// <summary>
    /// Un manifiesto ilegible devuelve uno vacío, nunca una excepción: el peor
    /// caso es volver a copiar de más, y eso es mucho mejor que no poder
    /// sincronizar.
    /// </summary>
    public static DeviceSyncManifest Load(string volumeRoot)
    {
        string path = Path.Combine(volumeRoot, ToNative(RelativePath));
        if (!File.Exists(path)) return Empty;

        try
        {
            return JsonSerializer.Deserialize<DeviceSyncManifest>(File.ReadAllText(path), Options) ?? Empty;
        }
        catch (Exception ex) when (ex is JsonException or IOException)
        {
            return Empty;
        }
    }

    private static DeviceSyncManifest Empty => new() { ContractVersion = CurrentContractVersion };

    /// <summary>
    /// Se guarda <b>después de cada archivo</b>, no al final: es lo que hace
    /// que desconectar el iPod a mitad conserve lo ya copiado en vez de
    /// obligar a recopiarlo todo la próxima vez.
    /// </summary>
    public void Save(string volumeRoot)
    {
        // Lo que se escribe son siempre registros v2 (con huella del destino y
        // autor): la versión se sella acá y no depende de que el llamador se
        // acuerde.
        ContractVersion = CurrentContractVersion;

        string path = Path.Combine(volumeRoot, ToNative(RelativePath));
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);

        string temporary = path + ".tmp";
        File.WriteAllText(temporary, JsonSerializer.Serialize(this, Options));
        File.Move(temporary, path, overwrite: true);
    }

    private static string ToNative(string relativePath) =>
        relativePath.Replace('/', Path.DirectorySeparatorChar);
}
