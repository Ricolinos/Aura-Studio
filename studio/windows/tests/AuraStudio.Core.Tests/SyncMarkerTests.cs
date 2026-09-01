using AuraStudio.Core;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// ST-012 / `docs/contracts/library-layout-v1.md` SS4: el marcador
/// `/.aura/sync-pending.json` que LibrarySync deja para que el firmware
/// reconstruya sus índices al arrancar, y las capacidades de `aura.cfg`
/// (`sync_marker_supported`, `theme_format_supported`, `firmware_family`).
/// Port de `SyncMarkerTests.swift` (los casos que dependen de `LibrarySync`
/// no aplican: ese tipo no forma parte de este port).
/// </summary>
public class SyncMarkerTests : IDisposable
{
    private readonly string _root;

    public SyncMarkerTests()
    {
        _root = Path.Combine(Path.GetTempPath(), "FakeIPod-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_root);
    }

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { /* best effort */ }
    }

    private string MarkerPath => Path.Combine(_root, SyncPendingMarker.RelativePath);

    private void WriteAuraConfig(string text)
    {
        string dir = Path.Combine(_root, ".rockbox/aura");
        Directory.CreateDirectory(dir);
        File.WriteAllText(Path.Combine(dir, "aura.cfg"), text);
    }

    // MARK: - Modelo

    [Fact]
    public void MarkerRoundTripsAndMatchesContractShape()
    {
        // Equivalente a testMarkerRoundTripsAndMatchesContractShape
        var marker = new SyncPendingMarker(
            new SyncPendingMarker.Changes(true, false, true),
            DateTimeOffset.FromUnixTimeSeconds(1_787_000_000));
        marker.Write(_root);

        string text = File.ReadAllText(MarkerPath);
        // Claves exactas del contrato SS4.1, en el nivel que corresponde
        // (formato de System.Text.Json con indentación).
        Assert.Contains("\"version\": 1", text);
        Assert.Contains("\"attempts\": 0", text);
        Assert.Contains("\"changes\"", text);
        Assert.Contains("\"music\": true", text);
        Assert.Contains("\"images\": true", text);
        Assert.Contains("\"timestamp\": \"2026-08-17T", text);

        Assert.Equal(marker, SyncPendingMarker.Read(_root));
    }

    [Fact]
    public void HandWrittenV1JsonDecodesEqualToConstructed()
    {
        // El marcador v1 (sin la clave nueva de versiones futuras) escrito a
        // mano con las claves exactas del contrato debe decodificar igual que
        // uno construido con los mismos valores.
        var marker = new SyncPendingMarker(
            new SyncPendingMarker.Changes(true, false, true),
            DateTimeOffset.FromUnixTimeSeconds(1_787_000_000));

        const string v1Json =
            "{\"version\":1,\"timestamp\":\"2026-08-17T20:53:20Z\"," +
            "\"changes\":{\"music\":true,\"video\":false,\"images\":true},\"attempts\":0}";

        Directory.CreateDirectory(Path.GetDirectoryName(MarkerPath)!);
        File.WriteAllText(MarkerPath, v1Json);

        var decoded = SyncPendingMarker.Read(_root);
        Assert.NotNull(decoded);
        Assert.Equal(marker, decoded);
    }

    [Fact]
    public void ReadReturnsNullWhenAbsentOrMalformed()
    {
        // Equivalente a testReadReturnsNilWhenAbsentOrMalformed
        Assert.Null(SyncPendingMarker.Read(_root));

        Directory.CreateDirectory(Path.GetDirectoryName(MarkerPath)!);
        File.WriteAllText(MarkerPath, "no es json");
        Assert.Null(SyncPendingMarker.Read(_root));
    }

    // MARK: - FirmwareCapabilities (parse de aura.cfg)

    [Fact]
    public void FirmwareCapabilityParsesAuraConfig()
    {
        // Equivalente a testFirmwareCapabilityParsesAuraConfig
        Assert.Null(FirmwareCapabilities.SupportedSyncMarkerVersion(_root));

        WriteAuraConfig("theme: 1\ntheme_format_supported: 1\n");
        // firmware anterior a D-293: sin la clave
        Assert.Null(FirmwareCapabilities.SupportedSyncMarkerVersion(_root));
        Assert.Equal(1, FirmwareCapabilities.SupportedThemeFormat(_root));

        WriteAuraConfig("theme: 1\nsync_marker_supported: 1\n");
        Assert.Equal(1, FirmwareCapabilities.SupportedSyncMarkerVersion(_root));
    }

