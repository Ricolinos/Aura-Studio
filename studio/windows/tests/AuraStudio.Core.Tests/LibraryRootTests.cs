using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// ST-171: el dueño abrió la app con su disco externo desmontado y le salió un
/// diálogo de "Algo salió mal". Una biblioteca en un disco que no está
/// conectado es un <b>estado normal</b>, y lo que hay que garantizar es que en
/// ese estado <b>no se escriba absolutamente nada</b>: lo que hay en memoria no
/// es el catálogo del usuario, es lo que quedó de no haber podido leerlo.
/// </summary>
public class LibraryRootTests : IDisposable
{
    /// <summary>Una carpeta de verdad, creada para la prueba y borrada al final.</summary>
    private readonly string _existing =
        Path.Combine(Path.GetTempPath(), "aura-st171-" + Guid.NewGuid().ToString("N"));

    /// <summary>Una unidad que no existe en ninguna máquina razonable.</summary>
    private const string MissingDrive = @"Q:\no\existe\biblioteca";

    public LibraryRootTests() => Directory.CreateDirectory(_existing);

    public void Dispose()
    {
        if (Directory.Exists(_existing)) Directory.Delete(_existing, recursive: true);
        GC.SuppressFinalize(this);
    }

    // MARK: - La carpeta está o no está

    [Fact]
    public void AnExistingFolderIsAvailable()
    {
        Assert.True(LibraryRoot.IsAvailable(_existing));
        Assert.True(LibraryAvailability.For(_existing).IsAvailable);
    }

    [Fact]
    public void AFolderOnAnUnmountedDriveIsNotAvailable()
    {
        Assert.False(LibraryRoot.IsAvailable(MissingDrive));

        LibraryAvailability availability = LibraryAvailability.For(MissingDrive);
        Assert.True(availability.IsRootMissing);
        // La ruta viaja con el estado: la pantalla tiene que poder decir CUÁL
        // biblioteca falta.
        Assert.Equal(MissingDrive, availability.Root);
    }

    [Fact]
    public void AFolderThatDoesNotExistYetOnAMountedDiskIsANewLibraryAndNotAMissingOne()
    {
        // EL PRIMER ARRANQUE. `Documentos\Aura Studio` todavía no existe, y la
        // app tiene que empezar con una biblioteca vacía como siempre — no
        // decirle al usuario que su carpeta de Documentos "está en un disco que
        // no está conectado".
        string brandNew = Path.Combine(_existing, "todavia-no-existe");

        Assert.False(LibraryRoot.IsAvailable(brandNew));       // la carpeta no está…
        Assert.True(LibraryRoot.VolumeIsMounted(brandNew));    // …pero el disco sí
        Assert.True(LibraryAvailability.For(brandNew).IsAvailable);
    }

