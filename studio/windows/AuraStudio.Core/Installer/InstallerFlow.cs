namespace AuraStudio.Core.Installer;

/// <summary>
/// Qué pasos recorre el asistente según lo que venga a hacer (ST-167).
///
/// <para><b>Hasta acá el instalador de Windows no tenía modos.</b> Solo
/// instalaba: el recorrido vivía disperso en las asignaciones a <c>Step</c> de
/// <c>InstallerViewModel</c>, y no había forma de preguntarle nada sin leerlo
/// entero. Introducir "Actualizar el arranque" obliga a que el recorrido sea un
/// dato y no una consecuencia — si no, cada paso nuevo se decide con un
/// <c>if</c> más, repartido, y la promesa de que ese flujo <b>no</b> pide
/// contraseñas queda escrita en cinco lugares distintos.</para>
///
/// <para>El recorrido de instalar que hay acá es <b>el que el asistente ya
/// hacía</b>, copiado de sus transiciones y fijado con pruebas antes de tocar
/// nada. Esta pieza no cambia ningún flujo: le pone nombre al que había.</para>
///
/// <para><see cref="InstallerStep.Failed"/> no está en ningún recorrido a
/// propósito: se llega desde cualquier paso y no es parte del camino, es su
/// interrupción.</para>
/// </summary>
public static class InstallerFlow
{
    /// <summary>
    /// El asistente completo (ST-017, ST-050): se prepara el disco, se graba
    /// por DFU, el iPod reaparece como disco en "Bootloader USB mode" y recién
    /// ahí se copian los archivos.
    ///
    /// <para><b>Es el recorrido, no una obligación de pisar cada casilla.</b>
    /// Con el iPod ya en DFU al abrir, el asistente salta de la Bienvenida
    /// directo a <see cref="InstallerStep.EnterDfu"/> (<c>AcceptDetectedDfu</c>):
    /// el disco no hace falta prepararlo si lo que sigue es grabar. Ese atajo
    /// existía antes de ST-167 y sigue existiendo — acá se declara a dónde
    /// puede llegar cada modo, no en qué orden está obligado a hacerlo.</para>
    /// </summary>
    private static readonly InstallerStep[] FullInstall =
    [
        InstallerStep.Welcome,
        InstallerStep.Permissions,
        InstallerStep.DetectDevice,
        InstallerStep.PreparingDisk,
        InstallerStep.EnterDfu,
        InstallerStep.Installing,
        InstallerStep.AwaitingBootloaderUsb,
        InstallerStep.CopyingFiles,
        InstallerStep.Done
    ];

    /// <summary>
    /// La actualización directa (D-222): con Aura ya instalado no hace falta
    /// DFU —el arranque ya está en la NOR—, así que actualizar es reemplazar
    /// archivos. Sin bienvenida, sin permisos y sin formatear.
    /// </summary>
    private static readonly InstallerStep[] InPlaceUpdate =
    [
        InstallerStep.CopyingFiles,
        InstallerStep.Done
    ];

    /// <summary>
    /// ST-143: cuatro pasos y <b>ninguno toca el disco</b> — pantalla propia,
    /// DFU, grabar, listo.
    /// </summary>
    private static readonly InstallerStep[] BootloaderOnly =
    [
        InstallerStep.Welcome,
        InstallerStep.EnterDfu,
        InstallerStep.Installing,
        InstallerStep.Done
    ];

    /// <summary>
    /// Los pasos que recorre un modo, en orden.
    /// </summary>
    /// <param name="automaticUpdate">
    /// La actualización directa desde General, que no abre el asistente. Solo
    /// tiene sentido con <see cref="InstallerMode.Install"/>.
    /// </param>
    public static IReadOnlyList<InstallerStep> StepsFor(InstallerMode mode, bool automaticUpdate = false) =>
        mode switch
        {
            InstallerMode.Install => automaticUpdate ? InPlaceUpdate : FullInstall,
            InstallerMode.UpdateBootloader => BootloaderOnly,
            _ => throw NotOnWindows(mode)
        };

    /// <summary>Si ese modo pasa por ese paso.</summary>
    public static bool Visits(InstallerMode mode, InstallerStep step, bool automaticUpdate = false) =>
        StepsFor(mode, automaticUpdate).Contains(step);

    /// <summary>
    /// El paso que sigue a la Bienvenida. Es lo que hace que actualizar el
    /// arranque se salte Permisos: no hay nada privilegiado que pedir.
    /// </summary>
    public static InstallerStep AfterWelcome(InstallerMode mode)
    {
        IReadOnlyList<InstallerStep> steps = StepsFor(mode);

        if (steps.Count < 2 || steps[0] != InstallerStep.Welcome)
            throw new InvalidOperationException($"El modo {mode} no empieza en la Bienvenida.");

        return steps[1];
    }

    /// <summary>
    /// Si el modo escribe en el disco del iPod: formatearlo o copiarle
    /// archivos. <c>false</c> para actualizar el arranque, y esa es justamente
    /// la promesa que le hace su pantalla al usuario — su música, sus fotos y
    /// sus ajustes no se tocan.
    /// </summary>
    public static bool TouchesDisk(InstallerMode mode) =>
        Visits(mode, InstallerStep.PreparingDisk) || Visits(mode, InstallerStep.CopyingFiles);

    /// <summary>
    /// Si el camino <b>normal</b> del modo necesita permisos de administrador.
    /// Instalar sí (formatear el disco); actualizar el arranque no —
    /// <c>mks5lboot</c> no los pide (D-043).
    ///
    /// <para>"Normal" es literal: ST-169 le agrega a la pantalla de DFU una
    /// ayuda opcional que sí los pide, y que aparece solo si el iPod no se
    /// detecta después de esperar. Que sea la excepción y no la regla es el
    /// punto.</para>
    /// </summary>
    public static bool NeedsPrivilegesInNormalPath(InstallerMode mode) =>
        Visits(mode, InstallerStep.PreparingDisk);

    /// <summary>
    /// Si se graba con <c>--single</c>, que borra el arranque de Apple de la
    /// NOR. Instalar sí (ST-050). Actualizar <b>no</b>, a propósito: no puede
    /// destruir más de lo que ya estaba destruido — en un iPod instalado con
    /// Solo firmware el de Apple ya no está, y en uno con dual boot no hay
    /// ninguna razón para quitárselo ahora (ST-143).
    /// </summary>
    public static bool FlashesSingle(InstallerMode mode) => mode switch
    {
        InstallerMode.Install => true,
        InstallerMode.UpdateBootloader => false,
        _ => throw NotOnWindows(mode)
    };

    private static NotSupportedException NotOnWindows(InstallerMode mode) =>
        new($"El modo {mode} no está implementado en el instalador de Windows.");
}
