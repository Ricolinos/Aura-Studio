using System.Buffers.Binary;
using System.Text;

namespace AuraStudio.Core.Installer;

/// <summary>
/// La geometría de un FAT32 concreto: cuántos sectores ocupa cada región y
/// dónde empieza cada una. Todo se calcula acá, sin tocar disco, para poder
/// probarlo entero con datos sintéticos.
/// </summary>
public readonly record struct Fat32Layout
{
    /// <summary>Bytes por sector del dispositivo tal como está conectado AHORA (512 o 4096; ver D-190).</summary>
    public int BytesPerSector { get; init; }

    /// <summary>Sectores por clúster. Potencia de dos, ≤ 128 y con clúster ≤ 32 KiB.</summary>
    public int SectorsPerCluster { get; init; }

    /// <summary>Sectores reservados antes de la primera FAT. 32 es el valor canónico de FAT32.</summary>
    public int ReservedSectors { get; init; }

    /// <summary>Siempre 2: una FAT y su copia. Un FAT32 con una sola FAT es válido pero nadie lo escribe.</summary>
    public int NumberOfFats { get; init; }

    /// <summary>Sectores que ocupa CADA FAT.</summary>
    public uint SectorsPerFat { get; init; }

    /// <summary>Sectores totales de la partición.</summary>
    public uint TotalSectors { get; init; }

    /// <summary>LBA donde empieza la partición dentro del disco (campo <c>BPB_HiddSec</c>).</summary>
    public uint HiddenSectors { get; init; }

    /// <summary>Clúster donde vive el directorio raíz. Siempre 2 en un volumen recién formateado.</summary>
    public uint RootCluster => 2;

    /// <summary>Primer sector de datos (clúster 2).</summary>
    public uint FirstDataSector => (uint)ReservedSectors + (uint)NumberOfFats * SectorsPerFat;

    /// <summary>Clústeres de datos utilizables.</summary>
    public uint CountOfClusters => (TotalSectors - FirstDataSector) / (uint)SectorsPerCluster;

    public int BytesPerCluster => BytesPerSector * SectorsPerCluster;

    /// <summary>Sector del respaldo del sector de arranque. 6 es lo que espera todo el mundo.</summary>
    public int BackupBootSector => 6;

    /// <summary>Sector del FSInfo (y el respaldo va en <c>BackupBootSector + 1</c>).</summary>
    public int FsInfoSector => 1;
}

/// <summary>
/// Escribe las estructuras de un FAT32 recién formateado sobre un
/// <see cref="Stream"/> que representa la partición.
///
/// <b>Por qué existe esto y no se usa el formateador de Windows.</b> El plan de
/// la Fase 2 daba por hecho <c>Format-Volume</c>/<c>diskpart format fs=fat32</c>.
/// Los dos comparten el mismo motor (<c>FormatEx</c>) y ese motor <b>se niega a
/// crear un FAT32 de más de 32 GB</b> — un límite de la herramienta, no del
/// sistema de archivos ni del driver: Windows monta y usa FAT32 de cualquier
/// tamaño sin problema. Un iPod Classic de fábrica tiene 120–160 GB, así que por
/// ese camino el formateo <b>nunca</b> habría funcionado en el aparato real del
/// dueño. En macOS el problema no existe (<c>diskutil eraseDisk FAT32</c> lo hace
/// y ya), y por eso el Swift no tiene nada parecido a este archivo.
///
/// La estructura del formateo queda igual que en macOS
/// (<c>PrivilegedExecutor.eraseAndFormatDisk</c>): primero la herramienta del
/// sistema, y solo si esa no puede, la escritura directa. Allá el segundo paso es
/// <c>newfs_msdos -S 4096</c>; acá es esto.
///
/// El formato está en la especificación pública de Microsoft (FAT32 File System
/// Specification, 1.03): sector de arranque + FSInfo + dos FAT + clúster raíz.
/// Nada de esto es heurística.
/// </summary>
public static class Fat32Formatter
{
    /// <summary>
    /// Tamaño de clúster por tamaño de volumen, la tabla que usa el propio
    /// Windows para FAT32 (expresada en bytes de volumen, no en sectores, para
    /// que valga igual con sectores de 512 y de 4096).
    /// </summary>
    public static int SectorsPerClusterFor(long volumeBytes, int bytesPerSector)
    {
        long targetClusterBytes = volumeBytes switch
        {
            < 260L * 1024 * 1024 => 512,
            < 8L * 1024 * 1024 * 1024 => 4 * 1024,
            < 16L * 1024 * 1024 * 1024 => 8 * 1024,
            < 32L * 1024 * 1024 * 1024 => 16 * 1024,
            _ => 32 * 1024
        };
        // Un clúster nunca puede ser menor que un sector, y el campo del BPB es de
        // un byte: máximo 128 sectores por clúster.
        int sectors = Math.Max(1, (int)(targetClusterBytes / bytesPerSector));
        return Math.Min(128, RoundUpToPowerOfTwo(sectors));
    }

