import Foundation
import Combine
import CoreGraphics

/// D-203: de donde sale la caratula cuando el archivo no trae una
/// propia. Cover Art Archive es la unica fuente activa desde el
/// principio (D-069); fanart.tv y Deezer son opcionales -- fanart.tv
/// necesita una API key propia (Keychain, ver `APIKeyStore`), Deezer no
/// necesita nada pero el usuario puede apagarla igual. El orden importa:
/// se prueban en la secuencia de `AppPreferences.coverArtProviderOrder`
/// y se usa la primera que devuelva un resultado.
enum CoverArtProvider: String, Codable, CaseIterable, Identifiable {
    case coverArtArchive, fanartTV, deezer

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .coverArtArchive: return "Cover Art Archive"
        case .fanartTV: return "fanart.tv"
        case .deezer: return "Deezer"
        }
    }

    /// Vive aca (no en `AppPreferences`, aislada a `@MainActor`) para que
    /// `LibraryEnricher` -- que corre fuera del main actor -- la pueda
    /// usar como valor default de parametro sin arrastrar aislamiento.
    static let defaultOrder: [CoverArtProvider] = [.coverArtArchive, .fanartTV, .deezer]
}

/// Preferencias de la app (no del dispositivo: los ajustes del firmware
/// viven en el iPod, en su propio aura.cfg). Se guardan en UserDefaults
/// -- son preferencias, no credenciales. La unica fuente que hoy pide
/// API key es fanart.tv (ver ServicesSettingsView); esa credencial vive
/// en el Keychain, no aca.
@MainActor
final class AppPreferences: ObservableObject {
    static let shared = AppPreferences()

    /// Como se resuelve la caratula de cada cancion al preparar la
    /// biblioteca. No es cosmetico: cambia que archivos terminan en el
    /// iPod y como los encuentra el firmware (find_albumart, D-010).
    enum CoverArtPolicy: String, Codable, CaseIterable, Identifiable {
        /// Una sola imagen por album, compartida por todas sus pistas:
        /// `cover.jpg` dentro de la carpeta del album. Es lo que el
        /// firmware busca primero y ocupa mucho menos espacio.
        case albumOnly
        /// Cada pista lleva su propia caratula embebida en el archivo,
        /// para singles y recopilaciones donde una portada por album
        /// seria incorrecta.
        case perTrack

        var id: String { rawValue }
    }

    @Published var coverArtPolicy: CoverArtPolicy {
        didSet { defaults.set(coverArtPolicy.rawValue, forKey: Keys.coverArtPolicy) }
    }

    /// Buscar letras sincronizadas al importar. Se puede apagar para que
    /// la importacion no toque la red.
    @Published var fetchSyncedLyrics: Bool {
        didSet { defaults.set(fetchSyncedLyrics, forKey: Keys.fetchSyncedLyrics) }
    }

    /// Completar metadata faltante contra servicios en linea. Apagado,
    /// solo se usa lo que ya traen las tags del archivo y su nombre.
    @Published var enrichOnline: Bool {
        didSet { defaults.set(enrichOnline, forKey: Keys.enrichOnline) }
    }

    /// Si ya se le ofreció al usuario volver a leer las etiquetas de su
    /// biblioteca con `LocalTagReader` (PLAN-studio-ux.md §2/P1) -- se
    /// pregunta una sola vez, nunca de nuevo aunque la respuesta haya
    /// sido "ahora no": la accion sigue disponible en el menu contextual.
    @Published var legacyMetadataBannerShown: Bool {
        didSet { defaults.set(legacyMetadataBannerShown, forKey: Keys.legacyMetadataBannerShown) }
    }

    /// ST-012: la revision "estas imagenes parecen caratulas" se ofrece
    /// una vez por instalacion (mismo criterio que
    /// `legacyMetadataBannerShown`).
    @Published var coverContaminationReviewShown: Bool {
        didSet { defaults.set(coverContaminationReviewShown, forKey: Keys.coverContaminationReviewShown) }
    }

