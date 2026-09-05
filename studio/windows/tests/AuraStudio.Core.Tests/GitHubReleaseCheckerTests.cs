using System.Net;
using AuraStudio.Core;
using AuraStudio.Core.Networking;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// ST-150: los tres repos del firmware son públicos. Port de
/// <c>GitHubReleaseCheckerTests.swift</c> (las pruebas específicas de "sin
/// token" — la construcción de la URL por familia y el parseo del JSON ya se
/// verifican en otro lado del port).
/// </summary>
internal sealed class CapturingHandler(Func<HttpRequestMessage, (HttpStatusCode Status, string Body)> respond)
    : HttpMessageHandler
{
    public List<HttpRequestMessage> Requests { get; } = [];

    protected override Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request, CancellationToken cancellationToken)
    {
        Requests.Add(request);
        (HttpStatusCode status, string body) = respond(request);
        return Task.FromResult(new HttpResponseMessage(status) { Content = new StringContent(body) });
    }
}

public class GitHubReleaseCheckerTests
{
    [Theory]
    [MemberData(nameof(Families))]
    public async Task WithoutATokenNoAuthorizationHeaderTravels(FirmwareFamily family)
    {
        var handler = new CapturingHandler(_ => (HttpStatusCode.OK, "[]"));
        using var http = new HttpClient(handler);

        await GitHubReleaseChecker.FetchReleasesAsync(http, family, token: null);

        Assert.False(handler.Requests[0].Headers.Contains("Authorization"),
            $"{family.DisplayName}: sin token no debe viajar Authorization");
    }

    [Theory]
    [MemberData(nameof(FamiliesWithExpectedUrl))]
    public async Task EachFamilyQueriesItsOwnPublicRepository(FirmwareFamily family, string expectedUrl)
    {
        var handler = new CapturingHandler(_ => (HttpStatusCode.OK, "[]"));
        using var http = new HttpClient(handler);

        await GitHubReleaseChecker.FetchReleasesAsync(http, family, token: null);

        Assert.Equal(expectedUrl, handler.Requests[0].RequestUri?.ToString());
    }

    public static IEnumerable<object[]> Families =>
        new[] { FirmwareFamily.Aura, FirmwareFamily.Metro, FirmwareFamily.Moonlit }
            .Select(f => new object[] { f });

    public static IEnumerable<object[]> FamiliesWithExpectedUrl =>
        new (FirmwareFamily Family, string Url)[]
        {
            (FirmwareFamily.Aura, "https://api.github.com/repos/Ricolinos/Aura-Firmware/releases"),
            (FirmwareFamily.Metro, "https://api.github.com/repos/Ricolinos/Metro-Aura/releases"),
            (FirmwareFamily.Moonlit, "https://api.github.com/repos/Ricolinos/moonlit-aura/releases"),
        }.Select(t => new object[] { t.Family, t.Url });
}

// La prueba de integración en vivo contra la API real (sin token, contra los
// tres repos públicos) vive del lado de macOS
// (GitHubReleaseCheckerLiveTests.swift): este proyecto de pruebas no trae
// ningún mecanismo de "saltar sin red" (xUnit v2 puro, sin SkippableFact), y
// agregar un paquete nuevo solo para un test de red no vale la pena -- el
// código de FetchReleasesAsync es casi idéntico al de Swift, ya probado en
// vivo ahí, y las dos pruebas mockeadas de arriba ya fijan la forma exacta
// de la petición (URL por familia, sin Authorization sin token).
