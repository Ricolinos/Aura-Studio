using System.Globalization;
using System.IO.Compression;
using System.Text;

namespace AuraStudio.Core;

/// <summary>Una entrada del árbol instalado: ruta dentro del zip, tamaño sin comprimir y CRC-32.</summary>
public readonly record struct InstallManifestEntry(string Path, long Size, uint Crc32);

/// <summary>Qué hay que escribir y qué hay que borrar para pasar de un árbol instalado al nuevo.</summary>
public sealed record InstallManifestDelta(IReadOnlyList<string> ToExtract, IReadOnlyList<string> ToDelete)
{
    public bool IsEmpty => ToExtract.Count == 0 && ToDelete.Count == 0;
    public int TotalOperations => ToExtract.Count + ToDelete.Count;
}

/// <summary>
/// ST-058 / `CONTRATO-firmware-studio.md` v11: actualizaciones selectivas.
///
/// Actualizar extraía el `rockbox.zip` completo sobre el iPod — 9,431 archivos
/// en Aura, y cada archivo chico paga su ida y vuelta USB+FAT: minutos. Entre
/// releases consecutivos reales cambian ~5 archivos (~2 MB), porque las builds
/// de Rockbox son reproducibles. Este módulo es la contabilidad que lo
/// aprovecha:
///
/// - <see cref="EntriesFromZip"/>: la lista (ruta, tamaño, CRC-32) del zip,
///   leída de su directorio central — no se calcula ningún hash ni se extrae
///   nada.
/// - `.rockbox/aura/install_manifest.cfg`: lo que Studio dejó instalado la
///   última vez (los firmwares lo ignoran). Es POR ÁRBOL (v10): viaja con su
///   árbol al dormir/despertar y nunca se espeja a los dormidos.
/// - <see cref="Delta"/>: qué extraer (nuevo o cambiado) y qué borrar
///   (desapareció del zip — la extracción-merge de antes dejaba huérfanos para
///   siempre).
///
/// La decisión delta-vs-completo y el respaldo a extracción completa viven en
/// quien instala: cualquier duda — sin manifiesto, ilegible, error a mitad —
/// cae a la extracción de siempre.
///
/// <para><b>Diferencia con macOS, deliberada:</b> el Swift lee el directorio
/// central invocando `/usr/bin/unzip -lv` y parseando su tabla de texto con una
/// expresión regular de columnas. Acá no hace falta un subproceso ni un parser:
/// <c>ZipArchiveEntry.Crc32</c> del BCL expone el CRC del directorio central
/// directamente. El **formato del archivo** `install_manifest.cfg` es
/// idéntico byte a byte — es contrato, y un iPod escrito desde una Mac tiene
/// que poder actualizarse desde Windows y al revés.</para>
/// </summary>
public sealed record InstallManifest
{
    public const string HeaderLine = "# aura-install-manifest v1";
    public const string RelativePath = ".rockbox/aura/install_manifest.cfg";

    /// <summary>Prefijo del árbol del firmware. Nada fuera de acá se borra jamás.</summary>
    public const string TreePrefix = ".rockbox/";

    /// <summary>Tag del Release del que salió este árbol, si se conoce.</summary>
    public string? Tag { get; init; }

    /// <summary>Ruta → entrada. Solo archivos, nunca directorios.</summary>
    public IReadOnlyDictionary<string, InstallManifestEntry> Entries { get; init; }
        = new Dictionary<string, InstallManifestEntry>(StringComparer.Ordinal);

    // MARK: - Zip

    /// <summary>
    /// Entradas del zip según su directorio central, sin extraer nada. Filtra
    /// directorios (entradas cuyo nombre termina en separador: el BCL les deja
    /// <c>Name</c> vacío).
    /// </summary>
    /// <exception cref="InvalidDataException">
    /// El zip no abre, o no trae ninguna entrada de archivo. Un `rockbox.zip`
    /// válido nunca está vacío acá: siempre trae `.rockbox/…`.
    /// </exception>
    public static IReadOnlyDictionary<string, InstallManifestEntry> EntriesFromZip(string zipPath)
    {
        using var archive = ZipFile.OpenRead(zipPath);
        var entries = new Dictionary<string, InstallManifestEntry>(StringComparer.Ordinal);

        foreach (ZipArchiveEntry entry in archive.Entries)
        {
            if (string.IsNullOrEmpty(entry.Name)) continue;      // directorio
            // Las rutas del zip siempre usan "/" (APPNOTE 4.4.17.1); se
            // conservan tal cual porque son la clave del contrato.
            entries[entry.FullName] = new InstallManifestEntry(entry.FullName, entry.Length, entry.Crc32);
        }

        if (entries.Count == 0)
        {
            throw new InvalidDataException("El archivo de firmware no contiene ninguna entrada.");
        }
        return entries;
    }

    // MARK: - install_manifest.cfg

