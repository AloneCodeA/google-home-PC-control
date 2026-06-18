using ScreenControl.Host.Display;

namespace ScreenControl.Host.Tests;

public sealed class WindowsDisplayStateMonitorTests
{
    [Fact]
    public void NativeNotification_UpdatesStateAndDisposeReleasesSource()
    {
        Action<uint>? notification = null;
        var source = new RecordingDisposable();
        var monitor = new WindowsDisplayStateMonitor(callback =>
        {
            notification = callback;
            return source;
        });
        bool? observedState = null;
        monitor.DisplayStateChanged += (_, eventArgs) => observedState = eventArgs.IsOn;

        Assert.NotNull(notification);
        notification(0);

        Assert.False(monitor.IsDisplayOn);
        Assert.False(observedState);

        monitor.Dispose();
        monitor.Dispose();
        Assert.Equal(1, source.DisposeCount);
    }

    private sealed class RecordingDisposable : IDisposable
    {
        public int DisposeCount { get; private set; }

        public void Dispose()
        {
            DisposeCount++;
        }
    }
}
