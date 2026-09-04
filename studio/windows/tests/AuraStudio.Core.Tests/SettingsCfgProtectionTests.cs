using AuraStudio.Core.Installer;
using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// ST-147 / contrato v19: <c>/.aura/settings.cfg</c> (ajustes compartidos
/// entre las tres familias) es propiedad del firmware, igual que
/// <c>/.aura/art/</c> desde ST-073 y <c>/.aura/tagcache/</c>+<c>/.aura/thumbs/</c>
/// desde ST-069. Ningún flujo de Studio puede borrarlo, moverlo ni
/// reescribirlo — estos tests fijan esa promesa contra cada operación real
/// que toca el volumen. Port de <c>SettingsCfgProtectionTests.swift</c>.
/// </summary>
public class SettingsCfgProtectionTests : IDisposable
{
    private readonly string _root;
    private const string SettingsContent = "# aura-shared-settings v1\nrev: 3\nupdated_by: aura\nbrightness: 20\n";

    public SettingsCfgProtectionTests()
    {
        _root = Path.Combine(Path.GetTempPath(), "SettingsProtect-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_root);
    }

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { /* best effort */ }
    }

    private void WriteFile(string relative, string contents = "x")
    {
        string path = Path.Combine(_root, relative.Replace('/', Path.DirectorySeparatorChar));
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, contents);
    }

    private string SettingsPath =>
        Path.Combine(_root, FirmwareSwitcher.SharedSettingsRelativePath.Replace('/', Path.DirectorySeparatorChar));

    private void PlantSettings() => WriteFile(FirmwareSwitcher.SharedSettingsRelativePath, SettingsContent);

    private void AssertSettingsUntouched(string because)
        => Assert.Equal(SettingsContent, File.ReadAllText(SettingsPath));

    // MARK: - Cambiar de familia

    [Fact]
    public void SwitchingActiveFirmwareDoesNotTouchSettings()
    {
        WriteFile(".rockbox/rockbox.ipod", "AURA");
        WriteFile(".rockbox/aura/aura.cfg", "firmware_family: aura\n");
        WriteFile(".firmware-metro/rockbox.ipod", "METRO");
        WriteFile(".firmware-metro/aura/aura.cfg", "firmware_family: metro\n");
        PlantSettings();

        FirmwareSwitcher.SwitchActiveFirmware(FirmwareFamily.Metro, FirmwareFamily.Aura, _root);

        AssertSettingsUntouched("cambiar de familia no puede tocar los ajustes compartidos");
    }

    // MARK: - Reparación (arranque en frío tras un corte)

    [Fact]
    public void RepairingAfterAColdStartDoesNotTouchSettings()
    {
        WriteFile(".firmware-aura/rockbox.ipod", "AURA");
        PlantSettings();

        FirmwareSwitcher.RepairIfNeeded(_root);

        AssertSettingsUntouched("reparar un arranque en frío no puede tocar los ajustes compartidos");
    }

    // MARK: - Siembra y espejo de archivos del contrato

    [Fact]
    public void SeedingContractFilesDoesNotTouchSettings()
    {
        WriteFile(".rockbox/rockbox.ipod", "AURA");
        WriteFile(".firmware-metro/aura/sync_summary.cfg", "music_count: 10\n");
        PlantSettings();

        FirmwareSwitcher.SeedContractFilesToActiveTree(_root);

        AssertSettingsUntouched("sembrar el árbol activo no puede tocar los ajustes compartidos");
    }

    [Fact]
    public void MirroringContractFilesDoesNotTouchSettings()
    {
        WriteFile(".rockbox/aura/sync_summary.cfg", "music_count: 10\n");
        WriteFile(".firmware-metro/rockbox.ipod", "METRO");
        PlantSettings();

        FirmwareSwitcher.MirrorContractFilesToDormantTrees(_root);

        AssertSettingsUntouched("espejar a los dormidos no puede tocar los ajustes compartidos");
    }

    // MARK: - Sincronización de biblioteca

    [Fact]
    public void LibrarySyncDoesNotTouchSettings()
    {
        PlantSettings();

        LibrarySyncEngine.Apply(_root, new SyncPlanResult([], []));   // ni siquiera un sync vacío

        AssertSettingsUntouched("sincronizar la biblioteca no puede tocar los ajustes compartidos");
    }

    // MARK: - Forzar la reconstrucción de la base

    [Fact]
    public void ForcingADatabaseRebuildDoesNotTouchSettings()
    {
        WriteFile(".aura/tagcache/database_idx.tcd");
        WriteFile(".rockbox/database_idx.tcd");
        PlantSettings();

        LibrarySyncEngine.ClearFirmwareDatabases(_root);

        AssertSettingsUntouched("forzar la reconstrucción de la base no puede tocar los ajustes compartidos");
    }

    // MARK: - El archivo no es candidato de ningún catálogo conocido

    [Fact]
    public void SettingsCfgIsNotNamedInAnyKnownCleanupList()
    {
        Assert.DoesNotContain(FirmwareSwitcher.MirroredContractEntries, e => e.Contains("settings"));
    }
}
