using AuraStudio.Core;
using AuraStudio.Core.Installer;
using AuraStudio.Core.Networking;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// El caché de Releases de GitHub (ST-077, remontado del ático en R4/ST-132).
///
/// <para>Lo que estas pruebas cuidan es <b>por familia</b>: con una sola llave,
/// la lista de Metro quedaría guardada bajo la de Aura, y conectar un iPod con
/// Metro y después uno con Aura le mostraría al segundo los tags del primero
/// durante 24 horas — comparados contra su propio <c>version.txt</c>
/// (ST-046).</para>
/// </summary>
public sealed class ReleaseCacheTests
{
    private static readonly DateTimeOffset Now = new(2026, 9, 1, 12, 0, 0, TimeSpan.Zero);

    private static List<GitHubRelease> Releases(params string[] tags) =>
        [.. tags.Select(tag => new GitHubRelease { TagName = tag, Prerelease = false })];

    [Fact]
    public void LoQueSeGuardaSeVuelveALeer()
    {
        var store = new InMemoryReleaseCacheStore();
        ReleaseCache.Store(Releases("v1.0", "v1.1"), store, FirmwareFamily.Aura, Now);

        IReadOnlyList<GitHubRelease>? loaded = ReleaseCache.Load(store, FirmwareFamily.Aura, Now);

        Assert.NotNull(loaded);
        Assert.Equal(["v1.0", "v1.1"], loaded!.Select(release => release.TagName));
    }

    /// <summary>El caso que ST-046 pagó: cada familia tiene su propia llave.</summary>
    [Fact]
    public void ElCacheDeUnaFamiliaNoSeLeDaAOtra()
    {
        var store = new InMemoryReleaseCacheStore();
        ReleaseCache.Store(Releases("metro-1.0"), store, FirmwareFamily.Metro, Now);

        Assert.Null(ReleaseCache.Load(store, FirmwareFamily.Aura, Now));
        Assert.Null(ReleaseCache.Load(store, FirmwareFamily.Moonlit, Now));
        Assert.NotNull(ReleaseCache.Load(store, FirmwareFamily.Metro, Now));

        Assert.NotEqual(ReleaseCache.DataKeyFor(FirmwareFamily.Aura), ReleaseCache.DataKeyFor(FirmwareFamily.Metro));
    }

    /// <summary>
    /// Aura conserva las llaves históricas —sin sufijo—: nadie pierde su caché
    /// al actualizar Studio.
    /// </summary>
    [Fact]
    public void AuraConservaLasLlavesHistoricas()
    {
        Assert.Equal(ReleaseCache.DataKey, ReleaseCache.DataKeyFor(FirmwareFamily.Aura));
        Assert.Equal(ReleaseCache.TimestampKey, ReleaseCache.TimestampKeyFor(FirmwareFamily.Aura));
    }

    [Fact]
    public void VencidoElTtlEsComoSiNoHubieraCache()
    {
        var store = new InMemoryReleaseCacheStore();
        ReleaseCache.Store(Releases("v1.0"), store, FirmwareFamily.Aura, Now);

        Assert.NotNull(ReleaseCache.Load(store, FirmwareFamily.Aura, Now + ReleaseCache.Ttl - TimeSpan.FromMinutes(1)));
        Assert.Null(ReleaseCache.Load(store, FirmwareFamily.Aura, Now + ReleaseCache.Ttl));
    }

    [Fact]
    public void SinNadaGuardadoNoHayCache() =>
        Assert.Null(ReleaseCache.Load(new InMemoryReleaseCacheStore(), FirmwareFamily.Aura, Now));

    /// <summary>
    /// Un caché ilegible es "no hay caché", nunca un error de cara al usuario:
    /// la consulta en vivo lo reemplaza en la misma pasada.
    /// </summary>
    [Fact]
    public void UnCacheCorruptoSeTrataComoAusente()
    {
        var store = new InMemoryReleaseCacheStore();
        store.SetString(ReleaseCache.DataKeyFor(FirmwareFamily.Aura), "{ esto no es json }");
        store.SetDate(ReleaseCache.TimestampKeyFor(FirmwareFamily.Aura), Now);

        Assert.Null(ReleaseCache.Load(store, FirmwareFamily.Aura, Now));
    }
}
