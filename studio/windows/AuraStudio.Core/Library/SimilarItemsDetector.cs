using System.Globalization;

namespace AuraStudio.Core.Library;

/// <summary>Qué tan seguro está el detector de que un grupo son "lo mismo".</summary>
public enum SimilarityConfidence
{
    /// <summary>Se parecen, pero con una diferencia que puede ser legítima.</summary>
    Possible = 1,

    /// <summary>Título y artista equivalentes tras normalizar; duración cercana o desconocida.</summary>
    Probable = 2,

    /// <summary>Metadata que solo difiere en formato o número de pista, misma duración o mismo tamaño exacto.</summary>
    Duplicate = 3
}

public static class SimilarityConfidenceText
{
    public static string Title(this SimilarityConfidence confidence) => confidence switch
    {
        SimilarityConfidence.Duplicate => "Duplicado",
        SimilarityConfidence.Probable => "Probable",
        _ => "Posible"
    };

    public static string Detail(this SimilarityConfidence confidence) => confidence switch
    {
        SimilarityConfidence.Duplicate => "Casi seguro es el mismo archivo dos veces.",
        SimilarityConfidence.Probable => "Probablemente es la misma canción con la metadata escrita distinto.",
        _ => "Se parecen, pero podrían ser versiones distintas. Conviene revisar."
    };
}

public enum SimilarityField { Title, Artist, Album }

/// <summary>
/// Un cambio de metadata que el detector <b>sugiere</b> para dejar el grupo
/// consistente (por ejemplo, unificar "SodaStereo"/"Soda-Stereo" al nombre que
/// más se usa). <b>Nunca se aplica solo</b>: la hoja de revisión lo muestra y el
/// usuario decide.
/// </summary>
public sealed record SimilarityProposedEdit(
    Guid ItemId, SimilarityField Field, string CurrentValue, string ProposedValue)
{
    public string Id => $"{ItemId:D}/{Field}".ToLowerInvariant();

    public string FieldTitle => Field switch
    {
        SimilarityField.Title => "Título",
        SimilarityField.Artist => "Artista",
        _ => "Álbum"
    };
}

/// <summary>
/// Un conjunto de elementos sospechosamente parecidos, con la explicación de
/// <b>por qué</b> el detector los juntó, cuál sugiere conservar y qué ediciones
/// propone para el resto.
/// </summary>
/// <param name="Items">Ordenados con el sugerido a conservar primero.</param>
public sealed record SimilarItemsGroup(
    string Id,
    LibraryItemKind Kind,
    IReadOnlyList<LibraryItem> Items,
    SimilarityConfidence Confidence,
    IReadOnlyList<string> Reasons,
    Guid SuggestedKeepId,
    string Suggestion,
    IReadOnlyList<SimilarityProposedEdit> ProposedEdits)
{
    /// <summary>
    /// Estable entre corridas mientras no cambien los miembros: es lo que se
    /// guarda cuando el usuario dice "estos no son lo mismo", y si cambiara,
    /// el grupo ignorado reaparecería.
    /// </summary>
    public static string KeyFor(IEnumerable<Guid> ids) =>
        string.Join("+", ids.Select(id => id.ToString("D").ToUpperInvariant()).Order(StringComparer.Ordinal));
}

