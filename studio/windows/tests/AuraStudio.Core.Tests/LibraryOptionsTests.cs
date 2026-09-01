using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// Las opciones de la biblioteca. Varias no son cosméticas: deciden qué
/// archivos terminan en el iPod y cómo los encuentra el firmware.
/// </summary>
public class LibraryOptionsTests
{
    // MARK: - Valores persistidos

    [Fact]
    public void EveryOptionRoundTripsThroughItsStoredValue()
    {
        // Se guardan como texto para que sobrevivan a que se agregue una
        // opción en medio del enum, y coinciden con los de macOS.
        foreach (CoverArtPolicy value in Enum.GetValues<CoverArtPolicy>())
            Assert.Equal(value, LibraryOptions.ParseCoverArtPolicy(value.RawValue()));

        foreach (MusicOrganization value in Enum.GetValues<MusicOrganization>())
            Assert.Equal(value, LibraryOptions.ParseMusicOrganization(value.RawValue()));

        foreach (MusicFilenameFormat value in Enum.GetValues<MusicFilenameFormat>())
            Assert.Equal(value, LibraryOptions.ParseMusicFilenameFormat(value.RawValue()));

        foreach (AudioQuality value in Enum.GetValues<AudioQuality>())
            Assert.Equal(value, LibraryOptions.ParseAudioQuality(value.RawValue()));

        foreach (PhotoQuality value in Enum.GetValues<PhotoQuality>())
            Assert.Equal(value, LibraryOptions.ParsePhotoQuality(value.RawValue()));
    }

    [Fact]
    public void TheStoredValuesAreTheSameOnesMacOsWrites()
    {
        // Si divergieran, un mismo criterio se leería distinto en cada app.
        Assert.Equal("albumOnly", CoverArtPolicy.AlbumOnly.RawValue());
        Assert.Equal("artistAlbum", MusicOrganization.ArtistAlbum.RawValue());
        Assert.Equal("titleOnly", MusicFilenameFormat.TitleOnly.RawValue());
        Assert.Equal("originalLossless", AudioQuality.OriginalLossless.RawValue());
        Assert.Equal("optimized", PhotoQuality.Optimized.RawValue());
    }

    [Fact]
    public void AnUnknownStoredValueFallsBackToTheSafeDefault()
    {
        // Lo seguro es lo que no pierde calidad ni reorganiza nada solo.
        Assert.Equal(CoverArtPolicy.AlbumOnly, LibraryOptions.ParseCoverArtPolicy("loQueSea"));
        Assert.Equal(MusicOrganization.ArtistAlbum, LibraryOptions.ParseMusicOrganization(null));
        Assert.Equal(AudioQuality.OriginalLossless, LibraryOptions.ParseAudioQuality("futuro"));
        Assert.Equal(PhotoQuality.Optimized, LibraryOptions.ParsePhotoQuality(null));
    }

    // MARK: - Calidad de foto

    [Fact]
    public void ThePhotoQualityUsesTheSameLimitsAsTheResizer()
    {
        // Si la preferencia y el redimensionador discreparan, el usuario elegiría
        // una cosa y en el iPod terminaría otra.
        Assert.Equal(ImageResizePlan.DefaultMaxDimension, PhotoQuality.Optimized.MaxDimension());
        Assert.Equal(ImageResizePlan.FirmwareMaxDimension, PhotoQuality.Hd.MaxDimension());
        Assert.Equal(320, PhotoQuality.Optimized.MaxDimension());
        Assert.Equal(640, PhotoQuality.Hd.MaxDimension());
    }

    // MARK: - Colecciones de fotos (D-228)

    [Fact]
    public void TheDefaultCollectionsMatchWhatTheClassifierSuggests()
    {
        Assert.Equal(["Imágenes", "Fotos", "IA"], LibraryOptions.DefaultPhotoCollections);
    }

