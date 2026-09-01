using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// Las normalizaciones que macOS aplica al leer etiquetas. La librería que lee
/// los contenedores es distinta en cada plataforma (allá AVFoundation, acá no
/// existe); **el resultado no puede serlo**, porque de ahí sale el
/// `biblioteca.json` y lo que termina en el iPod. Esto es lo que lo fija.
/// </summary>
public class TrackTagRulesTests
{
    // MARK: - Año

    [Theory]
    [InlineData("2013-05-01", "2013")]
    [InlineData("2013", "2013")]
    [InlineData("1999-12", "1999")]
    [InlineData("2020-01-01T00:00:00Z", "2020")]
    public void TheYearIsTheFirstFourCharactersOfTheDate(string input, string expected)
    {
        Assert.Equal(expected, TrackTagRules.YearPrefix(input));
    }

    [Theory]
    [InlineData("98")]
    [InlineData("")]
    [InlineData("x")]
    public void AShortValueIsKeptAsItIs(string input)
    {
        // macOS lo devuelve tal cual en vez de descartarlo: un año mal
        // etiquetado se conserva como estaba, no se convierte en nada.
        Assert.Equal(input, TrackTagRules.YearPrefix(input));
    }

    [Fact]
    public void NoDateIsNoYear()
    {
        Assert.Null(TrackTagRules.YearPrefix(null));
    }

    // MARK: - Número de pista

    [Theory]
    [InlineData("3/12", 3)]
    [InlineData("3", 3)]
    [InlineData(" 7 / 15 ", 7)]
    [InlineData("01/10", 1)]
    public void TheTrackNumberSurvivesTheSlash(string input, int expected)
    {
        // El bug concreto de macOS: convertir "3/12" a entero directamente no
        // da nada y la pista se perdía incluso en ID3v2.3.
        Assert.Equal(expected, TrackTagRules.TrackNumberFromSlashed(input));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("A/B")]
    [InlineData("/12")]
    public void SomethingThatIsNotANumberIsNoTrack(string? input)
    {
        Assert.Null(TrackTagRules.TrackNumberFromSlashed(input));
    }

    // MARK: - Átomos de iTunes

    [Fact]
    public void TheITunesAtomCarriesTheNumberInTheThirdAndFourthBytes()
    {
        // [reservado(2)][número(2)][total(2)][reservado(2)], big-endian.
        byte[] atom = [0, 0, 0, 7, 0, 12, 0, 0];
        Assert.Equal(7, TrackTagRules.TrackNumberFromITunesData(atom));

        byte[] bigNumber = [0, 0, 1, 0, 0, 0, 0, 0];   // 256
        Assert.Equal(256, TrackTagRules.TrackNumberFromITunesData(bigNumber));
    }

    [Fact]
    public void ZeroInTheAtomMeansNoNumber()
    {
        // En esos átomos, cero significa "sin número", no "pista cero".
        Assert.Null(TrackTagRules.TrackNumberFromITunesData([0, 0, 0, 0, 0, 5, 0, 0]));
    }

    [Fact]
    public void AShortOrMissingAtomIsIgnored()
    {
        Assert.Null(TrackTagRules.TrackNumberFromITunesData(null));
        Assert.Null(TrackTagRules.TrackNumberFromITunesData([0, 0, 1]));
    }

    // MARK: - El primero que llega gana

    [Fact]
    public void OnceAFieldHasAValueALaterTagDoesNotOverwriteIt()
    {
        // macOS escribe `campo ?? nuevo` en cada asignación. Sin esta regla, el
        // orden en que la librería entrega las etiquetas cambiaría el resultado.
        Assert.Equal("Primero", TrackTagRules.FirstNonEmpty("Primero", "Segundo"));
        Assert.Equal(3, TrackTagRules.FirstPositive(3, 9));
    }

    [Fact]
    public void AnEmptyFieldDoesTakeTheNewValue()
    {
        Assert.Equal("Nuevo", TrackTagRules.FirstNonEmpty(null, "Nuevo"));
        Assert.Equal("Nuevo", TrackTagRules.FirstNonEmpty("", "Nuevo"));
        Assert.Equal("Nuevo", TrackTagRules.FirstNonEmpty("   ", "Nuevo"));
        Assert.Equal(5, TrackTagRules.FirstPositive(null, 5));
        Assert.Equal(5, TrackTagRules.FirstPositive(0, 5));
    }

    [Fact]
    public void AnEmptyTagNeverErasesWhatWasAlreadyThere()
    {
        Assert.Equal("Tenía", TrackTagRules.FirstNonEmpty("Tenía", null));
        Assert.Equal("Tenía", TrackTagRules.FirstNonEmpty("Tenía", "   "));
        Assert.Equal(4, TrackTagRules.FirstPositive(4, null));
        Assert.Equal(4, TrackTagRules.FirstPositive(4, 0));
    }

    [Fact]
    public void SurroundingWhitespaceIsTrimmed()
    {
        Assert.Equal("Artista", TrackTagRules.FirstNonEmpty(null, "  Artista  "));
    }
}