    private static int RoundUpToPowerOfTwo(int value)
    {
        int result = 1;
        while (result < value) result <<= 1;
        return result;
    }

    /// <summary>Menos de 65 525 clústeres sería FAT16, no FAT32 — el driver lo leería como otro sistema de archivos.</summary>
    public const uint MinimumFat32Clusters = 65_525;

    /// <summary>
    /// Calcula la geometría. Lanza si los parámetros no dan un FAT32 válido —
    /// nunca devuelve un layout "casi": escribirlo produciría un volumen que
    /// Windows monta mal o no monta.
    /// </summary>
    public static Fat32Layout ComputeLayout(uint totalSectors, int bytesPerSector, uint hiddenSectors)
    {
        if (bytesPerSector is not (512 or 1024 or 2048 or 4096))
            throw new ArgumentOutOfRangeException(nameof(bytesPerSector), bytesPerSector, "tamaño de sector no soportado por FAT32");
        if (totalSectors < 1024)
            throw new ArgumentOutOfRangeException(nameof(totalSectors), totalSectors, "la partición es demasiado chica");

        const int reserved = 32;
        const int numberOfFats = 2;
        long volumeBytes = (long)totalSectors * bytesPerSector;
        int sectorsPerCluster = SectorsPerClusterFor(volumeBytes, bytesPerSector);

        uint sectorsPerFat = ComputeSectorsPerFat(totalSectors, bytesPerSector, sectorsPerCluster, reserved, numberOfFats);

        var layout = new Fat32Layout
        {
            BytesPerSector = bytesPerSector,
            SectorsPerCluster = sectorsPerCluster,
            ReservedSectors = reserved,
            NumberOfFats = numberOfFats,
            SectorsPerFat = sectorsPerFat,
            TotalSectors = totalSectors,
            HiddenSectors = hiddenSectors
        };

        if (layout.CountOfClusters < MinimumFat32Clusters)
        {
            throw new ArgumentOutOfRangeException(nameof(totalSectors), totalSectors,
                $"con estos parámetros salen {layout.CountOfClusters} clústeres: menos de {MinimumFat32Clusters} no es FAT32");
        }
        return layout;
    }

    /// <summary>
    /// Sectores por FAT: el menor valor que alcanza para describir todos los
    /// clústeres que quedan. La especificación trae una fórmula aproximada; acá se
    /// calcula esa aproximación y después se corrige hacia arriba hasta que la
    /// desigualdad se cumple de verdad — la aproximación puede quedarse corta por
    /// un sector y eso deja la última porción del volumen sin entrada de FAT.
    /// </summary>
    private static uint ComputeSectorsPerFat(uint totalSectors, int bytesPerSector, int sectorsPerCluster, int reserved, int numberOfFats)
    {
        uint entriesPerFatSector = (uint)(bytesPerSector / 4);
        long usable = totalSectors - reserved;

        // Aproximación de la especificación, generalizada a cualquier tamaño de
        // sector: cada sector de FAT describe `entriesPerFatSector` clústeres.
        long divisor = (long)entriesPerFatSector * sectorsPerCluster + numberOfFats;
        uint candidate = (uint)((usable + divisor - 1) / divisor);
        if (candidate == 0) candidate = 1;

        // Corrección: baja mientras sobre, sube mientras falte. Converge en un par
        // de vueltas y deja el valor mínimo exacto.
        while (true)
        {
            long dataSectors = usable - (long)numberOfFats * candidate;
            if (dataSectors <= 0) throw new InvalidOperationException("la partición no alcanza ni para las tablas FAT");
            long clusters = dataSectors / sectorsPerCluster;
            long needed = clusters + 2;
            long capacity = (long)candidate * entriesPerFatSector;
            if (capacity >= needed) break;
            candidate += (uint)Math.Max(1, (needed - capacity + entriesPerFatSector - 1) / entriesPerFatSector);
        }
        return candidate;
    }

