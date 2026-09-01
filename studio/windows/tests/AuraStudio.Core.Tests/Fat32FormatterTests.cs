using System.Buffers.Binary;
using System.Text;
using AuraStudio.Core.Installer;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// El formateador FAT32 propio, comprobado contra la especificación pública de
/// Microsoft (FAT32 File System Specification 1.03) sin tocar ningún disco:
/// <c>WriteStructures</c> escribe sobre un <see cref="Stream"/>, así que una
/// partición chica en memoria alcanza para verificar cada estructura byte a byte.
///
/// Existe porque este es el código más peligroso de todo el port — escribe las
/// tablas de un volumen real — y llegó sin ninguna prueba. Lo que estos casos
/// **no** pueden verificar es que Windows monte de verdad el volumen resultante
/// en el iPod físico; eso queda en la lista de validación con el dueño.
/// </summary>
public class Fat32FormatterTests
{
    // 64 MiB con sectores de 512 B: lo más chico que sigue siendo un FAT32
    // legítimo (más de 65 525 clústeres) y entra holgado en memoria.
    private const int Sector = 512;
    private const uint TotalSectors = 64u * 1024 * 1024 / Sector;

    private static (MemoryStream Volume, Fat32Layout Layout) Format(
        uint totalSectors = TotalSectors, int bytesPerSector = Sector,
        string? label = "IPOD", uint hiddenSectors = 2048)
    {
        Fat32Layout layout = Fat32Formatter.ComputeLayout(totalSectors, bytesPerSector, hiddenSectors);
        var volume = new MemoryStream();
        Fat32Formatter.WriteStructures(volume, layout, label, volumeId: 0x1234ABCD);
        return (volume, layout);
    }

    private static byte[] ReadSector(MemoryStream volume, Fat32Layout layout, uint sector)
    {
        byte[] buffer = new byte[layout.BytesPerSector];
        volume.Position = (long)sector * layout.BytesPerSector;
        volume.ReadExactly(buffer);
        return buffer;
    }

    // MARK: - Geometría

    [Fact]
    public void RejectsSectorSizesFat32DoesNotDefine()
    {
        Assert.Throws<ArgumentOutOfRangeException>(() => Fat32Formatter.ComputeLayout(TotalSectors, 511, 0));
        Assert.Throws<ArgumentOutOfRangeException>(() => Fat32Formatter.ComputeLayout(TotalSectors, 8192, 0));
    }

    [Fact]
    public void RejectsAPartitionTooSmallToBeFat32()
    {
        // Menos de 65 525 clústeres sería FAT16: el driver lo leería como otro
        // sistema de archivos. Nunca se devuelve un layout "casi".
        Assert.Throws<ArgumentOutOfRangeException>(() => Fat32Formatter.ComputeLayout(100, Sector, 0));
        Assert.Throws<ArgumentOutOfRangeException>(() => Fat32Formatter.ComputeLayout(20_000, Sector, 0));
    }

    [Theory]
    [InlineData(64u * 1024 * 1024)]
    [InlineData(8L * 1024 * 1024 * 1024)]
    [InlineData(120L * 1024 * 1024 * 1024)]
    [InlineData(160L * 1024 * 1024 * 1024)]
    public void RealisticIPodSizesProduceAValidFat32(long volumeBytes)
    {
        var layout = Fat32Formatter.ComputeLayout((uint)(volumeBytes / Sector), Sector, 2048);

        Assert.True(layout.CountOfClusters >= Fat32Formatter.MinimumFat32Clusters);
        // La invariante que de verdad importa: cada clúster tiene su entrada en
        // la FAT. Si esto falla, la última porción del volumen queda inaccesible.
        long entriesPerFat = (long)layout.SectorsPerFat * (layout.BytesPerSector / 4);
        Assert.True(entriesPerFat >= layout.CountOfClusters + 2,
                    $"la FAT describe {entriesPerFat} entradas y hacen falta {layout.CountOfClusters + 2}");
        Assert.Equal(0, layout.BytesPerCluster % layout.BytesPerSector);
        Assert.True(layout.BytesPerCluster <= 32 * 1024);
    }

