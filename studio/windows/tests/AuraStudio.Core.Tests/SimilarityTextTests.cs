using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// La normalización es la mitad del detector que se puede afirmar caso por
/// caso: si "01 Amor" y "Amor" no llegan al mismo texto, nada del resto
/// funciona.
/// </summary>
public class SimilarityTextTests
{
    // MARK: - Plegado

    [Theory]
    [InlineData("Canción", "cancion")]
    [InlineData("SODA STEREO", "sodastereo")]
    [InlineData("Soda-Stereo", "sodastereo")]
    [InlineData("Soda Stereo", "sodastereo")]
    [InlineData("¡Amor! (1987)", "amor1987")]
    [InlineData("", "")]
    public void AccentsCaseAndPunctuationAllDisappear(string raw, string expected)
        => Assert.Equal(expected, SimilarityText.Alnum(raw));

    [Fact]
    public void TheCaseThatMotivatedTheDetector()
    {
        // ST-063: "SodaStereo" y "Soda-Stereo" tienen que ser el mismo artista.
        Assert.Equal(SimilarityText.Alnum("SodaStereo"), SimilarityText.Alnum("Soda-Stereo"));
    }

    // MARK: - Número de pista al frente

    [Theory]
    [InlineData("01 Amor", "Amor")]
    [InlineData("1. Amor", "Amor")]
    [InlineData("01 - Amor", "Amor")]
    [InlineData("1-01 Amor", "Amor")]
    [InlineData("07) Amor", "Amor")]
    [InlineData("Amor", "Amor")]
    public void ALeadingTrackNumberIsRemoved(string raw, string expected)
        => Assert.Equal(expected, SimilarityText.StripLeadingTrackNumber(raw).Trim());

    [Fact]
    public void ATitleThatIsOnlyANumberSurvives()
    {
        // "7" de Prince, "99" de Toto: vaciarlos sería perder la canción.
        Assert.Equal("7", SimilarityText.StripLeadingTrackNumber("7"));
        Assert.Equal("99", SimilarityText.StripLeadingTrackNumber("99"));
    }

    // MARK: - Título normalizado

    [Fact]
    public void TheTrackNumberAndTheBracketsBothDisappear()
    {
        SimilarityText.NormalizedTitle normalized = SimilarityText.NormalizeTitle("01 Amor (Remasterizado)");
        Assert.Equal("amor", normalized.Core);
        Assert.Contains("remasterizado", normalized.Qualifiers);
    }

    [Fact]
    public void AQualifierIsFoundEvenLooseAtTheEnd()
    {
        // "Amor - Live" no trae paréntesis, y aun así es otra versión.
        SimilarityText.NormalizedTitle normalized = SimilarityText.NormalizeTitle("Amor - Live");
        Assert.Equal("amor", normalized.Core);
        Assert.Contains("live", normalized.Qualifiers);
    }

    [Fact]
    public void ATitleThatIsOnlyAQualifierKeepsItsWord()
    {
        // "Live" a secas es el nombre de la canción, no un calificador: si se
        // vaciara, cualquier otra canción de una palabra le parecería igual.
        Assert.Equal("live", SimilarityText.NormalizeTitle("Live").Core);
    }

    [Fact]
    public void TwoWaysOfWritingTheSameSongNormalizeAlike()
    {
        Assert.Equal(
            SimilarityText.NormalizeTitle("01 Amor").Core,
            SimilarityText.NormalizeTitle("Amor").Core);
    }

    [Fact]
    public void AStudioVersionAndALiveOneDifferInTheirQualifiersNotTheirCore()
    {
        SimilarityText.NormalizedTitle studio = SimilarityText.NormalizeTitle("Amor");
        SimilarityText.NormalizedTitle live = SimilarityText.NormalizeTitle("Amor (En vivo)");

        Assert.Equal(studio.Core, live.Core);
        Assert.Empty(studio.Qualifiers);
        Assert.Contains("vivo", live.Qualifiers);
    }

    // MARK: - Nombre de archivo

    [Theory]
    [InlineData(@"C:\fotos\IMG_0001.jpg", @"C:\fotos\IMG_0001 copia.jpg")]
    [InlineData(@"C:\fotos\IMG_0001.jpg", @"C:\fotos\IMG_0001 (1).jpg")]
    [InlineData(@"C:\fotos\IMG_0001.jpg", @"C:\fotos\IMG_0001 copy 2.jpg")]
    public void ACopyOfAPhotoNormalizesToTheSameStem(string original, string copy)
        => Assert.Equal(SimilarityText.NormalizeStem(original), SimilarityText.NormalizeStem(copy));

    [Fact]
    public void TwoConsecutiveShotsAreNotTheSameStem()
    {
        // IMG_0001 e IMG_0002 son tomas distintas, no una copia.
        Assert.NotEqual(
            SimilarityText.NormalizeStem(@"C:\fotos\IMG_0001.jpg"),
            SimilarityText.NormalizeStem(@"C:\fotos\IMG_0002.jpg"));
    }

    [Fact]
    public void TheYearAtTheEndOfAFileNameIsDropped()
    {
        Assert.Equal(
            SimilarityText.NormalizeStem(@"C:\videos\Vacaciones.mp4"),
            SimilarityText.NormalizeStem(@"C:\videos\Vacaciones (2019).mp4"));
    }

    // MARK: - Parecido

    [Fact]
    public void IdenticalTextsAreOne() => Assert.Equal(1, SimilarityText.Similarity("amor", "amor"));

    [Fact]
    public void OneLetterOfDifferenceIsStillVeryClose()
        => Assert.True(SimilarityText.Similarity("amor", "amar") >= 0.7);

    [Fact]
    public void VeryDifferentLengthsShortCircuitToZero()
    {
        // Se descarta por el largo antes de correr la programación dinámica:
        // en una biblioteca de miles de canciones eso es la diferencia entre
        // instantáneo y no.
        Assert.Equal(0, SimilarityText.Similarity("amor", "amordespuesdelamor"));
    }

    [Fact]
    public void AnEmptyTextIsNotSimilarToAnything()
    {
        Assert.Equal(0, SimilarityText.Similarity("", "amor"));
        Assert.Equal(1, SimilarityText.Similarity("", ""));   // dos vacíos sí son iguales
    }

    [Theory]
    [InlineData("", "abc", 3)]
    [InlineData("abc", "", 3)]
    [InlineData("abc", "abc", 0)]
    [InlineData("gato", "pato", 1)]
    [InlineData("kitten", "sitting", 3)]
    public void LevenshteinCountsTheEdits(string a, string b, int expected)
        => Assert.Equal(expected, SimilarityText.Levenshtein(a, b));

    // MARK: - Formatos para el usuario

    [Theory]
    [InlineData(512, "512 bytes")]
    [InlineData(1000, "1 kB")]
    [InlineData(4_200_000, "4.2 MB")]
    [InlineData(3_000_000_000, "3 GB")]
    public void SizesReadLikeAPersonWouldSayThem(long bytes, string expected)
        => Assert.Equal(expected, SimilarityText.FormatBytes(bytes));

    [Theory]
    [InlineData(204.0, "3:24")]
    [InlineData(60.0, "1:00")]
    [InlineData(5.0, "0:05")]
    [InlineData(null, "--")]
    public void DurationsReadLikeAPlayerShowsThem(double? seconds, string expected)
        => Assert.Equal(expected, SimilarityText.Clock(seconds));
}
