using AuraStudio.Core.Resources;

namespace AuraStudio.Core.Library;

/// <summary>
/// La frase que resume una migración (ST-247, B7c).
///
/// <para><b>Por qué se mudó acá.</b> Vivía dentro de <c>LibraryViewModel</c> y
/// estaba <b>a medio traducir</b>: B7a sacó a recursos el fragmento de las
/// etiquetas —porque tenía un ternario de plural y el extractor lo vio— y dejó
/// los otros siete pedazos como literales en el código, que era lo correcto
/// entonces. El resultado, con la app en alemán, es una sola oración con las
/// dos lenguas adentro:</para>
///
/// <para><c>"Biblioteca migrada: die Tags von 3 Titeln wurden geschrieben, se
/// ordenaron 2 preparados."</c></para>
///
/// <para>No falla nada, no hay error en ningún lado, y es ilegible. Una frase
/// que se arma de pedazos solo se puede comprobar entera, y por eso la
/// composición vive en Core y no en una vista: acá una prueba puede armarla en
/// cada idioma y leerla.</para>
///
/// <para>El orden de las partes también es texto: <c>summary</c> pone los dos
/// puntos y el punto final, y en otro idioma podrían ir de otra forma. Por eso
/// es una clave y no una interpolación escrita en el código.</para>
/// </summary>
public static class LibraryMigrationText
{
    /// <summary>
    /// El aviso de que esta biblioteca viene de una versión anterior, con lo que
    /// se encontró.
    ///
    /// <para>Estaba en el mismo estado que el resumen: los conteos salían del
    /// recurso y la oración que los envuelve —incluida la coma con «y» que une
    /// las dos partes— estaba escrita en el código. La barrida que buscaba otras
    /// frases compuestas lo encontró justo después de arreglar la primera.</para>
    ///
    /// <para>Cadena vacía cuando no hay nada que migrar: el aviso no se muestra,
    /// y decirlo con una frase sería peor que callarse.</para>
    /// </summary>
    public static string Needed(LibraryMigrationNeed need)
    {
        var parts = new List<string>();

        if (need.ItemsWithoutStorage > 0)
            parts.Add(Strings.Plural("library-view-model.migration-without-storage", need.ItemsWithoutStorage));

        if (need.LegacyPrepared > 0)
            parts.Add(Strings.Plural("library-view-model.migration-legacy-prepared", need.LegacyPrepared));

        if (parts.Count == 0) return "";

        string found = string.Join(Strings.Get("library-migration.needed-joiner"), parts);

        return Strings.Format("library-migration.needed-intro", found)
               + " "
               + Strings.Get("library-migration.needed-detail");
    }

    public static string Summarize(LibraryMigrationSummary summary)
    {
        if (summary.Touched == 0 && summary.Failed == 0)
        {
            return Strings.Get(summary.Cancelled
                ? "library-migration.cancelled-nothing-done"
                : "library-migration.already-up-to-date");
        }

        var parts = new List<string>();

        if (summary.Tagged > 0)
            parts.Add(Strings.Plural("library-view-model.migration-tagged", summary.Tagged));

        if (summary.PreparedRenamed > 0)
            parts.Add(Strings.Plural("library-migration.prepared-renamed", summary.PreparedRenamed));

        if (summary.PreparedBuilt > 0)
            parts.Add(Strings.Plural("library-migration.prepared-built", summary.PreparedBuilt));

        if (summary.OrphansDeleted > 0)
            parts.Add(Strings.Plural("library-migration.orphans-deleted", summary.OrphansDeleted));

        string done = parts.Count == 0
            ? Strings.Get("library-migration.no-changes")
            : string.Join(", ", parts);

        string head = Strings.Get(summary.Cancelled
            ? "library-migration.head-cancelled"
            : "library-migration.head-done");

        return summary.Failed > 0
            ? Strings.Format("library-migration.summary-with-failures", head, done,
                Strings.Plural("library-migration.failed", summary.Failed))
            : Strings.Format("library-migration.summary", head, done);
    }
}
