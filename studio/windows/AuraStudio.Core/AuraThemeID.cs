namespace AuraStudio.Core;

/// <summary>
/// Id de un paquete de tema -- mismas reglas que aura_style_id_is_valid()
/// del firmware (aura_style_manifest.c): 1-32 caracteres [a-z0-9-],
/// nunca vacío, nunca "default" (reservado para el tema compilado).
/// </summary>
public static class AuraThemeID
{
    public const int MaxLength = 32;
    private static readonly HashSet<char> Allowed = new("abcdefghijklmnopqrstuvwxyz0123456789-");

    public static bool IsValid(string id)
    {
        if (string.IsNullOrEmpty(id) || id.Length > MaxLength || id == "default")
            return false;
        return id.All(c => Allowed.Contains(c));
    }
}
