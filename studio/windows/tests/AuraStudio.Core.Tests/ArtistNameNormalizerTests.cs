using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// La homologación de artistas (R2-4, ST-117), caso por caso contra
/// <c>docs/normalizacion-artistas.md</c>.
///
/// <para>Los casos son <b>los mismos</b> que los de
/// <c>ArtistNameNormalizerTests.swift</c> a propósito: si las dos apps no dan
/// idéntico resultado, la vista Artistas se parte en dos según desde qué
/// máquina se abrió la biblioteca compartida, y el iPod recibe dos fotos
/// distintas para el mismo artista. Una diferencia acá no se ve como bug: se
/// ve como que la biblioteca "cambió sola".</para>
/// </summary>
public sealed class ArtistNameNormalizerTests
{
    [Theory]
    // El caso base.
    [InlineData("Gorillaz feat. De La Soul", "Gorillaz")]
    // Se corta en el PRIMER separador, no en el último.
    [InlineData("Calle 13 feat. Rubén Blades ft. Café Tacvba", "Calle 13")]
    // Sin distinguir mayúsculas.
    [InlineData("Gorillaz FEAT. De La Soul", "Gorillaz")]
    // `con` como palabra, sin distinguir mayúsculas ni acentos.
    [InlineData("Julieta Venegas CON Juanes", "Julieta Venegas")]
    // Cada entrada de la lista cerrada, una por una.
    [InlineData("Gorillaz feat De La Soul", "Gorillaz")]
    [InlineData("Gorillaz ft. De La Soul", "Gorillaz")]
    [InlineData("Gorillaz ft De La Soul", "Gorillaz")]
    [InlineData("Gorillaz featuring De La Soul", "Gorillaz")]
    [InlineData("Gorillaz + De La Soul", "Gorillaz")]
    [InlineData("Gorillaz with De La Soul", "Gorillaz")]
    [InlineData("Gorillaz con De La Soul", "Gorillaz")]
    public void CortaEnElPrimerSeparador(string credito, string esperado) =>
        Assert.Equal(esperado, ArtistNameNormalizer.PrincipalArtist(credito));

    [Theory]
    // `ft` vive DENTRO de "Daft": no es un token.
    [InlineData("Daft Punk")]
    // `con` dentro de "Confeti": tampoco.
    [InlineData("Confeti de Odio")]
    // `+` pegado no es un token suelto.
    [InlineData("Blink+182")]
    // Nombres reales que contienen un separador como parte del nombre y que
    // por eso existen la lista de excepciones y el ajuste para apagar todo.
    [InlineData("Earth, Wind & Fire")]
    public void NoTocaLoQueNoTieneUnSeparadorComoToken(string credito) =>
        Assert.Equal(credito, ArtistNameNormalizer.PrincipalArtist(credito));

    [Theory]
    // Decisión explícita del dueño: una colaboración con identidad propia es
    // OTRO artista, no el principal con invitados.
    [InlineData("Spacemonkeyz vs. Gorillaz")]
    [InlineData("Spacemonkeyz vs Gorillaz")]
    [InlineData("Spacemonkeyz versus Gorillaz")]
    public void VsNuncaHomologa(string credito) =>
        Assert.Equal(credito, ArtistNameNormalizer.PrincipalArtist(credito));

    [Fact]
    public void UnSeparadorAlPrincipioNoDejaArtistaPrincipal()
    {
        // Recortarlo daría cadena vacía y la pista caería bajo "Artista
        // desconocido" — peor que no hacer nada.
        Assert.Equal("feat. Alguien", ArtistNameNormalizer.PrincipalArtist("feat. Alguien"));
        Assert.Equal("+ Alguien", ArtistNameNormalizer.PrincipalArtist("+ Alguien"));
    }

    [Fact]
    public void SoloSeRecortanLosEspaciosExtremos() =>
        Assert.Equal("Café Tacvba", ArtistNameNormalizer.PrincipalArtist("  Café Tacvba  "));

    [Fact]
    public void ElResultadoNuncaEsVacioSiLaEntradaNoLoEra()
    {
        Assert.Equal("", ArtistNameNormalizer.PrincipalArtist(""));
        Assert.Equal("", ArtistNameNormalizer.PrincipalArtist(null));
        Assert.Equal("", ArtistNameNormalizer.PrincipalArtist("   "));

        foreach (string separator in ArtistNameNormalizer.Separators)
            Assert.NotEqual("", ArtistNameNormalizer.PrincipalArtist("Alguien " + separator + " Otro"));
    }

    [Fact]
    public void ConservaLosEspaciosInternosDelArtistaPrincipal() =>
        Assert.Equal("Los  Fabulosos  Cadillacs",
            ArtistNameNormalizer.PrincipalArtist("Los  Fabulosos  Cadillacs feat. Fito"));

    [Fact]
    public void ElAjusteApagadoDevuelveLaAgrupacionDeAntesDeR2Cuatro()
    {
        var off = ArtistGroupingOptions.Off;

        Assert.Equal("Gorillaz feat. De La Soul",
            ArtistNameNormalizer.PrincipalArtist("Gorillaz feat. De La Soul", off));

        // Apagado sigue recortando los espacios extremos: eso no es
        // homologación, es la limpieza de siempre.
        Assert.Equal("Café Tacvba", ArtistNameNormalizer.PrincipalArtist("  Café Tacvba  ", off));
    }

