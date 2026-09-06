namespace AuraStudio.Core.Library;

/// <summary>Un punto de la cuadrícula, en coordenadas del contenido desplazable.</summary>
public readonly record struct GridPoint(double X, double Y);

/// <summary>
/// Un rectángulo, en las mismas coordenadas. Existe acá y no se usa el de la
/// interfaz a propósito: el núcleo del arrastre no conoce ninguna vista, y así
/// se puede probar sin mover un mouse (ST-209).
/// </summary>
public readonly record struct GridRect(double X, double Y, double Width, double Height)
{
    public double Right => X + Width;

    public double Bottom => Y + Height;

    /// <summary>Un rectángulo sin superficie no toca nada, ni siquiera lo que lo contiene.</summary>
    public bool IsEmpty => Width <= 0 || Height <= 0;

    /// <summary>
    /// El rectángulo que va de un punto al otro, sin importar en qué dirección
    /// se arrastró: arrastrar hacia arriba y a la izquierda es tan válido como
    /// hacia abajo y a la derecha.
    /// </summary>
    public static GridRect Between(GridPoint a, GridPoint b) => new(
        Math.Min(a.X, b.X),
        Math.Min(a.Y, b.Y),
        Math.Abs(a.X - b.X),
        Math.Abs(a.Y - b.Y));

    /// <summary>
    /// Si los dos se solapan. <b>Tocarse de canto no cuenta</b>: el recuadro que
    /// apenas roza el borde de una tarjeta no la selecciona, que es lo que hace
    /// que arrastrar entre dos columnas no marque las dos.
    /// </summary>
    public bool Intersects(GridRect other)
    {
        if (IsEmpty || other.IsEmpty) return false;

        return X < other.Right && Right > other.X && Y < other.Bottom && Bottom > other.Y;
    }
}

/// <summary>
/// Las teclas que cambian lo que hace un gesto, como valor y no como estado
/// global del teclado (ST-209).
///
/// <para>Se pasan por parámetro por la misma razón que en ST-152: el estado del
/// teclado no se puede simular en una prueba, así que un núcleo que lo consulte
/// solo se puede verificar a mano.</para>
/// </summary>
[Flags]
public enum GridSelectionModifiers
{
    None = 0,

    /// <summary>Mayúsculas: <b>suma</b> a la selección de partida.</summary>
    Extend = 1,

    /// <summary>Control: <b>alterna</b> respecto de la selección de partida.</summary>
    Toggle = 2
}

/// <summary>
/// El arrastre de selección —el recuadro— resuelto como funciones puras
/// (ST-209; hermano de <c>GridMarquee</c> de ST-184 en la Mac).
///
/// <para>No sabe qué es una tarjeta: recibe los <b>marcos</b> que la cuadrícula
/// reporta y devuelve identificadores. La capa de interfaz solo traduce
/// pulsar/mover/soltar a puntos y modificadores, y no decide nada.</para>
/// </summary>
public static class GridMarquee
{
    /// <summary>Qué tarjetas toca el recuadro, en el orden en que están en la cuadrícula.</summary>
    public static IReadOnlyList<string> Hits(
        GridRect rect, IReadOnlyDictionary<string, GridRect> frames)
    {
        if (rect.IsEmpty || frames.Count == 0) return [];

        List<KeyValuePair<string, GridRect>> touched = [];

        foreach (KeyValuePair<string, GridRect> frame in frames)
        {
            if (rect.Intersects(frame.Value)) touched.Add(frame);
        }

        // Por posición y no por el orden del diccionario: lo que devuelve tiene
        // que leerse como se ve —de arriba abajo y de izquierda a derecha—, y un
        // diccionario no promete ningún orden.
        touched.Sort(static (a, b) =>
        {
            int byRow = a.Value.Y.CompareTo(b.Value.Y);
            return byRow != 0 ? byRow : a.Value.X.CompareTo(b.Value.X);
        });

        return [.. touched.Select(frame => frame.Key)];
    }

    /// <summary>
    /// La selección que resulta de arrastrar ese recuadro, dada la que había
    /// <b>al empezar</b>.
    ///
    /// <list type="bullet">
    /// <item>Sin modificadores, el recuadro <b>reemplaza</b> la selección.</item>
    /// <item>Con Mayúsculas, <b>suma</b> a la de partida.</item>
    /// <item>Con Control, <b>alterna</b> respecto de la de partida: lo que ya
    /// estaba marcado y entra al recuadro sale.</item>
    /// </list>
    ///
    /// <para>Con las dos manda Control, que es la más específica de las dos: un
    /// gesto que alterna y suma a la vez no significa nada.</para>
    ///
    /// <para><b>La de partida se pasa entera en cada movimiento</b>, y no se va
    /// acumulando: es lo que hace que agrandar y achicar el recuadro sea
    /// reversible. Resolver cada posición contra la selección anterior dejaría
    /// dentro lo que ya salió.</para>
    /// </summary>
    public static IReadOnlyList<string> Selection(
        GridRect rect,
        IReadOnlyDictionary<string, GridRect> frames,
        IReadOnlyCollection<string> start,
        GridSelectionModifiers modifiers)
    {
        IReadOnlyList<string> hits = Hits(rect, frames);

        if (modifiers.HasFlag(GridSelectionModifiers.Toggle))
        {
            var toggled = new HashSet<string>(start, StringComparer.Ordinal);
            foreach (string id in hits)
            {
                if (!toggled.Add(id)) toggled.Remove(id);
            }

            return [.. toggled];
        }

        if (!modifiers.HasFlag(GridSelectionModifiers.Extend)) return hits;

        var extended = new HashSet<string>(start, StringComparer.Ordinal);
        List<string> result = [.. start];

        foreach (string id in hits)
        {
            if (extended.Add(id)) result.Add(id);
        }

        return result;
    }
}