    /// <summary>
    /// Etiqueta de volumen tal como va en el BPB y en la entrada de directorio:
    /// 11 bytes, mayúsculas ASCII, rellenada con espacios. Lo que no cabe o no es
    /// representable se reemplaza — nunca se escribe un byte arbitrario en un
    /// campo de longitud fija.
    /// </summary>
    public static string NormalizeLabel(string? label)
    {
        var builder = new StringBuilder(11);
        foreach (char c in (label ?? "").ToUpperInvariant())
        {
            if (builder.Length == 11) break;
            bool ok = char.IsAsciiLetterOrDigit(c) || c is ' ' or '-' or '_';
            builder.Append(ok ? c : '_');
        }
        if (builder.Length == 0) builder.Append("IPOD");
        return builder.ToString().PadRight(11, ' ');
    }

    /// <summary>
    /// Escribe el sector de arranque, su respaldo, el FSInfo (y el suyo), las dos
    /// FAT y el clúster del directorio raíz sobre <paramref name="volume"/>, que
    /// debe estar posicionado en el byte 0 de la <b>partición</b> (no del disco).
    ///
    /// No borra el resto del volumen a propósito: un formateo rápido es
    /// exactamente lo que hacen <c>diskutil</c> y <c>Format-Volume</c>, y borrar
    /// 160 GB por USB tardaría horas sin ganar nada — lo que hace que el volumen
    /// esté vacío son las tablas, no los bytes viejos de los datos.
    /// </summary>
    public static void WriteStructures(Stream volume, Fat32Layout layout, string? label, uint volumeId)
    {
        string normalized = NormalizeLabel(label);
        byte[] boot = BuildBootSector(layout, normalized, volumeId);
        byte[] fsInfo = BuildFsInfoSector(layout);

        WriteSector(volume, layout, 0, boot);
        WriteSector(volume, layout, (uint)layout.FsInfoSector, fsInfo);
        WriteSector(volume, layout, (uint)layout.BackupBootSector, boot);
        WriteSector(volume, layout, (uint)(layout.BackupBootSector + layout.FsInfoSector), fsInfo);

        // Las dos FAT: primer sector con las tres entradas especiales, el resto en
        // cero. Se escribe por bloques grandes: una FAT de un iPod de 160 GB son
        // ~1.2 MB y hacerlo sector por sector sobre USB es lento sin motivo.
        byte[] firstFatSector = new byte[layout.BytesPerSector];
        BinaryPrimitives.WriteUInt32LittleEndian(firstFatSector.AsSpan(0), 0x0FFF_FFF8); // media + EOC
        BinaryPrimitives.WriteUInt32LittleEndian(firstFatSector.AsSpan(4), 0x0FFF_FFFF); // reservada
        BinaryPrimitives.WriteUInt32LittleEndian(firstFatSector.AsSpan(8), 0x0FFF_FFFF); // clúster 2 = raíz, fin de cadena

        byte[] zeros = new byte[layout.BytesPerSector * 64];
        for (int copy = 0; copy < layout.NumberOfFats; copy++)
        {
            uint start = (uint)layout.ReservedSectors + (uint)copy * layout.SectorsPerFat;
            WriteSector(volume, layout, start, firstFatSector);
            WriteZeroSectors(volume, layout, start + 1, layout.SectorsPerFat - 1, zeros);
        }

        // Clúster del directorio raíz: vacío, salvo la entrada de etiqueta de
        // volumen — es lo que hace que el Explorador muestre el nombre.
        byte[] rootCluster = new byte[layout.BytesPerCluster];
        WriteVolumeLabelEntry(rootCluster, normalized);
        volume.Position = (long)layout.FirstDataSector * layout.BytesPerSector;
        volume.Write(rootCluster, 0, rootCluster.Length);
        volume.Flush();
    }

    private static void WriteVolumeLabelEntry(Span<byte> rootCluster, string normalizedLabel)
    {
        // Entrada de directorio de 32 bytes: nombre 8.3 (acá los 11 bytes de la
        // etiqueta) + atributo ATTR_VOLUME_ID (0x08).
        Encoding.ASCII.GetBytes(normalizedLabel, rootCluster[..11]);
        rootCluster[11] = 0x08;
    }

