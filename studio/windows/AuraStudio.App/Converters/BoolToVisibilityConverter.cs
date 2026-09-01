using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Data;

namespace AuraStudio.App.Converters;

/// <summary>
/// `true` → visible. Con `ConverterParameter="invertir"` se invierte, para no
/// tener que publicar una propiedad negada en cada ViewModel.
///
/// Existe para que los ViewModels no expongan <see cref="Visibility"/>: los
/// estados de la sesión son booleanos de dominio ("hay dispositivo", "la
/// identificación quedó ambigua"), y traducirlos a tipos de interfaz es
/// trabajo de la vista.
/// </summary>
public sealed partial class BoolToVisibilityConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language)
    {
        bool flag = value is bool b && b;
        if (parameter as string == "invertir") flag = !flag;
        return flag ? Visibility.Visible : Visibility.Collapsed;
    }

    public object ConvertBack(object value, Type targetType, object parameter, string language)
        => throw new NotSupportedException("Conversión de un solo sentido.");
}
