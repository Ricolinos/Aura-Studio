using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Animation;
using AuraStudio.App.Resources;
using AuraStudio.App.ViewModels;

namespace AuraStudio.App.Views;

/// <summary>
/// Armazón de la app: barra de navegación Fluent y marco de contenido.
///
/// Vive como <c>Page</c> y no dentro de <c>MainWindow.xaml</c> a propósito:
/// <c>Window</c> no es un <c>FrameworkElement</c> (no tiene `DataContext`, ni
/// `RequestedTheme`, ni soporte pleno de `x:Bind`), así que todo lo que sea
/// interfaz vive en páginas y la ventana se queda con lo suyo — respaldo
/// Mica, tamaño/posición, tema y el enganche de WM_DEVICECHANGE.
///
/// El code-behind hace solo glue de navegación (mapear etiqueta → página);
/// la lógica de qué está habilitado y por qué es del <see cref="ShellViewModel"/>.
/// </summary>
public sealed partial class ShellPage : Page
{
    public ShellViewModel ViewModel { get; }

    /// <summary>
    /// Etiquetas de las secciones que dependen de la biblioteca: si se
    /// bloquean mientras una está abierta, la selección salta a General en vez
    /// de dejar una vista que ya no aplica (mismo comportamiento que macOS).
    /// </summary>
    private static readonly string[] LibraryTags =
        ["music", "video", "photos"];

    /// <summary>
    /// El armazón vivo, para que una página de contenido pueda mandar a la app
    /// a otra sección **por la barra lateral** y no por el marco a secas.
    ///
    /// <para>Navegar con <c>Frame.Navigate</c> desde adentro cambia la página
    /// pero deja la barra marcando la sección anterior: el usuario acaba en el
    /// Instalador con «Extras» resaltado. Con esto la selección y el contenido
    /// se mueven juntos, que es lo único que el usuario puede entender.</para>
    /// </summary>
    public static ShellPage? Current { get; private set; }

    public ShellPage()
    {
        InitializeComponent();
        ViewModel = App.Services.GetRequiredService<ShellViewModel>();
        ViewModel.PropertyChanged += OnViewModelPropertyChanged;
        Current = this;
    }

    /// <summary>Va a una sección de la barra lateral por su etiqueta.</summary>
    public void GoToSection(string tag) => SelectTag(tag);

    private void NavView_Loaded(object sender, RoutedEventArgs e)
    {
        // El elemento de Ajustes es del control: se le pone el nombre del repo
        // (macOS lo llama "Ajustes", no "Configuración").
        if (NavView.SettingsItem is NavigationViewItem settings)
        {
            settings.Content = AppStrings.NavSettings;
        }

        SelectTag("general");
    }

    private void OnViewModelPropertyChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e)
    {
        if (e.PropertyName != nameof(ShellViewModel.LibraryEnabled)) return;
        if (ViewModel.LibraryEnabled) return;

        if (NavView.SelectedItem is NavigationViewItem { Tag: string tag } && IsLibraryTag(tag))
        {
            SelectTag("general");
        }
    }

    private static bool IsLibraryTag(string tag) =>
        LibraryTags.Any(prefix => tag == prefix || tag.StartsWith(prefix + ".", StringComparison.Ordinal));

    private void SelectTag(string tag)
    {
        var item = FindItem(NavView.MenuItems, tag) ?? FindItem(NavView.FooterMenuItems, tag);
        if (item is null) return;
        NavView.SelectedItem = item;
        Navigate(tag);
    }

    private static NavigationViewItem? FindItem(IList<object> items, string tag)
    {
        foreach (object candidate in items)
        {
            if (candidate is not NavigationViewItem item) continue;
            if (item.Tag as string == tag) return item;
            if (FindItem(item.MenuItems, tag) is { } nested) return nested;
        }
        return null;
    }

    private void NavView_SelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        if (args.IsSettingsSelected)
        {
            NavigateTo(typeof(SettingsPage), null);
            return;
        }

        if (args.SelectedItemContainer is NavigationViewItem { Tag: string tag })
        {
            Navigate(tag);
        }
    }

    private void Navigate(string tag)
    {
        switch (tag)
        {
            case "general":
                NavigateTo(typeof(DeviceListPage), null);
                return;
            case "installer":
                NavigateTo(typeof(InstallerPage), null);
                return;
            // R4: Extras dejó de ser un marcador de posición.
            case "extras":
                NavigateTo(typeof(ExtrasPage), null);
                return;
            case "extras.themes":
                NavigateTo(typeof(ThemesPage), null);
                return;
            case "music.songs":
                NavigateTo(typeof(SongsPage), null);
                return;

            // R2-6: Artistas dejó de ser una cuadrícula de tarjetas. Tiene su
            // propia pantalla maestro-detalle, como la de macOS.
            case "music.artists":
                NavigateTo(typeof(ArtistsPage), null);
                return;
            case "music.playlists":
                NavigateTo(typeof(PlaylistsPage), null);
                return;
        }

        if (GridRequest(tag) is { } request)
        {
            // Con parámetro siempre se navega: la misma página sirve para
            // Álbumes y para Artistas, y saltarse la navegación por ser "la
            // misma página" dejaría la cuadrícula anterior en pantalla.
            ContentFrame.Navigate(typeof(MediaGridPage), request, new EntranceNavigationTransitionInfo());
            return;
        }

        // R4: ya no queda ninguna sección sin pantalla propia. La página de
        // marcador de posición —y su tipo— se retiraron con Extras: dejar
        // colgando el camino que las usaba invitaba a volver a colgar algo ahí.
    }

    private static MediaGridRequest? GridRequest(string tag) => tag switch
    {
        "music.albums" => new(MediaGridKind.Albums),
        "video.movies" => new(MediaGridKind.Movies),
        "video.series" => new(MediaGridKind.Series),
        "video.clips" => new(MediaGridKind.Clips),
        "video.all" => new(MediaGridKind.AllVideos),
        "photos.photos" => new(MediaGridKind.PhotoCollection, AppStrings.NavPhotosPhotos),
        "photos.images" => new(MediaGridKind.PhotoCollection, AppStrings.NavPhotosImages),
        "photos.ai" => new(MediaGridKind.PhotoCollection, AppStrings.NavPhotosAI),
        "photos.all" => new(MediaGridKind.AllPhotos),
        _ => null
    };

    private void NavigateTo(Type pageType, object? parameter)
    {
        if (ContentFrame.CurrentSourcePageType == pageType && parameter is null) return;
        ContentFrame.Navigate(pageType, parameter, new EntranceNavigationTransitionInfo());
    }
}
