namespace AuraStudio.Core;

/// <summary>Planifica la publicación del árbol activo sin tocar otros árboles.</summary>
public static class FirmwareTreePlanner
{
    public static string ActiveTree(string volumeRoot) => Path.Combine(volumeRoot, ".rockbox");
    public static string DormantTree(string volumeRoot, FirmwareFamily family)
        => Path.Combine(volumeRoot, $".firmware-{family.ConfigValue ?? "aura"}");

    public static bool IsComplete(string volumeRoot, FirmwareFamily family)
    {
        if (family.InstalledTreeSentinel is null) return Directory.Exists(ActiveTree(volumeRoot));
        return File.Exists(Path.Combine(volumeRoot, family.InstalledTreeSentinel));
    }

    public static bool IsSafeRelativePath(string relative)
    {
        if (string.IsNullOrWhiteSpace(relative) || Path.IsPathRooted(relative)) return false;
        return relative.Split(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)
            .All(part => part.Length > 0 && part != "." && part != "..");
    }
}