    /// Identificador estable de ESTA instalacion de Aura Studio (no del
    /// usuario ni de la Mac -- se regenera si se reinstala). PLAN-general-sync.md
    /// §9/P7: se escribe como `SyncRecord.writtenBy` para que dos Macs
    /// sincronizando el mismo iPod no se pisen registros -- cada una
    /// solo trata como "propios" los que ella misma escribio. Generado
    /// una sola vez y reusado para siempre (`UUID().uuidString`, no hay
    /// nada sensible en el valor, no hace falta Keychain).
    let installationID: String

    /// Último nombre visto por dispositivo (`deviceID` → `deviceName`,
    /// PLAN-general-sync.md §1.5/§9) -- el nombre real vive EN el iPod
    /// (`device.cfg`); esto es solo el reflejo local para poder mostrar
    /// algo razonable en la barra lateral mientras está desconectado. El
    /// iPod manda siempre que está conectado.
    @Published var knownDeviceNames: [String: String] {
        didSet { defaults.set(knownDeviceNames, forKey: Keys.knownDeviceNames) }
    }

    /// ST-016: discos del iPod (clave `AuraDevice.diskRecordKey`: UUID del
    /// volumen, o serial USB si no hay) a los que ESTA instalacion de
    /// Studio ya les verifico el bootloader de la familia Rockbox en la
    /// NOR -- porque lo flasheo ella misma (`--bl-inst` con exito y el
    /// aparato salio de DFU), o porque vio ese disco conectado con
    /// Aura/Rockbox atendiendo el USB (solo un bootloader grabado pudo
    /// arrancar eso). Valor: fecha de la ultima verificacion. Es la
    /// segunda mitad de la evidencia que el instalador exige para
    /// saltarse el DFU (`AuraDevice.canSkipBootloaderFlash`) -- la NOR no
    /// se puede leer, asi que esto sustituye a "confiar en un archivo que
    /// pudo copiarse de otro iPod". Se borra al restaurar (`--bl-uninst`).
    @Published private(set) var bootloaderVerifiedDisks: [String: Date] {
        didSet { defaults.set(bootloaderVerifiedDisks, forKey: Keys.bootloaderVerifiedDisks) }
    }

    func isBootloaderVerified(diskKey: String?) -> Bool {
        guard let diskKey else { return false }
        return bootloaderVerifiedDisks[diskKey] != nil
    }

    func recordBootloaderVerified(diskKey: String?, at date: Date = Date()) {
        guard let diskKey, !diskKey.isEmpty else { return }
        bootloaderVerifiedDisks[diskKey] = date
    }

    func forgetBootloaderVerified(diskKey: String?) {
        guard let diskKey else { return }
        bootloaderVerifiedDisks.removeValue(forKey: diskKey)
    }

