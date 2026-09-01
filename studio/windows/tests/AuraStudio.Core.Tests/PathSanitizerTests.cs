using AuraStudio.Core;
using Xunit;

namespace AuraStudio.Core.Tests;

public class PathSanitizerTests
{
    [Fact]
    public void PlainNameIsUnchanged()
    {
        // Equivalente a testPlainNameIsUnchanged
        Assert.Equal("Abbey Road", PathSanitizer.Sanitize("Abbey Road"));
    }

    [Fact]
    public void IllegalCharactersAreReplaced()
    {
        // Equivalente a testIllegalCharactersAreReplaced
        Assert.Equal("AC_DC", PathSanitizer.Sanitize("AC/DC"));
        Assert.Equal("Sigur Ros_ ()", PathSanitizer.Sanitize("Sigur Ros: ()"));
        Assert.Equal("Track _Live_", PathSanitizer.Sanitize("Track \"Live\""));
    }

    [Fact]
    public void TrailingDotsAndSpacesAreTrimmed()
    {
        // Equivalente a testTrailingDotsAndSpacesAreTrimmed
        Assert.Equal("Mr. Bungle", PathSanitizer.Sanitize("Mr. Bungle. "));
    }

    [Fact]
    public void EmptyResultFallsBackToUnderscore()
    {
        // Equivalente a testEmptyResultFallsBackToUnderscore
        Assert.Equal("_", PathSanitizer.Sanitize("   ..."));
    }

    // PLAN-sync-media-hardening.md PARTE 1A: visto en producción, un crédito
    // de composición completo ("Los Aguas Aguas, Luis Felipe Balderas Lopez,
    // Jose Edwin Bandala Mayoral, Osiel de Jesus Ro...") metido en el tag de
    // artista hacía que la ruta completa (Music/<artista>/<album>/<archivo>.mp3.aura-tmp)
    // excediera lo que el driver msdosfs de macOS acepta — sync() abortaba
    // entero en ese archivo con "el nombre de archivo es inválido".
    [Fact]
    public void LongComponentIsTruncated()
    {
        // Equivalente a testLongComponentIsTruncated
        string longName = new('a', 200);
        string result = PathSanitizer.Sanitize(longName);
        Assert.Equal(PathSanitizer.DefaultMaxLength, result.Length);
        Assert.Equal(longName[..PathSanitizer.DefaultMaxLength], result);
    }

    [Fact]
    public void ShortComponentIsUnaffectedByLengthCap()
    {
        // Equivalente a testShortComponentIsUnaffectedByLengthCap
        Assert.Equal("Abbey", PathSanitizer.Sanitize("Abbey Road", maxLength: 5));
    }

    [Fact]
    public void TruncationThatLandsOnTrailingDotOrSpaceIsTrimmed()
    {
        // Equivalente a testTruncationThatLandsOnTrailingDotOrSpaceIsTrimmed.
        // Corta justo después de un espacio — el resultado no debe quedar con
        // un espacio colgando al final.
        string raw = "Nombre muy largo " + new string('x', 200);
        string result = PathSanitizer.Sanitize(raw, maxLength: 17);
        Assert.Equal("Nombre muy largo", result);
    }

    // MARK: - sanitizeFilename (PLAN-sync-media-hardening.md PARTE 2A)

    [Fact]
    public void SanitizeFilenamePreservesShortNameUnchanged()
    {
        // Equivalente a testSanitizeFilenamePreservesShortNameUnchanged
        Assert.Equal("Año nuevo Ñoño.jpg", PathSanitizer.SanitizeFilename("Año nuevo Ñoño.jpg", 95));
    }

    [Fact]
    public void SanitizeFilenameTruncatesByBytesNotCharacters()
    {
        // Equivalente a testSanitizeFilenameTruncatesByBytesNotCharacters.
        // "ñ" son 2 bytes UTF-8 — 60 "ñ" = 120 bytes, más ".jpg" (4 bytes) =
        // 124 bytes, muy por encima de un límite de 20. Capar por CARACTERES
        // (60 "ñ" es solo 60 caracteres) no lo hubiera detectado.
        string raw = new string('ñ', 60) + ".jpg";
        string result = PathSanitizer.SanitizeFilename(raw, 20);
        Assert.True(System.Text.Encoding.UTF8.GetByteCount(result) <= 20);
        Assert.EndsWith(".jpg", result); // la extensión se conserva completa
    }

    [Fact]
    public void SanitizeFilenameNeverSplitsAMultibyteCharacter()
    {
        // Equivalente a testSanitizeFilenameNeverSplitsAMultibyteCharacter.
        // 21 es impar: fuerza el límite a mitad de un carácter de 2 bytes si no
        // se recorta por Character. Si se hubiera cortado a mitad de un
        // carácter, la cadena resultante ni siquiera sería UTF-8 válido
        // re-decodificable desde sus propios bytes — construirla de vuelta
        // confirma que sigue siendo texto válido (el recorte de C# nunca parte
        // un surrogado/byte, así que el redondeo es idéntico).
        string raw = new string('é', 50) + ".jpg";
        string result = PathSanitizer.SanitizeFilename(raw, 21);
        Assert.True(System.Text.Encoding.UTF8.GetByteCount(result) <= 21);
        var decoded = System.Text.Encoding.UTF8.GetString(System.Text.Encoding.UTF8.GetBytes(result));
        Assert.Equal(result, decoded);
    }

    [Fact]
    public void SanitizeFilenameAlsoReplacesIllegalCharacters()
    {
        // Equivalente a testSanitizeFilenameAlsoReplacesIllegalCharacters
        Assert.Equal("AC_DC_ Live.jpg", PathSanitizer.SanitizeFilename("AC/DC: Live.jpg", 95));
    }
}
