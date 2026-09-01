namespace AuraStudio.Core.Library;

/// <summary>
/// Una lista armada en Studio a partir de los <see cref="LibraryItem"/> de
/// música ya agregados. Port de <c>Playlist.swift</c>.
///
/// <para>Studio <b>no</b> mantiene una base de datos de lo que ya está en el
/// iPod: <see cref="TrackItemIds"/> guarda el orden que eligió el usuario y se
/// resuelve a rutas reales del dispositivo recién al sincronizar.</para>
/// </summary>
public sealed class Playlist
{
    public Guid Id { get; init; } = Guid.NewGuid();

    public string Name { get; set; } = "";

    /// <summary>En el orden que eligió el usuario.</summary>
    public List<Guid> TrackItemIds { get; set; } = [];

    /// <summary>
    /// Imagen elegida a mano, relativa a la carpeta de biblioteca — mismo
    /// criterio que la portada de un item: un archivo en <c>.portadas/</c>, no
    /// bytes embebidos acá, para que el catálogo siga siendo liviano.
    /// <c>null</c> = sin imagen propia; la sincronización genera un colage por
    /// omisión.
    /// </summary>
    public string? ImageRelativePath { get; set; }
}

/// <summary>
/// Genera el contenido de un <c>.m3u8</c> que el firmware ya sabe leer. Port de
/// <c>PlaylistExporter.swift</c>.
///
/// <para><c>aura_music_list_playlists</c> escanea <c>/Playlists</c> buscando
/// <c>.m3u</c>/<c>.m3u8</c> y se los pasa tal cual a <c>playlist_create()</c>
/// de Rockbox, que acepta rutas UNIX <b>absolutas</b> sin modificarlas — por eso
/// las entradas son <c>/Music/…</c> y no rutas relativas al archivo de lista,
/// que dejarían la resolución ambigua.</para>
/// </summary>
public static class PlaylistExporter
{
    public static string FileName(string playlistName) =>
        PathSanitizer.Sanitize(playlistName) + ".m3u8";

    /// <summary>
    /// La portada lleva el <b>mismo nombre base</b> que el <c>.m3u8</c>: el
    /// firmware la encuentra pelándole la extensión y probando ese nombre con
    /// <c>.jpg</c> (<c>aura_playlist_art_load</c>), así que los dos tienen que
    /// sanitizar exactamente igual — y por eso comparten la llamada.
    /// </summary>
    public static string ImageFileName(string playlistName) =>
        PathSanitizer.Sanitize(playlistName) + ".jpg";

    /// <summary>
    /// <paramref name="trackDestinationPaths"/> son las mismas rutas de destino
    /// con las que la sincronización copia cada pista (sin la "/" inicial):
    /// esta función es la <b>única</b> responsable de agregársela.
    ///
    /// <para>Termina en salto de línea y usa "\n", no "\r\n": lo lee el firmware
    /// en el iPod, no Windows.</para>
    /// </summary>
    public static string M3u8Contents(IEnumerable<string> trackDestinationPaths)
    {
        var lines = new List<string> { "#EXTM3U" };
        lines.AddRange(trackDestinationPaths.Select(path => "/" + path));
        return string.Join("\n", lines) + "\n";
    }
}

/// <summary>
/// Importa una lista M3U/M3U8 de otro programa o servicio. Port de
/// <c>PlaylistImporter.swift</c>.
///
/// <para>Es el camino simétrico de <see cref="PlaylistExporter"/>: cualquier
/// programa que exporte M3U/M3U8 (iTunes, VLC, Winamp, casi todo servicio con
/// exportador local) sirve como fuente.</para>
///
/// <para>El parseo es <b>puro</b> — no toca disco ni el catálogo — para poder
/// probarlo sin archivos reales. Resolver cada ruta a un item existente es de
/// quien llama, que es quien tiene el catálogo cargado.</para>
/// </summary>
public static class PlaylistImporter
{
    /// <summary>
    /// Las rutas referenciadas, en el orden del archivo. Ignora comentarios
    /// (<c>#EXTM3U</c>, <c>#EXTINF…</c>) y líneas vacías.
    ///
    /// <para>Las rutas relativas —frecuentes en listas exportadas por otros
    /// programas— se resuelven contra la carpeta donde vive el propio archivo,
    /// igual que hace cualquier reproductor al abrirlo.</para>
    /// </summary>
    public static IReadOnlyList<string> ParseTrackPaths(string contents, string playlistDirectory)
    {
        var paths = new List<string>();

        // Se parte por "\n" y se recorta: un M3U escrito en Windows trae "\r\n"
        // y uno escrito en Mac o por el firmware trae solo "\n".
        foreach (string rawLine in contents.Split('\n'))
        {
            string line = rawLine.Trim();
            if (line.Length == 0 || line.StartsWith('#')) continue;
            paths.Add(Resolve(line, playlistDirectory));
        }

        return paths;
    }

    private static string Resolve(string line, string playlistDirectory)
    {
        // Una lista escrita para el iPod trae rutas UNIX absolutas
        // (`/Music/...`). No son rutas de esta PC: se dejan como están y quien
        // llama decide si alguna corresponde a un item de su catálogo.
        if (line.StartsWith('/')) return line;

        if (Uri.TryCreate(line, UriKind.Absolute, out Uri? uri) && uri.IsFile)
            return uri.LocalPath;

        // Ya absoluta en Windows (`C:\…`, `\\servidor\…`).
        if (Path.IsPathRooted(line)) return line;

        try
        {
            return Path.GetFullPath(Path.Combine(playlistDirectory, line));
        }
        catch (ArgumentException)
        {
            // Una línea con caracteres imposibles en una ruta se conserva tal
            // cual: quien llama no la va a encontrar en el catálogo y la
            // reportará como pista faltante, que es lo correcto — mejor que
            // desaparecer en silencio.
            return line;
        }
    }

    /// <summary>Nombre sugerido: el del archivo sin extensión.</summary>
    public static string SuggestedName(string filePath) =>
        Path.GetFileNameWithoutExtension(filePath);
}
