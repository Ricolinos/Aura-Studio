using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// Paridad de menús contextuales contra <c>docs/paridad-menus-contextuales.md</c>,
/// que es <b>vinculante</b> (ST-105).
///
/// <para>Lo que se prueba no son los textos —esos saltan a la vista— sino lo que
/// se pierde en silencio al portar un menú: el orden, dónde va cada separador,
/// qué se deshabilita en vez de esconderse, cuándo el texto va en plural, y
/// sobre todo <b>qué alcanza la acción</b>. Nada de eso da error al perderse:
/// da un menú parecido.</para>
/// </summary>
public class ContextMenuParityTests
{
    private static string[] Texts(IReadOnlyList<MenuEntry> menu) =>
        [.. menu.Select(item => item.IsSeparator ? "───" : item.Text)];

    private static readonly string[] VideoCategories = ["Videos", "Series", "Películas"];
    private static readonly string[] PhotoCollections = ["Fotos", "Imágenes", "IA"];

    // MARK: - Regla 0.1 — el criterio Finder

    [Fact]
    public void RightClickOnSomethingSelectedActsOnTheWholeSelection()
    {
        Assert.Equal(["a", "b", "c"], GridSelection.EffectiveIds("b", new[] { "a", "b", "c" }));
    }

    [Fact]
    public void RightClickOnSomethingNotSelectedActsOnlyOnThat()
    {
        // Y la selección anterior no se pierde: eso lo garantiza que esto NO la
        // toque.
        Assert.Equal(["z"], GridSelection.EffectiveIds("z", new[] { "a", "b" }));
    }

    [Fact]
    public void WithoutSelectionItActsOnWhatWasClicked()
    {
        Assert.Equal(["z"], GridSelection.EffectiveIds("z", Array.Empty<string>()));
    }

    // MARK: - Regla 0.5 — tres puntos, no el carácter «…»

    [Fact]
    public void EverythingThatOpensASheetEndsInThreeDots()
    {
        // La convención de macOS se conserva en Windows. El carácter "…" se ve
        // igual y no es lo mismo: un menú mezcla las dos formas y se nota.
        IEnumerable<MenuEntry> all =
        [
            .. LibraryContextMenus.ForAlbums(new MenuScope(1, SingleAlbumWithTitle: true)),
            .. LibraryContextMenus.ForArtistSong(false),
            .. LibraryContextMenus.ForEpisodes(new MenuScope(1), VideoCategories),
            .. LibraryContextMenus.ForPhotoAlbums(new MenuScope(1, AnyNamedAlbum: true), PhotoCollections),
            .. MediaTableContextMenu.Build(LibraryItemKind.Music, new MenuScope(1, SingleAlbumWithTitle: true))
        ];

        Assert.DoesNotContain(all, item => item.Text.Contains('…'));
        Assert.Contains(all, item => item.Text.EndsWith("...", StringComparison.Ordinal));
    }

    // MARK: - §1 Álbum

    [Fact]
    public void TheAlbumMenuOfOneAlbumIsExactlyTheDocument()
    {
        Assert.Equal(
        [
            "Abrir",
            "───",
            "Marcar como favorito",
            "Buscar información en línea",
            "Buscar carátulas del álbum...",
            "Aplicar carátula recomendada",
            "───",
            "Mostrar en el Explorador",
            "Eliminar álbum"
        ], Texts(LibraryContextMenus.ForAlbums(
            new MenuScope(1, SingleAlbumWithTitle: true, AnyNamedAlbum: true))));
    }

    /// <summary>
    /// R2-3 (ST-118): la acción automática del menú de Álbumes. Aplica sin
    /// preguntar <b>solo</b> lo que supere el umbral; lo que no, no se toca.
    /// </summary>
    [Fact]
    public void ApplyingTheRecommendedCoverNeedsSomeAlbumWithATitleOfItsOwn()
    {
        // "Sin álbum" no es un disco: no hay tapa que recomendarle.
        Assert.DoesNotContain("Aplicar carátula recomendada",
            Texts(LibraryContextMenus.ForAlbums(new MenuScope(1, AnyNamedAlbum: false))));

        Assert.Contains("Aplicar carátula recomendada a 3 álbumes",
            Texts(LibraryContextMenus.ForAlbums(new MenuScope(3, AnyNamedAlbum: true))));
    }

