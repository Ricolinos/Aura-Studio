using System.Runtime.InteropServices;
using System.Text;
using AuraStudio.Core.Networking;

namespace AuraStudio.App.Platform;

/// <summary>
/// Las credenciales de Aura Studio, en el <b>Administrador de credenciales de
/// Windows</b> — el equivalente del Llavero de macOS.
///
/// <para>Regla del repo (D-203 / ST-032 / ST-033): las API keys viven <b>solo</b>
/// acá. Nunca en <c>preferences.json</c>, nunca en el repositorio. Este archivo
/// es el único lugar de la app que las lee o las escribe.</para>
///
/// <para>Se guardan como credenciales de tipo <c>GENERIC</c> con alcance
/// <c>LOCAL_MACHINE</c> del usuario actual: quedan cifradas con su perfil, así
/// que otro usuario de la misma PC no las puede leer.</para>
/// </summary>
public sealed partial class CredentialStore : IApiKeyStore
{
    /// <summary>
    /// Prefijo del nombre con el que aparecen en el Administrador de
    /// credenciales. Se elige legible a propósito: el usuario tiene que poder
    /// encontrarlas y borrarlas desde Windows sin depender de esta app.
    /// </summary>
    private const string TargetPrefix = "Aura Studio";

    private const uint CredTypeGeneric = 1;
    private const uint CredPersistLocalMachine = 2;

    /// <summary>El nombre del servicio no es libre: es la clave del almacén.</summary>
    private static string TargetFor(string service) => $"{TargetPrefix}: {service}";

    public string? Load(string service)
    {
        if (!CredRead(TargetFor(service), CredTypeGeneric, 0, out IntPtr handle)) return null;

        try
        {
            Credential credential = Marshal.PtrToStructure<Credential>(handle);
            if (credential.CredentialBlob == IntPtr.Zero || credential.CredentialBlobSize == 0) return null;

            byte[] bytes = new byte[credential.CredentialBlobSize];
            Marshal.Copy(credential.CredentialBlob, bytes, 0, bytes.Length);
            return Encoding.UTF8.GetString(bytes);
        }
        finally
        {
            CredFree(handle);
        }
    }

    /// <summary>
    /// Guarda —o reemplaza— la clave. Una cadena vacía <b>borra</b>: es lo que
    /// espera quien limpia el campo y guarda, y dejar una clave vacía guardada
    /// haría que los clientes creyeran que hay credencial.
    /// </summary>
    public bool Save(string service, string value)
    {
        if (string.IsNullOrWhiteSpace(value)) return Delete(service);

        byte[] bytes = Encoding.UTF8.GetBytes(value);
        IntPtr blob = Marshal.AllocHGlobal(bytes.Length);

        try
        {
            Marshal.Copy(bytes, 0, blob, bytes.Length);

            var credential = new Credential
            {
                Type = CredTypeGeneric,
                TargetName = TargetFor(service),
                CredentialBlob = blob,
                CredentialBlobSize = (uint)bytes.Length,
                Persist = CredPersistLocalMachine,
                UserName = Environment.UserName
            };

            return CredWrite(ref credential, 0);
        }
        finally
        {
            Marshal.FreeHGlobal(blob);
        }
    }

    /// <summary>
    /// Borra la credencial. Que no existiera cuenta como éxito: el estado que
    /// el usuario pidió —"que no esté"— es el que queda.
    /// </summary>
    public bool Delete(string service) =>
        CredDelete(TargetFor(service), CredTypeGeneric, 0) || Load(service) is null;

    public bool HasKey(string service) => Load(service) is { Length: > 0 };

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct Credential
    {
        public uint Flags;
        public uint Type;
        [MarshalAs(UnmanagedType.LPWStr)] public string TargetName;
        [MarshalAs(UnmanagedType.LPWStr)] public string? Comment;
        public long LastWritten;
        public uint CredentialBlobSize;
        public IntPtr CredentialBlob;
        public uint Persist;
        public uint AttributeCount;
        public IntPtr Attributes;
        [MarshalAs(UnmanagedType.LPWStr)] public string? TargetAlias;
        [MarshalAs(UnmanagedType.LPWStr)] public string? UserName;
    }

    [LibraryImport("advapi32.dll", EntryPoint = "CredReadW", StringMarshalling = StringMarshalling.Utf16)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool CredRead(string target, uint type, uint flags, out IntPtr credential);

    // `DllImport` y no `LibraryImport`: la estructura lleva cadenas, y el
    // generador de P/Invoke no las serializa (SYSLIB1051). El marshaller
    // clásico sí, y es exactamente para esto que sigue existiendo.
    [DllImport("advapi32.dll", EntryPoint = "CredWriteW", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CredWrite(ref Credential credential, uint flags);

    [LibraryImport("advapi32.dll", EntryPoint = "CredDeleteW", StringMarshalling = StringMarshalling.Utf16)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool CredDelete(string target, uint type, uint flags);

    [LibraryImport("advapi32.dll", EntryPoint = "CredFree")]
    private static partial void CredFree(IntPtr buffer);
}

/// <summary>
/// Los servicios que piden una clave, con lo que hay que decirle al usuario
/// <b>antes</b> de que la pegue, no después de que falle. Port de
/// <c>APIKeyService</c>.
/// </summary>
public sealed record ApiKeyService(string Key, string DisplayName, string Summary, string Guide, string Url)
{
    public static readonly ApiKeyService FanartTV = new(
        "fanarttv",
        "fanart.tv",
        "Carátulas y arte de disco en alta resolución (~1000 px), fotos de artista, y pósters curados de películas y series (estos últimos necesitan además la clave de TMDB para encontrar el título).",
        "Crea una cuenta gratuita en fanart.tv, entra a tu perfil y copia la \"Personal API Key\" (no la de proyecto).",
        "https://fanart.tv/get-an-api-key/");

    public static readonly ApiKeyService Tmdb = new(
        "tmdb",
        "TMDB (The Movie Database)",
        "Pósters de películas y series. Encuentra el título y su identificador; con fanart.tv configurado se prefiere el póster curado de allá, y si no, el de TMDB.",
        "Crea una cuenta gratuita en themoviedb.org, entra a Ajustes › API y copia la \"API Key (v3 auth)\".",
        "https://www.themoviedb.org/settings/api");

    /// <summary>
    /// ST-074: el token de GitHub. No es una fuente de metadata — sin él, el
    /// aviso de versión nueva no funciona porque los repositorios del firmware
    /// son privados. <b>Instalar el firmware no depende de esto</b>: los
    /// binarios vienen incluidos en la app.
    /// </summary>
    public static readonly ApiKeyService GitHub = new(
        "github",
        "GitHub (repositorios privados)",
        "Los repositorios del firmware son privados. Sin este token, Aura Studio no puede avisarte cuando hay una versión nueva; instalar el firmware sigue funcionando igual, porque viene incluido en la app.",
        "Crea un token de acceso personal \"fine-grained\" en github.com › Settings › Developer settings, con acceso solo a Aura-Firmware, Metro-Aura y moonlit-aura, y permiso Contents: Read-only. Solo se usa para consultar si hay versiones nuevas.",
        "https://github.com/settings/personal-access-tokens/new");

    public static readonly IReadOnlyList<ApiKeyService> MetadataServices = [FanartTV, Tmdb];
}
