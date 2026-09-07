namespace AuraStudio.Core.Library;

/// <summary>Qué pasó al intentar escribir las etiquetas de un archivo (ST-242).</summary>
/// <param name="Written">
/// <c>false</c> cuando <b>no se tocó el archivo</b>: o no había nada que
/// cambiar, o el formato no se etiqueta, o falló. Un archivo que no cambia no
/// se reescribe — es lo que hace que editar un rating no le mueva la fecha de
/// modificación a la canción.
/// </param>
/// <param name="Fields">
/// Qué campos se escribieron, por nombre. Sirve para el registro y para las
/// pruebas: "se escribió" sin decir qué no se puede verificar.
/// </param>
/// <param name="BytesWritten">Cuánto pesa el archivo resultante. 0 si no se escribió.</param>
/// <param name="Reason">Por qué no se escribió, cuando <paramref name="Written"/> es <c>false</c>.</param>
public readonly record struct TagWriteResult(
    bool Written,
    IReadOnlyList<string> Fields,
    long BytesWritten,
    string? Reason = null)
{
    public static TagWriteResult Skipped(string reason) => new(false, [], 0, reason);

    /// <summary>Nada que cambiar: el archivo ya dice lo que dice el catálogo.</summary>
    public static TagWriteResult UpToDate { get; } = Skipped("el archivo ya coincide con el catálogo");
}

/// <summary>
/// Escribe en el archivo de audio las etiquetas que gobierna el catálogo
/// (ST-242, hermano de <c>ID3Writer.swift</c> de la Mac).
///
/// <para><b>Qué había.</b> Windows leía etiquetas (<see cref="LocalTagReader"/>)
/// y no las escribía <b>nunca</b>: editar el título de una canción en Studio no
/// cambiaba el archivo, así que la edición no llegaba al iPod. La Mac sí
/// escribía, pero solo MP3 y solo anteponiendo una tag ID3 a mano.</para>
///
/// <para><b>La dirección es una sola: del catálogo al archivo.</b> El catálogo
/// es la fuente de verdad (§2 del plan de la ronda); leer del archivo para
/// rellenar el catálogo es otra operación distinta, la de "Releer etiquetas del
/// archivo", y no pasa por acá.</para>
///
/// <para><b>Qué se escribe</b>: título, artista, álbum, artista del álbum,
/// compositor, pista, disco, año, género y —solo con
/// <see cref="CoverArtPolicy.PerTrack"/>— la carátula incrustada.</para>
///
/// <para><b>Qué NO se escribe, a propósito</b>: rating, favorito, letra y
/// categoría. Son datos de Aura, no del archivo: el rating viaja en
/// <c>ratings.cfg</c>, la letra como <c>.lrc</c> hermano y la categoría es
/// organización de la biblioteca. Reescribir un archivo de cincuenta megabytes
/// porque alguien puso una estrella es exactamente el defecto que esta ronda
/// vino a arreglar, y hay una prueba de que el archivo queda byte a byte
/// igual.</para>
///
/// <para><b>Formatos</b>: MP3 (ID3v2.3, la versión que lee el tagcache de
/// Rockbox y la misma que escribe la Mac), FLAC (Vorbis comments + PICTURE) y
/// M4A/ALAC (átomos <c>ilst</c>). WAV y AIFF <b>no se etiquetan</b>: al
/// importarlos en modo copia se convierten a MP3 (§0.2 del plan), y hasta que
/// eso exista se dice que no y no se toca el archivo.</para>
///
/// <para><b>Nunca lanza.</b> Un archivo de solo lectura, en uso o corrupto
/// devuelve un resultado que lo explica; una edición no puede tumbar un lote.</para>
/// </summary>
public static class LocalTagWriter
{
    /// <summary>
    /// Los que se pueden etiquetar. WAV y AIFF quedan fuera: TagLib# sabe
    /// escribirles, pero el plan dice que en modo copia se convierten a MP3, y
    /// escribirles etiquetas que después nadie va a leer sería trabajo que
    /// ensucia el archivo del usuario.
    /// </summary>
    public static readonly IReadOnlySet<string> TaggableExtensions =
        new HashSet<string>(["mp3", "flac", "m4a"], StringComparer.OrdinalIgnoreCase);

    public static bool CanWrite(string? path)
    {
        if (path is not { Length: > 0 }) return false;

        string extension = Path.GetExtension(path).TrimStart('.');
        return TaggableExtensions.Contains(extension);
    }

