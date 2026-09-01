namespace AuraStudio.Core.Library;

public enum SyncAction
{
    /// <summary>Ya está en el iPod, igual y en el mismo lugar: no se toca.</summary>
    Skip,

    /// <summary>Hay que escribirlo: es nuevo, cambió, o se movió de lugar.</summary>
    Copy
}

/// <summary>
/// Lo que hay que hacer con un archivo de la biblioteca.
/// </summary>
/// <param name="SourcePath">De dónde se lee (el preparado, o el original).</param>
/// <param name="DestinationRelativePath">Dónde va, relativo a la raíz del volumen.</param>
/// <param name="StaleDestinationRelativePath">
/// Dónde estaba antes, si <b>se movió</b>. Hay que borrarlo de ahí o el iPod
/// termina con la canción dos veces — la razón por la que el plan lleva este
/// dato en vez de solo "copiar".
/// </param>
public sealed record SyncPlanItem(
    string SourcePath,
    string DestinationRelativePath,
    SyncAction Action,
    string? StaleDestinationRelativePath = null)
{
    public bool Moved => StaleDestinationRelativePath is { Length: > 0 };
}

/// <summary>Un archivo de la biblioteca listo para planificar.</summary>
public readonly record struct SyncSourceFile(
    string SourcePath, long SizeBytes, DateTimeOffset ModifiedAt, string DestinationRelativePath);

/// <summary>
/// Algo que Studio copió alguna vez y que ya no está en la biblioteca.
///
/// <para><b>No se borra solo.</b> El usuario lo confirma y recién entonces se
/// le pasa a <see cref="LibrarySyncEngine"/>: alguien que sacó una canción de
/// su biblioteca para reorganizarla no espera que desaparezca del iPod sin
/// avisar.</para>
/// </summary>
public readonly record struct SyncOrphan(string SourcePath, string DestinationRelativePath);

/// <param name="Items">Uno por archivo de la biblioteca, en el mismo orden.</param>
/// <param name="Orphans">Lo que ya no corresponde. Requiere confirmación.</param>
public sealed record SyncPlanResult(IReadOnlyList<SyncPlanItem> Items, IReadOnlyList<SyncOrphan> Orphans)
{
    public IEnumerable<SyncPlanItem> ToCopy => Items.Where(item => item.Action == SyncAction.Copy);

    public int SkipCount => Items.Count(item => item.Action == SyncAction.Skip);

    /// <summary>
    /// Los lugares viejos de lo que se movió. <b>Esto sí se borra solo</b>, y
    /// no es lo mismo que un huérfano: el archivo no desaparece, se está
    /// escribiendo ahora mismo en su lugar nuevo. Dejarlo sería tener la
    /// canción dos veces.
    /// </summary>
    public IReadOnlyList<string> ToSweep =>
    [
        .. Items.Where(item => item.Moved)
            .Select(item => item.StaleDestinationRelativePath!)
            .Distinct(StringComparer.OrdinalIgnoreCase)
    ];

    public bool HasChanges => ToCopy.Any() || ToSweep.Count > 0;

    /// <summary>Hay algo que proponerle al usuario, aunque no haya nada que copiar.</summary>
    public bool HasAnythingToDo => HasChanges || Orphans.Count > 0;
}

/// <summary>
/// Decide qué copiar, qué saltear y qué proponer para borrar. Port de
/// <c>SyncPlanner</c>.
///
/// <para>Puro a propósito: <b>no toca disco ni necesita un iPod</b>. La copia
/// real la hace <see cref="LibrarySyncEngine"/>, y así lo que decide se puede
/// probar entero.</para>
/// </summary>
public static class SyncPlanner
{
    /// <summary>
    /// Tolerancia al comparar fechas de modificación.
    ///
    /// <para>ST-090: macOS compara igualdad exacta porque siempre lee la misma
    /// fecha del mismo disco. Acá la biblioteca puede estar en una carpeta
    /// compartida de Parallels o en SMB, donde la fecha que ve Windows y la que
    /// vio la Mac difieren por el redondeo del transporte. Sin tolerancia, cada
    /// vez que el dueño cambia de app se recopiaría la biblioteca entera. Dos
    /// segundos es la granularidad de FAT32, el piso de todo lo que hay en
    /// juego; el tamaño se sigue comparando exacto.</para>
    /// </summary>
    public const double ModifiedAtToleranceSeconds = 2.0;

