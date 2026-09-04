using System.Globalization;
using System.Text;
using AuraStudio.Core;

namespace AuraStudio.Core.Installer;

/// <summary>
/// ST-056 / <c>CONTRATO-firmware-studio.md</c> v10 (v14: hasta tres familias):
/// varios firmwares instalados a la vez y conmutación entre ellos POR RENOMBRE,
/// sin borrar ni descargar. Port de <c>Services/FirmwareSwitcher.swift</c>.
///
/// El árbol activo es siempre <c>/.rockbox/</c> (lo único que el bootloader
/// compartido sabe arrancar); el de cualquier otra familia duerme como
/// <c>/.firmware-&lt;familia&gt;/</c>, completo y con sus propios ajustes. Cambiar
/// de firmware son dos renombres en FAT (instantáneos), en un orden que importa
/// — el saliente primero — más el respaldo del bootloader en la raíz y el
/// marcador de sync para que el entrante reconstruya su base de datos.
///
/// <b>INVARIANTE (ST-069/ST-073/ST-147, contrato v15/v16/v19)</b>: todo lo de
/// acá opera SOLO sobre <c>/.rockbox/</c>, <c>/.firmware-*/</c> y
/// <c>/rockbox.ipod</c>. <c>/.aura/tagcache/</c> (base compartida por los tres
/// firmwares), <c>/.aura/thumbs/</c> (miniaturas compartidas),
/// <c>/.aura/art/</c> (caché maestra de imágenes) y
/// <see cref="SharedSettingsRelativePath"/> (ajustes compartidos) son
/// propiedad del firmware aunque vivan bajo <c>/.aura/</c>: ningún renombre,
/// estacionamiento, reparación, siembra ni espejo los toca.
/// </summary>
public static class FirmwareSwitcher
{
    public const string ActiveTreeName = ".rockbox";
    public const string RootFirmwareBinaryName = "rockbox.ipod";

    /// <summary>
    /// ST-147 / contrato v19: ajustes compartidos entre las tres familias
    /// (bloqueo, brillo, idioma, etc.). Es un ARCHIVO, no un directorio, pero
    /// la regla es la misma que <c>/.aura/art/</c> desde ST-073 — Studio nunca
    /// lo borra, mueve ni reescribe. Ningún código de este repo enumera
    /// <c>/.aura/</c> de forma amplia (cada operación nombra explícitamente lo
    /// que le toca, ver <c>LibrarySyncEngine.ClearFirmwareDatabases</c>), así
    /// que esta constante existe para que la protección quede fijada por
    /// pruebas, no solo asumida.
    /// </summary>
    public const string SharedSettingsRelativePath = ".aura/settings.cfg";

    /// <summary>
    /// ST-059 / contrato v12: sello de biblioteca compartido — cambia solo
    /// cuando un sync toca música. Igualdad exacta de sellos = la base del árbol
    /// entrante sigue válida = no se escribe marcador.
    /// </summary>
    public const string LibraryStampRelativePath = ".aura/library-stamp";

    /// <summary>
    /// Hasta v14 la anotación vivía por árbol; desde v15 el firmware la
    /// lee/escribe en <c>/.aura/tagcache/db_stamp.txt</c>. Studio conserva la
    /// ruta por árbol solo para compararla al cambiar de familia con árboles
    /// anteriores a v15.
    /// </summary>
    public const string DbStampRelativePathInTree = "aura/db_stamp.txt";

    /// <summary>Motivos por los que un cambio de familia no se puede hacer.</summary>
    public enum SwitchFailure
    {
        None,
        /// <summary>No hay <c>/.firmware-&lt;familia&gt;/</c> que despertar.</summary>
        DormantTreeMissing,
        /// <summary>La familia pedida ya es la activa.</summary>
        AlreadyActive,
        /// <summary>Una familia que no se puede estacionar ni despertar (desconocida).</summary>
        FamilyNotSwitchable
    }

    public sealed class SwitchException(SwitchFailure failure, FirmwareFamily family)
        : Exception(Describe(failure, family))
    {
        public SwitchFailure Failure { get; } = failure;
        public FirmwareFamily Family { get; } = family;

        private static string Describe(SwitchFailure failure, FirmwareFamily family) => failure switch
        {
            SwitchFailure.DormantTreeMissing => $"No hay un árbol dormido de {family.DisplayName} en este iPod.",
            SwitchFailure.AlreadyActive => $"{family.DisplayName} ya es el firmware activo.",
            SwitchFailure.FamilyNotSwitchable => $"Aura Studio no sabe cómo estacionar ni despertar {family.DisplayName}.",
            _ => "No se pudo cambiar de firmware."
        };
    }

