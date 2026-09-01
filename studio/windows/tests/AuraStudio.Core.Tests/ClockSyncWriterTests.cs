using AuraStudio.Core;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// La hora del iPod. Escribe en <c>aura.cfg</c>, que son los ajustes del
/// usuario: lo que más importa es que <b>no se lleve nada por delante</b>.
/// </summary>
public sealed class ClockSyncWriterTests : IDisposable
{
    private readonly string _volume = Path.Combine(Path.GetTempPath(), "aura-reloj-" + Guid.NewGuid().ToString("N"));

    /// <summary>Con desfase de -6 h, que es el de la Ciudad de México.</summary>
    private static readonly DateTimeOffset Momento =
        new(2026, 9, 1, 14, 35, 7, TimeSpan.FromHours(-6));

    public ClockSyncWriterTests() => Directory.CreateDirectory(_volume);

    public void Dispose()
    {
        try { Directory.Delete(_volume, recursive: true); } catch (IOException) { }
    }

    private string ConfigPath => Path.Combine(_volume, ".rockbox", "aura", "aura.cfg");

    private void WriteConfig(string text)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(ConfigPath)!);
        File.WriteAllText(ConfigPath, text);
    }

    [Fact]
    public void TheDateAndTimeGoInAsTheFirmwareExpectsThem()
    {
        string result = ClockSyncWriter.WithClock("", Momento);

        Assert.Contains("rtc_sync_year: 2026\n", result);
        Assert.Contains("rtc_sync_month: 9\n", result);
        Assert.Contains("rtc_sync_day: 1\n", result);
        Assert.Contains("rtc_sync_hour: 14\n", result);
        Assert.Contains("rtc_sync_min: 35\n", result);
        Assert.Contains("rtc_sync_sec: 7\n", result);
    }

    [Theory]
    [InlineData(-6, -24)]
    [InlineData(0, 0)]
    [InlineData(5.5, 22)]
    [InlineData(5.75, 23)]
    public void TheTimeZoneGoesInQuartersOfAnHour(double hours, int quarters)
    {
        // Hay husos de media hora y de 45 minutos: en horas enteras no
        // entrarían.
        var moment = new DateTimeOffset(2026, 9, 1, 12, 0, 0, TimeSpan.FromHours(hours));

        Assert.Contains($"tz_local_quarters: {quarters}\n", ClockSyncWriter.WithClock("", moment));
    }

    [Fact]
    public void EverythingElseInTheFileIsLeftAlone()
    {
        string result = ClockSyncWriter.WithClock("volume: -25\ntheme_id: aura\n", Momento);

        Assert.Contains("volume: -25", result);
        Assert.Contains("theme_id: aura", result);
    }

    [Fact]
    public void SyncingTwiceDoesNotDuplicateTheLines()
    {
        string once = ClockSyncWriter.WithClock("volume: -25\n", Momento);
        string twice = ClockSyncWriter.WithClock(once, Momento.AddHours(1));

        Assert.Equal(1, twice.Split('\n').Count(line => line.StartsWith("rtc_sync_hour:", StringComparison.Ordinal)));
        Assert.Contains("rtc_sync_hour: 15\n", twice);
    }

    [Fact]
    public void TheFileDoesNotGrowABlankLineOnEachSync()
    {
        string result = ClockSyncWriter.WithClock(ClockSyncWriter.WithClock("volume: -25\n", Momento), Momento);

        Assert.DoesNotContain("\n\n", result);
    }

    // MARK: - En disco

    [Fact]
    public void OnDiskItRewritesTheConfigWithoutLosingAnything()
    {
        WriteConfig("volume: -25\naccent_rgb24: 4283215696\n");

        Assert.True(ClockSyncWriter.WriteToDisk(_volume, Momento));

        string result = File.ReadAllText(ConfigPath);
        Assert.Contains("volume: -25", result);
        Assert.Contains("accent_rgb24: 4283215696", result);
        Assert.Contains("rtc_sync_year: 2026", result);
    }

    [Fact]
    public void WithoutAConfigNothingIsCreated()
    {
        // Sin `aura.cfg` el firmware nunca arrancó en este iPod: no hay reloj
        // que poner en hora, y dejar un archivo a medias sería peor.
        Assert.False(ClockSyncWriter.WriteToDisk(_volume, Momento));
        Assert.False(File.Exists(ConfigPath));
    }

    [Fact]
    public void ANonWritableVolumeIsNotAnError()
    {
        // Es una cortesía en segundo plano al conectar: nunca puede interrumpir
        // al usuario ni tumbar otro flujo.
        Assert.False(ClockSyncWriter.WriteToDisk(@"Z:\no-existe", Momento));
    }
}
