using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;
using AuraStudio.App.ViewModels;

namespace AuraStudio.App.Views;

/// <summary>
/// La sección «Extras» (R4, ST-133), port de <c>ExtrasView.swift</c>.
///
/// <para>Dejó de ser un marcador de posición: es donde se elige qué firmware
/// instala el asistente, y es la entrada a Temas y a Licencias.</para>
/// </summary>
public sealed partial class ExtrasPage : Page
{
    public ExtrasViewModel ViewModel { get; }

    public ExtrasPage()
    {
        InitializeComponent();
        ViewModel = App.Services.GetRequiredService<ExtrasViewModel>();
    }

    /// <summary>
    /// Las versiones se consultan al aparecer la pantalla, no al arrancar la
    /// app: es una llamada de red por familia y solo importa si alguien está
    /// mirando esto.
    /// </summary>
    protected override async void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        await ViewModel.LoadAsync();
    }

    private void Firmware_Checked(object sender, RoutedEventArgs e) => SelectFrom(sender);

    /// <summary>Un clic en cualquier parte de la tarjeta la elige.</summary>
    private void FirmwareCard_Tapped(object sender, Microsoft.UI.Xaml.Input.TappedRoutedEventArgs e) =>
        SelectFrom(sender);

    private void SelectFrom(object sender)
    {
        if (sender is FrameworkElement { DataContext: FirmwareChoiceCard card }) ViewModel.Select(card);
    }

    /// <summary>
    /// Lleva al Instalador (ST-138). <b>No instala desde acá</b>: el flasheo y
    /// sus confirmaciones son del asistente y de nadie más — esta pantalla solo
    /// guarda una preferencia.
    /// </summary>
    private void OpenInstaller_Click(object sender, RoutedEventArgs e) => Go("installer");

    /// <summary>
    /// Temas tiene pantalla propia y ya estaba en la barra lateral; desde acá se
    /// llega igual, que es como la ofrece macOS.
    /// </summary>
    private void Themes_Click(object sender, RoutedEventArgs e) => Go("extras.themes");

    private void Licenses_Click(object sender, RoutedEventArgs e) =>
        Frame.Navigate(typeof(LicensesPage), null,
            new Microsoft.UI.Xaml.Media.Animation.DrillInNavigationTransitionInfo());

    /// <summary>
    /// Navega por la barra lateral cuando el destino <b>es</b> una sección de
    /// la barra. Con <c>Frame.Navigate</c> a secas el contenido cambiaba pero la
    /// barra seguía marcando «Extras», así que el usuario terminaba en otra
    /// pantalla sin que nada dijera dónde estaba. Licencias no está en la barra
    /// y por eso sí se abre en el marco, como subpágina.
    /// </summary>
    private void Go(string tag)
    {
        if (ShellPage.Current is { } shell)
        {
            shell.GoToSection(tag);
            return;
        }

        // Sin armazón (no debería pasar), al menos se llega a algún lado.
        Frame.Navigate(tag == "installer" ? typeof(InstallerPage) : typeof(ThemesPage), null,
            new Microsoft.UI.Xaml.Media.Animation.DrillInNavigationTransitionInfo());
    }
}
