using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using AuraStudio.App.ViewModels;

namespace AuraStudio.App.Views;

/// <summary>
/// Revisión de elementos parecidos (ST-063). Port de <c>SimilarItemsView.swift</c>.
///
/// <para>Cada acción del usuario es explícita y reversible salvo una: quitar de
/// la biblioteca. Y ni siquiera esa borra archivos — se dice en el aviso que
/// queda después, no en un diálogo que se despacha sin leer.</para>
/// </summary>
public sealed partial class SimilarItemsPage : Page
{
    public SimilarItemsViewModel ViewModel { get; }

    public SimilarItemsPage()
    {
        InitializeComponent();
        ViewModel = App.Services.GetRequiredService<SimilarItemsViewModel>();
    }

    private async void Scan_Click(object sender, RoutedEventArgs e) => await ViewModel.ScanAsync();

    private async void Restore_Click(object sender, RoutedEventArgs e) => await ViewModel.RestoreIgnoredAsync();

    /// <summary>
    /// El botón vive en la fila del elemento, así que hay que subir al grupo que
    /// lo contiene: es el único que sabe qué otros elementos se quitan.
    /// </summary>
    private void KeepOnly_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: Guid keepId }) return;

        SimilarGroupRow? group = ViewModel.Groups
            .FirstOrDefault(row => row.Members.Any(member => member.Id == keepId));

        if (group is not null) ViewModel.KeepOnly(group.Id, keepId);
    }

    private void ApplyEdits_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: string groupId }) ViewModel.ApplyEdits(groupId);
    }

    private void Ignore_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: string groupId }) ViewModel.Ignore(groupId);
    }
}