    private static string Combine(string root, string relative) =>
        Path.Combine(root, relative.Replace('/', Path.DirectorySeparatorChar));

    /// <summary>Qué familias tienen un árbol dormido en el volumen.</summary>
    public static IReadOnlyList<FirmwareFamily> DormantFamilies(string volumeRoot) =>
        FirmwareFamily.Installable
            .Where(family => family.DormantTreeName is { } name && Directory.Exists(Path.Combine(volumeRoot, name)))
            .ToList();

    public static bool HasActiveTree(string volumeRoot) =>
        Directory.Exists(Path.Combine(volumeRoot, ActiveTreeName));

    /// <summary>
    /// Un cambio que quedó a medias (batería, cable): sin <c>/.rockbox/</c> pero
    /// con exactamente un árbol dormido. Se repara despertándolo. Con dos
    /// dormidos y ninguno activo <b>no se adivina</b>: se deja como está y se
    /// devuelve <c>null</c> (contrato v14 — Studio pide elegir).
    /// </summary>
    public static FirmwareFamily? RepairIfNeeded(string volumeRoot)
    {
        if (HasActiveTree(volumeRoot)) return null;
        var dormant = DormantFamilies(volumeRoot);
        if (dormant.Count != 1) return null;
        var family = dormant[0];
        if (family.DormantTreeName is not { } name) return null;

        Directory.Move(Path.Combine(volumeRoot, name), Path.Combine(volumeRoot, ActiveTreeName));
        RefreshRootBinary(volumeRoot);
        return family;
    }

    /// <summary>
    /// Estaciona el árbol activo como dormido de <paramref name="family"/>
    /// (reemplazando un dormido anterior de esa misma familia, si lo hubiera —
    /// nunca dos de la misma). Lo usa el instalador antes de instalar OTRA
    /// familia en <c>/.rockbox/</c>, en vez de borrarla.
    /// </summary>
    public static void ParkActiveTree(FirmwareFamily family, string volumeRoot)
    {
        if (family.DormantTreeName is not { } name)
            throw new SwitchException(SwitchFailure.FamilyNotSwitchable, family);

        string active = Path.Combine(volumeRoot, ActiveTreeName);
        string dormant = Path.Combine(volumeRoot, name);
        if (!Directory.Exists(active)) return;
        if (Directory.Exists(dormant)) Directory.Delete(dormant, true);
        Directory.Move(active, dormant);
    }

    /// <summary>
    /// Borra el árbol dormido de <paramref name="family"/> si existe (tras
    /// instalar esa familia fresca en <c>/.rockbox/</c>: nunca un dormido de la
    /// familia activa).
    /// </summary>
    public static void RemoveDormantTree(FirmwareFamily family, string volumeRoot)
    {
        if (family.DormantTreeName is not { } name) return;
        string dormant = Path.Combine(volumeRoot, name);
        if (Directory.Exists(dormant)) Directory.Delete(dormant, true);
    }

