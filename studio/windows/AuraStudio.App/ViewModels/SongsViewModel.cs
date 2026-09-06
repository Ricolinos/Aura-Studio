using CommunityToolkit.Mvvm.ComponentModel;
using AuraStudio.App.Resources;
using AuraStudio.Core.Library;

namespace AuraStudio.App.ViewModels;

/// <summary>
/// Una celda ya resuelta: el texto, el ancho de su columna y si es la de
/// Favorito —que se dibuja con un corazón, no con letras—.
/// </summary>
public sealed record SongCell(MusicTableColumn Column, string Text, double Width, bool IsFavorite)
{
    public bool IsFavoriteColumn => Column == MusicTableColumn.Favorite;

    /// <summary>Corazón lleno o vacío; el texto va aparte para que se pueda leer con lector de pantalla.</summary>
    public string FavoriteGlyph => IsFavorite ? Glyphs.HeartFilled : Glyphs.HeartOutline;

    public string FavoriteLabel => IsFavorite ? "Favorito" : "No es favorito";
}

/// <summary>Un renglón de la tabla, con sus celdas ya armadas para las columnas visibles.</summary>
public sealed record SongRowViewModel(MediaTableRow Row, IReadOnlyList<SongCell> Cells)
{
    public Guid Id => Row.Id;
    public string Title => Row.Title;
    public string SourcePath => Row.Item.SourcePath;

    /// <summary>Lo que lee un lector de pantalla: el renglón entero, no celda por celda.</summary>
    public string AccessibleName =>
        string.Join(", ", new[] { Title }.Concat(
            Cells.Where(cell => !cell.IsFavoriteColumn && cell.Text.Length > 0)
                 .Select(cell => $"{cell.Column.HeaderTitle()}: {cell.Text}")));
}

/// <summary>Un encabezado de columna: su rótulo, su ancho y si es por el que se está ordenando.</summary>
public sealed record SongHeader(MusicTableColumn Column, string Title, double Width, bool IsSorted, bool Ascending)
{
    /// <summary>Flecha del criterio activo; vacío en las demás columnas.</summary>
    public string SortGlyph => !IsSorted ? "" : Ascending ? Glyphs.ChevronUp : Glyphs.ChevronDown;

    /// <summary>
    /// La columna de Favorito es angosta a propósito (34 px, igual que macOS),
    /// y ahí "Favorito" no cabe: se corta en "Favor", que se lee como otra cosa.
    /// Se muestra el corazón y el nombre completo queda para el lector de
    /// pantalla.
    /// </summary>
    public bool ShowsGlyph => Column == MusicTableColumn.Favorite;

    public string Glyph => ShowsGlyph ? Glyphs.HeartFilled : "";
}

/// <summary>
/// La tabla de Canciones (ST-030). Arma los renglones a partir de las columnas
/// que el usuario dejó visibles — <b>no hay tope de columnas</b>, que es
/// justamente el punto de esa decisión.
/// </summary>
public sealed partial class SongsViewModel : ViewModelBase
{
    private readonly LibraryViewModel _library;
    private MusicScope _scope = new MusicScope.All();

    [ObservableProperty]
    public partial IReadOnlyList<SongHeader> Headers { get; private set; }

    [ObservableProperty]
    public partial IReadOnlyList<SongRowViewModel> Rows { get; private set; }

    [ObservableProperty]
    public partial string Title { get; private set; }

    [ObservableProperty]
    public partial string Subtitle { get; private set; }

    public SongsViewModel(LibraryViewModel library)
    {
        _library = library;
        _library.PropertyChanged += OnLibraryChanged;
        Headers = [];
        Rows = [];
        Title = AppStrings.NavSongs;
        Subtitle = "";
        Refresh();
    }

