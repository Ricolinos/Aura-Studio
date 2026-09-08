using System.Text.RegularExpressions;
using AuraStudio.Core.Installer;
using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// Lo que la pantalla promete y lo que el código hace, cuando lo que el código
/// hace es una <b>cantidad</b> (ST-247, B7d — espejo de dos hallazgos de la Mac).
///
/// <para><b>De dónde salen estas dos pruebas.</b> La versión de macOS tuvo dos
/// defectos de la misma familia: la pantalla de privilegios nombraba dos
/// servicios cuando se pausaban tres, y un filtro comparaba la categoría contra
/// <c>"Fotografías"</c> cuando el clasificador devuelve <c>"Fotos"</c> — guarda
/// muerta, nunca verdadera. Ninguno de los dos se reproduce tal cual en Windows,
/// y eso es justamente lo que hay que dejar amarrado: hoy no pasa, y nada
/// impedía que empezara a pasar mañana.</para>
///
/// <para>Las dos miran el código, no el texto traducido. Una prueba que buscara
/// «servicio» en singular en seis idiomas sería una prueba de gramática ajena, y
/// se apagaría a la primera traducción legítima que la contradiga.</para>
/// </summary>
public class ServicePromiseTests
{
    private static string WindowsRoot()
    {
        DirectoryInfo? directory = new(AppContext.BaseDirectory);

        while (directory is not null)
        {
            string candidate = Path.Combine(directory.FullName, "studio", "windows");
            if (File.Exists(Path.Combine(candidate, "AuraStudio.Windows.slnx"))) return candidate;

            directory = directory.Parent;
        }

        throw new InvalidOperationException("No se encontró la raíz del repo desde el directorio de pruebas.");
    }

    /// <summary>
    /// Aura Studio pausa <b>un</b> servicio en Windows, y el texto lo dice en
    /// singular. Si mañana se pausa otro, esta prueba se pone roja antes de que
    /// la pantalla siga prometiendo uno.
    ///
    /// <para>Se cuenta sobre <see cref="PrivilegedOperationKind"/> y no sobre una
    /// lista escrita acá: el ejecutor privilegiado no acepta nada fuera de ese
    /// enum, así que agregar un servicio obliga a agregar un caso, y agregar un
    /// caso pone esto en rojo. Una constante <c>ServicesCount = 1</c> al lado del
    /// código habría pasado verde para siempre.</para>
    /// </summary>
    [Fact]
    public void SeDetieneUnSoloServicioYPorEsoElTextoVaEnSingular()
    {
        string[] pausing =
        [
            .. Enum.GetNames<PrivilegedOperationKind>()
                .Where(name => name.StartsWith("Pause", StringComparison.Ordinal)
                               && name.EndsWith("Service", StringComparison.Ordinal))
        ];

        Assert.True(pausing.Length == 1,
            $"Ahora se pausan {pausing.Length} servicios ({string.Join(", ", pausing)}) y las pantallas "
            + "siguen hablando de uno. Hay que actualizar, en los seis idiomas: "
            + "app-strings.service-pause-button, app-strings.service-pause-detail, "
            + "app-strings.service-pause-not-running y la familia privileged.service-*. "
            + "En macOS este mismo desfase dejó la pantalla nombrando dos servicios "
            + "mientras se pausaban tres.");

        // Y cada uno que se pausa se vuelve a arrancar: un servicio detenido sin
        // su pareja le quita iTunes al usuario para siempre.
        Assert.Equal(
            pausing.Select(name => name["Pause".Length..]),
            Enum.GetNames<PrivilegedOperationKind>()
                .Where(name => name.StartsWith("Resume", StringComparison.Ordinal))
                .Select(name => name["Resume".Length..]));
    }

    /// <summary>
    /// Las categorías contra las que <c>LibrarySyncFinalizer</c> compara existen
    /// de verdad. En la Mac una guarda comparaba contra un nombre que el
    /// clasificador no devuelve nunca: no fallaba, no avisaba, simplemente no se
    /// cumplía jamás — y contar fotos de menos no se nota mirando la pantalla.
    ///
    /// <para>Se leen del archivo fuente en vez de repetirlas acá, porque repetir
    /// la lista sería crear la segunda copia que este tipo de bug necesita para
    /// existir.</para>
    /// </summary>
    [Fact]
    public void LasCategoriasQueElResumenComparaExistenDeVerdad()
    {
        string source = File.ReadAllText(Path.Combine(
            WindowsRoot(), "AuraStudio.Core", "Library", "LibrarySyncFinalizer.cs"));

        List<string> compared =
        [
            .. Regex.Matches(source, @"Category\s*==\s*""([^""]+)""")
                .Select(match => match.Groups[1].Value)
                .Distinct(StringComparer.Ordinal)
        ];

        Assert.True(compared.Count > 0,
            "No se encontró ninguna comparación de categoría en LibrarySyncFinalizer. "
            + "Si se reescribió el resumen, esta prueba dejó de mirar algo y hay que "
            + "apuntarla a donde estén ahora.");

        List<string> unknown =
        [
            .. compared.Where(category =>
                !LibraryOptions.DefaultPhotoCollections.Contains(category, StringComparer.Ordinal))
        ];

        Assert.True(unknown.Count == 0,
            $"LibrarySyncFinalizer compara contra {string.Join(", ", unknown.Select(u => $"«{u}»"))}, "
            + $"y las colecciones de fotos que existen son {string.Join(", ", LibraryOptions.DefaultPhotoCollections.Select(c => $"«{c}»"))}. "
            + "Una comparación contra un nombre que nadie produce no falla: nunca se cumple, "
            + "y el resumen cuenta de menos sin decir nada.");
    }
}
