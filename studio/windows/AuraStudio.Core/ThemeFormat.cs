namespace AuraStudio.Core;

/// <summary>
/// Constantes del formato de tema v1 -- CONTRATO-formato-tema.md.
/// Mismos 14 roles/9 tamaños que aura_style.c (firmware) hardcodea.
/// </summary>
public static class ThemeFormat
{
    public const int Current = 1;

    /// <summary>(rol, tamaño en pt) -- mismo orden que CONTRATO-formato-tema.md SS C.</summary>
    public static readonly (string Role, int Px)[] FontRoles =
    [
        ("title", 20), ("body", 13), ("caption", 13), ("header", 13),
        ("micro", 7), ("ds_reg_8", 8), ("ds_semibold_15", 15),
        ("ds_reg_10", 10), ("ds_bold_10", 10), ("ds_reg_12", 12),
        ("ds_bold_12", 12), ("ds_bold_14", 14), ("ds_bold_18", 18),
        ("ds_medium_16", 16),
    ];

    public static readonly int[] IconSizes = [12, 16, 20, 24, 28, 36, 48, 60, 64];
    public const int IconKeyCount = 89;
    /// <summary>89 x 9 = 801 -- CONTRATO-formato-tema.md SS D.</summary>
    public const int RequiredMaskCount = 801;
}
