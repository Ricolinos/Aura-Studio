using System.Buffers.Binary;
using AuraStudio.Core.Installer;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// La tabla de particiones que va a leer el bootloader del iPod con su propio
/// driver (D-190). Se prueba entera en memoria: son 512 bytes y no hace falta
/// ningún disco.
/// </summary>
public class MasterBootRecordTests
{
    private static byte[] BuildSector(uint firstLba = 2048, uint sectors = 100_000,
                                      byte type = MasterBootRecord.Fat32LbaType, uint signature = 0)
    {
        byte[] sector = new byte[MasterBootRecord.Size];
        MasterBootRecord.BuildSinglePartition(sector, firstLba, sectors, type, signature);
        return sector;
    }

    [Fact]
    public void ABuiltTableHasTheSignatureAndOneEntry()
    {
        byte[] sector = BuildSector();

        Assert.True(MasterBootRecord.HasValidSignature(sector));
        Assert.Equal(1, MasterBootRecord.UsedEntryCount(sector));
        Assert.Equal(0, MasterBootRecord.FirstUsedEntry(sector));
    }

    [Fact]
    public void TheEntryCarriesWhatWasAskedFor()
    {
        byte[] sector = BuildSector(firstLba: 2048, sectors: 244_190_000);
        MbrPartitionEntry entry = MasterBootRecord.ReadEntry(sector, 0);

        Assert.Equal(MasterBootRecord.Fat32LbaType, entry.Type);
        Assert.Equal(2048u, entry.FirstLba);
        Assert.Equal(244_190_000u, entry.SectorCount);
        // No arrancable: el iPod arranca de la NOR, no del MBR.
        Assert.Equal(0x00, entry.Status);
    }

    [Fact]
    public void TheBootCodeAreaIsLeftEmpty()
    {
        // Un MBR con código sería código que nadie ejecuta y que nadie revisó.
        byte[] sector = BuildSector();
        for (int i = 0; i < 0x1B8; i++)
        {
            Assert.Equal(0, sector[i]);
        }
    }

    [Fact]
    public void TheOtherThreeEntriesStayEmpty()
    {
        byte[] sector = BuildSector();
        for (int i = 1; i < MasterBootRecord.EntryCount; i++)
        {
            Assert.True(MasterBootRecord.ReadEntry(sector, i).IsEmpty);
        }
    }

    [Fact]
    public void TheDiskSignatureIsWrittenWhereWindowsLooksForIt()
    {
        byte[] sector = BuildSector(signature: 0xDEADBEEF);
        Assert.Equal(0xDEADBEEFu, BinaryPrimitives.ReadUInt32LittleEndian(sector.AsSpan(0x1B8)));
    }

    [Fact]
    public void ChsFieldsAreTheOutOfRangeMarkerEveryModernToolWrites()
    {
        // Dejarlos en cero confunde a utilidades antiguas; nadie los lee ya.
        byte[] sector = BuildSector();
        Assert.Equal(0xFE, sector[MasterBootRecord.PartitionTableOffset + 1]);
        Assert.Equal(0xFF, sector[MasterBootRecord.PartitionTableOffset + 2]);
        Assert.Equal(0xFF, sector[MasterBootRecord.PartitionTableOffset + 3]);
        Assert.Equal(0xFE, sector[MasterBootRecord.PartitionTableOffset + 5]);
    }

    // MARK: - Rechazos

    [Fact]
    public void APartitionCannotStartAtSectorZero()
    {
        // Ahí vive la propia tabla.
        byte[] sector = new byte[MasterBootRecord.Size];
        Assert.Throws<ArgumentOutOfRangeException>(
            () => MasterBootRecord.BuildSinglePartition(sector, 0, 1000));
    }

    [Fact]
    public void AnEmptyPartitionIsRejected()
    {
        byte[] sector = new byte[MasterBootRecord.Size];
        Assert.Throws<ArgumentOutOfRangeException>(
            () => MasterBootRecord.BuildSinglePartition(sector, 2048, 0));
    }

    [Fact]
    public void APartitionBeyondThirtyTwoBitAddressingIsRejected()
    {
        // El MBR direcciona en 32 bits: más allá de eso la tabla mentiría.
        byte[] sector = new byte[MasterBootRecord.Size];
        Assert.Throws<ArgumentOutOfRangeException>(
            () => MasterBootRecord.BuildSinglePartition(sector, 2048, uint.MaxValue));
    }

    [Fact]
    public void ASectorTooSmallIsRejected()
    {
        byte[] tooSmall = new byte[128];
        Assert.Throws<ArgumentException>(() => MasterBootRecord.BuildSinglePartition(tooSmall, 2048, 1000));
        Assert.Throws<ArgumentException>(() => MasterBootRecord.ReadEntry(tooSmall, 0));
    }

    [Fact]
    public void TheTableOnlyHasFourEntries()
    {
        byte[] sector = BuildSector();
        Assert.Throws<ArgumentOutOfRangeException>(() => MasterBootRecord.ReadEntry(sector, 4));
        Assert.Throws<ArgumentOutOfRangeException>(() => MasterBootRecord.SetEntryType(sector, -1, 0x0C));
    }

    // MARK: - Lectura y parcheo de una tabla ajena

    [Fact]
    public void AnUnsignedSectorIsNotAPartitionTable()
    {
        Assert.False(MasterBootRecord.HasValidSignature(new byte[MasterBootRecord.Size]));
    }

    [Fact]
    public void TheTypeCanBePatchedWithoutTouchingAnythingElse()
    {
        // Es lo que hay que hacer cuando el particionado lo dejó otra herramienta:
        // diskpart deja 0x07 (IFS) y el bootloader espera FAT32.
        byte[] sector = BuildSector(type: MasterBootRecord.IfsType);
        byte[] before = (byte[])sector.Clone();

        MasterBootRecord.SetEntryType(sector, 0, MasterBootRecord.Fat32LbaType);

        Assert.Equal(MasterBootRecord.Fat32LbaType, MasterBootRecord.ReadEntry(sector, 0).Type);
        // Un solo byte cambió en todo el sector.
        int changed = 0;
        for (int i = 0; i < sector.Length; i++) if (sector[i] != before[i]) changed++;
        Assert.Equal(1, changed);
    }

    [Fact]
    public void AnEmptyTableHasNoUsedEntries()
    {
        byte[] sector = new byte[MasterBootRecord.Size];
        sector[510] = 0x55; sector[511] = 0xAA;
        Assert.Null(MasterBootRecord.FirstUsedEntry(sector));
        Assert.Equal(0, MasterBootRecord.UsedEntryCount(sector));
    }

    // MARK: - Alineación

    [Theory]
    [InlineData(512, 2048u)]
    [InlineData(4096, 256u)]
    [InlineData(1024, 1024u)]
    public void TheFirstSectorIsAlignedToOneMebibyte(int bytesPerSector, uint expected)
    {
        Assert.Equal(expected, MasterBootRecord.AlignedFirstLba(bytesPerSector));
        Assert.Equal(1024 * 1024, (long)MasterBootRecord.AlignedFirstLba(bytesPerSector) * bytesPerSector);
    }

    [Fact]
    public void AnImpossibleSectorSizeIsRejected()
    {
        Assert.Throws<ArgumentOutOfRangeException>(() => MasterBootRecord.AlignedFirstLba(0));
    }
}