/// <summary>
/// Un arrastre en curso (ST-209): congela la selección de partida y va
/// devolviendo <b>solo lo que cambia</b> en cada movimiento del puntero.
///
/// <para><b>Por qué congelarla.</b> Si cada posición del mouse se resolviera
/// contra la selección de ese instante, agrandar el recuadro y volver a
/// achicarlo no devolvería las tarjetas que ya habían entrado: se irían
/// acumulando. Se resuelve siempre contra la que había cuando empezó el
/// arrastre.</para>
///
/// <para>Devuelve <see cref="SelectionDelta"/> y no la selección entera por lo
/// mismo que ST-201: mover el puntero un píxel no puede costar escribir mil
/// propiedades.</para>
/// </summary>
public sealed class GridMarqueeDrag
{
    private readonly HashSet<string> _start;
    private readonly HashSet<string> _current;

    public GridMarqueeDrag(
        GridPoint origin, IReadOnlyCollection<string> start, GridSelectionModifiers modifiers)
    {
        Origin = origin;
        Modifiers = modifiers;
        _start = new HashSet<string>(start, StringComparer.Ordinal);
        _current = new HashSet<string>(_start, StringComparer.Ordinal);
    }

    /// <summary>Dónde se apretó el botón.</summary>
    public GridPoint Origin { get; }

    public GridSelectionModifiers Modifiers { get; }

    /// <summary>El recuadro de la última posición. Es lo que la vista dibuja.</summary>
    public GridRect Rect { get; private set; }

    /// <summary>Lo marcado ahora mismo por este arrastre.</summary>
    public IReadOnlyCollection<string> Current => _current;

    /// <summary>
    /// Mueve el puntero y dice qué cambió. Los marcos se pasan en cada
    /// movimiento porque la cuadrícula se desplaza <b>durante</b> el arrastre:
    /// las tarjetas que entran a pantalla reportan el suyo entonces.
    /// </summary>
    public SelectionDelta MoveTo(GridPoint point, IReadOnlyDictionary<string, GridRect> frames)
    {
        Rect = GridRect.Between(Origin, point);

        var next = new HashSet<string>(
            GridMarquee.Selection(Rect, frames, _start, Modifiers), StringComparer.Ordinal);

        List<string> selected = [];
        List<string> deselected = [];

        foreach (string id in next)
        {
            if (!_current.Contains(id)) selected.Add(id);
        }

        foreach (string id in _current)
        {
            if (!next.Contains(id)) deselected.Add(id);
        }

        _current.Clear();
        foreach (string id in next) _current.Add(id);

        return new SelectionDelta(selected, deselected);
    }
}

/// <summary>
/// Los marcos de las tarjetas realizadas (ST-209). Las tarjetas reportan el suyo
/// al aparecer y al moverse, y lo retiran al salir de pantalla — si no, el
/// arrastre "tocaría" tarjetas que ya no están donde dice el mapa.
///
/// <para>Son solo las <b>realizadas</b>: con la virtualización de la cuadrícula,
/// las decenas que se ven, no las mil que hay. Escribir acá <b>no avisa a
/// nadie</b>: desplazarse no puede repintar la cuadrícula por esto.</para>
/// </summary>
public sealed class GridFrameMap
{
    private readonly Dictionary<string, GridRect> _frames = new(StringComparer.Ordinal);

    public IReadOnlyDictionary<string, GridRect> Frames => _frames;

    public int Count => _frames.Count;

    public void Report(string id, GridRect frame) => _frames[id] = frame;

    public void Remove(string id) => _frames.Remove(id);

    public void Clear() => _frames.Clear();
}

/// <summary>
/// Cuánto desplazar cuando el arrastre llega al borde (ST-209). Sin esto no se
/// puede seleccionar más de lo que entra en pantalla.
///
/// <para>Es una función pura del puntero y del alto visible: la vista pregunta
/// y desplaza, no decide.</para>
/// </summary>
public static class GridAutoScroll
{
    /// <summary>A cuántos píxeles del borde empieza a desplazarse.</summary>
    public const double DefaultMargin = 32;

    /// <summary>Lo más rápido que se desplaza, en píxeles por paso.</summary>
    public const double DefaultMaxSpeed = 24;

    /// <summary>
    /// Negativo hacia arriba, positivo hacia abajo, cero en el medio. Crece con
    /// lo cerca que esté del borde —no es un escalón— para que se pueda ajustar
    /// despacio al llegar; pasado el borde, va al máximo.
    /// </summary>
    public static double SpeedFor(
        double pointerY,
        double viewportHeight,
        double margin = DefaultMargin,
        double maxSpeed = DefaultMaxSpeed)
    {
        if (viewportHeight <= 0 || margin <= 0 || maxSpeed <= 0) return 0;

        // Con una ventana más chica que los dos márgenes, se repartirían el alto
        // y no habría zona quieta: cualquier posición desplazaría.
        double usable = Math.Min(margin, viewportHeight / 2);

        if (pointerY < usable)
        {
            double depth = Math.Min(usable - pointerY, usable);
            return -maxSpeed * (depth / usable);
        }

        double fromBottom = viewportHeight - pointerY;

        if (fromBottom < usable)
        {
            double depth = Math.Min(usable - fromBottom, usable);
            return maxSpeed * (depth / usable);
        }

        return 0;
    }
}