    [Fact]
    public void WhileApplyingTheRecommendedCoverTheItemIsDisabledNotHidden()
    {
        MenuEntry item = Assert.Single(
            LibraryContextMenus.ForAlbums(
                new MenuScope(1, AnyNamedAlbum: true, ApplyingRecommendedCover: true)),
            entry => entry.Id == "album.cover.recommended");

        // Se ve y no se puede usar: que desaparezca a mitad de la operación
        // deja al usuario pensando que se rompió.
        Assert.False(item.Enabled);
    }

    [Fact]
    public void WithSeveralAlbumsThereIsNoOpenAndTheTextIsPlural()
    {
        string[] texts = Texts(LibraryContextMenus.ForAlbums(new MenuScope(3)));

        Assert.DoesNotContain("Abrir", texts);
        Assert.Contains("Eliminar álbumes", texts);

        // Y sin "Abrir" tampoco va su separador: quedaría uno suelto arriba.
        Assert.NotEqual("───", texts[0]);
    }

    [Fact]
    public void SearchingCoversNeedsOneAlbumWithATitleOfItsOwn()
    {
        // Con una selección que mezcla discos no hay nada que buscar, y
        // "Sin álbum" no es un disco sino el cajón de lo que no tiene uno.
        Assert.DoesNotContain("Buscar carátulas del álbum...",
            Texts(LibraryContextMenus.ForAlbums(new MenuScope(2, SingleAlbumWithTitle: false))));

        Assert.DoesNotContain("Buscar carátulas del álbum...",
            Texts(LibraryContextMenus.ForAlbums(new MenuScope(1, SingleAlbumWithTitle: false))));
    }

    [Fact]
    public void FavoriteSaysRemoveOnlyWhenEverythingReachedIsAlreadyFavorite()
    {
        Assert.Contains("Quitar favorito",
            Texts(LibraryContextMenus.ForAlbums(new MenuScope(2, AllFavorite: true))));

        Assert.Contains("Marcar como favorito",
            Texts(LibraryContextMenus.ForAlbums(new MenuScope(2, AllFavorite: false))));
    }

    // MARK: - §2 Artista

    [Fact]
    public void TheArtistMenuOfOneArtistWithAPhotoIsExactlyTheDocument()
    {
        Assert.Equal(
        [
            "Marcar como favorito",
            "Buscar información en línea",
            "Buscar foto del artista",
            "Quitar foto del artista",
            "───",
            "Mostrar en el Explorador",
            "Eliminar artista"
        ], Texts(LibraryContextMenus.ForArtists(new MenuScope(1, HasArtistPhoto: true))));
    }

    [Fact]
    public void RemovingTheArtistPhotoNeedsSomeoneWhoActuallyHasOne()
    {
        // Nadie con foto: no hay nada que quitar.
        Assert.DoesNotContain("Quitar foto del artista",
            Texts(LibraryContextMenus.ForArtists(new MenuScope(1, HasArtistPhoto: false))));
        Assert.DoesNotContain("Quitar fotos de los artistas",
            Texts(LibraryContextMenus.ForArtists(new MenuScope(3, HasArtistPhoto: false))));
    }

    /// <summary>
    /// R2-2 (ST-119): antes se ofrecía SOLO con un artista seleccionado, así
    /// que quitar cinco fotos obligaba a cinco pasadas. La acción tiene sentido
    /// en plural, así que ahora se ofrece si alguno de los alcanzados la tiene.
    /// </summary>
    [Fact]
    public void RemovingTheArtistPhotoIsOfferedForSeveralArtistsToo()
    {
        Assert.Contains("Quitar fotos de los artistas",
            Texts(LibraryContextMenus.ForArtists(
                new MenuScope(3, HasArtistPhoto: true, ArtistsWithPhotoCount: 2))));

        // El plural lo decide CUÁNTOS la tienen, no cuántos se alcanzaron: con
        // tres artistas y una sola foto, se quita una sola foto.
        Assert.Contains("Quitar foto del artista",
            Texts(LibraryContextMenus.ForArtists(
                new MenuScope(3, HasArtistPhoto: true, ArtistsWithPhotoCount: 1))));
    }

