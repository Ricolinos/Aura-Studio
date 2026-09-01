using AuraStudio.Core.Networking;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// La carátula recomendada (R2-3, ST-118), número por número contra
/// <c>docs/caratula-recomendada.md</c>.
///
/// <para>"Parecido" no sirve: si las dos apps recomiendan tapas distintas para
/// el mismo disco, el dueño ve la biblioteca cambiar sola según desde qué
/// máquina la abrió. Estas pruebas son las que sostienen que el documento, la
/// app de macOS y esta digan lo mismo.</para>
/// </summary>
public sealed class AlbumCoverScoringTests
{
    private static readonly AlbumFacts Album = new("Demon Days", "2005", 15);

    private static AlbumCoverCandidate Candidate(
        AlbumCoverEdition edition, AlbumCoverSource source = AlbumCoverSource.CoverArtArchive) =>
        new([1, 2, 3], source, null) { Edition = edition };

    // MARK: - La tabla de puntaje

    [Fact]
    public void CadaCriterioValeLoQueDiceElDocumento()
    {
        Assert.Equal(50, AlbumCoverScoring.Score(new AlbumCoverEdition(Title: "Demon Days"), Album));
        Assert.Equal(25, AlbumCoverScoring.Score(new AlbumCoverEdition(Year: "2005"), Album));
        Assert.Equal(15, AlbumCoverScoring.Score(new AlbumCoverEdition(TrackCount: 15), Album));
        Assert.Equal(6, AlbumCoverScoring.Score(new AlbumCoverEdition(Status: "Official"), Album));
        Assert.Equal(2, AlbumCoverScoring.Score(new AlbumCoverEdition(Country: "FR"), Album));
        Assert.Equal(4, AlbumCoverScoring.Score(new AlbumCoverEdition(Country: "MX"), Album));
        Assert.Equal(10, AlbumCoverScoring.Score(new AlbumCoverEdition(IsFrontCover: true), Album));
    }

    [Fact]
    public void ElMaximoAlcanzableEs110()
    {
        var perfect = new AlbumCoverEdition(
            Title: "Demon Days", Year: "2005", TrackCount: 15,
            Status: "Official", Country: "XW", IsFrontCover: true);

        Assert.Equal(110, AlbumCoverScoring.Score(perfect, Album));
        Assert.Equal(AlbumCoverScoring.MaximumScore, AlbumCoverScoring.Score(perfect, Album));
    }

    [Fact]
    public void ElTituloSeComparaNormalizadoYDosVaciosNoCoinciden()
    {
        Assert.Equal(50, AlbumCoverScoring.Score(new AlbumCoverEdition(Title: "  demon dáys "), Album));

        // Dos títulos vacíos NO son coincidencia: si lo fueran, cualquier
        // edición sin título ganaría 50 puntos sobre un álbum sin título.
        Assert.Equal(0, AlbumCoverScoring.Score(new AlbumCoverEdition(Title: ""), new AlbumFacts("", null, 0)));
        Assert.Equal(0, AlbumCoverScoring.Score(AlbumCoverEdition.Unknown, new AlbumFacts(null, null, 0)));
    }

    [Fact]
    public void UnConteoDeCeroNuncaCoincide()
    {
        // "No sé cuántas pistas tiene" no es lo mismo que "coincide en cero".
        Assert.Equal(0, AlbumCoverScoring.Score(new AlbumCoverEdition(TrackCount: 0), new AlbumFacts(null, null, 0)));
    }

    [Fact]
    public void ElPaisPreferidoAcumulaConElDeDeclararPais()
    {
        foreach (string country in new[] { "XW", "MX", "US", "GB", "mx" })
            Assert.Equal(4, AlbumCoverScoring.Score(new AlbumCoverEdition(Country: country), Album));
    }

