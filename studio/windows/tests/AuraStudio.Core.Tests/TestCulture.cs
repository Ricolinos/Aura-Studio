using System.Globalization;
using System.Runtime.CompilerServices;

namespace AuraStudio.Core.Tests;

/// <summary>
/// Fija la cultura de todas las pruebas en español de México (ST-247).
///
/// <para><b>Por qué hace falta ahora y no antes.</b> Hasta ST-247 los textos y
/// los formatos estaban clavados a <c>es-MX</c> en el código, así que la
/// cultura de la máquina que corriera las pruebas daba igual. Ahora los textos
/// salen de recursos por <see cref="CultureInfo.CurrentUICulture"/> y las
/// fechas y los números por <see cref="CultureInfo.CurrentCulture"/>: en cuanto
/// existan los satélites de B7b, una máquina configurada en inglés haría fallar
/// pruebas que comparan texto en español — y el fallo diría "esperaba
/// 'canciones', obtuve 'songs'", que parece un defecto y no lo es.</para>
///
/// <para>Se fija a propósito y no se lee del sistema: una prueba que dependa de
/// cómo está configurada la máquina no es una prueba, es una encuesta. Lo que
/// se comprueba de las <b>otras</b> culturas se hace pasándolas explícitamente,
/// como en <c>PluralRulesTests</c>.</para>
/// </summary>
internal static class TestCulture
{
    [ModuleInitializer]
    public static void Fix()
    {
        var spanish = new CultureInfo("es-MX");

        CultureInfo.DefaultThreadCurrentCulture = spanish;
        CultureInfo.DefaultThreadCurrentUICulture = spanish;
        CultureInfo.CurrentCulture = spanish;
        CultureInfo.CurrentUICulture = spanish;
    }
}
