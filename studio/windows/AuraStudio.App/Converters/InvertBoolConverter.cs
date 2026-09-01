using Microsoft.UI.Xaml.Data;

namespace AuraStudio.App.Converters;

/// <summary>
/// Niega un booleano. Para propiedades que esperan un `bool` y no una
/// <see cref="Microsoft.UI.Xaml.Visibility"/> (por ejemplo `IsOpen` de una
/// `InfoBar` o `IsEnabled`), donde el convertidor de visibilidad no aplica.
///
/// Existe por el mismo motivo que aquel: el ViewModel publica el booleano de
/// dominio en positivo (`HasDevice`, `IsNonCancelable`) y la vista lo adapta,
/// en vez de duplicar cada propiedad con su versión negada.
/// </summary>
public sealed partial class InvertBoolConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language)
        => value is not bool flag || !flag;

    public object ConvertBack(object value, Type targetType, object parameter, string language)
        => value is not bool flag || !flag;
}
