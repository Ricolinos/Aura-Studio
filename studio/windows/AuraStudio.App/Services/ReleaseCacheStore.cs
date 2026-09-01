using System.Text.Json;
using AuraStudio.Core.Installer;

namespace AuraStudio.App.Services;

/// <summary>
/// El caché de Releases en disco: un JSON bajo
/// <c>%LOCALAPPDATA%\Aura Studio\</c>, al lado de <c>preferences.json</c>
/// (R4/ST-132). Es el equivalente del <c>UserDefaults</c> que usa macOS.
///
/// <para><b>Acá NUNCA va el token de GitHub.</b> Ese vive en el Credential
/// Manager (D-203, ST-032, ST-074): esto guarda listas de Releases públicas,
/// que no son secretas y se pueden volver a pedir.</para>
///
/// <para>Como <see cref="AppPreferences"/>, no deja caer una excepción de disco:
/// un caché que no se puede leer ni escribir es un caché que no está, y eso solo
/// significa una consulta más a GitHub. Perder el caché es recuperable; no
/// arrancar, no.</para>
/// </summary>
public sealed class ReleaseCacheStore : IReleaseCacheStore
{
    private readonly string _path;
    private Dictionary<string, Entry> _entries;

    private sealed record Entry(string? Text, DateTimeOffset? Date);

    public ReleaseCacheStore()
    {
        string folder = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Aura Studio");

        _path = Path.Combine(folder, "release-cache.json");
        _entries = Read(_path);
    }

    public string? GetString(string key) => _entries.TryGetValue(key, out Entry? entry) ? entry.Text : null;

    public DateTimeOffset? GetDate(string key) => _entries.TryGetValue(key, out Entry? entry) ? entry.Date : null;

    public void SetString(string key, string value) => Update(key, entry => entry with { Text = value });

    public void SetDate(string key, DateTimeOffset value) => Update(key, entry => entry with { Date = value });

    private void Update(string key, Func<Entry, Entry> change)
    {
        _entries[key] = change(_entries.TryGetValue(key, out Entry? existing) ? existing : new Entry(null, null));
        Write();
    }

    private static Dictionary<string, Entry> Read(string path)
    {
        try
        {
            if (!File.Exists(path)) return [];

            return JsonSerializer.Deserialize<Dictionary<string, Entry>>(File.ReadAllText(path)) ?? [];
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or JsonException)
        {
            return [];
        }
    }

    private void Write()
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
            File.WriteAllText(_path, JsonSerializer.Serialize(_entries));
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            // Sin disco se sigue con el caché en memoria de esta sesión.
        }
    }
}