    private static byte[] BuildBootSector(Fat32Layout layout, string normalizedLabel, uint volumeId)
    {
        byte[] sector = new byte[layout.BytesPerSector];
        var span = sector.AsSpan();

        // Salto corto + NOP: ningún cargador lo va a ejecutar acá, pero un volumen
        // sin esos tres bytes lo rechazan varios sistemas.
        span[0] = 0xEB; span[1] = 0x58; span[2] = 0x90;
        Encoding.ASCII.GetBytes("MSWIN4.1", span.Slice(3, 8));

        BinaryPrimitives.WriteUInt16LittleEndian(span.Slice(11, 2), (ushort)layout.BytesPerSector);
        span[13] = (byte)layout.SectorsPerCluster;
        BinaryPrimitives.WriteUInt16LittleEndian(span.Slice(14, 2), (ushort)layout.ReservedSectors);
        span[16] = (byte)layout.NumberOfFats;
        BinaryPrimitives.WriteUInt16LittleEndian(span.Slice(17, 2), 0);      // RootEntCnt: 0 en FAT32
        BinaryPrimitives.WriteUInt16LittleEndian(span.Slice(19, 2), 0);      // TotSec16: 0, se usa el de 32 bits
        span[21] = 0xF8;                                                     // Media: disco fijo
        BinaryPrimitives.WriteUInt16LittleEndian(span.Slice(22, 2), 0);      // FATSz16: 0 en FAT32
        BinaryPrimitives.WriteUInt16LittleEndian(span.Slice(24, 2), 63);     // SecPerTrk (geometría heredada)
        BinaryPrimitives.WriteUInt16LittleEndian(span.Slice(26, 2), 255);    // NumHeads
        BinaryPrimitives.WriteUInt32LittleEndian(span.Slice(28, 4), layout.HiddenSectors);
        BinaryPrimitives.WriteUInt32LittleEndian(span.Slice(32, 4), layout.TotalSectors);
        BinaryPrimitives.WriteUInt32LittleEndian(span.Slice(36, 4), layout.SectorsPerFat);
        BinaryPrimitives.WriteUInt16LittleEndian(span.Slice(40, 2), 0);      // ExtFlags: las dos FAT activas y espejadas
        BinaryPrimitives.WriteUInt16LittleEndian(span.Slice(42, 2), 0);      // FSVer 0.0
        BinaryPrimitives.WriteUInt32LittleEndian(span.Slice(44, 4), layout.RootCluster);
        BinaryPrimitives.WriteUInt16LittleEndian(span.Slice(48, 2), (ushort)layout.FsInfoSector);
        BinaryPrimitives.WriteUInt16LittleEndian(span.Slice(50, 2), (ushort)layout.BackupBootSector);
        span[64] = 0x80;                                                     // DrvNum
        span[66] = 0x29;                                                     // BootSig: hay VolID/VolLab/FilSysType
        BinaryPrimitives.WriteUInt32LittleEndian(span.Slice(67, 4), volumeId);
        Encoding.ASCII.GetBytes(normalizedLabel, span.Slice(71, 11));
        Encoding.ASCII.GetBytes("FAT32   ", span.Slice(82, 8));

        // La firma va SIEMPRE en los bytes 510-511 del sector, aunque el sector
        // mida 4096: no es "el final del sector", es un desplazamiento fijo.
        span[510] = 0x55;
        span[511] = 0xAA;
        return sector;
    }

    private static byte[] BuildFsInfoSector(Fat32Layout layout)
    {
        byte[] sector = new byte[layout.BytesPerSector];
        var span = sector.AsSpan();
        BinaryPrimitives.WriteUInt32LittleEndian(span.Slice(0, 4), 0x4161_5252);   // "RRaA"
        BinaryPrimitives.WriteUInt32LittleEndian(span.Slice(484, 4), 0x6141_7272); // "rrAa"
        // Libres = todos menos el que ocupa el directorio raíz.
        BinaryPrimitives.WriteUInt32LittleEndian(span.Slice(488, 4), layout.CountOfClusters - 1);
        BinaryPrimitives.WriteUInt32LittleEndian(span.Slice(492, 4), layout.RootCluster);
        BinaryPrimitives.WriteUInt32LittleEndian(span.Slice(508, 4), 0xAA55_0000);
        span[510] = 0x55;
        span[511] = 0xAA;
        return sector;
    }

    private static void WriteSector(Stream volume, Fat32Layout layout, uint sector, byte[] data)
    {
        volume.Position = (long)sector * layout.BytesPerSector;
        volume.Write(data, 0, layout.BytesPerSector);
    }

    private static void WriteZeroSectors(Stream volume, Fat32Layout layout, uint firstSector, uint count, byte[] zeroBuffer)
    {
        if (count == 0) return;
        volume.Position = (long)firstSector * layout.BytesPerSector;
        int sectorsPerWrite = zeroBuffer.Length / layout.BytesPerSector;
        uint remaining = count;
        while (remaining > 0)
        {
            int chunk = (int)Math.Min(remaining, (uint)sectorsPerWrite);
            volume.Write(zeroBuffer, 0, chunk * layout.BytesPerSector);
            remaining -= (uint)chunk;
        }
    }
}
