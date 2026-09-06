using System.Net.Http;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using AuraStudio.App.Platform;
using AuraStudio.App.ViewModels;
using AuraStudio.Core.Networking;
using Windows.Graphics.Imaging;

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
///
/// <para><b>La cola</b> (addendum de ST-206): cuando un lote deja varios álbumes
/// sin una opción segura, se revisan de a uno en la <b>misma</b> hoja, que dice
/// dónde está parada ("Álbum 2 de 7") y ofrece saltear ese o cortar el resto.
/// Encadenar hojas sin decir eso es lo que R2-3 había descartado, con razón.</para>
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
            Title = TitleFor(albumTitle, position: 0, total: 0),
            Content = Searching(),
            CloseButtonText = "Cancelar"
        };

        Task<ContentDialogResult> showing = dialog.ShowAsync().AsTask();

        IReadOnlyList<AlbumCoverCandidate> candidates =
            await CandidatesAsync(albumTitle, artist, facts, deezerEnabled);

        if (candidates.Count == 0)
        {
            // Sin resultados se explica en pantalla: no se cierra sola ni deja
            // la tapa vieja sin decir por qué.
            dialog.Content = NoResults(deezerEnabled);

            await showing;
            return null;
        }

        GridView chooser = await ChooserAsync(candidates);

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

    /// <summary>
    /// Revisa <b>de a uno</b> los álbumes que un lote dejó sin una opción segura,
    /// sin cerrar la hoja entre uno y otro (addendum de ST-206).
    ///
    /// <para>La hoja dice dónde está parada la revisión y ofrece las tres cosas
    /// que hacen que una cola se pueda usar: elegir, <b>omitir este álbum</b> y
    /// <b>cancelar el resto</b>. Cancelar no deshace lo ya aplicado —cada álbum
    /// es una operación terminada en sí misma— sino que deja de preguntar.</para>
    ///
    /// <para>"Usar recomendada" no está acá a propósito: la recomendada viene
    /// preseleccionada, así que "Usar esta" ya es ese botón. Cuatro acciones no
    /// entran en una hoja de tres botones, y la que sobra es la que se puede
    /// hacer con un clic de todos modos.</para>
    ///
    /// <para><paramref name="apply"/> se llama por cada álbum que el usuario
    /// resuelve, en el momento: si corta a la mitad, lo elegido hasta ahí ya
    /// está.</para>
    /// </summary>
    /// <returns>Cuántos álbumes quedaron resueltos con una tapa.</returns>
    public static async Task<int> ReviewQueueAsync(
        XamlRoot xamlRoot,
        IReadOnlyList<AlbumCoverJob> jobs,
        bool deezerEnabled,
        Action<AlbumCoverJob, AlbumCoverCandidate> apply)
    {
        if (jobs.Count == 0) return 0;

        int index = 0;
        int applied = 0;

        IReadOnlyList<AlbumCoverCandidate> candidates = [];
        GridView? chooser = null;

        var dialog = new ContentDialog
        {
            XamlRoot = xamlRoot,
            Title = TitleFor(jobs[0].Title, 1, jobs.Count),
            Content = Searching(),
            PrimaryButtonText = "Usar esta",
            SecondaryButtonText = "Omitir este álbum",
            CloseButtonText = "Cancelar el resto",
            DefaultButton = ContentDialogButton.Primary,
            IsPrimaryButtonEnabled = false
        };

        // "Usar esta" y "Omitir" NO cierran la hoja: avanzan. Se cierra sola al
        // terminar la cola, o con "Cancelar el resto".
        dialog.PrimaryButtonClick += (_, args) =>
        {
            args.Cancel = true;

            if (chooser is { SelectedIndex: >= 0 } picked && picked.SelectedIndex < candidates.Count)
            {
                apply(jobs[index], candidates[picked.SelectedIndex]);
                applied++;
            }

            Advance();
        };

        dialog.SecondaryButtonClick += (_, args) =>
        {
            args.Cancel = true;
            Advance();
        };

        Task<ContentDialogResult> showing = dialog.ShowAsync().AsTask();

        await LoadAsync();
        await showing;

        return applied;

        // El avance no se espera desde el manejador: el manejador tiene que
        // volver ya para que la hoja no se cierre, y buscar las tapas del
        // siguiente álbum tarda lo que tarde la red.
        async void Advance()
        {
            index++;

            if (index >= jobs.Count)
            {
                dialog.Hide();
                return;
            }

            await LoadAsync();
        }

        async Task LoadAsync()
        {
            AlbumCoverJob job = jobs[index];

            chooser = null;
            candidates = [];
            dialog.Title = TitleFor(job.Title, index + 1, jobs.Count);
            dialog.Content = Searching();
            dialog.IsPrimaryButtonEnabled = false;

            IReadOnlyList<AlbumCoverCandidate> found =
                await CandidatesAsync(job.Title, job.Artist, job.Facts, deezerEnabled);

            // El usuario pudo haber avanzado o cortado mientras se buscaba: lo
            // que llega tarde no puede pisar la pantalla del álbum siguiente.
            if (index >= jobs.Count || !ReferenceEquals(jobs[index], job)) return;

            candidates = found;

            if (candidates.Count == 0)
            {
                dialog.Content = NoResults(deezerEnabled);
                return;
            }

            GridView built = await ChooserAsync(candidates);
            if (index >= jobs.Count || !ReferenceEquals(jobs[index], job)) return;

            built.SelectionChanged += (_, _) =>
                dialog.IsPrimaryButtonEnabled = built.SelectedIndex >= 0;

            chooser = built;
            dialog.Content = built;
            dialog.IsPrimaryButtonEnabled = true;
        }
    }

    private static string TitleFor(string albumTitle, int position, int total) =>
        total > 1
            ? $"Álbum {position} de {total} · tapas de \"{albumTitle}\""
            : $"Tapas de \"{albumTitle}\"";

    private static ProgressRing Searching() => new() { IsActive = true, Width = 32, Height = 32 };

    private static TextBlock NoResults(bool deezerEnabled) => new()
    {
        Text = AlbumCoverSearch.NoResultsMessage(deezerEnabled),
        TextWrapping = TextWrapping.Wrap
    };

    private static async Task<IReadOnlyList<AlbumCoverCandidate>> CandidatesAsync(
        string albumTitle, string? artist, AlbumFacts facts, bool deezerEnabled)
    {
        try
        {
            return await new AlbumCoverSearch()
                .CandidatesAsync(albumTitle, artist, deezerEnabled, facts: facts);
        }
        catch (Exception ex) when (ex is HttpRequestException or IOException)
        {
            return [];
        }
    }

    private static async Task<GridView> ChooserAsync(IReadOnlyList<AlbumCoverCandidate> candidates)
    {
        var chooser = new GridView { SelectionMode = ListViewSelectionMode.Single, MaxHeight = 420 };

        for (int index = 0; index < candidates.Count; index++)
            chooser.Items.Add(await TileAsync(candidates[index], isRecommended: index == 0));

        // La lista ya viene ordenada por el mismo criterio con el que se
        // recomienda, así que la recomendada es la primera — y se preselecciona.
        chooser.SelectedIndex = 0;

        return chooser;
    }

    /// <summary>El lado de cada opción: 132 px a 2×.</summary>
    private const int TileSide = 264;

    private static async Task<FrameworkElement> TileAsync(AlbumCoverCandidate candidate, bool isRecommended)
    {
        var image = new Image { Width = 132, Height = 132, Stretch = Stretch.UniformToFill };

        // ST-205: por la caché. Volver a abrir la hoja del mismo álbum no vuelve
        // a decodificar nada, y lo que se decodifica va ya reducido al tamaño de
        // la opción en vez de traerse el original entero.
        SoftwareBitmap? thumbnail =
            await CoverThumbnailCache.Shared.ThumbnailAsync(candidate.Data, TileSide);

        // Una imagen que no se puede decodificar no se ofrece rota: se deja el
        // hueco con su origen escrito debajo.
        image.Source = await CoverThumbnails.SourceAsync(thumbnail);

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