    [Fact]
    public void SeveralArtistsPluralizeBothTheSearchAndTheDeletion()
    {
        string[] texts = Texts(LibraryContextMenus.ForArtists(new MenuScope(2)));

        Assert.Contains("Buscar fotos de los artistas", texts);
        Assert.Contains("Eliminar artistas", texts);
    }

    // MARK: - §3 Canción dentro de Artistas

    [Fact]
    public void TheSongInsideAnArtistIsAShortMenuAndAlwaysAboutThatSong()
    {
        Assert.Equal(
        [
            "Más información...",
            "Quitar de favoritos",
            "───",
            "Mostrar en el Explorador"
        ], Texts(LibraryContextMenus.ForArtistSong(isFavorite: true)));
    }

    // MARK: - §4 Tablas: se arma por bloques

    [Fact]
    public void TheMusicTableMenuIsExactlyTheDocument()
    {
        Assert.Equal(
        [
            "Buscar información en línea",
            "Buscar carátulas del álbum...",
            "Buscar letra",
            "Volver a leer etiquetas del archivo",
            "Eliminar carátula",
            "───",
            "Marcar como favorito",
            "───",
            "Seleccionar canciones del mismo álbum",
            "Seleccionar canciones del mismo artista",
            "───",
            "Cambiar nombre...",
            "Más información...",
            "───",
            "Mostrar en el Explorador",
            "Buscar elementos similares...",
            "───",
            "Eliminar"
        ], Texts(MediaTableContextMenu.Build(LibraryItemKind.Music,
            new MenuScope(1, SingleAlbumWithTitle: true, HasCover: true, HasAlbum: true, HasArtist: true))));
    }

    [Fact]
    public void RemovingTheCoverIsDisabledInsteadOfHiddenWhenThereIsNone()
    {
        // Que desaparezca dejaría al usuario buscando una opción que ayer estaba.
        MenuEntry item = Assert.Single(
            MediaTableContextMenu.Build(LibraryItemKind.Music, new MenuScope(2, HasCover: false)),
            entry => entry.Id == "cover.remove");

        Assert.False(item.Enabled);
    }

    [Fact]
    public void TheVideoBlockOnlyShowsUpForVideo()
    {
        Assert.Contains("Buscar póster en línea",
            Texts(MediaTableContextMenu.Build(LibraryItemKind.Video, new MenuScope(1))));

        Assert.DoesNotContain("Buscar póster en línea",
            Texts(MediaTableContextMenu.Build(LibraryItemKind.Music, new MenuScope(1))));

        // Y el de música no aparece sobre un video.
        Assert.DoesNotContain("Buscar letra",
            Texts(MediaTableContextMenu.Build(LibraryItemKind.Video, new MenuScope(1))));
    }

    [Fact]
    public void MusicHasNoCategorySubmenu()
    {
        // La música se organiza por artista y álbum, y eso se elige en Ajustes,
        // no elemento por elemento.
        Assert.DoesNotContain("Cambiar categoría",
            Texts(MediaTableContextMenu.Build(LibraryItemKind.Music, new MenuScope(1), VideoCategories)));
    }

    [Fact]
    public void BatchInfoIsOnlyForMusicAndOnlyWithMoreThanOne()
    {
        Assert.Contains("Obtener información...",
            Texts(MediaTableContextMenu.Build(LibraryItemKind.Music, new MenuScope(3))));

        Assert.DoesNotContain("Obtener información...",
            Texts(MediaTableContextMenu.Build(LibraryItemKind.Music, new MenuScope(1))));

        Assert.DoesNotContain("Obtener información...",
            Texts(MediaTableContextMenu.Build(LibraryItemKind.Photo, new MenuScope(3))));
    }

