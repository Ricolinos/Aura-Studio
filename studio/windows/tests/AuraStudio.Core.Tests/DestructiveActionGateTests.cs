using AuraStudio.Core.Installer;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// La regla que impide que alguien explorando a clics llegue a borrar su iPod.
///
/// Existe por un incidente concreto: el asistente trataba "el ensayo pasó" como
/// permiso suficiente y el dueño ejecutó **dos formateos reales** creyendo que
/// solo estaba probando el software. Cada caso de acá es una de las cosas que
/// salió mal.
/// </summary>
public class DestructiveActionGateTests
{
    private static DestructiveActionGate Ready()
    {
        var gate = new DestructiveActionGate { HasTarget = true };
        gate.MarkChecked();
        gate.SetConfirmed(true);
        return gate;
    }

    [Fact]
    public void NothingIsAllowedAtTheStart()
    {
        var gate = new DestructiveActionGate();
        Assert.False(gate.CanProceed);
        Assert.Equal(DestructiveRefusal.NoTarget, gate.Evaluate());
    }

    [Fact]
    public void ACheckIsNotPermission()
    {
        // El corazón del bug: el ensayo comprueba, no autoriza.
        var gate = new DestructiveActionGate { HasTarget = true };
        gate.MarkChecked();

        Assert.False(gate.CanProceed);
        Assert.Equal(DestructiveRefusal.NotConfirmed, gate.Evaluate());
    }

    [Fact]
    public void ConfirmingDoesNotReplaceTheCheck()
    {
        // Y al revés: confirmar no exime de haber comprobado que es viable.
        var gate = new DestructiveActionGate { HasTarget = true };
        gate.SetConfirmed(true);

        Assert.False(gate.CanProceed);
        Assert.Equal(DestructiveRefusal.NotChecked, gate.Evaluate());
    }

    [Fact]
    public void WithTargetCheckAndConsentItProceeds()
    {
        Assert.True(Ready().CanProceed);
    }

    [Fact]
    public void ConsentIsConsumedSoASecondRunNeedsAFreshOne()
    {
        // Los dos formateos reales del incidente estuvieron a 19 segundos uno
        // del otro. El segundo no puede heredar el permiso del primero.
        var gate = Ready();

        Assert.True(gate.TryConsume());
        Assert.False(gate.CanProceed);
        Assert.Equal(DestructiveRefusal.NotConfirmed, gate.Evaluate());
        Assert.False(gate.TryConsume());
    }

    [Fact]
    public void AfterConsumingTheCheckSurvivesButThePermissionDoesNot()
    {
        // No hay que volver a ensayar; sí hay que volver a confirmar.
        var gate = Ready();
        gate.TryConsume();

        Assert.True(gate.Checked);
        Assert.False(gate.Confirmed);

        gate.SetConfirmed(true);
        Assert.True(gate.CanProceed);
    }

    [Fact]
    public void ChangingTheTargetDropsEverything()
    {
        // Ni el ensayo ni el permiso valen para otro disco: el ensayo se hizo
        // sobre otra geometría y el usuario confirmó sobre otro nombre.
        var gate = Ready();
        gate.TargetChanged(hasTarget: true);

        Assert.False(gate.Checked);
        Assert.False(gate.Confirmed);
        Assert.Equal(DestructiveRefusal.NotChecked, gate.Evaluate());
    }

    [Fact]
    public void LosingTheTargetBlocksEverything()
    {
        var gate = Ready();
        gate.TargetChanged(hasTarget: false);

        Assert.False(gate.CanProceed);
        Assert.Equal(DestructiveRefusal.NoTarget, gate.Evaluate());
    }

    [Fact]
    public void WithdrawingConsentBlocksAgain()
    {
        // Destildar la casilla vuelve a bloquear, sin tener que reiniciar nada.
        var gate = Ready();
        gate.SetConfirmed(false);
        Assert.False(gate.CanProceed);
    }

    [Fact]
    public void ARefusedAttemptDoesNotSpendTheConsent()
    {
        // Si falla por falta de comprobación, el permiso sigue puesto: no se
        // castiga al usuario haciéndole confirmar otra vez por un error ajeno.
        var gate = new DestructiveActionGate { HasTarget = true };
        gate.SetConfirmed(true);

        Assert.False(gate.TryConsume());
        Assert.True(gate.Confirmed);
    }
}
