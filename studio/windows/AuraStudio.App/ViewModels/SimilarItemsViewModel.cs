using CommunityToolkit.Mvvm.ComponentModel;
using AuraStudio.App.Services;
using AuraStudio.Core.Library;

namespace AuraStudio.App.ViewModels;

/// <summary>Un elemento dentro de un grupo, con si es el sugerido a conservar.</summary>
public sealed record SimilarMember(LibraryItem Item, bool IsSuggestedKeep, string Detail)
{
    public Guid Id => Item.Id;
    public string Title => Item.DisplayTitle;
    public string Path => Item.SourcePath;
    public string KeepLabel => IsSuggestedKeep ? "Conservar (sugerido)" : "";
    public bool ShowsKeepLabel => IsSuggestedKeep;
}

/// <summary>Un grupo listo para mostrar: por qué se juntó y qué se propone.</summary>
public sealed record SimilarGroupRow(
    SimilarItemsGroup Group, string ConfidenceTitle, string ConfidenceDetail,
    string Reasons, IReadOnlyList<SimilarMember> Members, IReadOnlyList<string> Edits)
{
    public string Id => Group.Id;
    public string Suggestion => Group.Suggestion;
    public bool HasEdits => Edits.Count > 0;
}

/// <summary>
/// La hoja de revisión de elementos similares (ST-063).
///
/// <para><b>Nada se aplica solo.</b> El detector devuelve evidencia y una
/// propuesta; acá el usuario decide, y hasta que decide no se toca nada. Los
/// grupos que descarta se recuerdan y no vuelven a aparecer.</para>
/// </summary>
public sealed partial class SimilarItemsViewModel : ViewModelBase
{
    private readonly LibraryViewModel _library;
    private readonly IAppPreferences _preferences;

    [ObservableProperty]
    public partial IReadOnlyList<SimilarGroupRow> Groups { get; private set; } = [];

    [ObservableProperty]
    public partial string? LastMessage { get; set; }

    [ObservableProperty]
    public partial bool IsScanning { get; private set; }

    public SimilarItemsViewModel(LibraryViewModel library, IAppPreferences preferences)
    {
        _library = library;
        _preferences = preferences;
    }

    public bool IsEmpty => Groups.Count == 0;

    public string EmptyMessage => _preferences.IgnoredSimilarGroups.Count > 0
        ? "No se encontró nada nuevo. Hay grupos que ya marcaste como \"no son lo mismo\": puedes volver a mostrarlos abajo."
        : "No se encontraron elementos parecidos en tu biblioteca.";

    public bool HasIgnored => _preferences.IgnoredSimilarGroups.Count > 0;

    /// <summary>
    /// Corre el detector fuera del hilo de interfaz: en una biblioteca grande
    /// compara miles de pares y bloquearía la ventana.
    /// </summary>
    public async Task ScanAsync()
    {
        IsScanning = true;
        OnPropertyChanged(nameof(IsEmpty));

        IReadOnlyList<LibraryItem> items = _library.AvailableItems;
        var ignored = _preferences.IgnoredSimilarGroups.ToHashSet(StringComparer.Ordinal);

        IReadOnlyList<SimilarItemsGroup> found = await Task.Run(
            () => SimilarItemsDetector.Detect(items, ignored)).ConfigureAwait(true);

        Groups = [.. found.Select(Describe)];

        IsScanning = false;
        LastMessage = found.Count == 0
            ? null
            : found.Count == 1 ? "Se encontró 1 grupo parecido." : $"Se encontraron {found.Count} grupos parecidos.";

        OnPropertyChanged(nameof(IsEmpty));
        OnPropertyChanged(nameof(EmptyMessage));
        OnPropertyChanged(nameof(HasIgnored));
    }

    private static SimilarGroupRow Describe(SimilarItemsGroup group) => new(
        Group: group,
        ConfidenceTitle: group.Confidence.Title(),
        ConfidenceDetail: group.Confidence.Detail(),
        Reasons: string.Join("\n", group.Reasons.Select(reason => "· " + reason)),
        Members:
        [
            .. group.Items.Select(item => new SimilarMember(
                item,
                item.Id == group.SuggestedKeepId,
                item.Metadata?.Artist is { Length: > 0 } artist ? artist : System.IO.Path.GetFileName(item.SourcePath)))
        ],
        Edits:
        [
            .. group.ProposedEdits.Select(edit =>
                $"{edit.FieldTitle}: «{edit.CurrentValue}» → «{edit.ProposedValue}»")
        ]);

    /// <summary>
    /// Quita del catálogo todo el grupo menos el que se conserva. <b>No borra
    /// archivos</b>: se quitan de la biblioteca y siguen en el disco.
    /// </summary>
    public void KeepOnly(string groupId, Guid keepId)
    {
        SimilarGroupRow? row = Groups.FirstOrDefault(candidate => candidate.Id == groupId);
        if (row is null) return;

        IEnumerable<Guid> doomed = row.Members.Where(member => member.Id != keepId).Select(member => member.Id);
        int count = doomed.Count();

        _library.Remove(doomed);
        Forget(groupId);

        LastMessage = count == 1
            ? "Se quitó 1 elemento de la biblioteca. El archivo sigue en tu computadora."
            : $"Se quitaron {count} elementos de la biblioteca. Los archivos siguen en tu computadora.";
    }

    /// <summary>Aplica las correcciones de metadata que el grupo proponía.</summary>
    public void ApplyEdits(string groupId)
    {
        SimilarGroupRow? row = Groups.FirstOrDefault(candidate => candidate.Id == groupId);
        if (row is null || row.Group.ProposedEdits.Count == 0) return;

        foreach (SimilarityProposedEdit edit in row.Group.ProposedEdits)
        {
            LibraryItem? item = _library.Items.FirstOrDefault(candidate => candidate.Id == edit.ItemId);
            if (item?.Metadata is null) continue;

            switch (edit.Field)
            {
                case SimilarityField.Artist: item.Metadata.Artist = edit.ProposedValue; break;
                case SimilarityField.Album: item.Metadata.Album = edit.ProposedValue; break;
                default: item.Metadata.Title = edit.ProposedValue; break;
            }

            _library.ApplyMetadataEdit(item.Id, item.Metadata);
        }

        LastMessage = $"Se aplicaron {row.Group.ProposedEdits.Count} correcciones.";
        Remove(groupId);
    }

    /// <summary>"No son lo mismo": el grupo no vuelve a aparecer.</summary>
    public void Ignore(string groupId)
    {
        _preferences.IgnoredSimilarGroups = [.. _preferences.IgnoredSimilarGroups, groupId];
        Remove(groupId);
        LastMessage = "Listo, no se vuelve a mostrar. Puedes restablecerlo abajo.";
        OnPropertyChanged(nameof(HasIgnored));
    }

    /// <summary>Vuelve a mostrar todo lo que se había descartado.</summary>
    public async Task RestoreIgnoredAsync()
    {
        _preferences.IgnoredSimilarGroups = [];
        OnPropertyChanged(nameof(HasIgnored));
        await ScanAsync();
    }

    private void Forget(string groupId) => Remove(groupId);

    private void Remove(string groupId)
    {
        Groups = [.. Groups.Where(row => row.Id != groupId)];
        OnPropertyChanged(nameof(IsEmpty));
    }
}
