using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

public class MediaTableRowTests
{
    private static MediaTableRow Row(
        string path = @"C:\m\a.mp3", string? title = null, string? artist = null,
        string? album = null, string? genre = null, string? year = null,
        string? albumArtist = null, string? composer = null,
        double? duration = null, int? track = null, int? disc = null, int? rating = null,
        bool favorite = false, DateTimeOffset? addedAt = null, long size = 0,
        LibraryItemStatus? status = null, SyncItemState? syncState = null)
        => new(new LibraryItem
        {
            SourcePath = path,
            Kind = LibraryItemKind.Music,
            Status = status ?? LibraryItemStatus.Ready,
            AddedAt = addedAt,
            Metadata = new TrackMetadata
            {
                Title = title,
                Artist = artist,
                Album = album,
                AlbumArtist = albumArtist,
                Composer = composer,
                Genre = genre,
                Year = year,
                DurationSeconds = duration,
                TrackNumber = track,
                DiscNumber = disc,
                Rating = rating,
                IsFavorite = favorite
            }
        }, size, syncState);

    // MARK: - Lo que se muestra

    [Fact]
    public void WithoutATagTheFileNameIsShown()
        => Assert.Equal("Persiana Americana", Row(@"C:\m\Persiana Americana.mp3").Title);

    [Fact]
    public void AMissingFieldShowsEmptyNotTheWordNull()
    {
        MediaTableRow row = Row();
        Assert.Equal("", row.Artist);
        Assert.Equal("", row.Album);
        Assert.Equal("", row.Genre);
        Assert.Equal("", row.TrackNumberText);
        Assert.Equal("", row.AddedAtText);
    }

    [Fact]
    public void AnUnknownDurationShowsTwoDashesNotZeroZero()
    {
        // "0:00" se leería como una canción de duración cero, que es otra cosa.
        Assert.Equal("--", Row().DurationText);
        Assert.Equal("3:24", Row(duration: 204).DurationText);
    }

    [Fact]
    public void TheRatingIsShownAsStars()
    {
        Assert.Equal("★★★★", Row(rating: 4).RatingText);
        Assert.Equal("", Row(rating: 0).RatingText);
        Assert.Equal("", Row().RatingText);
    }

    [Fact]
    public void TheFormatIsTheExtensionInCaps()
        => Assert.Equal("FLAC", Row(@"C:\m\a.flac").FileFormat);

    [Fact]
    public void AnUnknownSizeShowsTwoDashes()
    {
        Assert.Equal("--", Row().FileSizeText);
        Assert.Equal("4.2 MB", Row(size: 4_200_000).FileSizeText);
    }

    [Fact]
    public void TheDateIsWrittenInSpanish()
    {
        // Regla del repo: español de México pase lo que pase, aunque Windows
        // esté en otro idioma.
        string text = Row(addedAt: new DateTimeOffset(2026, 3, 15, 0, 0, 0, TimeSpan.Zero)).AddedAtText;
        Assert.Contains("marzo", text);
        Assert.Contains("2026", text);
    }

    // MARK: - Orden por estado (ST-030)

    [Fact]
    public void SortingByStatusGroupsWhatIsPendingAndWhatNeedsAttention()
    {
        // Primero lo que ya está en el iPod, después lo que falta, y al final lo
        // problemático: mezclarlos haría inútil el criterio.
        MediaTableRow enElIPod = Row(syncState: SyncItemState.Synced);
        MediaTableRow listoSinIPod = Row();
        MediaTableRow porCopiar = Row(syncState: SyncItemState.Pending);
        MediaTableRow enCola = Row(status: LibraryItemStatus.Queued);
        MediaTableRow necesitaRevision = Row(status: LibraryItemStatus.NeedsReview);
        MediaTableRow fallo = Row(status: LibraryItemStatus.Failed("x"));

        Assert.True(enElIPod.StatusRank < listoSinIPod.StatusRank);
        Assert.True(listoSinIPod.StatusRank < porCopiar.StatusRank);
        Assert.True(porCopiar.StatusRank < enCola.StatusRank);
        Assert.True(enCola.StatusRank < necesitaRevision.StatusRank);
        Assert.True(necesitaRevision.StatusRank < fallo.StatusRank);
    }

    [Fact]
    public void SomethingDeletedOnTheIPodRanksAfterEverythingElseThatIsReady()
    {
        // Se respeta como decisión del usuario, pero se ve.
        Assert.True(Row(syncState: SyncItemState.RemovedFromDevice).StatusRank >
                    Row(syncState: SyncItemState.ModifiedOnDevice).StatusRank);
    }

