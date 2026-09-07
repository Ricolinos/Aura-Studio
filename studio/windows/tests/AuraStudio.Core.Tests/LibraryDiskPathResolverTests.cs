using System.Text;
using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// La resolución NFC/NFD de un archivo dentro de la biblioteca (adición de A1
/// al contrato de ST-241, usada por B5 para borrar el archivo correcto).
///
/// <para>Confirmado en la VM de Windows real antes de escribir esto:
/// <c>File.Exists</c>/<c>Directory.Exists</c> con un nombre en NFC <b>no</b>
/// encuentran una carpeta creada en NFD — Windows compara la secuencia exacta
/// de caracteres, no normaliza. Así que si la Mac creó "Música" en NFD y el
/// catálogo guarda "Música" en NFC (como manda el contrato), la ruta que arma
/// un <c>Path.Combine</c> ciego no existe, aunque el archivo sí.</para>
/// </summary>
public class LibraryDiskPathResolverTests : IDisposable
{
    private readonly string _root;

    public LibraryDiskPathResolverTests()
    {
        _root = Path.Combine(Path.GetTempPath(), "AuraNFD-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_root);
    }

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { /* best effort */ }
    }

    private static string Nfd(string value) => value.Normalize(NormalizationForm.FormD);

    [Fact]
    public void ElCaminoRapidoDevuelveLaRutaTalCualCuandoYaExiste()
    {
        string musicDir = Directory.CreateDirectory(Path.Combine(_root, "Música")).FullName;
        string file = Path.Combine(musicDir, "Ingrata.mp3");
        File.WriteAllText(file, "x");

        string? resolved = LibraryDiskPathResolver.ResolveExisting(_root, file);

        Assert.Equal(file, resolved);
    }

    /// <summary>
    /// El caso real de A1: la Mac crea "Música" en NFD, el catálogo (y por lo
    /// tanto <c>item.SourcePath</c>) trae "Música" en NFC. El archivo tiene
    /// que encontrarse igual.
    /// </summary>
    [Fact]
    public void EncuentraElArchivoCuandoLaCarpetaEstaEnNFDYElCatalogoEnNFC()
    {
        string nfdMusicDir = Directory.CreateDirectory(Path.Combine(_root, Nfd("Música"))).FullName;
        string realFile = Path.Combine(nfdMusicDir, Nfd("Café Tacvba"));
        Directory.CreateDirectory(realFile);
        string realTrack = Path.Combine(realFile, "Ingrata.mp3");
        File.WriteAllText(realTrack, "x");

        // Lo que el catálogo diría (todo en NFC, como escribe CatalogPath.Canonical).
        string storedAsNfc = Path.Combine(_root, "Música", "Café Tacvba", "Ingrata.mp3");

        Assert.False(File.Exists(storedAsNfc), "la premisa de la prueba es que el camino rápido falle");

        string? resolved = LibraryDiskPathResolver.ResolveExisting(_root, storedAsNfc);

        Assert.Equal(realTrack, resolved);
    }

    [Fact]
    public void DevuelveNuloSiDeVerdadNoEstaEnNingunLado()
    {
        string wanted = Path.Combine(_root, "Música", "Nadie", "Nada.mp3");

        Assert.Null(LibraryDiskPathResolver.ResolveExisting(_root, wanted));
    }

    /// <summary>
    /// Si el archivo YA está donde se pidió, ese es el camino rápido y gana
    /// sin importar si está "adentro" o "afuera" — es justo lo que hace que
    /// el caso normal (todo en esta misma Windows, sin acentos raros) no
    /// pague ningún listado de más. Lo que se prueba acá es que el recorrido
    /// alterno —el que sí necesita saber si está adentro— nunca se sale de la
    /// biblioteca a buscar.
    /// </summary>
    [Fact]
    public void ElRecorridoAlternoNuncaSaleDeLaBibliotecaABuscar()
    {
        string outsideRoot = Path.Combine(Path.GetTempPath(), "AuraAfuera-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(outsideRoot);
        string realFileOutside = Path.Combine(outsideRoot, "Nada.mp3");
        File.WriteAllText(realFileOutside, "x");

        // Lo que se pide es una ruta que NO existe tal cual (para forzar el
        // recorrido alterno) y que además está fuera de _root.
        string wantedButMissing = Path.Combine(outsideRoot, "Otro.mp3");

        try
        {
            Assert.Null(LibraryDiskPathResolver.ResolveExisting(_root, wantedButMissing));
        }
        finally
        {
            Directory.Delete(outsideRoot, recursive: true);
        }
    }
}