    [Fact]
    public void NadaDeAbajoPuedeCompensarLaFaltaDeAlgoDeArriba()
    {
        // El invariante que sostiene el orden de importancia de la tabla: todo
        // lo que está debajo del título suma 62, menos que título + año (75).
        int belowTitle = AlbumCoverScoring.TrackCountPoints + AlbumCoverScoring.OfficialPoints +
                         AlbumCoverScoring.CountryPoints + AlbumCoverScoring.PreferredCountryPoints +
                         AlbumCoverScoring.FrontCoverPoints + AlbumCoverScoring.YearPoints;

        Assert.True(belowTitle - AlbumCoverScoring.YearPoints <
                    AlbumCoverScoring.TitlePoints + AlbumCoverScoring.YearPoints);

        var wrongTitle = new AlbumCoverEdition(
            Title: "Otro disco", Year: "2005", TrackCount: 15,
            Status: "Official", Country: "MX", IsFrontCover: true);

        var rightTitleAndYear = new AlbumCoverEdition(Title: "Demon Days", Year: "2005");

        Assert.True(AlbumCoverScoring.Score(rightTitleAndYear, Album) >
                    AlbumCoverScoring.Score(wrongTitle, Album));
    }

    // MARK: - El umbral

    [Fact]
    public void ElUmbralEs85YLoAlcanzanLasDosCombinacionesMinimasDelDocumento()
    {
        Assert.Equal(85, AlbumCoverScoring.AutoApplyThreshold);

        var titleYearFront = new AlbumCoverEdition(Title: "Demon Days", Year: "2005", IsFrontCover: true);
        Assert.Equal(85, AlbumCoverScoring.Score(titleYearFront, Album));
        Assert.True(AlbumCoverScoring.CanApplyWithoutAsking(AlbumCoverScoring.Score(titleYearFront, Album)));

        var titleTracksOfficialCountryFront = new AlbumCoverEdition(
            Title: "Demon Days", TrackCount: 15, Status: "Official", Country: "MX", IsFrontCover: true);
        Assert.Equal(85, AlbumCoverScoring.Score(titleTracksOfficialCountryFront, Album));
    }

    [Fact]
    public void LoQueDeliberadamenteNoAlcanzaElUmbral()
    {
        // Solo el título: el caso que el umbral existe para frenar. "Greatest
        // Hits" coincide de título con el de cualquier otro artista.
        int onlyTitle = AlbumCoverScoring.Score(new AlbumCoverEdition(Title: "Demon Days"), Album);
        Assert.Equal(50, onlyTitle);
        Assert.False(AlbumCoverScoring.CanApplyWithoutAsking(onlyTitle));

        // Título + todas las señales menores, sin año ni pistas: 70.
        int withoutCorroboration = AlbumCoverScoring.Score(
            new AlbumCoverEdition(Title: "Demon Days", Status: "Official", Country: "MX", IsFrontCover: true),
            Album);
        Assert.Equal(70, withoutCorroboration);
        Assert.False(AlbumCoverScoring.CanApplyWithoutAsking(withoutCorroboration));
    }

    [Fact]
    public void UnaCandidataDeDeezerSolaNuncaAlcanzaElUmbral()
    {
        // Deezer no trae año, ni pistas, ni estatus, ni país: su techo es 50.
        var deezer = Candidate(new AlbumCoverEdition(Title: "Demon Days"), AlbumCoverSource.Deezer);
        AlbumCoverCandidate ranked = Assert.Single(AlbumCoverScoring.Rank([deezer], Album));

        Assert.Equal(50, ranked.Score);
        Assert.False(ranked.CanApplyWithoutAsking);
    }

    // MARK: - Desempates

    [Fact]
    public void AIgualPuntajeGanaLaQueTieneTapaFrontal()
    {
        var sinFrontal = Candidate(new AlbumCoverEdition(
            Title: "Demon Days", Status: "Official", Country: "XW"));
        var conFrontal = Candidate(new AlbumCoverEdition(Title: "Demon Days", IsFrontCover: true));

        // Los dos suman 60; decide la tapa frontal.
        Assert.Equal(60, AlbumCoverScoring.Score(sinFrontal.Edition, Album));
        Assert.Equal(60, AlbumCoverScoring.Score(conFrontal.Edition, Album));
        Assert.Same(conFrontal.Edition, AlbumCoverScoring.Recommended([sinFrontal, conFrontal], Album)!.Edition);
    }

