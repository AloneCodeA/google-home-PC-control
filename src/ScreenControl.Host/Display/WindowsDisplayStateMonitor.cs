namespace ScreenControl.Host.Display;

internal sealed class WindowsDisplayStateMonitor : IDisplayStateMonitor
{
    private readonly DisplayStateTracker _tracker = new();
    private readonly IDisposable _notificationSource;
    private bool _disposed;

    public WindowsDisplayStateMonitor()
        : this(callback => new PowerSettingNotificationWindow(callback))
    {
    }

    internal WindowsDisplayStateMonitor(Func<Action<uint>, IDisposable> notificationSourceFactory)
    {
        ArgumentNullException.ThrowIfNull(notificationSourceFactory);
        _notificationSource = notificationSourceFactory(_tracker.Update);
        _tracker.DisplayStateChanged += OnDisplayStateChanged;
    }

    public bool? IsDisplayOn => _tracker.IsDisplayOn;

    public event EventHandler<DisplayStateChangedEventArgs>? DisplayStateChanged;

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _tracker.DisplayStateChanged -= OnDisplayStateChanged;
        _notificationSource.Dispose();
        _disposed = true;
    }

    private void OnDisplayStateChanged(object? sender, DisplayStateChangedEventArgs eventArgs)
    {
        DisplayStateChanged?.Invoke(this, eventArgs);
    }
}