    /// <summary>
    /// EL cambio (contrato v10, pasos 2–5; el 1 — que el firmware guarde lo suyo
    /// — no aplica desde Studio porque el firmware no está corriendo en modo
    /// disco, y el 6 — reiniciar — lo hace el usuario al expulsar):
    /// <code>
    /// /.rockbox/               -> /.firmware-&lt;activa&gt;/
    /// /.firmware-&lt;destino&gt;/ -> /.rockbox/
    /// /rockbox.ipod            := /.rockbox/rockbox.ipod del entrante
    /// /.aura/sync-pending.json  con music: true, SOLO si el sello lo pide (v12)
    /// </code>
    /// </summary>
    public static void SwitchActiveFirmware(FirmwareFamily target, FirmwareFamily currentlyActive, string volumeRoot)
    {
        if (Equals(target, currentlyActive)) throw new SwitchException(SwitchFailure.AlreadyActive, target);
        if (target.DormantTreeName is not { } targetName) throw new SwitchException(SwitchFailure.FamilyNotSwitchable, target);
        if (currentlyActive.DormantTreeName is not { } activeName) throw new SwitchException(SwitchFailure.FamilyNotSwitchable, currentlyActive);

        string active = Path.Combine(volumeRoot, ActiveTreeName);
        string targetDormant = Path.Combine(volumeRoot, targetName);
        string parkedActive = Path.Combine(volumeRoot, activeName);

        if (!Directory.Exists(targetDormant)) throw new SwitchException(SwitchFailure.DormantTreeMissing, target);

        // (2) saliente primero: el peor caso (corte acá) deja un árbol dormido
        // entero y ninguno activo — RepairIfNeeded() lo levanta.
        if (Directory.Exists(active))
        {
            if (Directory.Exists(parkedActive)) Directory.Delete(parkedActive, true);
            Directory.Move(active, parkedActive);
        }
        // (3) entrante
        Directory.Move(targetDormant, active);
        // (4) respaldo del bootloader
        RefreshRootBinary(volumeRoot);
        // (5) v12/ST-059: el marcador solo si la biblioteca cambió desde que el
        // ENTRANTE construyó su base — sin sync de por medio, el cambio es
        // instantáneo y sin reconstrucción.
        if (!IncomingDatabaseIsCurrent(volumeRoot, currentlyActive))
        {
            new SyncPendingMarker(new SyncPendingMarker.Changes(Music: true, Video: false, Images: false))
                .Write(volumeRoot);
        }

        // ST-146 / maestro §B: el árbol que acaba de despertar puede llevar
        // días o semanas dormido — su reloj queda tan atrasado como el último
        // apagado. Se sincroniza acá, en el árbol ENTRANTE (ya renombrado a
        // ActiveTreeName arriba), sin esperar a que el usuario desconecte y
        // vuelva a conectar.
        ClockSyncWriter.WriteToDisk(volumeRoot);
    }

    /// <summary>
    /// ST-059: compara el sello del árbol ya renombrado a <c>/.rockbox/</c> (el
    /// entrante) contra <c>/.aura/library-stamp</c>. Si el sello compartido falta
    /// (primer cambio tras v12), lo crea y lo anota como del SALIENTE — su base
    /// sí está al día, acaba de estar corriendo — para que el próximo cambio de
    /// vuelta ya no reconstruya.
    /// </summary>
    private static bool IncomingDatabaseIsCurrent(string volumeRoot, FirmwareFamily outgoing)
    {
        string stampPath = Combine(volumeRoot, LibraryStampRelativePath);
        string? stamp = ReadTrimmed(stampPath);

        if (string.IsNullOrEmpty(stamp))
        {
            string fresh = MakeLibraryStamp();
            TryWriteLine(stampPath, fresh);
            if (outgoing.DormantTreeName is { } name)
            {
                TryWriteLine(Path.Combine(volumeRoot, name, DbStampRelativePathInTree.Replace('/', Path.DirectorySeparatorChar)), fresh);
            }
            stamp = fresh;
        }

        string incoming = Path.Combine(volumeRoot, ActiveTreeName,
            DbStampRelativePathInTree.Replace('/', Path.DirectorySeparatorChar));
        string? recorded = ReadTrimmed(incoming);
        return recorded is not null && recorded == stamp;
    }

    /// <summary>Una línea opaca: marca de tiempo ISO-8601 + sufijo aleatorio. Se compara por igualdad exacta, nunca se interpreta.</summary>
    public static string MakeLibraryStamp(DateTimeOffset? date = null) =>
        (date ?? DateTimeOffset.Now).ToString("yyyy-MM-ddTHH:mm:sszzz", CultureInfo.InvariantCulture)
        + "-" + Guid.NewGuid().ToString("N")[..8];

    /// <summary>
    /// ST-059: Studio renueva el sello en cada sync que toca música — es LA
    /// definición de "la biblioteca cambió" para el cambio de firmware.
    /// </summary>
    public static void BumpLibraryStamp(string volumeRoot) =>
        TryWriteLine(Combine(volumeRoot, LibraryStampRelativePath), MakeLibraryStamp());

    /// <summary>
    /// <c>/rockbox.ipod</c> (raíz) = el binario del árbol activo. Es lo que el
    /// bootloader arranca si <c>/.rockbox/rockbox.ipod</c> falta; tiene que ser
    /// SIEMPRE el del firmware activo, nunca el de un árbol dormido.
    /// </summary>
    public static void RefreshRootBinary(string volumeRoot)
    {
        string source = Path.Combine(volumeRoot, ActiveTreeName, RootFirmwareBinaryName);
        string root = Path.Combine(volumeRoot, RootFirmwareBinaryName);
        if (!File.Exists(source)) return;
        File.Copy(source, root, overwrite: true);
    }

