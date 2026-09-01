using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// El alcance de la sincronización (R3-4, ST-129): "toda la biblioteca" o
/// "solo la selección", con las mismas reglas y los mismos mensajes que macOS.
///
/// <para>Son tres negativas parecidas con tres textos distintos, y el ORDEN en
/// que se comprueban cambia lo que el usuario entiende. Por eso viven acá y no
/// en la pantalla: escritas en cada vista, se desincronizan entre las dos
/// apps.</para>
/// </summary>
public sealed class SyncScopeResolverTests
{
    private static LibraryItem Item(string path, LibraryItemState state = LibraryItemState.Ready) => new()
    {
        SourcePath = path,
        Kind = LibraryItemKind.Music,
        Status = new LibraryItemStatus(state)
    };

    [Fact]
    public void TodaLaBibliotecaNoAcotaNada()
    {
        List<LibraryItem> items = [Item("a.mp3"), Item("b.mp3")];

        SyncScopeResolution resolution = SyncScopeResolver.Resolve(items, SyncScope.Everything);

        Assert.True(resolution.CanSync);
        Assert.Null(resolution.RestrictToSourcePaths);
    }

    [Fact]
    public void LaSeleccionAcotaALasRutasDeLoSeleccionadoYListo()
    {
        LibraryItem uno = Item("a.mp3");
        LibraryItem dos = Item("b.mp3");
        List<LibraryItem> items = [uno, dos, Item("c.mp3")];

        SyncScopeResolution resolution =
            SyncScopeResolver.Resolve(items, new SyncScope.Selection([uno.Id, dos.Id]));

        Assert.True(resolution.CanSync);
        Assert.Equal(["a.mp3", "b.mp3"], resolution.RestrictToSourcePaths!.Order());
    }

    /// <summary>
    /// Solo lo LISTO viaja: algo a medio convertir o que espera una decisión
    /// del usuario no es un archivo que se pueda copiar.
    /// </summary>
    [Fact]
    public void LoQueNoEstaListoSeQuedaFueraAunqueEsteSeleccionado()
    {
        LibraryItem listo = Item("listo.mp3");
        LibraryItem convirtiendo = Item("convirtiendo.mp4", LibraryItemState.Transcoding);
        LibraryItem revision = Item("revisar.mp3", LibraryItemState.NeedsReview);

        SyncScopeResolution resolution = SyncScopeResolver.Resolve(
            [listo, convirtiendo, revision],
            new SyncScope.Selection([listo.Id, convirtiendo.Id, revision.Id]));

        Assert.Equal(["listo.mp3"], resolution.RestrictToSourcePaths!);
    }

    // MARK: - Las tres negativas, cada una con su texto

    [Fact]
    public void SinNadaSeleccionadoSeDiceEsoYNoOtraCosa()
    {
        SyncScopeResolution resolution =
            SyncScopeResolver.Resolve([Item("a.mp3")], new SyncScope.Selection([]));

        Assert.False(resolution.CanSync);
        Assert.Equal(SyncScopeResolver.NothingSelected, resolution.Refusal);
    }

    [Fact]
    public void ConLoSeleccionadoTodaviaNoListoSeDiceEso()
    {
        LibraryItem esperando = Item("esperando.mp4", LibraryItemState.Transcoding);

        SyncScopeResolution resolution = SyncScopeResolver.Resolve(
            [esperando, Item("otro.mp3")],
            new SyncScope.Selection([esperando.Id]));

        Assert.False(resolution.CanSync);
        Assert.Equal(SyncScopeResolver.SelectionNotReady, resolution.Refusal);
    }

    [Fact]
    public void SinNadaListoEnTodaLaBibliotecaSeDiceEso()
    {
        SyncScopeResolution resolution = SyncScopeResolver.Resolve(
            [Item("a.mp3", LibraryItemState.Queued)], SyncScope.Everything);

        Assert.False(resolution.CanSync);
        Assert.Equal(SyncScopeResolver.NothingReady, resolution.Refusal);
    }

    /// <summary>
    /// El orden importa: con una selección hecha sobre una biblioteca sin nada
    /// listo, el mensaje tiene que hablar de <b>la selección</b>. Al revés, el
    /// usuario leería "no hay nada listo" y no sabría si el problema es lo que
    /// eligió.
    /// </summary>
    [Fact]
    public void LaNegativaDeLaSeleccionGanaALaGlobal()
    {
        LibraryItem esperando = Item("esperando.mp3", LibraryItemState.Queued);

        SyncScopeResolution resolution =
            SyncScopeResolver.Resolve([esperando], new SyncScope.Selection([esperando.Id]));

        Assert.Equal(SyncScopeResolver.SelectionNotReady, resolution.Refusal);
        Assert.NotEqual(SyncScopeResolver.NothingReady, resolution.Refusal);
    }

    [Fact]
    public void UnaSeleccionVaciaSobreUnaBibliotecaVaciaHablaDeLaSeleccion()
    {
        SyncScopeResolution resolution =
            SyncScopeResolver.Resolve([], new SyncScope.Selection([]));

        Assert.Equal(SyncScopeResolver.NothingSelected, resolution.Refusal);
    }

    // MARK: - El conteo que se muestra antes de revisar

    [Fact]
    public void LosPendientesSonLosQueEstanListos()
    {
        List<LibraryItem> items =
        [
            Item("a.mp3"),
            Item("b.mp3"),
            Item("c.mp4", LibraryItemState.Transcoding),
            Item("d.mp3", LibraryItemState.Failed)
        ];

        Assert.Equal(2, SyncScopeResolver.PendingCount(items));
    }

    [Fact]
    public void SinBibliotecaNoHayPendientes() => Assert.Equal(0, SyncScopeResolver.PendingCount([]));
}
