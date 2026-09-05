namespace AuraStudio.Core;

/// <summary>
/// El registro de qué arranque tiene grabado cada iPod (ST-166), en lo que
/// tiene de decidible: normalizar lo leído, buscar por disco y decidir si un
/// aparato se puede seguir. <b>No toca disco ni preferencias</b> — de guardarlo
/// se encarga <c>AppPreferences</c>, que es lo único que sabe dónde vive el
/// archivo.
///
/// <para>Existe porque la NOR del iPod <b>no se puede leer desde la
/// computadora</b>: la única forma de saber qué arranque tiene un aparato es
/// acordarse de habérselo grabado. Este registro es esa memoria, y
/// <see cref="BootloaderUpdate"/> es la regla que la interpreta.</para>
///
/// <para>ST-016 nunca se portó a Windows, así que acá no hay registros viejos
/// que migrar — el archivo de preferencias no tiene hoy ninguna clave de
/// arranques. Aun así <see cref="Normalize"/> es tolerante, por un caso que sí
/// es real: <c>preferences.json</c> es un archivo de texto que se puede editar a
/// mano, y un valor que no sea un SHA-256 tiene que leerse como
/// <see cref="BootloaderUpdate.UnknownBootloader"/> —"hay un arranque nuestro,
/// no sabemos cuál"— y nunca como ausente. Descartarlo forzaría un DFU
/// innecesario en un iPod que ya estaba instalado.</para>
/// </summary>
public static class BootloaderRegistry
{
    /// <summary>
    /// Un SHA-256 en hexadecimal: 64 dígitos. La comparación con el hash
    /// embebido la hace <see cref="BootloaderUpdate"/>; acá solo se decide si lo
    /// guardado <b>tiene forma</b> de hash.
    /// </summary>
    public static bool IsSha256(string? value) =>
        value is { Length: 64 } text && text.All(Uri.IsHexDigit);

    /// <summary>
    /// Sin clave de disco no hay registro fiable: no se anota nada y
    /// <b>tampoco se ofrece</b> actualizar el arranque. Ofrecerlo igual
    /// significaría volver a ofrecerlo en cada conexión, porque lo que se
    /// grabara no se podría anotar en ningún lado.
    /// </summary>
    public static bool CanTrack(string? diskKey) => !string.IsNullOrWhiteSpace(diskKey);

    /// <summary>
    /// Lo leído del archivo de preferencias, pasado a un mapa utilizable: las
    /// entradas sin clave se descartan y los valores que no son un hash se
    /// vuelven <see cref="BootloaderUpdate.UnknownBootloader"/>.
    ///
    /// <para>El hexadecimal se pasa a minúsculas porque la regla compara
    /// <b>cadenas</b>, no números: <c>FirmwareArtifactVerifier.Sha256Hex</c> ya
    /// las devuelve así, y normalizar acá es lo que evita que un archivo
    /// editado a mano en mayúsculas se lea como "otro arranque".</para>
    /// </summary>
    public static IReadOnlyDictionary<string, string> Normalize(
        IReadOnlyDictionary<string, string?>? stored)
    {
        var registry = new Dictionary<string, string>(StringComparer.Ordinal);
        if (stored is null) return registry;

        foreach ((string key, string? value) in stored)
        {
            if (!CanTrack(key)) continue;

            string trimmed = value?.Trim() ?? "";
            registry[key.Trim()] = IsSha256(trimmed)
                ? trimmed.ToLowerInvariant()
                : BootloaderUpdate.UnknownBootloader;
        }

        return registry;
    }

    /// <summary>
    /// El arranque anotado para ese disco: el SHA-256,
    /// <see cref="BootloaderUpdate.UnknownBootloader"/>, o <c>null</c> si esta
    /// instalación nunca le grabó el arranque a ese aparato.
    /// </summary>
    public static string? HashFor(IReadOnlyDictionary<string, string>? registry, string? diskKey)
    {
        if (registry is null || !CanTrack(diskKey)) return null;
        return registry.TryGetValue(diskKey!.Trim(), out string? hash) ? hash : null;
    }

