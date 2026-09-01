using AuraStudio.Core;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// Activar un tema es <b>editar un archivo del firmware</b>. Equivocarse ahí
/// puede dejar al usuario sin sus ajustes, que es mucho peor que no cambiar el
/// tema — por eso la edición se prueba entera acá, sin disco.
/// </summary>
public class ThemeActivationTests
{
    private const string Config = """
        volume: -25
        theme_id: apple-personal
        accent_rgb24: 4283215696
        sync_marker_supported: 1
        """;

    // MARK: - Leer

    [Fact]
    public void TheActiveThemeIsTheOneInTheConfig()
    {
        Assert.Equal("apple-personal", ThemeActivation.ActiveThemeId(Config));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("volume: -25\n")]
    [InlineData("theme_id:\n")]
    [InlineData("theme_id:   \n")]
    public void WithoutAThemeItIsTheOneBuiltIntoTheFirmware(string? config)
    {
        // Mismo criterio que el firmware: clave vacía o ausente es el default.
        Assert.Equal("default", ThemeActivation.ActiveThemeId(config));
    }

    // MARK: - Escribir

    [Fact]
    public void ChangingTheThemeLeavesEveryOtherSettingAlone()
    {
        string result = ThemeActivation.WithActiveTheme(Config, "aura");

        Assert.Equal("aura", ThemeActivation.ActiveThemeId(result));
        Assert.Contains("volume: -25", result);
        Assert.Contains("accent_rgb24: 4283215696", result);
        Assert.Contains("sync_marker_supported: 1", result);
    }

    [Fact]
    public void OnlyOneThemeLineIsLeft()
    {
        string result = ThemeActivation.WithActiveTheme(Config, "aura");

        Assert.Equal(1, result.Split('\n').Count(line => line.StartsWith("theme_id:", StringComparison.Ordinal)));
    }

    [Fact]
    public void AConfigWithoutTheKeyGetsIt()
    {
        string result = ThemeActivation.WithActiveTheme("volume: -25\n", "aura");

        Assert.Equal("aura", ThemeActivation.ActiveThemeId(result));
        Assert.Contains("volume: -25", result);
    }

    [Fact]
    public void AnEmptyConfigIsNotAProblem()
    {
        Assert.Equal("aura", ThemeActivation.ActiveThemeId(ThemeActivation.WithActiveTheme(null, "aura")));
        Assert.Equal("aura", ThemeActivation.ActiveThemeId(ThemeActivation.WithActiveTheme("", "aura")));
    }

    [Fact]
    public void NoBlankLineIsLeftInTheMiddle()
    {
        // El parser del firmware las tolera, pero el archivo se ensuciaría un
        // poco más en cada activación.
        string result = ThemeActivation.WithActiveTheme("volume: -25\n", "aura");

        Assert.DoesNotContain("\n\n", result);
    }

    [Fact]
    public void GoingBackToTheBuiltInThemeIsJustAnotherActivation()
    {
        Assert.Equal("default", ThemeActivation.ActiveThemeId(
            ThemeActivation.WithActiveTheme(Config, ThemeActivation.DefaultThemeId)));
    }

    // MARK: - El id sugerido

    [Theory]
    [InlineData("Apple (uso personal)", "apple-uso-personal")]
    [InlineData("Aura", "aura")]
    [InlineData("  espacios  raros  ", "espacios-raros")]
    [InlineData("Café con leche", "caf-con-leche")]
    public void TheNameSuggestsAnId(string name, string expected)
    {
        Assert.Equal(expected, ThemeActivation.SuggestId(name));
        Assert.True(AuraThemeID.IsValid(expected));
    }

    [Fact]
    public void ALongNameIsCutWithoutLeavingATrailingDash()
    {
        string id = ThemeActivation.SuggestId(new string('a', 40) + " y más");

        Assert.Equal(32, id.Length);
        Assert.True(AuraThemeID.IsValid(id));
    }

    [Fact]
    public void ANameThatSuggestsNothingIsRejectedByTheIdRulesNotHere()
    {
        // La sugerencia no valida: quien decide es AuraThemeID, y la pantalla
        // le dice al usuario que ese nombre no produce un id usable.
        Assert.Equal("", ThemeActivation.SuggestId("...!!!"));
        Assert.False(AuraThemeID.IsValid(""));
    }

    [Fact]
    public void TheNameDefaultCannotSneakInAsAnId()
    {
        // "default" es el tema compilado: un tema instalado con ese id lo
        // taparía y no habría a dónde volver.
        Assert.Equal("default", ThemeActivation.SuggestId("Default"));
        Assert.False(AuraThemeID.IsValid(ThemeActivation.SuggestId("Default")));
    }
}
