using AuraStudio.Core.Installer;

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

    // MARK: - La salida cuando el DFU no se detecta (ST-143 addendum, ST-169)

    /// <summary>
    /// Segundos que se espera en la pantalla de DFU antes de ofrecer la ayuda
    /// de último recurso. <b>Veinte y no menos</b>: la combinación de botones
    /// tarda doce, así que un plazo más corto ofrecería la ayuda mientras el
    /// usuario todavía la está haciendo.
    /// </summary>
    public const double AssistDelaySeconds = 20;

    /// <summary>
    /// Si la pantalla de DFU debe ofrecer pausar el servicio de Apple.
    ///
    /// <para>El flujo de actualizar el arranque arranca con <b>cero diálogos de
    /// permiso</b> a propósito, así que esta ayuda no puede estar desde el
    /// principio: aparece solo cuando ya se esperó de más y el iPod sigue sin
    /// detectarse. En el instalador completo no se ofrece acá, porque ese flujo
    /// ya la propone antes de llegar al DFU — y pedir permiso dos veces por lo
    /// mismo es peor que no ofrecerlo.</para>
    /// </summary>
    public static bool ShouldOfferServicePause(InstallerMode mode, double secondsWaiting,
                                               bool isDfuDetected, bool alreadyPaused)
    {
        if (mode != InstallerMode.UpdateBootloader) return false;
        if (isDfuDetected || alreadyPaused) return false;

        return secondsWaiting >= AssistDelaySeconds;
    }
}
