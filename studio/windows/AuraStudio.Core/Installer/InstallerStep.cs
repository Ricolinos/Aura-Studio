namespace AuraStudio.Core.Installer;

/// <summary>
/// Pasos del asistente de instalación/restauración. Port de
/// <c>Models/InstallerStep.swift</c> (macOS) — mismos casos, mismo orden y
/// mismos significados. El flujo normal es lineal, pero varios pasos avanzan
/// solos cuando la sesión del dispositivo (o el resultado de una operación
/// privilegiada) confirma el estado esperado.
///
/// Dos órdenes según el modo de arranque (ST-017):
///
/// <list type="bullet">
/// <item><b>Dual boot</b>: primero se prepara el disco de datos (copiar los
/// archivos del firmware) mientras el iPod todavía corre su firmware original
/// y está montado en modo disco normal — no requiere DFU, porque en el iPod 6G
/// el bootloader vive en NOR flash interna, separada del disco. Recién al final
/// se entra a DFU para flashear.</item>
/// <item><b>Solo firmware</b> (<c>--single</c>, destruye el arranque de Apple):
/// el flasheo va PRIMERO. Se formatea el disco (todavía con Apple corriendo),
/// se flashea por DFU, el iPod se reinicia solo y — como aún no tiene
/// <c>rockbox.ipod</c> — su bootloader cae en <c>fatal_error(ERR_RB)</c> y entra
/// automáticamente a "Bootloader USB mode": aparece como disco, y RECIÉN AHÍ se
/// copia el firmware.</item>
/// </list>
/// </summary>
public enum InstallerStep
{
    Welcome,

    /// <summary>
    /// ST-050: ya no se visita (la instalación es siempre Solo firmware). Se
    /// conserva el caso para no renumerar ni romper el <c>switch</c> exhaustivo,
    /// exactamente como en el Swift.
    /// </summary>
    ChooseBootMode,

    Permissions,
    DetectDevice,
    PreparingDisk,
    CopyingFiles,
    EnterDfu,
    Installing,

    /// <summary>
    /// Solo en Solo firmware (ST-017): el bootloader ya quedó grabado y se
    /// espera a que el iPod reaparezca como disco en "Bootloader USB mode" (o
    /// corriendo el firmware) para copiar los archivos.
    /// </summary>
    AwaitingBootloaderUsb,

    /// <summary>
    /// Solo en modo restaurar (D-184): tras quitar el bootloader por DFU,
    /// esperar a que el iPod reaparezca como disco y prepararlo para el
    /// restaurador de Apple.
    /// </summary>
    RestoreFormatting,

    /// <summary>
    /// Solo en modo restaurar: el disco quedó listo — la restauración del
    /// firmware de Apple la termina la app de Apple (Apple Devices / iTunes en
    /// Windows), con Aura Studio cerrado para no interferir con la detección USB.
    /// </summary>
    RestoreHandoff,

    Done,
    Failed
}

/// <summary>Instalar el firmware, o devolver el iPod a su firmware original.</summary>
public enum InstallerMode
{
    Install,
    Restore
}
