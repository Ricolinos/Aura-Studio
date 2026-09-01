namespace AuraStudio.Core.Library;

/// <summary>
/// Lee la metadata de un archivo de audio. Port de `LocalTagReader.swift`.
///
/// <para><b>Qué se porta y qué no.</b> El Swift se apoya en AVFoundation para
/// abrir los contenedores; acá esa parte la hace TagLib#, porque en Windows no
/// hay equivalente. Lo que sí se porta al detalle son las **reglas**: qué campo
/// sale de qué etiqueta, en qué orden, con qué normalizaciones y con qué
/// respaldos. El mismo archivo tiene que dar la misma metadata en las dos apps
/// — de ahí sale el `biblioteca.json` y lo que termina en el iPod.</para>
///
/// <para>Las reglas puras viven en <see cref="TrackTagRules"/> y tienen pruebas
/// propias; acá está solo el pegado con la librería.</para>
///
/// <para><b>Nunca lanza.</b> Un archivo corrupto o de un formato que TagLib# no
/// entiende devuelve metadata vacía, no una excepción: un archivo malo no puede
/// tumbar la importación de una carpeta entera.</para>
/// </summary>
public static class LocalTagReader
{
    public static TrackMetadata Read(string path)
    {
        var metadata = new TrackMetadata();
        if (string.IsNullOrWhiteSpace(path) || !File.Exists(path)) return metadata;

        try
        {
            using TagLib.File file = TagLib.File.Create(path);
            ApplyTag(file.Tag, metadata);

            // Duración: TagLib# la lee de las cabeceras del propio archivo. En
            // macOS este campo lo mide ffmpeg y queda nulo si no está
            // instalado; acá sale gratis y siempre.
            if (file.Properties is { Duration.TotalSeconds: > 0 } properties)
            {
                metadata.DurationSeconds = properties.Duration.TotalSeconds;
            }
        }
        catch (Exception ex) when (ex is not OutOfMemoryException)
        {
            // Corrupto, truncado, o un contenedor que TagLib# no reconoce.
            // Se devuelve lo que se haya podido leer.
        }

        // ST-012 (contrato §2): la carátula de CARPETA es un asset asociado a
        // la canción, no una entrada de Imágenes. Si la pista no trae portada
        // embebida, se toma de ahí — es lo que hace que un álbum arrastrado con
        // su `cover.jpg` conserve la portada aunque el importador ya no lo
        // cuente como foto.
        if (metadata.CoverArtData is null && CoverArtAssets.FolderCover(path) is { } cover)
        {
            try
            {
                metadata.CoverArtData = File.ReadAllBytes(cover);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                // Sin portada de carpeta; la canción entra igual.
            }
        }

        return metadata;
    }

    /// <summary>
    /// El mapeo campo por campo. TagLib# ya unifica ID3, Vorbis y los átomos
    /// MP4 en un mismo <c>Tag</c>, así que acá no hay que distinguir contenedor
    /// — pero sí aplicar las mismas normalizaciones y el mismo "el primero que
    /// llega gana" que macOS.
    /// </summary>
    private static void ApplyTag(TagLib.Tag tag, TrackMetadata metadata)
    {
        metadata.Title = TrackTagRules.FirstNonEmpty(metadata.Title, tag.Title);
        metadata.Album = TrackTagRules.FirstNonEmpty(metadata.Album, tag.Album);
        metadata.Genre = TrackTagRules.FirstNonEmpty(metadata.Genre, First(tag.Genres));

        // Artista: `Performers` es el intérprete de la pista (TPE1 / ARTIST /
        // ©ART). Si falta, el del álbum sirve mejor que nada.
        metadata.Artist = TrackTagRules.FirstNonEmpty(metadata.Artist, First(tag.Performers));
        metadata.AlbumArtist = TrackTagRules.FirstNonEmpty(metadata.AlbumArtist, First(tag.AlbumArtists));
        metadata.Artist = TrackTagRules.FirstNonEmpty(metadata.Artist, metadata.AlbumArtist);

        metadata.Composer = TrackTagRules.FirstNonEmpty(metadata.Composer, First(tag.Composers));

        // El año viene ya como número; se normaliza igual para que el formato
        // del campo sea el mismo que produce macOS a partir de una fecha.
        if (tag.Year > 0)
        {
            metadata.Year = TrackTagRules.FirstNonEmpty(
                metadata.Year, TrackTagRules.YearPrefix(tag.Year.ToString()));
        }

        metadata.TrackNumber = TrackTagRules.FirstPositive(metadata.TrackNumber, (int)tag.Track);
        metadata.DiscNumber = TrackTagRules.FirstPositive(metadata.DiscNumber, (int)tag.Disc);

        metadata.MusicBrainzRecordingId =
            TrackTagRules.FirstNonEmpty(metadata.MusicBrainzRecordingId, tag.MusicBrainzTrackId);
        metadata.MusicBrainzReleaseId =
            TrackTagRules.FirstNonEmpty(metadata.MusicBrainzReleaseId, tag.MusicBrainzReleaseId);

        // Carátula embebida: se toma la primera imagen con datos. No se
        // recodifica acá — lo que se guarda es el byte a byte del archivo.
        if (metadata.CoverArtData is null)
        {
            foreach (TagLib.IPicture picture in tag.Pictures)
            {
                if (picture.Data is { Count: > 0 } data)
                {
                    metadata.CoverArtData = data.Data;
                    break;
                }
            }
        }

        metadata.SyncedLyrics = TrackTagRules.FirstNonEmpty(metadata.SyncedLyrics, tag.Lyrics);
    }

    private static string? First(string[]? values)
        => values is { Length: > 0 } ? values[0] : null;
}
