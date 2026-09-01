using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using AuraStudio.App.Platform;

namespace AuraStudio.App;

/// <summary>
/// Punto de entrada propio, en lugar del que genera XAML
/// (<c>DISABLE_XAML_GENERATED_MAIN</c>).
///
/// La única razón es poder mirar los argumentos **antes** de arrancar la
/// interfaz: cuando Aura Studio se relanza a sí misma con permisos de
/// administrador para una operación privilegiada, ese proceso no debe abrir
/// ninguna ventana — hace su trabajo, deja el resultado y termina. Ver
/// <see cref="PrivilegedRunner"/> y <see cref="PrivilegedHost"/>.
/// </summary>
public static class Program
{
    [STAThread]
    public static int Main(string[] args)
    {
        if (PrivilegedHost.TryHandle(args, out int exitCode))
        {
            return exitCode;
        }

        WinRT.ComWrappersSupport.InitializeComWrappers();
        Application.Start(parameters =>
        {
            var context = new DispatcherQueueSynchronizationContext(DispatcherQueue.GetForCurrentThread());
            SynchronizationContext.SetSynchronizationContext(context);
            // La instancia se registra sola en Application.Current; no hay que guardarla.
            _ = new App();
        });
        return 0;
    }
}
