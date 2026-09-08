namespace AuraStudio.Core.Resources;

/// <summary>
/// Si esta compilación ofrece los idiomas que <b>nadie revisó</b> (ST-247,
/// encargo de la Maestra para el release 0.4.0).
///
/// <para><b>Para qué existe.</b> El release 0.4.0 va a salir de un solo commit
/// para las dos plataformas, posterior al cierre de B7d. Si el dueño decide que
/// 0.4.0 salga con español e inglés nada más, Windows tiene que poder
/// construirse desde ese mismo commit sin ofrecer los cuatro — sin revertir
/// nada, sin una rama aparte y sin tocar <see cref="AppLanguages.All"/>.</para>
///
/// <para><b>Por qué un atributo de ensamblado y no un archivo.</b> La decisión
/// es de la compilación, no del equipo donde corre la app: un archivo en disco
/// se puede borrar, se puede copiar de otro paquete, y deja al mismo binario
/// comportándose distinto según dónde aterrice. Acá queda grabado en el
/// ensamblado que se publica, y se lee de ahí.</para>
///
/// <para><b>Y no un <c>#if</c>.</b> Con compilación condicional solo existe una
/// de las dos ramas en cada binario, así que las pruebas de una compilación no
/// pueden ejercitar la otra — y la que no se prueba es justamente la que se va a
/// usar una sola vez, el día del release, sin red. Siendo un atributo, la regla
/// es una función pura (<see cref="AppLanguages.Offering"/>) que se prueba con
/// los dos valores en la misma corrida.</para>
///
/// <para>Lo que <b>no</b> cambia es <c>Built</c>: los cinco satélites se generan
/// igual y el instalador los sigue exigiendo. Apagar el ofrecimiento no puede
/// sacar archivos del paquete, o volver a encenderlo dejaría de ser una
/// decisión de una línea.</para>
/// </summary>
/// <param name="Offered">
/// <c>true</c> —lo normal— ofrece los seis idiomas. <c>false</c> deja el selector
/// con los que sí revisó una persona.
/// </param>
[AttributeUsage(AttributeTargets.Assembly, AllowMultiple = false)]
public sealed class OfferMachineTranslationsAttribute(bool offered) : Attribute
{
    public bool Offered { get; } = offered;
}
