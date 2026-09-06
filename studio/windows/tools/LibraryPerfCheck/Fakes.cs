using AuraStudio.App.Services;
using AuraStudio.Core.Library;
using AuraStudio.Core.Networking;

namespace AuraStudio.Tools.LibraryPerfCheck;

/// <summary>
/// Lo mínimo para que <c>LibraryViewModel</c> (App) se pueda construir en una
/// consola: procesar en línea y completar en línea no participan de la
/// cascada de selección que este arnés mide, así que no hacen nada real.
///
/// <para>Las preferencias sí son las de verdad (<see cref="AppPreferences"/>,
/// apuntadas a un archivo temporal): ya trae el constructor con ruta que usan
/// sus propias pruebas, y reimplementar <c>IAppPreferences</c> a mano acá
/// solo repetiría esa clase con más riesgo de desviarse.</para>
/// </summary>
internal sealed class NoOpLibraryProcessor : ILibraryProcessor
{
    public Task<bool> ProcessAsync(LibraryItem item, CancellationToken ct = default) => Task.FromResult(false);
}

internal sealed class NoOpEnrichmentService : IEnrichmentService
{
    public Task<EnrichmentReport> EnrichAsync(
        IReadOnlyList<LibraryItem> items, IProgress<string>? progress = null, CancellationToken ct = default) =>
        Task.FromResult(new EnrichmentReport(0, 0, 0, null));

    public Task<ArtistImageBatch> FetchArtistImagesAsync(
        IReadOnlyList<LibraryItem> items, string libraryRoot,
        IProgress<string>? progress = null, CancellationToken ct = default) =>
        Task.FromResult(new ArtistImageBatch(0, 0, false));

    public Task<int> FetchVideoPostersAsync(
        IReadOnlyList<LibraryItem> items, IProgress<string>? progress = null, CancellationToken ct = default) =>
        Task.FromResult(0);
}