    /// <summary>
    /// Escribe en <paramref name="path"/> lo que dice <paramref name="metadata"/>.
    ///
    /// <para>Si el archivo ya coincide, <b>no se escribe nada</b> y se devuelve
    /// <see cref="TagWriteResult.UpToDate"/>: así una edición que no toca
    /// etiquetas no le cambia la fecha de modificación al archivo, que es lo que
    /// mira la sincronización para decidir si hay que volver a copiarlo.</para>
    /// </summary>
    /// <param name="coverArt">
    /// Con <see cref="CoverArtPolicy.PerTrack"/> la carátula del catálogo se
    /// incrusta en cada pista. Con <see cref="CoverArtPolicy.AlbumOnly"/> —lo
    /// normal— la carátula viaja como <c>cover.jpg</c> de la carpeta del álbum y
    /// acá <b>no se toca</b> la que el archivo ya tenga: el catálogo no la
    /// gobierna, y borrarla sería quitarle al usuario algo que no pidió quitar.
    /// </param>
    /// <param name="coverBytes">
    /// Los bytes de la carátula, que desde ST-208 no viven en el elemento: los
    /// lee quien llama (<c>LibraryStore.ReadCover</c>) y los pasa acá. Solo se
    /// usan con <see cref="CoverArtPolicy.PerTrack"/>.
    /// </param>
    public static TagWriteResult Write(
        string path,
        TrackMetadata? metadata,
        CoverArtPolicy coverArt = CoverArtPolicy.AlbumOnly,
        byte[]? coverBytes = null)
    {
        if (metadata is null) return TagWriteResult.Skipped("el elemento no tiene metadata");
        if (!CanWrite(path)) return TagWriteResult.Skipped($"{Path.GetExtension(path)} no se etiqueta");
        if (!File.Exists(path)) return TagWriteResult.Skipped("el archivo no está");

        bool embedCover = coverArt == CoverArtPolicy.PerTrack && coverBytes is { Length: > 0 };

        try
        {
            IReadOnlyList<string> pending = PendingFields(path, metadata, embedCover, coverBytes);
            if (pending.Count == 0) return TagWriteResult.UpToDate;

            return Apply(path, metadata, embedCover, coverBytes, pending);
        }
        catch (Exception ex) when (ex is not OutOfMemoryException)
        {
            // Solo lectura, en uso por otro programa, corrupto, sin permisos.
            return TagWriteResult.Skipped($"no se pudo escribir: {ex.Message}");
        }
    }

    /// <summary>
    /// Qué campos hay que cambiar. Se compara contra lo que el archivo dice
    /// <b>hoy</b>, y no contra lo que se escribió la última vez: el archivo es
    /// el que manda sobre su propio estado, y alguien pudo haberlo tocado por
    /// fuera.
    /// </summary>
    private static IReadOnlyList<string> PendingFields(
        string path, TrackMetadata metadata, bool embedCover, byte[]? coverBytes)
    {
        using TagLib.File file = TagLib.File.Create(path);
        TagLib.Tag tag = file.Tag;

        List<string> pending = [];

        void Compare(string field, string? desired, string? current)
        {
            if (desired is null) return;                       // el catálogo no dice nada: no se toca
            if (string.Equals(desired, current, StringComparison.Ordinal)) return;

            pending.Add(field);
        }

        Compare("título", metadata.Title, tag.Title);
        Compare("artista", metadata.Artist, First(tag.Performers));
        Compare("álbum", metadata.Album, tag.Album);
        Compare("artista del álbum", metadata.AlbumArtist, First(tag.AlbumArtists));
        Compare("compositor", metadata.Composer, First(tag.Composers));
        Compare("género", metadata.Genre, First(tag.Genres));

        if (DesiredYear(metadata.Year) is { } year && year != tag.Year) pending.Add("año");
        if (metadata.TrackNumber is { } track && track > 0 && (uint)track != tag.Track) pending.Add("pista");
        if (metadata.DiscNumber is { } disc && disc > 0 && (uint)disc != tag.Disc) pending.Add("disco");

        if (embedCover && !SameCover(tag, coverBytes!)) pending.Add("carátula");

        return pending;
    }

