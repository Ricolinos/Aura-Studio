namespace AuraStudio.App.Resources;

/// <summary>
/// Los glifos de <c>Segoe Fluent Icons</c> que usa la app, en un solo lugar.
///
/// <para><b>Cada código de acá se verificó renderizándolo</b>, no de memoria.
/// La razón es concreta: en la Fase 1 se usó <c>E94A</c> como icono de
/// "Dispositivos" y resultó ser el <b>signo de división</b>; se descubrió
/// dibujando rangos de la fuente a un PNG y mirándolos. Al agregar un glifo
/// nuevo hay que renderizarlo antes — el nombre que uno recuerda de una tabla
/// no es evidencia.</para>
///
/// <para>Se escriben por su número y no como el carácter suelto: el carácter
/// cae en el Área de Uso Privado, así que pegado en el fuente se ve como un
/// cuadrito vacío y cualquier conversión de codificación lo corrompe en
/// silencio. Con el número, el archivo es ASCII puro y el código es lo que se
/// verificó.</para>
/// </summary>
public static class Glyphs
{
    private static string Of(int code) => ((char)code).ToString();

    /// <summary>Corazón lleno: es favorito.</summary>
    public static string HeartFilled { get; } = Of(0xE00B);

    /// <summary>Corazón de contorno: no es favorito.</summary>
    public static string HeartOutline { get; } = Of(0xEB51);

    /// <summary>Flecha del criterio de orden ascendente.</summary>
    public static string ChevronUp { get; } = Of(0xE70E);

    /// <summary>Flecha del criterio de orden descendente.</summary>
    public static string ChevronDown { get; } = Of(0xE70D);

    /// <summary>Menú de orden.</summary>
    public static string Sort { get; } = Of(0xE8CB);

    /// <summary>Filtro.</summary>
    public static string Filter { get; } = Of(0xE71C);

    /// <summary>Elegir columnas.</summary>
    public static string Columns { get; } = Of(0xE8FD);

    /// <summary>Quitar de la biblioteca (nunca borra del disco).</summary>
    public static string Remove { get; } = Of(0xE74D);

    /// <summary>Más acciones.</summary>
    public static string More { get; } = Of(0xE712);

    /// <summary>Estrella llena: parte de la calificación elegida.</summary>
    public static string StarFilled { get; } = Of(0xE735);

    /// <summary>Estrella de contorno: todavía sin elegir.</summary>
    public static string StarOutline { get; } = Of(0xE734);

    /// <summary>Editar / Más información.</summary>
    public static string Edit { get; } = Of(0xE70F);
}
