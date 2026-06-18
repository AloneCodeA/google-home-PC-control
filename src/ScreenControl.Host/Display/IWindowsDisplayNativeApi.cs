namespace ScreenControl.Host.Display;

internal interface IWindowsDisplayNativeApi
{
    void SendMonitorPowerCommand(int powerState);

    void PulseDisplayRequired();

    void SendWakeInput();

    void SetSystemRequired(bool isRequired);
}