    // MARK: - Familia (ST-046 / ST-067)

    [Fact]
    public void DeclaredFamilyIsAuraWhenKeyAbsent()
    {
        // La ausencia de la clave es la firma de Aura.
        WriteAuraConfig("theme: 1\nsync_marker_supported: 1\n");
        Assert.Equal(FirmwareFamily.Aura, FirmwareCapabilities.DeclaredFamily(_root));
    }

    [Fact]
    public void DeclaredFamilyParsesDeclaredKey()
    {
        WriteAuraConfig("theme: 1\nfirmware_family: metro\n");
        Assert.Equal(FirmwareFamily.Metro, FirmwareCapabilities.DeclaredFamily(_root));

        WriteAuraConfig("firmware_family: MOONLIT\n");
        Assert.Equal(FirmwareFamily.Moonlit, FirmwareCapabilities.DeclaredFamily(_root));
    }

    [Fact]
    public void AbsentKeyFallsBackToSentinel()
    {
        // ST-067: árbol recién copiado — sin clave, pero Metro/Moonlit dejan
        // un centinela que Aura no tiene.
        string moonlitSentinel = Path.Combine(_root, FirmwareFamily.Moonlit.InstalledTreeSentinel!);
        Directory.CreateDirectory(Path.GetDirectoryName(moonlitSentinel)!);
        File.WriteAllText(moonlitSentinel, "x");

        Assert.Equal(FirmwareFamily.Moonlit, FirmwareCapabilities.DeclaredFamily(_root));
        Assert.Equal(FirmwareFamily.Moonlit, FirmwareCapabilities.FamilyBySentinel(_root));
    }

    [Fact]
    public void AbsentKeyAndNoSentinelIsAura()
    {
        Assert.Null(FirmwareCapabilities.FamilyBySentinel(_root));
        Assert.Equal(FirmwareFamily.Aura, FirmwareCapabilities.DeclaredFamily(_root));
    }

    [Fact]
    public void SeedDeclaredFamilyUpsertsPreservingOtherLines()
    {
        WriteAuraConfig("theme: 1\n");

        FirmwareCapabilities.SeedDeclaredFamily(_root, FirmwareFamily.Metro);

        string[] lines = File.ReadAllText(Path.Combine(_root, ".rockbox/aura/aura.cfg"))
            .Split('\n', StringSplitOptions.RemoveEmptyEntries);
        Assert.Equal("firmware_family: metro", lines[0]);
        Assert.Contains("theme: 1", lines);
        Assert.Equal(FirmwareFamily.Metro, FirmwareCapabilities.DeclaredFamily(_root));
    }

    [Fact]
    public void SeedDeclaredFamilyWritesNothingForAura()
    {
        // La firma de Aura es la ausencia: no escribe nada.
        WriteAuraConfig("theme: 1\n");
        FirmwareCapabilities.SeedDeclaredFamily(_root, FirmwareFamily.Aura);

        string text = File.ReadAllText(Path.Combine(_root, ".rockbox/aura/aura.cfg"));
        Assert.DoesNotContain("firmware_family", text);
    }

    [Fact]
    public void FirmwareFamilyParseHandlesRawValues()
    {
        // Insensible a mayúsculas y espacios, igual que parse del Swift.
        Assert.Equal(FirmwareFamily.Aura, FirmwareFamily.Parse(null));
        Assert.Equal(FirmwareFamily.Aura, FirmwareFamily.Parse(""));
        Assert.Equal(FirmwareFamily.Aura, FirmwareFamily.Parse("  aura  "));
        Assert.Equal(FirmwareFamily.Metro, FirmwareFamily.Parse("METRO"));
        Assert.Equal(FirmwareFamily.Moonlit, FirmwareFamily.Parse("moonlit"));

        var unknown = FirmwareFamily.Parse("future-os");
        Assert.NotEqual(FirmwareFamily.Aura, unknown);
        Assert.Equal("future-os", unknown.ConfigValue);
        Assert.Equal("future-os", unknown.DisplayName);
        Assert.False(unknown.IsInstallable);
    }
}
