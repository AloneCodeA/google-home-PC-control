using ScreenControl.Host.Display;
using ScreenControl.Host.Protocol;

namespace ScreenControl.Host.Tests;

public sealed class DisplayCommandProcessorTests
{
    [Fact]
    public async Task ProcessAsync_WithValidPowerCommand_ControlsDisplayAndReturnsSuccess()
    {
        var controller = new RecordingDisplayPowerController();
        var processor = new DisplayCommandProcessor(controller);

        HostResult result = await processor.ProcessAsync(
            """
            {"type":"setDisplayPower","requestId":"request-1","isOn":true}
            """,
            CancellationToken.None);

        Assert.True(controller.LastRequestedState);
        Assert.Equal("result", result.Type);
        Assert.Equal("request-1", result.RequestId);
        Assert.True(result.Success);
        Assert.Null(result.Error);
    }

    [Fact]
    public async Task ProcessAsync_WithUnknownCommand_DoesNotControlDisplayAndReturnsFailure()
    {
        var controller = new RecordingDisplayPowerController();
        var processor = new DisplayCommandProcessor(controller);

        HostResult result = await processor.ProcessAsync(
            """
            {"type":"unknown","requestId":"request-2","isOn":false}
            """,
            CancellationToken.None);

        Assert.Null(controller.LastRequestedState);
        Assert.Equal("request-2", result.RequestId);
        Assert.False(result.Success);
        Assert.Equal("Unsupported command type 'unknown'.", result.Error);
    }

    [Fact]
    public async Task ProcessAsync_WhenDisplayControllerFails_ReturnsFailureWithoutChangingProtocolShape()
    {
        var controller = new RecordingDisplayPowerController
        {
            ExceptionToThrow = new InvalidOperationException("Simulated display failure."),
        };
        var processor = new DisplayCommandProcessor(controller);

        HostResult result = await processor.ProcessAsync(
            """
            {"type":"setDisplayPower","requestId":"request-3","isOn":false}
            """,
            CancellationToken.None);

        Assert.False(result.Success);
        Assert.Equal("request-3", result.RequestId);
        Assert.Equal("Display command failed: Simulated display failure.", result.Error);
    }

    [Fact]
    public async Task ProcessAsync_WithMalformedJson_ReturnsProtocolFailure()
    {
        var controller = new RecordingDisplayPowerController();
        var processor = new DisplayCommandProcessor(controller);

        HostResult result = await processor.ProcessAsync("{", CancellationToken.None);

        Assert.Null(controller.LastRequestedState);
        Assert.Equal(string.Empty, result.RequestId);
        Assert.False(result.Success);
        Assert.Equal("Invalid command payload.", result.Error);
    }

    [Theory]
    [InlineData("{\"type\":\"setDisplayPower\",\"isOn\":true}", "requestId is required.")]
    [InlineData("{\"type\":\"setDisplayPower\",\"requestId\":\"request-4\"}", "isOn is required.")]
    public async Task ProcessAsync_WithMissingRequiredProperty_DoesNotControlDisplay(
        string requestJson,
        string expectedError)
    {
        var controller = new RecordingDisplayPowerController();
        var processor = new DisplayCommandProcessor(controller);

        HostResult result = await processor.ProcessAsync(requestJson, CancellationToken.None);

        Assert.Null(controller.LastRequestedState);
        Assert.False(result.Success);
        Assert.Equal(expectedError, result.Error);
    }

    private sealed class RecordingDisplayPowerController : IDisplayPowerController
    {
        public bool? LastRequestedState { get; private set; }

        public Exception? ExceptionToThrow { get; init; }

        public Task SetDisplayPowerAsync(bool isOn, CancellationToken cancellationToken)
        {
            LastRequestedState = isOn;
            if (ExceptionToThrow is not null)
            {
                throw ExceptionToThrow;
            }

            return Task.CompletedTask;
        }
    }
}
