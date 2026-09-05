using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// ST-161: la app se congelaba con un núcleo al 100% porque la biblioteca y la
/// cuadrícula se llamaban en círculo — refrescar publicaba la selección,
/// publicar avisaba <b>siempre</b>, y el aviso volvía a refrescar.
///
/// <para>Acá está ese ciclo en miniatura, con las dos piezas reducidas a lo
/// único que importaba: quién avisa y quién escucha. Con la regla vieja
/// (<c>notifyAlways</c>) no termina; con la de ahora, se detiene solo.</para>
/// </summary>
public class SelectionPublicationTests
{
    /// <summary>La biblioteca, reducida a publicar la selección y avisarlo.</summary>
    private sealed class Library(bool notifyAlways)
    {
        /// <summary>El comportamiento viejo: avisar siempre, cambiara o no.</summary>
        private readonly bool _notifyAlways = notifyAlways;

        public event Action? SelectionPublished;

        public IReadOnlyCollection<Guid> SelectionForSync { get; private set; } = [];

        public int Notifications { get; private set; }

        public void PublishSelectionForSync(IReadOnlyCollection<Guid> ids)
        {
            if (!_notifyAlways && SelectionPublication.SameSelection(SelectionForSync, ids)) return;

            SelectionForSync = ids;
            Notifications++;
            SelectionPublished?.Invoke();
        }
    }

    /// <summary>
    /// La cuadrícula: se rehace ante el aviso de la biblioteca y, al rehacerse,
    /// vuelve a publicar su selección. Las dos mitades son razonables por
    /// separado; juntas eran el ciclo.
    /// </summary>
    private sealed class Grid
    {
        /// <summary>
        /// Sin este tope la prueba se llevaría al proceso entero con un
        /// <c>StackOverflowException</c>, que en .NET no se puede atrapar: la
        /// recursión se demuestra contando, no dejándola desbordar.
        /// </summary>
        private const int Runaway = 500;

        private readonly Library _library;

        public Grid(Library library)
        {
            _library = library;
            _library.SelectionPublished += Refresh;
        }

        public int Refreshes { get; private set; }

        public void Refresh()
        {
            if (++Refreshes > Runaway)
                throw new InvalidOperationException("Refresh se llamó a sí mismo sin fin (ST-161).");

            _library.PublishSelectionForSync(SelectedSongIds());
        }

        /// <summary>
        /// Una lista <b>nueva</b> en cada refresco, como la de verdad: la
        /// cuadrícula rearma sus tarjetas y recolecta los ids otra vez. Por eso
        /// comparar referencias no alcanza — siempre serían distintas.
        /// </summary>
        private static IReadOnlyCollection<Guid> SelectedSongIds() => new List<Guid>();
    }

    // MARK: - El ciclo

    [Fact]
    public void TheOldRuleMakesTheGridRefreshItselfForever()
    {
        var library = new Library(notifyAlways: true);
        var grid = new Grid(library);

        Assert.Throws<InvalidOperationException>(grid.Refresh);
    }

    [Fact]
    public void PublishingTheSameSelectionAgainDoesNotNotify()
    {
        var library = new Library(notifyAlways: false);
        var grid = new Grid(library);

        grid.Refresh();

        // Un solo refresco, ningún aviso: la selección vacía que publica una
        // cuadrícula recién armada es la que ya estaba publicada.
        Assert.Equal(1, grid.Refreshes);
        Assert.Equal(0, library.Notifications);
    }

    [Fact]
    public void ARealChangeStillNotifiesAndTheCycleClosesByItself()
    {
        var library = new Library(notifyAlways: false);
        var grid = new Grid(library);

        // Otra vista publicó su selección; al refrescarse, la cuadrícula
        // publica la suya —vacía— y eso SÍ es un cambio.
        library.PublishSelectionForSync([Guid.NewGuid()]);

        Assert.Equal(2, library.Notifications);
        Assert.Equal(2, grid.Refreshes);
        Assert.Empty(library.SelectionForSync);
    }

    // MARK: - La regla, sola

    [Fact]
    public void TwoNewListsWithTheSameIdsAreTheSameSelection()
    {
        Guid one = Guid.NewGuid();
        Guid two = Guid.NewGuid();

        Assert.True(SelectionPublication.SameSelection(
            new List<Guid> { one, two }, new List<Guid> { one, two }));
    }

    [Fact]
    public void TwoEmptySelectionsAreTheSame()
    {
        Assert.True(SelectionPublication.SameSelection(new List<Guid>(), Array.Empty<Guid>()));
    }

    [Fact]
    public void OrderDoesNotMakeItADifferentSelection()
    {
        Guid one = Guid.NewGuid();
        Guid two = Guid.NewGuid();

        Assert.True(SelectionPublication.SameSelection(
            new List<Guid> { one, two }, new List<Guid> { two, one }));
    }

    [Fact]
    public void RepeatingAnIdDoesNotMakeItADifferentSelection()
    {
        Guid one = Guid.NewGuid();

        Assert.True(SelectionPublication.SameSelection(
            new List<Guid> { one }, new List<Guid> { one, one }));
    }

    [Fact]
    public void AddingSomethingIsADifferentSelection()
    {
        Guid one = Guid.NewGuid();

        Assert.False(SelectionPublication.SameSelection(
            new List<Guid> { one }, new List<Guid> { one, Guid.NewGuid() }));
    }

    [Fact]
    public void EmptyingASelectionIsAChange()
    {
        Assert.False(SelectionPublication.SameSelection(
            new List<Guid> { Guid.NewGuid() }, Array.Empty<Guid>()));
    }
}
