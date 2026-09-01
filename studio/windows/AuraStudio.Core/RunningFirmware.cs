namespace AuraStudio.Core;

/// <summary>
/// Qué firmware está atendiendo el USB ahora mismo (ST-016). Es un hecho
/// distinto de "qué archivos hay en el disco" y se guarda aparte a propósito.
///
/// Instancias singleton por valor para poder comparar por referencia y
/// exponer <see cref="Classify"/> como método estático (equivalente al
/// <c>enum</c> de Swift).
/// </summary>
public sealed class RunningFirmware
{
    /// <summary>Modo disco del firmware original de Apple.</summary>
    public static RunningFirmware Apple { get; } = new(nameof(Apple));

    /// <summary>
    /// Rockbox o Aura (indistinguibles por USB), o su bootloader en modo
    /// USB. Prueba de que hay un bootloader de la familia Rockbox grabado
    /// en la NOR: nada más pudo poner ese firmware a atender el USB.
    /// </summary>
    public static RunningFirmware RockboxFamily { get; } = new(nameof(RockboxFamily));

    /// <summary>No se pudo leer (sin árbol de IOKit, o cadenas que no son ninguna de las dos).</summary>
    public static RunningFirmware Unknown { get; } = new(nameof(Unknown));

    public string Name { get; }

    private RunningFirmware(string name) => Name = name;

    public override string ToString() => Name;

    /// <summary>
    /// Clasifica los descriptores USB de vendor/producto. Sigue la misma
    /// regla que el firmware: "Rockbox" en cualquiera de las dos cadenas
    /// => familia Rockbox; producto "iPod" con vendor vacío o Apple => modo
    /// disco de Apple; cualquier otra cosa => unknown, nunca se adivina.
    /// </summary>
    public static RunningFirmware Classify(string vendorName, string productName)
    {
        var vendor = vendorName.ToLowerInvariant();
        var product = productName.ToLowerInvariant();

        if (vendor.Contains("rockbox") || product.Contains("rockbox"))
            return RockboxFamily;

        // El modo disco de Apple anuncia producto "iPod" (Rockbox nunca:
        // su producto es "Rockbox media player"). El vendor puede faltar
        // si solo se pudo leer el nodo de interfaz.
        if (product.Contains("ipod") && (vendor.Length == 0 || vendor.Contains("apple")))
            return Apple;

        return Unknown;
    }
}
