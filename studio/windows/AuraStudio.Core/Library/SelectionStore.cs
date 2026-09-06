namespace AuraStudio.Core.Library;

/// <summary>
/// Lo que está seleccionado en la vista activa, fuera del modelo grande
/// (ST-202; paridad con <c>SelectionStore.swift</c> de ST-153).
///
/// <para><b>Por qué existe.</b> En macOS la selección era un <c>@Published</c>
/// del modelo gigante que la ventana entera observa, así que publicarla
/// disparaba un redibujo de TODO en cada clic. Acá pasaba lo mismo con otra
/// forma: <c>LibraryViewModel.SelectionForSync</c> avisaba por
/// <c>PropertyChanged</c> del modelo que escuchan todas las vistas de la
/// biblioteca, y cada una tenía que decidir si ese aviso le tocaba. Un almacén
/// chico y aparte, observado solo por quien consume la selección, saca al resto
/// de la app de ese camino.</para>
///
/// <para><b>Uno solo, compartido</b> —no uno por tipo de medio—, igual que en
/// macOS y por la misma razón: es la selección de la vista <b>activa</b>, la que
/// alimenta «Solo la selección» de sincronización, y se limpia al salir de esa
/// vista para que la siguiente no herede lo que el usuario ya no ve.</para>
///
/// <para>Avisa <b>solo cuando de verdad cambió</b> (ST-161): la comparación es
/// por contenido, como conjunto. Cada refresco de una cuadrícula arma una lista
/// nueva con los mismos identificadores, así que comparar instancias diría
/// "cambió" siempre — y ese aviso de más era el que cerraba el ciclo que colgaba
/// la app.</para>
/// </summary>
public sealed class SelectionStore
{
    private HashSet<Guid> _selected = [];

    /// <summary>
    /// Salta cuando cambia el <b>contenido</b> de la selección. Nunca por
    /// publicar lo mismo.
    /// </summary>
    public event EventHandler? Changed;

    /// <summary>Lo seleccionado. Es un conjunto: ni el orden ni las repeticiones significan nada acá.</summary>
    public IReadOnlyCollection<Guid> Selected => _selected;

    public int Count => _selected.Count;

    public bool Any => _selected.Count > 0;

    public bool Contains(Guid id) => _selected.Contains(id);

    /// <summary>
    /// Deja exactamente esa selección. Devuelve si cambió algo — y solo entonces
    /// avisa.
    /// </summary>
    public bool Replace(IEnumerable<Guid> ids)
    {
        var incoming = new HashSet<Guid>(ids);
        if (incoming.SetEquals(_selected)) return false;

        _selected = incoming;
        Changed?.Invoke(this, EventArgs.Empty);
        return true;
    }

    /// <summary>
    /// Suma y quita <b>solo lo que cambió</b>, sin rearmar la selección entera
    /// (ST-202).
    ///
    /// <para>Es la diferencia entre lineal y cuadrático cuando el usuario va
    /// sumando de a uno: con <see cref="Replace"/>, agregar el álbum número
    /// 1 000 vuelve a armar los 12 000 identificadores de las canciones que
    /// alcanza la selección, y sumado sobre mil gestos son seis millones. Acá
    /// cuesta lo que trae ese álbum.</para>
    ///
    /// <para>Quitar va primero: si un identificador viniera en las dos listas
    /// —dos tarjetas distintas que alcanzan la misma canción—, gana la que
    /// suma.</para>
    /// </summary>
    public bool Apply(IEnumerable<Guid> added, IEnumerable<Guid> removed)
    {
        bool changed = false;

        foreach (Guid id in removed) changed |= _selected.Remove(id);
        foreach (Guid id in added) changed |= _selected.Add(id);

        if (changed) Changed?.Invoke(this, EventArgs.Empty);
        return changed;
    }

    /// <summary>Se llama al dejar una vista: lo de la anterior no puede sobrevivirla.</summary>
    public bool Clear()
    {
        if (_selected.Count == 0) return false;

        _selected = [];
        Changed?.Invoke(this, EventArgs.Empty);
        return true;
    }
}