    // MARK: - Comparadores

    [Fact]
    public void EveryColumnCanActuallySort()
    {
        // Regla del repo. Una columna sin comparador es un bug, y la forma de
        // notarlo es que dos renglones que difieren EN TODO igual empaten.
        MediaTableRow a = Row(@"C:\m\a.mp3", "A", "A", "A", "A", "1990", "A", "A",
            100, 1, 1, 1, true, DateTimeOffset.Now.AddDays(-1), 10);
        MediaTableRow b = Row(@"C:\m\b.flac", "B", "B", "B", "B", "2000", "B", "B",
            200, 2, 2, 5, false, DateTimeOffset.Now, 20, status: LibraryItemStatus.Queued);

        foreach (MusicTableColumn column in MusicTableColumns.All)
        {
            var ascending = new MediaTableRowComparer(MusicSortField.By(column), ascending: true);
            var descending = new MediaTableRowComparer(MusicSortField.By(column), ascending: false);

            Assert.Equal(0, ascending.Compare(a, a));

            int forward = ascending.Compare(a, b);
            Assert.True(forward != 0, $"la columna {column} no distingue dos renglones distintos");
            Assert.Equal(forward, -descending.Compare(a, b));
        }
    }

    [Fact]
    public void TextSortsInNaturalOrderNotByCharacterCode()
    {
        // "Pista 2" antes que "Pista 10", como en el Explorador.
        IReadOnlyList<MediaTableRow> sorted = new[]
        {
            Row(album: "Pista 10"), Row(album: "Pista 2")
        }.Sorted(MusicSortField.By(MusicTableColumn.Album), ascending: true);

        Assert.Equal("Pista 2", sorted[0].Album);
    }

    [Fact]
    public void AccentsDoNotSendAWordToTheEndOfTheList()
    {
        IReadOnlyList<MediaTableRow> sorted = new[]
        {
            Row(artist: "Zoé"), Row(artist: "Ángeles Azules"), Row(artist: "Café Tacvba")
        }.Sorted(MusicSortField.By(MusicTableColumn.Artist), ascending: true);

        Assert.Equal(["Ángeles Azules", "Café Tacvba", "Zoé"], sorted.Select(row => row.Artist));
    }

    [Fact]
    public void FavoritesFirstWhenSortingAscending()
    {
        IReadOnlyList<MediaTableRow> sorted = new[]
        {
            Row(title: "no", favorite: false), Row(title: "sí", favorite: true)
        }.Sorted(MusicSortField.By(MusicTableColumn.Favorite), ascending: true);

        Assert.True(sorted[0].IsFavorite);
    }

    [Fact]
    public void SortingByDurationUsesTheNumberNotItsText()
    {
        // Por texto, "10:00" iría antes que "3:24".
        IReadOnlyList<MediaTableRow> sorted = new[]
        {
            Row(title: "larga", duration: 600), Row(title: "corta", duration: 204)
        }.Sorted(MusicSortField.By(MusicTableColumn.Duration), ascending: true);

        Assert.Equal("corta", sorted[0].Title);
    }

    [Fact]
    public void SortingBySizeUsesTheBytesNotTheirText()
    {
        IReadOnlyList<MediaTableRow> sorted = new[]
        {
            Row(title: "grande", size: 900_000_000), Row(title: "chica", size: 4_200_000)
        }.Sorted(MusicSortField.By(MusicTableColumn.FileSize), ascending: true);

        Assert.Equal("chica", sorted[0].Title);
    }

    [Fact]
    public void RowsWithTheSameValueKeepTheOrderTheyCameIn()
    {
        // Ordenamiento estable, como la tabla de macOS: las tres canciones de un
        // mismo álbum no se barajan entre sí, ni la primera vez ni al reordenar.
        MediaTableRow[] rows =
        [
            Row(title: "Zamba", album: "Signos"),
            Row(title: "Amor", album: "Signos"),
            Row(title: "Persiana", album: "Signos")
        ];

        IReadOnlyList<MediaTableRow> once = rows.Sorted(MusicSortField.By(MusicTableColumn.Album), true);
        IReadOnlyList<MediaTableRow> twice = once.Sorted(MusicSortField.By(MusicTableColumn.Album), true);

        Assert.Equal(["Zamba", "Amor", "Persiana"], once.Select(row => row.Title));
        Assert.Equal(once.Select(row => row.Id), twice.Select(row => row.Id));
    }