    [Fact]
    public void RenamingAndMoreInfoNeedExactlyOneElement()
    {
        string[] several = Texts(MediaTableContextMenu.Build(LibraryItemKind.Photo, new MenuScope(2)));

        Assert.DoesNotContain("Cambiar nombre...", several);
        Assert.DoesNotContain("Más información...", several);
    }

    [Fact]
    public void SyncingTheSelectionOnlyExistsWithAnIPodAndNeedsSomethingReady()
    {
        Assert.DoesNotContain("Sincronizar la selección",
            Texts(MediaTableContextMenu.Build(LibraryItemKind.Music, new MenuScope(2))));

        MenuEntry item = Assert.Single(
            MediaTableContextMenu.Build(LibraryItemKind.Music,
                new MenuScope(2, DeviceConnected: true, AnyReady: false)),
            entry => entry.Id == "sync.selection");

        Assert.False(item.Enabled);
    }

    [Fact]
    public void WithNothingReachedOnlyDeleteIsLeftAndItIsDisabled()
    {
        IReadOnlyList<MenuEntry> menu = MediaTableContextMenu.Build(LibraryItemKind.Music, new MenuScope(0));

        MenuEntry only = Assert.Single(menu);
        Assert.Equal("delete", only.Id);
        Assert.False(only.Enabled);
        Assert.Equal(MenuRole.Destructive, only.Role);
    }

    [Fact]
    public void SelectingTheSameAlbumOrArtistNeedsTheFirstSongToHaveOne()
    {
        string[] texts = Texts(MediaTableContextMenu.Build(LibraryItemKind.Music,
            new MenuScope(1, HasAlbum: false, HasArtist: false)));

        Assert.DoesNotContain("Seleccionar canciones del mismo álbum", texts);
        Assert.DoesNotContain("Seleccionar canciones del mismo artista", texts);
    }

    // MARK: - §5, §6, §7 — video

    [Fact]
    public void TheMovieMenuIsExactlyTheDocument()
    {
        Assert.Equal(
        [
            "Abrir",
            "───",
            "Marcar como favorito",
            "Buscar póster en línea",
            "Cambiar categoría",
            "───",
            "Mostrar en el Explorador",
            "Eliminar película"
        ], Texts(LibraryContextMenus.ForMovies(new MenuScope(1), VideoCategories)));
    }

    [Fact]
    public void SeriesIsTheSameMenuWithItsOwnTexts()
    {
        Assert.Contains("Eliminar series", Texts(LibraryContextMenus.ForSeries(new MenuScope(2), VideoCategories)));
        Assert.Contains("Eliminar serie", Texts(LibraryContextMenus.ForSeries(new MenuScope(1), VideoCategories)));
    }

    [Fact]
    public void TheEpisodeMenuOpensWithMoreInfoAndNotWithOpen()
    {
        Assert.Equal(
        [
            "Más información...",
            "───",
            "Marcar como favorito",
            "Cambiar categoría",
            "───",
            "Mostrar en el Explorador",
            "Eliminar episodio"
        ], Texts(LibraryContextMenus.ForEpisodes(new MenuScope(1), VideoCategories)));
    }

    [Fact]
    public void TheCategorySubmenuCarriesOneEntryPerCategory()
    {
        MenuEntry submenu = Assert.Single(
            LibraryContextMenus.ForMovies(new MenuScope(1), VideoCategories),
            entry => entry.Id == "category");

        Assert.Equal(["Videos", "Series", "Películas"], submenu.Submenu!.Select(item => item.Text));
    }

    // MARK: - §8, §9 — fotos

    [Fact]
    public void ThePhotoAlbumMenuOfOneNamedAlbumIsExactlyTheDocument()
    {
        Assert.Equal(
        [
            "Abrir",
            "───",
            "Cambiar categoría",
            "───",
            "Renombrar álbum...",
            "Disolver álbum",
            "───",
            "Mostrar en el Explorador",
            "Eliminar fotos de la biblioteca"
        ], Texts(LibraryContextMenus.ForPhotoAlbums(new MenuScope(1, AnyNamedAlbum: true), PhotoCollections)));
    }