    [Fact]
    public void ACollectionWithACommaWouldBreakTheStoredListSoTheCommaGoes()
    {
        // La lista se persiste separada por comas: una coma adentro partiría la
        // entrada en dos al releerla.
        IReadOnlyList<string> result = LibraryOptions.AddPhotoCollection([], "Viaje, 2024");
        Assert.Equal(["Viaje 2024"], result);
    }

    [Fact]
    public void AnEmptyOrRepeatedCollectionIsIgnored()
    {
        IReadOnlyList<string> once = LibraryOptions.AddPhotoCollection([], "Viaje");
        Assert.Equal(once, LibraryOptions.AddPhotoCollection(once, "Viaje"));
        Assert.Equal(once, LibraryOptions.AddPhotoCollection(once, "   "));
        Assert.Equal(once, LibraryOptions.AddPhotoCollection(once, ","));
    }

    [Fact]
    public void RemovingACollectionOnlyTakesItOffTheList()
    {
        // No des-etiqueta las fotos que ya la tenían: eso lo dice el
        // doc-comment y es lo que esta prueba fija — la función solo toca la
        // lista y no recibe items siquiera.
        Assert.Equal(["Fotos"], LibraryOptions.RemovePhotoCollection(["Imágenes", "Fotos"], "Imágenes"));
        Assert.Equal(["Fotos"], LibraryOptions.RemovePhotoCollection(["Fotos"], "NoExiste"));
    }

    // MARK: - Orden de proveedores de carátula (D-203)

    [Fact]
    public void MovingAProviderSwapsItWithItsNeighbour()
    {
        IReadOnlyList<CoverArtProvider> order = CoverArtProviderInfo.DefaultOrder;

        Assert.Equal(
            [CoverArtProvider.FanartTV, CoverArtProvider.CoverArtArchive, CoverArtProvider.Deezer],
            LibraryOptions.Move(order, CoverArtProvider.FanartTV, -1));
    }

    [Fact]
    public void MovingPastTheEdgeChangesNothing()
    {
        // Reordenar algo distinto de lo que el usuario pidió sería peor que no
        // hacer nada.
        IReadOnlyList<CoverArtProvider> order = CoverArtProviderInfo.DefaultOrder;

        Assert.Equal(order, LibraryOptions.Move(order, CoverArtProvider.CoverArtArchive, -1));
        Assert.Equal(order, LibraryOptions.Move(order, CoverArtProvider.Deezer, 1));
    }

    [Fact]
    public void TheProviderOrderRoundTrips()
    {
        string raw = string.Join(",", CoverArtProviderInfo.DefaultOrder.Select(p => p.RawValue()));
        Assert.Equal(CoverArtProviderInfo.DefaultOrder, LibraryOptions.ParseCoverArtProviderOrder(raw));
    }

    [Fact]
    public void AnOrderMissingAProviderGetsItBackAtTheEnd()
    {
        // Un orden incompleto dejaría ese proveedor inalcanzable para siempre.
        IReadOnlyList<CoverArtProvider> order =
            LibraryOptions.ParseCoverArtProviderOrder("deezer");

        Assert.Equal(CoverArtProvider.Deezer, order[0]);
        Assert.Equal(3, order.Count);
        Assert.Contains(CoverArtProvider.CoverArtArchive, order);
        Assert.Contains(CoverArtProvider.FanartTV, order);
    }

    [Fact]
    public void GarbageInTheStoredOrderFallsBackToTheDefault()
    {
        Assert.Equal(CoverArtProviderInfo.DefaultOrder, LibraryOptions.ParseCoverArtProviderOrder("xxx,yyy"));
        Assert.Equal(CoverArtProviderInfo.DefaultOrder, LibraryOptions.ParseCoverArtProviderOrder(null));
    }

    [Fact]
    public void ARepeatedProviderIsNotListedTwice()
    {
        IReadOnlyList<CoverArtProvider> order =
            LibraryOptions.ParseCoverArtProviderOrder("deezer,deezer,coverArtArchive");

        Assert.Equal(3, order.Count);
        Assert.Equal(CoverArtProvider.Deezer, order[0]);
        Assert.Equal(CoverArtProvider.CoverArtArchive, order[1]);
    }
}
