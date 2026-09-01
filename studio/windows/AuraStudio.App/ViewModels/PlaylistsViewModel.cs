using CommunityToolkit.Mvvm.ComponentModel;
using AuraStudio.Core.Library;

namespace AuraStudio.App.ViewModels;

/// <summary>Una lista en pantalla, con lo que se ve en su fila.</summary>
public sealed record PlaylistRow(Playlist Playlist, int TrackCount, int MissingCount)
{
    public Guid Id => Playlist.Id;
    public string Name => Playlist.Name;

    public string Detail
    {
        get
        {
            string tracks = TrackCount == 1 ? "1 canción" : $"{TrackCount} canciones";

            // Una lista importada de otro programa suele traer pistas que no
            // están en la biblioteca. Decirlo evita que el usuario crea que la
            // importación falló.
            return MissingCount == 0
                ? tracks
                : $"{tracks} · faltan {MissingCount} que no están en tu biblioteca";
        }
    }
}

/// <summary>
/// Las listas de reproducción. Se arman con canciones que ya están en la
/// biblioteca; las rutas reales del iPod se resuelven recién al sincronizar.
/// </summary>
public sealed partial class PlaylistsViewModel : ViewModelBase
{
    private readonly LibraryViewModel _library;
    private List<Playlist> _playlists = [];

    [ObservableProperty]
    public partial IReadOnlyList<PlaylistRow> Rows { get; private set; } = [];

    [ObservableProperty]
    public partial string? LastMessage { get; set; }

    public PlaylistsViewModel(LibraryViewModel library)
    {
        _library = library;
        _library.PropertyChanged += (_, _) => Refresh();
        Reload();
    }

    public LibraryViewModel Library => _library;

    public bool IsEmpty => Rows.Count == 0;

    public void Reload()
    {
        _playlists = [.. _library.LoadPlaylists()];
        Refresh();
    }

    public void Refresh()
    {
        var known = _library.Items.Select(item => item.Id).ToHashSet();

        Rows =
        [
            .. _playlists.Select(playlist =>
            {
                int present = playlist.TrackItemIds.Count(known.Contains);
                return new PlaylistRow(playlist, present, playlist.TrackItemIds.Count - present);
            })
        ];

        OnPropertyChanged(nameof(IsEmpty));
    }

    public void Create(string name)
    {
        string trimmed = name.Trim();
        if (trimmed.Length == 0) return;

        _playlists.Add(new Playlist { Name = trimmed });
        Save($"Se creó «{trimmed}».");
    }

    public void Rename(Guid id, string name)
    {
        string trimmed = name.Trim();
        Playlist? playlist = _playlists.FirstOrDefault(candidate => candidate.Id == id);
        if (playlist is null || trimmed.Length == 0) return;

        playlist.Name = trimmed;
        Save($"Se renombró a «{trimmed}».");
    }

    public void Delete(Guid id)
    {
        Playlist? playlist = _playlists.FirstOrDefault(candidate => candidate.Id == id);
        if (playlist is null) return;

        _playlists.Remove(playlist);

        // Se borra la lista, no las canciones: siguen en la biblioteca.
        Save($"Se eliminó «{playlist.Name}». Las canciones siguen en tu biblioteca.");
    }

    /// <summary>
    /// Importa un M3U/M3U8. Las pistas se resuelven contra la biblioteca por
    /// ruta; las que no estén se cuentan y se dicen, en vez de desaparecer.
    /// </summary>
    public void Import(string filePath)
    {
        string directory = Path.GetDirectoryName(filePath) ?? "";
        string contents;

        try
        {
            contents = File.ReadAllText(filePath);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            LastMessage = $"No se pudo leer la lista: {ex.Message}";
            return;
        }

        IReadOnlyList<string> paths = PlaylistImporter.ParseTrackPaths(contents, directory);

        var byPath = new Dictionary<string, Guid>(StringComparer.OrdinalIgnoreCase);
        foreach (LibraryItem item in _library.Items) byPath[item.SourcePath] = item.Id;

        List<Guid> found = [.. paths.Select(path => byPath.TryGetValue(path, out Guid id) ? id : Guid.Empty)
            .Where(id => id != Guid.Empty)];

        int missing = paths.Count - found.Count;

        _playlists.Add(new Playlist
        {
            Name = PlaylistImporter.SuggestedName(filePath),
            TrackItemIds = found
        });

        Save(missing == 0
            ? $"Se importó «{PlaylistImporter.SuggestedName(filePath)}» con {found.Count} canciones."
            : $"Se importó «{PlaylistImporter.SuggestedName(filePath)}» con {found.Count} canciones. Otras {missing} no están en tu biblioteca todavía.");
    }

    /// <summary>
    /// El contenido del <c>.m3u8</c> a exportar y su nombre de archivo. Las
    /// rutas son las de destino en el iPod, que es lo que el firmware sabe leer.
    /// </summary>
    public (string FileName, string Contents)? Export(Guid id)
    {
        Playlist? playlist = _playlists.FirstOrDefault(candidate => candidate.Id == id);
        if (playlist is null) return null;

        var byId = _library.Items.ToDictionary(item => item.Id);

        List<string> destinations =
        [
            .. playlist.TrackItemIds
                .Where(byId.ContainsKey)
                .Select(trackId => "Music/" + Path.GetFileName(byId[trackId].SourcePath))
        ];

        return (PlaylistExporter.FileName(playlist.Name),
                PlaylistExporter.M3u8Contents(destinations));
    }

    private void Save(string message)
    {
        _library.SavePlaylists(_playlists);
        LastMessage = message;
        Refresh();
    }
}
