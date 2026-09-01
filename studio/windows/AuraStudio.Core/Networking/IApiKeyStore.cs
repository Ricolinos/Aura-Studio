namespace AuraStudio.Core.Networking;

/// <summary>
/// Proveedor de claves de API para los clientes externos (TMDB, fanart.tv).
/// La implementacion real vive en AuraStudio.Win/Platform/ (Credential
/// Manager), donde se puede acceder al Keychain/Windows Credential Store.
/// En Core (portable) solo definimos la interfaz.
/// </summary>
public interface IApiKeyStore
{
    /// <summary>Carga la clave para el servicio dado. Devuelve null si no hay clave.</summary>
    string? Load(string service);
}