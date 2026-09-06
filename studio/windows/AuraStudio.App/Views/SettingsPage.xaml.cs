using System.Diagnostics;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Animation;
using AuraStudio.App.Platform;
using AuraStudio.App.ViewModels;
using AuraStudio.Core.Library;

namespace AuraStudio.App.Views;

/// <summary>
/// Ajustes de la app, con las mismas seis pestañas que macOS: General,
/// Biblioteca, Música, Fotos, Video y Servicios.
///
/// <para><b>Ojo con la distinción</b>: los ajustes del <i>firmware</i> (tema del
/// iPod, animaciones, ecualizador) viven en el iPod y se cambian ahí. Acá está
/// solo lo que le toca decidir a Studio.</para>
///
/// <para>Las filas de claves se arman en código porque salen de
/// <c>ApiKeyService</c>: declararlas a mano en XAML sería una segunda lista que
/// se desincroniza sola.</para>
/// </summary>
public sealed partial class SettingsPage : Page
{
    public SettingsViewModel ViewModel { get; }

    public SettingsPage()
    {
        InitializeComponent();
        ViewModel = App.Services.GetRequiredService<SettingsViewModel>();
        Loaded += SettingsPage_Loaded;
    }

    private void SettingsPage_Loaded(object sender, RoutedEventArgs e)
    {
        BuildKeyRows();
        ViewModel.RefreshCoverProviders();
    }

    // MARK: - Pestañas

    private void Tabs_SelectionChanged(SelectorBar sender, SelectorBarSelectionChangedEventArgs args)
    {
        string tag = sender.SelectedItem?.Tag as string ?? "general";

        GeneralPanel.Visibility = Show(tag == "general");
        LibraryPanel.Visibility = Show(tag == "library");
        MusicPanel.Visibility = Show(tag == "music");
        PhotosPanel.Visibility = Show(tag == "photos");
        VideoPanel.Visibility = Show(tag == "video");
        ServicesPanel.Visibility = Show(tag == "services");
    }

    private static Visibility Show(bool visible) => visible ? Visibility.Visible : Visibility.Collapsed;

    private void OpenLicenses_Click(object sender, RoutedEventArgs e)
        => Frame.Navigate(typeof(LicensesPage), null, new DrillInNavigationTransitionInfo());

    /// <summary>
    /// "Buscar actualizaciones" de la app (ST-211). Ignora el intervalo de 24 h:
    /// una revisión que el usuario pide a mano tiene que preguntar de verdad.
    /// </summary>
    private async void CheckAppUpdates_Click(object sender, RoutedEventArgs e) =>
        await ViewModel.Updates.CheckNowAsync();

    // MARK: - Biblioteca

    /// <summary>
    /// ST-171: con el disco de la biblioteca desconectado esto era un segundo
    /// diálogo de "Algo salió mal" esperando — <c>CreateDirectory</c> sobre una
    /// unidad que no está lanza igual que en el arranque. Y con la unidad
    /// presente pero la carpeta borrada, la creaba: el Explorador abría una
    /// carpeta vacía recién inventada como si fuera la biblioteca del usuario.
    ///
    /// <para>Ahora solo se crea si el volumen está montado —el caso legítimo de
    /// una biblioteca nueva que todavía no tiene carpeta— y si aun así no se
    /// puede abrir, no pasa nada: la pantalla ya dice dónde está y que no está.</para>
    /// </summary>
    private void OpenLibraryFolder_Click(object sender, RoutedEventArgs e)
    {
        string root = ViewModel.LibraryPath;
        if (!LibraryRoot.VolumeIsMounted(root)) return;

        try
        {
            Directory.CreateDirectory(root);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return;
        }

        FilePickers.OpenFolder(root);
    }

    private async void ChangeLibraryFolder_Click(object sender, RoutedEventArgs e)
    {
        string? folder = await FilePickers.PickFolderAsync();
        if (folder is not null) ViewModel.SetLibraryPath(folder);
    }

    /// <summary>
    /// Agrega una excepción de agrupación (R2-4) y vacía la caja: dejar el
    /// texto adentro después de agregar invita a agregarlo dos veces.
    /// </summary>
    private void AddArtistException_Click(object sender, RoutedEventArgs e)
    {
        ViewModel.AddArtistGroupingException(ArtistExceptionBox.Text);
        ArtistExceptionBox.Text = "";
    }

