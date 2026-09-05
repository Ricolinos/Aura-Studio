using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// ST-162: el recorte cuadrado de una foto con orientación EXIF salía
/// rectangular. El decodificador de Windows escala <b>antes</b> de orientar y
/// recorta <b>después</b>, así que el escalado se pide en medidas crudas y el
/// recorte en medidas orientadas; calcular las dos en el mismo espacio pedía un
/// cuadrado que no cabía y WIC lo recortaba a lo que hubiera.
///
/// <para>Estas pruebas fijan los dos espacios. La afirmación que resume el bug
/// —<see cref="TheCropAlwaysFitsInsideTheOrientedImage"/>— es que el cuadrado
/// cabe entero adentro de la imagen sobre la que cae.</para>
/// </summary>
public class SquareCropTransformTests
{
    // Orientación 6 (girada un cuarto de vuelta): el archivo mide 400×200 y se
    // ve 200×400. Es el caso exacto que fallaba, devolviendo 100×200.
    private const int RawWidth = 400;
    private const int RawHeight = 200;
    private const int OrientedWidth = 200;
    private const int OrientedHeight = 400;

    [Fact]
    public void ARotatedPhotoIsCroppedInTheSpaceWhereItIsSeen()
    {
        var plan = SquareCropTransform.For(RawWidth, RawHeight, OrientedWidth, OrientedHeight, 320);

        // El lado corto de lo que se VE son 200, y nunca se agranda a 320.
        Assert.Equal(200, plan.OutputSide);
        Assert.Equal(200, plan.CropSide);

        // El escalado va en el espacio crudo, y acá no hay nada que escalar.
        Assert.Equal(400, plan.ScaledWidth);
        Assert.Equal(200, plan.ScaledHeight);

        // El recorte cae sobre la imagen orientada (200 de ancho, 400 de alto):
        // el margen que sobra es VERTICAL. Antes se recortaba desde x=100 —el
        // margen horizontal del espacio crudo—, que ahí ya no existe.
        Assert.True(plan.SwapsSides);
        Assert.Equal(0, plan.CropX);
        Assert.Equal(100, plan.CropY);
    }

    [Fact]
    public void TheCropAlwaysFitsInsideTheOrientedImage()
    {
        var plan = SquareCropTransform.For(RawWidth, RawHeight, OrientedWidth, OrientedHeight, 320);

        (int width, int height) = plan.CropSpace;

        Assert.Equal((200, 400), (width, height));
        Assert.True(plan.CropX + plan.CropSide <= width,
                    $"el recorte se sale por la derecha: {plan.CropX}+{plan.CropSide} > {width}");
        Assert.True(plan.CropY + plan.CropSide <= height,
                    $"el recorte se sale por abajo: {plan.CropY}+{plan.CropSide} > {height}");
    }

    // Las orientaciones 5 a 8 no se distinguen acá y no hace falta: las cuatro
    // giran un cuarto de vuelta y le dan al plan exactamente las mismas medidas
    // orientadas, que es lo único que entra en la cuenta. Una prueba unitaria
    // que compare la 6 con la 8 compararía dos llamadas idénticas y no
    // afirmaría nada; lo que sí puede fallar distinto es el decodificador, y eso
    // se verifica de punta a punta en `tools/ImageResizerCheck` (comprobación 25b).

    [Fact]
    public void WithoutRotationNothingIsSwapped()
    {
        // Orientaciones 1 a 4: se ve como está guardada (la 2, 3 y 4 espejan o
        // giran media vuelta, que no intercambia los lados).
        var plan = SquareCropTransform.For(400, 200, 400, 200, 320);

        Assert.False(plan.SwapsSides);
        Assert.Equal((400, 200), plan.CropSpace);
        Assert.Equal(100, plan.CropX);
        Assert.Equal(0, plan.CropY);
        Assert.Equal(200, plan.OutputSide);
    }

    [Fact]
    public void ATallSourceIsScaledByItsShortSideAndCroppedTopAndBottom()
    {
        // 300×1200 sin rotación, miniatura de 128: el lado corto va exacto a 128
        // y el largo se redondea hacia arriba, para no tener que agrandar nada.
        var plan = SquareCropTransform.For(300, 1200, 300, 1200, 128);

        Assert.Equal(128, plan.ScaledWidth);
        Assert.Equal(512, plan.ScaledHeight);
        Assert.Equal(0, plan.CropX);
        Assert.Equal(192, plan.CropY);
        Assert.Equal(128, plan.OutputSide);
    }

    [Fact]
    public void TheSameImageRotatedGivesTheSameCropOnTheOtherAxis()
    {
        // La misma foto de arriba, guardada horizontal con la rotación en EXIF:
        // 1200×300 en el archivo, 300×1200 a la vista. El escalado se invierte
        // (va en crudas) y el recorte NO (va en orientadas) — que es justo la
        // distinción que ST-162 no hacía.
        var plan = SquareCropTransform.For(1200, 300, 300, 1200, 128);

        Assert.Equal(512, plan.ScaledWidth);
        Assert.Equal(128, plan.ScaledHeight);
        Assert.Equal((128, 512), plan.CropSpace);
        Assert.Equal(0, plan.CropX);
        Assert.Equal(192, plan.CropY);
        Assert.Equal(128, plan.OutputSide);
    }

    [Fact]
    public void ASquareSourceIsOnlyRescaled()
    {
        var plan = SquareCropTransform.For(1000, 1000, 1000, 1000, 320);

        Assert.Equal(320, plan.ScaledWidth);
        Assert.Equal(320, plan.ScaledHeight);
        Assert.Equal(0, plan.CropX);
        Assert.Equal(0, plan.CropY);
        Assert.Equal(320, plan.OutputSide);
    }

    [Fact]
    public void ASquareSourceWithRotationDoesNotCareAboutTheSwap()
    {
        // Una fuente cuadrada con orientación 6 informa las mismas medidas
        // orientadas que crudas: no hay swap que detectar, y tampoco hace falta.
        var plan = SquareCropTransform.For(500, 500, 500, 500, 320);

        Assert.False(plan.SwapsSides);
        Assert.Equal((320, 320), plan.CropSpace);
        Assert.Equal(320, plan.OutputSide);
    }

    [Theory]
    [InlineData(0, 200, 200, 400, 320)]
    [InlineData(400, 0, 200, 400, 320)]
    [InlineData(400, 200, 0, 400, 320)]
    [InlineData(400, 200, 200, 0, 320)]
    [InlineData(400, 200, 200, 400, 0)]
    [InlineData(-400, 200, 200, 400, 320)]
    public void AnUnusableSizeGivesTheEmptyPlan(
        int rawWidth, int rawHeight, int orientedWidth, int orientedHeight, int maxSide)
    {
        var plan = SquareCropTransform.For(rawWidth, rawHeight, orientedWidth, orientedHeight, maxSide);

        Assert.True(plan.IsEmpty);
        Assert.Equal(SquareCropTransform.Empty, plan);
    }
}
