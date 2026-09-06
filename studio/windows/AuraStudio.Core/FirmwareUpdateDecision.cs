using AuraStudio.Core.Networking;

namespace AuraStudio.Core;

/// <summary>Qué se concluyó al buscar actualizaciones del firmware (ST-210).</summary>
public enum FirmwareUpdateOutcome
{
    /// <summary>
    /// No se pudo concluir nada: familia desconocida, sin volumen, o GitHub no
    /// contestó y tampoco hubo con qué comparar localmente. <b>Nunca se dice "al
    /// día" acá</b>: no saber y estar al día no son lo mismo.
    /// </summary>
    Unknown,

    /// <summary>Lo instalado es lo más nuevo que se conoce.</summary>
    UpToDate,

    /// <summary>Hay algo más nuevo <b>y esta copia de Studio lo trae</b>: se puede instalar ahora.</summary>
    UpdateAvailable,

    /// <summary>
    /// Se publicó algo más nuevo que lo que esta copia de Studio trae adentro.
    /// Se <b>avisa</b> y no se ofrece instalar: Studio instala lo que tiene en
    /// <c>Vendor\firmware-dist\</c>, no descarga Releases.
    /// </summary>
    NewerThanBundled
}

/// <summary>
/// Lo que la pantalla de Dispositivos muestra después de buscar
/// actualizaciones.
/// </summary>
/// <param name="InstalledTag">Lo que dice <c>version.txt</c> del iPod, si se pudo leer.</param>
/// <param name="PublishedTag">El Release más nuevo de la familia, si GitHub contestó.</param>
/// <param name="BundledTag">El pin que trae esta copia de Studio (<c>FIRMWARE_VERSION</c>).</param>
public readonly record struct FirmwareUpdateReport(
    FirmwareUpdateOutcome Outcome,
    string Message,
    string? InstalledTag = null,
    string? PublishedTag = null,
    string? BundledTag = null,
    UpdateVerdictReason Reason = UpdateVerdictReason.Unknown)
{
    /// <summary>
    /// Si el botón de actualizar tiene algo que hacer. <b>Solo</b> cuando lo más
    /// nuevo que se ofrece es lo que Studio ya tiene: ofrecer instalar un
    /// Release que no está descargado sería un botón que no puede cumplir.
    /// </summary>
    public bool CanInstallNow => Outcome == FirmwareUpdateOutcome.UpdateAvailable;
}

/// <summary>
/// La decisión de "¿hay actualización del firmware?", <b>pura y sin red</b>
/// (ST-210): entran el tag instalado, el Release más nuevo publicado, el pin que
/// trae esta copia de Studio y el veredicto por hash; sale qué decirle al
/// usuario y si el botón de actualizar sirve.
///
/// <para><b>Por qué existe.</b> Hasta ST-210, "Buscar actualizaciones" en
/// Dispositivos era sincrónico y <b>no salía a la red</b>: comparaba el iPod
/// contra el pin horneado y respondía "está al día" aunque hubiera un Release
/// nuevo publicado hacía semanas. El botón decía una cosa y hacía otra.</para>
///
/// <para><b>Tres versiones, no dos.</b> La del iPod, la publicada en GitHub y la
/// que Studio trae adentro. Confundir las dos últimas es lo que hacía que la
/// pantalla no pudiera decir "hay algo nuevo, pero para instalarlo actualiza
/// Studio" — que es la verdad cuando el Release es más nuevo que el pin, porque
/// Studio <b>no descarga firmware</b>: instala lo que hay en
/// <c>Vendor\firmware-dist\</c>.</para>
///
/// <para>ST-046: todo se compara <b>contra la familia instalada</b>. Sin familia
/// conocida no se ofrece nada — ofrecer "actualizar" ahí significaría ofrecer
/// sobrescribir Metro con Aura.</para>
/// </summary>
public static class FirmwareUpdateDecision
{
    /// <summary>Lo que se dice cuando no se pudo preguntar y tampoco concluir nada.</summary>
    public const string NoNetworkMessage =
        "No se pudo consultar GitHub para saber si hay una versión más nueva. " +
        "Revisa tu conexión y vuelve a intentar.";

