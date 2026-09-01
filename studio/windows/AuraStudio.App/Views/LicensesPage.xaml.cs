using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml.Controls;
using AuraStudio.App.ViewModels;

namespace AuraStudio.App.Views;

/// <summary>
/// Pantalla de Licencias (contrato §B). Accesible desde Ajustes › Acerca de.
/// Es una restricción crítica del proyecto, no una cortesía: es la vía por la
/// que Aura Studio cumple el §3 de la GPL v2 para lo que distribuye embebido.
/// </summary>
public sealed partial class LicensesPage : Page
{
    public LicensesViewModel ViewModel { get; }

    public LicensesPage()
    {
        InitializeComponent();
        ViewModel = App.Services.GetRequiredService<LicensesViewModel>();
    }
}