    /// <summary>
    /// Formato del contrato v11: cabecera, `tag: <valor>` opcional, y una línea
    /// por archivo con `<crc 8 hex> <tamaño> <ruta>`, ordenadas por ruta.
    /// Terminadores `\n` — nunca CRLF: es el mismo archivo que escribe macOS.
    /// </summary>
    public string Serialize()
    {
        var sb = new StringBuilder();
        sb.Append(HeaderLine).Append('\n');
        if (Tag is { Length: > 0 })
        {
            sb.Append("tag: ").Append(Tag).Append('\n');
        }
        foreach (InstallManifestEntry entry in Entries.Values.OrderBy(e => e.Path, StringComparer.Ordinal))
        {
            sb.Append(entry.Crc32.ToString("x8", CultureInfo.InvariantCulture))
              .Append(' ')
              .Append(entry.Size.ToString(CultureInfo.InvariantCulture))
              .Append(' ')
              .Append(entry.Path)
              .Append('\n');
        }
        return sb.ToString();
    }

    /// <summary>
    /// `null` si el texto no empieza con la cabecera v1 (otra versión, o no es
    /// un manifiesto): quien llama cae a extracción completa. Las líneas que no
    /// se entienden se saltan — un manifiesto a medias vale menos que uno
    /// completo, pero mucho más que ninguno.
    /// </summary>
    public static InstallManifest? Parse(string text)
    {
        string[] lines = text.Split('\n');
        if (lines.Length == 0 || lines[0].Trim() != HeaderLine) return null;

        string? tag = null;
        var entries = new Dictionary<string, InstallManifestEntry>(StringComparer.Ordinal);

        foreach (string raw in lines.Skip(1))
        {
            string line = raw.TrimEnd('\r');
            if (line.StartsWith("tag: ", StringComparison.Ordinal))
            {
                tag = line["tag: ".Length..].Trim();
                continue;
            }

            // <crc 8 hex> <tamaño> <ruta…> — la ruta puede traer espacios, así
            // que solo se parten los dos primeros campos.
            string[] parts = line.Split(' ', 3);
            if (parts.Length != 3) continue;
            if (parts[0].Length != 8) continue;
            if (!uint.TryParse(parts[0], NumberStyles.HexNumber, CultureInfo.InvariantCulture, out uint crc)) continue;
            if (!long.TryParse(parts[1], NumberStyles.None, CultureInfo.InvariantCulture, out long size)) continue;
            if (parts[2].Length == 0) continue;

            entries[parts[2]] = new InstallManifestEntry(parts[2], size, crc);
        }

        return new InstallManifest { Tag = string.IsNullOrEmpty(tag) ? null : tag, Entries = entries };
    }

    /// <summary>`null` si no está o no se puede leer — quien llama extrae completo.</summary>
    public static InstallManifest? Read(string volumeRoot)
    {
        if (string.IsNullOrWhiteSpace(volumeRoot)) return null;
        string path = System.IO.Path.Combine(volumeRoot, RelativePath.Replace('/', System.IO.Path.DirectorySeparatorChar));
        try
        {
            return File.Exists(path) ? Parse(File.ReadAllText(path)) : null;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return null;
        }
    }

    public void Write(string volumeRoot)
    {
        string path = System.IO.Path.Combine(volumeRoot, RelativePath.Replace('/', System.IO.Path.DirectorySeparatorChar));
        Directory.CreateDirectory(System.IO.Path.GetDirectoryName(path)!);
        // Sin BOM: el archivo lo escribe también macOS y lo puede leer el firmware.
        File.WriteAllText(path, Serialize(), new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
    }

    // MARK: - Diff

    /// <summary>
    /// Qué escribir y qué borrar. Una entrada se conserva solo si coinciden
    /// **tamaño y CRC-32**: cualquiera de los dos distinto significa reescribir.
    ///
    /// Lo que se borra está acotado a <see cref="TreePrefix"/> a propósito:
    /// pase lo que pase con un manifiesto corrupto o ajeno, esto **jamás**
    /// puede proponer borrar la música del usuario.
    /// </summary>
    public static InstallManifestDelta Delta(
        IReadOnlyDictionary<string, InstallManifestEntry> installed,
        IReadOnlyDictionary<string, InstallManifestEntry> updated)
    {
        var toExtract = new List<string>();
        foreach ((string path, InstallManifestEntry entry) in updated)
        {
            if (installed.TryGetValue(path, out InstallManifestEntry old)
                && old.Size == entry.Size && old.Crc32 == entry.Crc32)
            {
                continue;
            }
            toExtract.Add(path);
        }

        var toDelete = installed.Keys
            .Where(path => !updated.ContainsKey(path) && path.StartsWith(TreePrefix, StringComparison.Ordinal))
            .ToList();

        toExtract.Sort(StringComparer.Ordinal);
        toDelete.Sort(StringComparer.Ordinal);
        return new InstallManifestDelta(toExtract, toDelete);
    }
}