    @Published var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Keys.language)
            AppLanguageResolver.current = language.resolved
        }
    }

    /// Carpeta de la biblioteca Aura (encargo del dueño, 2026-08-13):
    /// por default es donde vive todo lo que la app necesita para
    /// funcionar como biblioteca -- el catalogo, lo preparado para el
    /// iPod, y (si `copyMediaIntoLibrary` esta activo) las copias de los
    /// archivos originales.
    @Published var libraryFolderPath: String {
        didSet { defaults.set(libraryFolderPath, forKey: Keys.libraryFolderPath) }
    }

    /// Si es `true` (default, y el unico comportamiento que existia
    /// hasta ahora): todo lo que se suelta en la app se COPIA a
    /// `Originales/` dentro de la biblioteca -- el archivo del usuario
    /// jamas se toca, pero queda una copia completa ahi.
    ///
    /// Si es `false`: la biblioteca REFERENCIA el archivo original en su
    /// ubicacion actual (nunca se copia), y solo guarda ahi la
    /// configuracion que lo liga al catalogo (metadata, letras,
    /// portadas) -- exactamente lo mismo que ya se escribe en
    /// `Preparados/`/`Portadas/`/`biblioteca.json` en ambos modos. La
    /// diferencia real ocurre recien al sincronizar: con copia, el
    /// archivo final para el iPod ya estaba preparado de antemano; sin
    /// copia, `LibraryViewModel.process(itemAt:)` arma ese archivo leyendo
    /// el original en su ubicacion externa en ese momento -- mas lento la
    /// primera vez que se procesa, pero el disco del usuario nunca
    /// termina con una copia duplicada de su biblioteca completa.
    @Published var copyMediaIntoLibrary: Bool {
        didSet { defaults.set(copyMediaIntoLibrary, forKey: Keys.copyMediaIntoLibrary) }
    }

    /// Como se arma la carpeta de cada cancion al sincronizar con el
    /// iPod. El tagcache de Rockbox escanea el volumen entero sin
    /// importar la profundidad de carpetas (a diferencia del navegador
    /// de fotos/video, que es plano por ahora -- ver `organizePhotos...`/
    /// `organizeVideos...` mas abajo), asi que esta eleccion es libre.
    enum MusicOrganization: String, Codable, CaseIterable, Identifiable {
        /// `Music/<Artista>/<Album>/`. El default desde D-180.
        case artistAlbum
        /// `Music/<Album>/`, sin carpeta de artista -- util para quien
        /// organiza por album sin pensar en el artista (recopilaciones,
        /// bandas sonoras).
        case album
        /// `Music/<Artista>/`, todas las canciones del artista juntas
        /// sin carpeta de album.
        case artist

        var id: String { rawValue }
    }

    /// Formato del nombre de archivo de cada cancion (sin extension).
    enum MusicFilenameFormat: String, Codable, CaseIterable, Identifiable {
        /// Solo el titulo. Default (encargo del dueño, 2026-08-13).
        case titleOnly
        /// "NN Titulo" -- con el numero de pista al frente.
        case trackNumberTitle
        /// "Titulo - Artista".
        case titleArtist
        /// "Titulo - Album".
        case titleAlbum

        var id: String { rawValue }
    }

    @Published var musicOrganization: MusicOrganization {
        didSet { defaults.set(musicOrganization.rawValue, forKey: Keys.musicOrganization) }
    }

    @Published var musicFilenameFormat: MusicFilenameFormat {
        didSet { defaults.set(musicFilenameFormat.rawValue, forKey: Keys.musicFilenameFormat) }
    }

    /// Calidad de audio al sincronizar. El iPod (y Rockbox) leen FLAC/
    /// ALAC/WAV sin problema, asi que "mantener original" es seguro por
    /// default -- comprimir es una eleccion del usuario para ahorrar
    /// espacio, no algo que la app le imponga.
    enum AudioQuality: String, Codable, CaseIterable, Identifiable {
        /// Copia el archivo tal cual (FLAC/ALAC/WAV/MP3/M4A sin tocar).
        /// Default: nunca se pierde calidad sin que el usuario lo pida.
        case originalLossless
        /// Transcodifica a MP3 256kbps VBR -- buena calidad, una
        /// fraccion del espacio de un FLAC.
        case compressed

        var id: String { rawValue }
    }

    @Published var audioQuality: AudioQuality {
        didSet { defaults.set(audioQuality.rawValue, forKey: Keys.audioQuality) }
    }

    /// Ancho maximo (en px) al redimensionar fotos para el LCD de
    /// 320x240 del iPod. `optimized` es el comportamiento que ya existia
    /// (D-028/ImageResizer) antes de que esto fuera una preferencia.
    enum PhotoQuality: String, Codable, CaseIterable, Identifiable {
        /// 320px de lado mayor -- el ancho nativo del LCD, el minimo
        /// espacio posible. Default.
        case optimized
        /// 640px -- se sigue comprimiendo (sigue siendo JPEG, sigue
        /// siendo mucho mas chico que la foto original de una camara o
        /// telefono actual), pero se ve mas nitida al hacer zoom en el
        /// visor del iPod, a cambio de mas espacio en disco.
        case hd

        var id: String { rawValue }

        var maxDimension: CGFloat {
            switch self {
            case .optimized: return 320
            case .hd: return 640
            }
        }
    }

    @Published var photoQuality: PhotoQuality {
        didSet { defaults.set(photoQuality.rawValue, forKey: Keys.photoQuality) }
    }

    /// Agrupar fotos/videos por categoria (fotos: colecciones editables,
    /// ver `photoCollections` abajo; videos: Videos/Series/Películas)
    /// SOLO dentro de la biblioteca de Aura Studio -- es una ayuda para
    /// que el usuario encuentre las cosas en la app. NO cambia la
    /// carpeta donde se sincronizan en el iPod
    /// (`Photos/`/`Videos/`, siempre planas): el navegador de fotos/
    /// video del firmware todavia no recorre subcarpetas (ver
    /// aura_photos.c/aura_video.c, D-062 sigue pendiente como su propia
    /// funcionalidad) -- anidar por categoria ahi haria que esos
    /// archivos dejaran de aparecer en el iPod, justo lo contrario de lo
    /// que se busca.
    @Published var organizePhotosByCategory: Bool {
        didSet { defaults.set(organizePhotosByCategory, forKey: Keys.organizePhotosByCategory) }
    }

    @Published var organizeVideosByCategory: Bool {
        didSet { defaults.set(organizeVideosByCategory, forKey: Keys.organizeVideosByCategory) }
    }

    /// Colecciones de fotos DENTRO de la biblioteca de Aura Studio
    /// (D-228): a diferencia de las categorias de video (fijas, ver
    /// `MediaCategory`), el dueño pidio que estas fueran editables sin
    /// tocar codigo -- se agregan/quitan desde Ajustes → Fotos. Cada
    /// nombre es ademas una subcarpeta real dentro de `Imágenes/` en la
    /// biblioteca local (ver `LibrarySync.localLibraryRelativePath`).
    /// Persistida como lista separada por comas, mismo criterio que
    /// `coverArtProviderOrder`. Quitar una coleccion de esta lista NO le
    /// cambia el valor a los items ya etiquetados con ella -- mismo
    /// comportamiento que borrar un tag no des-etiqueta lo existente.
    @Published var photoCollections: [String] {
        didSet {
            defaults.set(photoCollections.joined(separator: ","), forKey: Keys.photoCollections)
        }
    }

    /// Mismos tres nombres que sugiere `MediaCategoryHeuristics.
    /// classifyPhoto` -- asi "recien instalado, sin tocar nada" clasifica
    /// igual que antes de que esto fuera editable.
    static let defaultPhotoCollections = ["Imágenes", "Fotos", "IA"]

    /// Ignora nombres vacios/duplicados -- una coleccion repetida no
    /// tendria sentido en el picker (dos filas identicas para elegir).
    /// Tambien quita comas: `photoCollections` se persiste como lista
    /// separada por comas (mismo criterio que `coverArtProviderOrder`),
    /// y a diferencia de esa lista (valores fijos de un enum, nunca
    /// llevan coma) esta es texto libre del usuario -- una coma en el
    /// nombre partiria la entrada en dos al releer.
    func addPhotoCollection(_ name: String) {
        let trimmed = name
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !photoCollections.contains(trimmed) else { return }
        photoCollections.append(trimmed)
    }

    /// No toca los items ya etiquetados con `name` -- ver doc-comment de
    /// `photoCollections`.
    func removePhotoCollection(_ name: String) {
        photoCollections.removeAll { $0 == name }
    }

    // MARK: - Tabla de Canciones (ST-030)

    /// Columnas visibles de la tabla de Canciones, EN ORDEN (Título es
    /// fija y va aparte). Se editan desde "Opciones de visualización".
    /// Lista separada por comas, mismo criterio que
    /// `coverArtProviderOrder`.
    @Published var musicVisibleColumns: [MusicTableColumn] {
        didSet {
            defaults.set(musicVisibleColumns.map(\.rawValue).joined(separator: ","), forKey: Keys.musicVisibleColumns)
        }
    }

    /// Criterio y sentido de orden de la tabla de Canciones -- persiste
    /// para que la tabla vuelva como se dejo (antes el orden se perdia
    /// al cambiar de seccion).
    @Published var musicSortField: MusicSortField {
        didSet { defaults.set(musicSortField.rawValue, forKey: Keys.musicSortField) }
    }

    @Published var musicSortAscending: Bool {
        didSet { defaults.set(musicSortAscending, forKey: Keys.musicSortAscending) }
    }

    /// "Solo favoritos" del menu de encabezado. `false` = "Todas las
    /// canciones".
    @Published var musicShowOnlyFavorites: Bool {
        didSet { defaults.set(musicShowOnlyFavorites, forKey: Keys.musicShowOnlyFavorites) }
    }

    func toggleMusicColumn(_ column: MusicTableColumn) {
        if let index = musicVisibleColumns.firstIndex(of: column) {
            musicVisibleColumns.remove(at: index)
        } else {
            musicVisibleColumns.append(column)
        }
    }

    /// D-203: orden de intento para resolver caratula cuando falta.
    /// Persistido como lista separada por comas (mismo criterio que las
    /// columnas visibles de `MediaSectionView`) porque es un array chico
    /// de un enum simple -- no justifica el costo de un blob JSON.
    /// Entradas invalidas o repetidas de una version vieja se filtran al
    /// leer; si el resultado queda vacio, se vuelve al default.
    @Published var coverArtProviderOrder: [CoverArtProvider] {
        didSet {
            defaults.set(coverArtProviderOrder.map(\.rawValue).joined(separator: ","), forKey: Keys.coverArtProviderOrder)
        }
    }

    /// Deezer no pide key, pero el usuario puede apagarla igual (a
    /// diferencia de fanart.tv, cuyo "habilitado" real es tener una key
    /// guardada). Default true: sus terminos permiten explicitamente
    /// este uso (ver ServicesSettingsView) y no hay ninguna credencial
    /// que pedirle primero al usuario.
    @Published var deezerEnabled: Bool {
        didSet { defaults.set(deezerEnabled, forKey: Keys.deezerEnabled) }
    }

    /// Carpetas externas que el usuario arrastro a Aura Studio con
    /// "Crear copias de los medios en la Biblioteca de Aura" apagado
    /// (encargo del dueño, 2026-08-14, ver
    /// `LibraryViewModel.addDroppedFiles`). Aura no copia nada de ahi
    /// -- esta lista solo existe para que Ajustes → Biblioteca muestre
    /// que carpetas quedaron vinculadas. No hay watcher: un archivo que
    /// se agregue despues a esa carpeta no se importa solo, hay que
    /// volver a arrastrarlo (o la carpeta entera).
    ///
    /// Guardado como ruta plana (sin bookmark de seguridad): el proyecto
    /// corre con `ENABLE_APP_SANDBOX: NO` (D-033) -- sin sandbox de App
    /// Store no hace falta re-pedir acceso a una ruta ya concedida, la
    /// misma razon por la que `libraryFolderPath` de arriba tampoco usa
    /// uno. A diferencia de `photoCollections`/`coverArtProviderOrder`
    /// (listas separadas por comas), esta usa el arreglo nativo de
    /// `UserDefaults` (`set([String], forKey:)`/`stringArray(forKey:)`):
    /// ahi SÍ tiene sentido unir por comas porque son nombres cortos
    /// elegidos por el usuario o identificadores de un enum, nunca con
    /// coma real adentro (y `photoCollections` además la filtra al
    /// agregar). Una RUTA de carpeta real puede perfectamente traer una
    /// coma en el nombre ("Música, respaldo 2024") -- ahí sí uniría mal
    /// al separar, y a diferencia del nombre de una colección no se le
    /// puede quitar la coma sin romper la ruta real. El arreglo nativo
    /// evita el problema por completo, sin inventar un formato nuevo.
    @Published var linkedLibraryFolders: [String] {
        didSet {
            defaults.set(linkedLibraryFolders, forKey: Keys.linkedLibraryFolders)
        }
    }

    /// Dedup por ruta estandarizada -- soltar la misma carpeta dos veces
    /// no debe dejar dos filas identicas en Ajustes.
    func addLinkedLibraryFolder(_ url: URL) {
        let path = url.standardizedFileURL.path
        guard !linkedLibraryFolders.contains(path) else { return }
        linkedLibraryFolders.append(path)
    }

    /// "Quitar" de Ajustes: solo deja de listar la carpeta como
    /// vinculada. NO borra ni desvincula los `LibraryItem` que ya se
    /// importaron desde ahi -- esos siguen en la biblioteca igual que
    /// cualquier otro item, esto es pura higiene de la lista.
    func removeLinkedLibraryFolder(_ path: String) {
        linkedLibraryFolders.removeAll { $0 == path }
    }

    static var defaultLibraryFolderPath: String {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Aura Library", isDirectory: true).path
            ?? NSHomeDirectory() + "/Documents/Aura Library"
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let coverArtPolicy = "aura.coverArtPolicy"
        static let fetchSyncedLyrics = "aura.fetchSyncedLyrics"
        static let enrichOnline = "aura.enrichOnline"
        static let language = "aura.language"
        static let legacyMetadataBannerShown = "aura.legacyMetadataBannerShown"
        static let coverContaminationReviewShown = "aura.coverContaminationReviewShown"
        static let installationID = "aura.installationID"
        static let knownDeviceNames = "aura.knownDeviceNames"
        static let bootloaderVerifiedDisks = "aura.bootloaderVerifiedDisks"
        static let libraryFolderPath = "aura.libraryFolderPath"
        static let copyMediaIntoLibrary = "aura.copyMediaIntoLibrary"
        static let musicOrganization = "aura.musicOrganization"
        static let musicFilenameFormat = "aura.musicFilenameFormat"
        static let audioQuality = "aura.audioQuality"
        static let photoQuality = "aura.photoQuality"
        static let organizePhotosByCategory = "aura.organizePhotosByCategory"
        static let organizeVideosByCategory = "aura.organizeVideosByCategory"
        static let photoCollections = "aura.photoCollections"
        static let coverArtProviderOrder = "aura.coverArtProviderOrder"
        static let deezerEnabled = "aura.deezerEnabled"
        static let linkedLibraryFolders = "aura.linkedLibraryFolders"
        static let musicVisibleColumns = "aura.musicVisibleColumns"
        static let musicSortField = "aura.musicSortField"
        static let musicSortAscending = "aura.musicSortAscending"
        static let musicShowOnlyFavorites = "aura.musicShowOnlyFavorites"
        /// Clave vieja del menu "+" (D-199) -- solo se lee para migrar.
        static let legacyMusicExtraColumns = "aura.visibleColumns.music"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.coverArtPolicy = (defaults.string(forKey: Keys.coverArtPolicy)
            .flatMap(CoverArtPolicy.init(rawValue:))) ?? .albumOnly
        self.fetchSyncedLyrics = defaults.object(forKey: Keys.fetchSyncedLyrics) as? Bool ?? true
        self.enrichOnline = defaults.object(forKey: Keys.enrichOnline) as? Bool ?? true
        self.language = (defaults.string(forKey: Keys.language)
            .flatMap(AppLanguage.init(rawValue:))) ?? .system
        self.legacyMetadataBannerShown = defaults.object(forKey: Keys.legacyMetadataBannerShown) as? Bool ?? false
        self.coverContaminationReviewShown = defaults.object(forKey: Keys.coverContaminationReviewShown) as? Bool ?? false
        if let existingID = defaults.string(forKey: Keys.installationID) {
            self.installationID = existingID
        } else {
            let newID = UUID().uuidString
            defaults.set(newID, forKey: Keys.installationID)
            self.installationID = newID
        }
        self.knownDeviceNames = defaults.dictionary(forKey: Keys.knownDeviceNames) as? [String: String] ?? [:]
        self.bootloaderVerifiedDisks = defaults.dictionary(forKey: Keys.bootloaderVerifiedDisks) as? [String: Date] ?? [:]
        self.libraryFolderPath = defaults.string(forKey: Keys.libraryFolderPath)
            ?? Self.defaultLibraryFolderPath
        self.copyMediaIntoLibrary = defaults.object(forKey: Keys.copyMediaIntoLibrary) as? Bool ?? true
        self.musicOrganization = (defaults.string(forKey: Keys.musicOrganization)
            .flatMap(MusicOrganization.init(rawValue:))) ?? .artistAlbum
        self.musicFilenameFormat = (defaults.string(forKey: Keys.musicFilenameFormat)
            .flatMap(MusicFilenameFormat.init(rawValue:))) ?? .titleOnly
        self.audioQuality = (defaults.string(forKey: Keys.audioQuality)
            .flatMap(AudioQuality.init(rawValue:))) ?? .originalLossless
        self.photoQuality = (defaults.string(forKey: Keys.photoQuality)
            .flatMap(PhotoQuality.init(rawValue:))) ?? .optimized
        self.organizePhotosByCategory = defaults.object(forKey: Keys.organizePhotosByCategory) as? Bool ?? true
        self.organizeVideosByCategory = defaults.object(forKey: Keys.organizeVideosByCategory) as? Bool ?? true
        let storedCollections = defaults.string(forKey: Keys.photoCollections)?
            .split(separator: ",")
            .map { String($0) }
            .filter { !$0.isEmpty } ?? []
        self.photoCollections = storedCollections.isEmpty ? Self.defaultPhotoCollections : storedCollections
        let storedOrder = defaults.string(forKey: Keys.coverArtProviderOrder)?
            .split(separator: ",")
            .compactMap { CoverArtProvider(rawValue: String($0)) } ?? []
        self.coverArtProviderOrder = storedOrder.isEmpty ? CoverArtProvider.defaultOrder : storedOrder
        self.deezerEnabled = defaults.object(forKey: Keys.deezerEnabled) as? Bool ?? true
        self.linkedLibraryFolders = defaults.stringArray(forKey: Keys.linkedLibraryFolders) ?? []
        if let storedColumns = defaults.string(forKey: Keys.musicVisibleColumns) {
            // Lista vacia guardada a proposito = el usuario quito todas
            // las columnas opcionales (solo queda Título): se respeta.
            var seen = Set<MusicTableColumn>()
            self.musicVisibleColumns = storedColumns.split(separator: ",")
                .compactMap { MusicTableColumn(rawValue: String($0)) }
                .filter { seen.insert($0).inserted }
        } else {
            self.musicVisibleColumns = MusicTableColumn.migratingLegacyExtraColumns(
                defaults.string(forKey: Keys.legacyMusicExtraColumns))
        }
        self.musicSortField = defaults.string(forKey: Keys.musicSortField)
            .flatMap(MusicSortField.init(rawValue:)) ?? .title
        self.musicSortAscending = defaults.object(forKey: Keys.musicSortAscending) as? Bool ?? true
        self.musicShowOnlyFavorites = defaults.object(forKey: Keys.musicShowOnlyFavorites) as? Bool ?? false
        AppLanguageResolver.current = self.language.resolved
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case spanish
    case english

    var id: String { rawValue }

    /// Codigo que se le pasa a la tabla de cadenas. `system` se resuelve
    /// contra el idioma preferido de macOS, cayendo a espanol.
    var resolved: AppLanguage {
        guard self == .system else { return self }
        let preferred = Locale.preferredLanguages.first ?? "es"
        return preferred.hasPrefix("en") ? .english : .spanish
    }
}
