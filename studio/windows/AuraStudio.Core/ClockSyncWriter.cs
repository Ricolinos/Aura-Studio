using System.Text;

namespace AuraStudio.Core;

/// <summary>
/// Le pone la hora al iPod desde la computadora, para que el dueño nunca tenga
/// que configurarla a mano (contrato §D.4).
///
/// <para>Escribe en <c>aura.cfg</c> con el mismo cuidado que
/// <see cref="ThemeActivation"/>: <b>solo las líneas que le corresponden</b>,
/// dejando el resto del archivo igual. Las claves <c>rtc_sync_*</c> son
/// transitorias —el firmware las aplica una vez al reloj real y las descarta en
/// su próximo guardado—; <c>tz_local_quarters</c> es la misma clave persistente
/// que ya usa el reloj mundial, así que acá solo se refresca.</para>
/// </summary>
public static class ClockSyncWriter
{
    /// <summary>
    /// El texto de <c>aura.cfg</c> con la hora puesta. Puro: qué se escribe se
    /// puede revisar sin un iPod y sin depender de la hora de la máquina.
    /// </summary>
    public static string WithClock(string? auraConfigText, DateTimeOffset now)
    {
        List<string> lines = auraConfigText is null ? [] : [.. auraConfigText.Split('\n')];

        // Un archivo que terminaba en salto deja un renglón vacío al final: se
        // reutiliza en vez de ir agregando uno nuevo en cada sincronización.
        if (lines.Count > 0 && lines[^1].Length == 0) lines.RemoveAt(lines.Count - 1);

        Upsert(lines, "rtc_sync_year", now.Year);
        Upsert(lines, "rtc_sync_month", now.Month);
        Upsert(lines, "rtc_sync_day", now.Day);
        Upsert(lines, "rtc_sync_hour", now.Hour);
        Upsert(lines, "rtc_sync_min", now.Minute);
        Upsert(lines, "rtc_sync_sec", now.Second);

        // En cuartos de hora: hay husos de media hora y de 45 minutos, y el
        // firmware guarda el desfase en esa unidad.
        Upsert(lines, "tz_local_quarters", (int)(now.Offset.TotalSeconds / 900));

        var builder = new StringBuilder();
        foreach (string line in lines) builder.Append(line).Append('\n');

        return builder.ToString();
    }

    /// <summary>
    /// Lee, actualiza y reescribe <c>aura.cfg</c>.
    ///
    /// <para><b>Silencioso ante cualquier problema</b>: esto es una cortesía en
    /// segundo plano al conectar el iPod, y no puede interrumpir al usuario ni
    /// bloquear ningún otro flujo. Devuelve si alcanzó a escribir.</para>
    /// </summary>
    public static bool WriteToDisk(string volumeRoot, DateTimeOffset? now = null)
    {
        string path = Path.Combine(volumeRoot,
            ThemeActivation.AuraConfigRelativePath.Replace('/', Path.DirectorySeparatorChar));

        try
        {
            // Sin `aura.cfg` el firmware nunca arrancó en este iPod: no hay a
            // qué ponerle la hora todavía, y crear el archivo a medias sería
            // peor que no hacer nada.
            if (!File.Exists(path)) return false;

            string updated = WithClock(File.ReadAllText(path), now ?? DateTimeOffset.Now);

            string temporary = path + ".tmp";
            File.WriteAllText(temporary, updated, new UTF8Encoding(false));
            File.Move(temporary, path, overwrite: true);

            return true;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return false;
        }
    }

    private static void Upsert(List<string> lines, string key, int value)
    {
        string prefix = key + ":";

        for (int i = 0; i < lines.Count; i++)
        {
            if (!lines[i].StartsWith(prefix, StringComparison.Ordinal)) continue;

            lines[i] = $"{key}: {value}";
            return;
        }

        lines.Add($"{key}: {value}");
    }
}
