using AuraStudio.Core;
using Xunit;

namespace AuraStudio.Core.Tests;

public sealed class FirmwareTreePlannerTests
{
    [Theory]
    [InlineData(".rockbox/aura/aura.cfg")]
    [InlineData(".rockbox\\aura\\aura.cfg")]
    public void AcceptsRelativePaths(string path) => Assert.True(FirmwareTreePlanner.IsSafeRelativePath(path));

    [Theory]
    [InlineData("..\\outside.txt")]
    [InlineData(".\\file")]
    [InlineData("C:\\outside.txt")]
    [InlineData("")]
    public void RejectsUnsafePaths(string path) => Assert.False(FirmwareTreePlanner.IsSafeRelativePath(path));

    [Fact]
    public void BuildsFamilySpecificDormantTree()
    {
        Assert.EndsWith(".firmware-metro", FirmwareTreePlanner.DormantTree("E:\\", FirmwareFamily.Metro));
    }
}
