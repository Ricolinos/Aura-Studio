using AuraStudio.Core;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// ST-166: el registro de qué arranque tiene grabado cada iPod. La NOR no se
/// puede leer desde la computadora, así que este registro <b>es</b> lo que la
/// app sabe — y por eso lo que importa acá es qué pasa cuando lo guardado no es
/// lo que se esperaba.
/// </summary>
public class BootloaderRegistryTests
{
    private const string Hash =
        "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";

    private const string OtherHash =
        "fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210";

    // MARK: - Forma de un hash

    [Theory]
    [InlineData(Hash)]
    [InlineData("0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF")]
    public void SixtyFourHexDigitsLookLikeAHash(string value) =>
        Assert.True(BootloaderRegistry.IsSha256(value));

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("unknown")]
    [InlineData("2026-09-05T02:30:00Z")]
    [InlineData("0123456789abcdef")]
    public void AnythingElseDoesNot(string? value) =>
        Assert.False(BootloaderRegistry.IsSha256(value));

    [Fact]
    public void SixtyFourCharactersThatAreNotHexDoNotCount()
    {
        Assert.False(BootloaderRegistry.IsSha256(new string('z', 64)));
    }

    // MARK: - Normalizar lo leído

    [Fact]
    public void AStoredHashSurvivesIntact()
    {
        var registry = BootloaderRegistry.Normalize(
            new Dictionary<string, string?> { ["IPOD-1"] = Hash });

        Assert.Equal(Hash, registry["IPOD-1"]);
    }

    [Fact]
    public void AHashInUppercaseIsTheSameHash()
    {
        // La regla compara cadenas: sin esto, el mismo arranque anotado en
        // mayúsculas se leería como uno distinto y se ofrecería actualizarlo
        // para siempre.
        var registry = BootloaderRegistry.Normalize(
            new Dictionary<string, string?> { ["IPOD-1"] = Hash.ToUpperInvariant() });

        Assert.Equal(Hash, registry["IPOD-1"]);
    }

    [Theory]
    [InlineData("2026-09-05T02:30:00Z")]  // lo que guardaba ST-016 en macOS: una fecha
    [InlineData("")]
    [InlineData("   ")]
    [InlineData(null)]
    [InlineData("cualquier cosa escrita a mano")]
    public void AValueThatIsNotAHashMeansUnknownAndNeverAbsent(string? stored)
    {
        // "unknown" no es "no hay arranque nuestro": es "lo hay, no sabemos
        // cuál". Descartarlo forzaría un DFU innecesario en un iPod que ya
        // estaba instalado.
        var registry = BootloaderRegistry.Normalize(
            new Dictionary<string, string?> { ["IPOD-1"] = stored });

        Assert.Equal(BootloaderUpdate.UnknownBootloader, registry["IPOD-1"]);
        Assert.True(registry.ContainsKey("IPOD-1"));
    }

    [Fact]
    public void EntriesWithoutAKeyAreDropped()
    {
        var registry = BootloaderRegistry.Normalize(new Dictionary<string, string?>
        {
            [""] = Hash,
            ["   "] = Hash,
            ["IPOD-1"] = Hash
        });

        Assert.Equal(["IPOD-1"], registry.Keys);
    }

    [Fact]
    public void NothingStoredIsAnEmptyRegistryAndNotACrash()
    {
        Assert.Empty(BootloaderRegistry.Normalize(null));
        Assert.Empty(BootloaderRegistry.Normalize(new Dictionary<string, string?>()));
    }

    // MARK: - Buscar por disco

    [Fact]
    public void AnUnrecordedDiskHasNoHash()
    {
        var registry = BootloaderRegistry.Normalize(
            new Dictionary<string, string?> { ["IPOD-1"] = Hash });

        Assert.Null(BootloaderRegistry.HashFor(registry, "IPOD-2"));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("  ")]
    public void WithoutADiskKeyThereIsNothingToLookUp(string? diskKey)
    {
        var registry = BootloaderRegistry.Normalize(
            new Dictionary<string, string?> { ["IPOD-1"] = Hash });

        Assert.Null(BootloaderRegistry.HashFor(registry, diskKey));
    }

    // MARK: - Anotar y olvidar

    [Fact]
    public void RecordingADiskStoresItsHash()
    {
        var updated = BootloaderRegistry.WithRecord(null, "IPOD-1", Hash);

        Assert.Equal(Hash, BootloaderRegistry.HashFor(updated, "IPOD-1"));
    }

    [Fact]
    public void RecordingTheSameDiskAgainReplacesItAndDoesNotDuplicate()
    {
        var first = BootloaderRegistry.WithRecord(null, "IPOD-1", OtherHash);
        var second = BootloaderRegistry.WithRecord(first, "IPOD-1", Hash);

        Assert.Single(second);
        Assert.Equal(Hash, BootloaderRegistry.HashFor(second, "IPOD-1"));
    }

    [Fact]
    public void RecordingOneDiskDoesNotTouchTheOthers()
    {
        var registry = BootloaderRegistry.WithRecord(null, "IPOD-1", Hash);
        var updated = BootloaderRegistry.WithRecord(registry, "IPOD-2", OtherHash);

        Assert.Equal(Hash, BootloaderRegistry.HashFor(updated, "IPOD-1"));
        Assert.Equal(OtherHash, BootloaderRegistry.HashFor(updated, "IPOD-2"));
        // Y el registro original no se modificó: quien lo tenga en la mano
        // sigue viendo lo que veía.
        Assert.Single(registry);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void WithoutADiskKeyNothingIsRecorded(string? diskKey)
    {
        var updated = BootloaderRegistry.WithRecord(null, diskKey, Hash);

        Assert.Empty(updated);
    }

    [Fact]
    public void RecordingWithoutAHashStillRecordsThatThereIsOne()
    {
        // El arranque se grabó: eso es un hecho. Cuál, no se pudo calcular
        // (el artefacto no estaba). "unknown" dice exactamente eso.
        var updated = BootloaderRegistry.WithRecord(null, "IPOD-1", null);

        Assert.Equal(BootloaderUpdate.UnknownBootloader,
                     BootloaderRegistry.HashFor(updated, "IPOD-1"));
    }

    [Fact]
    public void ForgettingADiskLeavesNothingBehind()
    {
        var registry = BootloaderRegistry.WithRecord(null, "IPOD-1", Hash);
        var updated = BootloaderRegistry.Without(registry, "IPOD-1");

        Assert.Null(BootloaderRegistry.HashFor(updated, "IPOD-1"));
        Assert.Empty(updated);
    }

    [Fact]
    public void ForgettingADiskThatWasNeverThereChangesNothing()
    {
        var registry = BootloaderRegistry.WithRecord(null, "IPOD-1", Hash);

        Assert.True(BootloaderRegistry.SameRegistry(
            registry, BootloaderRegistry.Without(registry, "IPOD-2")));
    }

    // MARK: - Cuándo NO hay que reescribir el archivo

    [Fact]
    public void RecordingTheSameThingTwiceIsNoChange()
    {
        // Pasa en cada reconexión del mismo iPod. Sin esto se reescribiría el
        // archivo de preferencias cada vez, para dejarlo igual.
        var registry = BootloaderRegistry.WithRecord(null, "IPOD-1", Hash);
        var again = BootloaderRegistry.WithRecord(registry, "IPOD-1", Hash);

        Assert.True(BootloaderRegistry.SameRegistry(registry, again));
    }

    [Fact]
    public void ADifferentHashForTheSameDiskIsAChange()
    {
        var registry = BootloaderRegistry.WithRecord(null, "IPOD-1", Hash);
        var updated = BootloaderRegistry.WithRecord(registry, "IPOD-1", OtherHash);

        Assert.False(BootloaderRegistry.SameRegistry(registry, updated));
    }

    [Fact]
    public void AnAddedDiskIsAChange()
    {
        var registry = BootloaderRegistry.WithRecord(null, "IPOD-1", Hash);
        var updated = BootloaderRegistry.WithRecord(registry, "IPOD-2", Hash);

        Assert.False(BootloaderRegistry.SameRegistry(registry, updated));
    }

    [Fact]
    public void TwoEmptyRegistriesSayTheSameThing()
    {
        Assert.True(BootloaderRegistry.SameRegistry(null, null));
        Assert.True(BootloaderRegistry.SameRegistry(
            null, BootloaderRegistry.Normalize(new Dictionary<string, string?>())));
    }

    // MARK: - Sin clave de disco no se ofrece nada

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void WithoutADiskKeyTheUpdateIsNotOffered(string? diskKey)
    {
        // Sin clave, lo que se grabara no se podría anotar en ningún lado: la
        // oferta volvería en cada conexión, para siempre. Mejor no ofrecerla.
        Assert.Null(BootloaderRegistry.OfferReason(
            registry: null, diskKey: diskKey, embeddedHash: Hash, hasOurFirmware: true));
    }

    [Fact]
    public void TheRuleWouldHaveOfferedItWithoutThatCondition()
    {
        // La condición de arriba es DE VERDAD la que decide: con los mismos
        // datos, la regla pura sí ofrecería (motivo "no sabemos cuál").
        Assert.Equal(BootloaderUpdate.Reason.UnknownBootloader,
                     BootloaderUpdate.ReasonFor(null, Hash, hasOurFirmware: true));
    }

    [Fact]
    public void ADiskRecordedWithAnotherBootloaderIsOfferedTheUpdate()
    {
        var registry = BootloaderRegistry.Normalize(
            new Dictionary<string, string?> { ["IPOD-1"] = OtherHash });

        Assert.Equal(BootloaderUpdate.Reason.DifferentBootloader,
                     BootloaderRegistry.OfferReason(registry, "IPOD-1", Hash, hasOurFirmware: true));
    }

    [Fact]
    public void ADiskRecordedWithAnUnreadableValueIsOfferedItAsUnknown()
    {
        var registry = BootloaderRegistry.Normalize(
            new Dictionary<string, string?> { ["IPOD-1"] = "2026-09-05T02:30:00Z" });

        Assert.Equal(BootloaderUpdate.Reason.UnknownBootloader,
                     BootloaderRegistry.OfferReason(registry, "IPOD-1", Hash, hasOurFirmware: true));
    }

    [Fact]
    public void ADiskAlreadyRunningThisBootloaderIsNotOfferedAnything()
    {
        var registry = BootloaderRegistry.Normalize(
            new Dictionary<string, string?> { ["IPOD-1"] = Hash });

        Assert.Null(BootloaderRegistry.OfferReason(registry, "IPOD-1", Hash, hasOurFirmware: true));
    }

    [Fact]
    public void AFactoryIPodIsOfferedNothingBecauseWhatItNeedsIsToBeInstalled()
    {
        Assert.Null(BootloaderRegistry.OfferReason(
            registry: null, diskKey: "IPOD-1", embeddedHash: Hash, hasOurFirmware: false));
    }

    [Fact]
    public void WithoutAnEmbeddedBootloaderNothingIsOffered()
    {
        // Una build sin `FirmwareFetch.ps1`: ofrecer grabar algo que no existe
        // es peor que no ofrecer nada.
        var registry = BootloaderRegistry.Normalize(
            new Dictionary<string, string?> { ["IPOD-1"] = OtherHash });

        Assert.Null(BootloaderRegistry.OfferReason(registry, "IPOD-1", null, hasOurFirmware: true));
        Assert.Null(BootloaderRegistry.OfferReason(registry, "IPOD-1", "", hasOurFirmware: true));
    }

    // MARK: - La misma decisión, con el hash ya buscado

    [Fact]
    public void TheOverloadThatTakesTheHashDecidesTheSame()
    {
        // Es la que usa la app: el almacén de preferencias ya resolvió la
        // búsqueda por disco y entrega el valor. Las dos formas tienen que
        // decidir igual, o la oferta diría una cosa en las pruebas y otra en
        // pantalla.
        var registry = BootloaderRegistry.Normalize(
            new Dictionary<string, string?> { ["IPOD-1"] = OtherHash });

        Assert.Equal(
            BootloaderRegistry.OfferReason(registry, "IPOD-1", Hash, hasOurFirmware: true),
            BootloaderRegistry.OfferReason("IPOD-1", OtherHash, Hash, hasOurFirmware: true));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void TheOverloadAlsoRefusesWithoutADiskKey(string? diskKey)
    {
        Assert.Null(BootloaderRegistry.OfferReason(diskKey, OtherHash, Hash, hasOurFirmware: true));
    }

    // MARK: - La clave de disco sale del serial USB

    [Fact]
    public void TheDiskKeyIsTheUsbSerial()
    {
        var device = new IPodDiskInfo
        {
            USBIdentity = new USBDeviceIdentity("Apple", "iPod", "000A2700123ABCD",
                                                USBDeviceIdentity.AppleVendorID,
                                                USBDeviceIdentity.IPodClassicProductID)
        };

        Assert.Equal("000A2700123ABCD", device.DiskRecordKey);
        Assert.True(BootloaderRegistry.CanTrack(device.DiskRecordKey));
    }

    [Fact]
    public void AnIPodWithoutASerialCannotBeTracked()
    {
        var device = new IPodDiskInfo
        {
            USBIdentity = new USBDeviceIdentity("Apple", "iPod", null,
                                                USBDeviceIdentity.AppleVendorID,
                                                USBDeviceIdentity.IPodClassicProductID)
        };

        Assert.Null(device.DiskRecordKey);
        Assert.False(BootloaderRegistry.CanTrack(device.DiskRecordKey));
    }

    [Fact]
    public void AnIPodWithoutUsbIdentityCannotBeTrackedEither()
    {
        Assert.Null(new IPodDiskInfo().DiskRecordKey);
    }

    [Fact]
    public void ASerialOfOnlySpacesIsNoSerial()
    {
        var device = new IPodDiskInfo
        {
            USBIdentity = new USBDeviceIdentity("Apple", "iPod", "   ",
                                                USBDeviceIdentity.AppleVendorID,
                                                USBDeviceIdentity.IPodClassicProductID)
        };

        Assert.Null(device.DiskRecordKey);
    }
}
