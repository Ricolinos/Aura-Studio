namespace AuraStudio.Core.Library;

/// <summary>
/// Dónde va lo preparado: el <c>.mpg</c> transcodificado, la foto
/// redimensionada, el audio comprimido.
///
/// <para><c>.preparados/</c> es una carpeta <b>plana</b> compartida por toda la
/// biblioteca y nombrada por el nombre del archivo de origen. Por eso hay que
/// desambiguar: dos canciones distintas que se llamen igual —justo el caso de
/// los duplicados— compartirían el mismo preparado, y borrar uno dejaría al
/// otro apuntando a un archivo que no existe (ST-064).</para>
///
/// <para><b>Esta carpeta nunca se limpia</b>: es la reconstrucción latente de
/// la biblioteca, con los archivos ya convertidos y sus etiquetas escritas.</para>
/// </summary>
public static class StagingPaths
{
    /// <summary>
    /// La ruta para un elemento nuevo, o la que ya tenía si ese archivo sigue
    /// ahí — reprocesar algo no puede dejarle un preparado nuevo y abandonar el
    /// anterior.
    ///
    /// <para><b>Nombrado por el archivo de origen: es la forma vieja.</b> Lo
    /// nuevo se nombra por identificador (<see cref="ForItem"/>, ST-241) y no
    /// necesita desambiguar nada. Esto sigue acá porque los preparados que ya
    /// están en disco conservan su nombre —cargar la biblioteca no renombra
    /// archivos— y porque el cambio de llamadores es de B4.</para>
    /// </summary>
    /// <param name="exists">
    /// Si una ruta ya está ocupada. Se inyecta para poder probar la
    /// desambiguación sin escribir archivos.
    /// </param>
    public static string Resolve(
        string stagingDirectory, string baseName, string extension,
        string? existingPrepared = null, Func<string, bool>? exists = null)
    {
        exists ??= File.Exists;

        if (existingPrepared is { Length: > 0 } existing && exists(existing)) return existing;

        string suffix = extension.Length == 0 ? "" : "." + extension.TrimStart('.');
        string candidate = Path.Combine(stagingDirectory, baseName + suffix);

        for (int counter = 2; exists(candidate); counter++)
            candidate = Path.Combine(stagingDirectory, $"{baseName} {counter}{suffix}");

        return candidate;
    }

    /// <summary>
    /// La ruta de un preparado <b>por identificador</b>:
    /// <c>.preparados/&lt;ID en mayúsculas con guiones&gt;.&lt;ext&gt;</c>
    /// (ST-241, contrato de ST-221 con la Mac).
    ///
    /// <para>Reemplaza al nombrado por el archivo de origen. Un identificador no
    /// se repite, así que no hay nada que desambiguar: el caso de ST-064 —dos
    /// canciones distintas con el mismo nombre peleándose el mismo preparado, y
    /// borrar una dejando a la otra apuntando a un archivo que no existe— deja
    /// de ser posible en vez de taparse con un contador.</para>
    ///
    /// <para><b>Lo que ya está no se renombra.</b> Si el elemento trae un
    /// preparado y ese archivo sigue en disco, se devuelve tal cual: puede
    /// llamarse con el nombre viejo y está bien que siga llamándose así. Cargar
    /// la biblioteca <b>nunca</b> mueve archivos —a diferencia de las carátulas,
    /// donde sí se renombra al canónico (ST-087), porque ahí el nombre viejo las
    /// hacía invisibles para las dos apps y acá no: al preparado lo encuentra el
    /// catálogo, no su nombre.</para>
    /// </summary>
    /// <param name="exists">
    /// Si una ruta ya está ocupada. Se inyecta para poder probar sin escribir
    /// archivos.
    /// </param>
    public static string ForItem(
        string stagingDirectory, Guid id, string? extension,
        string? existingPrepared = null, Func<string, bool>? exists = null)
    {
        exists ??= File.Exists;

        if (existingPrepared is { Length: > 0 } existing && exists(existing)) return existing;

        return Path.Combine(stagingDirectory, CatalogPath.PreparedFileName(id, extension));
    }

    /// <summary>
    /// El póster de un video preparado. Es
    /// <see cref="CatalogPath.PosterFor(string)"/>: está acá para que quien
    /// arma el preparado no tenga que ir a buscarlo a otro tipo.
    /// </summary>
    public static string PosterFor(string preparedPath) => CatalogPath.PosterFor(preparedPath);
}