    private void RemoveArtistException_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: string name }) ViewModel.RemoveArtistGroupingException(name);
    }

    private void RemoveLinkedFolder_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: string path }) ViewModel.RemoveLinkedFolder(path);
    }

    // MARK: - Video

    private async void ChooseFfmpeg_Click(object sender, RoutedEventArgs e)
    {
        IReadOnlyList<string> chosen = await FilePickers.PickFilesAsync([".exe"]);
        if (chosen.Count > 0) ViewModel.SetFfmpegPath(chosen[0]);
    }

    private void ClearFfmpeg_Click(object sender, RoutedEventArgs e) => ViewModel.SetFfmpegPath("");

    // MARK: - Fotos

    private void AddCollection_Click(object sender, RoutedEventArgs e)
    {
        ViewModel.AddPhotoCollection(NewCollectionBox.Text);
        NewCollectionBox.Text = "";
    }

    private void RemoveCollection_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: string name }) ViewModel.RemovePhotoCollection(name);
    }

    // MARK: - Servicios

    private void MoveProviderUp_Click(object sender, RoutedEventArgs e) => MoveProvider(sender, -1);

    private void MoveProviderDown_Click(object sender, RoutedEventArgs e) => MoveProvider(sender, 1);

    private void MoveProvider(object sender, int offset)
    {
        if (sender is Button { Tag: CoverArtProvider provider })
            ViewModel.MoveCoverProvider(provider, offset);
    }

    /// <summary>
    /// Una fila por servicio con clave. <b>Ningún botón queda gris sin
    /// explicación</b> (ST-053): "Guardar" y "Quitar" responden siempre y dicen
    /// en pantalla qué pasó.
    /// </summary>
    private void BuildKeyRows()
    {
        KeyRows.Children.Clear();

        foreach (ApiKeyService service in ViewModel.KeyServices)
        {
            KeyRows.Children.Add(BuildKeyRow(service));
        }
    }

    private Border BuildKeyRow(ApiKeyService service)
    {
        var status = new TextBlock
        {
            Style = (Style)Application.Current.Resources["AuraCaptionTextStyle"],
            TextWrapping = TextWrapping.Wrap,
            Text = ViewModel.HasKey(service)
                ? "Guardada en el Administrador de credenciales."
                : "Sin configurar."
        };

        var input = new PasswordBox
        {
            PlaceholderText = ViewModel.HasKey(service) ? "Ya hay una guardada" : "Pega la clave aquí",
            MinWidth = 260
        };

        var save = new Button { Content = "Guardar" };
        save.Click += (_, _) =>
        {
            status.Text = ViewModel.SaveKey(service, input.Password);
            input.Password = "";
            input.PlaceholderText = ViewModel.HasKey(service) ? "Ya hay una guardada" : "Pega la clave aquí";
        };

        var remove = new Button { Content = "Quitar" };
        remove.Click += (_, _) =>
        {
            status.Text = ViewModel.DeleteKey(service);
            input.Password = "";
            input.PlaceholderText = "Pega la clave aquí";
        };

        var open = new HyperlinkButton { Content = "Conseguir la clave", NavigateUri = new Uri(service.Url) };

        var controls = new Grid { ColumnSpacing = 8, Margin = new Thickness(0, 8, 0, 0) };
        controls.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        controls.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        controls.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        controls.Children.Add(input);
        Grid.SetColumn(save, 1);
        controls.Children.Add(save);
        Grid.SetColumn(remove, 2);
        controls.Children.Add(remove);

        var content = new StackPanel { Spacing = 4 };
        content.Children.Add(new TextBlock
        {
            Text = service.DisplayName,
            Style = (Style)Application.Current.Resources["AuraSectionTitleTextStyle"]
        });
        content.Children.Add(new TextBlock
        {
            Text = service.Summary,
            Style = (Style)Application.Current.Resources["AuraCaptionTextStyle"],
            TextWrapping = TextWrapping.Wrap
        });
        content.Children.Add(new TextBlock
        {
            Text = service.Guide,
            Style = (Style)Application.Current.Resources["AuraCaptionTextStyle"],
            TextWrapping = TextWrapping.Wrap
        });
        content.Children.Add(open);
        content.Children.Add(controls);
        content.Children.Add(status);

        return new Border
        {
            Style = (Style)Application.Current.Resources["AuraCardStyle"],
            Child = content
        };
    }
}
