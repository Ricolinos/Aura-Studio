using System.Globalization;
using System.Text;

namespace AuraStudio.App.Platform;

/// <summary>
/// Trazas de diagnóstico del arrastre de selección (2.º addendum de ST-209).
///
/// <para><b>Por qué existe.</b> El recuadro no recibe el gesto y esta sesión no
/// puede abrir la ventana: la única forma de saber <b>dónde</b> se corta la
/// cadena es que la app lo escriba mientras alguien la usa. No es telemetría ni
/// registro permanente — es un instrumento para una medición concreta, apagado
/// salvo que se lo pidan.</para>
///
/// <para><b>Apagado por omisión.</b> Se enciende con <c>AURA_MARQUEE_TRACE=1</c>
/// en el entorno, o siempre en compilaciones de depuración. Sin eso no abre ni
/// crea nada.</para>
///
/// <para><b>Nunca lanza.</b> Un instrumento de diagnóstico que tumba la app
/// impide justamente la medición que vino a hacer.</para>
/// </summary>
internal static class MarqueeTrace
{
    private static readonly Lock Gate = new();

    private static readonly bool EnabledByEnvironment =
        Environment.GetEnvironmentVariable("AURA_MARQUEE_TRACE") == "1";

    private static string? _path;
    private static bool _failed;

    /// <summary>Si hay que escribir. En <c>DEBUG</c> siempre; si no, con la variable puesta.</summary>
    public static bool Enabled
    {
        get
        {
#if DEBUG
            return !_failed;
#else
            return EnabledByEnvironment && !_failed;
#endif
        }
    }

    /// <summary>
    /// <c>%LOCALAPPDATA%\Aura Studio\marquee.log</c>. Se resuelve una vez.
    /// </summary>
    private static string? Path()
    {
        if (_path is not null) return _path;

        try
        {
            string folder = System.IO.Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Aura Studio");

            Directory.CreateDirectory(folder);
            return _path = System.IO.Path.Combine(folder, "marquee.log");
        }
        catch (Exception)
        {
            _failed = true;
            return null;
        }
    }

    /// <summary>Una línea con la hora, para poder leer el orden de los eventos.</summary>
    public static void Write(string line)
    {
        if (!Enabled) return;
        if (Path() is not { } path) return;

        try
        {
            string stamped =
                $"{DateTimeOffset.Now.ToString("HH:mm:ss.fff", CultureInfo.InvariantCulture)}  {line}";

            lock (Gate) File.AppendAllText(path, stamped + Environment.NewLine, Encoding.UTF8);
        }
        catch (Exception)
        {
            // Un instrumento que se rompe deja de instrumentar, no rompe la app.
            _failed = true;
        }
    }

    /// <summary>
    /// Marca el arranque de una corrida, para que dos pasadas seguidas no se
    /// lean como una sola.
    /// </summary>
    public static void Session(string what) => Write($"===== {what} =====");
}
