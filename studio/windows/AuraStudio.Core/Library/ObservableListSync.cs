using System.Collections.ObjectModel;

namespace AuraStudio.Core.Library;

/// <summary>
/// Deja una <see cref="ObservableCollection{T}"/> igual a una lista deseada
/// <b>tocando solo lo que cambió</b> (ST-201).
///
/// <para>Antes, refrescar una cuadrícula tiraba las 1 091 tarjetas y construía
/// 1 091 nuevas. Eso cuesta tres veces: reconstruirlas, volver a suscribirse a
/// cada una, y —lo caro de verdad— obligar al control a rehacer todos sus
/// contenedores realizados, con lo que cada portada se vuelve a decodificar.
/// Y se hacía en cada refresco, incluso cuando el catálogo no había cambiado
/// en nada.</para>
///
/// <para>La identidad es por <b>referencia</b>, no por igualdad de contenido:
/// quien llama ya decidió qué instancia sobrevive y cuál se reemplaza —esa
/// decisión necesita saber qué campos importan, y acá no se sabe—. Lo que se
/// hace acá es el mínimo de quitar, insertar y mover para llegar a esa
/// lista.</para>
///
/// <para><b>Costo</b>: O(n) cuando no cambió nada, cuando solo cambió el
/// contenido de algunas posiciones, o cuando se agregó o se quitó un puñado. Un
/// reordenamiento completo —cambiar el criterio de orden— es el peor caso, y
/// pasa por acción explícita del usuario, no en cada clic.</para>
/// </summary>
public static class ObservableListSync
{
    /// <summary>
    /// <paramref name="target"/> queda igual a <paramref name="desired"/>.
    /// Devuelve cuántas operaciones de colección hizo — <b>0 significa que el
    /// control no se enteró de nada</b>, que es el caso que se busca en cada
    /// cambio de selección.
    /// </summary>
    /// <param name="onAdded">Se llama por cada instancia que entra (suscribirse).</param>
    /// <param name="onRemoved">Se llama por cada instancia que sale (desuscribirse).</param>
    public static int Apply<T>(
        ObservableCollection<T> target,
        IReadOnlyList<T> desired,
        Action<T>? onAdded = null,
        Action<T>? onRemoved = null)
        where T : class
    {
        if (AlreadyEqual(target, desired)) return 0;

        var wanted = new HashSet<T>(desired, ReferenceEqualityComparer.Instance);
        int edits = 0;

        // 1. Fuera lo que ya no está. De atrás hacia adelante: así los índices
        //    que faltan por mirar no se corren bajo los pies.
        for (int i = target.Count - 1; i >= 0; i--)
        {
            if (wanted.Contains(target[i])) continue;

            T removed = target[i];
            target.RemoveAt(i);
            onRemoved?.Invoke(removed);
            edits++;
        }

        // 2. Cada posición, en orden, con la instancia que le toca. Lo que queda
        //    en `target` es subconjunto de `desired`, así que o la instancia ya
        //    está más adelante (se mueve) o todavía no está (se inserta).
        for (int i = 0; i < desired.Count; i++)
        {
            T want = desired[i];
            if (i < target.Count && ReferenceEquals(target[i], want)) continue;

            int at = IndexFrom(target, want, i);

            if (at >= 0)
            {
                target.Move(at, i);
            }
            else
            {
                target.Insert(i, want);
                onAdded?.Invoke(want);
            }

            edits++;
        }

        // 3. Cola sobrante. Con una lista deseada sin repetidos no debería
        //    quedar nada, pero recortar de más es más barato que dejar tarjetas
        //    fantasma en pantalla.
        while (target.Count > desired.Count)
        {
            T removed = target[^1];
            target.RemoveAt(target.Count - 1);
            onRemoved?.Invoke(removed);
            edits++;
        }

        return edits;
    }

    private static bool AlreadyEqual<T>(ObservableCollection<T> target, IReadOnlyList<T> desired)
        where T : class
    {
        if (target.Count != desired.Count) return false;

        for (int i = 0; i < desired.Count; i++)
            if (!ReferenceEquals(target[i], desired[i])) return false;

        return true;
    }

    private static int IndexFrom<T>(ObservableCollection<T> target, T value, int start)
        where T : class
    {
        for (int i = start; i < target.Count; i++)
            if (ReferenceEquals(target[i], value)) return i;

        return -1;
    }
}
