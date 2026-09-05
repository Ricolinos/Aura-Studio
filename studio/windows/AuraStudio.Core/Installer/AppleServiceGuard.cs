using System.Globalization;
using System.Security;

namespace AuraStudio.Core.Installer;

/// <summary>
/// La red que garantiza que el servicio de Apple vuelva, aunque la app se
/// muera (ST-169).
///
/// <para><b>El problema.</b> Pausar ese servicio es lo único que destraba un
/// iPod en DFU que Windows no deja ver (D-041/D-044), y la app lo reanuda al
/// terminar. Pero si muere entre una cosa y la otra —un cierre forzado, un
/// cuelgue, un corte de luz— el servicio <b>queda detenido para siempre</b> y el
/// usuario se queda sin iTunes ni Dispositivos Apple sin saber por qué. Reanudar
/// al cerrar la ventana no alcanza: eso no corre en un cuelgue.</para>
///
/// <para><b>La forma.</b> Una tarea programada de un solo disparo, creada
/// <b>dentro de la misma operación elevada que pausa</b> y <b>antes</b> de
/// pausar. Si no se pudo crear, no se pausa nada: es preferible que la ayuda no
/// funcione a dejar el servicio caído sin red. La sostiene Windows, no un
/// proceso nuestro — que es justo lo que hace falta cuando lo que puede morir es
/// nuestra app.</para>
///
/// <para><b>Por qué XML y no <c>/ST</c>.</b> <c>schtasks</c> interpreta las
/// fechas de la línea de comandos con el <b>formato regional</b> de la máquina:
/// la misma cadena significa cosas distintas en dos Windows y en algunos ni
/// siquiera es válida. El XML lleva la hora en ISO-8601, que es la misma en
/// todos lados, y de paso deja decir <c>DeleteExpiredTaskAfter</c> —que la tarea
/// se borre sola— y que corra como SYSTEM sin depender de ningún nombre de
/// cuenta traducido.</para>
/// </summary>
public static class AppleServiceGuard
{
    /// <summary>
    /// Bajo una carpeta propia para que se vea de quién es en el Programador de
    /// tareas: quien la encuentre tiene que poder saber qué la puso ahí.
    /// </summary>
    public const string TaskName = @"Aura Studio\Reanudar servicio de Apple";

    /// <summary>
    /// Cuánto se espera antes de reactivar solo.
    ///
    /// <para>El cálculo: grabar el arranque y esperar a que el iPod salga de DFU
    /// suman menos de dos minutos (la espera de salida son 45 s). Diez deja
    /// margen de sobra para cualquier corrida legítima —si la tarea saltara en
    /// medio, el servicio volvería y podría quitarle el USB a
    /// <c>mks5lboot</c>— y sigue siendo poco para alguien que se quedó sin
    /// iTunes sin saberlo.</para>
    /// </summary>
    public const int ResumeAfterMinutes = 10;

    /// <summary>SID de <c>NT AUTHORITY\SYSTEM</c>. Es el mismo en cualquier Windows y en cualquier idioma.</summary>
    public const string SystemAccountSid = "S-1-5-18";

    public static DateTimeOffset FiresAt(DateTimeOffset now) => now.AddMinutes(ResumeAfterMinutes);

    /// <summary>
    /// <b>Solo se puede pausar si la reactivación ya quedó programada.</b> Es la
    /// regla entera de ST-169 en una línea: primero la red, después el salto.
    /// </summary>
    public static bool CanPause(bool guardScheduled) => guardScheduled;

    /// <summary>Los argumentos para registrar la tarea desde el XML. <c>/F</c> reemplaza una previa en vez de duplicarla.</summary>
    public static string CreateArguments(string xmlPath) =>
        $"/Create /TN \"{TaskName}\" /XML \"{xmlPath}\" /F";

    /// <summary>
    /// Los argumentos para borrarla al reanudar normalmente. Nombra
    /// <b>la misma tarea</b> que <see cref="CreateArguments"/>: si los dos
    /// nombres se separaran, la tarea quedaría huérfana y reiniciaría el
    /// servicio diez minutos después, en medio de cualquier otra cosa.
    /// </summary>
    public static string DeleteArguments() => $"/Delete /TN \"{TaskName}\" /F";

    /// <summary>
    /// La definición de la tarea. La hora va en ISO-8601 y sin zona, que es lo
    /// que el Programador entiende como hora local.
    /// </summary>
    public static string TaskXml(DateTimeOffset firesAt, string serviceName)
    {
        string start = firesAt.LocalDateTime.ToString("yyyy-MM-ddTHH:mm:ss", CultureInfo.InvariantCulture);

        // Sin un final, `DeleteExpiredTaskAfter` no aplica y la tarea quedaría
        // registrada para siempre después de haber corrido.
        string end = firesAt.LocalDateTime.AddMinutes(ResumeAfterMinutes)
            .ToString("yyyy-MM-ddTHH:mm:ss", CultureInfo.InvariantCulture);

        string service = SecurityElement.Escape(serviceName) ?? "";

        return $"""
            <?xml version="1.0" encoding="UTF-16"?>
            <Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
              <RegistrationInfo>
                <Description>Aura Studio detuvo el servicio de Apple para poder ver un iPod en modo DFU. Esta tarea lo vuelve a encender sola si Aura Studio no llega a hacerlo.</Description>
              </RegistrationInfo>
              <Triggers>
                <TimeTrigger>
                  <StartBoundary>{start}</StartBoundary>
                  <EndBoundary>{end}</EndBoundary>
                  <Enabled>true</Enabled>
                </TimeTrigger>
              </Triggers>
              <Principals>
                <Principal id="Author">
                  <UserId>{SystemAccountSid}</UserId>
                  <RunLevel>HighestAvailable</RunLevel>
                </Principal>
              </Principals>
              <Settings>
                <DeleteExpiredTaskAfter>PT1M</DeleteExpiredTaskAfter>
                <StartWhenAvailable>true</StartWhenAvailable>
                <AllowStartOnDemand>true</AllowStartOnDemand>
                <Enabled>true</Enabled>
                <ExecutionTimeLimit>PT5M</ExecutionTimeLimit>
                <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
                <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
                <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
              </Settings>
              <Actions Context="Author">
                <Exec>
                  <Command>sc.exe</Command>
                  <Arguments>start "{service}"</Arguments>
                </Exec>
              </Actions>
            </Task>
            """;
    }
}
