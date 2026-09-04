using System.IO.Compression;
using System.Text;
using AuraStudio.Core;
using AuraStudio.Core.Installer;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// ST-058 / contrato v11: el manifiesto de instalación y el delta que evita
/// reescribir 9,431 archivos para cambiar cinco. Port de la lógica del
/// `InstallManifest.swift` de macOS — el **formato del archivo** es contrato
/// compartido, así que los casos de serialización son deliberadamente estrictos.
/// </summary>
public class InstallManifestTests : IDisposable
{
    private readonly string _root;

    public InstallManifestTests()
    {
        _root = Path.Combine(Path.GetTempPath(), "AuraManifest-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_root);
    }

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { /* best effort */ }
    }

    private static Dictionary<string, InstallManifestEntry> Entries(params (string Path, long Size, uint Crc)[] items)
        => items.ToDictionary(i => i.Path, i => new InstallManifestEntry(i.Path, i.Size, i.Crc), StringComparer.Ordinal);

    private string MakeZip(params (string Path, string Contents)[] files)
    {
        string path = Path.Combine(_root, "rockbox-" + Guid.NewGuid().ToString("N") + ".zip");
        using var zip = ZipFile.Open(path, ZipArchiveMode.Create);
        foreach ((string entryPath, string contents) in files)
        {
            ZipArchiveEntry entry = zip.CreateEntry(entryPath);
            using var writer = new StreamWriter(entry.Open());
            writer.Write(contents);
        }
        return path;
    }

    // MARK: - Lectura del zip

    [Fact]
    public void ReadsPathSizeAndCrcFromTheZip()
    {
        string zip = MakeZip((".rockbox/rockbox.ipod", "hola"), (".rockbox/codecs/mpa.codec", "mundo!"));
        var entries = InstallManifest.EntriesFromZip(zip);

        Assert.Equal(2, entries.Count);
        Assert.Equal(4, entries[".rockbox/rockbox.ipod"].Size);
        Assert.Equal(6, entries[".rockbox/codecs/mpa.codec"].Size);
        // El CRC-32 de "hola" es un valor fijo y conocido: si el BCL leyera el
        // CRC de otro lado (o lo recalculara mal) esto lo delata.
        Assert.Equal(0x6FA0F988u, entries[".rockbox/rockbox.ipod"].Crc32);
    }

    [Fact]
    public void DirectoryEntriesAreNotFiles()
    {
        string path = Path.Combine(_root, "condirs.zip");
        using (var zip = ZipFile.Open(path, ZipArchiveMode.Create))
        {
            zip.CreateEntry(".rockbox/");
            zip.CreateEntry(".rockbox/codecs/");
            using var writer = new StreamWriter(zip.CreateEntry(".rockbox/config.cfg").Open());
            writer.Write("x");
        }

        var entries = InstallManifest.EntriesFromZip(path);
        Assert.Single(entries);
        Assert.True(entries.ContainsKey(".rockbox/config.cfg"));
    }

    [Fact]
    public void AnEmptyZipIsRejected()
    {
        string path = Path.Combine(_root, "vacio.zip");
        using (ZipFile.Open(path, ZipArchiveMode.Create)) { }
        Assert.Throws<InvalidDataException>(() => InstallManifest.EntriesFromZip(path));
    }

    // MARK: - Formato del archivo (contrato)

    [Fact]
    public void SerializedFormatMatchesTheContract()
    {
        var manifest = new InstallManifest
        {
            Tag = "v0.4.4-beta",
            Entries = Entries((".rockbox/b.txt", 20, 0x0000000A), (".rockbox/a.txt", 10, 0xDEADBEEF))
        };

        // Cabecera, tag, y una línea por archivo ORDENADA por ruta, con el CRC
        // en 8 hex minúsculas. Saltos "\n", nunca CRLF: es el mismo archivo que
        // escribe la app de macOS.
        Assert.Equal(
            "# aura-install-manifest v1\n" +
            "tag: v0.4.4-beta\n" +
            "deadbeef 10 .rockbox/a.txt\n" +
            "0000000a 20 .rockbox/b.txt\n",
            manifest.Serialize());
    }

