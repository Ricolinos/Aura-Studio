namespace AuraStudio.Core.Library;

/// <summary>
/// Dónde va un archivo <b>copiado</b> dentro de la biblioteca (ST-243, modo
/// copia).
///
/// <para>Con "copiar los medios a la biblioteca" activo, el archivo del usuario
/// se copia adentro de la carpeta de la biblioteca y esa copia pasa a ser el
/// archivo del elemento. Acá se decide su ruta; copiarlo es de
/// <see cref="LibraryFileCopier"/>.</para>
///
/// <para><b>Con el mismo criterio con el que se acomoda en el iPod.</b> La
/// música usa la organización y el formato de nombre que el usuario ya eligió en
/// Ajustes (<see cref="SyncLayout.MusicRelativePath"/>); las fotos y los videos,
/// su categoría si el usuario pidió organizarlos así. Tener dos reglas para lo
/// mismo sería que la carpeta de la computadora y la del iPod no se parecieran
/// sin que nadie lo hubiera decidido.</para>
///
/// <para><b>La ruta es relativa, con "/" y en NFC</b>: es una ruta del catálogo
/// (addendum de ST-241), y de ella sale tanto el archivo en disco como lo que se
/// escribe en <c>biblioteca.json</c>. Cuando fueron dos cálculos distintos, el
/// archivo quedó bien y el catálogo apuntando a un nombre que no existía
/// (ST-107).</para>
/// </summary>
public static class LibraryFileLayout
{
    /// <summary>
    /// La carpeta de lo que no trae categoría. No se deja suelto en la raíz del
    /// medio: una carpeta con diez mil fotos sueltas no la abre nadie.
    /// </summary>
    public const string UncategorizedFolder = "Sin categoría";

    /// <param name="extensionOverride">
    /// La extensión del archivo que de verdad se va a escribir, cuando no es la
    /// del original — un WAV que se convierte a MP3 al importarlo llega acá como
    /// <c>mp3</c>.
    /// </param>
    public static string RelativePath(
        LibraryItem item,
        MusicOrganization organization = MusicOrganization.ArtistAlbum,
        MusicFilenameFormat filenameFormat = MusicFilenameFormat.TitleOnly,
        bool organizePhotosByCategory = true,
        bool organizeVideosByCategory = true,
        string? extensionOverride = null)
    {
        string root = MediaRoots.DirectoryName(item.Kind);

        if (item.Kind == LibraryItemKind.Music)
        {
            return CatalogPath.Canonical(
                SyncLayout.MusicRelativePath(item, root, organization, filenameFormat, extensionOverride));
        }

        // Foto y video conservan su nombre de archivo: no hay un "título" que
        // sea mejor que el nombre que el usuario ya le puso, y renombrárselo
        // sería no reconocer su propia foto en el Explorador.
        string filename = PathSanitizer.Sanitize(
            Path.GetFileNameWithoutExtension(item.SourcePath));

        string extension = (extensionOverride ?? Path.GetExtension(item.SourcePath)).TrimStart('.');
        if (extension.Length > 0) filename += "." + extension;

        bool byCategory = item.Kind == LibraryItemKind.Photo
            ? organizePhotosByCategory
            : organizeVideosByCategory;

        if (!byCategory) return CatalogPath.Canonical($"{root}/{filename}");

        string category = PathSanitizer.Sanitize(
            item.Category is { Length: > 0 } named ? named : UncategorizedFolder);

        return CatalogPath.Canonical($"{root}/{category}/{filename}");
    }
}