    /// <summary>
    /// El registro con ese iPod anotado. Sin clave devuelve el registro tal
    /// cual: no hay dónde anotarlo, y una clave inventada sería peor que no
    /// anotar. Un <paramref name="hash"/> que no tenga forma de SHA-256 se anota
    /// como <see cref="BootloaderUpdate.UnknownBootloader"/> — el arranque se
    /// grabó, eso es un hecho; cuál, no se pudo calcular.
    /// </summary>
    public static IReadOnlyDictionary<string, string> WithRecord(
        IReadOnlyDictionary<string, string>? registry, string? diskKey, string? hash)
    {
        var updated = Copy(registry);
        if (!CanTrack(diskKey)) return updated;

        string trimmed = hash?.Trim() ?? "";
        updated[diskKey!.Trim()] = IsSha256(trimmed)
            ? trimmed.ToLowerInvariant()
            : BootloaderUpdate.UnknownBootloader;

        return updated;
    }

    /// <summary>
    /// El registro sin ese iPod. Es lo que corresponde al quitarle el arranque:
    /// a partir de ahí lo que tiene es el de Apple, y decir "no sabemos cuál"
    /// sería falso.
    /// </summary>
    public static IReadOnlyDictionary<string, string> Without(
        IReadOnlyDictionary<string, string>? registry, string? diskKey)
    {
        var updated = Copy(registry);
        if (CanTrack(diskKey)) updated.Remove(diskKey!.Trim());
        return updated;
    }

    /// <summary>
    /// Si dos registros dicen lo mismo. Lo usa el almacén para <b>no reescribir
    /// el archivo de preferencias</b> cuando se vuelve a anotar el mismo
    /// arranque en el mismo iPod — que es lo que pasa en cada reconexión.
    /// </summary>
    public static bool SameRegistry(
        IReadOnlyDictionary<string, string>? a, IReadOnlyDictionary<string, string>? b)
    {
        a ??= Empty;
        b ??= Empty;
        if (a.Count != b.Count) return false;

        foreach ((string key, string value) in a)
        {
            if (!b.TryGetValue(key, out string? other) || other != value) return false;
        }

        return true;
    }

    private static readonly IReadOnlyDictionary<string, string> Empty =
        new Dictionary<string, string>(StringComparer.Ordinal);

    private static Dictionary<string, string> Copy(IReadOnlyDictionary<string, string>? registry) =>
        registry is null
            ? new Dictionary<string, string>(StringComparer.Ordinal)
            : new Dictionary<string, string>(registry, StringComparer.Ordinal);

    /// <summary>
    /// Por qué ofrecerle a ESTE iPod actualizar el arranque, o <c>null</c> si no
    /// hay nada que ofrecerle. Es <see cref="BootloaderUpdate.ReasonFor"/> con
    /// la única condición que la regla pura no puede conocer: <b>sin clave de
    /// disco no se ofrece</b>.
    /// </summary>
    public static BootloaderUpdate.Reason? OfferReason(
        IReadOnlyDictionary<string, string>? registry, string? diskKey,
        string? embeddedHash, bool hasOurFirmware) =>
        OfferReason(diskKey, HashFor(registry, diskKey), embeddedHash, hasOurFirmware);

    /// <summary>
    /// La misma decisión cuando quien llama <b>ya tiene</b> el hash anotado y no
    /// el registro entero — que es el caso de la app: el almacén de preferencias
    /// resuelve la búsqueda por disco y entrega el valor.
    /// </summary>
    public static BootloaderUpdate.Reason? OfferReason(
        string? diskKey, string? recordedHash, string? embeddedHash, bool hasOurFirmware)
    {
        if (!CanTrack(diskKey)) return null;

        return BootloaderUpdate.ReasonFor(recordedHash, embeddedHash, hasOurFirmware);
    }
}
