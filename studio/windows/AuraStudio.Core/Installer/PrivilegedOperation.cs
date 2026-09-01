using System.Text.Json;
using System.Text.Json.Serialization;

namespace AuraStudio.Core.Installer;

/// <summary>Las únicas operaciones que Aura Studio sabe pedir con permisos de administrador.</summary>
public enum PrivilegedOperationKind
{
    /// <summary>Reparticionar (MBR) y formatear en FAT32 el disco del iPod.</summary>
    FormatIPodFat32,

    /// <summary>Detener el servicio de dispositivos móviles de Apple durante el flasheo.</summary>
    PauseAppleMobileDeviceService,

    /// <summary>Volver a arrancarlo al terminar.</summary>
    ResumeAppleMobileDeviceService
}

/// <summary>
/// Una operación privilegiada concreta y auditada — <b>nunca</b> una API genérica
/// de "corre este comando como administrador". Es el equivalente Windows del
/// criterio de <c>PrivilegedExecutor</c> en macOS: cada operación tiene su propio
/// caso, sus propios argumentos validados, y el ejecutor no acepta nada fuera de
/// esta lista.
///
/// Se serializa a JSON para pasársela al proceso elevado. Ese proceso la
/// <see cref="Validate"/> otra vez antes de hacer nada: el archivo con la
/// petición vive un instante en el disco del usuario y no se confía en él por
/// haberlo escrito nosotros.
/// </summary>
public sealed record PrivilegedOperation
{
    [JsonConverter(typeof(JsonStringEnumConverter))]
    public PrivilegedOperationKind Kind { get; init; }

    /// <summary>Número de disco físico de Windows (<c>\\.\PhysicalDrive&lt;N&gt;</c>).</summary>
    public int DiskNumber { get; init; }

    /// <summary>Tamaño que el disco tenía cuando el usuario confirmó. Se vuelve a comparar antes de tocar nada.</summary>
    public long ExpectedSizeBytes { get; init; }

    /// <summary>Modelo reportado por WMI cuando el usuario confirmó, para la misma re-verificación.</summary>
    public string ExpectedModel { get; init; } = "";

    /// <summary>Etiqueta del volumen nuevo.</summary>
    public string VolumeLabel { get; init; } = "IPOD";

    /// <summary>
    /// Tolerancia de tamaño al re-verificar. El disco del iPod puede reportar un
    /// tamaño ligeramente distinto entre reconexiones; fuera de este margen ya no
    /// es "el mismo disco" y la operación se aborta.
    /// </summary>
    public long SizeToleranceBytes { get; init; } = 64L * 1024 * 1024;

    /// <summary>
    /// Ensayo: el proceso elevado hace **todas** las comprobaciones y devuelve la
    /// bitácora completa de lo que haría, pero no escribe un solo byte.
    ///
    /// Existe porque nada de esta cadena se puede probar sin un iPod y permisos
    /// de administrador: permite validar de punta a punta — elevación, paso de
    /// la petición, re-verificación del disco, plan de particionado y geometría
    /// FAT32 — sin arriesgar el disco de nadie. Es la primera cosa que se corre
    /// con hardware real, antes de cualquier formateo de verdad.
    /// </summary>
    public bool DryRun { get; init; }

    /// <summary>
    /// Motivo por el que la petición no es válida, o <c>null</c> si lo es. Se
    /// devuelve el texto y no un booleano porque este mensaje termina en pantalla:
    /// una operación privilegiada que se rehúsa tiene que decir exactamente por qué.
    /// </summary>
    public string? Validate()
    {
        switch (Kind)
        {
            case PrivilegedOperationKind.FormatIPodFat32:
                if (DiskNumber < 0 || DiskNumber > 99)
                    return $"El número de disco {DiskNumber} está fuera de rango.";
                if (ExpectedSizeBytes <= 0)
                    return "La petición no trae el tamaño esperado del disco, así que no se puede re-verificar.";
                if (SizeToleranceBytes < 0)
                    return "La tolerancia de tamaño no puede ser negativa.";
                if (Fat32Formatter.NormalizeLabel(VolumeLabel).Trim().Length == 0)
                    return "La etiqueta del volumen quedó vacía.";
                return null;

            case PrivilegedOperationKind.PauseAppleMobileDeviceService:
            case PrivilegedOperationKind.ResumeAppleMobileDeviceService:
                return null;

            default:
                return "Operación privilegiada desconocida.";
        }
    }

    public string ToJson() => JsonSerializer.Serialize(this, JsonOptions);

    public static PrivilegedOperation? FromJson(string json)
    {
        try
        {
            return JsonSerializer.Deserialize<PrivilegedOperation>(json, JsonOptions);
        }
        catch (JsonException)
        {
            return null;
        }
    }

    internal static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        WriteIndented = false
    };
}

/// <summary>Cómo terminó una operación privilegiada.</summary>
public sealed record PrivilegedOperationResult
{
    public bool Success { get; init; }

    /// <summary>
    /// Se abortó por seguridad: el disco ya no es el que el usuario confirmó. Es
    /// distinto de un fallo — el equivalente del <c>AURA_SAFETY_ABORT</c> de macOS
    /// — y la UI lo explica sin culpar al usuario ni al aparato.
    /// </summary>
    public bool SafetyAbort { get; init; }

    public string Message { get; init; } = "";

    /// <summary>Bitácora de lo que hizo el proceso elevado, para poder mostrarla si algo sale mal.</summary>
    public IReadOnlyList<string> Log { get; init; } = [];

    public string ToJson() => JsonSerializer.Serialize(this, PrivilegedOperation.JsonOptions);

    public static PrivilegedOperationResult? FromJson(string json)
    {
        try
        {
            return JsonSerializer.Deserialize<PrivilegedOperationResult>(json, PrivilegedOperation.JsonOptions);
        }
        catch (JsonException)
        {
            return null;
        }
    }

    public static PrivilegedOperationResult Ok(string message, IReadOnlyList<string>? log = null) =>
        new() { Success = true, Message = message, Log = log ?? [] };

    public static PrivilegedOperationResult Failure(string message, IReadOnlyList<string>? log = null) =>
        new() { Success = false, Message = message, Log = log ?? [] };

    public static PrivilegedOperationResult Abort(string reason, IReadOnlyList<string>? log = null) =>
        new() { Success = false, SafetyAbort = true, Message = reason, Log = log ?? [] };
}
