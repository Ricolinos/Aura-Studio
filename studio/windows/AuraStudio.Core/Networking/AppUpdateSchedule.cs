namespace AuraStudio.Core.Networking;

/// <summary>
/// Cuándo Aura Studio se pregunta por sí misma, y cuándo lo dice (ST-211,
/// §1 y §4 de <c>docs/propuesta-actualizacion-de-la-app.md</c>).
///
/// <para>Es puro: entran la última vez que se consultó, la versión que ya se
/// anunció y el reloj; sale si toca preguntar y si toca avisar. Así se prueba
/// sin esperar veinticuatro horas ni tocar preferencias.</para>
/// </summary>
public static class AppUpdateSchedule
{
    /// <summary>
    /// Cada cuánto consulta el chequeo <b>automático</b>. Fijo para las dos
    /// plataformas: es la misma app y el mismo repositorio, y dos intervalos
    /// distintos serían dos comportamientos que explicar.
    /// </summary>
    public static readonly TimeSpan Interval = TimeSpan.FromHours(24);

    /// <summary>
    /// Si al arrancar corresponde consultar. <c>null</c> —nunca se consultó—
    /// cuenta como que sí.
    ///
    /// <para>Un reloj que fue hacia atrás (cambio de zona, ajuste de hora)
    /// también cuenta como que sí: quedarse esperando a que el futuro alcance a
    /// una marca imposible dejaría a la app sin volver a preguntar nunca.</para>
    /// </summary>
    public static bool ShouldCheckAutomatically(DateTimeOffset? lastCheck, DateTimeOffset now)
    {
        if (lastCheck is not { } last) return true;
        if (last > now) return true;

        return now - last >= Interval;
    }

    /// <summary>
    /// Si hay que <b>avisar</b> de esa versión. Un aviso por versión: cerrar la
    /// franja no puede significar que vuelva a aparecer al rato con lo mismo.
    ///
    /// <para>Lo que sí vuelve a avisar es una versión <b>distinta</b>: haber
    /// cerrado el aviso de la 0.3.0 no calla el de la 0.3.1.</para>
    /// </summary>
    public static bool ShouldAnnounce(string version, string? alreadyAnnounced)
    {
        if (version.Length == 0) return false;

        return !string.Equals(version, alreadyAnnounced, StringComparison.OrdinalIgnoreCase);
    }
}