    [Fact]
    public void WithOnlyTheUnnamedAlbumThereIsNothingToRenameOrDissolve()
    {
        string[] texts = Texts(LibraryContextMenus.ForPhotoAlbums(
            new MenuScope(1, AnyNamedAlbum: false), PhotoCollections));

        Assert.DoesNotContain("Renombrar álbum...", texts);
        Assert.DoesNotContain("Disolver álbum", texts);
        Assert.Contains("Eliminar fotos de la biblioteca", texts);
    }

    [Fact]
    public void TheCategorySubmenuIsDisabledWithoutPhotosInsteadOfDisappearing()
    {
        MenuEntry submenu = Assert.Single(
            LibraryContextMenus.ForPhotoAlbums(new MenuScope(1), PhotoCollections, hasPhotos: false),
            entry => entry.Id == "category");

        Assert.False(submenu.Enabled);
    }

    [Fact]
    public void DeletingPhotosHasNoPluralVariant()
    {
        // Es la misma frase con una foto o con doscientas.
        Assert.Contains("Eliminar fotos de la biblioteca",
            Texts(LibraryContextMenus.ForPhotoAlbums(new MenuScope(5, AnyNamedAlbum: true), PhotoCollections)));

        Assert.Contains("Eliminar de la biblioteca",
            Texts(LibraryContextMenus.ForPhotos(new MenuScope(5), PhotoCollections)));
    }

    [Fact]
    public void ThePhotoMenuIsExactlyTheDocument()
    {
        Assert.Equal(
        [
            "Vista previa",
            "───",
            "Cambiar categoría",
            "Quitar del álbum",
            "Mostrar en el Explorador",
            "───",
            "Eliminar de la biblioteca"
        ], Texts(LibraryContextMenus.ForPhotos(new MenuScope(1), PhotoCollections)));
    }

    [Fact]
    public void PreviewNeedsExactlyOnePhoto()
    {
        Assert.DoesNotContain("Vista previa", Texts(LibraryContextMenus.ForPhotos(new MenuScope(3), PhotoCollections)));
    }

    // MARK: - §10 Tema

    [Fact]
    public void TheDefaultThemeHasNoMenuAtAll()
    {
        // No es lo mismo que un menú con un solo ítem deshabilitado: macOS no
        // muestra ninguno.
        Assert.Empty(LibraryContextMenus.ForTheme(isDefaultTheme: true));
    }

    [Fact]
    public void AnyOtherThemeCanBeDeleted()
    {
        MenuEntry only = Assert.Single(LibraryContextMenus.ForTheme(isDefaultTheme: false));

        Assert.Equal("Eliminar", only.Text);
        Assert.Equal(MenuRole.Destructive, only.Role);
    }

    // MARK: - Lo destructivo va marcado (regla 0.3)

    [Fact]
    public void EverythingThatDeletesIsMarkedAsDestructive()
    {
        IEnumerable<MenuEntry> all =
        [
            .. LibraryContextMenus.ForAlbums(new MenuScope(1)),
            .. LibraryContextMenus.ForArtists(new MenuScope(1)),
            .. LibraryContextMenus.ForMovies(new MenuScope(1), VideoCategories),
            .. LibraryContextMenus.ForSeries(new MenuScope(1), VideoCategories),
            .. LibraryContextMenus.ForEpisodes(new MenuScope(1), VideoCategories),
            .. LibraryContextMenus.ForPhotoAlbums(new MenuScope(1, AnyNamedAlbum: true), PhotoCollections),
            .. LibraryContextMenus.ForPhotos(new MenuScope(1), PhotoCollections),
            .. MediaTableContextMenu.Build(LibraryItemKind.Music, new MenuScope(1))
        ];

        Assert.All(all.Where(item => item.Id is "delete" or "album.dissolve"),
            item => Assert.Equal(MenuRole.Destructive, item.Role));
    }

    // MARK: - Ningún menú queda con separadores sueltos

