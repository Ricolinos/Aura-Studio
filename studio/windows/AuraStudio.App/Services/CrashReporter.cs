using System.Text;
using Microsoft.UI.Xaml;

namespace AuraStudio.App.Services;

/// <summary>
/// Deja rastro de cualquier error que nadie atrapó, y evita que la app
/// desaparezca sin decir nada.
///
/// <para><b>Por qué existe.</b> La app se cerró sola al instalar Metro después
/// de Aura. Del lado de Aura Studio no quedó absolutamente nada: ni un mensaje,
/// ni un archivo, ni una pista. Lo único que había era una entrada del Visor de
/// eventos de Windows con <c>0xC000027B</c> y un desplazamiento dentro de
/// <c>combase.dll</c> — que dice que hubo una excepción no controlada en el
/// hilo de la interfaz, y nada más. Diagnosticar así es arqueología.</para>
///
/// <para>En WinUI 3, una excepción que escapa de un manejador de interfaz mata
/// el proceso <b>sin diálogo</b>. Con esto, en cambio, queda un archivo legible
/// en <c>%LOCALAPPDATA%\Aura Studio\errores.log</c> y —cuando se puede— un
/// aviso en pantalla.</para>
/// </summary>
public static class CrashReporter
{
    private const string FolderName = "Aura Studio";
    private const string FileName = "errores.log";

    private static readonly Lock Gate = new();

    public static string LogPath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        FolderName, FileName);

    /// <summary>Se engancha una sola vez, lo antes posible en el arranque.</summary>
    public static void Install(Application application)
    {
        application.UnhandledException += (_, e) =>
        {
            Record("interfaz", e.Exception, e.Message);

            // Se marca como controlada para poder CONTAR lo que pasó. Es una
            // decisión con costo: la app sigue viva y quizá en un estado raro.
            // Pero morir en silencio es peor — el usuario no sabe si su iPod
            // quedó a medias, y no queda nada que mirar después.
            e.Handled = true;

            Notify(e.Exception?.Message ?? e.Message);
        };

        AppDomain.CurrentDomain.UnhandledException += (_, e) =>
            // Acá ya no se puede evitar el cierre; al menos queda escrito.
            Record("proceso", e.ExceptionObject as Exception, null);

        TaskScheduler.UnobservedTaskException += (_, e) =>
        {
            // Una tarea que nadie esperó y falló. No mata el proceso, pero suele
            // ser la causa de que "no pasó nada" cuando debía pasar algo.
            Record("tarea sin observar", e.Exception, null);
            e.SetObserved();
        };
    }

    /// <summary>
    /// Escribe una entrada. <b>Nunca lanza</b>: un reportador de errores que
    /// falla al reportar deja al usuario peor que antes.
    /// </summary>
    public static void Record(string origin, Exception? exception, string? message)
    {
        try
        {
            var entry = new StringBuilder()
                .AppendLine("──────────────────────────────────────────")
                .Append("Cuándo: ").AppendLine(DateTimeOffset.Now.ToString("u"))
                .Append("Dónde:  ").AppendLine(origin);

            if (!string.IsNullOrWhiteSpace(message))
                entry.Append("Mensaje: ").AppendLine(message);

            if (exception is not null)
            {
                entry.Append("Tipo:   ").AppendLine(exception.GetType().FullName);
                entry.Append("Detalle: ").AppendLine(exception.Message);
                entry.AppendLine(exception.StackTrace ?? "(sin pila)");

                for (Exception? inner = exception.InnerException; inner is not null; inner = inner.InnerException)
                    entry.Append("Causado por: ").Append(inner.GetType().Name).Append(" — ").AppendLine(inner.Message);
            }

            string? directory = Path.GetDirectoryName(LogPath);
            if (!string.IsNullOrEmpty(directory)) Directory.CreateDirectory(directory);

            lock (Gate) File.AppendAllText(LogPath, entry.ToString());
        }
        catch (Exception)
        {
            // Ver el resumen de la clase.
        }
    }

    /// <summary>
    /// Avisa en pantalla si hay ventana. Si no la hay —o si el aviso también
    /// falla— el archivo ya quedó escrito, que es lo que importa.
    /// </summary>
    private static void Notify(string message)
    {
        try
        {
            if ((Application.Current as App)?.MainWindow?.Content is not FrameworkElement root) return;

            var dialog = new Microsoft.UI.Xaml.Controls.ContentDialog
            {
                XamlRoot = root.XamlRoot,
                Title = "Algo salió mal",
                Content = $"Aura Studio encontró un error inesperado y lo anotó en:\n{LogPath}\n\n{message}",
                CloseButtonText = "Entendido"
            };

            _ = dialog.ShowAsync();
        }
        catch (Exception)
        {
            // Ídem.
        }
    }
}
