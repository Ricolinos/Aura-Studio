using System.Globalization;
using System.Text;

namespace AuraStudio.Core.Library;

/// <summary>
/// Fotos de artista (ST-031/ST-032). Viven junto a las carátulas, en
/// <c>&lt;biblioteca&gt;/.portadas/artistas/&lt;clave&gt;.jpg</c>, con la misma
/// clave con la que agrupa <see cref="LibraryGrouping.ArtistKeyOf"/>.
///
/// <para>No van al catálogo: <b>el archivo es la fuente de verdad</b>, igual
/// que las carátulas. Y viajan reducidas a <c>.rockbox/aura/artists/</c> en
/// cada sync, con el mismo nombre de archivo, para que el firmware las
/// encuentre (contrato §D.3).</para>
/// </summary>
/// <param name="normalizer">
/// ST-141: con él, la foto se guarda <b>cuadrada</b> (lado = min(lado corto,
/// 1000)). El contrato §D.3 exige cuadradas en el iPod y hasta v18 Studio
/// mandaba el lado mayor a 128 con la proporción original — se arregla desde el
/// origen, no al sincronizar, para que la vista Artistas y el aparato muestren
/// la misma imagen. Es opcional porque la normalización necesita la plataforma
/// (WIC) y este tipo vive en Core: sin él, se guarda tal cual (es lo que hacen
/// las pruebas que no miran imágenes).
/// </param>
public sealed class ArtistImageStore(string libraryRoot, CoverArtNormalizer? normalizer = null)
{
    public string Directory { get; } =
        Path.Combine(libraryRoot, PersistedLibrary.CoversDirName, "artistas");

    /// <summary>
    /// Nombre estable y seguro para una clave de artista: letras, dígitos y
    /// guiones tal cual, el espacio como guion, y todo lo demás como
    /// <c>_xx</c>.
    ///
    /// <para><b>Es el mismo algoritmo que la app de macOS</b>, carácter por
    /// carácter: las dos escriben en la misma biblioteca compartida y un
    /// artista tiene que quedarse con un solo archivo, no con uno por
    /// sistema operativo.</para>
    /// </summary>
    public static string FileName(string artistKey)
    {
        var builder = new StringBuilder();

        foreach (Rune rune in artistKey.EnumerateRunes())
        {
            if (rune.IsAscii && (Rune.IsLetter(rune) || (rune.Value >= '0' && rune.Value <= '9') || rune.Value == '-'))
                builder.Append((char)rune.Value);
            else if (rune.Value == ' ')
                builder.Append('-');
            else
                builder.Append(CultureInfo.InvariantCulture, $"_{rune.Value & 0xFF:x2}");
        }

        string name = builder.Length == 0 ? "artista" : builder.ToString();
        return (name.Length > 120 ? name[..120] : name) + ".jpg";
    }

    public string PathFor(string artistKey) => Path.Combine(Directory, FileName(artistKey));

    /// <summary><c>null</c> si no hay foto para ese artista.</summary>
    public byte[]? Image(string artistKey)
    {
        string path = PathFor(artistKey);

        try
        {
            if (!File.Exists(path)) return null;
            byte[] data = File.ReadAllBytes(path);
            return data.Length == 0 ? null : data;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return null;
        }
    }

    public void Save(string artistKey, byte[] image)
    {
        System.IO.Directory.CreateDirectory(Directory);

        image = normalizer?.Normalize(image) ?? image;

        string path = PathFor(artistKey);
        string temporary = path + ".tmp";
        File.WriteAllBytes(temporary, image);
        File.Move(temporary, path, overwrite: true);
    }

    public void Remove(string artistKey)
    {
        try { File.Delete(PathFor(artistKey)); }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { }
    }
}
