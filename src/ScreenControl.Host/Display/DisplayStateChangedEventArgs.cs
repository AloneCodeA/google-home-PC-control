namespace ScreenControl.Host.Display;

internal sealed class DisplayStateChangedEventArgs(bool isOn) : EventArgs
{
    public bool IsOn { get; } = isOn;
}
