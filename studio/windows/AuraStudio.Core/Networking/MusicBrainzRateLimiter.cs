namespace AuraStudio.Core.Networking;

/// <summary>
/// Serializa los pedidos a MusicBrainz respetando su límite documentado de
/// 1 request por segundo por IP, que está *estrictamente* aplicado:
/// pasarse no da un error distinto, te mete en una cola compartida y te
/// degrada a todos los usuarios del mismo User-Agent.
///
/// Es un actor en Swift y no un simple sleep en el cliente porque el
/// límite es por IP, no por llamada: si el pipeline enriquece varias
/// canciones a la vez, todas tienen que pasar por el mismo cuello de
/// botella. En C# se implementa con un lock; si los clientes lo llaman
/// correctamente con await, todas pasan por esta única instancia.
/// </summary>
public sealed class MusicBrainzRateLimiter
{
    /// <summary>Instancia compartida para que todos los clientes gasten un solo turno por segundo.</summary>
    public static MusicBrainzRateLimiter Shared { get; } = new();

    private readonly object _sync = new();
    private readonly double _minimumIntervalSeconds;
    private DateTimeOffset? _lastRequestAt;

    /// <summary>Crea un limitador (inyectable para tests).</summary>
    public MusicBrainzRateLimiter(double minimumIntervalSeconds = 1.0)
    {
        _minimumIntervalSeconds = minimumIntervalSeconds;
    }

    /// <summary>
    /// Espera lo necesario para que hayan pasado al menos
    /// <c>minimumInterval</c> desde el pedido anterior, y reserva el turno.
    /// Equivalente de <c>MusicBrainzRateLimiter.waitForTurn(now:)</c>.
    /// </summary>
    public async ValueTask WaitForTurnAsync(DateTimeOffset now = default)
    {
        now = now == default ? DateTimeOffset.UtcNow : now;
        DateTimeOffset toWaitUntil;
        lock (_sync)
        {
            if (_lastRequestAt is { } last)
            {
                var elapsed = (now - last).TotalSeconds;
                if (elapsed < _minimumIntervalSeconds)
                    toWaitUntil = last.AddSeconds(_minimumIntervalSeconds);
                else
                    toWaitUntil = now;
            }
            else
            {
                toWaitUntil = now;
            }
            _lastRequestAt = now;
        }
        var remaining = (toWaitUntil - DateTimeOffset.UtcNow).TotalMilliseconds;
        if (remaining > 0)
            await Task.Delay((int)remaining).ConfigureAwait(false);
    }

    /// <summary>
    /// Solo para tests: cuánto habría que esperar, sin dormir ni reservar.
    /// Equivalente de <c>MusicBrainzRateLimiter.pendingDelay(now:)</c>.
    /// </summary>
    public double PendingDelay(DateTimeOffset now)
    {
        lock (_sync)
        {
            if (_lastRequestAt is not { } last) return 0;
            return Math.Max(0, _minimumIntervalSeconds - (now - last).TotalSeconds);
        }
    }

    /// <summary>Reserva un turno en <paramref name="date"/> (para tests). Equivalente de <c>reserve(at:)</c>.</summary>
    public void Reserve(DateTimeOffset date)
    {
        lock (_sync)
        {
            _lastRequestAt = date;
        }
    }
}
