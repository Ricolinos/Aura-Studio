using System.Buffers.Binary;

namespace AuraStudio.Core.Installer;

/// <param name="Status">0x80 = arrancable, 0x00 = normal.</param>
/// <param name="Type">Identificador de tipo de partición (0x0C = FAT32 con LBA).</param>
/// <param name="FirstLba">Primer sector de la partición, en sectores lógicos del disco.</param>
/// <param name="SectorCount">Cuántos sectores ocupa.</param>
public readonly record struct MbrPartitionEntry(byte Status, byte Type, uint FirstLba, uint SectorCount)
{
    public bool IsEmpty => Type == 0 && SectorCount == 0;
}

/// <summary>
/// Lectura y parcheo del Master Boot Record — solo lo que el instalador
/// necesita, sin escribir una tabla de particiones desde cero.
///
/// <para><b>Por qué existe.</b> El particionado lo hace la herramienta del
/// sistema (`diskpart`), igual que en macOS lo hace `diskutil`: es código
/// probado por Microsoft y no tiene sentido reimplementarlo. Pero el
/// identificador de tipo que deja `create partition primary` no es el que el
/// bootloader del iPod espera leer, y **el bootloader lee la tabla de
/// particiones con su propio driver** (D-190). Cambiar ese byte es un parche de
/// un solo campo sobre el sector 0; hacerlo acá, en código puro y probado, es
/// mucho más seguro que confiar en que una herramienta ponga el valor correcto.</para>
///
/// <para>Nada de esto abre un disco: opera sobre los 512 bytes del sector, que
/// quien llama lee y escribe. Así se puede probar entero en memoria.</para>
/// </summary>
public static class MasterBootRecord
{
    /// <summary>El MBR vive siempre en los primeros 512 bytes, aunque el sector físico sea de 4096.</summary>
    public const int Size = 512;

    /// <summary>Desplazamiento de la tabla de particiones dentro del sector.</summary>
    public const int PartitionTableOffset = 446;

    public const int EntrySize = 16;
    public const int EntryCount = 4;

    /// <summary>FAT32 con direccionamiento LBA — lo que espera el bootloader del iPod.</summary>
    public const byte Fat32LbaType = 0x0C;

    /// <summary>FAT32 con CHS: aceptable de leer, pero no es lo que se escribe.</summary>
    public const byte Fat32ChsType = 0x0B;

    /// <summary>Lo que suele dejar `create partition primary` de diskpart: "IFS" (NTFS/exFAT).</summary>
    public const byte IfsType = 0x07;

    public static bool HasValidSignature(ReadOnlySpan<byte> sector)
        => sector.Length >= Size && sector[510] == 0x55 && sector[511] == 0xAA;

    public static MbrPartitionEntry ReadEntry(ReadOnlySpan<byte> sector, int index)
    {
        ValidateIndex(sector, index);
        ReadOnlySpan<byte> entry = sector.Slice(PartitionTableOffset + index * EntrySize, EntrySize);
        return new MbrPartitionEntry(
            Status: entry[0],
            Type: entry[4],
            FirstLba: BinaryPrimitives.ReadUInt32LittleEndian(entry[8..]),
            SectorCount: BinaryPrimitives.ReadUInt32LittleEndian(entry[12..]));
    }

    /// <summary>
    /// Cambia **solo** el byte de tipo de una entrada. No toca el resto de la
    /// tabla, ni la firma, ni el código de arranque: cuanto menos se escriba en
    /// el sector 0 de un disco ajeno, mejor.
    /// </summary>
    public static void SetEntryType(Span<byte> sector, int index, byte type)
    {
        ValidateIndex(sector, index);
        sector[PartitionTableOffset + index * EntrySize + 4] = type;
    }

    /// <summary>
    /// Índice de la primera entrada con datos, o `null` si la tabla está vacía.
    /// Tras `clean` + `create partition primary` debería ser la 0; se busca en
    /// vez de asumirlo.
    /// </summary>
    public static int? FirstUsedEntry(ReadOnlySpan<byte> sector)
    {
        for (int i = 0; i < EntryCount; i++)
        {
            if (!ReadEntry(sector, i).IsEmpty) return i;
        }
        return null;
    }

