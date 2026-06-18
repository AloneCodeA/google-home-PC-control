using ScreenControl.Host.Display;

namespace ScreenControl.Host.Tests;

public sealed class WindowsDisplayPowerControllerTests
{
    [Fact]
    public async Task SystemAsyncDelay_HonorsCancellation()
    {
        var delay = new SystemAsyncDelay();
        using var cancellationSource = new CancellationTokenSource();
        await cancellationSource.CancelAsync();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(
            () => delay.WaitAsync(TimeSpan.FromMinutes(1), cancellationSource.Token));
    }

    [Fact]
    public void SystemWakeLock_AcquiresAndReleasesSystemRequirement()
    {
        var nativeApi = new RecordingWindowsDisplayNativeApi();

        var wakeLock = new SystemWakeLock(nativeApi);
        Assert.Equal([true], nativeApi.SystemRequiredStates);

        wakeLock.Dispose();
        wakeLock.Dispose();

        Assert.Equal([true, false], nativeApi.SystemRequiredStates);
    }

    [Fact]
    public async Task SetDisplayPowerAsync_WhenTurningOff_SendsOnlyMonitorOffCommand()
    {
        var nativeApi = new RecordingWindowsDisplayNativeApi();
        var stateMonitor = new StubDisplayStateMonitor();
        var delay = new ImmediateAsyncDelay();
        var controller = new WindowsDisplayPowerController(nativeApi, stateMonitor, delay);

        await controller.SetDisplayPowerAsync(false, CancellationToken.None);

        Assert.Equal([WindowsDisplayPowerController.MonitorPowerOff], nativeApi.PowerCommands);
        Assert.Equal(0, nativeApi.DisplayRequiredPulseCount);
        Assert.Equal(0, nativeApi.WakeInputCount);
    }

    [Fact]
    public async Task SetDisplayPowerAsync_WhenTurningOnWithoutStateConfirmation_UsesWakeInputFallback()
    {
        var nativeApi = new RecordingWindowsDisplayNativeApi();
        var stateMonitor = new StubDisplayStateMonitor { IsDisplayOn = false };
        var delay = new ImmediateAsyncDelay();
        var controller = new WindowsDisplayPowerController(nativeApi, stateMonitor, delay);

        await controller.SetDisplayPowerAsync(true, CancellationToken.None);

        Assert.Equal([WindowsDisplayPowerController.MonitorPowerOn], nativeApi.PowerCommands);
        Assert.Equal(1, nativeApi.DisplayRequiredPulseCount);
        Assert.Equal(1, nativeApi.WakeInputCount);
    }

    [Fact]
    public async Task SetDisplayPowerAsync_WhenDisplayConfirmsOn_DoesNotSendWakeInput()
    {
        var nativeApi = new RecordingWindowsDisplayNativeApi();
        var stateMonitor = new StubDisplayStateMonitor { IsDisplayOn = true };
        var delay = new ImmediateAsyncDelay();
        var controller = new WindowsDisplayPowerController(nativeApi, stateMonitor, delay);

        await controller.SetDisplayPowerAsync(true, CancellationToken.None);

        Assert.Equal(0, nativeApi.WakeInputCount);
    }

    private sealed class RecordingWindowsDisplayNativeApi : IWindowsDisplayNativeApi
    {
        public List<int> PowerCommands { get; } = [];

        public int DisplayRequiredPulseCount { get; private set; }

        public int WakeInputCount { get; private set; }

        public List<bool> SystemRequiredStates { get; } = [];

        public void SendMonitorPowerCommand(int powerState)
        {
            PowerCommands.Add(powerState);
        }

        public void PulseDisplayRequired()
        {
            DisplayRequiredPulseCount++;
        }

        public void SendWakeInput()
        {
            WakeInputCount++;
        }

        public void SetSystemRequired(bool isRequired)
        {
            SystemRequiredStates.Add(isRequired);
        }
    }

    private sealed class StubDisplayStateMonitor : IDisplayStateMonitor
    {
        public bool? IsDisplayOn { get; set; }

        public event EventHandler<DisplayStateChangedEventArgs>? DisplayStateChanged
        {
            add { }
            remove { }
        }

        public void Dispose()
        {
        }
    }

    private sealed class ImmediateAsyncDelay : IAsyncDelay
    {
        public Task WaitAsync(TimeSpan duration, CancellationToken cancellationToken)
        {
            return Task.CompletedTask;
        }
    }
}