/// <summary>
/// Detector de elementos "sospechosamente similares" (ST-063): "01 Amor" de
/// "SodaStereo" contra "Amor" de "Soda-Stereo" tiene que aparecer como posible
/// duplicado, con la sugerencia de cuál conservar. Port de
/// <c>SimilarItemsDetector.swift</c>.
///
/// <para>Todo es puro y sincrónico sobre los items; la única lectura de disco es
/// el tamaño de archivo, que se inyecta para poder probarlo sin archivos.</para>
///
/// <para><b>Nunca borra ni edita nada.</b> Devuelve grupos con evidencia, una
/// confianza y una propuesta — quien ejecuta es la hoja de revisión, con lo que
/// el usuario haya elegido.</para>
/// </summary>
public static class SimilarItemsDetector
{
    private static readonly IReadOnlySet<string> LosslessExtensions =
        new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "flac", "wav", "aiff", "aif" };

    /// <summary>Lo que el detector precalcula de cada elemento antes de comparar.</summary>
    public sealed class Fingerprint
    {
        public required LibraryItem Item { get; init; }
        public required string RawTitle { get; init; }
        public required string TitleCore { get; init; }
        public required IReadOnlySet<string> Qualifiers { get; init; }
        public required string Artist { get; init; }
        public required string Album { get; init; }
        public required string Stem { get; init; }
        public required double? Duration { get; init; }
        public required long FileSize { get; init; }
        public required string Extension { get; init; }
        public required string? EpisodeKey { get; init; }

        public static Fingerprint For(LibraryItem item, long fileSize)
        {
            string? title = item.Metadata?.Title?.Trim();
            string rawTitle = string.IsNullOrEmpty(title)
                ? Path.GetFileNameWithoutExtension(item.SourcePath)
                : title;

            SimilarityText.NormalizedTitle normalized = SimilarityText.NormalizeTitle(rawTitle);

            return new Fingerprint
            {
                Item = item,
                RawTitle = rawTitle,
                TitleCore = normalized.Core,
                Qualifiers = normalized.Qualifiers,
                Artist = SimilarityText.Alnum(item.Metadata?.Artist),
                Album = SimilarityText.Alnum(item.Metadata?.Album),
                Stem = SimilarityText.NormalizeStem(item.SourcePath),
                Duration = item.Metadata?.DurationSeconds is > 0 and double seconds ? seconds : null,
                FileSize = fileSize,
                Extension = Path.GetExtension(item.SourcePath).TrimStart('.').ToLowerInvariant(),
                EpisodeKey = item is { SeriesName: { Length: > 0 } series, Season: { } season, Episode: { } episode }
                    ? $"{SimilarityText.Alnum(series)}/{season}/{episode}"
                    : null
            };
        }
    }

    public static long FileSizeOf(string path)
    {
        try
        {
            var info = new FileInfo(path);
            return info.Exists ? info.Length : 0;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return 0;
        }
    }

    private readonly record struct PairVerdict(SimilarityConfidence Confidence, IReadOnlyList<string> Reasons);

    /// <summary>
    /// Corre el detector sobre toda la biblioteca.
    /// <paramref name="ignoredGroupIds"/> son los grupos que el usuario ya dijo
    /// que no son lo mismo.
    /// </summary>
    public static IReadOnlyList<SimilarItemsGroup> Detect(
        IReadOnlyList<LibraryItem> items,
        IReadOnlySet<string>? ignoredGroupIds = null,
        Func<string, long>? fileSize = null)
    {
        fileSize ??= FileSizeOf;
        var groups = new List<SimilarItemsGroup>();

        foreach (LibraryItemKind kind in (LibraryItemKind[])
                 [LibraryItemKind.Music, LibraryItemKind.Video, LibraryItemKind.Photo])
        {
            List<Fingerprint> prints = [.. items
                .Where(item => item.Kind == kind)
                .Select(item => Fingerprint.For(item, fileSize(item.SourcePath)))];

            groups.AddRange(Detect(prints, kind, items));
        }

        return [.. groups
            .Where(group => ignoredGroupIds is null || !ignoredGroupIds.Contains(group.Id))
            .OrderByDescending(group => group.Confidence)
            .ThenBy(group => Path.GetFileName(group.Items[0].SourcePath), NaturalOrder)];
    }

    /// <summary>
    /// Orden natural e insensible a mayúsculas, como el Explorador: "pista 2"
    /// antes que "pista 10".
    /// </summary>
    private static readonly StringComparer NaturalOrder = StringComparer.Create(
        CultureInfo.CurrentCulture, CompareOptions.IgnoreCase | CompareOptions.NumericOrdering);

    private static List<SimilarItemsGroup> Detect(
        List<Fingerprint> prints, LibraryItemKind kind, IReadOnlyList<LibraryItem> allItems)
    {
        if (prints.Count <= 1) return [];

        // Bloqueo por las 3 primeras letras del título (y del nombre de
        // archivo) para no comparar todos contra todos: un título con una letra
        // cambiada al frente se pierde, a cambio de que una biblioteca de miles
        // de canciones se procese al instante. Y el mismo tamaño exacto forma su
        // propio bloque, que es como se encuentran los duplicados byte a byte
        // con nombres distintos.
        var blocks = new Dictionary<string, List<int>>(StringComparer.Ordinal);

        void AddToBlock(string key, int index)
        {
            if (!blocks.TryGetValue(key, out List<int>? block)) blocks[key] = block = [];
            block.Add(index);
        }

        for (int index = 0; index < prints.Count; index++)
        {
            Fingerprint print = prints[index];
            string basis = kind == LibraryItemKind.Photo ? print.Stem : print.TitleCore;
            AddToBlock(Prefix(basis, 3), index);

            if (kind != LibraryItemKind.Photo && print.Stem.Length > 0)
                AddToBlock("f:" + Prefix(print.Stem, 3), index);

            if (print.FileSize > 0) AddToBlock($"s:{print.FileSize}", index);
        }

        int n = prints.Count;
        int[] parent = [.. Enumerable.Range(0, n)];

        int Find(int x)
        {
            while (parent[x] != x) { parent[x] = parent[parent[x]]; x = parent[x]; }
            return x;
        }

        var pairVerdicts = new Dictionary<long, PairVerdict>();
        var compared = new HashSet<long>();
        var involved = new HashSet<int>();

        foreach (List<int> indices in blocks.Values.Where(block => block.Count > 1))
        {
            for (int i = 0; i < indices.Count; i++)
                for (int j = i + 1; j < indices.Count; j++)
                {
                    int a = Math.Min(indices[i], indices[j]), b = Math.Max(indices[i], indices[j]);
                    if (a == b) continue;

                    long pairKey = (long)a * n + b;
                    if (!compared.Add(pairKey)) continue;

                    PairVerdict? verdict = Compare(prints[a], prints[b], kind);
                    if (verdict is null) continue;

                    pairVerdicts[pairKey] = verdict.Value;
                    involved.Add(a);
                    involved.Add(b);

                    int rootA = Find(a), rootB = Find(b);
                    if (rootA != rootB) parent[rootA] = rootB;
                }
        }

        var clusters = new Dictionary<int, List<int>>();
        foreach (int index in involved.Order())
        {
            int root = Find(index);
            if (!clusters.TryGetValue(root, out List<int>? cluster)) clusters[root] = cluster = [];
            cluster.Add(index);
        }

        var groups = new List<SimilarItemsGroup>();

        foreach (List<int> members in clusters.Values)
        {
            if (members.Count <= 1) continue;

            var confidence = SimilarityConfidence.Possible;
            var reasons = new List<string>();
            var memberSet = members.ToHashSet();

            foreach ((long pair, PairVerdict verdict) in pairVerdicts)
            {
                if (!memberSet.Contains((int)(pair / n)) || !memberSet.Contains((int)(pair % n))) continue;

                if (verdict.Confidence > confidence) confidence = verdict.Confidence;
                foreach (string reason in verdict.Reasons)
                    if (!reasons.Contains(reason)) reasons.Add(reason);
            }

            groups.Add(BuildGroup([.. members.Select(index => prints[index])], kind, confidence, reasons, allItems));
        }

        return groups;
    }

    private static string Prefix(string value, int length) =>
        value.Length <= length ? value : value[..length];

    // MARK: - Comparación de a pares

    /// <summary>
    /// Qué tan cerca están dos duraciones. <c>null</c> si alguna se desconoce —
    /// que no es lo mismo que "no se parecen".
    /// </summary>
    private static double? DurationMatch(double? a, double? b)
    {
        if (a is null || b is null) return null;

        double delta = Math.Abs(a.Value - b.Value);
        if (delta <= 2) return 1;
        if (delta <= 5) return 0.7;
        if (delta <= 15) return 0.3;
        return 0;
    }

    private static PairVerdict? Compare(Fingerprint a, Fingerprint b, LibraryItemKind kind) => kind switch
    {
        LibraryItemKind.Music => CompareMusic(a, b),
        LibraryItemKind.Video => CompareVideo(a, b),
        LibraryItemKind.Photo => ComparePhoto(a, b),
        _ => null
    };

    private static PairVerdict? CompareMusic(Fingerprint a, Fingerprint b)
    {
        var reasons = new List<string>();
        bool sameFileSize = a.FileSize > 0 && a.FileSize == b.FileSize;

        // Descartes rápidos, antes de Levenshtein: duraciones lejanas, o
        // títulos distintos sin ser el mismo archivo.
        double? duration = DurationMatch(a.Duration, b.Duration);
        if (duration == 0 && !sameFileSize) return null;

        double titleSim = SimilarityText.Similarity(a.TitleCore, b.TitleCore);
        if (titleSim < 0.8 && !(sameFileSize && titleSim >= 0.6)) return null;

        double artistSim;
        if (a.Artist.Length == 0 && b.Artist.Length == 0) artistSim = 0.6;
        else if (a.Artist.Length == 0 || b.Artist.Length == 0) artistSim = 0.65;
        else artistSim = SimilarityText.Similarity(a.Artist, b.Artist);

        double albumSim = a.Album.Length == 0 || b.Album.Length == 0
            ? 0.5
            : SimilarityText.Similarity(a.Album, b.Album);

        if (artistSim < 0.6 && albumSim < 0.85 && !sameFileSize) return null;

        if (titleSim >= 0.999)
        {
            reasons.Add(a.RawTitle != b.RawTitle
                ? $"Mismo título sin contar el número de pista o los paréntesis: «{a.RawTitle}» / «{b.RawTitle}»"
                : $"Mismo título: «{a.RawTitle}»");
        }
        else if (titleSim >= 0.8)
        {
            reasons.Add($"Título casi igual: «{a.RawTitle}» / «{b.RawTitle}»");
        }

        string artistA = a.Item.Metadata?.Artist ?? "", artistB = b.Item.Metadata?.Artist ?? "";

        if (a.Artist.Length > 0 && b.Artist.Length > 0)
        {
            if (a.Artist == b.Artist)
            {
                if (artistA != artistB)
                    reasons.Add($"Artista escrito distinto: «{artistA}» / «{artistB}»");
            }
            else if (artistSim >= 0.6)
            {
                reasons.Add($"Artista parecido: «{artistA}» / «{artistB}»");
            }
        }
        else
        {
            reasons.Add("A uno le falta el artista");
        }

        if (duration == 1) reasons.Add($"Misma duración ({SimilarityText.Clock(a.Duration)})");
        else if (duration >= 0.3)
            reasons.Add($"Duración parecida ({SimilarityText.Clock(a.Duration)} / {SimilarityText.Clock(b.Duration)})");

        if (sameFileSize)
            reasons.Add($"Mismo tamaño exacto de archivo ({SimilarityText.FormatBytes(a.FileSize)})");

        if (a.Extension != b.Extension)
            reasons.Add($"Formatos distintos: {a.Extension.ToUpperInvariant()} / {b.Extension.ToUpperInvariant()}");

        List<string> qualifierDiff = [.. a.Qualifiers.Except(b.Qualifiers).Concat(b.Qualifiers.Except(a.Qualifiers)).Order(StringComparer.Ordinal)];
        if (qualifierDiff.Count > 0)
            reasons.Add($"Una parece otra versión ({string.Join(", ", qualifierDiff)})");

        SimilarityConfidence confidence;

        if (sameFileSize && titleSim >= 0.8)
        {
            confidence = SimilarityConfidence.Duplicate;
        }
        else if (titleSim >= 0.92 && artistSim >= 0.85 && qualifierDiff.Count == 0)
        {
            if (duration == 1) confidence = SimilarityConfidence.Duplicate;
            else if (duration is null or >= 0.7) confidence = SimilarityConfidence.Probable;
            else confidence = SimilarityConfidence.Possible;
        }
        else if (titleSim >= 0.8 && (artistSim >= 0.6 || albumSim >= 0.85))
        {
            if (duration is < 0.3) return null;
            confidence = SimilarityConfidence.Possible;
        }
        else
        {
            return null;
        }

        return new PairVerdict(confidence, reasons);
    }

    private static PairVerdict? CompareVideo(Fingerprint a, Fingerprint b)
    {
        var reasons = new List<string>();
        bool sameFileSize = a.FileSize > 0 && a.FileSize == b.FileSize;
        double? duration = DurationMatch(a.Duration, b.Duration);

        // Mismo episodio de la misma serie: no hace falta mirar el título, ya
        // se sabe qué es.
        if (a.EpisodeKey is not null && a.EpisodeKey == b.EpisodeKey)
        {
            reasons.Add($"Mismo episodio: {a.Item.SeriesName ?? ""} T{a.Item.Season ?? 0}E{a.Item.Episode ?? 0}");
            if (duration == 1) reasons.Add($"Misma duración ({SimilarityText.Clock(a.Duration)})");
            if (sameFileSize) reasons.Add("Mismo tamaño exacto de archivo");

            return new PairVerdict(
                duration == 1 || sameFileSize ? SimilarityConfidence.Duplicate : SimilarityConfidence.Probable,
                reasons);
        }

        double titleSim = Math.Max(
            SimilarityText.Similarity(a.TitleCore, b.TitleCore),
            SimilarityText.Similarity(a.Stem, b.Stem));

        if (titleSim < 0.85 && !sameFileSize) return null;
        if (duration == 0 && !sameFileSize) return null;

        reasons.Add(titleSim >= 0.999
            ? $"Mismo título: «{a.RawTitle}»"
            : $"Título casi igual: «{a.RawTitle}» / «{b.RawTitle}»");

        if (duration == 1) reasons.Add($"Misma duración ({SimilarityText.Clock(a.Duration)})");
        else if (duration >= 0.3)
            reasons.Add($"Duración parecida ({SimilarityText.Clock(a.Duration)} / {SimilarityText.Clock(b.Duration)})");

        if (sameFileSize) reasons.Add("Mismo tamaño exacto de archivo");

        if (a.Extension != b.Extension)
            reasons.Add($"Formatos distintos: {a.Extension.ToUpperInvariant()} / {b.Extension.ToUpperInvariant()}");

        if ((a.Item.Category ?? "") != (b.Item.Category ?? ""))
            reasons.Add($"Categorías distintas: {a.Item.Category ?? "sin categoría"} / {b.Item.Category ?? "sin categoría"}");

        SimilarityConfidence confidence;
        if (sameFileSize || (titleSim >= 0.95 && duration == 1)) confidence = SimilarityConfidence.Duplicate;
        else if (titleSim >= 0.92 && duration is null or >= 0.7) confidence = SimilarityConfidence.Probable;
        else confidence = SimilarityConfidence.Possible;

        return new PairVerdict(confidence, reasons);
    }

    private static PairVerdict? ComparePhoto(Fingerprint a, Fingerprint b)
    {
        var reasons = new List<string>();
        bool sameFileSize = a.FileSize > 0 && a.FileSize == b.FileSize;
        double stemSim = SimilarityText.Similarity(a.Stem, b.Stem);

        // Con fotos el nombre tiene que ser EQUIVALENTE ("IMG_0001" contra
        // "IMG_0001 copia"), no solo parecido: IMG_0001 e IMG_0002 son tomas
        // consecutivas, no duplicados. Un nombre distinto solo cuenta si además
        // el tamaño es exacto.
        if (stemSim < 0.999 && !sameFileSize) return null;

        string nameA = Path.GetFileName(a.Item.SourcePath), nameB = Path.GetFileName(b.Item.SourcePath);

        if (stemSim >= 0.999)
            reasons.Add($"Mismo nombre de archivo sin contar «copia»/«(1)»: {nameA} / {nameB}");
        else if (stemSim >= 0.85)
            reasons.Add($"Nombre de archivo casi igual: {nameA} / {nameB}");

        if (sameFileSize)
            reasons.Add($"Mismo tamaño exacto de archivo ({SimilarityText.FormatBytes(a.FileSize)})");

        if (a.Extension != b.Extension)
            reasons.Add($"Formatos distintos: {a.Extension.ToUpperInvariant()} / {b.Extension.ToUpperInvariant()}");

        SimilarityConfidence confidence;
        if (sameFileSize && stemSim >= 0.85) confidence = SimilarityConfidence.Duplicate;
        else if (stemSim >= 0.999) confidence = SimilarityConfidence.Probable;
        else confidence = SimilarityConfidence.Possible;

        return new PairVerdict(confidence, reasons);
    }

    // MARK: - Sugerencia

    /// <summary>
    /// Puntaje de "cuál conservar": más metadata, mejor formato, más grande,
    /// corregido a mano, con carátula o letra. Público a propósito, para que las
    /// pruebas puedan afirmar el criterio en vez de solo su resultado.
    /// </summary>
    public static double KeepScore(LibraryItem item, long fileSize, long largestSize)
    {
        double score = 0;
        string extension = Path.GetExtension(item.SourcePath).TrimStart('.').ToLowerInvariant();
        TrackMetadata? meta = item.Metadata;

        if (item.Kind == LibraryItemKind.Music && LosslessExtensions.Contains(extension)) score += 3;
        if (fileSize > 0 && fileSize == largestSize) score += 1;
        if (item.HasCover) score += 1;
        if (meta?.SyncedLyrics is not null) score += 1;
        if (item.MetadataEditedByUser) score += 2;
        if (meta?.TrackNumber is not null) score += 0.5;
        if (!string.IsNullOrEmpty(meta?.Album)) score += 0.5;
        if (!string.IsNullOrEmpty(meta?.Artist)) score += 0.5;
        if (!string.IsNullOrEmpty(meta?.Year)) score += 0.25;
        if (!string.IsNullOrEmpty(meta?.Genre)) score += 0.25;
        if (meta?.IsFavorite == true) score += 1;
        if (meta?.Rating is > 0) score += 0.5;
        if (meta?.Title is { } title && SimilarityText.StripLeadingTrackNumber(title) == title) score += 0.5;
        if (item.Status.State == LibraryItemState.Ready) score += 0.5;

        return score;
    }

    /// <summary>
    /// El nombre "canónico" de un artista o álbum: la forma en que más veces
    /// está escrito en toda la biblioteca entre las que normalizan igual. A
    /// igualdad, la que tiene más caracteres — "Soda Stereo" antes que
    /// "SodaStereo", porque los espacios y los acentos son información.
    /// </summary>
    public static string CanonicalSpelling(
        string value, IReadOnlyList<LibraryItem> allItems, SimilarityField field)
    {
        string key = SimilarityText.Alnum(value);
        if (key.Length == 0) return value;

        var counts = new Dictionary<string, int>(StringComparer.Ordinal);

        foreach (LibraryItem item in allItems)
        {
            string? candidate = field switch
            {
                SimilarityField.Artist => item.Metadata?.Artist,
                SimilarityField.Album => item.Metadata?.Album,
                _ => null
            };

            candidate = candidate?.Trim();
            if (string.IsNullOrEmpty(candidate) || SimilarityText.Alnum(candidate) != key) continue;

            counts[candidate] = counts.GetValueOrDefault(candidate) + 1;
        }

        if (counts.Count == 0) return value;

        return counts
            .OrderByDescending(entry => entry.Value)
            .ThenByDescending(entry => entry.Key.Length)
            .ThenBy(entry => entry.Key, StringComparer.Ordinal)
            .First().Key;
    }

    private static SimilarItemsGroup BuildGroup(
        List<Fingerprint> prints, LibraryItemKind kind, SimilarityConfidence confidence,
        List<string> reasons, IReadOnlyList<LibraryItem> allItems)
    {
        long largest = prints.Count == 0 ? 0 : prints.Max(print => print.FileSize);

        List<Fingerprint> ordered = [.. prints
            .OrderByDescending(print => KeepScore(print.Item, print.FileSize, largest))
            // A igual puntaje gana el que se agregó primero; uno sin fecha
            // (catálogo viejo) va al final, nunca "gana por accidente".
            .ThenBy(print => print.Item.AddedAt ?? DateTimeOffset.MaxValue)];

        Fingerprint keep = ordered[0];
        var edits = new List<SimilarityProposedEdit>();
        string suggestion = SuggestionFor(confidence, keep, kind, prints, largest);

        if (kind == LibraryItemKind.Music)
        {
            suggestion += ProposeArtistEdits(prints, keep, allItems, edits);
            ProposeAlbumEdits(prints, keep, allItems, edits);
            ProposeCleanTitles(prints, edits);
        }

        return new SimilarItemsGroup(
            SimilarItemsGroup.KeyFor(prints.Select(print => print.Item.Id)),
            kind,
            [.. ordered.Select(print => print.Item)],
            confidence,
            reasons,
            keep.Item.Id,
            suggestion,
            edits);
    }

    private static string SuggestionFor(
        SimilarityConfidence confidence, Fingerprint keep, LibraryItemKind kind,
        List<Fingerprint> prints, long largest)
    {
        var bits = new List<string> { keep.Extension.ToUpperInvariant() };
        if (kind == LibraryItemKind.Music && LosslessExtensions.Contains(keep.Extension))
            bits[0] += " sin pérdida";
        if (keep.Item.HasCover)
            bits.Add(kind == LibraryItemKind.Music ? "con carátula" : "con póster");
        if (keep.Item.Metadata?.SyncedLyrics is not null) bits.Add("con letra");
        if (keep.Item.MetadataEditedByUser) bits.Add("corregido a mano");
        if (keep.FileSize > 0 && keep.FileSize == largest && prints.Any(print => print.FileSize != largest))
            bits.Add("el más grande");

        string description = string.Join(", ", bits);

        return confidence switch
        {
            SimilarityConfidence.Duplicate =>
                $"Parecen el mismo archivo repetido. Sugerencia: conservar «{keep.RawTitle}» ({description}) y eliminar el resto.",
            SimilarityConfidence.Probable =>
                $"Probablemente es el mismo elemento con la metadata escrita distinto. Sugerencia: conservar «{keep.RawTitle}» ({description}) y eliminar el resto, o unificar la metadata si prefieres quedarte con ambos.",
            _ =>
                $"Podrían ser versiones distintas. Sugerencia: revisar antes de eliminar. Si resultan ser la misma, conservar «{keep.RawTitle}» ({description})."
        };
    }

    private static string ProposeArtistEdits(
        List<Fingerprint> prints, Fingerprint keep, IReadOnlyList<LibraryItem> allItems,
        List<SimilarityProposedEdit> edits)
    {
        List<string> values = [.. prints
            .Select(print => print.Item.Metadata?.Artist?.Trim())
            .Where(artist => !string.IsNullOrEmpty(artist))
            .Select(artist => artist!)];

        if (values.Distinct(StringComparer.Ordinal).Count() <= 1) return "";

        string canonical = CanonicalSpelling(
            keep.Item.Metadata?.Artist ?? values[0], allItems, SimilarityField.Artist);

        foreach (Fingerprint print in prints)
        {
            string? current = print.Item.Metadata?.Artist;
            if (!string.IsNullOrEmpty(current) && current != canonical)
                edits.Add(new SimilarityProposedEdit(
                    print.Item.Id, SimilarityField.Artist, current, canonical));
        }

        return $" El artista que más se usa en tu biblioteca es «{canonical}».";
    }

    private static void ProposeAlbumEdits(
        List<Fingerprint> prints, Fingerprint keep, IReadOnlyList<LibraryItem> allItems,
        List<SimilarityProposedEdit> edits)
    {
        List<string> values = [.. prints
            .Select(print => print.Item.Metadata?.Album?.Trim())
            .Where(album => !string.IsNullOrEmpty(album))
            .Select(album => album!)];

        // Escrito distinto, sí; pero solo si es el MISMO álbum al normalizar.
        // Dos álbumes de verdad distintos no se unifican jamás.
        if (values.Distinct(StringComparer.Ordinal).Count() <= 1) return;
        if (values.Select(SimilarityText.Alnum).Distinct(StringComparer.Ordinal).Count() != 1) return;

        string canonical = CanonicalSpelling(
            keep.Item.Metadata?.Album ?? values[0], allItems, SimilarityField.Album);

        foreach (Fingerprint print in prints)
        {
            string? current = print.Item.Metadata?.Album;
            if (!string.IsNullOrEmpty(current) && current != canonical)
                edits.Add(new SimilarityProposedEdit(
                    print.Item.Id, SimilarityField.Album, current, canonical));
        }
    }

    private static void ProposeCleanTitles(List<Fingerprint> prints, List<SimilarityProposedEdit> edits)
    {
        foreach (Fingerprint print in prints)
        {
            if (print.Item.Metadata?.Title is not { } title) continue;

            string clean = SimilarityText.StripLeadingTrackNumber(title).Trim();
            if (clean != title && clean.Length > 0)
                edits.Add(new SimilarityProposedEdit(
                    print.Item.Id, SimilarityField.Title, title, clean));
        }
    }
}
