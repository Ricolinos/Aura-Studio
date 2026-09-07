using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using AuraStudio.App.ViewModels;

namespace AuraStudio.App.Views;

/// <summary>
/// Revisión de elementos parecidos (ST-063). Port de <c>SimilarItemsView.swift</c>.
///
/// <para>Cada acción del usuario es explícita y reversible salvo una: quitar
/// de la biblioteca. Esa <b>sí</b> puede borrar archivos —en modo copia van a
/// la Papelera de reciclaje— y por eso pasa por el mismo diálogo de
/// confirmación que las otras pantallas (ST-245, addendum). El comentario que
/// había acá decía lo contrario, y esa creencia es exactamente la que dejó
/// esta pantalla eliminando sin preguntar y avisando después algo que en modo
/// copia era falso.</para>
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
    ///
    /// <para>Pasa por <see cref="DeleteConfirmation"/>, el mismo camino que
    /// Canciones, la cuadrícula y Artistas (ST-245, addendum). Esta pantalla era
    /// la única que eliminaba sin preguntar, y "Conservar solo este" no dice en
    /// ningún lado que a los otros dos del grupo se los lleve la Papelera.</para>
    /// </summary>
    private async void KeepOnly_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: Guid keepId }) return;

        SimilarGroupRow? group = ViewModel.Groups
            .FirstOrDefault(row => row.Members.Any(member => member.Id == keepId));

        if (group is null) return;

        IReadOnlyList<Guid> doomed = ViewModel.IdsToRemoveKeeping(group.Id, keepId);
        if (doomed.Count == 0) return;

        if (await DeleteConfirmation.ConfirmAndRemoveAsync(XamlRoot, ViewModel.Library, doomed))
            ViewModel.ConfirmKeptOnly(group.Id, doomed.Count);
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