    /// <summary>
    /// <paramref name="previous"/> es el manifiesto de la última
    /// sincronización a <b>este</b> dispositivo. Un archivo se saltea solo si
    /// coinciden las tres cosas: tamaño, fecha y destino.
    ///
    /// <para>El destino entra en la comparación porque cambiar una preferencia
    /// —el layout de carpetas, el formato del nombre— no cambia el archivo pero
    /// sí dónde va: sin eso, reorganizar la biblioteca entera no copiaría
    /// nada.</para>
    /// </summary>
    public static SyncPlanResult Plan(IEnumerable<SyncSourceFile> current, DeviceSyncManifest previous)
    {
        var records = new Dictionary<string, DeviceSyncRecord>(previous.Records, StringComparer.OrdinalIgnoreCase);

        var items = new List<SyncPlanItem>();
        var stillPresent = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (SyncSourceFile file in current)
        {
            stillPresent.Add(file.SourcePath);

            if (!records.TryGetValue(file.SourcePath, out DeviceSyncRecord? record))
            {
                items.Add(new SyncPlanItem(file.SourcePath, file.DestinationRelativePath, SyncAction.Copy));
                continue;
            }

            bool sameDestination = string.Equals(record.DestinationRelativePath, file.DestinationRelativePath,
                StringComparison.OrdinalIgnoreCase);

            bool unchanged = record.SourceSize == file.SizeBytes
                             && Math.Abs(record.SourceModifiedAt - DeviceSyncRecord.ToTimeInterval(file.ModifiedAt))
                                <= ModifiedAtToleranceSeconds
                             && sameDestination;

            if (unchanged)
            {
                items.Add(new SyncPlanItem(file.SourcePath, file.DestinationRelativePath, SyncAction.Skip));
                continue;
            }

            // Si además cambió de lugar, hay que barrer el anterior.
            items.Add(new SyncPlanItem(file.SourcePath, file.DestinationRelativePath, SyncAction.Copy,
                sameDestination ? null : record.DestinationRelativePath));
        }

        List<SyncOrphan> orphans =
        [
            .. records.Values
                .Where(record => !stillPresent.Contains(record.SourcePath))
                .Select(record => new SyncOrphan(record.SourcePath, record.DestinationRelativePath))
        ];

        return new SyncPlanResult(items, orphans);
    }

    /// <summary>
    /// Qué secciones tocaría el plan, para anticiparle al usuario lo que el
    /// firmware va a reconstruir. Cuenta lo que se copia y lo que se barre;
    /// <b>los huérfanos no</b>, porque todavía nadie confirmó borrarlos.
    ///
    /// <para>Lo que de verdad se marca en <c>/.aura/sync-pending.json</c> lo
    /// devuelve <see cref="SyncOutcome"/>, contado sobre lo que realmente se
    /// escribió.</para>
    /// </summary>
    public static SyncPendingSections SectionsTouched(SyncPlanResult plan)
    {
        var sections = new SyncPendingSections();

        foreach (string path in plan.ToCopy.Select(item => item.DestinationRelativePath).Concat(plan.ToSweep))
            sections = sections.Including(path);

        return sections;
    }
}

/// <summary>
/// Las tres secciones del marcador. <b>Las listas no son una sección</b>: el
/// firmware las lee del directorio al entrar, no las indexa.
/// </summary>
public readonly record struct SyncPendingSections(bool Music, bool Video, bool Images)
{
    public bool IsEmpty => !Music && !Video && !Images;

    /// <summary>La misma más la sección a la que pertenece <paramref name="deviceRelativePath"/>.</summary>
    public SyncPendingSections Including(string deviceRelativePath)
    {
        if (deviceRelativePath.StartsWith(SyncLayout.MusicDirectory + "/", StringComparison.OrdinalIgnoreCase))
            return this with { Music = true };
        if (deviceRelativePath.StartsWith(SyncLayout.VideosDirectory + "/", StringComparison.OrdinalIgnoreCase))
            return this with { Video = true };
        if (deviceRelativePath.StartsWith(SyncLayout.PhotosDirectory + "/", StringComparison.OrdinalIgnoreCase))
            return this with { Images = true };

        return this;
    }
}
