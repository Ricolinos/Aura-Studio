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
        public override string Message => "No se detectó ningún iPod conectado.";
    }

    public sealed record WrongDiskFormat : InstallerError
    {
        public override string Message =>
            "El iPod no está formateado en FAT32. Conviértelo antes de continuar.";
    }

    public sealed record DfuTimeout : InstallerError
    {
        public override string Message =>
            "No se detectó el iPod en modo DFU a tiempo. Vuelve a intentar la combinación de botones.";
    }

    public sealed record ChecksumMismatch(string File) : InstallerError
    {
        public override string Message =>
            $"El archivo {File} no superó la verificación de integridad.";
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
            $"El firmware de este Release está incompleto: a rockbox.zip le faltan {string.Join(", ", Missing)} " +
            "— el iPod quedaría sin video o sin audio. No es un problema de tu conexión; vuelve a intentar más " +
            "tarde o avisa que este Release salió mal.";
    }

    /// <summary>
    /// Sin nombrar la herramienta: este error lo producen tanto mks5lboot como
    /// la extracción del árbol — el texto viejo de macOS culpaba a mks5lboot de
    /// fallas que no eran suyas (visto en vivo, D-185).
    /// </summary>
    public sealed record ProcessFailed(int ExitCode, string Output) : InstallerError
    {
        public override string Message => $"La operación terminó con código {ExitCode}: {Output}";
    }

    public sealed record MissingArtifact(string Name) : InstallerError
    {
        public override string Message =>
            $"Falta el artefacto {Name} entre los archivos del firmware. Vuelve a correr scripts\\FirmwareFetch.ps1.";
    }

    public sealed record DiskAmbiguous(int Count) : InstallerError
    {
        public override string Message =>
            $"Se encontraron {Count} discos que podrían ser tu iPod. Por seguridad, Aura Studio no elige uno " +
            "solo — desconecta los demás discos externos y vuelve a intentar.";
    }

    /// <summary>El usuario cerró el diálogo de Control de cuentas de usuario (UAC).</summary>
    public sealed record AuthorizationCancelled : InstallerError
    {
        public override string Message =>
            "Cancelaste el permiso de administrador. Este paso no puede continuar sin ese permiso.";
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
        public override string Message =>
            "Para dual boot, el iPod debe conservar el firmware original de Apple en formato \"winpod\": tabla de " +
            "particiones MBR con la partición de firmware de Apple intacta más una partición FAT32 — el formato que " +
            "crea iTunes al restaurar en una PC con Windows. Este iPod está en formato de Mac (particiones " +
            "Apple/HFS, que Rockbox no puede leer) o su disco no es legible, y prepararlo desde aquí borraría el " +
            "disco completo, incluido el firmware original. Opciones: restaura el iPod con iTunes/Apple Devices y " +
            "vuelve a intentar dual boot, o instala solo el firmware si no necesitas conservar el de Apple.";
    }

    public sealed record DeviceDisconnectedDuringCopy : InstallerError
    {
        public override string Message =>
            "Tu iPod se desconectó durante la copia de archivos. Copiar el firmware completo son miles de archivos " +
            "chicos y puede tardar varios minutos por USB — revisa el cable (evita concentradores USB si usas uno) " +
            "y vuelve a intentar: lo que ya se copió no se pierde, la copia sigue desde donde quedó.";
    }

    /// <summary>
    /// mks5lboot confirmó el ENVÍO por USB (D-191) pero el iPod nunca salió de
    /// modo DFU — no hay evidencia de que aplicara el flasheo.
    /// </summary>
    public sealed record DeviceStuckInDfu : InstallerError
    {
        public override string Message =>
            "El iPod recibió el envío del firmware, pero nunca confirmó haberlo aplicado — sigue en modo DFU. Si " +
            "Windows abrió iTunes o Apple Devices mostrando el iPod en modo de recuperación, ciérralo SIN tocar " +
            "\"Restaurar\" (eso reinstalaría el firmware original de Apple). Después vuelve a intentar: el iPod ya " +
            "está en modo DFU, así que el reintento debería llegar rápido a este mismo paso.";
    }

    /// <summary>
    /// ST-017 (Solo firmware): tras el flasheo <c>--single</c>, el iPod reapareció
    /// atendiendo el USB con el firmware original de Apple — el bootloader no
    /// quedó grabado (con <c>--single</c> el arranque de Apple ya no debería existir).
    /// </summary>
    public sealed record BootloaderNotApplied : InstallerError
    {
        public override string Message =>
            "El iPod volvió a aparecer con el firmware original de Apple atendiendo el USB: el bootloader no quedó " +
            "grabado. Vuelve a intentar el paso de DFU (el disco ya está preparado, no hace falta formatearlo otra vez).";
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
            $"No se pudo descargar la versión más reciente de {Family}: {Reason} Se usará la versión que trae Aura Studio.";
    }

    /// <summary>ST-077: al Release publicado le falta un asset de la tabla §A del contrato.</summary>
    public sealed record ReleaseMissingAsset(string Tag, string Asset) : InstallerError
    {
        public override string Message =>
            $"Al Release {Tag} le falta {Asset}, así que no se puede instalar desde él. Se usará la versión que trae Aura Studio.";
    }

    /// <summary>
    /// Riesgo #4 del plan v1, específico de Windows: en macOS el sistema habla
    /// con un dispositivo DFU sin driver de terceros; en Windows hace falta uno
    /// (el de Apple Mobile Device Support, o WinUSB). Sin él, mks5lboot no ve el
    /// iPod aunque esté en DFU.
    /// </summary>
    public sealed record DfuDriverMissing : InstallerError
    {
        public override string Message =>
            "Windows no tiene un controlador para tu iPod en modo DFU, así que Aura Studio no puede hablarle. " +
            "Instala Apple Devices (o iTunes) desde la Microsoft Store, o asigna el controlador WinUSB al " +
            "dispositivo con Zadig; el paso de permisos explica ambas opciones.";
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
