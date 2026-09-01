using AuraStudio.Core.Networking;
using Xunit;

namespace AuraStudio.Core.Tests.Networking;

/// <summary>
/// MusicBrainz aplica 1 pedido/segundo por IP de forma estricta. Estos
/// tests fijan la aritmética del limitador sin dormir de verdad: se
/// inyecta la marca de tiempo en vez de esperar en tiempo real
/// (equivalente de MusicBrainzRateLimiterTests.swift).
/// </summary>
public class MusicBrainzRateLimiterTests
{
    [Fact]
    public void FirstRequestDoesNotWait()
    {
        var limiter = new MusicBrainzRateLimiter();
        Assert.Equal(0, limiter.PendingDelay(DateTimeOffset.UtcNow));
    }

    [Fact]
    public void ImmediateSecondRequestWaitsAlmostAFullSecond()
    {
        var limiter = new MusicBrainzRateLimiter();
        var start = DateTimeOffset.UtcNow;
        limiter.Reserve(start);

        var delay = limiter.PendingDelay(start.AddSeconds(0.2));
        Assert.Equal(0.8, delay, 3); // accuracy ~0.001
    }

    [Fact]
    public void NoWaitOnceTheIntervalHasElapsed()
    {
        var limiter = new MusicBrainzRateLimiter();
        var start = DateTimeOffset.UtcNow;
        limiter.Reserve(start);

        var delay = limiter.PendingDelay(start.AddSeconds(1.5));
        Assert.Equal(0, delay);
    }

    [Fact]
    public void IntervalIsConfigurable()
    {
        var limiter = new MusicBrainzRateLimiter(minimumIntervalSeconds: 3);
        var start = DateTimeOffset.UtcNow;
        limiter.Reserve(start);

        var delay = limiter.PendingDelay(start.AddSeconds(1));
        Assert.Equal(2, delay, 3);
    }

    /// El limitador es compartido por todos los clientes justamente porque
    /// el límite es por IP: dos instancias de MusicBrainzClient no pueden
    /// gastar cada una su propio pedido por segundo.
    [Fact]
    public void SharedInstanceIsTheSame()
    {
        var a = MusicBrainzRateLimiter.Shared;
        var b = MusicBrainzRateLimiter.Shared;
        Assert.Same(a, b);
    }
}
