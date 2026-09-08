using System.Globalization;
using AuraStudio.Core.Resources;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// El idioma que viaja al proceso elevado (ST-247, B7d).
///
/// <para><b>Por qué existe esto.</b> Aura Studio se relanza a sí misma con
/// permisos de administrador para formatear el disco del iPod. Ese proceso entra
/// por <c>Program.Main</c> y termina antes de que exista <c>App</c>, así que
/// nunca corre <c>ApplyLanguage</c>: se queda con la cultura del sistema.</para>
///
/// <para>Mientras sus mensajes estuvieron en español no se notaba. Traducidos,
/// alguien con Windows en alemán y la app puesta en inglés recibiría el
/// resultado del formateo en alemán dentro de una pantalla en inglés — dos
/// idiomas correctos en la misma operación, sin que falle nada. Es el mismo
/// fallo silencioso de las frases compuestas, repartido entre dos procesos.</para>
/// </summary>
public class UiCultureTests
{
    private static T Isolated<T>(Func<T> body)
    {
        CultureInfo before = CultureInfo.CurrentUICulture;
        CultureInfo? beforeDefault = CultureInfo.DefaultThreadCurrentUICulture;
        try
        {
            return body();
        }
        finally
        {
            CultureInfo.CurrentUICulture = before;
            CultureInfo.DefaultThreadCurrentUICulture = beforeDefault;
        }
    }

    [Theory]
    [InlineData("ja")]
    [InlineData("de")]
    [InlineData("ru")]
    [InlineData("en-GB")]
    public void ElIdiomaQueLlegaEsElQueSeAplica(string name) =>
        Assert.Equal(name, Isolated(() =>
        {
            Assert.True(UiCulture.Apply(name));
            return CultureInfo.CurrentUICulture.Name;
        }));

    /// <summary>
    /// Y lo que se manda es lo que se ve. Junto con la prueba de arriba, eso
    /// cierra el viaje de ida y vuelta: lo que el lado no elevado pone en la
    /// línea de comandos es lo que el elevado termina usando.
    /// </summary>
    [Fact]
    public void LoQueSeMandaEsLaCulturaDeLaInterfaz() =>
        Isolated(() =>
        {
            CultureInfo.CurrentUICulture = new CultureInfo("fr");
            Assert.Equal("fr", UiCulture.Current);

            UiCulture.Apply(UiCulture.Current);
            Assert.Equal("fr", CultureInfo.CurrentUICulture.Name);

            return true;
        });

    /// <summary>
    /// Un nombre que .NET no conoce <b>no detiene nada</b>. Del otro lado hay
    /// una operación que formatea un disco: abortarla porque el idioma de un
    /// mensaje no se pudo resolver cambiaría un defecto cosmético por uno que
    /// deja al usuario sin iPod.
    /// </summary>
    [Theory]
    [InlineData("")]
    [InlineData(null)]
    [InlineData("no-es-una-cultura-de-verdad")]
    public void UnNombreQueNoSirveDejaLaCulturaComoEstaba(string? name) =>
        Isolated(() =>
        {
            CultureInfo.CurrentUICulture = new CultureInfo("es");

            Assert.False(UiCulture.Apply(name));
            Assert.Equal("es", CultureInfo.CurrentUICulture.Name);

            return true;
        });
}
