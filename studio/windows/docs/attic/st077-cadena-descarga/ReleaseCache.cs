// ============================================================================
// ÁTICO — implementación de REFERENCIA, no forma parte del build.
// Ver README.md en esta misma carpeta antes de reutilizar nada de acá.
// Cuelga de un modelo de artefactos (`BundledArtifacts`) que se descartó al
// reconciliar la Fase 2; el que sobrevivió es `AuraStudio.Core/FirmwareArtifacts.cs`.
// ============================================================================

using System.Text.Json;
using AuraStudio.Core.Networking;

namespace AuraStudio.Core.Installer;

/// <summary>
/// Dónde persiste el caché de Releases. En macOS es <c>UserDefaults</c>; acá se
/// abstrae para que <see cref="ReleaseCache"/> sea puro y testeable sin tocar
/// disco. La implementación real (JSON bajo <c>%LOCALAPPDATA%</c>) vive en la app.
/// </summary>
public interface IReleaseCacheStore
{
    string? GetString(string key);
    void SetString(string key, string value);
    DateTimeOffset? GetDate(string key);
    void SetDate(string key, DateTimeOffset value);
}

/// <summary>Store en memoria: el de las pruebas, y el respaldo si no hay disco.</summary>
public sealed class InMemoryReleaseCacheStore : IReleaseCacheStore
{
    private readonly Dictionary<string, string> _strings = new(StringComparer.Ordinal);
    private readonly Dictionary<string, DateTimeOffset> _dates = new(StringComparer.Ordinal);

    public string? GetString(string key) => _strings.TryGetValue(key, out var value) ? value : null;
    public void SetString(string key, string value) => _strings[key] = value;
    public DateTimeOffset? GetDate(string key) => _dates.TryGetValue(key, out var value) ? value : null;
    public void SetDate(string key, DateTimeOffset value) => _dates[key] = value;
}

/// <summary>
/// Caché de la lista de Releases de GitHub con TTL de 24 h: evita pegarle a la
/// API en cada conexión de dispositivo — el límite anónimo de GitHub
/// (60 req/hora) no es el problema real, es no depender de la red para algo que
/// casi nunca cambia. Vencido el TTL, el próximo chequeo vuelve a consultar y lo
/// renueva. Port de <c>enum ReleaseCache</c> (Swift, dentro de
/// <c>Services/AuraUpdateChecker.swift</c>).
///
/// ST-046: el caché es <b>por familia</b>. Con una sola llave, la lista de
/// Releases de Metro habría quedado guardada bajo la de Aura (y al revés):
/// conectar un iPod con Metro y después uno con Aura le habría mostrado al
/// segundo los tags del primero durante 24 h, comparados contra su propio
/// <c>version.txt</c>. Las llaves históricas se conservan tal cual para Aura, así
/// que nadie pierde su caché al actualizar Studio.
/// </summary>
public static class ReleaseCache
{
    public const string DataKey = "AuraUpdateChecker.cachedReleases";
    public const string TimestampKey = "AuraUpdateChecker.cachedReleasesTimestamp";
    public static readonly TimeSpan Ttl = TimeSpan.FromHours(24);

    public static string DataKeyFor(FirmwareFamily family) =>
        family.ConfigValue is { } suffix ? $"{DataKey}.{suffix}" : DataKey;

    public static string TimestampKeyFor(FirmwareFamily family) =>
        family.ConfigValue is { } suffix ? $"{TimestampKey}.{suffix}" : TimestampKey;

    public static IReadOnlyList<GitHubRelease>? Load(IReleaseCacheStore store, FirmwareFamily family, DateTimeOffset? now = null)
    {
        if (store.GetDate(TimestampKeyFor(family)) is not { } timestamp) return null;
        if ((now ?? DateTimeOffset.Now) - timestamp >= Ttl) return null;
        if (store.GetString(DataKeyFor(family)) is not { } json) return null;
        try
        {
            return JsonSerializer.Deserialize<List<GitHubRelease>>(json);
        }
        catch (JsonException)
        {
            // Un caché ilegible es "no hay caché", nunca un error de cara al
            // usuario: la consulta en vivo lo reemplaza en la misma pasada.
            return null;
        }
    }

    public static void Store(IReadOnlyList<GitHubRelease> releases, IReleaseCacheStore store, FirmwareFamily family, DateTimeOffset? now = null)
    {
        store.SetString(DataKeyFor(family), JsonSerializer.Serialize(releases));
        store.SetDate(TimestampKeyFor(family), now ?? DateTimeOffset.Now);
    }
}