    [Fact]
    public void LasExcepcionesSeComparanContraElCreditoCompletoSinAcentosNiMayusculas()
    {
        var options = new ArtistGroupingOptions(true, ["Simon + Garfunkel", "Café con Leche"]);

        Assert.Equal("Simon + Garfunkel", ArtistNameNormalizer.PrincipalArtist("Simon + Garfunkel", options));
        Assert.Equal("SIMON + GARFUNKEL", ArtistNameNormalizer.PrincipalArtist("SIMON + GARFUNKEL", options));
        Assert.Equal("Cafe con Leche", ArtistNameNormalizer.PrincipalArtist("Cafe con Leche", options));

        // La excepción es por nombre completo, no por prefijo: un crédito que
        // empieza igual pero sigue distinto sí se homologa.
        Assert.Equal("Simon", ArtistNameNormalizer.PrincipalArtist("Simon + Garfunkel + Otro", options));
    }

    [Fact]
    public void LaListaDeSeparadoresEsLaDelDocumentoYEstaCerrada()
    {
        Assert.Equal(
            new[] { "feat.", "feat", "ft.", "ft", "featuring", "+", "with", "con" },
            ArtistNameNormalizer.Separators);

        Assert.Equal(new[] { "vs.", "vs", "versus" }, ArtistNameNormalizer.NeverJoined);

        // Ninguna entrada de una lista puede estar en la otra: si "vs" cayera
        // entre los separadores, "Spacemonkeyz vs. Gorillaz" desaparecería
        // como artista sin que nadie lo note.
        Assert.Empty(ArtistNameNormalizer.Separators.Intersect(ArtistNameNormalizer.NeverJoined));
    }

    [Fact]
    public void LaClaveDeAgrupacionJuntaLasGrafiasDelMismoPrincipal()
    {
        string uno = ArtistNameNormalizer.PrincipalKey("Gorillaz feat. De La Soul");
        string otro = ArtistNameNormalizer.PrincipalKey("GORILLAZ");

        Assert.Equal(uno, otro);
        Assert.NotEqual(uno, ArtistNameNormalizer.PrincipalKey("Spacemonkeyz vs. Gorillaz"));
    }
}

/// <summary>
/// El efecto de la homologación sobre la agrupación (R2-4, ST-117): lo que el
/// dueño ve, no la función suelta.
/// </summary>
public sealed class ArtistGroupingEffectTests
{
    private static LibraryItem Song(string path, string artist, string album) => new()
    {
        SourcePath = path,
        Kind = LibraryItemKind.Music,
        Metadata = new TrackMetadata { Artist = artist, Album = album, Title = path }
    };

    [Fact]
    public void LaVistaArtistasMuestraUnaSolaFilaPorArtistaPrincipal()
    {
        List<LibraryItem> items =
        [
            Song("a.mp3", "Gorillaz", "Demon Days"),
            Song("b.mp3", "Gorillaz feat. De La Soul", "Demon Days"),
            Song("c.mp3", "Spacemonkeyz vs. Gorillaz", "Laika Come Home")
        ];

        IReadOnlyList<ArtistGroup> artists = LibraryGrouping.Artists(items);

        // Dos filas, no tres: la colaboración cae dentro de "Gorillaz" y el
        // proyecto con identidad propia se queda aparte.
        Assert.Equal(2, artists.Count);
        Assert.Contains(artists, artist => artist.Name == "Gorillaz");
        Assert.Contains(artists, artist => artist.Name == "Spacemonkeyz vs. Gorillaz");
    }

    [Fact]
    public void LasDosGrafiasCaenEnElMismoAlbum()
    {
        List<LibraryItem> items =
        [
            Song("a.mp3", "Gorillaz", "Demon Days"),
            Song("b.mp3", "Gorillaz feat. De La Soul", "Demon Days")
        ];

        AlbumGroup album = Assert.Single(LibraryGrouping.Albums(items));
        Assert.Equal("Gorillaz", album.Artist);
        Assert.Equal(2, album.Items.Count);
    }

    [Fact]
    public void JamasSeReescribeElArtistaDeLaPista()
    {
        List<LibraryItem> items = [Song("b.mp3", "Gorillaz feat. De La Soul", "Demon Days")];

        LibraryGrouping.Artists(items);

        // El crédito completo sigue en la metadata: viaja en el archivo y se
        // sigue viendo en la tabla de canciones.
        Assert.Equal("Gorillaz feat. De La Soul", items[0].Metadata!.Artist);

        // Y la ruta en disco se arma con el valor CRUDO, no con el principal:
        // R2-4 pidió agrupación, no mover archivos ya sincronizados.
        Assert.Equal("Gorillaz feat. De La Soul", LibraryGrouping.AlbumArtistOf(items[0]));
    }

    [Fact]
    public void ConElAjusteApagadoVuelveLaAgrupacionDeAntes()
    {
        List<LibraryItem> items =
        [
            Song("a.mp3", "Gorillaz", "Demon Days"),
            Song("b.mp3", "Gorillaz feat. De La Soul", "Demon Days")
        ];

        Assert.Equal(2, LibraryGrouping.Artists(items, ArtistGroupingOptions.Off).Count);
    }

    [Fact]
    public void UnaExcepcionSacaEseNombreDeLaHomologacion()
    {
        List<LibraryItem> items =
        [
            Song("a.mp3", "Simon + Garfunkel", "Bookends"),
            Song("b.mp3", "Simon", "Solo")
        ];

        var options = new ArtistGroupingOptions(true, ["Simon + Garfunkel"]);

        Assert.Equal(2, LibraryGrouping.Artists(items, options).Count);
        Assert.Single(LibraryGrouping.Artists(items));   // sin la excepción, se juntan
    }
}
