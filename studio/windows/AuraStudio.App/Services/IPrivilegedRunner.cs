using AuraStudio.Core.Installer;

namespace AuraStudio.App.Services;

/// <summary>
/// Ejecuta una de las operaciones privilegiadas de la lista cerrada
/// (<see cref="PrivilegedOperation"/>) pidiendo permisos de administrador.
///
/// <para><b>La promesa que esto sostiene.</b> En macOS, `PermissionsView` le
/// promete al usuario por escrito que nunca va a tener que abrir Terminal ni
/// escribir un comando: Aura Studio explica en su propia pantalla qué va a
/// pasar y por qué, y recién después aparece el diálogo del sistema. Acá es
/// igual, con UAC en lugar del diálogo de macOS. Quien llame a esto **ya** debe
/// haber mostrado esa explicación.</para>
///
/// <para><b>Nunca una API genérica.</b> No hay forma de pedirle a esto que corra
/// un comando arbitrario: solo acepta una <see cref="PrivilegedOperation"/>, y
/// el proceso elevado la vuelve a validar antes de hacer nada.</para>
/// </summary>
public interface IPrivilegedRunner
{
    /// <summary>Esta copia de Aura Studio ya corre con permisos de administrador.</summary>
    bool IsElevated { get; }

    /// <summary>
    /// Pide la elevación y ejecuta. Si el usuario cierra el diálogo de UAC, el
    /// resultado lo dice con esas palabras — cancelar no es un error.
    /// </summary>
    Task<PrivilegedOperationResult> RunAsync(PrivilegedOperation operation, CancellationToken ct = default);
}
