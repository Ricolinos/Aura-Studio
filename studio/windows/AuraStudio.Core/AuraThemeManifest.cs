namespace AuraStudio.Core;

// ---------------------------------------------------------------------------
// ThemeLicense
// ---------------------------------------------------------------------------

/// <summary>
/// Licencia declarada por el constructor del tema -- el firmware la ignora
/// por completo (CONTRATO-formato-tema.md SS I); Studio la respeta al
/// ofrecer exportar/compartir.
/// </summary>
public sealed record ThemeLicense
{
    public static readonly ThemeLicense Open = new("open");
    public static readonly ThemeLicense Personal = new("personal");

    public string RawValue { get; }

    private ThemeLicense(string rawValue) => RawValue = rawValue;

    public static ThemeLicense Custom(string value) => new(value);

    public string DisplayName => RawValue.ToLowerInvariant() switch
    {
        "open" => "Libre",
        "personal" => "Uso personal",
        _ => RawValue,
    };

    public static ThemeLicense FromRawValue(string rawValue) =>
        rawValue.ToLowerInvariant() switch
        {
            "open" => Open,
            "personal" => Personal,
            _ => Custom(rawValue),
        };
}

// ---------------------------------------------------------------------------
// ThemePaletteRole
// ---------------------------------------------------------------------------

public static class ThemePaletteRole
{
    public static readonly string[] AllValues =
    [
        "shell_bg", "text_primary", "text_secondary", "text_tertiary",
        "shell_rail", "progress_fill", "progress_track", "selection_fill",
    ];
}

// ---------------------------------------------------------------------------
// ThemeCategoryKey
// ---------------------------------------------------------------------------

public static class ThemeCategoryKey
{
    public static readonly string[] AllValues =
    [
        "settings_gray", "video", "photos", "extras_yellow",
    ];
}

// ---------------------------------------------------------------------------
// AuraThemeManifest
// ---------------------------------------------------------------------------

/// <summary>
/// Manifiesto theme.cfg -- mismo formato "clave: valor" que aura.cfg
/// (settings_parseline() del firmware: sin comillas, # inicial comenta la
/// linea). CONTRATO-formato-tema.md SS B.
/// </summary>
public sealed class AuraThemeManifest : IEquatable<AuraThemeManifest>
{
    public int Format { get; set; }
    public string Id { get; set; }
    public string Name { get; set; }
    public string Author { get; set; }
    public ThemeLicense License { get; set; }
    public bool Redistributable { get; set; }
    public Dictionary<string, string> PaletteLight { get; set; }
    public Dictionary<string, string> PaletteDark { get; set; }
    public Dictionary<string, string> Category { get; set; }
    public string? AccentDefault { get; set; }
    public List<string> AccentPresets { get; set; }

    public AuraThemeManifest(
        int format = ThemeFormat.Current,
        string id = "",
        string name = "",
        string author = "",
        ThemeLicense? license = null,
        bool redistributable = false,
        Dictionary<string, string>? paletteLight = null,
        Dictionary<string, string>? paletteDark = null,
        Dictionary<string, string>? category = null,
        string? accentDefault = null,
        List<string>? accentPresets = null)
    {
        Format = format;
        Id = id;
        Name = name;
        Author = author;
        License = license ?? ThemeLicense.Personal;
        Redistributable = redistributable;
        PaletteLight = paletteLight ?? [];
        PaletteDark = paletteDark ?? [];
        Category = category ?? [];
        AccentDefault = accentDefault;
        AccentPresets = accentPresets ?? [];
    }

    public bool IsFormatCurrentOrOlder => Format <= ThemeFormat.Current;

    // -----------------------------------------------------------------------
    // Parse
    // -----------------------------------------------------------------------

