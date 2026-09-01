using System.Globalization;
using System.Text;

namespace AuraStudio.Core;

/// <summary>
/// El contenido de <c>/.rockbox/aura/device.cfg</c> —
/// <c>CONTRATO-dispositivo.md</c> v2.
/// </summary>
/// <param name="Owner">
/// La instalación de Studio que nombró este iPod por primera vez, y la única
/// que puede cambiarle el nombre después. <c>null</c> en un archivo v1, que
/// cualquiera puede reclamar.
/// </param>
public sealed record DeviceConfig(
    int ContractVersion,
    string? DeviceId,
    string? Name,
    string? Owner,
    string? NameUpdatedAt)
{
    /// <summary>Un iPod que Studio todavía no nombró.</summary>
    public static DeviceConfig Empty { get; } = new(1, null, null, null, null);
}

/// <summary>
/// El nombre editable de un iPod. Port de <c>DeviceNameStore</c>
/// (ST-011/ST-013, <c>CONTRATO-dispositivo.md</c> v2).
///
/// <para><b>No vive en <c>aura.cfg</c></b> a propósito: el firmware reescribe
/// ese archivo entero cada vez que guarda un ajuste, y cualquier clave que no
/// conozca se perdería en el primer cambio de volumen. <c>device.cfg</c> es un
/// archivo propio que el firmware solo lee.</para>
/// </summary>
public static class DeviceNameStore
{
    public const string RelativePath = ".rockbox/aura/device.cfg";

    /// <summary>La versión del contrato que escribe este Studio.</summary>
    public const int CurrentContractVersion = 2;

    /// <summary>
    /// Tope del nombre: 32 caracteres <b>y además</b> 48 bytes UTF-8 — un
    /// acento o una "ñ" pesan dos. Sale del techo real de 63 bytes por línea
    /// del lector de <c>.cfg</c> del firmware.
    /// </summary>
    public const int MaxNameLength = 32;

    public const int MaxNameBytes = 48;

    // MARK: - Leer y escribir

    public static DeviceConfig Read(string volumeRoot)
    {
        string path = Path.Combine(volumeRoot, ToNative(RelativePath));

        try
        {
            return File.Exists(path) ? Parse(File.ReadAllText(path)) : DeviceConfig.Empty;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return DeviceConfig.Empty;
        }
    }

    /// <summary>
    /// Guarda el nombre, si esta instalación puede.
    ///
    /// <para>Devuelve el archivo tal como quedó. Si el iPod ya tiene dueño y no
    /// es esta instalación, <b>no escribe nada</b> y devuelve lo que había: el
    /// nombre es de quien lo puso.</para>
    /// </summary>
    public static DeviceConfig Save(string volumeRoot, string name, string installationId)
    {
        DeviceConfig current = Read(volumeRoot);

        if (!CanEdit(current, installationId)) return current;

        string sanitized = SanitizeName(name);

        // Un nombre que se queda en nada tras el saneo no borra el que había:
        // el usuario escribió algo que el iPod no puede mostrar, no pidió
        // quitarle el nombre.
        if (sanitized.Length == 0) return current;

        var updated = new DeviceConfig(
            CurrentContractVersion,
            current.DeviceId ?? Guid.NewGuid().ToString("D").ToUpperInvariant(),
            sanitized,
            // Un archivo v1 se reclama recién ahora, cuando de todas formas se
            // iba a escribir — nunca se reescribe solo para reclamarlo.
            current.Owner ?? installationId,
            DateTimeOffset.UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture));

