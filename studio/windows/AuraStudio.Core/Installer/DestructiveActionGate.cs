namespace AuraStudio.Core.Installer;

/// <summary>Por qué una acción destructiva no puede proceder.</summary>
public enum DestructiveRefusal
{
    None,

    /// <summary>No hay sobre qué actuar (el dispositivo se fue, o nunca estuvo).</summary>
    NoTarget,

    /// <summary>Falta la comprobación previa que valida que la operación es viable.</summary>
    NotChecked,

    /// <summary>Falta el consentimiento explícito del usuario para **esta** ejecución.</summary>
    NotConfirmed
}

/// <summary>
/// La regla de si una acción destructiva puede ejecutarse. Chica a propósito, y
/// en Core a propósito: es lógica de dominio, no de interfaz, y tiene que poder
/// probarse.
///
/// <para><b>De dónde sale.</b> El asistente exigía que un ensayo previo hubiera
/// pasado antes de ofrecer el formateo real, y trataba ese ensayo como permiso
/// suficiente. No lo es: **un ensayo comprueba, no autoriza**. El resultado fue
/// que el dueño ejecutó dos formateos reales creyendo que solo estaba probando
/// el software — tras el ensayo aparecía un único botón con estilo de acento,
/// justo donde había quedado el clic anterior, con la forma de un "Continuar".
/// El disco era sacrificable; en el iPod de un usuario habría sido su
/// biblioteca.</para>
///
/// <para>De ahí las tres condiciones separadas, y sobre todo que el
/// consentimiento se <b>consuma</b>: cada ejecución destructiva exige el suyo,
/// nunca hereda el de la anterior.</para>
/// </summary>
public sealed class DestructiveActionGate
{
    /// <summary>Hay un objetivo válido (un dispositivo presente y verificado).</summary>
    public bool HasTarget { get; set; }

    /// <summary>La comprobación previa (el ensayo) pasó para este objetivo.</summary>
    public bool Checked { get; private set; }

    /// <summary>El usuario confirmó **esta** ejecución, con el objetivo a la vista.</summary>
    public bool Confirmed { get; private set; }

    /// <summary>Registra que la comprobación previa pasó. No implica permiso.</summary>
    public void MarkChecked() => Checked = true;

    /// <summary>
    /// Registra o retira el consentimiento explícito. Confirmar **no** sustituye
    /// a la comprobación previa: son cosas distintas y se exigen las dos.
    /// </summary>
    public void SetConfirmed(bool confirmed) => Confirmed = confirmed;

    /// <summary>
    /// El objetivo cambió: se cae todo. Ni la comprobación ni el permiso valen
    /// para otro disco — el ensayo se hizo sobre otra geometría y el usuario
    /// confirmó sobre otro nombre.
    /// </summary>
    public void TargetChanged(bool hasTarget)
    {
        HasTarget = hasTarget;
        Checked = false;
        Confirmed = false;
    }

    public DestructiveRefusal Evaluate()
    {
        if (!HasTarget) return DestructiveRefusal.NoTarget;
        if (!Checked) return DestructiveRefusal.NotChecked;
        if (!Confirmed) return DestructiveRefusal.NotConfirmed;
        return DestructiveRefusal.None;
    }

    public bool CanProceed => Evaluate() == DestructiveRefusal.None;

    /// <summary>
    /// Toma el permiso y lo **consume**: devuelve `true` una sola vez por
    /// confirmación. La siguiente ejecución destructiva vuelve a necesitar que
    /// el usuario confirme.
    /// </summary>
    public bool TryConsume()
    {
        if (!CanProceed) return false;
        Confirmed = false;
        return true;
    }
}
