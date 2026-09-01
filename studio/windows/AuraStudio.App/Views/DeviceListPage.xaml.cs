using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.UI;
using AuraStudio.Core;
using AuraStudio.App.ViewModels;

namespace AuraStudio.App.Views;

/// <summary>
/// Vista "General" del iPod conectado: su estado, lo que ocupa, y —desde
/// R3-2— la sincronización, que dejó de ser una sección aparte para vivir
/// junto a los datos con los que uno decide sincronizar (igual que la
/// <c>DeviceActivityBar</c> de macOS dentro de General).
///
/// <para>Sin lógica propia: los dos ViewModels vienen por DI, que es lo único
/// que XAML no puede construir por sí mismo. Lo único que hace el
/// code-behind es abrir la hoja de huérfanos, porque un diálogo necesita el
/// <c>XamlRoot</c> de la página.</para>
/// </summary>
public sealed partial class DeviceListPage : Page
{
    public DeviceListViewModel ViewModel { get; }

    /// <summary>La misma instancia que usa el resto de la app: es singleton.</summary>
    public SyncViewModel Sync { get; }

    public DeviceListPage()
    {
        InitializeComponent();
        ViewModel = App.Services.GetRequiredService<DeviceListViewModel>();
        Sync = App.Services.GetRequiredService<SyncViewModel>();

        ViewModel.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName is nameof(DeviceListViewModel.StorageSegments)
                              or nameof(DeviceListViewModel.Device))
            {
                RebuildStorageBar();
            }
        };

        Loaded += (_, _) => RebuildStorageBar();
    }

    // MARK: - La barra de capacidad (R3-3)

    /// <summary>
    /// Los colores de cada tramo. Viven en la vista y no en Core a propósito:
    /// Core dice cuánto ocupa cada cosa; con qué color se pinta es del tema.
    /// </summary>
    private static Brush BrushFor(string label) => label switch
    {
        StorageBreakdown.Music => (Brush)Application.Current.Resources["AccentFillColorDefaultBrush"],
        StorageBreakdown.Video => new SolidColorBrush(Color.FromArgb(255, 0x8E, 0x7C, 0xC3)),
        StorageBreakdown.Photos => new SolidColorBrush(Color.FromArgb(255, 0x4C, 0xA6, 0x8A)),
        StorageBreakdown.Other => new SolidColorBrush(Color.FromArgb(255, 0x9A, 0x9A, 0x9A)),
        _ => (Brush)Application.Current.Resources["ControlAltFillColorSecondaryBrush"]
    };

    /// <summary>
    /// Dibuja la barra segmentada y su leyenda.
    ///
    /// <para>Va en código y no en XAML porque los anchos son <b>proporcionales
    /// a los bytes</b>, y eso no se expresa con un enlace: cada tramo es una
    /// columna con ancho estrella igual a su fracción. Los tramos vacíos no se
    /// agregan — una columna de ancho cero igual dibuja su separación.</para>
    ///
    /// <para>"Libre" no lleva entrada en la leyenda: es el resto implícito de
    /// la barra, mismo criterio que la barra del firmware (D-282).</para>
    /// </summary>
    private void RebuildStorageBar()
    {
        StorageBar.ColumnDefinitions.Clear();
        StorageBar.Children.Clear();
        StorageLegend.Children.Clear();

        if (ViewModel.Device is not { } device) return;

        foreach (StorageSegment segment in ViewModel.StorageSegments)
        {
            double fraction = StorageBreakdown.Fraction(segment, device);
            if (fraction <= 0) continue;

            StorageBar.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(fraction, GridUnitType.Star) });

            var block = new Border { Background = BrushFor(segment.Label) };
            Grid.SetColumn(block, StorageBar.ColumnDefinitions.Count - 1);
            StorageBar.Children.Add(block);
        }

        foreach (StorageSegment segment in ViewModel.StorageLegend)
        {
            StorageLegend.Children.Add(new StackPanel
            {
                Orientation = Orientation.Horizontal,
                Spacing = 5,
                VerticalAlignment = VerticalAlignment.Center,
                Children =
                {
                    new Border
                    {
                        Width = 8,
                        Height = 8,
                        CornerRadius = new CornerRadius(4),
                        Background = BrushFor(segment.Label),
                        VerticalAlignment = VerticalAlignment.Center
                    },
                    new TextBlock
                    {
                        Text = segment.Label,
                        Style = (Style)Application.Current.Resources["AuraCaptionTextStyle"]
                    }
                }
            });
        }
    }

    /// <summary>
    /// La hoja de lo que quedó en el iPod y ya no está en la biblioteca.
    ///
    /// <para>Es lo <b>único</b> que Studio podría borrar del aparato, y borrar
    /// es lo único que no se deshace: por eso va en una hoja aparte, con una
    /// casilla por archivo, y <b>nada se marca solo</b>. Lo que no se marque se
    /// queda donde está.</para>
    /// </summary>
    private async void Orphans_Click(object sender, RoutedEventArgs e)
    {
        var list = new ListView
        {
            ItemsSource = Sync.Orphans,
            SelectionMode = ListViewSelectionMode.None,
            MaxHeight = 320,
            ItemTemplate = (DataTemplate)Resources["OrphanTemplate"]
        };

        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = Sync.OrphanHeader,
            Content = new StackPanel
            {
                Spacing = 10,
                Children =
                {
                    new TextBlock
                    {
                        Text = "Se quedan en el iPod. Marca los que quieras quitar y vuelve a sincronizar; " +
                               "los demás no se tocan.",
                        TextWrapping = TextWrapping.Wrap
                    },
                    list
                }
            },
            CloseButtonText = "Listo"
        };

        await dialog.ShowAsync();
    }
}
