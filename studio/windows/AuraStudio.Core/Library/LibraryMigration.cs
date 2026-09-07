namespace AuraStudio.Core.Library;

/// <summary>
/// Por qué conviene migrar esta biblioteca (ST-246). Los dos motivos se cuentan
/// por separado porque se le dicen por separado al usuario.
/// </summary>
/// <param name="ItemsWithoutStorage">Elementos cuyo catálogo no dice cómo están guardados.</param>
/// <param name="LegacyPrepared">
/// Preparados con el nombre viejo —el del archivo de origen— en vez del
/// identificador (ST-241).
/// </param>
public readonly record struct LibraryMigrationNeed(int ItemsWithoutStorage, int LegacyPrepared)
{
    public static readonly LibraryMigrationNeed None = new(0, 0);

    public bool Needed => ItemsWithoutStorage > 0 || LegacyPrepared > 0;

    public int Total => ItemsWithoutStorage + LegacyPrepared;
}

/// <summary>
/// Detecta si una biblioteca viene de una versión anterior (ST-246).
///
/// <para><b>Barato, y solo con el catálogo.</b> Corre al abrir la biblioteca,
/// así que no puede preguntarle al disco por cada archivo: ST-203 sacó
/// justamente eso de la carga, y volver a meterlo por una comprobación de
/// migración sería deshacerlo. Las dos señales que se usan salen de datos que
/// la carga ya tenía en la mano.</para>
///
/// <para><b>Lo que no se puede detectar barato se confirma adentro de la
/// migración.</b> Que una copia de <c>Música/</c> tenga o no las etiquetas del
/// catálogo solo se sabe abriendo el archivo — y eso lo hace la migración
/// cuando corre, no el arranque. La consecuencia, dicha para que no sorprenda:
/// una biblioteca cuyo <b>único</b> problema sea ese no dispara el aviso sola;
/// se migra desde Ajustes, donde la acción está siempre disponible.</para>
/// </summary>
public static class LibraryMigrationScanner
{
    /// <param name="itemsWithoutStorage">
    /// Lo que contó la carga (<see cref="LibraryLoad.ItemsWithoutStorage"/>).
    /// No se puede recalcular desde los elementos vivos: para cuando llegan acá,
    /// <c>storage</c> ya está inferido.
    /// </param>
    public static LibraryMigrationNeed Detect(
        IReadOnlyList<LibraryItem> items, int itemsWithoutStorage) =>
        new(itemsWithoutStorage, items.Count(HasLegacyPreparedName));

    /// <summary>
    /// Si el preparado de este elemento tiene el nombre viejo. Es comparación de
    /// texto: no toca disco.
    ///
    /// <para>La música <b>copiada</b> no cuenta: su preparado es el archivo
    /// mismo (ST-241) y no vive en <c>.preparados/</c>, así que su nombre no
    /// tiene por qué ser un identificador.</para>
    /// </summary>
    public static bool HasLegacyPreparedName(LibraryItem item)
    {
        if (item.PreparedPath is not { Length: > 0 } prepared) return false;
        if (item.Kind == LibraryItemKind.Music && item.StorageKind == ItemStorage.Copy) return false;

        string expected = CatalogPath.PreparedFileName(item.Id, Path.GetExtension(prepared));

        return !string.Equals(
            CatalogPath.Normalize(Path.GetFileName(prepared)),
            expected,
            StringComparison.OrdinalIgnoreCase);
    }
}

/// <summary>Qué hizo la migración (ST-246). Se le cuenta al usuario tal cual.</summary>
/// <param name="Tagged">Copias de <c>Música/</c> a las que se les escribieron las etiquetas.</param>
/// <param name="PreparedRenamed">Preparados que pasaron a llamarse por identificador.</param>
/// <param name="PreparedBuilt">Preparados que hubo que armar porque faltaban.</param>
/// <param name="OrphansDeleted">Preparados y carátulas que ya no referenciaba nadie.</param>
/// <param name="Failed">Elementos que no se pudieron migrar. Siguen en la biblioteca.</param>
/// <param name="Errors">Qué falló, con el nombre del archivo. Para poder decirlo, no para tragárselo.</param>
/// <param name="Cancelled">Si el usuario la paró a mitad. Lo hecho hasta ahí queda hecho.</param>
public sealed record LibraryMigrationSummary(
    int Tagged,
    int PreparedRenamed,
    int PreparedBuilt,
    int OrphansDeleted,
    int Failed,
    IReadOnlyList<string> Errors,
    bool Cancelled)
{
    public static readonly LibraryMigrationSummary Nothing =
        new(0, 0, 0, 0, 0, [], false);

    public int Touched => Tagged + PreparedRenamed + PreparedBuilt + OrphansDeleted;
}
