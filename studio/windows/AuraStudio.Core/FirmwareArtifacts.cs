using System.IO.Compression;
using System.Security.Cryptography;

namespace AuraStudio.Core;

/// <summary>Qué se va a hacer con los artefactos — decide qué hay que verificar.</summary>
public enum ArtifactScope
{
    /// <summary>Copiar el árbol al iPod: `rockbox.zip` y `rockbox.ipod`.</summary>
    FirmwareTree,

    /// <summary>Grabar el bootloader por DFU: `mks5lboot.exe` y `bootloader-ipod6g.ipod`.</summary>
    Flashing,

    /// <summary>Todo.</summary>
    All
}

/// <summary>
/// Qué tan bien se pudo comprobar la procedencia de `mks5lboot.exe`.
///
/// Existe porque en Windows este binario **no viene del Release**: el contrato
/// §A publica `mks5lboot` (Unix) y su hash en `checksums.txt`; Windows necesita
/// un `.exe`. Ver la decisión abierta en `DECISIONS.md` / `ESTADO-PORT.md`.
/// </summary>
public enum ToolProvenance
{
    /// <summary>No se encontró el binario.</summary>
    Missing,

    /// <summary>Ningún hash con el cual compararlo. Es lo peor: no se sabe qué se va a ejecutar.</summary>
    Unverified,

    /// <summary>
    /// Coincide con un hash fijado localmente (`mks5lboot.exe.origin`), pero ese
    /// archivo no acredita de qué fuente salió: detecta corrupción o reemplazo,
    /// no acredita origen.
    /// </summary>
    LocalPin,

    /// <summary>Coincide con su entrada en el `checksums.txt` del Release. Lo correcto.</summary>
    ReleaseChecksums
}

/// <summary>
/// Procedencia declarada del `mks5lboot.exe` de Windows, leída de
/// `mks5lboot.exe.origin` junto al binario. Formato de texto plano:
/// <code>
/// sha256=&lt;64 hex&gt;
/// tag=v0.4.4-beta        # o "desconocido"
/// </code>
/// </summary>
public sealed record ToolOrigin(string? Sha256, string? Tag)
{
    public const string FileName = "mks5lboot.exe.origin";

    public static ToolOrigin? Parse(string text)
    {
        string? sha = null;
        string? tag = null;
        foreach (string raw in text.Split('\n'))
        {
            string line = raw.Trim();
            if (line.Length == 0 || line.StartsWith('#')) continue;
            int eq = line.IndexOf('=');
            if (eq <= 0) continue;
            string key = line[..eq].Trim();
            string value = line[(eq + 1)..].Trim();
            if (key.Equals("sha256", StringComparison.OrdinalIgnoreCase)) sha = value;
            else if (key.Equals("tag", StringComparison.OrdinalIgnoreCase)) tag = value;
        }
        if (sha is null && tag is null) return null;
        return new ToolOrigin(sha, tag);
    }

    public static ToolOrigin? Read(string directory)
    {
        string path = Path.Combine(directory, FileName);
        try
        {
            return File.Exists(path) ? Parse(File.ReadAllText(path)) : null;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return null;
        }
    }
}

/// <summary>
/// Artefactos de una única versión de firmware, ubicados en un directorio.
/// Equivalente de `BundledArtifacts` de macOS: **ubica y verifica**, nunca
/// compila ni descarga.
///
/// El directorio se puebla con `scripts/FirmwareFetch.ps1` desde el Release
/// fijado en `FIRMWARE_VERSION` (contrato §A) — nunca desde un checkout de las
/// fuentes del firmware.
/// </summary>
public sealed record FirmwareArtifacts(
    FirmwareFamily Family,
    string Directory,
    string? ReleaseTag,
    bool IsRelease)
{
    public const string VersionMarkerFileName = "firmware-version.txt";

    public string RockboxImage => Path.Combine(Directory, "rockbox.ipod");
    public string RockboxArchive => Path.Combine(Directory, "rockbox.zip");
    public string Mks5lboot => Path.Combine(Directory, "mks5lboot.exe");
    public string? BootloaderImage => Find("bootloader-ipod6g.ipod");
    public string? Checksums => Find("checksums.txt");
    public string? Modifications => Find("MODIFICATIONS.md");
    public string? ThirdPartyNotices => Find("THIRD-PARTY-NOTICES.txt");

    public string? Find(string name)
    {
        string path = Path.Combine(Directory, name);
        return File.Exists(path) ? path : null;
    }

    /// <summary>
    /// Artefactos de <paramref name="directory"/>, con el tag leído de
    /// `firmware-version.txt` (lo deja `FirmwareFetch.ps1`). Sin ese archivo el
    /// tag queda en `null` — la pantalla de Licencias lo dice en vez de
    /// inventar uno.
    /// </summary>
    public static FirmwareArtifacts Load(string directory, FirmwareFamily family)
    {
        string? tag = null;
        try
        {
            string marker = Path.Combine(directory, VersionMarkerFileName);
            if (File.Exists(marker))
            {
                string text = File.ReadAllText(marker).Trim();
                if (text.Length > 0) tag = text;
            }
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            // Sin tag: se reporta como desconocido, nunca se inventa.
        }

        // "local-dev" lo escribe FirmwareFetch.ps1 en el modo -FromDir: es un
        // dist armado a mano, no un Release etiquetado.
        bool isRelease = tag is { Length: > 0 } && tag != "local-dev";
        return new FirmwareArtifacts(family, directory, tag, isRelease);
    }

    /// <summary>
    /// Directorio de artefactos de una familia, junto al ejecutable de la app.
    ///
    /// <para>Sin raíz se cae a la del ejecutable, que es lo que quería decir
    /// quien llamó. <b>Sin familia, en cambio, se lanza</b> (ST-130): elegir
    /// una por omisión resolvería el directorio de un firmware que el usuario
    /// no pidió, y el que llama está a punto de copiarlo al iPod. Una excepción
    /// con nombre es mucho mejor que un <c>NullReferenceException</c> — dice
    /// qué faltaba.</para>
    /// </summary>
    public static string DirectoryFor(string appRoot, FirmwareFamily family)
    {
        ArgumentNullException.ThrowIfNull(family);

        string root = string.IsNullOrWhiteSpace(appRoot) ? AppContext.BaseDirectory : appRoot;
        string baseDir = Path.Combine(root, "artifacts");

        // §A bis: Aura en la raíz; cada hermana en su subdirectorio.
        return family.ConfigValue is { Length: > 0 } sub ? Path.Combine(baseDir, sub) : baseDir;
    }
}

