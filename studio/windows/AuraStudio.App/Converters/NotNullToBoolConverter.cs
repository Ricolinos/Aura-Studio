using Microsoft.UI.Xaml.Data;

namespace AuraStudio.App.Converters;

/// <summary>
/// "Hay algo que decir" → <c>true</c>. Un texto vacío cuenta como nada: un
/// <c>InfoBar</c> abierto sin mensaje es una franja en blanco que el usuario no
/// sabe cómo cerrar.
/// </summary>
public sealed partial class NotNullToBoolConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language) =>
        value is string text ? text.Length > 0 : value is not null;

    public object ConvertBack(object value, Type targetType, object parameter, string language)
        => throw new NotSupportedException("Conversión de un solo sentido.");
}
