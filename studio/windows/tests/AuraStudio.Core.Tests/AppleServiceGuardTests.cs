using AuraStudio.Core.Installer;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// ST-169: la red que hace que el servicio de Apple vuelva aunque la app se
/// muera. Lo que se prueba acá es lo decidible: qué se le pide al Programador de
/// tareas, y —lo que sostiene la decisión entera— que sin esa red no se pausa
/// nada.
/// </summary>
public class AppleServiceGuardTests
{
    private const string Service = "Apple Mobile Device Service";

    private static readonly DateTimeOffset Now =
        new(2026, 9, 5, 23, 55, 0, TimeSpan.FromHours(-6));

    // MARK: - La regla que sostiene todo

    [Fact]
    public void WithoutTheGuardScheduledNothingIsPaused()
    {
        // Es preferible que la ayuda no funcione a dejar el servicio caído sin
        // red: quien se queda sin iTunes no tiene forma de adivinar por qué.
        Assert.False(AppleServiceGuard.CanPause(guardScheduled: false));
    }

    [Fact]
    public void WithTheGuardScheduledItCanPause()
    {
        Assert.True(AppleServiceGuard.CanPause(guardScheduled: true));
    }

    // MARK: - Cuándo se dispara

    [Fact]
    public void TheGuardFiresTenMinutesLater()
    {
        // Grabar y esperar la salida del DFU suman menos de dos minutos; diez
        // deja margen sin dejar al usuario media tarde sin su servicio.
        Assert.Equal(10, AppleServiceGuard.ResumeAfterMinutes);
        Assert.Equal(Now.AddMinutes(10), AppleServiceGuard.FiresAt(Now));
    }

    [Fact]
    public void CrossingMidnightIsJustAnotherTimestamp()
    {
        // A las 23:55 la tarea cae al día siguiente. Es el caso que se rompe
        // cuando se le pasa a schtasks solo la hora, y la razón de usar XML con
        // fecha completa en vez de /ST.
        string xml = AppleServiceGuard.TaskXml(AppleServiceGuard.FiresAt(Now), Service);

        DateTime expected = Now.AddMinutes(10).LocalDateTime;
        Assert.Contains($"<StartBoundary>{expected:yyyy-MM-ddTHH:mm:ss}</StartBoundary>", xml, StringComparison.Ordinal);
    }

    [Fact]
    public void TheTimestampIsIsoAndNotRegional()
    {
        // Lo mismo dicho al revés: nada de "05/09/2026" ni "9/5/2026", que
        // significan cosas distintas en dos Windows.
        string xml = AppleServiceGuard.TaskXml(AppleServiceGuard.FiresAt(Now), Service);

        Assert.DoesNotContain("/2026", xml, StringComparison.Ordinal);
        Assert.Contains("2026-09-06T00:05:00", xml, StringComparison.Ordinal);
    }

    // MARK: - Qué hace la tarea

    [Fact]
    public void TheTaskStartsTheServiceItWasToldTo()
    {
        string xml = AppleServiceGuard.TaskXml(AppleServiceGuard.FiresAt(Now), Service);

        Assert.Contains("<Command>sc.exe</Command>", xml, StringComparison.Ordinal);
        Assert.Contains($"start \"{Service}\"", xml, StringComparison.Ordinal);
    }

    [Fact]
    public void TheTaskRunsAsSystemBySidAndNotByAccountName()
    {
        // "NT AUTHORITY\SYSTEM" está traducido en un Windows en español; el SID
        // es el mismo en todos.
        string xml = AppleServiceGuard.TaskXml(AppleServiceGuard.FiresAt(Now), Service);

        Assert.Contains("<UserId>S-1-5-18</UserId>", xml, StringComparison.Ordinal);
        Assert.DoesNotContain("NT AUTHORITY", xml, StringComparison.Ordinal);
    }

