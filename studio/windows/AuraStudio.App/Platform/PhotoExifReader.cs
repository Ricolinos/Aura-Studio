using Windows.Graphics.Imaging;
using Windows.Storage;
using Windows.Storage.Streams;

namespace AuraStudio.App.Platform;

/// <param name="SoftwareTag">El tag EXIF/TIFF "Software", si lo trae.</param>
/// <param name="HasCameraExif">Si la imagen trae rastro de haber salido de una cámara.</param>
public readonly record struct PhotoExif(string? SoftwareTag, bool HasCameraExif);

/// <summary>
/// Lo poco de EXIF que hace falta para clasificar una imagen en Fotos, Imágenes
/// o IA (la heurística en sí es de <c>MediaCategoryHeuristics</c>, en Core y
/// probada ahí). En macOS lo lee ImageIO; acá, WIC.
/// </summary>
public static class PhotoExifReader
{
    /// <summary>Las propiedades que delatan una cámara: si hay alguna, la foto salió de una.</summary>
    private static readonly string[] CameraProperties =
    [
        "System.Photo.CameraManufacturer",
        "System.Photo.CameraModel",
        "System.Photo.ExposureTime",
        "System.Photo.FNumber",
        "System.Photo.ISOSpeed"
    ];

    private const string SoftwareProperty = "System.ApplicationName";

    /// <summary>
    /// <b>Nunca lanza.</b> Una imagen sin EXIF, ilegible o de un formato exótico
    /// devuelve "no sé", que la heurística trata como "Imágenes" — clasificar de
    /// más sería peor que dejarla donde el usuario la puede mover.
    /// </summary>
    public static async Task<PhotoExif> ReadAsync(string path)
    {
        try
        {
            StorageFile file = await StorageFile.GetFileFromPathAsync(path);
            using IRandomAccessStream stream = await file.OpenReadAsync();
            BitmapDecoder decoder = await BitmapDecoder.CreateAsync(stream);

            string[] wanted = [SoftwareProperty, .. CameraProperties];
            BitmapPropertySet properties = await decoder.BitmapProperties.GetPropertiesAsync(wanted);

            string? software = properties.TryGetValue(SoftwareProperty, out BitmapTypedValue? value)
                ? value?.Value as string
                : null;

            bool hasCamera = CameraProperties.Any(property =>
                properties.TryGetValue(property, out BitmapTypedValue? camera) && camera?.Value is not null);

            return new PhotoExif(software, hasCamera);
        }
        catch (Exception)
        {
            return new PhotoExif(null, false);
        }
    }
}