    [Fact]
    public void TheDeviceSectorSizeIsRespected()
    {
        // D-190: el bootloader lee la tabla de particiones con su propio driver;
        // un tamaño de sector fijo desde la PC produce un volumen que Windows
        // escribe sin error pero que el iPod no arranca. Se usa el del disco.
        // Con sectores de 4096 el clúster mínimo también es 4096, así que hace
        // falta medio giga para pasar los 65 525 clústeres que definen FAT32.
        var layout = Fat32Formatter.ComputeLayout(512u * 1024 * 1024 / 4096, 4096, 2048);
        Assert.Equal(4096, layout.BytesPerSector);

        var volume = new MemoryStream();
        Fat32Formatter.WriteStructures(volume, layout, "IPOD", 1);
        byte[] boot = ReadSector(volume, layout, 0);
        Assert.Equal(4096, BinaryPrimitives.ReadUInt16LittleEndian(boot.AsSpan(11)));
        Assert.Equal(0x55, boot[510]);
        Assert.Equal(0xAA, boot[511]);
    }

    // MARK: - Sector de arranque

    [Fact]
    public void TheBootSectorCarriesTheBpbTheSpecificationRequires()
    {
        (MemoryStream volume, Fat32Layout layout) = Format();
        byte[] boot = ReadSector(volume, layout, 0);

        Assert.Equal(layout.BytesPerSector, BinaryPrimitives.ReadUInt16LittleEndian(boot.AsSpan(11)));
        Assert.Equal(layout.SectorsPerCluster, boot[13]);
        Assert.Equal(layout.ReservedSectors, BinaryPrimitives.ReadUInt16LittleEndian(boot.AsSpan(14)));
        Assert.Equal(layout.NumberOfFats, boot[16]);

        // En FAT32 estos tres van SIEMPRE en cero; si no, el driver lo lee como FAT16.
        Assert.Equal(0, BinaryPrimitives.ReadUInt16LittleEndian(boot.AsSpan(17)));   // RootEntCnt
        Assert.Equal(0, BinaryPrimitives.ReadUInt16LittleEndian(boot.AsSpan(19)));   // TotSec16
        Assert.Equal(0, BinaryPrimitives.ReadUInt16LittleEndian(boot.AsSpan(22)));   // FATSz16

        Assert.Equal(0xF8, boot[21]);                                                 // Media: disco fijo
        Assert.Equal(layout.HiddenSectors, BinaryPrimitives.ReadUInt32LittleEndian(boot.AsSpan(28)));
        Assert.Equal(layout.TotalSectors, BinaryPrimitives.ReadUInt32LittleEndian(boot.AsSpan(32)));
        Assert.Equal(layout.SectorsPerFat, BinaryPrimitives.ReadUInt32LittleEndian(boot.AsSpan(36)));
        Assert.Equal(0u, BinaryPrimitives.ReadUInt32LittleEndian(boot.AsSpan(44)) - 2);  // RootClus = 2
        Assert.Equal(1, BinaryPrimitives.ReadUInt16LittleEndian(boot.AsSpan(48)));       // FSInfo
        Assert.Equal(6, BinaryPrimitives.ReadUInt16LittleEndian(boot.AsSpan(50)));       // BkBootSec
        Assert.Equal("FAT32   ", Encoding.ASCII.GetString(boot, 82, 8));
        Assert.Equal(0x55, boot[510]);
        Assert.Equal(0xAA, boot[511]);
    }

    [Fact]
    public void TheBackupBootSectorIsAnExactCopy()
    {
        // Sector 6: es de donde se recupera un volumen cuyo sector 0 se dañó.
        (MemoryStream volume, Fat32Layout layout) = Format();
        Assert.Equal(ReadSector(volume, layout, 0), ReadSector(volume, layout, 6));
    }

    [Fact]
    public void TheHiddenSectorsFieldCarriesTheStartOfThePartition()
    {
        // BPB_HiddSec mal puesto es exactamente el síntoma de D-190: la tabla se
        // escribe sin error y el bootloader busca la partición en otro lado.
        (MemoryStream volume, Fat32Layout layout) = Format(hiddenSectors: 63);
        byte[] boot = ReadSector(volume, layout, 0);
        Assert.Equal(63u, BinaryPrimitives.ReadUInt32LittleEndian(boot.AsSpan(28)));
    }

