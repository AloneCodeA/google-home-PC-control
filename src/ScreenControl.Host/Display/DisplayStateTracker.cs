namespace ScreenControl.Host.Display;

internal sealed class DisplayStateTracker
{
    private readonly object _stateLock = new();
    private bool? _isDisplayOn;

    public bool? IsDisplayOn
    {
        get
        {
            lock (_stateLock)
            {
                return _isDisplayOn;
            }
        }
    }

    public event EventHandler<DisplayStateChangedEventArgs>? DisplayStateChanged;

    public void Update(uint nativeState)
    {
        bool isOn = nativeState switch
        {
            0 => false,
            1 or 2 => true,
            _ => throw new ArgumentOutOfRangeException(nameof(nativeState), nativeState, "Unsupported console display state."),
        };

        lock (_stateLock)
        {
            if (_isDisplayOn == isOn)
            {
                return;
            }

            _isDisplayOn = isOn;
        }

        DisplayStateChanged?.Invoke(this, new DisplayStateChangedEventArgs(isOn));
    }
}