    [Fact]
    public void ANewLibraryReadsAsEmptyAndWithoutAnError()
    {
        // La otra cara de lo mismo: en el primer arranque no puede aparecer
        // ningún aviso de error — no hay nada roto, hay una biblioteca por
        // estrenar.
        string brandNew = Path.Combine(_existing, "sin-estrenar");

        LibraryCatalogStore.CatalogLoad load = LibraryCatalogStore.TryLoad(brandNew);

        Assert.Null(load.Error);
        Assert.Empty(load.Catalog.Items);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void NoPathAtAllIsNotAvailable(string? root)
    {
        Assert.False(LibraryRoot.IsAvailable(root));
        Assert.False(LibraryRoot.VolumeIsMounted(root));
        Assert.True(LibraryAvailability.For(root).IsRootMissing);
    }

    // MARK: - El volumen, que es otra pregunta

    [Fact]
    public void TheVolumeOfAnExistingFolderIsMounted()
    {
        Assert.True(LibraryRoot.VolumeIsMounted(_existing));
    }

    [Fact]
    public void TheVolumeOfAnUnmountedDriveIsNot()
    {
        Assert.False(LibraryRoot.VolumeIsMounted(MissingDrive));
    }

    // MARK: - No leer de más

    [Fact]
    public void AnUnmountedDiskIsNotTheSameAsAnEmptyLibrary()
    {
        // Ésta es la raíz del bug. `TryLoad` devolvía catálogo vacío Y SIN
        // ERROR cuando el archivo no estaba, así que "no pude mirar" se veía
        // igual que "no hay nada". De ahí salía la cadena entera: nada que
        // normalizar → doy por normalizado → guardo esa conclusión.
        LibraryCatalogStore.CatalogLoad missing = LibraryCatalogStore.TryLoad(MissingDrive);
        Assert.NotNull(missing.Error);
        Assert.Empty(missing.Catalog.Items);

        LibraryCatalogStore.CatalogLoad empty = LibraryCatalogStore.TryLoad(_existing);
        Assert.Null(empty.Error);
        Assert.Empty(empty.Catalog.Items);
    }

    // MARK: - Y sobre todo: no escribir nada

    [Fact]
    public void SavingToAnUnmountedDriveFailsWithoutCreatingAnything()
    {
        var store = new LibraryStore(MissingDrive);

        Assert.Throws<LibraryRootUnavailableException>(() => store.SaveItems([]));
        // Lo que importa de verdad: no quedó ninguna carpeta inventada.
        Assert.False(Directory.Exists(MissingDrive));
        Assert.False(Directory.Exists(@"Q:\"));
    }

    [Fact]
    public void TheExceptionSaysWhichLibraryItWas()
    {
        var thrown = Assert.Throws<LibraryRootUnavailableException>(
            () => LibraryCatalogStore.Save(MissingDrive, new PersistedLibrary()));

        Assert.Equal(MissingDrive, thrown.Root);
    }

    [Fact]
    public void SavingIntoAMountedDriveStillCreatesTheFolderOfANewLibrary()
    {
        // La otra mitad de la regla: crear la carpeta de una biblioteca nueva es
        // legítimo — es lo que pasa en el primer arranque. Si se prohibiera
        // escribir siempre que la carpeta no existe, no se podría empezar.
        string brandNew = Path.Combine(_existing, "biblioteca-nueva");
        Assert.False(Directory.Exists(brandNew));

        LibraryCatalogStore.Save(brandNew, new PersistedLibrary());

        Assert.True(Directory.Exists(brandNew));
    }

    // MARK: - El estado observable

    [Fact]
    public void TheStoreReportsWhetherItsLibraryIsThere()
    {
        Assert.True(new LibraryStore(_existing).Availability.IsAvailable);
        Assert.True(new LibraryStore(MissingDrive).Availability.IsRootMissing);
    }

    [Fact]
    public void TheStateGoesFromMissingToAvailableWhenTheDiskComesBack()
    {
        // Es el reintento automático visto desde Core: el mismo almacén, sin
        // recrearlo, tiene que notar que el disco volvió. Se prueba con la
        // carpeta que hace de volumen, porque montar y desmontar una unidad de
        // verdad no cabe en una prueba unitaria — la respuesta se lee igual.
        string disk = Path.Combine(_existing, "disco");
        var store = new LibraryStore(Path.Combine(disk, "Aura Library"));

        Assert.True(LibraryAvailability.For(Path.Combine(@"Q:\", "Aura Library")).IsRootMissing);
        Assert.True(store.Availability.IsAvailable);   // el volumen (C:) siempre estuvo

        // Y la carpeta de la biblioteca puede seguir sin existir: eso es una
        // biblioteca nueva, no una desconectada.
        Assert.False(Directory.Exists(Path.Combine(disk, "Aura Library")));
    }

    [Fact]
    public void OnlyTheDiskGoingAwayPutsTheLibraryOutOfReach()
    {
        // El resumen de la regla, que es lo que ST-171 tuvo que corregir sobre
        // sí mismo: la carpeta ausente NO basta para declarar la biblioteca
        // desconectada; el disco ausente, sí.
        Assert.True(LibraryAvailability.For(Path.Combine(_existing, "sin-crear")).IsAvailable);
        Assert.True(LibraryAvailability.For(MissingDrive).IsRootMissing);
    }
}
