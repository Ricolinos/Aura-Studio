using Microsoft.UI.Xaml.Data;

namespace AuraStudio.App.Converters;

/// <summary>
/// Booleano a opacidad: <c>true</c> → 1, <c>false</c> → 0.
///
/// <para>Existe por la casilla de selección de las cuadrículas (R2-1): tiene
/// que <b>ocultarse sin salir del layout</b>, porque quitarla y devolverla haría
/// saltar la tarjeta cada vez que el mouse pasa por encima. Con
/// <c>Visibility</c> no se puede expresar eso; con opacidad, sí.</para>
///
/// <para>Lo que se oculta así <b>sigue estando</b> para el mouse, así que quien
/// lo use tiene que apagar también <c>IsHitTestVisible</c>: una casilla
/// invisible que igual se puede marcar es peor que una visible.</para>
/// </summary>
public sealed partial class BoolToOpacityConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language)
        => value is bool flag && flag ? 1.0 : 0.0;

    public object ConvertBack(object value, Type targetType, object parameter, string language)
        => value is double opacity && opacity > 0.5;
}
