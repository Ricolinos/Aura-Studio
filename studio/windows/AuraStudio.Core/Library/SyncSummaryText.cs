using AuraStudio.Core.Resources;

namespace AuraStudio.Core.Library;

/// <summary>
/// La frase con la que termina una sincronización (ST-247, B7d).
///
/// <para><b>Por qué vive en Core.</b> Se armaba con cinco pedazos dentro de la
/// vista, y ninguno se podía leer entero desde una prueba. Es la misma mudanza
/// que hizo falta con <see cref="LibraryMigrationText"/>, por la misma razón:
/// una oración que se arma de partes solo se puede comprobar entera.</para>
///
/// <para><b>Y lo que se encontró al mudarla.</b> Los conteos estaban
/// pluralizados con paréntesis:</para>
///
/// <para><c>$"{result.FilesCopied} archivo(s) copiado(s)"</c>,
/// <c>$" y {result.FilesDeleted} quitado(s) del iPod"</c>,
/// <c>$" {result.Failures.Count} no se pudo(ieron) copiar."</c></para>
///
/// <para>Ese truco no funciona bien en ningún idioma —tampoco en español, que
/// es donde se escribió— y en los otros cinco no funciona en absoluto: el ruso
/// necesita tres formas y el alemán concuerda el verbo. Ahora cada conteo es
/// una forma de plural de verdad.</para>
///
/// <para>Toma números y no un <c>SyncResult</c> porque ese tipo vive en la
/// capa de la app: acá entra lo que la frase necesita y nada más.</para>
/// </summary>
public static class SyncSummaryText
{
    /// <param name="errorMessage">
    /// Lo que ya venía explicado desde más abajo. Si no hay nada, se dice que no
    /// se completó — nunca se deja al usuario con una frase vacía.
    /// </param>
    public static string Describe(
        bool success, string? errorMessage, int copied, int removed, int failures, bool cancelled)
    {
        if (!success)
            return errorMessage is { Length: > 0 } explained
                ? explained
                : Strings.Get("sync-summary.not-completed");

        List<string> parts = [Strings.Plural("sync-summary.copied", copied)];

        if (removed > 0) parts.Add(Strings.Plural("sync-summary.removed", removed));

        string done = string.Join(Strings.Get("sync-summary.joiner"), parts);

        if (failures == 0)
        {
            return Strings.Format(
                cancelled ? "sync-summary.cancelled" : "sync-summary.done", done);
        }

        return Strings.Format(
            cancelled ? "sync-summary.cancelled-with-failures" : "sync-summary.done-with-failures",
            done,
            Strings.Plural("sync-summary.failed-count", failures));
    }
}
