namespace AuraStudio.Core.Library;

/// <summary>Qué hay que hacer con el preparado de una canción (ST-244).</summary>
public enum PreparedMusicAction
{
    /// <summary>No hace falta ninguno: al iPod puede viajar el archivo tal como está.</summary>
    None,

    /// <summary>Hay que armarlo desde el origen.</summary>
    Build,

    /// <summary>Ya está y sirve; a lo sumo hay que refrescarle las etiquetas.</summary>
    Keep
}

/// <summary>La decisión, con el motivo dicho. El motivo es lo que se registra y lo que se prueba.</summary>
public readonly record struct PreparedMusicDecision(PreparedMusicAction Action, string Reason);

/// <summary>
/// Cuándo hace falta un preparado de música y cuándo no (ST-244).
///
/// <para><b>La regla que evita duplicar la biblioteca entera.</b> En modo
/// referencia, Ajustes le promete al usuario que "tu disco nunca termina con una
/// copia duplicada de toda tu biblioteca". Armar un preparado por cada canción
/// rompería esa promesa —y <c>.preparados/</c> no se limpia nunca (ST-087)—, así
/// que <b>solo se prepara lo que hace falta preparar</b>: la canción cuyo
/// archivo ya dice lo que dice el catálogo viaja al iPod tal como está.</para>
///
/// <para>Se prepara cuando hay algo que cambiar: el usuario corrigió una
/// etiqueta, o el formato hay que convertirlo. En una biblioteca referenciada
/// normal eso es un puñado de canciones, no doce mil.</para>
///
/// <para>Y una vez preparado, <b>no se rehace por gusto</b>. Se rehace si el
/// archivo de origen cambió —de tamaño, o con fecha más nueva que el
/// preparado—; si solo cambió una etiqueta, se le reescribe la etiqueta al
/// preparado y listo. Copiar de nuevo cincuenta megabytes porque alguien
/// corrigió un año es exactamente lo que esta ronda viene a no hacer.</para>
/// </summary>
public static class PreparedMusicPlan
{
    /// <summary>
    /// Holgura al comparar fechas. Los sistemas de archivos no guardan todos la
    /// misma precisión —FAT redondea a dos segundos— y sin holgura un preparado
    /// se reharía en cada pasada, para siempre.
    /// </summary>
    public static readonly TimeSpan ModifiedTolerance = TimeSpan.FromSeconds(2);

    /// <summary>
    /// Qué hacer, sin tocar disco: quien llama trae los datos ya leídos.
    /// </summary>
    /// <param name="needed">
    /// Si hace falta un preparado: porque hay que convertir el formato, o porque
    /// el archivo de origen no dice lo que dice el catálogo.
    /// </param>
    /// <param name="catalogSourceSize">
    /// El tamaño del origen <b>según el catálogo</b> (ST-201). <c>null</c> en un
    /// catálogo viejo que no lo trae: entonces el tamaño no opina y decide la
    /// fecha.
    /// </param>
    public static PreparedMusicDecision Decide(
        bool needed,
        bool preparedExists,
        long? catalogSourceSize,
        long currentSourceSize,
        DateTimeOffset? sourceModifiedUtc,
        DateTimeOffset? preparedModifiedUtc)
    {
        if (!needed)
        {
            return new PreparedMusicDecision(PreparedMusicAction.None,
                "el archivo de origen ya sirve tal como está");
        }

        if (!preparedExists)
        {
            return new PreparedMusicDecision(PreparedMusicAction.Build, "todavía no hay preparado");
        }

        if (catalogSourceSize is { } known && known != currentSourceSize)
        {
            return new PreparedMusicDecision(PreparedMusicAction.Build,
                "el archivo de origen cambió de tamaño");
        }

        if (sourceModifiedUtc is not { } sourceTime || preparedModifiedUtc is not { } preparedTime)
        {
            // Sin fechas no se puede afirmar que el preparado esté al día, y el
            // lado seguro es rehacerlo: servir uno viejo manda al iPod las
            // etiquetas que el usuario ya corrigió.
            return new PreparedMusicDecision(PreparedMusicAction.Build,
                "no se pudo leer la fecha de los archivos");
        }

        if (sourceTime > preparedTime + ModifiedTolerance)
        {
            return new PreparedMusicDecision(PreparedMusicAction.Build,
                "el archivo de origen es más nuevo que el preparado");
        }

        return new PreparedMusicDecision(PreparedMusicAction.Keep, "el preparado sigue sirviendo");
    }
}
