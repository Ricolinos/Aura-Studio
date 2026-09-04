namespace AuraStudio.Core;

/// <summary>
/// Cuándo ofrecer "Actualizar el arranque" (ST-143, plan maestro §B.5).
///
/// <para>El bootloader vive en la NOR del iPod y <b>no se puede leer desde la
/// computadora</b> — la única forma de saber cuál está grabado es acordarse de
/// haberlo grabado. Cuando el pin de <c>FIRMWARE_VERSION</c> trae un
/// <c>bootloader-ipod6g.ipod</c> distinto al registrado, esta es la regla que
/// decide si vale la pena decírselo al usuario.</para>
///
/// <para>Es aritmética de tres datos, sin disco ni red de por medio, para que
/// se pueda probar entera — la misma decisión y los mismos casos que
/// <c>BootloaderUpdate.swift</c> en macOS.</para>
/// </summary>
public static class BootloaderUpdate
{
    /// <summary>
    /// Un disco verificado por una versión anterior, que anotaba fecha y no
    /// hash. No es "sin verificar": el bootloader está, solo que no se sabe de
    /// qué versión — por eso se ofrece actualizarlo, sin exigirlo.
    /// </summary>
    public const string UnknownBootloader = "unknown";

    /// <summary>Por qué se ofrece, para poder decirlo en pantalla.</summary>
    public enum Reason
    {
        /// <summary>Se sabe que el arranque grabado es de otra versión.</summary>
        DifferentBootloader,

        /// <summary>
        /// El iPod se instaló con una versión que no anotaba cuál — o lo
        /// instaló otra computadora. Puede que ya esté al día.
        /// </summary>
        UnknownBootloader
    }

    /// <summary>
    /// <c>true</c> si hay algo que ofrecer.
    /// </summary>
    /// <param name="recordedHash">
    /// Lo que esta instalación anotó para ese disco. <c>null</c> = nunca le
    /// verificó el arranque; <see cref="UnknownBootloader"/> = lo verificó una
    /// versión anterior a ST-143, que no guardaba el hash.
    /// </param>
    /// <param name="embeddedHash">
    /// El del <c>bootloader-ipod6g.ipod</c> que trae esta build <b>para la
    /// familia instalada en el iPod</b> — no para la familia por omisión: un
    /// iPod con Metro se compara contra el bootloader de Metro.
    /// </param>
    /// <param name="hasOurFirmware">
    /// Hay rastro de un firmware nuestro en el disco. Sin eso no se ofrece
    /// nada: en un iPod de fábrica lo que corresponde es instalar.
    /// </param>
    public static bool IsAvailable(string? recordedHash, string? embeddedHash, bool hasOurFirmware)
    {
        if (!hasOurFirmware || string.IsNullOrEmpty(embeddedHash)) return false;
        return recordedHash != embeddedHash;
    }

    public static Reason? ReasonFor(string? recordedHash, string? embeddedHash, bool hasOurFirmware)
    {
        if (!IsAvailable(recordedHash, embeddedHash, hasOurFirmware)) return null;

        return recordedHash is null or UnknownBootloader
            ? Reason.UnknownBootloader
            : Reason.DifferentBootloader;
    }
}
