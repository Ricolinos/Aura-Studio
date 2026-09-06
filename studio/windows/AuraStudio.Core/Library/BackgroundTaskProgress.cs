namespace AuraStudio.Core.Library;

/// <summary>
/// El avance de una tarea de fondo (ST-203; paridad con
/// <c>BackgroundTaskCenter.Progress</c> de ST-156).
///
/// <para>Dos formas, y la diferencia importa en pantalla: <b>determinada</b>
/// cuando se sabe cuántas son de antemano —cargar la biblioteca, importar,
/// enriquecer— e <b>indeterminada</b> cuando no se puede estimar. Una barra que
/// finge saber cuánto falta es peor que una que gira.</para>
/// </summary>
public readonly record struct BackgroundTaskProgress(int Completed, int Total)
{
    /// <summary>No se puede estimar cuánto falta.</summary>
    public static BackgroundTaskProgress Indeterminate { get; } = new(0, 0);

    public static BackgroundTaskProgress Of(int completed, int total) =>
        new(Math.Max(0, completed), Math.Max(0, total));

    public bool IsDeterminate => Total > 0;

    /// <summary>De 0 a 1; <c>null</c> si no se sabe.</summary>
    public double? Fraction => IsDeterminate ? Math.Clamp((double)Completed / Total, 0, 1) : null;

    /// <summary>"3 de 40"; vacío si no se sabe cuántas son.</summary>
    public string CountText => IsDeterminate
        ? $"{LibraryStats.Formatted(Completed)} de {LibraryStats.Formatted(Total)}"
        : "";

    /// <summary>
    /// El avance de varias tareas juntas, para un solo indicador. Las
    /// indeterminadas <b>no promedian</b> —no tienen fracción que aportar—,
    /// pero su sola presencia ya basta para que el indicador se vea: girando,
    /// sin fingir un porcentaje.
    /// </summary>
    public static double? Aggregate(IEnumerable<BackgroundTaskProgress> progresses)
    {
        double sum = 0;
        int count = 0;

        foreach (BackgroundTaskProgress progress in progresses)
        {
            if (progress.Fraction is not { } fraction) continue;

            sum += fraction;
            count++;
        }

        return count == 0 ? null : sum / count;
    }
}
