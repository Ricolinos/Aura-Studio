namespace AuraStudio.Core.Networking;

/// <summary>
/// Version SemVer simple (`vMAJOR.MINOR.PATCH[-prerelease]`), lo unico
/// que hace falta para comparar el tag de un Release de GitHub contra
/// lo instalado (PLAN-release-updates.md S1.5). No hay nada asi en
/// .NET.
///
/// La comparacion de dos sufijos de prerelease distintos (`beta` vs
/// `rc1`) usa orden lexicografico simple, no la regla completa de
/// precedencia de SemVer (punto 11, identificadores separados por
/// puntos comparados uno a uno). Alcance reducido a proposito: el
/// unico mantenedor de este repositorio nunca usa mas de un sufijo de
/// prerelease por release real, asi que la regla completa seria
/// trabajo sin caso de uso.
/// </summary>
public readonly struct SemVer : IEquatable<SemVer>, IComparable<SemVer>
{
    public int Major { get; }
    public int Minor { get; }
    public int Patch { get; }
    public string? Prerelease { get; }

    public SemVer(int major, int minor, int patch, string? prerelease = null)
    {
        Major = major;
        Minor = minor;
        Patch = patch;
        Prerelease = prerelease;
    }

    /// <summary>Parsea un tag como "v1.2.3-beta" o "0.1.0". Devuelve null si no es valido.</summary>
    public static SemVer? Parse(string raw)
    {
        if (string.IsNullOrEmpty(raw)) return null;

        var s = raw;
        if (s.Length > 0 && s[0] == 'v') s = s[1..];

        var parts = s.Split('-', 2);
        var core = parts[0];
        var prerelease = parts.Length > 1 ? parts[1] : null;

        var nums = core.Split('.');
        if (nums.Length != 3) return null;

        if (!int.TryParse(nums[0], out var major) ||
            !int.TryParse(nums[1], out var minor) ||
            !int.TryParse(nums[2], out var patch) ||
            major < 0 || minor < 0 || patch < 0)
        {
            return null;
        }

        return new SemVer(major, minor, patch, prerelease);
    }

    /// <summary>
    /// La versión como aparece en el <b>nombre</b> de un asset y en el tag, sin
    /// la <c>v</c>: <c>0.3.0</c>, o <c>0.3.0-beta</c> si tiene sufijo (ST-193,
    /// <c>releaseString</c> de Swift).
    /// </summary>
    public string ReleaseString =>
        Prerelease is { Length: > 0 } suffix ? $"{Major}.{Minor}.{Patch}-{suffix}" : $"{Major}.{Minor}.{Patch}";

    public int CompareTo(SemVer other)
    {
        if (Major != other.Major) return Major.CompareTo(other.Major);
        if (Minor != other.Minor) return Minor.CompareTo(other.Minor);
        if (Patch != other.Patch) return Patch.CompareTo(other.Patch);

        // Estable > cualquier prerelease
        if (Prerelease == null && other.Prerelease == null) return 0;
        if (Prerelease == null) return 1;  // estable > prerelease
        if (other.Prerelease == null) return -1; // prerelease < estable

        return string.Compare(Prerelease, other.Prerelease, StringComparison.Ordinal);
    }

    public bool Equals(SemVer other) =>
        Major == other.Major && Minor == other.Minor && Patch == other.Patch &&
        string.Equals(Prerelease, other.Prerelease, StringComparison.Ordinal);

    public override bool Equals(object? obj) => obj is SemVer other && Equals(other);

    public override int GetHashCode() => HashCode.Combine(Major, Minor, Patch, Prerelease);

    public static bool operator ==(SemVer left, SemVer right) => left.Equals(right);
    public static bool operator !=(SemVer left, SemVer right) => !left.Equals(right);
    public static bool operator <(SemVer left, SemVer right) => left.CompareTo(right) < 0;
    public static bool operator >(SemVer left, SemVer right) => left.CompareTo(right) > 0;
    public static bool operator <=(SemVer left, SemVer right) => left.CompareTo(right) <= 0;
    public static bool operator >=(SemVer left, SemVer right) => left.CompareTo(right) >= 0;

    public override string ToString() =>
        Prerelease != null ? $"v{Major}.{Minor}.{Patch}-{Prerelease}" : $"v{Major}.{Minor}.{Patch}";
}