    [Fact]
    public void TheTaskDeletesItselfAfterRunning()
    {
        // Sin esto quedaría registrada para siempre después de haber corrido, y
        // el Programador del usuario acumularía una tarea nuestra por cada DFU.
        string xml = AppleServiceGuard.TaskXml(AppleServiceGuard.FiresAt(Now), Service);

        Assert.Contains("<DeleteExpiredTaskAfter>", xml, StringComparison.Ordinal);
        // `DeleteExpiredTaskAfter` no aplica sin un final declarado.
        Assert.Contains("<EndBoundary>", xml, StringComparison.Ordinal);
    }

    [Fact]
    public void TheTaskRunsEvenOnBattery()
    {
        // Una laptop desenchufada es el caso normal de alguien flasheando un
        // iPod en la mesa de la cocina. Con el ajuste por omisión de Windows,
        // la tarea no correría y el servicio se quedaría abajo.
        string xml = AppleServiceGuard.TaskXml(AppleServiceGuard.FiresAt(Now), Service);

        Assert.Contains("<DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>", xml,
                        StringComparison.Ordinal);
        Assert.Contains("<StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>", xml,
                        StringComparison.Ordinal);
    }

    [Fact]
    public void ThePcBeingAsleepDoesNotLoseTheResume()
    {
        // Si la máquina estaba apagada o suspendida a la hora del disparo, la
        // tarea corre en cuanto pueda en vez de perderse.
        string xml = AppleServiceGuard.TaskXml(AppleServiceGuard.FiresAt(Now), Service);

        Assert.Contains("<StartWhenAvailable>true</StartWhenAvailable>", xml, StringComparison.Ordinal);
    }

    // MARK: - Cómo se registra y cómo se borra

    [Fact]
    public void RegisteringReplacesAPreviousTaskInsteadOfDuplicatingIt()
    {
        string arguments = AppleServiceGuard.CreateArguments(@"C:\tmp\guard.xml");

        Assert.Contains("/Create", arguments, StringComparison.Ordinal);
        Assert.Contains("/XML \"C:\\tmp\\guard.xml\"", arguments, StringComparison.Ordinal);
        Assert.Contains("/F", arguments, StringComparison.Ordinal);
    }

    [Fact]
    public void DeletingNamesTheVerySameTaskThatWasCreated()
    {
        // Si los dos nombres se separaran, la tarea quedaría huérfana y
        // reiniciaría el servicio diez minutos después, en medio de otra cosa.
        Assert.Contains($"/TN \"{AppleServiceGuard.TaskName}\"",
                        AppleServiceGuard.CreateArguments("x.xml"), StringComparison.Ordinal);
        Assert.Contains($"/TN \"{AppleServiceGuard.TaskName}\"",
                        AppleServiceGuard.DeleteArguments(), StringComparison.Ordinal);
    }

    [Fact]
    public void DeletingDoesNotAskForConfirmation()
    {
        // Sin /F, schtasks pregunta — y del otro lado no hay nadie escribiendo.
        Assert.Contains("/F", AppleServiceGuard.DeleteArguments(), StringComparison.Ordinal);
    }

    [Fact]
    public void TheTaskSaysWhoPutItThereAndWhy()
    {
        // Quien la encuentre en el Programador tiene que poder entenderla sin
        // buscar en internet.
        string xml = AppleServiceGuard.TaskXml(AppleServiceGuard.FiresAt(Now), Service);

        Assert.Contains("Aura Studio", xml, StringComparison.Ordinal);
        Assert.Contains("Aura Studio", AppleServiceGuard.TaskName, StringComparison.Ordinal);
    }

    [Fact]
    public void AServiceNameWithMarkupCannotBreakTheXml()
    {
        string xml = AppleServiceGuard.TaskXml(AppleServiceGuard.FiresAt(Now), "raro & <peligroso>");

        Assert.DoesNotContain("<peligroso>", xml, StringComparison.Ordinal);
        Assert.Contains("&amp;", xml, StringComparison.Ordinal);
    }
}
