namespace ScreenControl.Host.Display;

internal interface IDisplayStateMonitor : IDisposable
{
    bool? IsDisplayOn { get; }

    event EventHandler<DisplayStateChangedEventArgs>? DisplayStateChanged;
}
