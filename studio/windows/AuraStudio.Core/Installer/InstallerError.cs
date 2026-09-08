using AuraStudio.Core.Resources;

namespace AuraStudio.Core.Installer;

/// <summary>
/// Los errores del asistente, con su texto de cara al usuario. Port de
/// <c>InstallerError</c> (Swift, <c>Models/InstallerStep.swift</c>): un
/// <c>enum</c> con valores asociados en Swift se modela acá como jerarquía
/// cerrada de <c>record</c>, el mismo patrón que ya usa
/// <c>DiskIdentificationResult</c> en este proyecto.
///
/// El texto vive junto al caso a propósito (igual que en el Swift): es lo que
/// hace imposible que un error nuevo llegue a la pantalla sin explicación. Un
/// caso sin equivalente en Windows no se porta con un texto de macOS traducido
/// a medias — se retira y se anota por qué (ver <c>ESTADO-PORT.md</c>).
/// </summary>
public abstract record InstallerError
{
    /// <summary>Explicación en español de México, lista para mostrar.</summary>
    public abstract string Message { get; }

    public sealed record DeviceNotFound : InstallerError
    {
        public override string Message => Strings.Get("installer-error.device-not-found");
    }

    public sealed record WrongDiskFormat : InstallerError
    {
        public override string Message => Strings.Get("installer-error.wrong-disk-format");
    }

    public sealed record DfuTimeout : InstallerError
    {
        public override string Message => Strings.Get("installer-error.dfu-timeout");
    }

    public sealed record ChecksumMismatch(string File) : InstallerError
    {
        public override string Message => Strings.Format("installer-error.checksum-mismatch", File);
    }

    /// <summary>
    /// D-297/D-298 (Aura-Firmware), ST-018: <c>rockbox.zip</c> pasó su checksum
    /// pero le faltan entradas reales (códecs/plugins) — un Release mal
    /// empaquetado del lado del firmware, no un problema de transferencia. Un
    /// checksum correcto por sí solo nunca lo hubiera detectado.
    /// </summary>
    public sealed record IncompleteRockboxTree(IReadOnlyList<string> Missing) : InstallerError
    {
        public override string Message =>
            Strings.Format("installer-error.incomplete-rockbox-tree", string.Join(", ", Missing));
    }

    /// <summary>
    /// Sin nombrar la herramienta: este error lo producen tanto mks5lboot como
    /// la extracción del árbol — el texto viejo de macOS culpaba a mks5lboot de
    /// fallas que no eran suyas (visto en vivo, D-185).
    /// </summary>
    public sealed record ProcessFailed(int ExitCode, string Output) : InstallerError
    {
        public override string Message => Strings.Format("installer-error.process-failed", ExitCode, Output);
    }

    public sealed record MissingArtifact(string Name) : InstallerError
    {
        public override string Message => Strings.Format("installer-error.missing-artifact", Name);
    }

    public sealed record DiskAmbiguous(int Count) : InstallerError
    {
        public override string Message => Strings.Plural("installer-error.disk-ambiguous", Count);
    }

    /// <summary>El usuario cerró el diálogo de Control de cuentas de usuario (UAC).</summary>
    public sealed record AuthorizationCancelled : InstallerError
    {
        public override string Message => Strings.Get("installer-error.authorization-cancelled");
    }

    public sealed record PrivilegedOperationFailed(string Detail) : InstallerError
    {
        public override string Message => Detail;
    }

    /// <summary>
    /// Dual boot elegido pero el disco necesitaría formatearse desde cero — lo
    /// que destruiría justamente el firmware de Apple que dual boot promete
    /// conservar (D-185).
    /// </summary>
    public sealed record DualBootRequiresWinpod : InstallerError
    {
        public override string Message => Strings.Get("installer-error.dual-boot-requires-winpod");
    }

    public sealed record DeviceDisconnectedDuringCopy : InstallerError
    {
        public override string Message => Strings.Get("installer-error.device-disconnected-during-copy");
    }

    /// <summary>
    /// mks5lboot confirmó el ENVÍO por USB (D-191) pero el iPod nunca salió de
    /// modo DFU — no hay evidencia de que aplicara el flasheo.
    /// </summary>
    public sealed record DeviceStuckInDfu : InstallerError
    {
        public override string Message => Strings.Get("installer-error.device-stuck-in-dfu");
    }

    /// <summary>
    /// ST-017 (Solo firmware): tras el flasheo <c>--single</c>, el iPod reapareció
    /// atendiendo el USB con el firmware original de Apple — el bootloader no
    /// quedó grabado (con <c>--single</c> el arranque de Apple ya no debería existir).
    /// </summary>
    public sealed record BootloaderNotApplied : InstallerError
    {
        public override string Message => Strings.Get("installer-error.bootloader-not-applied");
    }

    /// <summary>
    /// ST-077: no se pudo bajar el Release más nuevo (sin red, token sin acceso,
    /// Release incompleto). <b>Nunca es fatal por sí mismo</b>: el instalador cae
    /// a los artefactos locales y sigue. El caso existe para poder DECIR por qué
    /// se instaló la versión incluida en vez de la más nueva, no para detener nada.
    /// </summary>
    public sealed record ReleaseDownloadFailed(string Family, string Reason) : InstallerError
    {
        public override string Message =>
            Strings.Format("installer-error.release-download-failed", Family, Reason);
    }

    /// <summary>ST-077: al Release publicado le falta un asset de la tabla §A del contrato.</summary>
    public sealed record ReleaseMissingAsset(string Tag, string Asset) : InstallerError
    {
        public override string Message =>
            Strings.Format("installer-error.release-missing-asset", Tag, Asset);
    }

    /// <summary>
    /// Riesgo #4 del plan v1, específico de Windows: en macOS el sistema habla
    /// con un dispositivo DFU sin driver de terceros; en Windows hace falta uno
    /// (el de Apple Mobile Device Support, o WinUSB). Sin él, mks5lboot no ve el
    /// iPod aunque esté en DFU.
    /// </summary>
    public sealed record DfuDriverMissing : InstallerError
    {
        public override string Message => Strings.Get("installer-error.dfu-driver-missing");
    }
}

/// <summary>
/// Excepción que transporta un <see cref="InstallerError"/> por la pila de
/// llamadas. Existe solo para no repetir <c>(bool ok, InstallerError? err)</c>
/// en cada método: el error de dominio sigue siendo el <see cref="Error"/>.
/// </summary>
public sealed class InstallerException(InstallerError error) : Exception(error.Message)
{
    public InstallerError Error { get; } = error;
}
