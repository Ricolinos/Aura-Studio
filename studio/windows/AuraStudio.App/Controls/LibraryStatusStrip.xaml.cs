using AuraStudio.App.ViewModels;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace AuraStudio.App.Controls;

/// <summary>Ver <c>LibraryStatusStrip.xaml</c>.</summary>
public sealed partial class LibraryStatusStrip : UserControl
{
    public static readonly DependencyProperty LibraryProperty = DependencyProperty.Register(
        nameof(Library), typeof(LibraryViewModel), typeof(LibraryStatusStrip), new PropertyMetadata(null));

    public LibraryViewModel? Library
    {
        get => (LibraryViewModel?)GetValue(LibraryProperty);
        set => SetValue(LibraryProperty, value);
    }

    /// <summary>
    /// El centro de tareas de la app (ST-203). Se resuelve acá y no llega como
    /// una propiedad más porque es <b>uno solo</b>: pasárselo a mano desde las
    /// cinco páginas que usan esta franja serían cinco oportunidades de
    /// olvidarse en una.
    /// </summary>
    public Services.BackgroundTaskCenter Tasks { get; } =
        Microsoft.Extensions.DependencyInjection.ServiceProviderServiceExtensions
            .GetRequiredService<Services.BackgroundTaskCenter>(App.Services);

    public LibraryStatusStrip() => InitializeComponent();

    private void CancelTask_Click(object sender, RoutedEventArgs e) => Tasks.Current?.RequestCancel();
}
