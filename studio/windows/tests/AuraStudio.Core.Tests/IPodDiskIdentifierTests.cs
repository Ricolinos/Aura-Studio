using AuraStudio.Core;
using Xunit;

namespace AuraStudio.Core.Tests;

public class IPodDiskIdentifierTests
{
    private static DiskCandidateInfo IpodCandidate(string bsdName = "disk7") => new(
        BSDName: bsdName,
        Vendor: "Apple Computer, Inc.",
        Model: "HS12YHA", // nombre de media real observado en hardware — no dice "iPod"
        IsRemovable: true,
        IsInternal: false,
        SizeBytes: 120_034_123_776, // tamaño real observado en hardware
        VolumeName: "IPOD");

    // MARK: - Caso: iPod presente (único candidato)

    [Fact]
    public void IpodPresentAlone_IsFound()
    {
        var ipod = IpodCandidate();
        var result = IPodDiskIdentifier.Identify(new[] { ipod });

        Assert.Equal(new DiskIdentificationResult.Found(ipod), result);
    }

    [Fact]
    public void MediaNameNotContainingIpodString_StillMatches()
    {
        // Caso real de esta sesión: diskutil reportó "HS12YHA" (el modelo del
        // disco duro interno), no "iPod" ni "Apple" — el criterio no debe
        // depender de eso.
        var ipod = IpodCandidate();
        Assert.True(ipod.MatchesIPodCriteria);
    }

    // MARK: - Caso: iPod ausente

    [Fact]
    public void NoCandidates_IsNotFound()
    {
        var result = IPodDiskIdentifier.Identify(Array.Empty<DiskCandidateInfo>());
        Assert.IsType<DiskIdentificationResult.NotFound>(result);
    }

    [Fact]
    public void OnlyNonMatchingDisks_IsNotFound()
    {
        var internalDrive = new DiskCandidateInfo(
            BSDName: "disk0", Vendor: "Apple", Model: "APPLE SSD",
            IsRemovable: false, IsInternal: true,
            SizeBytes: 2_000_000_000_000, VolumeName: "Macintosh HD");

        var result = IPodDiskIdentifier.Identify(new[] { internalDrive });
        Assert.IsType<DiskIdentificationResult.NotFound>(result);
    }

    // MARK: - Caso: disco externo de tamaño similar presente (no debe matchear)

    [Fact]
    public void SimilarSizeExternalDiskWithDifferentVendor_IsNotFound()
    {
        // Un SSD externo de terceros, del tamaño parecido a un iPod, pero de
        // otro fabricante — no debe confundirse con el iPod.
        var thirdPartyDrive = new DiskCandidateInfo(
            BSDName: "disk8", Vendor: "SanDisk", Model: "Extreme 55AE",
            IsRemovable: true, IsInternal: false,
            SizeBytes: 122_000_000_000, VolumeName: "Extreme SSD");

        var result = IPodDiskIdentifier.Identify(new[] { thirdPartyDrive });
        Assert.IsType<DiskIdentificationResult.NotFound>(result);
    }

    [Fact]
    public void AppleVendorButWrongSize_IsNotFound()
    {
        // Vendor Apple pero tamaño muy distinto — el tamaño también tiene que
        // coincidir, no alcanza el vendor.
        var wrongSize = new DiskCandidateInfo(
            BSDName: "disk9", Vendor: "Apple", Model: "Some Device",
            IsRemovable: true, IsInternal: false,
            SizeBytes: 32_000_000_000, VolumeName: "OTHER");

        var result = IPodDiskIdentifier.Identify(new[] { wrongSize });
        Assert.IsType<DiskIdentificationResult.NotFound>(result);
    }

    // MARK: - Caso: dos candidatos (ambiguo, nunca "el más probable")

    [Fact]
    public void TwoMatchingCandidates_IsAmbiguousNeverPicksOne()
    {
        var ipod1 = IpodCandidate(bsdName: "disk7");
        var ipod2 = IpodCandidate(bsdName: "disk11"); // p.ej. otro iPod Classic conectado

        var result = IPodDiskIdentifier.Identify(new[] { ipod1, ipod2 });

        var ambiguous = Assert.IsType<DiskIdentificationResult.Ambiguous>(result);
        // Comparación de conjunto (sin orden), igual que en el test Swift.
        Assert.Equal(
            new HashSet<string> { "disk7", "disk11" },
            ambiguous.Candidates.Select(c => c.BSDName).ToHashSet());
    }