    /// <summary>
    /// La tabla se rehace cuando cambia el <b>contenido</b> de la biblioteca, no
    /// ante cualquier aviso suyo. Es lo que le faltaba a ST-161 acá (ST-201).
    ///
    /// <para>Escucharlos todos era el trabón: cada clic en una tarjeta de Álbumes
    /// publica la selección, publicar avisa, y ese aviso rearmaba la tabla de
    /// 12 000 renglones —con un <c>FileInfo</c> por fila, por red— aunque la
    /// tabla ni siquiera estuviera en pantalla. Al tercer álbum la app quedaba
    /// colgada.</para>
    /// </summary>
    private void OnLibraryChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e)
    {
        if (ChangesLibraryContent(e.PropertyName)) Refresh();
    }

    /// <summary>
    /// Nombre vacío o <c>null</c> significa "cambió todo" en
    /// <c>INotifyPropertyChanged</c>: eso sí obliga a rehacer. Mismo criterio que
    /// <c>MediaGridViewModel</c>, y a propósito: dos reglas distintas para "esto
    /// me obliga a rearmar" es cómo se desincronizan dos vistas del mismo dato.
    /// </summary>
    private static bool ChangesLibraryContent(string? propertyName) =>
        string.IsNullOrEmpty(propertyName)
        || propertyName == nameof(LibraryViewModel.Items)
        || propertyName == nameof(LibraryViewModel.AvailableItems);

    public LibraryViewModel Library => _library;

    /// <summary>El ancho de la columna fija de Título, que siempre va primero.</summary>
    public double TitleWidth => 260;

    /// <summary>Separación entre columnas; la misma en el encabezado y en la fila.</summary>
    public const double ColumnSpacing = 12;

    /// <summary>
    /// El ancho que ocupan todas las columnas juntas. Lo necesita el
    /// desplazamiento horizontal: <b>el encabezado y las filas tienen que
    /// moverse juntos</b>, así que van dentro del mismo contenedor y ese
    /// contenedor necesita un ancho explícito — si se estira al de la ventana,
    /// las últimas columnas quedan cortadas sin manera de llegar a ellas.
    /// </summary>
    public double TotalWidth =>
        TitleWidth
        + Headers.Sum(header => header.Width + ColumnSpacing)
        + ColumnSpacing * 2;

    public string TitleHeader => "Título";

    public bool TitleIsSorted => _library.SortField.Column is null;

    public string TitleSortGlyph =>
        !TitleIsSorted ? "" : _library.SortAscending ? Glyphs.ChevronUp : Glyphs.ChevronDown;

    public bool FavoritesOnly
    {
        get => _library.FavoritesOnly;
        set { _library.FavoritesOnly = value; Refresh(); }
    }

    public IReadOnlyList<MusicTableColumn> AllColumns => MusicTableColumns.All;

    public bool IsVisible(MusicTableColumn column) => _library.VisibleColumns.Contains(column);

    /// <summary>
    /// Prender o apagar una columna. Al prenderla se agrega <b>al final</b> del
    /// orden actual: reordenar la lista entera porque el usuario activó una
    /// columna le movería de lugar las que ya tenía.
    /// </summary>
    public void SetVisible(MusicTableColumn column, bool visible)
    {
        List<MusicTableColumn> columns = [.. _library.VisibleColumns];

        if (visible && !columns.Contains(column)) columns.Add(column);
        else if (!visible) columns.Remove(column);
        else return;

        _library.VisibleColumns = columns;
        Refresh();
    }

    /// <summary>
    /// Ordenar por una columna. Volver a elegir la misma invierte el sentido,
    /// como cualquier tabla; elegir otra empieza ascendente.
    /// </summary>
    public void SortBy(MusicSortField field)
    {
        if (_library.SortField == field) _library.SortAscending = !_library.SortAscending;
        else
        {
            _library.SortField = field;
            _library.SortAscending = true;
        }

        Refresh();
    }

    public void SetScope(MusicScope scope, string title, string subtitle)
    {
        _scope = scope;
        Title = title;
        Subtitle = subtitle;
        Refresh();
    }

    public void ToggleFavorite(Guid id)
    {
        _library.ToggleFavorite(id);
        Refresh();
    }

    public void Refresh()
    {
        IReadOnlyList<MusicTableColumn> columns = _library.VisibleColumns;
        MusicSortField sortField = _library.SortField;

        Headers =
        [
            .. columns.Select(column => new SongHeader(
                column, column.HeaderTitle(), column.IdealWidth(),
                sortField.Column == column, _library.SortAscending))
        ];

        Rows =
        [
            .. _library.Rows(_scope).Select(row => new SongRowViewModel(row,
                [.. columns.Select(column => new SongCell(
                    column, row.CellText(column), column.IdealWidth(),
                    column == MusicTableColumn.Favorite && row.IsFavorite))]))
        ];

        OnPropertyChanged(nameof(TitleIsSorted));
        OnPropertyChanged(nameof(TitleSortGlyph));
        OnPropertyChanged(nameof(FavoritesOnly));
        OnPropertyChanged(nameof(IsEmpty));
        OnPropertyChanged(nameof(EmptyMessage));
        OnPropertyChanged(nameof(CountText));
        OnPropertyChanged(nameof(TotalWidth));
    }

    public bool IsEmpty => Rows.Count == 0;

    /// <summary>
    /// Vacío por no tener nada y vacío por el filtro no son lo mismo: si el
    /// usuario dejó "Solo favoritos" prendido y no ve nada, hay que decírselo o
    /// va a creer que perdió su música.
    /// </summary>
    public string EmptyMessage =>
        FavoritesOnly && _library.Items.Any(item => item.Kind == LibraryItemKind.Music)
            ? "Ninguna canción está marcada como favorita. Quita el filtro para verlas todas."
            : AppStrings.LibraryDropHint(LibraryItemKind.Music);

    public string CountText => AppStrings.LibraryTracks(Rows.Count);
}
