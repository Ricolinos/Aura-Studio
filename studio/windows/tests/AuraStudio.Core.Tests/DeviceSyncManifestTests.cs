using System.Text.Json;
using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// El manifiesto es el único archivo que las dos apps —la de la Mac y la de
/// Windows— escriben y leen del mismo iPod. Si Windows escribe algo que macOS
/// no decodifica, macOS lo descarta entero y vuelve a copiar la biblioteca
/// completa; y al revés. Por eso las claves y los tipos se prueban uno por uno.
/// </summary>
public sealed class DeviceSyncManifestTests : IDisposable
{
    private readonly string _volume = Path.Combine(Path.GetTempPath(), "aura-man-" + Guid.NewGuid().ToString("N"));

    public DeviceSyncManifestTests() => Directory.CreateDirectory(_volume);

    public void Dispose()
    {
        try { Directory.Delete(_volume, recursive: true); } catch (IOException) { }
    }

    private void WriteRaw(string json)
    {
        string path = Path.Combine(_volume, ".rockbox", "aura", "sync_manifest.json");
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, json);
    }

    private string ReadRaw() =>
        File.ReadAllText(Path.Combine(_volume, ".rockbox", "aura", "sync_manifest.json"));

    // MARK: - Leer lo que escribió la Mac

    [Fact]
    public void AManifestWrittenByTheMacIsReadWhole()
    {
        WriteRaw("""
        {"records":{"/Users/r/Aura Library/.preparados/a.mp3":{"sourcePath":"/Users/r/Aura Library/.preparados/a.mp3","sourceSize":5242880,"sourceModifiedAt":1756598400.123,"destinationRelativePath":"Music/Soda Stereo/Signos/Persiana Americana.mp3","destinationSize":5242880,"destinationModifiedAt":1756598450,"writtenBy":"8B1F0C4E-0000-4000-8000-000000000001","syncedAt":1756598451.5}},"contractVersion":2}
        """);

        DeviceSyncManifest manifest = DeviceSyncManifest.Load(_volume);
        DeviceSyncRecord record = manifest.Records["/Users/r/Aura Library/.preparados/a.mp3"];

        Assert.Equal(2, manifest.ContractVersion);
        Assert.Equal(5242880, record.SourceSize);
        Assert.Equal(1756598400.123, record.SourceModifiedAt);
        Assert.Equal("Music/Soda Stereo/Signos/Persiana Americana.mp3", record.DestinationRelativePath);
        Assert.Equal(5242880, record.DestinationSize);
        Assert.Equal("8B1F0C4E-0000-4000-8000-000000000001", record.WrittenBy);
        Assert.Equal(1756598451.5, record.SyncedAt);
    }

    [Fact]
    public void AnOldManifestWithoutTheOptionalKeysStillDecodes()
    {
        // v1: sin huella del destino, sin autor, sin fecha. Un decodificador
        // que las exigiera tiraría el manifiesto ENTERO por una clave que falta
        // y recopiaría toda la biblioteca.
        WriteRaw("""
        {"records":{"/m/a.mp3":{"sourcePath":"/m/a.mp3","sourceSize":100,"sourceModifiedAt":1700000000,"destinationRelativePath":"Music/A/a.mp3"}}}
        """);

        DeviceSyncManifest manifest = DeviceSyncManifest.Load(_volume);

        Assert.Null(manifest.ContractVersion);
        Assert.Null(manifest.Records["/m/a.mp3"].DestinationSize);
        Assert.Equal("Music/A/a.mp3", manifest.Records["/m/a.mp3"].DestinationRelativePath);
    }

    [Fact]
    public void AManifestThatCannotBeReadIsEmptyAndNotAnException()
    {
        // Lo peor que puede pasar es copiar de más. No poder sincronizar sería
        // mucho peor.
        WriteRaw("{ esto no es json");

        Assert.Empty(DeviceSyncManifest.Load(_volume).Records);
    }

    [Fact]
    public void NoManifestIsAnEmptyOne()
    {
        Assert.Empty(DeviceSyncManifest.Load(_volume).Records);
        Assert.Equal(DeviceSyncManifest.CurrentContractVersion, DeviceSyncManifest.Load(_volume).ContractVersion);
    }

    // MARK: - Escribir algo que la Mac pueda leer

    [Fact]
    public void WhatIsWrittenCarriesExactlyTheKeysThatSwiftExpects()
    {
        var manifest = new DeviceSyncManifest();
        manifest.Records["/m/a.mp3"] = new DeviceSyncRecord("/m/a.mp3", 100, 1700000000, "Music/A/a.mp3")
        {
            DestinationSize = 100,
            DestinationModifiedAt = 1700000001,
            WrittenBy = "windows-1",
            SyncedAt = 1700000002
        };
        manifest.Save(_volume);

        using JsonDocument document = JsonDocument.Parse(ReadRaw());
        JsonElement record = document.RootElement.GetProperty("records").GetProperty("/m/a.mp3");

        Assert.Equal(2, document.RootElement.GetProperty("contractVersion").GetInt32());
        foreach (string key in (string[])
                 [
                     "sourcePath", "sourceSize", "sourceModifiedAt", "destinationRelativePath",
                     "destinationSize", "destinationModifiedAt", "writtenBy", "syncedAt"
                 ])
        {
            Assert.True(record.TryGetProperty(key, out _), key);
        }
    }

    [Fact]
    public void TheDateIsANumberOfSecondsNotAText()
    {
        // `TimeInterval` de Swift es un Double. Una fecha ISO, o los segundos
        // desde 2001 que usa `Date` de Codable, no decodificarían.
        var manifest = new DeviceSyncManifest();
        manifest.Records["/m/a.mp3"] = new DeviceSyncRecord(
            "/m/a.mp3", 100, DeviceSyncRecord.ToTimeInterval(new DateTimeOffset(2026, 9, 1, 0, 0, 0, TimeSpan.Zero)),
            "Music/A/a.mp3");
        manifest.Save(_volume);

        using JsonDocument document = JsonDocument.Parse(ReadRaw());
        JsonElement date = document.RootElement.GetProperty("records").GetProperty("/m/a.mp3")
            .GetProperty("sourceModifiedAt");

        Assert.Equal(JsonValueKind.Number, date.ValueKind);
        Assert.Equal(1788220800, date.GetDouble());
    }

    [Fact]
    public void AnAbsentOptionalIsNotWrittenAsNull()
    {
        // Swift omite los opcionales nulos. Escribir `"writtenBy": null` igual
        // decodifica del otro lado, pero deja el archivo distinto del que
        // escribiría la Mac sin ninguna razón.
        var manifest = new DeviceSyncManifest();
        manifest.Records["/m/a.mp3"] = new DeviceSyncRecord("/m/a.mp3", 100, 0, "Music/A/a.mp3");
        manifest.Save(_volume);

        Assert.DoesNotContain("null", ReadRaw());
    }

    [Fact]
    public void ARoundTripChangesNothing()
    {
        var original = new DeviceSyncManifest();
        original.Records["/m/a.mp3"] = new DeviceSyncRecord("/m/a.mp3", 100, 1700000000.5, "Music/A/a.mp3")
        {
            DestinationSize = 100, DestinationModifiedAt = 1700000001, WrittenBy = "windows-1", SyncedAt = 1700000002
        };
        original.Save(_volume);

        string first = ReadRaw();
        DeviceSyncManifest.Load(_volume).Save(_volume);

        Assert.Equal(first, ReadRaw());
    }

    [Fact]
    public void SavingIsAtomicSoAnInterruptionNeverLeavesHalfAManifest()
    {
        var manifest = new DeviceSyncManifest();
        manifest.Records["/m/a.mp3"] = new DeviceSyncRecord("/m/a.mp3", 100, 0, "Music/A/a.mp3");
        manifest.Save(_volume);

        Assert.Empty(Directory.EnumerateFiles(Path.Combine(_volume, ".rockbox", "aura"), "*.tmp"));
    }
}
