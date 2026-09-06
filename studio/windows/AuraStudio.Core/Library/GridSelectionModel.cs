namespace AuraStudio.Core.Library;

/// <summary>
/// Qué cambió en una selección: nada más que eso.
///
/// <para>Existe porque la vista solo puede permitirse tocar <b>lo que cambió</b>.
/// Un clic en una cuadrícula de 1 091 tarjetas cambia dos: la que estaba marcada
/// y la nueva. Escribir la propiedad en las 1 091 —aunque el <c>set</c> descarte
/// las 1 089 iguales— era el recorrido que se pagaba en cada clic.</para>
/// </summary>
/// <param name="Selected">Los que pasaron a estar marcados.</param>
/// <param name="Deselected">Los que dejaron de estarlo.</param>
public readonly record struct SelectionDelta(
    IReadOnlyList<string> Selected, IReadOnlyList<string> Deselected)
{
    public static SelectionDelta None { get; } = new([], []);

    public bool IsEmpty => Selected.Count == 0 && Deselected.Count == 0;

    public int Count => Selected.Count + Deselected.Count;
}

/// <summary>
/// La selección de una cuadrícula o de una tabla, como lógica pura: un conjunto
/// de identificadores y las operaciones que lo cambian, cada una devolviendo
/// <b>solo lo que cambió</b> (ST-201).
///
/// <para>Todo es O(1) o proporcional a lo que se toca, nunca al tamaño de la
/// cuadrícula: <see cref="Count"/> no cuenta, <see cref="Contains"/> no busca y
/// <see cref="SelectOnly"/> no recorre las tarjetas — se sabe de antemano cuáles
/// estaban marcadas.</para>
///
/// <para>No sabe qué es una tarjeta ni qué es una fila. Eso es a propósito: la
/// misma clase le sirve a la cuadrícula de Álbumes, a la tabla de Canciones y al
/// alcance de sincronización, y así "seleccionar" significa exactamente lo mismo
/// en las tres.</para>
/// </summary>
public sealed class GridSelectionModel
{
    private readonly HashSet<string> _ids = new(StringComparer.Ordinal);

    /// <summary>Cuántos hay marcados. O(1).</summary>
    public int Count => _ids.Count;

    /// <summary>Si hay <b>algo</b> marcado — lo que decide si se ven las casillas (R2-1).</summary>
    public bool Any => _ids.Count > 0;

    public bool Contains(string id) => _ids.Contains(id);

    /// <summary>
    /// Lo marcado, sin orden garantizado. Quien necesite el orden de la
    /// cuadrícula tiene que recorrer la cuadrícula: acá no vive esa información
    /// y fingir que sí sería mentirle a quien lo use.
    /// </summary>
    public IReadOnlyCollection<string> Ids => _ids;

    /// <summary>La casilla: <b>suma o quita ese</b> sin tocar el resto.</summary>
    public SelectionDelta Toggle(string id) => Set(id, !_ids.Contains(id));

    /// <summary>Marcar o desmarcar uno, sin tocar el resto.</summary>
    public SelectionDelta Set(string id, bool selected)
    {
        if (selected) return _ids.Add(id) ? new SelectionDelta([id], []) : SelectionDelta.None;
        return _ids.Remove(id) ? new SelectionDelta([], [id]) : SelectionDelta.None;
    }

    /// <summary>
    /// El clic en la tarjeta: <b>reemplaza</b> la selección, como en macOS y como
    /// en cualquier cuadrícula del sistema.
    /// </summary>
    public SelectionDelta SelectOnly(string id)
    {
        if (_ids.Count == 1 && _ids.Contains(id)) return SelectionDelta.None;

        List<string> deselected = [.. _ids.Where(other => !string.Equals(other, id, StringComparison.Ordinal))];
        bool wasSelected = _ids.Contains(id);

        _ids.Clear();
        _ids.Add(id);

        return new SelectionDelta(wasSelected ? [] : [id], deselected);
    }

    public SelectionDelta Clear()
    {
        if (_ids.Count == 0) return SelectionDelta.None;

        List<string> deselected = [.. _ids];
        _ids.Clear();
        return new SelectionDelta([], deselected);
    }

    /// <summary>Ctrl+A: suma todo lo que se ve, sin quitar nada.</summary>
    public SelectionDelta SelectAll(IEnumerable<string> ids)
    {
        List<string> selected = [.. ids.Where(_ids.Add)];
        return selected.Count == 0 ? SelectionDelta.None : new SelectionDelta(selected, []);
    }

    /// <summary>
    /// Deja exactamente esa selección. Es lo que hace falta cuando manda el
    /// control —el <c>SelectedItems</c> nativo de W2— y el modelo solo tiene que
    /// ponerse al día.
    /// </summary>
    public SelectionDelta Replace(IEnumerable<string> ids)
    {
        var incoming = new HashSet<string>(ids, StringComparer.Ordinal);

        List<string> selected = [.. incoming.Where(id => !_ids.Contains(id))];
        List<string> deselected = [.. _ids.Where(id => !incoming.Contains(id))];

        if (selected.Count == 0 && deselected.Count == 0) return SelectionDelta.None;

        _ids.Clear();
        foreach (string id in incoming) _ids.Add(id);

        return new SelectionDelta(selected, deselected);
    }

    /// <summary>
    /// Después de refrescar: se quedan marcados los que <b>siguen existiendo</b>.
    ///
    /// <para>Sin esto, borrar un álbum seleccionado lo dejaría en la selección
    /// para siempre — invisible, pero alcanzado por «Solo la selección» y por el
    /// menú contextual.</para>
    /// </summary>
    public SelectionDelta Retain(IEnumerable<string> present)
    {
        if (_ids.Count == 0) return SelectionDelta.None;

        var alive = new HashSet<string>(present, StringComparer.Ordinal);
        List<string> gone = [.. _ids.Where(id => !alive.Contains(id))];
        if (gone.Count == 0) return SelectionDelta.None;

        foreach (string id in gone) _ids.Remove(id);
        return new SelectionDelta([], gone);
    }
}
