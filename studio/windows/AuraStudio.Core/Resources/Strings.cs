using System.Globalization;
using System.Resources;

namespace AuraStudio.Core.Resources;

/// <summary>
/// De dónde salen los textos de la app (ST-247).
///
/// <para><b>Qué había, y por qué cambia.</b> ST-079 decidió una tabla estática
/// de C# en vez de recursos, con dos argumentos que siguen siendo buenos: el
/// compilador atrapa una clave mal escrita, y la cadena se lee junto al código
/// que la usa. El tercero —"esta app tiene un solo idioma"— es el que dejó de
/// valer: la ronda "ajustes 3" trae segundo idioma (§3 del plan), y una tabla
/// con un <c>if</c> por cadena no escala a quinientas cincuenta.</para>
///
/// <para><b>Por qué <c>.resx</c> y no <c>.resw</c> con <c>ResourceLoader</c></b>,
/// que era lo primero que se propuso:</para>
///
/// <list type="bullet">
/// <item><b>Se conserva la verificación</b>. Con <c>ResourceLoader</c> las
/// claves son texto: una mal escrita devuelve cadena vacía y el usuario ve un
/// hueco — el modo de falla silencioso que ST-079 quería evitar. Acá el acceso
/// pasa por <see cref="AppStrings"/>, que son propiedades, y hay una prueba que
/// comprueba que <b>toda</b> clave usada existe en el archivo.</item>
/// <item><b>La app no está empaquetada</b> (<c>WindowsPackageType=None</c>). El
/// sistema de recursos de WinUI depende de un <c>resources.pri</c> que hay que
/// encontrar al lado del ejecutable; cuando no lo encuentra, la app abre con
/// <b>todos los textos en blanco</b>. Un <c>.resx</c> se compila dentro del
/// ensamblado y no puede faltar.</item>
/// <item><b>El español no puede desaparecer.</b> Va como cultura
/// <b>neutra</b>, o sea dentro del ensamblado principal: si mañana falta el
/// satélite de otro idioma, la app cae en español, nunca en blanco.</item>
/// <item><b>Las vistas no cambian de forma.</b> El XAML ya usa
/// <c>{x:Bind res:AppStrings.Algo}</c>; con <c>x:Uid</c> habría que rehacer
/// cada elemento. Acá solo cambia de dónde saca el texto
/// <see cref="AppStrings"/>.</item>
/// </list>
///
/// <para>El idioma sale de <see cref="CultureInfo.CurrentUICulture"/>, que es
/// el del sistema. El selector de Ajustes es B7b y lo único que tendrá que
/// hacer es fijar esa cultura al arrancar.</para>
/// </summary>
public static class Strings
{
    private static readonly ResourceManager Manager =
        new("AuraStudio.Core.Strings.Resources", typeof(Strings).Assembly);

    /// <summary>
    /// El texto de una clave.
    ///
    /// <para>Una clave que no está <b>se ve</b>: devuelve la clave entre
    /// corchetes en vez de una cadena vacía. Un hueco en la pantalla no dice
    /// qué falta y puede pasar meses sin que nadie lo note; <c>⟦ajustes.titulo⟧</c>
    /// se nota en la primera corrida y dice exactamente qué buscar. Que además
    /// no llegue nunca a pasar lo comprueba una prueba.</para>
    /// </summary>
    public static string Get(string key)
    {
        try
        {
            return Manager.GetString(key, CultureInfo.CurrentUICulture) ?? Missing(key);
        }
        catch (MissingManifestResourceException)
        {
            return Missing(key);
        }
    }

    /// <summary>
    /// El texto de una clave con formato. Los huecos van numerados
    /// (<c>{0}</c>), no interpolados: el orden de las palabras cambia con el
    /// idioma y quien traduce tiene que poder moverlos.
    /// </summary>
    public static string Format(string key, params object?[] arguments) =>
        string.Format(CultureInfo.CurrentUICulture, Get(key), arguments);

    /// <summary>
    /// El texto de una clave en la forma plural que corresponda a
    /// <paramref name="count"/> según la cultura activa (ST-247).
    ///
    /// <para>Las formas viven en el archivo de recursos como
    /// <c>&lt;clave&gt;.one</c>, <c>.few</c>, <c>.many</c> y <c>.other</c>, no en
    /// el código: un ternario <c>count == 1 ? "…" : "…"</c> es una regla del
    /// español metida en el programa, y en ruso hacen falta tres formas y en
    /// japonés una sola.</para>
    /// </summary>
    public static string Plural(string key, int count, params object?[] arguments) =>
        string.Format(CultureInfo.CurrentUICulture, Template(key, count), [count, .. arguments]);

    /// <summary>
    /// Igual que <see cref="Plural"/>, pero el número va escrito con el formato
    /// de la cultura, con sus separadores de miles.
    ///
    /// <para>Existe aparte porque no es lo mismo en todos lados: la barra de
    /// estado dice "1,234 canciones" y un mensaje de operación dice "1234
    /// archivos copiados". Unificarlos cambiaría lo que el usuario lee en uno
    /// de los dos, y B7a mueve, no redacta.</para>
    /// </summary>
    public static string PluralCount(string key, int count) =>
        string.Format(
            CultureInfo.CurrentUICulture,
            Template(key, count),
            count.ToString("N0", CultureInfo.CurrentCulture));

    /// <summary>
    /// La forma que le toca a <paramref name="count"/>, con su respaldo: si la
    /// cultura no trae esa forma se cae a <c>.other</c>, que toda cultura
    /// tiene. Mejor el plural de otra forma que un hueco.
    /// </summary>
    private static string Template(string key, int count)
    {
        string suffix = PluralRules.SuffixFor(count, CultureInfo.CurrentUICulture);

        return Manager.GetString(key + suffix, CultureInfo.CurrentUICulture)
               ?? Manager.GetString(key + PluralRules.OtherSuffix, CultureInfo.CurrentUICulture)
               ?? Missing(key + suffix);
    }

    private static string Missing(string key) => $"⟦{key}⟧";
}