    [Fact]
    public void DespuesDeLaFrontalDecideLaEdicionOficial()
    {
        var oficial = Candidate(new AlbumCoverEdition(Title: "Demon Days", Status: "Official", IsFrontCover: true));
        var noOficial = Candidate(new AlbumCoverEdition(
            Title: "Demon Days", Country: "FR", IsFrontCover: true, Status: "Bootleg"));

        Assert.Equal(66, AlbumCoverScoring.Score(oficial.Edition, Album));
        Assert.Equal(62, AlbumCoverScoring.Score(noOficial.Edition, Album));
        Assert.Same(oficial.Edition, AlbumCoverScoring.Recommended([noOficial, oficial], Album)!.Edition);
    }

    [Fact]
    public void LaEdicionMasAntiguaGanaYLaQueNoTieneAnoVaAlFinal()
    {
        var reedicion = Candidate(new AlbumCoverEdition(Title: "Demon Days", Year: "2015", IsFrontCover: true));
        var original = Candidate(new AlbumCoverEdition(Title: "Demon Days", Year: "1999", IsFrontCover: true));
        var sinAno = Candidate(new AlbumCoverEdition(Title: "Demon Days", IsFrontCover: true));

        // Ninguna coincide en año con el álbum (2005), así que empatan en 60 y
        // decide el desempate por año.
        IReadOnlyList<AlbumCoverCandidate> ranked =
            AlbumCoverScoring.Rank([sinAno, reedicion, original], Album);

        Assert.Equal("1999", ranked[0].Edition.Year);
        Assert.Equal("2015", ranked[1].Edition.Year);
        Assert.Null(ranked[2].Edition.Year);
    }

    [Fact]
    public void CoverArtArchiveVaAntesQueDeezer()
    {
        var deezer = Candidate(new AlbumCoverEdition(Title: "Demon Days"), AlbumCoverSource.Deezer);
        var archive = Candidate(new AlbumCoverEdition(Title: "Demon Days"));

        Assert.Equal(AlbumCoverSource.CoverArtArchive,
            AlbumCoverScoring.Recommended([deezer, archive], Album)!.Source);
    }

    [Fact]
    public void ElOrdenDeDescubrimientoGarantizaUnOrdenTotal()
    {
        // Dos candidatas idénticas en todo: sin este último desempate, el
        // orden quedaría indefinido y dos corridas podrían recomendar distinto.
        var edition = new AlbumCoverEdition(Title: "Demon Days", Year: "2005", IsFrontCover: true);
        var primera = new AlbumCoverCandidate([1], AlbumCoverSource.CoverArtArchive, "primera") { Edition = edition };
        var segunda = new AlbumCoverCandidate([2], AlbumCoverSource.CoverArtArchive, "segunda") { Edition = edition };

        IReadOnlyList<AlbumCoverCandidate> ranked = AlbumCoverScoring.Rank([primera, segunda], Album);

        Assert.Equal("primera", ranked[0].Detail);
        Assert.Equal(0, ranked[0].DiscoveryOrder);
        Assert.Equal(1, ranked[1].DiscoveryOrder);

        // Y el mismo insumo da el mismo orden siempre.
        Assert.Equal(
            ranked.Select(c => c.Detail),
            AlbumCoverScoring.Rank([primera, segunda], Album).Select(c => c.Detail));
    }

    [Fact]
    public void LaListaQueVeElUsuarioVaEnElMismoOrdenQueLaRecomendacion()
    {
        var floja = Candidate(new AlbumCoverEdition(Title: "Otro"));
        var buena = Candidate(new AlbumCoverEdition(
            Title: "Demon Days", Year: "2005", TrackCount: 15, Status: "Official",
            Country: "MX", IsFrontCover: true));

        IReadOnlyList<AlbumCoverCandidate> ranked = AlbumCoverScoring.Rank([floja, buena], Album);

        Assert.Equal(ranked[0], AlbumCoverScoring.Recommended([floja, buena], Album));
        Assert.Equal(110, ranked[0].Score);
    }

    [Fact]
    public void SinCandidatasNoHayRecomendada() =>
        Assert.Null(AlbumCoverScoring.Recommended([], Album));
}