        Write(volumeRoot, updated);
        return updated;
    }

    /// <summary>
    /// Le pone nombre a un iPod que todavía no tiene, la primera vez que Studio
    /// lo ve. No toca uno que ya esté nombrado.
    /// </summary>
    public static DeviceConfig EnsureNamed(string volumeRoot, string defaultName, string installationId)
    {
        DeviceConfig current = Read(volumeRoot);

        return current.Name is { Length: > 0 } ? current : Save(volumeRoot, defaultName, installationId);
    }

    /// <summary>
    /// Si esta instalación puede cambiar el nombre. Un archivo sin dueño —v1, o
    /// un iPod sin nombrar— lo puede reclamar cualquiera.
    /// </summary>
    public static bool CanEdit(DeviceConfig config, string installationId) =>
        config.Owner is not { Length: > 0 } owner
        || string.Equals(owner, installationId, StringComparison.OrdinalIgnoreCase);

    /// <summary>
    /// Lo que se le dice al usuario cuando el nombre es de otra instalación.
    /// <b>Se explica, no se esconde el campo</b>: un campo que desaparece sin
    /// motivo parece un error de la app.
    /// </summary>
    public const string NotOwnerExplanation =
        "El nombre de este iPod se puso desde otra computadora; solo desde ahí se puede cambiar.";

    private static void Write(string volumeRoot, DeviceConfig config)
    {
        string path = Path.Combine(volumeRoot, ToNative(RelativePath));
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);

        // Studio es el único que escribe este archivo, así que se reescribe
        // entero con las cinco claves del contrato.
        var builder = new StringBuilder();
        builder.Append("contract_version: ").Append(config.ContractVersion).Append('\n');
        if (config.DeviceId is { Length: > 0 }) builder.Append("device_id: ").Append(config.DeviceId).Append('\n');
        if (config.Name is { Length: > 0 }) builder.Append("device_name: ").Append(config.Name).Append('\n');
        if (config.Owner is { Length: > 0 }) builder.Append("device_owner: ").Append(config.Owner).Append('\n');
        if (config.NameUpdatedAt is { Length: > 0 })
            builder.Append("device_name_updated_at: ").Append(config.NameUpdatedAt).Append('\n');

        string temporary = path + ".tmp";
        File.WriteAllText(temporary, builder.ToString(), new UTF8Encoding(false));
        File.Move(temporary, path, overwrite: true);
    }

    // MARK: - Formato

    /// <summary>
    /// Mismo formato <c>clave: valor</c> que el resto de los <c>.cfg</c>. Las
    /// claves desconocidas se ignoran.
    /// </summary>
    public static DeviceConfig Parse(string text)
    {
        int version = 1;
        string? id = null, name = null, owner = null, updatedAt = null;

        foreach (string raw in text.Split('\n'))
        {
            string line = raw.TrimEnd('\r');
            int colon = line.IndexOf(':');
            if (colon <= 0) continue;

            string key = line[..colon].Trim();
            string value = line[(colon + 1)..].Trim();

            switch (key)
            {
                case "contract_version":
                    // Ausente o ilegible es 1: no había versión antes del contrato.
                    if (int.TryParse(value, out int parsed)) version = parsed;
                    break;
                case "device_id": id = value; break;
                case "device_name": name = value; break;
                case "device_owner": owner = value; break;
                case "device_name_updated_at": updatedAt = value; break;
            }
        }

        return new DeviceConfig(version, Blank(id), Blank(name), Blank(owner), Blank(updatedAt));
    }

    /// <summary>
    /// El nombre tal como se puede guardar: una sola línea, sin nada que el
    /// iPod no pueda dibujar, y dentro de los dos topes.
    ///
    /// <para>Los emoji se descartan en vez de recortarse: el iPod no tiene
    /// glifo para nada fuera del BMP y mostraría cajas vacías.</para>
    /// </summary>
    public static string SanitizeName(string name)
    {
        var builder = new StringBuilder();
        bool lastWasSpace = true; // arranca en true para comerse los espacios del principio

        foreach (Rune rune in name.EnumerateRunes())
        {
            // Fuera del BMP: emoji. El iPod no tiene con qué dibujarlos.
            if (rune.Value > 0xFFFF) continue;

            if (Rune.GetUnicodeCategory(rune) == UnicodeCategory.Control) continue;

            if (rune.Value == 0x20)
            {
                if (!lastWasSpace) { builder.Append(' '); lastWasSpace = true; }
                continue;
            }

            builder.Append(rune.ToString());
            lastWasSpace = false;
        }

        string collapsed = builder.ToString().TrimEnd();

        return TruncateToLimits(collapsed);
    }

    /// <summary>
    /// Recorta a 32 caracteres y a 48 bytes UTF-8, <b>sin partir un
    /// carácter</b>, y sin dejar un espacio al final.
    /// </summary>
    private static string TruncateToLimits(string value)
    {
        var builder = new StringBuilder();
        int characters = 0;
        int bytes = 0;

        foreach (Rune rune in value.EnumerateRunes())
        {
            int size = Encoding.UTF8.GetByteCount(rune.ToString());
            if (characters + 1 > MaxNameLength || bytes + size > MaxNameBytes) break;

            builder.Append(rune.ToString());
            characters++;
            bytes += size;
        }

        return builder.ToString().TrimEnd();
    }

    private static string? Blank(string? value) => string.IsNullOrWhiteSpace(value) ? null : value;

    private static string ToNative(string relativePath) =>
        relativePath.Replace('/', Path.DirectorySeparatorChar);
}
