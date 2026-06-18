namespace ScreenControl.Host.Display;

/// <summary>
/// Controls all displays in the current Windows session using monitor power commands.
/// </summary>
public sealed class WindowsDisplayPowerController : IDisplayPowerController
{
    internal const int MonitorPowerOn = -1;
    internal const int MonitorPowerOff = 2;
    private static readonly TimeSpan WakeConfirmationDelay = TimeSpan.FromSeconds(2);

    private readonly IWindowsDisplayNativeApi _nativeApi;
    private readonly IDisplayStateMonitor _stateMonitor;
    private readonly IAsyncDelay _delay;

    internal WindowsDisplayPowerController(
        IWindowsDisplayNativeApi nativeApi,
        IDisplayStateMonitor stateMonitor,
        IAsyncDelay delay)
    {
        _nativeApi = nativeApi;
        _stateMonitor = stateMonitor;
        _delay = delay;
    }

    /// <inheritdoc />
    public async Task SetDisplayPowerAsync(bool isOn, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        if (!isOn)
        {
            _nativeApi.SendMonitorPowerCommand(MonitorPowerOff);
            return;
        }

        _nativeApi.SendMonitorPowerCommand(MonitorPowerOn);
        _nativeApi.PulseDisplayRequired();
        await _delay.WaitAsync(WakeConfirmationDelay, cancellationToken).ConfigureAwait(false);
        if (_stateMonitor.IsDisplayOn is not true)
        {
            _nativeApi.SendWakeInput();
        }
    }
}