    [Fact]
    public void SerializeAndParseRoundTrip()
    {
        var original = new InstallManifest
        {
            Tag = "v1.2.3",
            Entries = Entries((".rockbox/x", 1, 1), (".rockbox/con espacio.cfg", 99, 0xFFFFFFFF))
        };

        InstallManifest? parsed = InstallManifest.Parse(original.Serialize());

        Assert.NotNull(parsed);
        Assert.Equal("v1.2.3", parsed!.Tag);
        Assert.Equal(2, parsed.Entries.Count);
        // Una ruta con espacios sobrevive: solo se parten los dos primeros campos.
        Assert.Equal(99, parsed.Entries[".rockbox/con espacio.cfg"].Size);
        Assert.Equal(0xFFFFFFFFu, parsed.Entries[".rockbox/con espacio.cfg"].Crc32);
    }

    [Fact]
    public void ManifestWithoutTagOmitsTheLine()
    {
        var manifest = new InstallManifest { Entries = Entries((".rockbox/a", 1, 2)) };
        Assert.DoesNotContain("tag:", manifest.Serialize(), StringComparison.Ordinal);
        Assert.Null(InstallManifest.Parse(manifest.Serialize())!.Tag);
    }

    [Fact]
    public void AnotherHeaderIsNotAManifest()
    {
        // Una versión futura del formato no se interpreta a medias: se rechaza
        // entera y quien llama extrae completo.
        Assert.Null(InstallManifest.Parse("# aura-install-manifest v2\ndeadbeef 1 .rockbox/a\n"));
        Assert.Null(InstallManifest.Parse("cualquier cosa"));
        Assert.Null(InstallManifest.Parse(""));
    }

    [Fact]
    public void UnreadableLinesAreSkippedWithoutLosingTheRest()
    {
        InstallManifest? parsed = InstallManifest.Parse(
            "# aura-install-manifest v1\n" +
            "deadbeef 10 .rockbox/bueno\n" +
            "nohex 10 .rockbox/malo\n" +
            "deadbee 10 .rockbox/corto\n" +
            "deadbeef diez .rockbox/malo2\n" +
            "deadbeef 10\n" +
            "cafebabe 20 .rockbox/bueno2\n");

        Assert.NotNull(parsed);
        Assert.Equal(2, parsed!.Entries.Count);
        Assert.True(parsed.Entries.ContainsKey(".rockbox/bueno"));
        Assert.True(parsed.Entries.ContainsKey(".rockbox/bueno2"));
    }

    [Fact]
    public void CrLfLineEndingsStillParse()
    {
        // Un manifiesto que pasó por una herramienta de Windows no debe volverse
        // ilegible: se acepta al leer, pero al escribir siempre sale con "\n".
        InstallManifest? parsed = InstallManifest.Parse(
            "# aura-install-manifest v1\r\ntag: v1.0.0\r\ndeadbeef 10 .rockbox/a\r\n");
        Assert.NotNull(parsed);
        Assert.Equal("v1.0.0", parsed!.Tag);
        Assert.Single(parsed.Entries);
    }

    [Fact]
    public void WriteAndReadOnAVolume()
    {
        var manifest = new InstallManifest { Tag = "v0.4.4-beta", Entries = Entries((".rockbox/a", 5, 7)) };
        manifest.Write(_root);

        string written = Path.Combine(_root, ".rockbox", "aura", "install_manifest.cfg");
        Assert.True(File.Exists(written));
        // Sin BOM: lo lee también la app de macOS.
        byte[] bytes = File.ReadAllBytes(written);
        Assert.NotEqual(0xEF, bytes[0]);

        InstallManifest? read = InstallManifest.Read(_root);
        Assert.NotNull(read);
        Assert.Equal("v0.4.4-beta", read!.Tag);
        Assert.Equal(5, read.Entries[".rockbox/a"].Size);
    }

    [Fact]
    public void ReadingAVolumeWithoutManifestIsNull()
    {
        Assert.Null(InstallManifest.Read(_root));
        Assert.Null(InstallManifest.Read(""));
    }

    // MARK: - Delta

    [Fact]
    public void UnchangedEntriesAreNotRewritten()
    {
        var installed = Entries((".rockbox/a", 10, 1), (".rockbox/b", 20, 2));
        var updated = Entries((".rockbox/a", 10, 1), (".rockbox/b", 20, 2));

        InstallManifestDelta delta = InstallManifest.Delta(installed, updated);
        Assert.True(delta.IsEmpty);
    }

    [Fact]
    public void ChangedCrcOrSizeForcesRewrite()
    {
        var installed = Entries((".rockbox/crc", 10, 1), (".rockbox/tam", 10, 2));
        var updated = Entries((".rockbox/crc", 10, 999), (".rockbox/tam", 11, 2));

        InstallManifestDelta delta = InstallManifest.Delta(installed, updated);
        Assert.Equal([".rockbox/crc", ".rockbox/tam"], delta.ToExtract);
        Assert.Empty(delta.ToDelete);
    }

