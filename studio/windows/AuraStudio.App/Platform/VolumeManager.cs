using System.Diagnostics;
using System.Runtime.InteropServices;

namespace AuraStudio.App.Platform;

/// <summary>Operaciones no destructivas sobre un volumen del iPod.</summary>
internal static partial class VolumeManager
{
    public static bool OpenInExplorer(string volumePath)
    {
        if (string.IsNullOrWhiteSpace(volumePath) || !Directory.Exists(volumePath)) return false;
        try
        {
            Process.Start(new ProcessStartInfo("explorer.exe", $"\"{volumePath}\"")
            {
                UseShellExecute = true
            });
            return true;
        }
        catch { return false; }
    }

    /// <summary>
    /// Solicita expulsión lógica de la unidad. No se informa éxito hasta que
    /// Windows acepta la operación; el usuario aún debe desconectar el cable.
    /// </summary>
    public static bool Eject(string volumePath)
    {
        if (string.IsNullOrWhiteSpace(volumePath)) return false;
        string root = Path.GetPathRoot(volumePath) ?? "";
        if (root.Length < 2 || root[1] != ':') return false;
        try
        {
            return EjectVolume(root[0]);
        }
        catch { return false; }
    }

    [LibraryImport("kernel32.dll", EntryPoint = "GetLogicalDrives")]
    private static partial uint GetLogicalDrives();

    private static bool EjectVolume(char letter)
    {
        // Shell eject is intentionally delegated to Windows Explorer: unlike
        // a forced dismount it flushes the filesystem and respects open handles.
        try
        {
            Process.Start(new ProcessStartInfo("powershell.exe",
                $"-NoProfile -NonInteractive -Command \"(New-Object -ComObject Shell.Application).NameSpace(17).ParseName('{letter}:').InvokeVerb('Eject')\"")
            {
                UseShellExecute = false,
                CreateNoWindow = true
            });
            return true;
        }
        catch { return false; }
    }
}
