namespace AuraStudio.Core.Library;

/// <summary>
/// Sobre qué se sincroniza (R3-4). Port de <c>LibraryViewModel.SyncScope</c>.
/// </summary>
public abstract record SyncScope
{
    /// <summary>Toda la biblioteca.</summary>
    public sealed record All : SyncScope;

    /// <summary>Solo lo que el usuario tiene seleccionado en la vista activa.</summary>
    public sealed record Selection(IReadOnlyCollection<Guid> Ids) : SyncScope;

    public static SyncScope Everything { get; } = new All();
}

/// <summary>
/// Qué se puede sincronizar con este alcance, o por qué no se puede.
/// </summary>
/// <param name="RestrictToSourcePaths">
/// Las rutas de origen a las que se acota la copia. <c>null</c> = sin acotar.
/// </param>
/// <param name="Refusal">
/// El motivo, <b>en palabras y para el usuario</b>, cuando no hay nada que
/// sincronizar. <c>null</c> = adelante.
/// </param>
public readonly record struct SyncScopeResolution(
    IReadOnlyCollection<string>? RestrictToSourcePaths,
    string? Refusal)
{
    public bool CanSync => Refusal is null;
}

/// <summary>
/// Traduce un alcance a "qué archivos exactamente", con los mismos mensajes
/// que macOS (R3-4).
///
/// <para>Existe aparte de la pantalla porque son <b>reglas</b>, no interfaz:
/// qué cuenta como "listo", en qué orden se comprueban las negativas y qué se
/// le dice al usuario en cada caso. Tres condiciones parecidas con tres
/// mensajes distintos es exactamente lo que se desincroniza entre dos apps si
/// cada una las escribe en su vista.</para>
///
/// <para>El botón que sincroniza la selección ya debería venir deshabilitado
/// sin nada elegido; esto es <b>la última línea de defensa</b> si de todas
/// formas se invoca vacío.</para>
/// </summary>
public static class SyncScopeResolver
{
    public const string NothingSelected = "No hay ningún elemento seleccionado para sincronizar.";

    public const string SelectionNotReady = "Los elementos seleccionados todavía no están listos para sincronizar.";

    public const string NothingReady = "No hay nada listo para sincronizar.";

    /// <summary>
    /// Solo lo que está <b>listo</b> viaja. Un elemento a medio convertir o que
    /// espera una decisión del usuario no es un archivo que se pueda copiar.
    /// </summary>
    public static IReadOnlyList<LibraryItem> Ready(IEnumerable<LibraryItem> items) =>
        [.. items.Where(item => item.Status.State == LibraryItemState.Ready)];

    /// <summary>
    /// Cuántos elementos están listos. Es la <b>aproximación</b> que se muestra
    /// antes de comparar contra el iPod: alguno de estos puede estar ya
    /// sincronizado con ESTE aparato, y eso solo lo sabe la revisión.
    /// </summary>
    public static int PendingCount(IEnumerable<LibraryItem> items) => Ready(items).Count;

    public static SyncScopeResolution Resolve(IReadOnlyList<LibraryItem> items, SyncScope scope)
    {
        IReadOnlyList<LibraryItem> ready = Ready(items);
        IReadOnlyCollection<string>? restricted = null;

        // El orden importa y es el de macOS: primero las negativas propias del
        // alcance —son las que explican qué le falta a SU selección— y recién
        // después la global. Al revés, quien selecciona tres canciones en una
        // biblioteca vacía leería "no hay nada listo" y no sabría si el
        // problema es su selección.
        if (scope is SyncScope.Selection selection)
        {
            if (selection.Ids.Count == 0) return new SyncScopeResolution(null, NothingSelected);

            var ids = selection.Ids.ToHashSet();
            IReadOnlyList<LibraryItem> selectedReady = [.. ready.Where(item => ids.Contains(item.Id))];

            if (selectedReady.Count == 0) return new SyncScopeResolution(null, SelectionNotReady);

            restricted = [.. selectedReady.Select(item => item.SourcePath)];
        }

        return ready.Count == 0
            ? new SyncScopeResolution(null, NothingReady)
            : new SyncScopeResolution(restricted, null);
    }
}
