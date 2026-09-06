namespace AuraStudio.Core.Library;

/// <summary>
/// El orden y el costo de una caché de miniaturas, <b>sin las imágenes</b>
/// (ST-205). Dice qué hay, qué se acaba de usar y qué hay que soltar cuando ya
/// no cabe; quién guarda los mapas de bits es la app, que es la única que sabe
/// de imágenes.
///
/// <para><b>Por costo y no por cantidad.</b> Un tope de "600 entradas" no dice
/// nada sobre la memoria: seiscientas miniaturas de 48 px son 5 MB y seiscientas
/// de 304 px son 220 MB. Lo que se acota es lo que ocupan.</para>
///
/// <para><b>Todo es O(1).</b> Cada clave guarda su nodo en la lista de uso, así
/// que marcar una como reciente no la busca: una lista enlazada recorrida por
/// tarjeta al desplazarse es exactamente el costo que una caché viene a
/// quitar.</para>
///
/// <para>No es seguro entre hilos: quien lo use lo protege. Está pensado para
/// vivir detrás del candado de la caché de verdad, y meterle otro adentro sería
/// pagarlo dos veces.</para>
/// </summary>
public sealed class ThumbnailCacheIndex
{
    /// <summary>
    /// 64 MB. Con miniaturas de 304 px (152 pt a 2×) son unas cuatrocientas
    /// cincuenta, bastante más de lo que entra en pantalla y suficiente para que
    /// desplazarse hacia atrás no vuelva a decodificar nada.
    /// </summary>
    public const long DefaultCostLimit = 64L * 1024 * 1024;

    private readonly Dictionary<string, LinkedListNode<string>> _nodes = new(StringComparer.Ordinal);
    private readonly Dictionary<string, long> _costs = new(StringComparer.Ordinal);
    private readonly LinkedList<string> _order = [];

    public ThumbnailCacheIndex(long costLimit = DefaultCostLimit) =>
        CostLimit = costLimit > 0 ? costLimit : DefaultCostLimit;

    /// <summary>Lo más que puede ocupar lo guardado, en bytes.</summary>
    public long CostLimit { get; }

    /// <summary>Lo que ocupa ahora.</summary>
    public long Cost { get; private set; }

    public int Count => _nodes.Count;

    public bool Contains(string key) => _nodes.ContainsKey(key);

    /// <summary>
    /// Marca esa clave como la más reciente. Devuelve <c>false</c> si no estaba
    /// —entonces quien llama tiene que producirla— y no la agrega: agregarla
    /// sin su imagen dejaría el índice diciendo que hay algo que no hay.
    /// </summary>
    public bool Touch(string key)
    {
        if (!_nodes.TryGetValue(key, out LinkedListNode<string>? node)) return false;

        _order.Remove(node);
        _order.AddLast(node);
        return true;
    }

    /// <summary>
    /// Agrega una entrada y devuelve <b>las que hubo que soltar</b> para que
    /// entrara, en el orden en que se soltaron. Quien llama libera esas
    /// imágenes: el índice no sabe cómo.
    ///
    /// <para>Una entrada que sola ya no cabe en el tope <b>no se guarda</b> y se
    /// devuelve ella misma como expulsada: guardarla vaciaría la caché entera
    /// para nada.</para>
    /// </summary>
    public IReadOnlyList<string> Add(string key, long cost)
    {
        if (cost <= 0) cost = 1;

        List<string> evicted = [];

        // Reemplazar es soltar la vieja primero: si no, el costo se contaría dos
        // veces y el tope dejaría de significar nada.
        if (_nodes.TryGetValue(key, out LinkedListNode<string>? existing))
        {
            _order.Remove(existing);
            _nodes.Remove(key);
            Cost -= _costs[key];
            _costs.Remove(key);
        }

        if (cost > CostLimit)
        {
            evicted.Add(key);
            return evicted;
        }

        _nodes[key] = _order.AddLast(key);
        _costs[key] = cost;
        Cost += cost;

        while (Cost > CostLimit && _order.First is { } oldest)
        {
            string victim = oldest.Value;

            _order.RemoveFirst();
            _nodes.Remove(victim);
            Cost -= _costs[victim];
            _costs.Remove(victim);

            evicted.Add(victim);
        }

        return evicted;
    }

    /// <summary>
    /// Saca una entrada, si está. Devuelve <c>true</c> si estaba, para que quien
    /// llama sepa si tiene una imagen que soltar.
    /// </summary>
    public bool Remove(string key)
    {
        if (!_nodes.TryGetValue(key, out LinkedListNode<string>? node)) return false;

        _order.Remove(node);
        _nodes.Remove(key);
        Cost -= _costs[key];
        _costs.Remove(key);
        return true;
    }

    /// <summary>Vacía el índice y devuelve todo lo que había, para soltarlo.</summary>
    public IReadOnlyList<string> Clear()
    {
        List<string> all = [.. _order];

        _order.Clear();
        _nodes.Clear();
        _costs.Clear();
        Cost = 0;

        return all;
    }

    /// <summary>Lo guardado, de lo más viejo a lo más reciente. Para probar y para medir.</summary>
    public IReadOnlyList<string> KeysOldestFirst => [.. _order];
}
