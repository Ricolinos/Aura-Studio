using System.Net.Http;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using AuraStudio.Core.Networking;
using Windows.Storage.Streams;

namespace AuraStudio.App.Views;

/// <summary>
/// La hoja de tapas de un álbum (ST-104, con la recomendación de R2-3):
/// <b>ofrece, no aplica</b>. Ni siquiera cuando encuentra una sola — dos
/// ediciones de un disco tienen tapas distintas y las dos son correctas.
///
/// <para>Vive aparte de las pantallas porque el documento de paridad (§13.2)
/// pide la misma hoja en <b>tres</b> lugares: el menú de la cuadrícula de
/// Álbumes, el de la tabla de Canciones y el botón de la cabecera del detalle
/// del álbum. Estaba escrita adentro de una sola pantalla, y la cuadrícula de
/// Álbumes ofrecía el ítem sin que hiciera nada.</para>
/// </summary>
internal static class AlbumCoverPicker
{
    /// <summary>
    /// Devuelve la tapa que eligió el usuario, o <c>null</c> si canceló o no
    /// hubo resultados. <b>No escribe nada</b>: aplicarla es de quien llama.
    /// </summary>
    public static async Task<AlbumCoverCandidate?> ShowAsync(
        XamlRoot xamlRoot, string albumTitle, string? artist, AlbumFacts facts, bool deezerEnabled)
    {
        var dialog = new ContentDialog
        {
            XamlRoot = xamlRoot,
            Title = $"Tapas de \"{albumTitle}\"",
            Content = new ProgressRing { IsActive = true, Width = 32, Height = 32 },
            CloseButtonText = "Cancelar"
        };

        Task<ContentDialogResult> showing = dialog.ShowAsync().AsTask();

        IReadOnlyList<AlbumCoverCandidate> candidates;

        try
        {
            candidates = await new AlbumCoverSearch()
                .CandidatesAsync(albumTitle, artist, deezerEnabled, facts: facts);
        }
        catch (Exception ex) when (ex is HttpRequestException or IOException)
        {
            candidates = [];
        }

        if (candidates.Count == 0)
        {
            // Sin resultados se explica en pantalla: no se cierra sola ni deja
            // la tapa vieja sin decir por qué.
            dialog.Content = new TextBlock
            {
                Text = AlbumCoverSearch.NoResultsMessage(deezerEnabled),
                TextWrapping = TextWrapping.Wrap
            };

            await showing;
            return null;
        }

        var chooser = new GridView { SelectionMode = ListViewSelectionMode.Single, MaxHeight = 420 };

        for (int index = 0; index < candidates.Count; index++)
            chooser.Items.Add(await TileAsync(candidates[index], isRecommended: index == 0));

        // La lista ya viene ordenada por el mismo criterio con el que se
        // recomienda, así que la recomendada es la primera — y se preselecciona.
        chooser.SelectedIndex = 0;

        dialog.Content = chooser;
        dialog.PrimaryButtonText = "Usar esta";
        dialog.SecondaryButtonText = "Usar recomendada";
        dialog.DefaultButton = ContentDialogButton.Primary;

        // Se deshabilita, no se esconde: que el botón aparezca y desaparezca
        // según dónde esté la selección es peor que verlo apagado.
        dialog.IsSecondaryButtonEnabled = false;
        chooser.SelectionChanged += (_, _) =>
        {
            dialog.IsPrimaryButtonEnabled = chooser.SelectedIndex >= 0;
            dialog.IsSecondaryButtonEnabled = chooser.SelectedIndex > 0;
        };

        return await showing switch
        {
            ContentDialogResult.Primary => chooser.SelectedIndex >= 0 ? candidates[chooser.SelectedIndex] : null,
            ContentDialogResult.Secondary => candidates[0],
            _ => null
        };
    }

    private static async Task<FrameworkElement> TileAsync(AlbumCoverCandidate candidate, bool isRecommended)
    {
        var image = new Image { Width = 132, Height = 132, Stretch = Stretch.UniformToFill };

        try
        {
            var bitmap = new BitmapImage { DecodePixelWidth = 264 };
            using var stream = new InMemoryRandomAccessStream();

            using (var writer = new DataWriter(stream.GetOutputStreamAt(0)))
            {
                writer.WriteBytes(candidate.Data);
                await writer.StoreAsync();
            }

            await bitmap.SetSourceAsync(stream);
            image.Source = bitmap;
        }
        catch (Exception)
        {
            // Una imagen que no se puede decodificar no se ofrece rota: se deja
            // el hueco con su origen escrito debajo.
        }

        var tile = new StackPanel
        {
            Width = 148,
            Spacing = 4,
            Children =
            {
                image,
                new TextBlock
                {
                    Text = candidate.Detail ?? candidate.SourceName,
                    TextTrimming = TextTrimming.CharacterEllipsis,
                    Style = (Style)Application.Current.Resources["AuraCaptionTextStyle"]
                }
            }
        };

        if (isRecommended)
        {
            tile.Children.Add(new TextBlock
            {
                Text = "Recomendada",
                FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
                Style = (Style)Application.Current.Resources["AuraCaptionTextStyle"]
            });
        }

        return tile;
    }
}
