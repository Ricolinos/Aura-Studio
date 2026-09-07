namespace AuraStudio.Core.Library;

/// <summary>Qué quedó después de asegurar el preparado de una canción (ST-244).</summary>
/// <param name="Path">
/// El preparado, o <c>null</c> si no hace falta ninguno — y entonces al iPod
/// viaja el archivo de origen.
/// </param>
/// <param name="BytesWritten">Cuánto se escribió. 0 si no se tocó el disco.</param>
public readonly record struct PreparedMusicResult(
    string? Path, PreparedMusicAction Action, string Reason, long BytesWritten)
{
    public static PreparedMusicResult None(string reason) =>
        new(null, PreparedMusicAction.None, reason, 0);
}

/// <summary>
/// Arma —y solo cuando hace falta— el archivo que viaja al iPod por una canción
/// <b>referenciada</b> (ST-244).
///
/// <para><b>Por qué existe.</b> En modo referencia el archivo es del usuario y
/// no se toca: no se le escriben las etiquetas que el usuario corrigió en
/// Studio. Sin un intermediario, esas correcciones no llegaban al iPod. El
/// intermediario es <c>.preparados/&lt;ID&gt;.&lt;ext&gt;</c> (ST-241): una
/// copia nuestra, con las etiquetas del catálogo escritas, que es la que se
/// sincroniza.</para>
///
/// <para><b>Solo lo que hace falta.</b> Ajustes le promete al usuario que en
/// modo referencia "tu disco nunca termina con una copia duplicada de toda tu
/// biblioteca". Una canción cuyo archivo ya dice lo que dice el catálogo no
/// necesita intermediario: viaja el original. Se prepara la que hay que
/// convertir y la que el usuario corrigió — en una biblioteca normal, un puñado
/// y no doce mil.</para>
///
/// <para>La música <b>copiada</b> no pasa por acá: es su propio preparado
/// (ST-241), y prepararla otra vez sería la copia de la copia que esa
/// invariante vino a evitar.</para>
/// </summary>
public static class PreparedMusicBuilder
{
    /// <summary>
    /// Deja el preparado como tiene que estar y devuelve qué pasó. <b>Nunca
    /// lanza</b> y <b>nunca borra nada del catálogo</b>: un origen que no está
    /// devuelve "no está" y el elemento sigue en la biblioteca como no
    /// disponible (ST-241).
    /// </summary>
    /// <param name="transcode">
    /// Convierte al códec que se le pida y devuelve los bytes escritos. Lo pone
    /// quien llama porque el codificador es de la plataforma y esto es Core. Sin
    /// él, un archivo que haya que convertir se reporta sin preparado en vez de
    /// copiarse en un formato que el iPod no va a poder con comodidad.
    /// </param>
    public static async Task<PreparedMusicResult> EnsureAsync(
        LibraryItem item,
        string stagingDirectory,
        AudioQuality quality = AudioQuality.OriginalLossless,
        CoverArtPolicy coverArt = CoverArtPolicy.AlbumOnly,
        byte[]? coverBytes = null,
        Func<string, string, AudioCodec, CancellationToken, Task<long>>? transcode = null,
        IPreparedMusicFiles? files = null,
        CancellationToken ct = default)
    {
        IPreparedMusicFiles disk = files ?? PreparedMusicFiles.Shared;

        if (item.Kind != LibraryItemKind.Music) return PreparedMusicResult.None("no es música");

        if (item.StorageKind == ItemStorage.Copy)
            return PreparedMusicResult.None("la música copiada es su propio preparado");

        string source = item.SourcePath;

        // Un original que no está NO se borra ni se marca como error: se dice
        // que no está, y el elemento sigue en el catálogo como no disponible.
        if (!disk.Exists(source)) return PreparedMusicResult.None("el archivo de origen no está");

        // La tabla sale de UN solo lugar, el mismo que usa la importación en modo
        // copia (ST-244).
        AudioConversion conversion = AudioConversionRules.For(source, quality);
        bool convert = conversion.Converts;

        // Ni se convierte ni se le pueden escribir etiquetas: preparar una copia
        // idéntica no le serviría a nadie y ocuparía el doble.
        if (!convert && !LocalTagWriter.CanWrite(source))
            return PreparedMusicResult.None("este formato viaja tal cual");

        bool needed = convert || !LocalTagWriter.Matches(source, item.Metadata, coverArt, coverBytes);

        string extension = conversion.Extension ?? Path.GetExtension(source).TrimStart('.');

        string prepared = StagingPaths.ForItem(
            stagingDirectory, item.Id, extension, item.PreparedPath, disk.Exists);

        bool preparedExists = disk.Exists(prepared);

        PreparedMusicDecision decision = PreparedMusicPlan.Decide(
            needed,
            preparedExists,
            item.FileSizeBytes,
            disk.Length(source),
            disk.LastWriteUtc(source),
            preparedExists ? disk.LastWriteUtc(prepared) : DateTimeOffset.MinValue);

        switch (decision.Action)
        {
            case PreparedMusicAction.None:
                return PreparedMusicResult.None(decision.Reason);

            case PreparedMusicAction.Keep:
                // Solo las etiquetas, que es lo barato. El escritor no hace nada
                // si ya coinciden.
                TagWriteResult refreshed = LocalTagWriter.Write(prepared, item.Metadata, coverArt, coverBytes);

                return new PreparedMusicResult(
                    prepared, PreparedMusicAction.Keep, decision.Reason, refreshed.BytesWritten);

            default:
                return await BuildAsync(
                    item, source, prepared, conversion.Codec, coverArt, coverBytes,
                    transcode, disk, decision.Reason, ct).ConfigureAwait(false);
        }
    }

