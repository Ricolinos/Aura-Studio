namespace AuraStudio.Tools.ExtraerCadenasWindows;

/// <summary>Un sitio real de literal encontrado (archivo:línea), con su clave propuesta.</summary>
public sealed record Site(
    string Key,
    string File,
    int Line,
    string Kind,
    string TextOriginal,
    string TextWithMarkers,
    bool HasInterpolation,
    string? Note = null);

/// <summary>Un ternario de plural (`n == 1 ? "singular" : "plural"`), listado aparte.</summary>
public sealed record PluralSite(string File, int Line, string Singular, string Plural);
