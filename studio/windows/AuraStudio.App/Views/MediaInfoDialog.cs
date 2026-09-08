using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using AuraStudio.App.Resources;
using AuraStudio.Core;
using AuraStudio.Core.Library;
using AuraStudio.Core.Resources;

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
            Title = Strings.Get("media-info-dialog.mas-informacion"),
            PrimaryButtonText = Strings.Get("media-info-dialog.guardar"),
            CloseButtonText = Strings.Get("media-info-dialog.cancelar"),
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

        // La llave es el campo, no su etiqueta.
        //
        // Estaba al revés —`fields["Álbum"]`— y mientras la app habló un solo
        // idioma funcionó. Traducir las etiquetas lo rompía sin avisar: una
        // punta que no coincidiera dejaba `Text` devolviendo cadena vacía y el
        // álbum se borraba al guardar, y dos campos que cayeran en la misma
        // etiqueta se pisaban. Ver MediaInfoFields (ST-247, B7d).
        var fields = new Dictionary<MediaInfoField, TextBox>();

        TextBox Field(MediaInfoField field, string value, bool digitsOnly = false)
        {
            var box = new TextBox { Header = MediaInfoFields.Label(field), Text = value };

            if (digitsOnly)
                box.TextChanged += (_, _) =>
                {
                    string clean = MediaInfoEdit.DigitsOnly(box.Text);
                    if (clean == box.Text) return;
                    int caret = Math.Min(box.SelectionStart, clean.Length);
                    box.Text = clean;
                    box.SelectionStart = caret;
                };

            fields[field] = box;
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
            Section(Strings.Get("media-info-dialog.section-rating"));
            content.Children.Add(stars);
            Caption(Strings.Get("media-info-dialog.rating-caption"));

            Section(Strings.Get("media-info-dialog.section-information"));
            content.Children.Add(incomplete);

            Field(MediaInfoField.Title, draft.Title);
            Field(MediaInfoField.Artist, draft.Artist);
            Field(MediaInfoField.Album, draft.Album);
            Field(MediaInfoField.AlbumArtist, draft.AlbumArtist);
            Field(MediaInfoField.TrackNumber, draft.TrackNumber, digitsOnly: true);
            Field(MediaInfoField.Year, draft.Year);
            Field(MediaInfoField.Genre, draft.Genre);
            Field(MediaInfoField.Composer, draft.Composer);

            Section(Strings.Get("media-info-dialog.section-lyrics"));
            TextBox lyrics = Field(MediaInfoField.Lyrics, draft.Lyrics);
            lyrics.AcceptsReturn = true;
            lyrics.Height = 120;
            lyrics.TextWrapping = TextWrapping.Wrap;
            lyrics.FontFamily = new Microsoft.UI.Xaml.Media.FontFamily("Consolas");
            Caption(Strings.Get("media-info-dialog.lyrics-caption"));

            void Validate()
            {
                MediaInfoDraft current = Read();
                bool complete = MediaInfoEdit.IsCompleteForSync(current, item.Kind);
                dialog.IsPrimaryButtonEnabled = complete;
                incomplete.IsOpen = !complete;
            }

            // Los obligatorios salen de Core, no de un arreglo escrito acá: si
            // mañana se agrega uno y nadie toca esta vista, el aviso de "falta
            // algo" no aparecería hasta cerrar la hoja. Y con TryGetValue: la
            // línea anterior usaba el indizador, así que una llave que no
            // estuviera reventaba al abrir.
            foreach (MediaInfoField required in MediaInfoFields.RequiredForMusic)
                if (fields.TryGetValue(required, out TextBox? box))
                    box.TextChanged += (_, _) => Validate();

            Validate();
        }

        // MARK: - Video

        if (item.Kind == LibraryItemKind.Video)
        {
            Section(Strings.Get("media-info-dialog.section-information"));
            Field(MediaInfoField.Title, draft.VideoTitle);

            if (isSeries)
            {
                Field(MediaInfoField.SeriesName, draft.SeriesName);
                Field(MediaInfoField.Season, draft.Season, digitsOnly: true);
                Field(MediaInfoField.Episode, draft.Episode, digitsOnly: true);
                Caption(Strings.Get("media-info-dialog.series-caption"));
            }
            else
            {
                // El nombre de la categoría no se escribe en la frase: se pide.
                // Escrito, en japonés diría "Series" y el selector de abajo
                // 「シリーズ」, y la frase mandaría a elegir algo que con ese
                // nombre no está en la lista.
                Caption(Strings.Format(
                    "media-info-dialog.series-hint", MediaCategory.Series.LocalizedName()));
            }
        }

        // MARK: - Categoría

        ComboBox? categoryBox = null;

        if (availableCategories is { Count: > 0 })
        {
            Section(Strings.Get("media-info-dialog.section-category"));
            categoryBox = new ComboBox
            {
                ItemsSource = availableCategories,
                SelectedItem = availableCategories.Contains(category) ? category : availableCategories[0],
                MinWidth = 220
            };
            content.Children.Add(categoryBox);
        }

        // MARK: - Archivo

        Section(Strings.Get("media-info-dialog.section-file"));
        var row = new MediaTableRow(item, fileSize);
        Info(Strings.Get("media-info-dialog.info-location"), item.SourcePath);
        Info(Strings.Get("media-info-dialog.info-format"), row.FileFormat);
        Info(Strings.Get("media-info-dialog.info-size"), row.FileSizeText);
        if (item.Metadata?.DurationSeconds is > 0)
            Info(Strings.Get("media-info-dialog.info-duration"), row.DurationText);
        Info(Strings.Get("media-info-dialog.info-status"), row.StatusText);

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
            Title = Text(MediaInfoField.Title),
            Artist = Text(MediaInfoField.Artist),
            Album = Text(MediaInfoField.Album),
            AlbumArtist = Text(MediaInfoField.AlbumArtist),
            TrackNumber = Text(MediaInfoField.TrackNumber),
            Year = Text(MediaInfoField.Year),
            Genre = Text(MediaInfoField.Genre),
            Composer = Text(MediaInfoField.Composer),
            Lyrics = Text(MediaInfoField.Lyrics),
            Rating = stars.Value,
            VideoTitle = item.Kind == LibraryItemKind.Video
                ? Text(MediaInfoField.Title)
                : draft.VideoTitle,
            SeriesName = Text(MediaInfoField.SeriesName),
            Season = Text(MediaInfoField.Season),
            Episode = Text(MediaInfoField.Episode)
        };

        // Un campo que esta hoja no mostró —los de serie en una película— no
        // está en el diccionario, y ahí "" es lo correcto: el `draft with` lo
        // sobreescribe con vacío y MediaInfoEdit ya trata vacío como ausente.
        string Text(MediaInfoField field) => fields.TryGetValue(field, out TextBox? box) ? box.Text : "";

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
            Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(
                button, Strings.Format("media-info-dialog.star-of-five", index));
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
