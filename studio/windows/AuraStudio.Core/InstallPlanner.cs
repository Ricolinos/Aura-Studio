namespace AuraStudio.Core;

/// <summary>La primera acción del instalador al confirmar el dispositivo.</summary>
public enum InstallAction
{
    /// <summary>
    /// Copiar los archivos ahora (dual boot; o el bootloader ya está, por
    /// evidencia o porque se grabó en esta corrida).
    /// </summary>
    CopyFiles,

    /// <summary>Formatear el disco y después ir a DFU (Solo Aura).</summary>
    FormatThenFlash,

    /// <summary>
    /// Formatear el disco y después copiar (el bootloader ya se grabó en esta
    /// corrida y el disco no está en FAT32).
    /// </summary>
    FormatThenCopy,

    /// <summary>Ir a DFU ahora (Solo Aura con el disco ya listo).</summary>
    EnterDfu,

    /// <summary>
    /// Dual boot sobre un disco que habría que formatear: se detiene antes de
    /// borrar nada (D-185). Formatear destruiría el firmware original de Apple,
    /// que es justamente lo que "dual boot" promete conservar.
    /// </summary>
    RefuseDualBootRequiresWinpod
}

/// <param name="Action">Qué hacer primero.</param>
/// <param name="FlashFirst">`true` cuando el flasheo va antes que la copia (Solo Aura).</param>
public readonly record struct InstallPlan(InstallAction Action, bool FlashFirst);

/// <summary>
/// ST-017: decide, **sin tocar nada**, cuál es la primera acción del instalador
/// al confirmar el dispositivo. Es la parte del asistente que se puede probar
/// con datos sintéticos, separada a propósito de la que escribe en el disco.
///
/// Dos órdenes según el modo de arranque:
/// <list type="bullet">
/// <item>Dual boot: copiar primero (el modo disco de Apple sirve el USB), DFU al final.</item>
/// <item>Solo Aura (<c>--single</c>): formatear, flashear por DFU, y copiar
/// DESPUÉS vía el "Bootloader USB mode" del bootloader recién grabado.</item>
/// </list>
/// </summary>
public static class InstallPlanner
{
    /// <param name="volumeIsFat32">
    /// `true`/`false` para un volumen montado; `null` cuando el disco no tiene
    /// ningún sistema de archivos legible (disco de fábrica en blanco, o tabla
    /// de particiones rota por una instalación interrumpida).
    /// </param>
    /// <param name="singleBoot">El usuario eligió Solo Aura (<c>--single</c>).</param>
    /// <param name="canSkipFlash">
    /// Evidencia suficiente de que el bootloader de la familia Rockbox ya está
    /// en la NOR (ST-016) — la NOR misma no se puede leer desde una PC.
    /// </param>
    /// <param name="deviceIsAura">
    /// Aura verificada en el disco: en Solo Aura se conserva la biblioteca en
    /// vez de formatear.
    /// </param>
    /// <param name="bootloaderFlashedThisFlow">
    /// El flasheo ya se hizo en esta corrida (reintento tras un problema posterior).
    /// </param>
    /// <param name="diskPreparedThisFlow">El disco ya se formateó en esta corrida.</param>
    public static InstallPlan Plan(bool? volumeIsFat32,
                                   bool singleBoot,
                                   bool canSkipFlash,
                                   bool deviceIsAura,
                                   bool bootloaderFlashedThisFlow,
                                   bool diskPreparedThisFlow)
    {
        if (volumeIsFat32 != true)
        {
            // Hay que formatear.
            if (!singleBoot) return new InstallPlan(InstallAction.RefuseDualBootRequiresWinpod, false);
            if (bootloaderFlashedThisFlow) return new InstallPlan(InstallAction.FormatThenCopy, false);
            return new InstallPlan(InstallAction.FormatThenFlash, true);
        }

        if (canSkipFlash || bootloaderFlashedThisFlow)
        {
            return new InstallPlan(InstallAction.CopyFiles, false);
        }

        if (singleBoot)
        {
            // Sin Aura verificada se formatea limpio: en Solo Aura no hay
            // partición del firmware de Apple que conservar, y un disco con el
            // firmware original (o archivos sueltos) no aporta nada. Con Aura
            // verificada, o ya formateado en esta corrida, directo a DFU.
            if (diskPreparedThisFlow || deviceIsAura)
            {
                return new InstallPlan(InstallAction.EnterDfu, true);
            }
            return new InstallPlan(InstallAction.FormatThenFlash, true);
        }

        return new InstallPlan(InstallAction.CopyFiles, false);
    }
}
