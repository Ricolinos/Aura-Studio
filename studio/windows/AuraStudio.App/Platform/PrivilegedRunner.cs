using System.ComponentModel;
using System.Diagnostics;
using System.Security.Principal;
using System.Text;
using AuraStudio.Core.Installer;
using AuraStudio.App.Services;

namespace AuraStudio.App.Platform;

/// <summary>
/// Lado no elevado: escribe la petición, relanza **esta misma aplicación** con
/// permisos de administrador para que la ejecute, y lee el resultado.
///
/// <para><b>Por qué se relanza la propia app y no un script.</b> Un script en
/// disco que se va a ejecutar como administrador es un blanco: entre que se
/// escribe y que se ejecuta, cualquier proceso con acceso a esa carpeta podría
/// cambiarlo, y lo que se elevaría sería el cambio. Relanzando el propio
/// ejecutable no hay nada nuevo que firmar ni que proteger: lo que corre
/// elevado es el mismo binario que el usuario ya está ejecutando, y lo único
/// que viaja por disco es una petición JSON que el lado elevado **vuelve a
/// validar** antes de tocar nada.</para>
///
/// <para>La petición y el resultado van por archivos porque el verbo
/// <c>runas</c> exige <c>UseShellExecute</c>, y con eso no se pueden redirigir
/// las tuberías estándar del proceso hijo.</para>
/// </summary>
public sealed class PrivilegedRunner : IPrivilegedRunner
{
    /// <summary>Argumento que enciende el modo elevado. Ver <see cref="PrivilegedHost"/>.</summary>
    public const string Switch = "--aura-privileged";

    private readonly IPrivilegedOperationLog _log;

    public PrivilegedRunner(IPrivilegedOperationLog log) => _log = log;

