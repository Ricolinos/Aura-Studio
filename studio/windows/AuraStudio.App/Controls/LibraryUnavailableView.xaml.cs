using AuraStudio.App.Services;
using AuraStudio.App.ViewModels;
using AuraStudio.App.Views;
using AuraStudio.Core.Library;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace AuraStudio.App.Controls;

/// <summary>Ver <c>LibraryUnavailableView.xaml</c>.</summary>
public sealed partial class LibraryUnavailableView : UserControl
{
    public static readonly DependencyProperty LibraryProperty = DependencyProperty.Register(
        nameof(Library), typeof(LibraryViewModel), typeof(LibraryUnavailableView),
        new PropertyMetadata(null));

    public LibraryViewModel? Library
    {
        get => (LibraryViewModel?)GetValue(LibraryProperty);
        set => SetValue(LibraryProperty, value);
    }

    public LibraryUnavailableView() => InitializeComponent();

    /// <summary>
    /// Volver a mirar ahora mismo. La app ya lo hace sola cada pocos segundos
    /// mientras la biblioteca falta; el botón existe para quien acaba de
    /// conectar el disco y no quiere esperar.
    /// </summary>
    private void Retry_Click(object sender, RoutedEventArgs e) => Library?.Reload();

    /// <summary>El mismo selector de carpeta que usa Ajustes › Biblioteca.</summary>
    private async void Choose_Click(object sender, RoutedEventArgs e)
    {
        string? folder = await FilePickers.PickFolderAsync();
        if (folder is null) return;

        App.Services.GetRequiredService<IAppPreferences>().LibraryPath = folder;
        Library?.Reload();
    }

    /// <summary>
    /// Empezar una biblioteca nueva en la carpeta de siempre
    /// (<c>Documentos\Aura Studio</c>), sin selector: quien aprieta esto no
    /// quiere elegir nada, quiere seguir trabajando ya.
    ///
    /// <para><b>No borra ni mueve nada.</b> La biblioteca del disco que falta
    /// queda intacta donde está y vuelve con solo volver a elegirla, igual que
    /// promete Ajustes › Biblioteca. Y si en esa carpeta ya había una, se abre
    /// esa: crear no puede significar perder.</para>
    /// </summary>
    private void Create_Click(object sender, RoutedEventArgs e)
    {
        string root = LibraryStore.DefaultRoot;

        try
        {
            Directory.CreateDirectory(root);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            // Si ni la carpeta de Documentos se puede crear, no hay nada mejor
            // que ofrecer que el selector.
            Choose_Click(sender, e);
            return;
        }

        App.Services.GetRequiredService<IAppPreferences>().LibraryPath = root;
        Library?.Reload();
    }
}
