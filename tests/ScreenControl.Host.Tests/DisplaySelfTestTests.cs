using ScreenControl.Host.Display;

namespace ScreenControl.Host.Tests;

public sealed class DisplaySelfTestTests
{
    [Fact]
    public async Task RunAsync_TurnsDisplaysOffThenOn()
    {
        var controller = new RecordingDisplayPowerController();
        var selfTest = new DisplaySelfTest(controller, new CompletingDelay());

        await selfTest.RunAsync(TimeSpan.FromSeconds(5), CancellationToken.None);

        Assert.Equal([false, true], controller.RequestedStates);
    }

    [Fact]
    public async Task RunAsync_WhenDelayFails_StillTurnsDisplaysOn()
    {
        var controller = new RecordingDisplayPowerController();
        var selfTest = new DisplaySelfTest(controller, new ThrowingDelay());

        await Assert.ThrowsAsync<InvalidOperationException>(
            () => selfTest.RunAsync(TimeSpan.FromSeconds(5), CancellationToken.None));

        Assert.Equal([false, true], controller.RequestedStates);
    }

    private sealed class RecordingDisplayPowerController : IDisplayPowerController
    {
        public List<bool> RequestedStates { get; } = [];

        public Task SetDisplayPowerAsync(bool isOn, CancellationToken cancellationToken)
        {
            RequestedStates.Add(isOn);
            return Task.CompletedTask;
        }
    }

    private sealed class CompletingDelay : IAsyncDelay
    {
        public Task WaitAsync(TimeSpan duration, CancellationToken cancellationToken)
        {
            return Task.CompletedTask;
        }
    }

    private sealed class ThrowingDelay : IAsyncDelay
    {
        public Task WaitAsync(TimeSpan duration, CancellationToken cancellationToken)
        {
            throw new InvalidOperationException("Simulated delay failure.");
        }
    }
}