/// <param name="Errors">Vacío cuando todo lo del alcance pedido verificó.</param>
/// <param name="Provenance">Solo significativo cuando el alcance incluye el flasheo.</param>
public sealed record ArtifactVerificationResult(
    bool IsValid,
    IReadOnlyList<string> Errors,
    ToolProvenance Provenance = ToolProvenance.Missing,
    string? ToolOriginTag = null)
{
    public static ArtifactVerificationResult Valid { get; } = new(true, []);
}

/// <summary>
/// Verifica assets antes de permitir que nada escriba en el iPod ni corra la
/// herramienta de flasheo. Port de `BundledArtifacts.verifyAll` de macOS.
/// </summary>
public static class FirmwareArtifactVerifier
{
    /// <summary>
    /// D-297/D-298 (Aura-Firmware), ST-018: `package_dist.sh` llegó a armar
    /// `rockbox.zip` copiando assets a mano en vez de correr `make zip` — el zip
    /// resultante tenía checksum interno consistente (coincidía con lo que el
    /// propio Release publicaba) pero **no traía codecs ni plugins**, así que un
    /// iPod instalado con ese Release se quedaba sin video y, desde cero, sin
    /// audio. Un checksum correcto por sí solo nunca hubiera detectado esto: el
    /// bug estaba en lo que el Release publicó, no en la transferencia. Dos
    /// entradas representativas alcanzan (un plugin real y un codec real).
    /// </summary>
    public static readonly string[] RequiredArchiveEntries =
    [
        ".rockbox/rocks/viewers/mpegplayer.rock",
        ".rockbox/codecs/mpa.codec"
    ];

    private static readonly string[] TreeFiles = ["rockbox.ipod", "rockbox.zip"];

    public static ArtifactVerificationResult Verify(FirmwareArtifacts artifacts,
                                                    ArtifactScope scope = ArtifactScope.All)
    {
        var errors = new List<string>();
        if (!Directory.Exists(artifacts.Directory))
        {
            return new ArtifactVerificationResult(false,
                ["No existe el directorio de artefactos del firmware."]);
        }

        string? checksumsPath = artifacts.Checksums;
        Dictionary<string, string> expected = checksumsPath is null
            ? []
            : ReadChecksums(checksumsPath, errors);

        if (checksumsPath is null)
        {
            errors.Add("Falta checksums.txt: no hay con qué verificar los archivos del firmware.");
        }

        bool wantsTree = scope is ArtifactScope.FirmwareTree or ArtifactScope.All;
        bool wantsFlashing = scope is ArtifactScope.Flashing or ArtifactScope.All;

        if (wantsTree)
        {
            foreach (string name in TreeFiles)
            {
                VerifyAgainstChecksums(artifacts, name, expected, errors, required: true);
            }
            VerifyArchiveContents(artifacts.RockboxArchive, errors);
        }

        var provenance = ToolProvenance.Missing;
        string? originTag = null;

        if (wantsFlashing)
        {
            // El bootloader sí viaja en el Release y sí está en checksums.txt.
            if (artifacts.BootloaderImage is null)
            {
                errors.Add("Falta bootloader-ipod6g.ipod: no se puede grabar el bootloader.");
            }
            else
            {
                VerifyAgainstChecksums(artifacts, "bootloader-ipod6g.ipod", expected, errors, required: true);
            }

            (provenance, originTag) = VerifyTool(artifacts, expected, errors);
        }

        return new ArtifactVerificationResult(errors.Count == 0, errors, provenance, originTag);
    }

