using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using AuraStudio.App.Resources;
using AuraStudio.Core;
using AuraStudio.Core.Library;

namespace AuraStudio.App.Views;

/// <param name="Metadata">La metadata editada; <c>null</c> si el elemento no es música.</param>
/// <param name="VideoInfo">Título y datos de serie; <c>null</c> si no es video.</param>
/// <param name="Category">La categoría elegida, si la hoja la ofrecía.</param>
public sealed record MediaInfoResult(
    TrackMetadata? Metadata,
    (string? Title, string? SeriesName, int? Season, int? Episode)? VideoInfo,
    string? Category);

/// <summary>
/// "Más información": todos los atributos del elemento en una hoja — metadata
/// completa, calificación, letra, categoría y los datos del archivo en disco.
/// Port de <c>MediaInfoView.swift</c>.
///
/// <para>Se arma en código y no en XAML porque los campos <b>dependen del tipo
/// de elemento y de su categoría</b>: una canción, una película y un episodio
/// de serie muestran cosas distintas. En XAML serían tres plantillas casi
/// iguales que se desincronizan solas.</para>
///
/// <para>Lo que decide qué es válido y qué se guarda está en
/// <see cref="MediaInfoEdit"/>, en Core y con pruebas. Acá solo hay campos.</para>
/// </summary>
public static class MediaInfoDialog
{
    public static async Task<MediaInfoResult?> ShowAsync(
        XamlRoot root, LibraryItem item, IReadOnlyList<string>? availableCategories, long fileSize)
    {
        MediaInfoDraft draft = MediaInfoDraft.From(item);
        bool isSeries = MediaCategoryNames.IsSeriesCategory(item.Category);
        string category = item.Category ?? availableCategories?.FirstOrDefault() ?? "";

        var content = new StackPanel { Spacing = 16, Width = 460 };

        // El diálogo se crea antes que los campos para que la validación pueda
        // habilitar y deshabilitar SU botón: un botón propio dentro del
        // contenido quedaría al lado del real y nadie sabría cuál usar.
        var dialog = new ContentDialog
        {
            XamlRoot = root,
            Title = "Más información",
            PrimaryButtonText = "Guardar",
            CloseButtonText = "Cancelar",
            DefaultButton = ContentDialogButton.Primary
        };

        // Un aviso que aparece solo cuando falta algo, y dice QUÉ falta.
        var incomplete = new InfoBar
        {
            Severity = InfoBarSeverity.Warning,
            IsClosable = false,
            Message = MediaInfoEdit.IncompleteReason,
            IsOpen = false
        };

        var fields = new Dictionary<string, TextBox>(StringComparer.Ordinal);

        TextBox Field(string label, string value, bool digitsOnly = false)
        {
            var box = new TextBox { Header = label, Text = value };

            if (digitsOnly)
                box.TextChanged += (_, _) =>
                {
                    string clean = MediaInfoEdit.DigitsOnly(box.Text);
                    if (clean == box.Text) return;
                    int caret = Math.Min(box.SelectionStart, clean.Length);
                    box.Text = clean;
                    box.SelectionStart = caret;
                };

            fields[label] = box;
            content.Children.Add(box);
            return box;
        }

        void Section(string title) => content.Children.Add(new TextBlock
        {
            Text = title,
            Style = (Style)Application.Current.Resources["AuraSectionTitleTextStyle"],
            Margin = new Thickness(0, 8, 0, 0)
        });

        void Caption(string text) => content.Children.Add(new TextBlock
        {
            Text = text,
            Style = (Style)Application.Current.Resources["AuraCaptionTextStyle"],
            TextWrapping = TextWrapping.Wrap
        });

        // MARK: - Música

        var stars = new StarRating { Value = draft.Rating };

        if (item.Kind == LibraryItemKind.Music)
        {
            Section("Calificación");
            content.Children.Add(stars);
            Caption("Se sincroniza con el iPod: la misma calificación que eliges aquí o en el aparato.");

            Section("Información");
            content.Children.Add(incomplete);

            Field("Título", draft.Title);
            Field("Artista", draft.Artist);
            Field("Álbum", draft.Album);
            Field("Artista del álbum (opcional)", draft.AlbumArtist);
            Field("Número de pista (opcional)", draft.TrackNumber, digitsOnly: true);
            Field("Año (opcional)", draft.Year);
            Field("Género (opcional)", draft.Genre);
            Field("Autor (opcional)", draft.Composer);

            Section("Letra (opcional)");
            TextBox lyrics = Field("", draft.Lyrics);
            lyrics.AcceptsReturn = true;
            lyrics.Height = 120;
            lyrics.TextWrapping = TextWrapping.Wrap;
            lyrics.FontFamily = new Microsoft.UI.Xaml.Media.FontFamily("Consolas");
            Caption("Se guarda junto a la canción y se muestra en el iPod mientras suena.");

            void Validate()
            {
                MediaInfoDraft current = Read();
                bool complete = MediaInfoEdit.IsCompleteForSync(current, item.Kind);
                dialog.IsPrimaryButtonEnabled = complete;
                incomplete.IsOpen = !complete;
            }

            foreach (string key in (string[])["Título", "Artista", "Álbum"])
                fields[key].TextChanged += (_, _) => Validate();

            Validate();
        }

        // MARK: - Video

        if (item.Kind == LibraryItemKind.Video)
        {
            Section("Información");
            Field("Título", draft.VideoTitle);

            if (isSeries)
            {
                Field("Nombre de la serie", draft.SeriesName);
                Field("Temporada", draft.Season, digitsOnly: true);
                Field("Episodio", draft.Episode, digitsOnly: true);
                Caption("El nombre con el que el episodio llega al iPod se arma con estos tres campos: cambiarlos y volver a sincronizar lo reagrupa.");
            }
            else
            {
                Caption("Los datos de serie aparecen al elegir la categoría Series aquí abajo y volver a abrir esta hoja.");
            }
        }

        // MARK: - Categoría

        ComboBox? categoryBox = null;

        if (availableCategories is { Count: > 0 })
        {
            Section("Categoría");
            categoryBox = new ComboBox
            {
                ItemsSource = availableCategories,
                SelectedItem = availableCategories.Contains(category) ? category : availableCategories[0],
                MinWidth = 220
            };
            content.Children.Add(categoryBox);
        }

        // MARK: - Archivo

        Section("Archivo");
        var row = new MediaTableRow(item, fileSize);
        Info("Ubicación", item.SourcePath);
        Info("Formato", row.FileFormat);
        Info("Tamaño", row.FileSizeText);
        if (item.Metadata?.DurationSeconds is > 0) Info("Duración", row.DurationText);
        Info("Estado", row.StatusText);

        void Info(string label, string value)
        {
            var grid = new Grid { ColumnSpacing = 12 };
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(96) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

            grid.Children.Add(new TextBlock
            {
                Text = label,
                Style = (Style)Application.Current.Resources["AuraCaptionTextStyle"]
            });

            var valueBlock = new TextBlock
            {
                Text = value,
                Style = (Style)Application.Current.Resources["AuraCaptionTextStyle"],
                TextWrapping = TextWrapping.Wrap,
                IsTextSelectionEnabled = true
            };
            Grid.SetColumn(valueBlock, 1);
            grid.Children.Add(valueBlock);

            content.Children.Add(grid);
        }

        MediaInfoDraft Read() => draft with
        {
            Title = Text("Título"),
            Artist = Text("Artista"),
            Album = Text("Álbum"),
            AlbumArtist = Text("Artista del álbum (opcional)"),
            TrackNumber = Text("Número de pista (opcional)"),
            Year = Text("Año (opcional)"),
            Genre = Text("Género (opcional)"),
            Composer = Text("Autor (opcional)"),
            Lyrics = Text(""),
            Rating = stars.Value,
            VideoTitle = item.Kind == LibraryItemKind.Video ? Text("Título") : draft.VideoTitle,
            SeriesName = Text("Nombre de la serie"),
            Season = Text("Temporada"),
            Episode = Text("Episodio")
        };

        string Text(string label) => fields.TryGetValue(label, out TextBox? box) ? box.Text : "";

        dialog.Content = new ScrollViewer { Content = content, MaxHeight = 560 };

        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return null;

        MediaInfoDraft edited = Read();

        return new MediaInfoResult(
            Metadata: item.Kind == LibraryItemKind.Music
                ? MediaInfoEdit.ToMetadata(edited, item.Metadata)
                : null,
            VideoInfo: item.Kind == LibraryItemKind.Video
                ? MediaInfoEdit.ToVideoInfo(edited, isSeries)
                : null,
            Category: categoryBox?.SelectedItem as string);
    }
}

/// <summary>
/// Cinco estrellas. Tocar la que ya está activa borra la calificación — el
/// mismo gesto que Música.app, y la única forma de volver a "sin calificar".
/// </summary>
public sealed partial class StarRating : StackPanel
{
    private readonly List<Button> _stars = [];
    private int _value;

    public StarRating()
    {
        Orientation = Orientation.Horizontal;
        Spacing = 2;

        for (int star = 1; star <= 5; star++)
        {
            int index = star;
            var button = new Button
            {
                Background = null,
                BorderThickness = new Thickness(0),
                Padding = new Thickness(4),
                Content = new FontIcon { Glyph = Glyphs.StarOutline }
            };
            Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(button, $"{index} de 5");
            button.Click += (_, _) => Value = MediaInfoEdit.RatingAfterTapping(Value, index);

            _stars.Add(button);
            Children.Add(button);
        }
    }

    public int Value
    {
        get => _value;
        set
        {
            _value = Math.Clamp(value, 0, 5);
            for (int i = 0; i < _stars.Count; i++)
                ((FontIcon)_stars[i].Content).Glyph = i < _value ? Glyphs.StarFilled : Glyphs.StarOutline;
        }
    }
}