    /// <summary>
    /// Parsea theme.cfg. null si no hay theme_format (obligatoria,
    /// CONTRATO-formato-tema.md SS G) o si el texto no tiene ninguna
    /// linea valida. Claves desconocidas se ignoran en silencio.
    /// </summary>
    public static AuraThemeManifest? Parse(string text)
    {
        int? format = null;
        var id = "";
        var name = "";
        var author = "";
        ThemeLicense license = ThemeLicense.Personal;
        bool redistributable = false;
        var paletteLight = new Dictionary<string, string>();
        var paletteDark = new Dictionary<string, string>();
        var category = new Dictionary<string, string>();
        string? accentDefault = null;
        var accentPresets = new List<string>();

        foreach (var rawLine in text.Split('\n'))
        {
            var line = rawLine.Trim();
            if (string.IsNullOrEmpty(line) || line.StartsWith('#'))
                continue;

            var colonIndex = line.IndexOf(':');
            if (colonIndex < 0) continue;

            var key = line[..colonIndex].Trim();
            var value = line[(colonIndex + 1)..].Trim();
            if (string.IsNullOrEmpty(key)) continue;

            switch (key)
            {
                case "theme_format":
                    if (int.TryParse(value, out var fmt)) format = fmt;
                    break;
                case "theme_id": id = value; break;
                case "theme_name": name = value; break;
                case "theme_author": author = value; break;
                case "theme_license": license = ThemeLicense.FromRawValue(value); break;
                case "theme_redistributable":
                    redistributable = string.Equals(value, "yes", StringComparison.OrdinalIgnoreCase);
                    break;
                case "accent_default": accentDefault = value; break;
                case "accent_presets":
                    accentPresets = value.Split(',', StringSplitOptions.TrimEntries)
                        .Where(s => !string.IsNullOrEmpty(s)).ToList();
                    break;
                default:
                    if (key.StartsWith("palette_light_"))
                    {
                        var roleKey = key["palette_light_".Length..];
                        paletteLight[roleKey] = value;
                    }
                    else if (key.StartsWith("palette_dark_"))
                    {
                        var roleKey = key["palette_dark_".Length..];
                        paletteDark[roleKey] = value;
                    }
                    else if (key.StartsWith("category_"))
                    {
                        var catKey = key["category_".Length..];
                        category[catKey] = value;
                    }
                    // Clave desconocida: se ignora en silencio.
                    break;
            }
        }

        if (format is null) return null;

        return new AuraThemeManifest
        {
            Format = format.Value,
            Id = id,
            Name = name,
            Author = author,
            License = license,
            Redistributable = redistributable,
            PaletteLight = paletteLight,
            PaletteDark = paletteDark,
            Category = category,
            AccentDefault = accentDefault,
            AccentPresets = accentPresets,
        };
    }

    // -----------------------------------------------------------------------
    // Serialize
    // -----------------------------------------------------------------------

    /// <summary>
    /// Serializa en el mismo orden que package_dist.sh escribe el tema
    /// por defecto reempaquetado.
    /// </summary>
    public string Serialized()
    {
        var lines = new List<string>
        {
            $"theme_format: {Format}",
            $"theme_id: {Id}",
            $"theme_name: {Name}",
        };

        if (!string.IsNullOrEmpty(Author))
            lines.Add($"theme_author: {Author}");

        lines.Add($"theme_license: {License.RawValue}");
        lines.Add($"theme_redistributable: {(Redistributable ? "yes" : "no")}");

        foreach (var role in ThemePaletteRole.AllValues)
        {
            if (PaletteLight.TryGetValue(role, out var hex))
                lines.Add($"palette_light_{role}: {hex}");
        }

        foreach (var role in ThemePaletteRole.AllValues)
        {
            if (PaletteDark.TryGetValue(role, out var hex))
                lines.Add($"palette_dark_{role}: {hex}");
        }

        foreach (var catKey in ThemeCategoryKey.AllValues)
        {
            if (Category.TryGetValue(catKey, out var hex))
                lines.Add($"category_{catKey}: {hex}");
        }

        if (AccentDefault is not null)
            lines.Add($"accent_default: {AccentDefault}");

        if (AccentPresets.Count > 0)
            lines.Add($"accent_presets: {string.Join(",", AccentPresets)}");

        return string.Join("\n", lines) + "\n";
    }

    // -----------------------------------------------------------------------
    // Equality
    // -----------------------------------------------------------------------

    public bool Equals(AuraThemeManifest? other)
    {
        if (other is null) return false;
        if (ReferenceEquals(this, other)) return true;
        return Format == other.Format
            && Id == other.Id
            && Name == other.Name
            && Author == other.Author
            && License == other.License
            && Redistributable == other.Redistributable
            && AccentDefault == other.AccentDefault;
    }

    public override bool Equals(object? obj) => Equals(obj as AuraThemeManifest);
    public override int GetHashCode() => HashCode.Combine(Format, Id, Name, Author);
}