    /// <summary>
    /// `mks5lboot.exe` es el caso especial de Windows: el Release publica
    /// `mks5lboot` (Unix), así que hay tres niveles posibles de confianza. Ver
    /// <see cref="ToolProvenance"/>.
    /// </summary>
    private static (ToolProvenance, string?) VerifyTool(FirmwareArtifacts artifacts,
                                                        Dictionary<string, string> expected,
                                                        List<string> errors)
    {
        if (!File.Exists(artifacts.Mks5lboot))
        {
            errors.Add("Falta mks5lboot.exe: sin esa herramienta no se puede grabar el bootloader.");
            return (ToolProvenance.Missing, null);
        }

        string actual = Sha256Hex(artifacts.Mks5lboot);

        // 1) Lo ideal: el Release publicó el .exe y su hash.
        if (expected.TryGetValue("mks5lboot.exe", out string? released))
        {
            if (!string.Equals(actual, released, StringComparison.OrdinalIgnoreCase))
            {
                errors.Add("El checksum de mks5lboot.exe no coincide con el del Release.");
                return (ToolProvenance.Unverified, null);
            }
            return (ToolProvenance.ReleaseChecksums, artifacts.ReleaseTag);
        }

        // 2) Hash fijado localmente: detecta corrupción o reemplazo, no acredita origen.
        ToolOrigin? origin = ToolOrigin.Read(artifacts.Directory);
        if (origin?.Sha256 is { Length: 64 } pinned)
        {
            if (!string.Equals(actual, pinned, StringComparison.OrdinalIgnoreCase))
            {
                errors.Add("mks5lboot.exe no coincide con el hash fijado en " +
                           $"{ToolOrigin.FileName}: el archivo cambió y no se puede confiar en él.");
                return (ToolProvenance.Unverified, origin.Tag);
            }
            return (ToolProvenance.LocalPin, origin.Tag);
        }

        // 3) Nada con qué comparar.
        errors.Add($"mks5lboot.exe no se puede verificar: ni el Release lo publica ni existe {ToolOrigin.FileName}.");
        return (ToolProvenance.Unverified, null);
    }

    private static void VerifyAgainstChecksums(FirmwareArtifacts artifacts,
                                               string name,
                                               Dictionary<string, string> expected,
                                               List<string> errors,
                                               bool required)
    {
        string path = Path.Combine(artifacts.Directory, name);
        if (!File.Exists(path))
        {
            if (required) errors.Add($"Falta {name}.");
            return;
        }
        if (!expected.TryGetValue(name, out string? hash))
        {
            errors.Add($"checksums.txt no describe {name}.");
            return;
        }
        if (!string.Equals(Sha256Hex(path), hash, StringComparison.OrdinalIgnoreCase))
        {
            errors.Add($"El checksum de {name} no coincide.");
        }
    }

    public static string Sha256Hex(string path)
    {
        using FileStream stream = File.OpenRead(path);
        return Convert.ToHexString(SHA256.HashData(stream)).ToLowerInvariant();
    }

    /// <summary>Formato de `shasum -a 256`: hash, espacios, nombre de archivo.</summary>
    public static Dictionary<string, string> ReadChecksums(string path, List<string> errors)
    {
        var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (string line in File.ReadLines(path))
        {
            if (string.IsNullOrWhiteSpace(line)) continue;
            string[] parts = line.Trim().Split((char[]?)null, 2, StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length != 2 || parts[0].Length != 64 || !parts[0].All(Uri.IsHexDigit))
            {
                errors.Add("checksums.txt contiene una línea inválida.");
                continue;
            }
            string name = parts[1].TrimStart('*').Trim();
            if (Path.IsPathRooted(name) || name.Contains("..", StringComparison.Ordinal))
            {
                errors.Add("checksums.txt contiene una ruta insegura.");
                continue;
            }
            result[name] = parts[0].ToLowerInvariant();
        }
        return result;
    }

    /// <summary>
    /// El zip trae de verdad el árbol completo (no solo un checksum consistente):
    /// ver <see cref="RequiredArchiveEntries"/>. Además rechaza rutas inseguras
    /// — un zip nunca escribe fuera del volumen del iPod.
    /// </summary>
    private static void VerifyArchiveContents(string path, List<string> errors)
    {
        if (!File.Exists(path)) return;   // ya se reportó como faltante
        try
        {
            using ZipArchive archive = ZipFile.OpenRead(path);
            var names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            bool unsafePath = false;

            foreach (ZipArchiveEntry entry in archive.Entries)
            {
                names.Add(entry.FullName.Replace('\\', '/'));
                if (Path.IsPathRooted(entry.FullName)
                    || entry.FullName.Split('/', '\\').Contains(".."))
                {
                    unsafePath = true;
                }
            }

            if (unsafePath) errors.Add("rockbox.zip contiene una ruta insegura.");

            string[] missing = RequiredArchiveEntries.Where(e => !names.Contains(e)).ToArray();
            if (missing.Length > 0)
            {
                errors.Add("rockbox.zip está incompleto (le faltan codecs o plugins): " +
                           string.Join(", ", missing) + ".");
            }
        }
        catch (Exception ex) when (ex is InvalidDataException or IOException)
        {
            errors.Add("rockbox.zip no es un archivo válido.");
        }
    }
}
