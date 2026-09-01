using AuraStudio.Core;
using AuraStudio.Core.Library;

namespace AuraStudio.App.Services;

/// <summary>Tema de la app. `System` sigue el de Windows (claro/oscuro).</summary>
public enum AppTheme
{
    System,
    Light,
    Dark
}

/// <summary>
/// Posición y tamaño de la ventana, en píxeles físicos de escritorio (lo que
/// usa <c>AppWindow</c>). Se guarda al cerrar y se restaura al abrir.
/// </summary>
public readonly record struct WindowPlacement(int X, int Y, int Width, int Height, bool Maximized);

/// <summary>
/// Preferencias locales de Aura Studio, persistidas en disco.
///
/// Equivalente de <c>AppPreferences.swift</c> (macOS, sobre `UserDefaults`).
/// En Windows la app corre **sin empaquetar** (`WindowsPackageType None`), así
/// que `Windows.Storage.ApplicationData` no está disponible: se guarda un JSON
/// bajo `%LOCALAPPDATA%`.
///
/// Acá viven **solo preferencias**. Las API keys nunca: van al Administrador de
/// credenciales de Windows vía <c>CredentialStore</c> (D-203/ST-032/ST-033),
/// jamás a este archivo.
/// </summary>
public interface IAppPreferences
{
    AppTheme Theme { get; set; }

    /// <summary>`null` la primera vez que se abre la app (sin nada que restaurar).</summary>
    WindowPlacement? WindowPlacement { get; set; }

    // MARK: - Biblioteca

    /// <summary>
    /// Dónde vive la biblioteca: el catálogo, lo preparado para el iPod y —si
    /// <see cref="CopyMediaIntoLibrary"/> está activo— las copias de los
    /// originales.
    /// </summary>
    string LibraryPath { get; set; }

    /// <summary>
    /// Con esto activo, lo que se suelta en la app se <b>copia</b> a la carpeta
    /// de la biblioteca; el archivo del usuario nunca se toca, pero queda una
    /// copia completa. Apagado, la biblioteca <b>referencia</b> el original
    /// donde está y solo guarda acá lo que lo liga al catálogo.
    /// </summary>
    bool CopyMediaIntoLibrary { get; set; }

    /// <summary>
    /// Carpetas externas que se arrastraron con la copia apagada. Solo se
    /// recuerdan para poder mostrarlas; <b>no hay vigilancia</b>: un archivo
    /// que se agregue después no se importa solo.
    /// </summary>
    IReadOnlyList<string> LinkedLibraryFolders { get; set; }

    CoverArtPolicy CoverArtPolicy { get; set; }

    /// <summary>Completar metadata faltante contra servicios en línea.</summary>
    bool EnrichOnline { get; set; }

    /// <summary>Buscar letras sincronizadas al importar.</summary>
    bool FetchSyncedLyrics { get; set; }

    // MARK: - Música

    MusicOrganization MusicOrganization { get; set; }
    MusicFilenameFormat MusicFilenameFormat { get; set; }
    AudioQuality AudioQuality { get; set; }

    // MARK: - Fotos y video

    PhotoQuality PhotoQuality { get; set; }
    bool OrganizePhotosByCategory { get; set; }
    bool OrganizeVideosByCategory { get; set; }

    /// <summary>
    /// ST-093: dónde está ffmpeg, cuando el usuario lo eligió a mano. Vacío =
    /// se busca solo. En macOS no existe este ajuste porque Homebrew lo deja
    /// siempre en el mismo lugar; en Windows puede estar en cualquier carpeta y
    /// sin esto el usuario quedaría sin recurso.
    /// </summary>
    string FfmpegPath { get; set; }

    /// <summary>Las colecciones de fotos, editables por el usuario (D-228).</summary>
    IReadOnlyList<string> PhotoCollections { get; set; }

    // MARK: - Servicios (D-203)

    /// <summary>Orden en que se prueban los proveedores de carátula.</summary>
    IReadOnlyList<CoverArtProvider> CoverArtProviderOrder { get; set; }

    /// <summary>
    /// Deezer no pide clave, pero se puede apagar igual — a diferencia de
    /// fanart.tv, cuyo "habilitado" real es tener una clave guardada.
    /// </summary>
    bool DeezerEnabled { get; set; }

    // MARK: - Tabla de Canciones (ST-030)

    /// <summary>
    /// Las columnas visibles, <b>en el orden en que el usuario las puso</b>: la
    /// lista es la configuración, no un conjunto. Título no está acá — es la
    /// columna fija que siempre va primero.
    /// </summary>
    IReadOnlyList<MusicTableColumn> MusicVisibleColumns { get; set; }

    MusicSortField MusicSortField { get; set; }

    bool MusicSortAscending { get; set; }

    /// <summary>Filtro "Solo favoritos" de la tabla de Canciones.</summary>
    bool MusicFavoritesOnly { get; set; }

    /// <summary>Barra de estado al pie de cada sección de la biblioteca (ST-063).</summary>
    bool ShowStatusBar { get; set; }

    /// <summary>
    /// Grupos de elementos similares que el usuario marcó como "no son lo
    /// mismo". No vuelven a aparecer hasta que se restablezcan.
    /// </summary>
    IReadOnlyList<string> IgnoredSimilarGroups { get; set; }

    /// <summary>
    /// «Agrupar las colaboraciones bajo el artista principal» (R2-4, ST-117),
    /// encendido por omisión. Ver <c>docs/normalizacion-artistas.md</c>.
    /// </summary>
    bool GroupCollaborations { get; set; }

    /// <summary>
    /// Nombres de grupo que contienen un separador y <b>no</b> se recortan
    /// ("Simon + Garfunkel"). La lista de separadores es cerrada y ciega; esta
    /// es la válvula de escape.
    /// </summary>
    IReadOnlyList<string> ArtistGroupingExceptions { get; set; }

    /// <summary>Las dos de arriba juntas, que es como las consume la agrupación.</summary>
    ArtistGroupingOptions ArtistGrouping { get; }

    /// <summary>
    /// Qué firmware instalaría el asistente (ST-047). Se elige en Extras y es
    /// una <b>preferencia</b>: elegir no toca el iPod. Actualizar desde General
    /// la ignora y reinstala la familia que el aparato ya tiene (ST-046).
    /// </summary>
    FirmwareFamily FirmwareFamilyToInstall { get; set; }

    // MARK: - Identidad de esta instalación

    /// <summary>
    /// Identificador estable de <b>esta instalación</b> de Aura Studio — no del
    /// usuario ni de la PC; se regenera si se reinstala. Se escribe en los
    /// registros de sincronización para que dos computadoras sincronizando el
    /// mismo iPod no se pisen: cada una trata como propios solo los que ella
    /// escribió. No hay nada sensible en el valor.
    /// </summary>
    string InstallationId { get; }

    /// <summary>Se dispara con el nombre de la preferencia que cambió.</summary>
    event EventHandler<string>? Changed;
}