    [Fact]
    public void NewFilesAreExtracted()
    {
        InstallManifestDelta delta = InstallManifest.Delta(
            Entries((".rockbox/viejo", 1, 1)),
            Entries((".rockbox/viejo", 1, 1), (".rockbox/nuevo", 2, 2)));

        Assert.Equal([".rockbox/nuevo"], delta.ToExtract);
    }

    [Fact]
    public void FilesThatDisappearedFromTheZipAreDeleted()
    {
        // Sin esto la extracción-merge dejaba huérfanos para siempre.
        InstallManifestDelta delta = InstallManifest.Delta(
            Entries((".rockbox/queda", 1, 1), (".rockbox/se-va", 2, 2)),
            Entries((".rockbox/queda", 1, 1)));

        Assert.Empty(delta.ToExtract);
        Assert.Equal([".rockbox/se-va"], delta.ToDelete);
    }

    [Fact]
    public void NothingOutsideTheFirmwareTreeIsEverDeleted()
    {
        // Regla dura: pase lo que pase con un manifiesto corrupto o ajeno, esto
        // no puede proponer borrar la música del usuario.
        InstallManifestDelta delta = InstallManifest.Delta(
            Entries((".rockbox/interno", 1, 1),
                    ("Music/Artista/cancion.mp3", 2, 2),
                    ("iPod_Control/x", 3, 3),
                    (".aura/art/algo", 4, 4)),
            Entries());

        Assert.Equal([".rockbox/interno"], delta.ToDelete);
    }

    /// <summary>
    /// ST-147 / contrato v19: mismo guardia de arriba, nombrado con el archivo
    /// real que protege — un manifiesto viejo (o corrupto) que de alguna forma
    /// llegara a listar <c>/.aura/settings.cfg</c> NUNCA puede hacer que la
    /// actualización selectiva lo borre: <c>Delta()</c> exige el prefijo
    /// <c>.rockbox/</c> para cualquier candidato a <c>ToDelete</c>.
    /// </summary>
    [Fact]
    public void DeltaNeverDeletesTheSharedSettingsFile()
    {
        InstallManifestDelta delta = InstallManifest.Delta(
            Entries((".rockbox/rockbox.ipod", 1, 1),
                    (FirmwareSwitcher.SharedSettingsRelativePath, 2, 2)),
            Entries((".rockbox/rockbox.ipod", 1, 1)));

        Assert.Empty(delta.ToDelete);
    }

    [Fact]
    public void DeltaOutputIsSortedForAStablePlan()
    {
        InstallManifestDelta delta = InstallManifest.Delta(
            Entries((".rockbox/z-viejo", 1, 1), (".rockbox/a-viejo", 1, 1)),
            Entries((".rockbox/z-nuevo", 1, 1), (".rockbox/a-nuevo", 1, 1)));

        Assert.Equal([".rockbox/a-nuevo", ".rockbox/z-nuevo"], delta.ToExtract);
        Assert.Equal([".rockbox/a-viejo", ".rockbox/z-viejo"], delta.ToDelete);
        Assert.Equal(4, delta.TotalOperations);
    }

    [Fact]
    public void RealisticUpdateTouchesOnlyWhatChanged()
    {
        // El caso que justifica todo el módulo: entre releases consecutivos
        // reales cambian un puñado de archivos de miles.
        var installed = new Dictionary<string, InstallManifestEntry>(StringComparer.Ordinal);
        for (int i = 0; i < 500; i++)
        {
            string p = $".rockbox/archivo-{i:D4}";
            installed[p] = new InstallManifestEntry(p, 100, (uint)i);
        }
        var updated = new Dictionary<string, InstallManifestEntry>(installed, StringComparer.Ordinal);
        updated[".rockbox/archivo-0007"] = new InstallManifestEntry(".rockbox/archivo-0007", 100, 999_999);
        updated[".rockbox/rockbox.ipod"] = new InstallManifestEntry(".rockbox/rockbox.ipod", 900_000, 42);

        InstallManifestDelta delta = InstallManifest.Delta(installed, updated);
        Assert.Equal([".rockbox/archivo-0007", ".rockbox/rockbox.ipod"], delta.ToExtract);
        Assert.Empty(delta.ToDelete);
    }
}
