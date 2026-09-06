namespace AuraStudio.Core.Library;

/// <summary>
/// Lo que el persistidor necesita de la plataforma: un temporizador y un hilo de
/// fondo (ST-204). Se inyecta para que la lógica de coalescencia se pueda probar
/// sin esperar medio segundo de reloj real — y para que Core no dependa de la
/// cola de despacho de WinUI.
/// </summary>
public interface ICatalogPersisterHost
{
    /// <summary>
    /// Corre <paramref name="work"/> dentro de <paramref name="delay"/>,
    /// <b>reemplazando</b> lo que hubiera pendiente. Tiene que correr en el hilo
    /// de interfaz: es donde se puede mirar el catálogo vivo sin carreras.
    /// </summary>
    void ScheduleAfter(TimeSpan delay, Action work);

    /// <summary>Cancela lo programado, si hay algo.</summary>
    void CancelScheduled();

    /// <summary>Corre <paramref name="work"/> fuera del hilo de interfaz.</summary>
    void RunInBackground(Action work);
}

/// <summary>
/// Guarda el catálogo <b>una vez por ráfaga</b> y <b>fuera del hilo de
/// interfaz</b> (ST-204; paridad con <c>CatalogPersister.swift</c> de ST-155).
///
/// <para><b>Qué había.</b> Cada mutación escribía el catálogo entero, de
/// inmediato y en el hilo de interfaz. Aplicar la tapa recomendada a 200 álbumes
/// eran 200 escrituras completas del catálogo; marcar 500 canciones como
/// favoritas, otras tantas.</para>
///
/// <para><b>Cómo funciona.</b> Pedir un guardado arma un temporizador corto;
/// pedirlo de nuevo antes de que salte lo reemplaza. Cuando salta, se arma la
/// <b>instantánea</b> en el hilo de interfaz —que es el único lugar donde el
/// catálogo vivo se puede leer sin carreras— y la escritura, que es lo lento, se
/// hace en segundo plano.</para>
///
/// <para><b>Por qué la instantánea.</b> Serializar directamente los elementos
/// vivos desde un hilo de fondo sería leerlos mientras la interfaz los muta: no
/// corrompería el archivo, pero sí podría escribir un estado que nunca existió
/// —media edición— en el catálogo del usuario. Copiarlos primero cuesta unas
/// decenas de milisegundos y quita el problema entero.</para>
/// </summary>
public sealed class CatalogPersister
{
    /// <summary>
    /// Cuánto se espera a que la ráfaga termine. Medio segundo es lo que pide el
    /// plan: suficiente para juntar un lote entero, poco para que nadie alcance
    /// a cerrar la app en el medio — y si lo hace, <see cref="Flush"/> lo
    /// escribe antes de salir.
    /// </summary>
    public static readonly TimeSpan DefaultDelay = TimeSpan.FromMilliseconds(500);

    private readonly ICatalogPersisterHost _host;
    private readonly Func<CatalogSnapshotRequest> _snapshot;
    private readonly TimeSpan _delay;

    /// <summary>
    /// Serializa las escrituras. <see cref="Flush"/> puede llegar mientras una
    /// programada ya está escribiendo, y dos escrituras a la vez se pisarían el
    /// archivo temporal.
    /// </summary>
    private readonly Lock _writing = new();

    private bool _pending;

    public CatalogPersister(
        ICatalogPersisterHost host, Func<CatalogSnapshotRequest> snapshot, TimeSpan? delay = null)
    {
        _host = host;
        _snapshot = snapshot;
        _delay = delay ?? DefaultDelay;
    }

    /// <summary>Si hay un guardado esperando a que salte el temporizador.</summary>
    public bool HasPending => _pending;

    /// <summary>Cuántas veces se escribió de verdad. Para medir la coalescencia.</summary>
    public int WriteCount { get; private set; }

    /// <summary>
    /// Por qué no se pudo guardar, si es que no se pudo. Sale en el hilo de
    /// fondo: quien lo escuche tiene que volver al de interfaz para mostrarlo.
    /// </summary>
    public event EventHandler<string>? Failed;

    /// <summary>
    /// Pide guardar. Varias llamadas seguidas son <b>un</b> guardado: es lo que
    /// convierte "aplicar la tapa a 200 álbumes" en una escritura y no en 200.
    /// </summary>
    public void Schedule()
    {
        _pending = true;
        _host.ScheduleAfter(_delay, WritePending);
    }

    /// <summary>
    /// Escribe lo que esté pendiente <b>ahora y sin volver</b>. Es lo que se
    /// llama antes de cerrar la app o de cambiar de carpeta de biblioteca: un
    /// guardado que todavía no salió no puede perderse porque el usuario cerró
    /// la ventana.
    /// </summary>
    public void Flush()
    {
        if (!_pending) return;

        _host.CancelScheduled();
        WriteNow(inBackground: false);
    }

    private void WritePending()
    {
        if (!_pending) return;

        WriteNow(inBackground: true);
    }

    private void WriteNow(bool inBackground)
    {
        _pending = false;

        CatalogSnapshotRequest request = _snapshot();
        if (request.Skip) return;

        // La instantánea se arma ACÁ, en el hilo de interfaz: es lo que hace que
        // lo que se escriba sea un estado que de verdad existió.
        PersistedLibrary catalog = request.Build();

        if (inBackground) _host.RunInBackground(() => Write(request.LibraryRoot, catalog));
        else Write(request.LibraryRoot, catalog);
    }

    private void Write(string libraryRoot, PersistedLibrary catalog)
    {
        lock (_writing)
        {
            try
            {
                LibraryCatalogStore.Save(libraryRoot, catalog);
                WriteCount++;
            }
            catch (LibraryRootUnavailableException)
            {
                // ST-171: el disco se fue. Es un estado, no un error que tirar
                // en la cara del usuario, y lo que hay en memoria sigue estando.
                Failed?.Invoke(this, "La biblioteca no está disponible: no se pudo guardar.");
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                Failed?.Invoke(this, $"No se pudo guardar la biblioteca: {ex.Message}");
            }
        }
    }
}

/// <summary>
/// De dónde sale lo que hay que guardar, resuelto en el momento del guardado y
/// no cuando se pidió: si entre medio hubo veinte cambios más, se escribe el
/// estado final una sola vez.
/// </summary>
/// <param name="Skip">
/// <c>true</c> para no escribir nada. ST-171: sin la biblioteca delante, lo que
/// hay en memoria no es el catálogo del usuario —es lo que quedó de no haber
/// podido leerlo— y guardarlo lo reemplazaría por eso.
/// </param>
/// <param name="Build">
/// Arma la instantánea. Se llama en el hilo de interfaz, y de ahí en adelante lo
/// que se escribe ya no cambia.
/// </param>
public readonly record struct CatalogSnapshotRequest(
    bool Skip, string LibraryRoot, Func<PersistedLibrary> Build)
{
    /// <summary>No hay nada que guardar, o no se debe.</summary>
    public static CatalogSnapshotRequest None { get; } =
        new(true, "", static () => new PersistedLibrary());
}
