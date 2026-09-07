namespace AuraStudio.Core.Library;

/// <summary>
/// De quién es el archivo de un elemento (ST-241, contrato fijado con la Mac en
/// ST-221).
/// </summary>
public enum ItemStorage
{
    /// <summary>
    /// El archivo lo copió Studio adentro de la biblioteca. Es <b>nuestro</b>:
    /// vive bajo <c>Música/</c>, <c>Imágenes/</c> o <c>Videos/</c>, lo puso ahí
    /// la app y se puede reorganizar, reescribir y borrar con ella.
    /// </summary>
    Copy,

    /// <summary>
    /// El archivo es del usuario y vive donde él lo tiene. Studio lo lee y lo
    /// prepara, pero no manda sobre él.
    ///
    /// <para>Es el valor por omisión de todo lo que no se sabe, y a propósito:
    /// equivocarse hacia "referencia" hace que Studio toque de menos; hacia
    /// "copia", que toque archivos ajenos.</para>
    /// </summary>
    Reference
}

/// <summary>
/// Cómo se lee, se infiere y se escribe el campo <c>storage</c> de
/// <c>biblioteca.json</c> (ST-241, contrato de ST-221 con la Mac).
///
/// <para><b>Las cuatro reglas del contrato</b>, en orden:</para>
///
/// <list type="number">
/// <item><c>"copy"</c> y <c>"reference"</c> significan lo que dicen.</item>
/// <item><b>Ausente</b>: se infiere <b>una vez</b> y se persiste. Un catálogo
/// escrito antes de que este campo existiera no tiene por qué volver a
/// adivinarse en cada arranque, y menos con las dos apps adivinando por
/// separado.</item>
/// <item><b>Desconocido</b>: se interpreta como <c>reference</c> — y se
/// <b>conserva tal cual</b> en el catálogo. Interpretar no es reescribir: si
/// una versión futura de la Mac escribe un valor que esta build no conoce,
/// normalizarlo a <c>reference</c> le borraría el dato al volver a guardar, que
/// es exactamente cómo se rompe un catálogo compartido.</item>
/// <item>Se infiere <c>copy</c> <b>solo</b> si la ruta guardada es relativa y
/// cuelga de <c>Música/</c>, <c>Imágenes/</c> o <c>Videos/</c>. Cualquier otra
/// cosa —una ruta absoluta, <c>.preparados/</c>, <c>.portadas/</c>, una carpeta
/// suelta— es <c>reference</c>.</item>
/// </list>
///
/// <para><b>Inferir no es autorizar.</b> Que un archivo cuelgue de
/// <c>Música/</c> dice dónde está, no que Studio sea su dueño: el usuario pudo
/// haber apuntado la biblioteca a una carpeta que ya tenía ese nombre. Por eso
/// acá no hay ningún "se puede escribir": quien vaya a modificar el archivo del
/// usuario —escribirle etiquetas, moverlo, borrarlo— decide aparte y con más
/// que esta inferencia. Este tipo <b>clasifica</b>; no da permiso.</para>
/// </summary>
public static class ItemStorageRules
{
    public const string CopyValue = "copy";
    public const string ReferenceValue = "reference";

    /// <summary>
    /// Las tres raíces de las que puede colgar una copia. Son las mismas que ve
    /// el usuario en el Explorador; <c>.preparados/</c> y <c>.portadas/</c> son
    /// técnicas y no cuentan — lo que hay ahí es derivado, no el medio.
    /// </summary>
    private static readonly string[] CopyRoots =
    [
        PersistedLibrary.MusicDirName,
        PersistedLibrary.ImagesDirName,
        PersistedLibrary.VideosDirName
    ];

    public static string RawValue(ItemStorage storage) =>
        storage == ItemStorage.Copy ? CopyValue : ReferenceValue;

    /// <summary>
    /// Qué significa lo que trae el catálogo. Todo lo que no sea exactamente
    /// <c>copy</c> —incluidos el nulo, el vacío y cualquier valor desconocido—
    /// es <see cref="ItemStorage.Reference"/>.
    /// </summary>
    public static ItemStorage Interpret(string? raw) =>
        string.Equals(raw?.Trim(), CopyValue, StringComparison.OrdinalIgnoreCase)
            ? ItemStorage.Copy
            : ItemStorage.Reference;

    /// <summary>
    /// Qué es un elemento cuyo catálogo no lo dice, a partir de <b>la ruta tal
    /// como está guardada</b> — no de la absoluta ya resuelta: lo que distingue
    /// una copia es justamente que se haya guardado relativa a la biblioteca.
    /// </summary>
    public static ItemStorage Infer(string? storedSourcePath)
    {
        if (storedSourcePath is not { Length: > 0 } stored) return ItemStorage.Reference;

        // Una ruta absoluta es, por definición, un archivo de afuera:
        // `CatalogPath.Store` solo deja absoluto lo que no cuelga de la raíz.
        if (Path.IsPathRooted(stored)) return ItemStorage.Reference;

        string first = FirstSegment(stored);
        if (first.Length == 0 || first == "..") return ItemStorage.Reference;

        // Comparación en NFC: la Mac escribe los nombres acentuados descompuestos
        // (`Mu` + acento) y Windows compuestos. Sin normalizar, "Música" del
        // catálogo de la Mac no sería "Música" acá y toda la biblioteca copiada
        // se leería como referenciada.
        string normalized = Normalize(first);

        foreach (string root in CopyRoots)
        {
            if (string.Equals(normalized, Normalize(root), StringComparison.OrdinalIgnoreCase))
                return ItemStorage.Copy;
        }

        return ItemStorage.Reference;
    }

    /// <summary>
    /// El valor que va al catálogo: el que ya estaba si lo hay —tal cual, aunque
    /// no se entienda— y el inferido si no.
    /// </summary>
    public static string Resolve(string? raw, string? storedSourcePath) =>
        raw is { Length: > 0 } existing && existing.Trim().Length > 0
            ? existing
            : RawValue(Infer(storedSourcePath));

    /// <summary>
    /// El primer componente de una ruta del catálogo. Tolera los dos
    /// separadores: leer es tolerante, escribir es canónico
    /// (<see cref="CatalogPath"/>).
    /// </summary>
    private static string FirstSegment(string stored)
    {
        int cut = stored.IndexOfAny([CatalogPath.Separator, '\\']);
        return cut < 0 ? stored : stored[..cut];
    }

    /// <summary>
    /// La misma normalización que usa el resto del catálogo (addendum de
    /// ST-241): una sola implementación, para que escribir y comparar no puedan
    /// discrepar.
    /// </summary>
    private static string Normalize(string value) => CatalogPath.Normalize(value);
}