    /// <summary>
    /// Cuántas entradas tienen datos. Más de una en el disco del iPod después de
    /// preparar significa que el particionado no quedó como se pidió, y eso se
    /// detiene antes de escribir un sistema de archivos encima.
    /// </summary>
    public static int UsedEntryCount(ReadOnlySpan<byte> sector)
    {
        int count = 0;
        for (int i = 0; i < EntryCount; i++)
        {
            if (!ReadEntry(sector, i).IsEmpty) count++;
        }
        return count;
    }

    /// <summary>
    /// Escribe una tabla con **una sola** partición primaria y la firma del
    /// sector. Deja en cero el área de código de arranque: el iPod no arranca
    /// desde el MBR (su bootloader vive en la NOR), así que un MBR con código
    /// sería código que nadie ejecuta y que nadie revisó.
    ///
    /// <para>Los campos CHS se llenan con el valor "fuera de rango" que usan
    /// todas las herramientas modernas para particiones grandes: nadie los lee
    /// ya, y dejarlos en cero confunde a algunas utilidades antiguas.</para>
    /// </summary>
    /// <param name="sector">Al menos <see cref="Size"/> bytes; se sobrescribe entero.</param>
    /// <param name="firstLba">Primer sector de la partición (en sectores lógicos del disco).</param>
    /// <param name="sectorCount">Sectores de la partición.</param>
    /// <param name="type">Identificador de tipo; para el iPod, <see cref="Fat32LbaType"/>.</param>
    /// <param name="diskSignature">Firma de disco de Windows (offset 0x1B8). Cero es válido.</param>
    public static void BuildSinglePartition(Span<byte> sector, uint firstLba, uint sectorCount,
                                            byte type = Fat32LbaType, uint diskSignature = 0)
    {
        if (sector.Length < Size)
        {
            throw new ArgumentException($"El sector de arranque necesita al menos {Size} bytes.", nameof(sector));
        }
        if (firstLba == 0)
        {
            throw new ArgumentOutOfRangeException(nameof(firstLba), firstLba,
                "una partición no puede empezar en el sector 0: ahí vive la propia tabla");
        }
        if (sectorCount == 0)
        {
            throw new ArgumentOutOfRangeException(nameof(sectorCount), sectorCount, "la partición no puede estar vacía");
        }
        if (firstLba > uint.MaxValue - sectorCount)
        {
            throw new ArgumentOutOfRangeException(nameof(sectorCount), sectorCount,
                "la partición se sale del direccionamiento de 32 bits del MBR");
        }

        sector[..Size].Clear();

        BinaryPrimitives.WriteUInt32LittleEndian(sector[0x1B8..], diskSignature);

        Span<byte> entry = sector.Slice(PartitionTableOffset, EntrySize);
        entry[0] = 0x00;                 // no arrancable: el iPod arranca de la NOR
        entry[1] = 0xFE;                 // CHS de inicio: fuera de rango
        entry[2] = 0xFF;
        entry[3] = 0xFF;
        entry[4] = type;
        entry[5] = 0xFE;                 // CHS de fin: fuera de rango
        entry[6] = 0xFF;
        entry[7] = 0xFF;
        BinaryPrimitives.WriteUInt32LittleEndian(entry[8..], firstLba);
        BinaryPrimitives.WriteUInt32LittleEndian(entry[12..], sectorCount);

        sector[510] = 0x55;
        sector[511] = 0xAA;
    }

    /// <summary>
    /// Primer sector de la partición para un disco con sectores de
    /// <paramref name="bytesPerSector"/>, alineado a 1 MiB — lo que alinean
    /// Windows y macOS desde hace más de una década.
    /// </summary>
    public static uint AlignedFirstLba(int bytesPerSector)
    {
        if (bytesPerSector <= 0) throw new ArgumentOutOfRangeException(nameof(bytesPerSector));
        const int oneMebibyte = 1024 * 1024;
        // Con sectores mayores a 1 MiB (no existen, pero la cuenta no puede dar 0)
        // se cae al primer sector después de la tabla.
        return (uint)Math.Max(1, oneMebibyte / bytesPerSector);
    }

    private static void ValidateIndex(ReadOnlySpan<byte> sector, int index)
    {
        if (sector.Length < Size)
        {
            throw new ArgumentException($"El sector de arranque necesita al menos {Size} bytes.", nameof(sector));
        }
        if (index is < 0 or >= EntryCount)
        {
            throw new ArgumentOutOfRangeException(nameof(index), index, "La tabla MBR tiene 4 entradas.");
        }
    }
}
