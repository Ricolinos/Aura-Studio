import Foundation

/// PLAN-studio-rendimiento-2.md Fase 3 (ST-182): el índice de agrupación
/// del catálogo -- `albumKey → ítems de música` y `ítem → albumKey` --
/// calculado UNA vez por versión del catálogo y reusado por todo lo que
/// necesite resolver "qué canciones son de este álbum".
///
/// Diagnóstico §0.6: abrir el menú contextual con N álbumes
/// seleccionados hacía, **por cada álbum**, un `filter` sobre los 12 000
/// ítems de la biblioteca calculando `albumKey` de cada uno (dos
/// normalizaciones de cadena: `folding` sin mayúsculas ni acentos, más
/// el recorte de artista principal de R2-4). Con los 1 000 álbumes
/// seleccionados son **12 millones de claves normalizadas** por apertura
/// de menú: la línea base de ST-180 (d) lo midió en **81 s**, contra un
/// objetivo de §A de 200 ms.
///
/// Acá esas 12 000 claves se calculan una sola vez y cada consulta pasa
/// a ser una búsqueda en diccionario. `keyByItemID` existe además de
/// `itemsByAlbumKey` para que resolver "de qué álbumes es esta
/// selección" no vuelva a normalizar nada: con 12 000 canciones
/// seleccionadas es la diferencia entre 24 000 `folding` y 12 000
/// búsquedas en una tabla hash.
///
/// Es una FOTO: vale para el catálogo y las opciones de agrupación con
/// los que se construyó. Quien lo guarda (`LibraryViewModel`) lo
/// descarta cuando cambia cualquiera de los dos, y solo lo reconstruye
/// si alguien lo pide -- así una biblioteca que nadie está mirando no
/// paga por mantenerlo al día.
///
/// Hermano en Windows de `LibraryCatalogIndex` (ST-201, `ByAlbumKey` /
/// `ItemsForKeys` / `GroupCount`): misma idea, cacheado por versión;
/// las APIs no tienen por qué coincidir.
struct LibraryCatalogIndex {
    /// Con qué opciones de agrupación se construyó -- cambiarlas cambia
    /// las claves, así que el índice deja de valer.
    let options: ArtistGroupingOptions

    private let itemsByAlbumKey: [String: [LibraryItem]]
    private let keyByItemID: [UUID: String]

    init(items: [LibraryItem], options: ArtistGroupingOptions) {
        self.options = options
        var buckets: [String: [LibraryItem]] = [:]
        var keys: [UUID: String] = [:]
        buckets.reserveCapacity(items.count / 8 + 1)
        keys.reserveCapacity(items.count)
        for item in items where item.kind == .music {
            let key = LibraryGrouping.albumKey(of: item, options: options)
            buckets[key, default: []].append(item)
            keys[item.id] = key
        }
        self.itemsByAlbumKey = buckets
        self.keyByItemID = keys
    }

    /// Cuántos álbumes distintos hay en el catálogo (incluido "Sin
    /// álbum", que es una clave más).
    var groupCount: Int { itemsByAlbumKey.count }

    /// Todas las canciones de ese álbum, en el orden del catálogo.
    func items(forAlbumKey key: String) -> [LibraryItem] {
        itemsByAlbumKey[key] ?? []
    }

    func trackCount(forAlbumKey key: String) -> Int {
        itemsByAlbumKey[key]?.count ?? 0
    }

    /// La clave de álbum de una canción, sin volver a normalizar nada.
    /// `nil` para lo que no sea música o no esté en el catálogo con el
    /// que se armó el índice.
    func albumKey(of item: LibraryItem) -> String? {
        keyByItemID[item.id]
    }

    func albumKey(ofItemID id: UUID) -> String? {
        keyByItemID[id]
    }

    /// Las claves de álbum que toca una selección, **sin repetir y en el
    /// orden en que aparecen**. El orden importa: es el que va a ver el
    /// usuario en la cola del selector de carátulas.
    func albumKeys(of selection: [LibraryItem]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for item in selection {
            guard let key = keyByItemID[item.id], seen.insert(key).inserted else { continue }
            result.append(key)
        }
        return result
    }

    func albumKeys(ofItemIDs ids: some Sequence<UUID>) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for id in ids {
            guard let key = keyByItemID[id], seen.insert(key).inserted else { continue }
            result.append(key)
        }
        return result
    }
}