    /// <summary>
    /// Archivos del contrato que Studio escribe en <c>.rockbox/aura/</c> y que el
    /// firmware dormido también necesita al despertar (v10). <c>aura.cfg</c> NO
    /// (es de cada firmware); <c>themes/</c> tampoco (viaja con su árbol).
    /// <c>aura/db_stamp.txt</c> tampoco: es la anotación de CADA árbol sobre su
    /// propia base. <c>aura/install_manifest.cfg</c> tampoco (v11): es POR ÁRBOL
    /// y espejarlo haría que la actualización selectiva del dormido diera por
    /// escritos archivos que nunca se le escribieron.
    /// </summary>
    public static readonly IReadOnlyList<string> MirroredContractEntries =
    [
        "aura/sync_summary.cfg",
        "aura/sync_manifest.json",
        "aura/artist_images.cfg",
        "aura/artists",
        "aura/video_categories.cfg",
        "aura/photo_categories.cfg",
        "aura/ratings.cfg",
        "aura/device.cfg"
    ];

    /// <summary>
    /// ST-061: el problema inverso al espejo — un árbol ACTIVO recién instalado
    /// (extracción fresca) no tiene los archivos del contrato que Studio escribió
    /// en su vida anterior: sin <c>sync_summary.cfg</c> el firmware dice "sin
    /// sincronizar todavía", sin <c>artist_images.cfg</c>/<c>artists/</c> no hay
    /// fotos de artista, sin <c>*_categories.cfg</c> los videos/fotos salen sin
    /// clasificar. Si el árbol dormido SÍ los tiene, se copian de ahí. Solo
    /// cuando el activo NO tiene <c>sync_summary.cfg</c> — si lo tiene, lo suyo
    /// es igual o más nuevo.
    /// </summary>
    public static bool SeedContractFilesToActiveTree(string volumeRoot)
    {
        string active = Path.Combine(volumeRoot, ActiveTreeName);
        if (File.Exists(Combine(active, "aura/sync_summary.cfg"))) return false;

        var donor = DormantFamilies(volumeRoot)
            .Select(family => family.DormantTreeName)
            .OfType<string>()
            .Select(name => Path.Combine(volumeRoot, name))
            .FirstOrDefault(dir => File.Exists(Combine(dir, "aura/sync_summary.cfg")));
        if (donor is null) return false;

        Directory.CreateDirectory(Path.Combine(active, "aura"));
        foreach (var entry in MirroredContractEntries)
        {
            CopyEntry(Combine(donor, entry), Combine(active, entry));
        }
        return true;
    }

    /// <summary>Espeja los archivos del contrato del árbol activo a TODOS los dormidos presentes (v10/v14).</summary>
    public static void MirrorContractFilesToDormantTrees(string volumeRoot)
    {
        string active = Path.Combine(volumeRoot, ActiveTreeName);
        foreach (var family in DormantFamilies(volumeRoot))
        {
            if (family.DormantTreeName is not { } name) continue;
            string dormant = Path.Combine(volumeRoot, name);
            Directory.CreateDirectory(Path.Combine(dormant, "aura"));
            foreach (var entry in MirroredContractEntries)
            {
                CopyEntry(Combine(active, entry), Combine(dormant, entry));
            }
        }
    }

    /// <summary>Copia un archivo o un directorio completo, reemplazando el destino.</summary>
    private static void CopyEntry(string source, string destination)
    {
        if (Directory.Exists(source))
        {
            if (Directory.Exists(destination)) Directory.Delete(destination, true);
            Directory.CreateDirectory(destination);
            foreach (string file in Directory.EnumerateFiles(source, "*", SearchOption.AllDirectories))
            {
                string target = Path.Combine(destination, Path.GetRelativePath(source, file));
                Directory.CreateDirectory(Path.GetDirectoryName(target)!);
                File.Copy(file, target, overwrite: true);
            }
            return;
        }

        if (!File.Exists(source)) return;
        if (Directory.Exists(destination)) Directory.Delete(destination, true);
        Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
        File.Copy(source, destination, overwrite: true);
    }

    private static string? ReadTrimmed(string path)
    {
        try
        {
            return File.Exists(path) ? File.ReadAllText(path, Encoding.UTF8).Trim() : null;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return null;
        }
    }

    private static void TryWriteLine(string path, string value)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            File.WriteAllText(path, value + "\n", new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            // Perder el sello degrada a "reconstruir la base una vez de más";
            // fallar el cambio de firmware entero sería mucho peor.
        }
    }
}
