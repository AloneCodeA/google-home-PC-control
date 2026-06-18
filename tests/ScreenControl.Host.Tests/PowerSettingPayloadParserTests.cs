using ScreenControl.Host.Display;

namespace ScreenControl.Host.Tests;

public sealed class PowerSettingPayloadParserTests
{
    [Fact]
    public void TryReadConsoleDisplayState_WithMatchingFourBytePayload_ReturnsState()
    {
        bool parsed = PowerSettingPayloadParser.TryReadConsoleDisplayState(
            PowerSettingPayloadParser.ConsoleDisplayStateGuid,
            BitConverter.GetBytes(2u),
            out uint state);

        Assert.True(parsed);
        Assert.Equal(2u, state);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(3)]
    [InlineData(5)]
    public void TryReadConsoleDisplayState_WithInvalidPayloadLength_ReturnsFalse(int length)
    {
        bool parsed = PowerSettingPayloadParser.TryReadConsoleDisplayState(
            PowerSettingPayloadParser.ConsoleDisplayStateGuid,
            new byte[length],
            out _);

        Assert.False(parsed);
    }
}
