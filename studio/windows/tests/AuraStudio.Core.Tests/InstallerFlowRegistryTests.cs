using AuraStudio.Core.Installer;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// D-185: en macOS, dos instancias del instalador extrajeron el árbol a la vez
/// sobre el mismo volumen y abortaron la instalación. Estas son las dos
/// barreras que lo impiden.
/// </summary>
public class InstallerFlowRegistryTests
{
    [Fact]
    public void NothingIsActiveAtTheStart()
    {
        var registry = new InstallerFlowRegistry();
        Assert.False(registry.FlowActive);
        Assert.False(registry.IsWritingToDisk);
        Assert.True(registry.CanInterrupt);
    }

    [Fact]
    public void AnActiveFlowBlocksAnyAutomaticInterruption()
    {
        // La barrera de arriba: el reconocimiento automático de DFU jamás toma
        // la pantalla con el asistente en curso.
        var registry = new InstallerFlowRegistry { FlowActive = true };
        Assert.False(registry.CanInterrupt);
    }

    [Fact]
    public void WritingBlocksInterruptionEvenWithoutAnActiveFlow()
    {
        // Cinturón y tirantes: aunque la bandera de flujo se hubiera quedado
        // apagada por error, escribir en el disco basta para bloquear.
        var registry = new InstallerFlowRegistry();
        Assert.True(registry.BeginWriting());
        Assert.False(registry.CanInterrupt);
    }

    [Fact]
    public void OnlyOneWriterAtATime()
    {
        var registry = new InstallerFlowRegistry();
        Assert.True(registry.BeginWriting());
        // El segundo NO debe tocar el disco: es exactamente el caso del incidente.
        Assert.False(registry.BeginWriting());
        Assert.True(registry.IsWritingToDisk);
    }

    [Fact]
    public void ReleasingLetsTheNextOneWrite()
    {
        var registry = new InstallerFlowRegistry();
        Assert.True(registry.BeginWriting());
        registry.EndWriting();
        Assert.False(registry.IsWritingToDisk);
        Assert.True(registry.BeginWriting());
    }

    [Fact]
    public void ReleasingTwiceIsHarmless()
    {
        var registry = new InstallerFlowRegistry();
        registry.EndWriting();
        registry.EndWriting();
        Assert.False(registry.IsWritingToDisk);
    }

    [Fact]
    public void OnlyOneOfManyConcurrentWritersWins()
    {
        var registry = new InstallerFlowRegistry();
        int granted = 0;

        Parallel.For(0, 64, _ =>
        {
            if (registry.BeginWriting()) Interlocked.Increment(ref granted);
        });

        Assert.Equal(1, granted);
    }
}