    /// <param name="published">
    /// El Release más nuevo que GitHub devolvió, o <c>null</c> si no se pudo
    /// consultar. <c>null</c> <b>no</b> significa "no hay novedades".
    /// </param>
    /// <param name="networkFailed">
    /// Si la consulta se intentó y falló. Con <c>false</c> y
    /// <paramref name="published"/> nulo, es que no había a quién preguntar.
    /// </param>
    /// <param name="hashVerdict">
    /// El respaldo sin red de <see cref="AuraUpdateChecker"/>: compara el binario
    /// instalado contra el de esta copia de Studio. Es lo único que queda cuando
    /// el iPod no tiene <c>version.txt</c> o cuando GitHub no contesta.
    /// </param>
    public static FirmwareUpdateReport Decide(
        FirmwareFamily family,
        string? installedTag,
        string? published,
        string? bundledTag,
        UpdateVerdict hashVerdict,
        bool networkFailed)
    {
        // ST-046: sin repositorio no hay a quién preguntar ni binario propio con
        // qué comparar. Callar es lo correcto.
        if (family.ReleaseRepository is null)
        {
            return new FirmwareUpdateReport(
                FirmwareUpdateOutcome.Unknown,
                $"No se sabe de dónde salen las actualizaciones de {family.DisplayName}.");
        }

        // Un árbol incompleto se arregla reinstalando, y eso no depende de lo
        // que diga GitHub.
        if (hashVerdict.Reason == UpdateVerdictReason.InstalledBinaryMissing)
        {
            return new FirmwareUpdateReport(
                FirmwareUpdateOutcome.UpdateAvailable,
                $"El árbol de {family.DisplayName} en el iPod está incompleto. Reinstálalo desde el Instalador.",
                installedTag, published, bundledTag, hashVerdict.Reason);
        }

        SemVer? installed = Version(installedTag);
        SemVer? latest = Version(published);
        SemVer? bundled = Version(bundledTag);

        // Lo publicado es más nuevo que lo que Studio trae: se avisa y no se
        // ofrece instalar lo que no se tiene.
        bool publishedBeatsBundled = latest is not null && (bundled is null || bundled.Value < latest.Value);

        if (installed is not null && latest is not null)
        {
            if (installed.Value >= latest.Value)
            {
                return new FirmwareUpdateReport(
                    FirmwareUpdateOutcome.UpToDate,
                    $"{family.DisplayName} está al día: el iPod tiene {installedTag}, " +
                    "la versión más nueva publicada.",
                    installedTag, published, bundledTag, UpdateVerdictReason.VersionTag);
            }

            // El iPod está atrasado. ¿Con qué se lo puede adelantar?
            if (bundled is not null && installed.Value < bundled.Value)
            {
                string message = publishedBeatsBundled
                    ? $"Hay {family.DisplayName} {published} publicada. Esta copia de Aura Studio trae " +
                      $"{bundledTag}, que ya es más nueva que la del iPod ({installedTag}): puedes instalar " +
                      $"{bundledTag} ahora, o actualizar Aura Studio para tener {published}."
                    : $"Hay una versión más nueva de {family.DisplayName} ({published}).";

                return new FirmwareUpdateReport(
                    FirmwareUpdateOutcome.UpdateAvailable, message,
                    installedTag, published, bundledTag, UpdateVerdictReason.VersionTag);
            }

            return new FirmwareUpdateReport(
                FirmwareUpdateOutcome.NewerThanBundled,
                $"Se publicó {family.DisplayName} {published}, pero esta copia de Aura Studio trae " +
                $"{bundledTag ?? "una versión más vieja"}. Actualiza Aura Studio para poder instalarla.",
                installedTag, published, bundledTag, UpdateVerdictReason.VersionTag);
        }

        // Sin poder comparar por tag queda el respaldo por hash, que solo sabe
        // de lo que Studio trae adentro.
        if (hashVerdict.UpdateAvailable)
        {
            string message = latest is not null && publishedBeatsBundled
                ? $"El iPod tiene una versión más vieja de {family.DisplayName} que la de esta copia de " +
                  $"Aura Studio ({bundledTag}); la más nueva publicada es {published}."
                : $"Hay una versión más nueva de {family.DisplayName} ({bundledTag}) que la del iPod.";

            return new FirmwareUpdateReport(
                FirmwareUpdateOutcome.UpdateAvailable, message,
                installedTag, published, bundledTag, hashVerdict.Reason);
        }

        // Nada que ofrecer. Si además no se pudo preguntar, NO se dice "al día":
        // se dice exactamente lo que se sabe.
        if (networkFailed || latest is null)
        {
            string message = hashVerdict.Reason == UpdateVerdictReason.BinaryHash
                ? NoNetworkMessage + $" Lo instalado coincide con {family.DisplayName} {bundledTag}, " +
                  "que es lo que trae esta copia de Aura Studio."
                : NoNetworkMessage;

            return new FirmwareUpdateReport(
                FirmwareUpdateOutcome.Unknown, message,
                installedTag, published, bundledTag, hashVerdict.Reason);
        }

        if (publishedBeatsBundled)
        {
            return new FirmwareUpdateReport(
                FirmwareUpdateOutcome.NewerThanBundled,
                $"Se publicó {family.DisplayName} {published}, pero esta copia de Aura Studio trae " +
                $"{bundledTag ?? "otra versión"}. Actualiza Aura Studio para poder instalarla.",
                installedTag, published, bundledTag, hashVerdict.Reason);
        }

        return new FirmwareUpdateReport(
            FirmwareUpdateOutcome.UpToDate,
            $"{family.DisplayName} está al día: lo instalado coincide con {published}, " +
            "la versión más nueva publicada.",
            installedTag, published, bundledTag, hashVerdict.Reason);
    }

    /// <summary>
    /// Un tag ausente no es un tag ilegible, pero acá los dos significan lo
    /// mismo: no se puede comparar por versión.
    /// </summary>
    private static SemVer? Version(string? tag) =>
        tag is { Length: > 0 } ? SemVer.Parse(tag) : null;
}