    [Fact]
    public void ATieDoesNotMoveButTheAlbumsAroundItDo()
    {
        // Lo empatado conserva su orden; lo que sí ordena es el álbum.
        MediaTableRow[] rows =
        [
            Row(title: "Zamba", album: "Signos"),
            Row(title: "Uno", album: "Nada Personal"),
            Row(title: "Amor", album: "Signos")
        ];

        IReadOnlyList<MediaTableRow> sorted = rows.Sorted(MusicSortField.By(MusicTableColumn.Album), true);

        Assert.Equal(["Uno", "Zamba", "Amor"], sorted.Select(row => row.Title));
    }

    [Fact]
    public void DescendingIsTheExactReverse()
    {
        MediaTableRow[] rows = [Row(title: "A"), Row(title: "B"), Row(title: "C")];

        IReadOnlyList<MediaTableRow> up = rows.Sorted(MusicSortField.ByTitle, ascending: true);
        IReadOnlyList<MediaTableRow> down = rows.Sorted(MusicSortField.ByTitle, ascending: false);

        Assert.Equal(up.Select(row => row.Id).Reverse(), down.Select(row => row.Id));
    }

    [Fact]
    public void SortingReturnsANewListWithoutTouchingTheOriginal()
    {
        // El orden es una vista, no una mutación del catálogo.
        List<MediaTableRow> original = [Row(title: "C"), Row(title: "A")];
        _ = original.Sorted(MusicSortField.ByTitle, ascending: true);
        Assert.Equal("C", original[0].Title);
    }

    [Fact]
    public void SomethingWithoutADateGoesToTheEndNotTheBeginning()
    {
        IReadOnlyList<MediaTableRow> sorted = new[]
        {
            Row(title: "sin fecha"), Row(title: "con fecha", addedAt: DateTimeOffset.Now)
        }.Sorted(MusicSortField.By(MusicTableColumn.DateAdded), ascending: false);

        Assert.Equal("con fecha", sorted[0].Title);
    }

    // MARK: - Lo que dice cada celda

    [Fact]
    public void EveryColumnKnowsWhatToShowInItsCell()
    {
        MediaTableRow row = Row(album: "Signos", artist: "Soda Stereo", genre: "Rock",
            year: "1986", albumArtist: "Soda Stereo", composer: "Cerati",
            duration: 204, track: 3, disc: 1, rating: 4, size: 4_200_000,
            addedAt: DateTimeOffset.Now);

        foreach (MusicTableColumn column in MusicTableColumns.All)
        {
            string cell = row.CellText(column);

            // Favorito se dibuja con un corazón, no con letras; el resto tiene
            // que decir algo — una celda vacía con datos presentes es un bug.
            if (column == MusicTableColumn.Favorite) Assert.Equal("", cell);
            else Assert.False(string.IsNullOrEmpty(cell), $"la columna {column} no muestra nada");
        }
    }

    [Fact]
    public void WhatTheCellShowsMatchesWhatTheColumnSortsBy()
    {
        // El error clásico de las tablas: mostrar "3:24" y ordenar por otra
        // cosa. Duración y tamaño muestran texto pero ordenan por número, y eso
        // tiene que seguir siendo cierto.
        MediaTableRow corta = Row(title: "corta", duration: 204, size: 4_200_000);
        MediaTableRow larga = Row(title: "larga", duration: 600, size: 900_000_000);

        Assert.Equal("3:24", corta.CellText(MusicTableColumn.Duration));
        Assert.Equal("10:00", larga.CellText(MusicTableColumn.Duration));

        var byDuration = new MediaTableRowComparer(
            MusicSortField.By(MusicTableColumn.Duration), ascending: true);
        Assert.True(byDuration.Compare(corta, larga) < 0);

        var bySize = new MediaTableRowComparer(
            MusicSortField.By(MusicTableColumn.FileSize), ascending: true);
        Assert.True(bySize.Compare(corta, larga) < 0);
    }

    [Fact]
    public void ReadyWithoutAnIPodDoesNotPromiseItIsOnTheDevice()
    {
        Assert.Equal("Listo", Row().StatusText);
        Assert.Equal("En el iPod", Row(syncState: SyncItemState.Synced).StatusText);
        Assert.Equal("Falta copiar", Row(syncState: SyncItemState.Pending).StatusText);
    }

    [Fact]
    public void AFailureSaysWhyNotJustThatItFailed()
        => Assert.Equal("Error: se cayó la red",
            Row(status: LibraryItemStatus.Failed("se cayó la red")).StatusText);

    [Fact]
    public void TranscodingShowsItsProgressBecauseItCanTakeMinutes()
        => Assert.Equal("Convirtiendo… 50%",
            Row(status: LibraryItemStatus.Transcoding(0.5)).StatusText);
}
