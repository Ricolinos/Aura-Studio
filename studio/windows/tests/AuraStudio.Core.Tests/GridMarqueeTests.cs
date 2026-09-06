using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// El núcleo del arrastre de selección (ST-209). Todo lo que decide el recuadro
/// vive en tipos sin vistas, así que se ejerce entero sin mover un mouse: qué
/// toca, qué selección resulta, y que agrandar y achicar sea reversible.
///
/// <para>Lo único que queda para verificar a mano es el gesto físico — que los
/// eventos lleguen a la capa que captura, y que el desplazamiento automático se
/// sienta bien.</para>
/// </summary>
public class GridMarqueeTests
{
    /// <summary>Una cuadrícula de 3 columnas x 2 filas, tarjetas de 100x100 con 10 de separación.</summary>
    private static Dictionary<string, GridRect> Grid()
    {
        var frames = new Dictionary<string, GridRect>(StringComparer.Ordinal);

        for (int row = 0; row < 2; row++)
        {
            for (int column = 0; column < 3; column++)
            {
                frames[$"{row}-{column}"] = new GridRect(column * 110, row * 110, 100, 100);
            }
        }

        return frames;
    }

    // MARK: - El rectángulo

    [Fact]
    public void ElRecuadroValeEnLasCuatroDirecciones()
    {
        // Arrastrar hacia arriba y a la izquierda es tan válido como al revés:
        // el rectángulo es el mismo.
        GridRect abajo = GridRect.Between(new GridPoint(10, 20), new GridPoint(110, 220));
        GridRect arriba = GridRect.Between(new GridPoint(110, 220), new GridPoint(10, 20));

        Assert.Equal(abajo, arriba);
        Assert.Equal(new GridRect(10, 20, 100, 200), abajo);
    }

    [Fact]
    public void UnRecuadroSinSuperficieNoTocaNada()
    {
        // Un clic sin arrastre: el botón bajó y subió en el mismo punto.
        GridRect punto = GridRect.Between(new GridPoint(50, 50), new GridPoint(50, 50));

        Assert.True(punto.IsEmpty);
        Assert.Empty(GridMarquee.Hits(punto, Grid()));
    }

    [Fact]
    public void TocarseDeCantoNoCuenta()
    {
        // El recuadro termina exactamente donde empieza la tarjeta: no la marca.
        // Es lo que hace que arrastrar entre dos columnas no marque las dos.
        var frames = new Dictionary<string, GridRect>(StringComparer.Ordinal)
        {
            ["a"] = new GridRect(100, 0, 100, 100)
        };

        Assert.Empty(GridMarquee.Hits(new GridRect(0, 0, 100, 100), frames));
        Assert.Equal(["a"], GridMarquee.Hits(new GridRect(0, 0, 101, 100), frames));
    }

    // MARK: - Qué toca

    [Fact]
    public void TocaLoQueSeSolapaAunqueSeaUnaEsquina()
    {
        Dictionary<string, GridRect> frames = Grid();

        // Un recuadro chico sobre la esquina inferior derecha de la primera
        // tarjeta y la superior izquierda de la que sigue en diagonal.
        IReadOnlyList<string> hits = GridMarquee.Hits(new GridRect(95, 95, 20, 20), frames);

        Assert.Equal(["0-0", "0-1", "1-0", "1-1"], hits);
    }

    [Fact]
    public void LoQueTocaSaleEnElOrdenEnQueSeVe()
    {
        // De arriba abajo y de izquierda a derecha, no en el orden del
        // diccionario — que no promete ninguno.
        IReadOnlyList<string> hits = GridMarquee.Hits(new GridRect(0, 0, 400, 400), Grid());

        Assert.Equal(["0-0", "0-1", "0-2", "1-0", "1-1", "1-2"], hits);
    }

    // MARK: - Qué selección resulta

    [Fact]
    public void SinModificadoresElRecuadroReemplazaLaSeleccion()
    {
        IReadOnlyList<string> result = GridMarquee.Selection(
            new GridRect(0, 0, 100, 100), Grid(), ["1-2"], GridSelectionModifiers.None);

        Assert.Equal(["0-0"], result);
    }