    [Fact]
    public void NoMenuStartsOrEndsWithASeparatorNorHasTwoInARow()
    {
        IReadOnlyList<MenuEntry>[] menus =
        [
            LibraryContextMenus.ForAlbums(new MenuScope(1, SingleAlbumWithTitle: true)),
            LibraryContextMenus.ForAlbums(new MenuScope(4)),
            LibraryContextMenus.ForArtists(new MenuScope(1, HasArtistPhoto: true)),
            LibraryContextMenus.ForArtists(new MenuScope(2), canFetchPhotos: false),
            LibraryContextMenus.ForArtistSong(true),
            LibraryContextMenus.ForMovies(new MenuScope(2), VideoCategories),
            LibraryContextMenus.ForSeries(new MenuScope(1), VideoCategories),
            LibraryContextMenus.ForEpisodes(new MenuScope(3), VideoCategories),
            LibraryContextMenus.ForPhotoAlbums(new MenuScope(1, AnyNamedAlbum: true), PhotoCollections),
            LibraryContextMenus.ForPhotoAlbums(new MenuScope(2), PhotoCollections),
            LibraryContextMenus.ForPhotos(new MenuScope(1), PhotoCollections),
            MediaTableContextMenu.Build(LibraryItemKind.Music,
                new MenuScope(1, SingleAlbumWithTitle: true, HasAlbum: true, HasArtist: true)),
            MediaTableContextMenu.Build(LibraryItemKind.Music, new MenuScope(3, DeviceConnected: true)),
            MediaTableContextMenu.Build(LibraryItemKind.Video, new MenuScope(1), VideoCategories),
            MediaTableContextMenu.Build(LibraryItemKind.Photo, new MenuScope(2), PhotoCollections),
            MediaTableContextMenu.Build(LibraryItemKind.Music, new MenuScope(0))
        ];

        foreach (IReadOnlyList<MenuEntry> menu in menus)
        {
            Assert.False(menu[0].IsSeparator, "empieza con separador");
            Assert.False(menu[^1].IsSeparator, "termina con separador");

            for (int i = 1; i < menu.Count; i++)
                Assert.False(menu[i].IsSeparator && menu[i - 1].IsSeparator, "dos separadores seguidos");
        }
    }
}

/// <summary>
/// §11: el menú de los encabezados de la tabla de Canciones. El mismo contenido
/// sale del clic derecho en el encabezado y del botón de la barra superior — dos
/// listas armadas por separado se desincronizan en cuanto alguien agregue una
/// opción a una sola.
/// </summary>
public class SongsHeaderMenuTests
{
    private static string[] Texts(IReadOnlyList<MenuEntry> menu) =>
        [.. menu.Select(item => item.IsSeparator ? "───" : item.Text)];

    [Fact]
    public void TheHeaderMenuIsExactlyTheDocument()
    {
        Assert.Equal(
        [
            "Todas las canciones",
            "Solo favoritos",
            "───",
            "Opciones para ordenar",
            "───",
            "Mostrar opciones de visualización"
        ], Texts(SongsHeaderMenu.Build(favoritesOnly: false, MusicSortField.ByTitle, ascending: true)));
    }

    [Fact]
    public void TheFilterCheckmarkFollowsTheFilter()
    {
        IReadOnlyList<MenuEntry> off = SongsHeaderMenu.Build(false, MusicSortField.ByTitle, true);
        Assert.True(off[0].Checked);
        Assert.False(off[1].Checked);

        IReadOnlyList<MenuEntry> on = SongsHeaderMenu.Build(true, MusicSortField.ByTitle, true);
        Assert.False(on[0].Checked);
        Assert.True(on[1].Checked);
    }

    [Fact]
    public void TheSortSubmenuMarksTheCurrentFieldAndDirection()
    {
        MenuEntry submenu = Assert.Single(
            SongsHeaderMenu.Build(false, MusicSortField.ByTitle, ascending: false),
            entry => entry.Id == "sort");

        IReadOnlyList<MenuEntry> items = submenu.Submenu!;

        // Un campo marcado, y exactamente uno.
        Assert.Single(items, item => !item.IsSeparator
                                     && item.Id.StartsWith("sort:", StringComparison.Ordinal)
                                     && item.Checked);

        Assert.False(items.Single(item => item.Id == "sort.ascending").Checked);
        Assert.True(items.Single(item => item.Id == "sort.descending").Checked);
    }

