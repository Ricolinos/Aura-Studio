using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.Storage.Pickers;
using AuraStudio.App.ViewModels;

namespace AuraStudio.App.Views;

/// <summary>
/// Las listas de reproducción: crear, renombrar, eliminar, importar un M3U y
/// exportarlo. Port de <c>PlaylistsView.swift</c>.
///
/// <para>Eliminar una lista <b>no borra sus canciones</b>, y se dice en el
/// aviso posterior — no en un diálogo que el usuario despacha sin leer.</para>
/// </summary>
public sealed partial class PlaylistsPage : Page
{
    public PlaylistsViewModel ViewModel { get; }

    public PlaylistsPage()
    {
        InitializeComponent();
        ViewModel = App.Services.GetRequiredService<PlaylistsViewModel>();
        Loaded += (_, _) => ViewModel.Reload();
    }

    private async void New_Click(object sender, RoutedEventArgs e)
    {
        string? name = await AskForName("Nueva lista", "");
        if (name is not null) ViewModel.Create(name);
    }

    private async void Rename_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: Guid id }) return;

        PlaylistRow? row = ViewModel.Rows.FirstOrDefault(candidate => candidate.Id == id);
        if (row is null) return;

        string? name = await AskForName("Renombrar la lista", row.Name);
        if (name is not null) ViewModel.Rename(id, name);
    }

    private void Delete_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: Guid id }) ViewModel.Delete(id);
    }

    private async void Export_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: Guid id }) return;
        if (ViewModel.Export(id) is not { } export) return;

        var picker = new FileSavePicker { SuggestedFileName = Path.GetFileNameWithoutExtension(export.FileName) };
        picker.FileTypeChoices.Add("Lista de reproducción", [".m3u8"]);
        FilePickers.Attach(picker);

        Windows.Storage.StorageFile? file = await picker.PickSaveFileAsync();
        if (file is null) return;

        try
        {
            // Sin BOM y con saltos UNIX: el archivo lo lee el firmware del iPod,
            // no Windows.
            await File.WriteAllTextAsync(file.Path, export.Contents, new System.Text.UTF8Encoding(false));
            ViewModel.LastMessage = $"Se exportó a {file.Path}.";
        }
        catch (Exception ex)
        {
            ViewModel.LastMessage = $"No se pudo exportar: {ex.Message}";
        }
    }

    private async void Import_Click(object sender, RoutedEventArgs e)
    {
        IReadOnlyList<string> paths = await FilePickers.PickFilesAsync(["m3u", "m3u8"]);
        foreach (string path in paths) ViewModel.Import(path);
    }

    /// <summary>Un cuadro de texto con Aceptar deshabilitado si está vacío.</summary>
    private async Task<string?> AskForName(string title, string current)
    {
        var box = new TextBox { Text = current, PlaceholderText = "Nombre de la lista" };

        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = title,
            Content = box,
            PrimaryButtonText = "Aceptar",
            CloseButtonText = "Cancelar",
            DefaultButton = ContentDialogButton.Primary,
            IsPrimaryButtonEnabled = current.Trim().Length > 0
        };

        box.TextChanged += (_, _) => dialog.IsPrimaryButtonEnabled = box.Text.Trim().Length > 0;

        return await dialog.ShowAsync() == ContentDialogResult.Primary ? box.Text : null;
    }
}