    public bool IsElevated
    {
        get
        {
            try
            {
                using WindowsIdentity identity = WindowsIdentity.GetCurrent();
                return new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator);
            }
            catch (Exception ex) when (ex is UnauthorizedAccessException or InvalidOperationException)
            {
                return false;
            }
        }
    }

    public async Task<PrivilegedOperationResult> RunAsync(PrivilegedOperation operation, CancellationToken ct = default)
    {
        // Validar de este lado también: no porque el otro no lo haga, sino para
        // no molestar al usuario con un diálogo de UAC por una petición que ya
        // se sabe inválida.
        if (operation.Validate() is { } invalid)
        {
            return PrivilegedOperationResult.Failure(invalid);
        }

        string workDirectory = WorkDirectory();
        string requestPath = Path.Combine(workDirectory, $"peticion-{Guid.NewGuid():N}.json");
        string resultPath = Path.Combine(workDirectory, $"resultado-{Guid.NewGuid():N}.json");

        try
        {
            Directory.CreateDirectory(workDirectory);
            await File.WriteAllTextAsync(requestPath, operation.ToJson(), ct);

            _log.Append(operation.Kind.ToString(), operation.DryRun ? "solicitada (ensayo)" : "solicitada");

            int exitCode = await LaunchElevatedAsync(requestPath, resultPath, ct);

            if (exitCode == PrivilegedHost.ExitCancelled)
            {
                _log.Append(operation.Kind.ToString(), "cancelada por el usuario");
                return PrivilegedOperationResult.Failure(
                    "Cancelaste la autorización. Este paso no puede continuar sin ese permiso.");
            }

            if (!File.Exists(resultPath))
            {
                _log.Append(operation.Kind.ToString(), $"sin resultado (código {exitCode})");
                return PrivilegedOperationResult.Failure(
                    "La operación con permisos de administrador terminó sin dejar resultado. " +
                    "No se puede saber si alcanzó a hacer algo, así que no se continúa.");
            }

            string json = await File.ReadAllTextAsync(resultPath, ct);
            PrivilegedOperationResult result = PrivilegedOperationResult.FromJson(json)
                ?? PrivilegedOperationResult.Failure("No se pudo leer el resultado de la operación.");

            _log.Append(operation.Kind.ToString(),
                result.Success ? "ok" : result.SafetyAbort ? $"abortada por seguridad: {result.Message}" : $"error: {result.Message}");

            return result;
        }
        catch (Win32Exception ex) when (ex.NativeErrorCode == ErrorCancelled)
        {
            // El usuario cerró el diálogo de UAC. No es un fallo.
            _log.Append(operation.Kind.ToString(), "cancelada por el usuario");
            return PrivilegedOperationResult.Failure(
                "Cancelaste la autorización. Este paso no puede continuar sin ese permiso.");
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or Win32Exception)
        {
            _log.Append(operation.Kind.ToString(), $"error: {ex.Message}");
            return PrivilegedOperationResult.Failure(
                $"No se pudo pedir permiso de administrador: {ex.Message}");
        }
        finally
        {
            Delete(requestPath);
            Delete(resultPath);
        }
    }

    /// <summary>`ERROR_CANCELLED`: el usuario cerró el diálogo de UAC.</summary>
    private const int ErrorCancelled = 1223;

    private static async Task<int> LaunchElevatedAsync(string requestPath, string resultPath, CancellationToken ct)
    {
        string executable = Environment.ProcessPath
            ?? throw new InvalidOperationException("No se pudo determinar el ejecutable de Aura Studio.");

        var psi = new ProcessStartInfo(executable)
        {
            UseShellExecute = true,     // obligatorio para el verbo runas
            Verb = "runas",
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden
        };
        psi.ArgumentList.Add(Switch);
        psi.ArgumentList.Add(requestPath);
        psi.ArgumentList.Add(resultPath);

        using Process process = Process.Start(psi)
            ?? throw new InvalidOperationException("No se pudo iniciar el proceso con permisos de administrador.");

        await process.WaitForExitAsync(ct);
        return process.ExitCode;
    }

    /// <summary>
    /// Carpeta propia del usuario bajo `%LOCALAPPDATA%`, no `%TEMP%` compartido:
    /// la petición vive un instante en disco y cuanto menos accesible sea, mejor.
    /// </summary>
    private static string WorkDirectory() => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "Aura Studio", "privilegiado");

    private static void Delete(string path)
    {
        try { if (File.Exists(path)) File.Delete(path); }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { /* best effort */ }
    }
}

/// <summary>Bitácora de operaciones privilegiadas — qué se pidió y cómo terminó.</summary>
public interface IPrivilegedOperationLog
{
    void Append(string operation, string result);

    /// <summary>Últimas líneas, para poder mostrarlas cuando algo sale mal.</summary>
    IReadOnlyList<string> Tail(int lines = 50);
}

/// <summary>
/// Port de `PrivilegedOperationLog` de macOS: un archivo de texto con una línea
/// por operación. Que quede rastro de cada vez que la app pidió permisos de
/// administrador no es opcional en algo que puede formatear un disco.
/// </summary>
public sealed class PrivilegedOperationLog : IPrivilegedOperationLog
{
    private readonly string _path;
    private readonly object _gate = new();

    public PrivilegedOperationLog() : this(Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "Aura Studio", "operaciones-privilegiadas.log"))
    { }

    public PrivilegedOperationLog(string path) => _path = path;

    public void Append(string operation, string result)
    {
        string line = $"{DateTimeOffset.Now:yyyy-MM-dd HH:mm:ss zzz}\t{operation}\t{result}";
        lock (_gate)
        {
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
                File.AppendAllText(_path, line + Environment.NewLine, Encoding.UTF8);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                // Perder una línea de bitácora nunca puede impedir la operación.
            }
        }
    }

    public IReadOnlyList<string> Tail(int lines = 50)
    {
        lock (_gate)
        {
            try
            {
                if (!File.Exists(_path)) return [];
                return File.ReadLines(_path).TakeLast(lines).ToList();
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                return [];
            }
        }
    }
}