    private static TagWriteResult Apply(
        string path, TrackMetadata metadata, bool embedCover, byte[]? coverBytes,
        IReadOnlyList<string> fields)
    {
        // ID3v2.3 y no la 2.4 que TagLib# usaría por omisión: es la versión que
        // lee el tagcache de Rockbox y la que escribe la Mac. Sin esto, las dos
        // apps dejarían el mismo archivo con etiquetas distintas.
        TagLib.Id3v2.Tag.DefaultVersion = 3;
        TagLib.Id3v2.Tag.ForceDefaultVersion = true;

        // Escritura atómica: se trabaja sobre una copia y se reemplaza al final.
        // TagLib# guarda EN EL ARCHIVO, así que sin esto un corte de luz a mitad
        // de guardar deja la canción del usuario rota.
        string temporary = path + ".aura-tmp";

        // TagLib# resuelve el formato por la EXTENSIÓN, así que sobre un
        // archivo llamado `.aura-tmp` no sabe qué está abriendo y se niega. Se
        // le dice cuál es, con el nombre que usa la propia librería
        // ("taglib/mp3"), en vez de renombrar el temporal a `.mp3`: un temporal
        // que se llama como música es un temporal que una importación posterior
        // puede levantar como si fuera una canción del usuario.
        string mimetype = "taglib/" + Path.GetExtension(path).TrimStart('.').ToLowerInvariant();

        try
        {
            File.Copy(path, temporary, overwrite: true);

            using (TagLib.File file = TagLib.File.Create(temporary, mimetype, TagLib.ReadStyle.Average))
            {
                WriteInto(file, metadata, embedCover, coverBytes);
                file.Save();
            }

            long bytes = new FileInfo(temporary).Length;

            // Reemplazo en un paso. `File.Move` con `overwrite` es atómico
            // dentro del mismo volumen, que es donde está el temporal: o queda
            // el archivo viejo entero, o el nuevo entero.
            File.Move(temporary, path, overwrite: true);

            return new TagWriteResult(true, fields, bytes);
        }
        finally
        {
            // Si algo falló, el temporal no se queda tirado al lado de la música
            // del usuario.
            try
            {
                if (File.Exists(temporary)) File.Delete(temporary);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                // Nada más que hacer: lo que importa es que el original está bien.
            }
        }
    }

    /// <summary>
    /// Lo que el catálogo gobierna, y <b>solo</b> eso. Todo lo demás que traiga
    /// el archivo —comentarios, ReplayGain, identificadores de otros programas,
    /// la carátula cuando la política es por álbum— se queda como estaba: el
    /// catálogo no lo gobierna, así que no le corresponde borrarlo.
    /// </summary>
    private static void WriteInto(
        TagLib.File file, TrackMetadata metadata, bool embedCover, byte[]? coverBytes)
    {
        TagLib.Tag tag = file.Tag;

        if (metadata.Title is not null) tag.Title = metadata.Title;
        if (metadata.Artist is not null) tag.Performers = [metadata.Artist];
        if (metadata.Album is not null) tag.Album = metadata.Album;
        if (metadata.AlbumArtist is not null) tag.AlbumArtists = [metadata.AlbumArtist];
        if (metadata.Composer is not null) tag.Composers = [metadata.Composer];
        if (metadata.Genre is not null) tag.Genres = [metadata.Genre];

        if (DesiredYear(metadata.Year) is { } year) tag.Year = year;
        if (metadata.TrackNumber is { } track && track > 0) tag.Track = (uint)track;
        if (metadata.DiscNumber is { } disc && disc > 0) tag.Disc = (uint)disc;

        if (embedCover)
        {
            tag.Pictures =
            [
                new TagLib.Picture(new TagLib.ByteVector(coverBytes!))
                {
                    Type = TagLib.PictureType.FrontCover,
                    MimeType = MimeTypeOf(coverBytes!),
                    Description = "Cover"
                }
            ];
        }
    }

    /// <summary>
    /// El año como número, del prefijo de cuatro dígitos que ya normaliza
    /// <see cref="TrackTagRules.YearPrefix"/>. Un año que no es un año no se
    /// escribe: es mejor dejar el que había que poner un cero.
    /// </summary>
    private static uint? DesiredYear(string? year)
    {
        if (TrackTagRules.YearPrefix(year) is not { Length: 4 } prefix) return null;

        return uint.TryParse(prefix, out uint parsed) && parsed > 0 ? parsed : null;
    }

    /// <summary>
    /// Si el archivo ya tiene <b>esa misma</b> imagen. Se comparan los bytes, no
    /// el tamaño: dos carátulas distintas del mismo peso son dos carátulas.
    /// </summary>
    private static bool SameCover(TagLib.Tag tag, byte[] coverBytes)
    {
        foreach (TagLib.IPicture picture in tag.Pictures)
        {
            if (picture.Data is not { Count: > 0 } data) continue;

            return data.Count == coverBytes.Length
                   && data.Data.AsSpan().SequenceEqual(coverBytes);
        }

        return false;
    }

    /// <summary>
    /// El tipo de la imagen por su firma, no por la extensión de nada: los bytes
    /// vienen del catálogo, sin nombre de archivo. Un tipo equivocado hace que
    /// algunos reproductores no muestren la carátula.
    /// </summary>
    private static string MimeTypeOf(byte[] data)
    {
        if (data.Length >= 8 && data[0] == 0x89 && data[1] == 0x50 && data[2] == 0x4E && data[3] == 0x47)
            return "image/png";

        return "image/jpeg";
    }

    private static string? First(string[]? values) => values is { Length: > 0 } ? values[0] : null;
}