    [Fact]
    public void EveryOrderFieldOfTheTableIsOffered()
    {
        MenuEntry submenu = Assert.Single(
            SongsHeaderMenu.Build(false, MusicSortField.ByTitle, true), entry => entry.Id == "sort");

        Assert.Equal(MusicSortField.MenuFields.Count,
            submenu.Submenu!.Count(item => item.Id.StartsWith("sort:", StringComparison.Ordinal)));
    }

    [Fact]
    public void TheSortSubmenuHasItsSeparatorBetweenFieldsAndDirection()
    {
        IReadOnlyList<MenuEntry> items = Assert.Single(
            SongsHeaderMenu.Build(false, MusicSortField.ByTitle, true), entry => entry.Id == "sort").Submenu!;

        int separator = items.ToList().FindIndex(item => item.IsSeparator);

        Assert.True(separator > 0);
        Assert.Equal("sort.ascending", items[separator + 1].Id);
        Assert.False(items[0].IsSeparator);
        Assert.False(items[^1].IsSeparator);
    }

    // MARK: - Buscar carátulas, en singular y en plural (ST-206)

    [Fact]
    public void ConUnAlbumConTituloElItemVaEnSingular()
    {
        IReadOnlyList<MenuEntry> menu = MediaTableContextMenu.Build(
            LibraryItemKind.Music, new MenuScope(12, SingleAlbumWithTitle: true, AlbumCount: 1));

        Assert.Contains(menu, item => item.Id == "album.covers"
                                      && item.Text == "Buscar carátulas del álbum...");
    }

    [Fact]
    public void ConVariosAlbumesElItemVaEnPluralYDiceCuantos()
    {
        // Es el caso que el dueño reportó: en Canciones con todo seleccionado el
        // ítem NO aparecía. La respuesta no es esconderlo sino buscar la de cada
        // uno.
        IReadOnlyList<MenuEntry> menu = MediaTableContextMenu.Build(
            LibraryItemKind.Music, new MenuScope(12_000, AlbumCount: 7));

        Assert.Contains(menu, item => item.Id == "album.covers"
                                      && item.Text == "Buscar carátulas de 7 álbumes...");
    }

    [Fact]
    public void SinNingunAlbumConTituloNoHayNadaQueBuscar()
    {
        // "Sin álbum" no es un disco: es el cajón de lo que no tiene uno.
        IReadOnlyList<MenuEntry> menu = MediaTableContextMenu.Build(
            LibraryItemKind.Music, new MenuScope(40, AlbumCount: 0));

        Assert.DoesNotContain(menu, item => item.Id == "album.covers");
    }

    [Fact]
    public void ElMenuDeAlbumesNoDuplicaLaAccionEnLote()
    {
        // En Álbumes el lote ya se ofrece como "Aplicar carátula recomendada a N
        // álbumes" (R2-3): dos ítems que hacen lo mismo en el mismo menú son
        // peor que uno.
        IReadOnlyList<MenuEntry> menu = LibraryContextMenus.ForAlbums(
            new MenuScope(7, AnyNamedAlbum: true, AlbumCount: 7));

        Assert.DoesNotContain(menu, item => item.Id == "album.covers");
        Assert.Contains(menu, item => item.Id == "album.cover.recommended"
                                      && item.Text == "Aplicar carátula recomendada a 7 álbumes");
    }

    [Fact]
    public void EnAlbumesUnoSoloSigueAbriendoSuSelector()
    {
        IReadOnlyList<MenuEntry> menu = LibraryContextMenus.ForAlbums(
            new MenuScope(1, SingleAlbumWithTitle: true, AnyNamedAlbum: true, AlbumCount: 1));

        Assert.Contains(menu, item => item.Id == "album.covers"
                                      && item.Text == "Buscar carátulas del álbum...");
    }
}