    [Fact]
    public void AmbiguousAmongMixedCandidates_IgnoresNonMatchingOnes()
    {
        var ipod1 = IpodCandidate(bsdName: "disk7");
        var ipod2 = IpodCandidate(bsdName: "disk11");
        var unrelated = new DiskCandidateInfo(
            BSDName: "disk0", Vendor: "Apple", Model: "APPLE SSD",
            IsRemovable: false, IsInternal: true,
            SizeBytes: 2_000_000_000_000, VolumeName: "Macintosh HD");

        var result = IPodDiskIdentifier.Identify(new[] { unrelated, ipod1, ipod2 });

        var ambiguous = Assert.IsType<DiskIdentificationResult.Ambiguous>(result);
        Assert.Equal(2, ambiguous.Candidates.Count);
    }

    // MARK: - Criterios individuales

    [Fact]
    public void InternalDiskNeverMatches_EvenIfOtherwiseIdentical()
    {
        var candidate = IpodCandidate() with { IsInternal = true };
        Assert.False(candidate.MatchesIPodCriteria);
    }

    [Fact]
    public void NonRemovableDiskNeverMatches()
    {
        var candidate = IpodCandidate() with { IsRemovable = false };
        Assert.False(candidate.MatchesIPodCriteria);
    }

    // MARK: - ST-016: VID/PID USB como señal de identidad

    private static readonly USBDeviceIdentity IPodClassicUSB = new(
        VendorName: "Rockbox.org", ProductName: "Rockbox media player", SerialNumber: null,
        VendorID: 0x05AC, ProductID: 0x1261);

    /// iPod corriendo Aura/Rockbox con un disco Toshiba de fábrica: el INQUIRY
    /// SCSI dice lo que dice el disco — ni "Apple" ni "iPod". Sin el VID/PID
    /// USB, este aparato era invisible.
    [Fact]
    public void RockboxUSBWithPlainDriveStrings_MatchesByVIDPID()
    {
        var candidate = new DiskCandidateInfo(
            BSDName: "disk7", Vendor: "TOSHIBA", Model: "MK1231GAL",
            IsRemovable: true, IsInternal: false,
            SizeBytes: 120_034_123_776, VolumeName: "IPOD",
            USB: IPodClassicUSB);

        Assert.True(candidate.MatchesIPodCriteria);
    }

    /// El VID/PID no salta las reglas duras: interno/no removible o un tamaño
    /// imposible siguen descartando.
    [Fact]
    public void VIDPIDDoesNotBypassHardRules()
    {
        var internalDisk = new DiskCandidateInfo(
            BSDName: "disk0", Vendor: "", Model: "", IsRemovable: false, IsInternal: true,
            SizeBytes: 120_034_123_776, VolumeName: null, USB: IPodClassicUSB);
        Assert.False(internalDisk.MatchesIPodCriteria);

        var absurdSize = new DiskCandidateInfo(
            BSDName: "disk8", Vendor: "", Model: "", IsRemovable: true, IsInternal: false,
            SizeBytes: 1_000_000, VolumeName: null, USB: IPodClassicUSB);
        Assert.False(absurdSize.MatchesIPodCriteria);
    }

    /// Un iPad (0x05AC, otro PID) con las cadenas de un disco cualquiera no
    /// pasa: el PID es lo que identifica al iPod Classic.
    [Fact]
    public void OtherApplePID_DoesNotMatch()
    {
        var ipad = new DiskCandidateInfo(
            BSDName: "disk9", Vendor: "", Model: "", IsRemovable: true, IsInternal: false,
            SizeBytes: 64_000_000_000, VolumeName: null,
            USB: new USBDeviceIdentity("Apple Inc.", "iPad", null, 0x05AC, 0x12AB));

        Assert.False(ipad.MatchesIPodCriteria);
    }
}
