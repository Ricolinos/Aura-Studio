namespace AuraStudio.Core.Library;

/// <summary>
/// Se intentó escribir en una biblioteca cuyo disco no está montado (ST-171).
///
/// <para>Es un tipo propio y no una <c>DirectoryNotFoundException</c> suelta a
/// propósito: quien llama tiene que poder distinguir "esta biblioteca no está
/// disponible ahora" —un estado normal, que se cuenta en pantalla— de un error
/// de entrada/salida de verdad.</para>
/// </summary>
public sealed class LibraryRootUnavailableException(string root)
    : IOException($"La biblioteca no está disponible: {root}")
{
    public string Root { get; } = root;
}

/// <summary>En qué estado está la carpeta donde vive la biblioteca (ST-171).</summary>
public enum LibraryRootState
{
    /// <summary>La carpeta está donde dice y se puede trabajar con ella.</summary>
    Available,

    /// <summary>
    /// No está: el disco no está conectado, la unidad de red no está mapeada, o
    /// alguien movió o borró la carpeta. <b>No es un error</b> — es un estado
    /// normal de una biblioteca que vive en un disco externo.
    /// </summary>
    RootMissing
}

/// <summary>
/// Si se puede tocar la biblioteca ahora mismo, y en qué carpeta (ST-171).
/// </summary>
/// <param name="Root">La carpeta que se esperaba, para poder decírsela al usuario.</param>
public readonly record struct LibraryAvailability(LibraryRootState State, string Root)
{
    public bool IsAvailable => State == LibraryRootState.Available;

    public bool IsRootMissing => State == LibraryRootState.RootMissing;

    /// <summary>
    /// Lo decide el <b>volumen</b>, no la carpeta: una carpeta que todavía no
    /// existe en un disco que sí está es una biblioteca <b>nueva</b>, no una
    /// desconectada — es exactamente lo que pasa en el primer arranque, con
    /// <c>Documentos\Aura Studio</c> sin crear todavía.
    /// </summary>
    public static LibraryAvailability For(string? root) =>
        new(LibraryRoot.VolumeIsMounted(root) ? LibraryRootState.Available : LibraryRootState.RootMissing,
            root ?? "");
}

/// <summary>
/// La precondición de todo lo que lee o escribe la biblioteca (ST-171).
///
/// <para><b>De dónde sale.</b> El dueño abrió la 0.2.1 con su disco externo
/// desmontado y le salió un diálogo de "Algo salió mal": una
/// <c>DirectoryNotFoundException</c> desde el <b>constructor</b> del modelo de
/// la biblioteca, que la inyección de dependencias nunca llegaba a construir —
/// así que cada página que lo pedía volvía a intentarlo y volvía a
/// explotar.</para>
///
/// <para><b>Lo que decide es el VOLUMEN, no la carpeta</b>, y la diferencia no
/// es un detalle: una carpeta que todavía no existe en un disco que sí está es
/// una biblioteca <b>nueva</b> —el primer arranque, con
/// <c>Documentos\Aura Studio</c> sin crear— y tiene que seguir funcionando como
/// siempre: se crea sola al primer guardado. Atarlo a que la carpeta exista
/// rompía justamente ese caso, y la primera pantalla de alguien que abre la app
/// por primera vez decía "la biblioteca está en un disco que no está
/// conectado", señalando su propia carpeta de Documentos.</para>
///
/// <list type="bullet">
/// <item><see cref="VolumeIsMounted"/> — el disco de esa ruta está montado. Es
/// la única condición: sin él no se lee, no se escribe y no se concluye nada.
/// Con él, una carpeta ausente es una biblioteca por estrenar.</item>
/// <item><see cref="IsAvailable"/> — además, la carpeta existe. No gobierna
/// ningún flujo: está para quien necesite distinguir "por estrenar" de "ya
/// usada" sin volver a tocar el disco.</item>
/// </list>
///
/// <para><b>Lo que se acepta a cambio</b>: con el disco presente y la carpeta
/// borrada por fuera, la app la trata como biblioteca nueva y la vuelve a crear
/// —igual que antes de ST-171—. Distinguir ese caso del primer arranque exige
/// recordar si alguna vez se leyó esa biblioteca, y ese estado extra no vale lo
/// que cuesta: el catálogo ya se había perdido con la carpeta.</para>
/// </summary>
public static class LibraryRoot
{
    /// <summary>
    /// La carpeta de la biblioteca existe ahora mismo. Una ruta vacía no
    /// cuenta: no hay ninguna biblioteca que abrir.
    /// </summary>
    public static bool IsAvailable(string? root)
    {
        if (string.IsNullOrWhiteSpace(root)) return false;

        try
        {
            return Directory.Exists(root);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException
                                      or ArgumentException or NotSupportedException)
        {
            // Una ruta con forma inválida o un volumen que responde mal es,
            // para lo que importa acá, lo mismo que una carpeta ausente.
            return false;
        }
    }

    /// <summary>
    /// El volumen de esa ruta está montado — aunque la carpeta todavía no
    /// exista. Es lo que distingue "hay que crear la carpeta de la biblioteca
    /// nueva" de "esa unidad no está".
    /// </summary>
    public static bool VolumeIsMounted(string? root)
    {
        if (string.IsNullOrWhiteSpace(root)) return false;

        try
        {
            string? volume = Path.GetPathRoot(Path.GetFullPath(root));

            // Una ruta relativa no tiene volumen propio: cuelga del directorio
            // actual, que por definición está montado.
            if (string.IsNullOrEmpty(volume)) return true;

            return Directory.Exists(volume);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException
                                      or ArgumentException or NotSupportedException)
        {
            return false;
        }
    }
}
