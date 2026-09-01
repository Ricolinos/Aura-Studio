using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// ST-030: las columnas de la tabla de Canciones. Regla del repo: <b>toda
/// columna declara su comparador</b> — una columna que no ordena es un bug, no
/// una decisión.
/// </summary>
public class MusicTableColumnTests
{
    [Fact]
    public void EveryColumnHasATitleAHeaderAndWidths()
    {
        foreach (MusicTableColumn column in MusicTableColumns.All)
        {
            Assert.False(string.IsNullOrWhiteSpace(column.Title()), $"{column} sin título");
            Assert.False(string.IsNullOrWhiteSpace(column.HeaderTitle()), $"{column} sin encabezado");
            Assert.True(column.MinWidth() > 0, $"{column} sin ancho mínimo");
            Assert.True(column.IdealWidth() >= column.MinWidth(), $"{column}: ideal menor que el mínimo");
        }
    }

    [Fact]
    public void EveryColumnBelongsToExactlyOneGroup()
    {
        // Si una faltara, no aparecería en la ventana de opciones y el usuario
        // no podría activarla nunca.
        List<MusicTableColumn> grouped = [.. Enum.GetValues<MusicColumnGroup>().SelectMany(g => g.Columns())];

        Assert.Equal(MusicTableColumns.All.Count, grouped.Count);
        Assert.Equal([.. MusicTableColumns.All.Order()], [.. grouped.Order()]);
    }

    [Fact]
    public void EveryColumnRoundTripsThroughItsStoredValue()
    {
        // Es lo que se persiste: si no volviera, la configuración del usuario se
        // perdería en silencio al reabrir.
        foreach (MusicTableColumn column in MusicTableColumns.All)
            Assert.Equal(column, MusicTableColumns.Parse(column.RawValue()));
    }

    [Fact]
    public void TheStoredValuesAreAllDistinct()
    {
        IEnumerable<string> raw = MusicTableColumns.All.Select(column => column.RawValue());
        Assert.Equal(MusicTableColumns.All.Count, raw.Distinct(StringComparer.Ordinal).Count());
    }

    [Fact]
    public void AnUnknownStoredValueIsIgnoredInsteadOfCrashing()
    {
        // Un catálogo escrito por una versión posterior puede traer una columna
        // que esta no conoce.
        Assert.Null(MusicTableColumns.Parse("columnaDelFuturo"));
        Assert.Null(MusicTableColumns.Parse(null));
    }

    [Fact]
    public void TheDefaultColumnsAreTheOnesTheOldFixedTableShowed()
    {
        Assert.Equal(
            [MusicTableColumn.Artist, MusicTableColumn.Album, MusicTableColumn.Genre,
             MusicTableColumn.Duration, MusicTableColumn.Favorite, MusicTableColumn.Status],
            MusicTableColumns.DefaultVisible);
    }

    [Fact]
    public void TheOldPlusMenuConfigurationIsCarriedOver()
    {
        // D-199: lo que el usuario ya había activado no puede desaparecer
        // porque cambió el mecanismo.
        IReadOnlyList<MusicTableColumn> migrated =
            MusicTableColumns.MigratingLegacyExtraColumns("rating,year");

        Assert.Contains(MusicTableColumn.Rating, migrated);
        Assert.Contains(MusicTableColumn.Year, migrated);
        Assert.Contains(MusicTableColumn.Artist, migrated);   // y no se pierden las de fábrica
    }

    [Fact]
    public void AnUnknownTokenInTheOldConfigurationIsSkipped()
    {
        Assert.Equal(MusicTableColumns.DefaultVisible,
            MusicTableColumns.MigratingLegacyExtraColumns("algoQueYaNoExiste"));
        Assert.Equal(MusicTableColumns.DefaultVisible,
            MusicTableColumns.MigratingLegacyExtraColumns(null));
    }

    [Fact]
    public void MigratingDoesNotDuplicateAColumnAlreadyOnByDefault()
    {
        IReadOnlyList<MusicTableColumn> migrated =
            MusicTableColumns.MigratingLegacyExtraColumns("rating,rating");

        Assert.Single(migrated, column => column == MusicTableColumn.Rating);
    }

    // MARK: - Criterio de orden

    [Fact]
    public void TitleIsASortCriterionEvenThoughItIsNotAConfigurableColumn()
    {
        Assert.Equal("Título", MusicSortField.ByTitle.Title);
        Assert.Equal("title", MusicSortField.ByTitle.RawValue);
        Assert.Equal(MusicSortField.ByTitle, MusicSortField.Parse("title"));
    }

    [Fact]
    public void EverySortFieldRoundTrips()
    {
        foreach (MusicSortField field in MusicSortField.MenuFields)
            Assert.Equal(field, MusicSortField.Parse(field.RawValue));
    }

    [Fact]
    public void TheSortMenuIsAlphabeticalWithTitleInItsPlace()
    {
        // Como en Music.app: Título no va primero por ser especial, va donde le
        // toca por nombre.
        List<string> titles = [.. MusicSortField.MenuFields.Select(field => field.Title)];
        Assert.Equal([.. titles.OrderBy(t => t, MediaTableRow.NaturalOrder)], titles);
        Assert.Contains("Título", titles);
    }

    [Fact]
    public void AnUnknownSortCriterionFallsBackInsteadOfCrashing()
        => Assert.Null(MusicSortField.Parse("criterioDelFuturo"));
}
