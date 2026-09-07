using AuraStudio.Core.Resources;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// Con trabajo en curso, cambiar el idioma no ofrece cerrar la app (ST-247,
/// B7b; decisión de la Maestra).
///
/// <para>El centro de tareas puede estar sincronizando el iPod, convirtiendo un
/// video, migrando una biblioteca o instalando firmware. Cerrar en medio de
/// cualquiera de esas deja algo a medias en el disco de alguien — y lo dejaría
/// por un cambio de idioma, que es lo más prescindible que hay en la
/// app.</para>
///
/// <para>La decisión vive en Core y no en la pantalla justamente para poder
/// comprobarla acá: si estuviera dentro del manejador del botón, la única forma
/// de saber si es correcta sería abrir la ventana con una sincronización
/// corriendo, que es la clase de prueba que nadie repite.</para>
/// </summary>
public class LanguageChangePromptTests
{
    /// <summary>Sin nada corriendo se puede cerrar, y el texto lo dice.</summary>
    [Fact]
    public void SinTareasEnCursoSePuedeCerrar()
    {
        LanguageChangeAdvice advice = LanguageChangePrompt.For(runningTasks: 0);

        Assert.True(advice.CanCloseNow);
        Assert.Equal(LanguageChangePrompt.SafeToCloseKey, advice.DetailKey);
    }

    /// <summary>
    /// Con una sola tarea ya no. No hace falta que sean muchas: una
    /// sincronización a medias es una sincronización a medias.
    /// </summary>
    [Theory]
    [InlineData(1)]
    [InlineData(2)]
    [InlineData(17)]
    public void ConTareasEnCursoNoSeOfreceCerrar(int running)
    {
        LanguageChangeAdvice advice = LanguageChangePrompt.For(running);

        Assert.False(advice.CanCloseNow);
        Assert.Equal(LanguageChangePrompt.BusyKey, advice.DetailKey);
    }

    /// <summary>
    /// Los dos textos existen y <b>son distintos</b>. Si el aviso dijera lo
    /// mismo en los dos casos, quitar el botón sería un misterio: el usuario
    /// vería desaparecer la única acción que se le ofrecía, sin explicación.
    /// </summary>
    [Fact]
    public void CadaCasoTieneSuPropioTextoYNoElMismo()
    {
        string safe = Strings.Get(LanguageChangePrompt.SafeToCloseKey);
        string busy = Strings.Get(LanguageChangePrompt.BusyKey);

        Assert.DoesNotContain('⟦', safe);
        Assert.DoesNotContain('⟦', busy);
        Assert.NotEqual(safe, busy);
    }

    /// <summary>
    /// Y el texto de "hay trabajo en curso" dice que <b>no</b> se cierre. Es la
    /// única frase del par que tiene que contener una instrucción: la otra
    /// acompaña a un botón, esta lo reemplaza.
    /// </summary>
    [Fact]
    public void ElTextoDeOcupadoPideQueNoSeCierre()
    {
        string busy = Strings.Get(LanguageChangePrompt.BusyKey);

        Assert.Contains("No la cierres", busy, StringComparison.Ordinal);
    }
}