    // MARK: - FSInfo

    [Fact]
    public void FsInfoCarriesItsThreeSignatures()
    {
        (MemoryStream volume, Fat32Layout layout) = Format();
        foreach (uint sector in new uint[] { 1, 7 })   // el propio y su respaldo
        {
            byte[] fsInfo = ReadSector(volume, layout, sector);
            Assert.Equal(0x41615252u, BinaryPrimitives.ReadUInt32LittleEndian(fsInfo.AsSpan(0)));
            Assert.Equal(0x61417272u, BinaryPrimitives.ReadUInt32LittleEndian(fsInfo.AsSpan(484)));
            Assert.Equal(0xAA550000u, BinaryPrimitives.ReadUInt32LittleEndian(fsInfo.AsSpan(508)));
        }
    }

    // MARK: - Tablas FAT

    [Fact]
    public void BothFatsStartWithTheThreeReservedEntries()
    {
        (MemoryStream volume, Fat32Layout layout) = Format();

        for (int copy = 0; copy < layout.NumberOfFats; copy++)
        {
            uint start = (uint)layout.ReservedSectors + (uint)copy * layout.SectorsPerFat;
            byte[] fat = ReadSector(volume, layout, start);

            Assert.Equal(0x0FFFFFF8u, BinaryPrimitives.ReadUInt32LittleEndian(fat.AsSpan(0)));   // media + EOC
            Assert.Equal(0x0FFFFFFFu, BinaryPrimitives.ReadUInt32LittleEndian(fat.AsSpan(4)));   // reservada
            // Clúster 2 = directorio raíz, fin de cadena: sin esto el raíz no existe.
            Assert.Equal(0x0FFFFFFFu, BinaryPrimitives.ReadUInt32LittleEndian(fat.AsSpan(8)));
            Assert.Equal(0u, BinaryPrimitives.ReadUInt32LittleEndian(fat.AsSpan(12)));           // clúster 3 libre
        }
    }

    [Fact]
    public void TheRestOfTheFatIsZeroed()
    {
        // Un volumen recién formateado tiene todos los clústeres libres; si
        // quedaran bytes viejos, el driver vería cadenas inventadas.
        (MemoryStream volume, Fat32Layout layout) = Format();
        uint start = (uint)layout.ReservedSectors;
        Assert.All(ReadSector(volume, layout, start + 1), b => Assert.Equal(0, b));
        Assert.All(ReadSector(volume, layout, start + layout.SectorsPerFat - 1), b => Assert.Equal(0, b));
    }

    // MARK: - Directorio raíz y etiqueta

    [Fact]
    public void TheRootDirectoryCarriesTheVolumeLabel()
    {
        (MemoryStream volume, Fat32Layout layout) = Format(label: "IPOD");
        volume.Position = (long)layout.FirstDataSector * layout.BytesPerSector;
        byte[] entry = new byte[32];
        volume.ReadExactly(entry);

        Assert.Equal("IPOD       ", Encoding.ASCII.GetString(entry, 0, 11));
        Assert.Equal(0x08, entry[11]);   // ATTR_VOLUME_ID
    }

    [Theory]
    [InlineData("IPOD", "IPOD       ")]
    [InlineData("ipod", "IPOD       ")]
    [InlineData("", "IPOD       ")]
    [InlineData(null, "IPOD       ")]
    [InlineData("NOMBRE MUY LARGO PARA FAT", "NOMBRE MUY ")]
    [InlineData("Ñoño*", "_O_O_      ")]
    public void TheLabelIsAlwaysElevenSafeBytes(string? input, string expected)
    {
        // Nunca se escribe un byte arbitrario en un campo de longitud fija.
        string normalized = Fat32Formatter.NormalizeLabel(input);
        Assert.Equal(11, normalized.Length);
        Assert.Equal(expected, normalized);
    }

    [Fact]
    public void TheFirstDataSectorLandsAfterTheReservedAreaAndBothFats()
    {
        (_, Fat32Layout layout) = Format();
        Assert.Equal((uint)layout.ReservedSectors + 2 * layout.SectorsPerFat, layout.FirstDataSector);
    }
}
