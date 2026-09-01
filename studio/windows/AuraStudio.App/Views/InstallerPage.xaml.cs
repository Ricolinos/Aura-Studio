using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;
using AuraStudio.App.ViewModels;

namespace AuraStudio.App.Views;

/// <summary>
/// Asistente de instalación. Sin lógica propia: los pasos, las confirmaciones y
/// las operaciones viven en <see cref="InstallerViewModel"/>.
/// </summary>
public sealed partial class InstallerPage : Page
{
    public InstallerViewModel ViewModel { get; }

    public InstallerPage()
    {
        InitializeComponent();
        ViewModel = App.Services.GetRequiredService<InstallerViewModel>();
    }

    /// <summary>
    /// Al abrir el instalador se mira si el iPod ya está en DFU — el usuario
    /// pudo haberlo puesto antes de llegar acá. Es una pregunta, no una acción:
    /// el ViewModel decide si corresponde preguntar y jamás interrumpe un flujo
    /// en curso (D-185).
    /// </summary>
    protected override void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        _ = ViewModel.LookForDfuAsync();
    }
}