    private static async Task<PreparedMusicResult> BuildAsync(
        LibraryItem item, string source, string prepared, AudioCodec codec,
        CoverArtPolicy coverArt, byte[]? coverBytes,
        Func<string, string, AudioCodec, CancellationToken, Task<long>>? transcode,
        IPreparedMusicFiles disk, string reason, CancellationToken ct)
    {
        if (codec != AudioCodec.None)
        {
            if (transcode is null)
                return PreparedMusicResult.None("hay que convertirlo y no hay convertidor");

            try
            {
                long converted = await transcode(source, prepared, codec, ct).ConfigureAwait(false);
                LocalTagWriter.Write(prepared, item.Metadata, coverArt, coverBytes);

                return new PreparedMusicResult(prepared, PreparedMusicAction.Build, reason,
                    disk.Exists(prepared) ? disk.Length(prepared) : converted);
            }
            catch (OperationCanceledException)
            {
                throw;
            }
            catch (Exception ex) when (ex is not OutOfMemoryException)
            {
                return PreparedMusicResult.None($"no se pudo convertir: {ex.Message}");
            }
        }

        LibraryCopyResult copied = LibraryFileCopier.CopyTo(source, prepared, disk.Copier);
        if (!copied.Copied) return PreparedMusicResult.None(copied.Reason ?? "no se pudo copiar");

        LocalTagWriter.Write(prepared, item.Metadata, coverArt, coverBytes);

        return new PreparedMusicResult(prepared, PreparedMusicAction.Build, reason, disk.Length(prepared));
    }
}

/// <summary>
/// Lo que el preparador necesita del disco. Existe para poder probar la regla de
/// regeneración —que depende de tamaños y fechas— sin tener que fabricar
/// archivos con fechas puestas a mano.
/// </summary>
public interface IPreparedMusicFiles
{
    bool Exists(string path);
    long Length(string path);
    DateTimeOffset? LastWriteUtc(string path);

    /// <summary>Con qué copiar. Es el mismo sistema de archivos, visto por el copiador.</summary>
    ILibraryFileSystem Copier { get; }
}

/// <summary>El disco de verdad.</summary>
public sealed class PreparedMusicFiles : IPreparedMusicFiles
{
    public static readonly PreparedMusicFiles Shared = new();

    public ILibraryFileSystem Copier => LibraryFileSystem.Shared;

    public bool Exists(string path) => FileAvailability.Exists(path);

    public long Length(string path)
    {
        try
        {
            return new FileInfo(path).Length;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException)
        {
            return 0;
        }
    }

    public DateTimeOffset? LastWriteUtc(string path)
    {
        try
        {
            return File.GetLastWriteTimeUtc(path);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException)
        {
            // Sin fecha, quien decide lo toma como "no se sabe" y rehace el
            // preparado, que es el lado seguro.
            return null;
        }
    }
}