    [Fact]
    public void ConMayusculasSumaALaDePartida()
    {
        IReadOnlyList<string> result = GridMarquee.Selection(
            new GridRect(0, 0, 100, 100), Grid(), ["1-2"], GridSelectionModifiers.Extend);

        Assert.Equal(["1-2", "0-0"], result);
    }

    [Fact]
    public void ConControlAlternaRespectoDeLaDePartida()
    {
        // Lo que ya estaba marcado y entra al recuadro SALE: eso es alternar.
        IReadOnlyList<string> result = GridMarquee.Selection(
            new GridRect(0, 0, 220, 100), Grid(), ["0-0", "1-2"], GridSelectionModifiers.Toggle);

        // "0-0" estaba marcado y el recuadro lo toca: sale. "0-1" no estaba y lo
        // toca: entra. "1-2" no lo toca: se queda como estaba.
        Assert.Equal(2, result.Count);
        Assert.DoesNotContain("0-0", result);
        Assert.Contains("0-1", result);
        Assert.Contains("1-2", result);
    }

    [Fact]
    public void ConLasDosTeclasMandaControl()
    {
        // Un gesto que alterna y suma a la vez no significa nada: se queda con
        // la más específica.
        IReadOnlyList<string> conLasDos = GridMarquee.Selection(
            new GridRect(0, 0, 100, 100), Grid(), ["0-0"],
            GridSelectionModifiers.Extend | GridSelectionModifiers.Toggle);

        Assert.Empty(conLasDos);
    }

    // MARK: - El arrastre en curso

    [Fact]
    public void AgrandarYAchicarElRecuadroEsReversible()
    {
        Dictionary<string, GridRect> frames = Grid();
        var drag = new GridMarqueeDrag(new GridPoint(0, 0), [], GridSelectionModifiers.None);

        drag.MoveTo(new GridPoint(50, 50), frames);
        Assert.Equal(["0-0"], drag.Current);

        drag.MoveTo(new GridPoint(400, 400), frames);
        Assert.Equal(6, drag.Current.Count);

        // Y al volver, lo que entró vuelve a salir. Sin congelar la selección de
        // partida esto no pasaría: se irían acumulando.
        SelectionDelta vuelta = drag.MoveTo(new GridPoint(50, 50), frames);

        Assert.Equal(["0-0"], drag.Current);
        Assert.Equal(5, vuelta.Deselected.Count);
        Assert.Empty(vuelta.Selected);
    }

    [Fact]
    public void LaSeleccionDePartidaSeCongelaAlEmpezar()
    {
        Dictionary<string, GridRect> frames = Grid();
        var drag = new GridMarqueeDrag(
            new GridPoint(0, 0), ["1-2"], GridSelectionModifiers.Extend);

        drag.MoveTo(new GridPoint(50, 50), frames);
        drag.MoveTo(new GridPoint(400, 400), frames);
        drag.MoveTo(new GridPoint(50, 50), frames);

        // La de partida sigue ahí después de ir y volver, y no se duplicó.
        Assert.Equal(["1-2", "0-0"], [.. drag.Current]);
    }

    [Fact]
    public void CadaMovimientoDiceSoloLoQueCambio()
    {
        Dictionary<string, GridRect> frames = Grid();
        var drag = new GridMarqueeDrag(new GridPoint(0, 0), [], GridSelectionModifiers.None);

        SelectionDelta primero = drag.MoveTo(new GridPoint(50, 50), frames);
        Assert.Equal(["0-0"], primero.Selected);
        Assert.Empty(primero.Deselected);

        // Moverse dentro de la misma tarjeta no cambia nada: mover el puntero un
        // píxel no puede costar escribir mil propiedades.
        SelectionDelta quieto = drag.MoveTo(new GridPoint(60, 60), frames);
        Assert.True(quieto.IsEmpty);

        SelectionDelta crece = drag.MoveTo(new GridPoint(150, 50), frames);
        Assert.Equal(["0-1"], crece.Selected);
        Assert.Empty(crece.Deselected);
    }

    [Fact]
    public void ElRecuadroQueSeDibujaEsElDelUltimoMovimiento()
    {
        var drag = new GridMarqueeDrag(new GridPoint(30, 40), [], GridSelectionModifiers.None);

        drag.MoveTo(new GridPoint(10, 10), Grid());

        Assert.Equal(new GridRect(10, 10, 20, 30), drag.Rect);
    }

