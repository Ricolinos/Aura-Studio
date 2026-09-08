namespace AuraStudio.Core.Library;

/// <summary>
/// Cómo terminó el intento de preparar una canción (ST-247, B7d).
///
/// <para><b>Por qué existe.</b> Esto se leía del texto del motivo:
/// <c>result.Reason.Contains("no se pudo")</c>. No hacía falta traducir nada
/// para romperlo — bastaba con reescribir una de esas frases en español y decir
/// "no fue posible" para que el aviso de fallo dejara de salir, sin que nada
/// avisara. Un motivo es prosa: sirve para leerlo, no para decidir con él.</para>
/// </summary>
public enum PreparedMusicOutcome
{
    /// <summary>No hacía falta preparar nada: al iPod viaja el archivo de origen.</summary>
    NotNeeded,

    /// <summary>Hay preparado, recién hecho o el que ya estaba.</summary>
    Ready,

    /// <summary>
    /// El archivo de origen no está.
    ///
    /// <para>No cuenta como fallo del preparado y por eso no se avisa: el
    /// elemento ya aparece como no disponible en la biblioteca (ST-241), y
    /// decirlo dos veces por el mismo archivo es ruido.</para>
    /// </summary>
    SourceMissing,

    /// <summary>Hay que convertirlo y no hay convertidor.</summary>
    NoTranscoder,

    /// <summary>El convertidor falló.</summary>
    TranscodeFailed,

    /// <summary>No se pudo copiar el origen al preparado.</summary>
    CopyFailed,
}

/// <summary>Qué quedó después de asegurar el preparado de una canción (ST-244).</summary>
/// <param name="Path">
/// El preparado, o <c>null</c> si no hace falta ninguno — y entonces al iPod
/// viaja el archivo de origen.
/// </param>
/// <param name="Reason">
/// Por qué, en español y para leerlo: es lo que se registra y lo que se prueba.
///
/// <para><b>No es texto de pantalla</b> y no se le pega a ninguna frase. Lo era:
/// la biblioteca mostraba <c>"No se pudo preparar «X» para el iPod: {Reason}"</c>,
/// media oración del recurso y media escrita acá — con la app en alemán, media
/// oración en cada idioma. Lo que el usuario lee sale ahora de
/// <see cref="PreparedMusicResult.Outcome"/>.</para>
/// </param>
/// <param name="BytesWritten">Cuánto se escribió. 0 si no se tocó el disco.</param>
public readonly record struct PreparedMusicResult(
    string? Path, PreparedMusicAction Action, PreparedMusicOutcome Outcome, string Reason, long BytesWritten)
{
    /// <summary>Si hacía falta un preparado y no se pudo. Es lo único que se le dice al usuario.</summary>
    public bool Failed => Outcome
        is PreparedMusicOutcome.NoTranscoder
        or PreparedMusicOutcome.TranscodeFailed
        or PreparedMusicOutcome.CopyFailed;

    public static PreparedMusicResult None(PreparedMusicOutcome outcome, string reason) =>
        new(null, PreparedMusicAction.None, outcome, reason, 0);
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

        if (item.Kind != LibraryItemKind.Music)
            return PreparedMusicResult.None(PreparedMusicOutcome.NotNeeded, "no es música");

        if (item.StorageKind == ItemStorage.Copy)
            return PreparedMusicResult.None(
                PreparedMusicOutcome.NotNeeded, "la música copiada es su propio preparado");

        string source = item.SourcePath;

        // Un original que no está NO se borra ni se marca como error: se dice
        // que no está, y el elemento sigue en el catálogo como no disponible.
        if (!disk.Exists(source))
            return PreparedMusicResult.None(
                PreparedMusicOutcome.SourceMissing, "el archivo de origen no está");

        // La tabla sale de UN solo lugar, el mismo que usa la importación en modo
        // copia (ST-244).
        AudioConversion conversion = AudioConversionRules.For(source, quality);
        bool convert = conversion.Converts;

        // Ni se convierte ni se le pueden escribir etiquetas: preparar una copia
        // idéntica no le serviría a nadie y ocuparía el doble.
        if (!convert && !LocalTagWriter.CanWrite(source))
            return PreparedMusicResult.None(PreparedMusicOutcome.NotNeeded, "este formato viaja tal cual");

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
                return PreparedMusicResult.None(PreparedMusicOutcome.NotNeeded, decision.Reason);

            case PreparedMusicAction.Keep:
                // Solo las etiquetas, que es lo barato. El escritor no hace nada
                // si ya coinciden.
                TagWriteResult refreshed = LocalTagWriter.Write(prepared, item.Metadata, coverArt, coverBytes);

                return new PreparedMusicResult(
                    prepared, PreparedMusicAction.Keep, PreparedMusicOutcome.Ready,
                    decision.Reason, refreshed.BytesWritten);

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
                return PreparedMusicResult.None(
                    PreparedMusicOutcome.NoTranscoder, "hay que convertirlo y no hay convertidor");

            try
            {
                long converted = await transcode(source, prepared, codec, ct).ConfigureAwait(false);
                LocalTagWriter.Write(prepared, item.Metadata, coverArt, coverBytes);

                return new PreparedMusicResult(prepared, PreparedMusicAction.Build, PreparedMusicOutcome.Ready,
                    reason, disk.Exists(prepared) ? disk.Length(prepared) : converted);
            }
            catch (OperationCanceledException)
            {
                throw;
            }
            catch (Exception ex) when (ex is not OutOfMemoryException)
            {
                return PreparedMusicResult.None(
                    PreparedMusicOutcome.TranscodeFailed, $"no se pudo convertir: {ex.Message}");
            }
        }

        LibraryCopyResult copied = LibraryFileCopier.CopyTo(source, prepared, disk.Copier);
        if (!copied.Copied)
            return PreparedMusicResult.None(
                PreparedMusicOutcome.CopyFailed, copied.Reason ?? "no se pudo copiar");

        LocalTagWriter.Write(prepared, item.Metadata, coverArt, coverBytes);

        return new PreparedMusicResult(
            prepared, PreparedMusicAction.Build, PreparedMusicOutcome.Ready, reason, disk.Length(prepared));
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
