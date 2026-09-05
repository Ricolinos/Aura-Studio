namespace AuraStudio.Core.Library;

/// <summary>
/// Cuándo vale la pena anunciar que la selección cambió (ST-161).
///
/// <para>Publicar la selección es un <b>aviso</b>, y un aviso que sale cuando
/// no cambió nada es una invitación a un ciclo: la vista que lo escucha se
/// refresca, al refrescarse vuelve a publicar su selección, el aviso vuelve a
/// salir, y así hasta que se acaba la pila. Eso fue exactamente ST-161.</para>
///
/// <para>La comparación es <b>por contenido, nunca por referencia</b>: cada
/// refresco arma una lista nueva con los mismos ids, así que comparar las
/// instancias diría "cambió" siempre — que es justo la lectura que cerraba el
/// ciclo.</para>
/// </summary>
public static class SelectionPublication
{
    /// <summary>
    /// Si las dos selecciones alcanzan lo mismo.
    ///
    /// <para>Es un <b>conjunto</b>: ni el orden ni las repeticiones cambian a
    /// qué canciones llega «Solo la selección», así que tampoco pueden contar
    /// como un cambio que valga un aviso.</para>
    /// </summary>
    public static bool SameSelection<T>(
        IReadOnlyCollection<T> published, IReadOnlyCollection<T> incoming)
        where T : notnull
    {
        if (ReferenceEquals(published, incoming)) return true;
        if (published.Count == 0 && incoming.Count == 0) return true;

        return published.ToHashSet().SetEquals(incoming);
    }
}