    [Fact]
    public void LasTarjetasQueAparecenDuranteElArrastreCuentan()
    {
        // La cuadrícula se desplaza MIENTRAS se arrastra: lo que entra a pantalla
        // reporta su marco entonces, y el arrastre tiene que verlo.
        var frames = new Dictionary<string, GridRect>(StringComparer.Ordinal)
        {
            ["a"] = new GridRect(0, 0, 100, 100)
        };

        var drag = new GridMarqueeDrag(new GridPoint(0, 0), [], GridSelectionModifiers.None);
        drag.MoveTo(new GridPoint(400, 400), frames);

        frames["b"] = new GridRect(0, 200, 100, 100);
        SelectionDelta despues = drag.MoveTo(new GridPoint(400, 400), frames);

        Assert.Equal(["b"], despues.Selected);
    }

    // MARK: - El mapa de marcos

    [Fact]
    public void ElMapaSeQuedaSoloConLoQueEstaEnPantalla()
    {
        var map = new GridFrameMap();

        map.Report("a", new GridRect(0, 0, 100, 100));
        map.Report("b", new GridRect(110, 0, 100, 100));
        Assert.Equal(2, map.Count);

        // Al salir de pantalla se retira: si no, el arrastre "tocaría" una
        // tarjeta que ya no está donde dice el mapa.
        map.Remove("a");

        Assert.Equal(1, map.Count);
        Assert.Empty(GridMarquee.Hits(new GridRect(0, 0, 50, 50), map.Frames));
    }

    [Fact]
    public void ReportarDosVecesElMismoMarcoLoMueve()
    {
        var map = new GridFrameMap();

        map.Report("a", new GridRect(0, 0, 100, 100));
        map.Report("a", new GridRect(0, 500, 100, 100));

        Assert.Equal(1, map.Count);
        Assert.Empty(GridMarquee.Hits(new GridRect(0, 0, 50, 50), map.Frames));
        Assert.Equal(["a"], GridMarquee.Hits(new GridRect(0, 490, 50, 50), map.Frames));
    }

    // MARK: - Desplazamiento automático

    [Fact]
    public void EnElMedioNoSeDesplaza()
    {
        Assert.Equal(0, GridAutoScroll.SpeedFor(300, 600));
    }

    [Fact]
    public void CercaDelBordeSeDesplazaHaciaEseLado()
    {
        Assert.True(GridAutoScroll.SpeedFor(5, 600) < 0);
        Assert.True(GridAutoScroll.SpeedFor(595, 600) > 0);
    }

    [Fact]
    public void CuantoMasCercaDelBordeMasRapido()
    {
        // Crece con la cercanía, no es un escalón: así se puede ajustar despacio
        // al llegar al borde.
        double lejos = GridAutoScroll.SpeedFor(30, 600);
        double cerca = GridAutoScroll.SpeedFor(5, 600);

        Assert.True(Math.Abs(cerca) > Math.Abs(lejos));
        Assert.True(Math.Abs(cerca) <= GridAutoScroll.DefaultMaxSpeed);
    }

    [Fact]
    public void PasadoElBordeVaAlMaximoYNoMas()
    {
        Assert.Equal(-GridAutoScroll.DefaultMaxSpeed, GridAutoScroll.SpeedFor(-200, 600));
        Assert.Equal(GridAutoScroll.DefaultMaxSpeed, GridAutoScroll.SpeedFor(900, 600));
    }

    [Fact]
    public void ConUnaVentanaDiminutaSigueHabiendoZonaQuieta()
    {
        // Con la ventana más chica que los dos márgenes, se repartirían el alto y
        // cualquier posición desplazaría: el medio tiene que quedarse quieto.
        Assert.Equal(0, GridAutoScroll.SpeedFor(20, 40));
        Assert.True(GridAutoScroll.SpeedFor(1, 40) < 0);
        Assert.True(GridAutoScroll.SpeedFor(39, 40) > 0);
    }

    [Fact]
    public void SinAltoVisibleNoSeDesplaza()
    {
        Assert.Equal(0, GridAutoScroll.SpeedFor(10, 0));
    }
}
