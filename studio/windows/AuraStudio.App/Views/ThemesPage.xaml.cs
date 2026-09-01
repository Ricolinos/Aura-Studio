using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Navigation;
using AuraStudio.App.ViewModels;
using AuraStudio.Core.Library;

namespace AuraStudio.App.Views;

public sealed partial class ThemesPage : Page
{
    public ThemesViewModel ViewModel { get; }

    public ThemesPage()
    {
        InitializeComponent();
        ViewModel = App.Services.GetRequiredService<ThemesViewModel>();
        DataContext = ViewModel;
    }

    protected override async void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        await ViewModel.RefreshAsync();
    }

    private ThemeRow? RowOf(object sender) =>
        sender is Button { Tag: string id }
            ? ViewModel.Themes.FirstOrDefault(theme => theme.Id == id)
            : null;

    private async void Activate_Click(object sender, RoutedEventArgs e)
    {
        if (RowOf(sender) is { } row) await ViewModel.ActivateCommand.ExecuteAsync(row);
    }

    private async void Remove_Click(object sender, RoutedEventArgs e)
    {
        if (RowOf(sender) is { } row) await ConfirmRemoveAsync(row);
    }

    /// <summary>
    /// Eliminar es lo único que no se puede deshacer: se confirma diciendo qué
    /// tema y qué pasa con el iPod si estaba activo. La misma confirmación
    /// para el botón y para el menú contextual.
    /// </summary>
    private async Task ConfirmRemoveAsync(ThemeRow row)
    {
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = $"¿Quitar \"{row.Name}\" del iPod?",
            Content = row.IsActive
                ? "Es el tema activo: el iPod vuelve al tema integrado de Aura."
                : "Se borra del iPod. Puedes volver a instalarlo si conservas la carpeta de assets.",
            PrimaryButtonText = "Quitar",
            CloseButtonText = "Cancelar",
            DefaultButton = ContentDialogButton.Close
        };

        if (await dialog.ShowAsync() == ContentDialogResult.Primary)
            await ViewModel.RemoveCommand.ExecuteAsync(row);
    }

    /// <summary>
    /// §10 del documento de paridad. Con el tema por omisión el menú queda
    /// <b>vacío</b> —macOS no muestra ninguno—, y por eso acá no se muestra
    /// nada en vez de un menú con un solo ítem deshabilitado.
    /// </summary>
    private void Themes_ContextRequested(UIElement sender, ContextRequestedEventArgs args)
    {
        if (RowFrom(args.OriginalSource) is not { } row) return;

        MenuFlyout? menu = ContextMenuBuilder.Build(
            LibraryContextMenus.ForTheme(row.IsBuiltIn),
            async id => { if (id == "delete") await ConfirmRemoveAsync(row); });

        menu?.ShowAt(sender, new FlyoutShowOptions
        {
            Position = args.TryGetPosition(sender, out var point) ? point : null
        });

        args.Handled = true;
    }

    private static ThemeRow? RowFrom(object? source)
    {
        for (var element = source as FrameworkElement; element is not null; element = element.Parent as FrameworkElement)
        {
            if (element.DataContext is ThemeRow row) return row;
        }

        return null;
    }

    private async void Share_Click(object sender, RoutedEventArgs e)
    {
        if (RowOf(sender) is not { } row) return;

        string? folder = await FilePickers.PickFolderAsync();
        if (folder is not null) await ViewModel.ShareAsync(row, folder);
    }

    private async void ChooseSourceFolder_Click(object sender, RoutedEventArgs e)
    {
        string? folder = await FilePickers.PickFolderAsync();
        if (folder is not null) ViewModel.NewThemeSourceFolder = folder;
    }

    private async void Build_Click(object sender, RoutedEventArgs e) => await ViewModel.BuildAsync();
}
