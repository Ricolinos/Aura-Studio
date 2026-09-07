using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using AuraStudio.App.Resources;
using AuraStudio.App.ViewModels;
using AuraStudio.Core.Library;

namespace AuraStudio.App.Views;

/// <summary>
/// El diálogo de "¿Eliminar N elementos?" (ST-245, §0.4 del plan): compartido
/// por las tres pantallas que lo disparan —Canciones, la cuadrícula y
/// Artistas— para que las tres digan exactamente lo mismo, con el mismo
/// texto, en vez de triplicar el diálogo y arriesgar que se desalineen.
/// </summary>
public static class DeleteConfirmation
{
    /// <summary>
    /// Pregunta y, si el usuario confirma, elimina. Devuelve si de verdad
    /// eliminó algo, para que el llamador sepa si le hace falta refrescar.
    /// </summary>
    public static async Task<bool> ConfirmAndRemoveAsync(
        XamlRoot xamlRoot, LibraryViewModel library, IReadOnlyList<Guid> ids)
    {
        if (ids.Count == 0) return false;

        DeletionPreview preview = library.PreviewRemoval(ids);
        if (preview.TotalCount == 0) return false;

        var dialog = new ContentDialog
        {
            XamlRoot = xamlRoot,
            Title = AppStrings.DeleteConfirmTitle(preview.TotalCount),
            Content = new TextBlock
            {
                Text = AppStrings.DeleteConfirmMessage(preview),
                TextWrapping = TextWrapping.Wrap
            },
            PrimaryButtonText = AppStrings.DeleteConfirmPrimary,
            CloseButtonText = AppStrings.DeleteConfirmCancel,
            // Cierra por omisión, no elimina: un Enter sin querer no puede
            // mandar nada a la Papelera.
            DefaultButton = ContentDialogButton.Close
        };

        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return false;

        library.Remove(ids);
        return true;
    }
}
