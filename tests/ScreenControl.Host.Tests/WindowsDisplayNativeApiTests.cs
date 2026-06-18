using ScreenControl.Host.Display;

namespace ScreenControl.Host.Tests;

public sealed class WindowsDisplayNativeApiTests
{
    [Fact]
    public void Operations_ForwardExactWindowsPowerValues()
    {
        var monitorStates = new List<int>();
        var executionStates = new List<uint>();
        int wakeInputCount = 0;
        var nativeApi = new WindowsDisplayNativeApi(
            monitorStates.Add,
            executionStates.Add,
            () => wakeInputCount++);

        nativeApi.SendMonitorPowerCommand(WindowsDisplayPowerController.MonitorPowerOff);
        nativeApi.PulseDisplayRequired();
        nativeApi.SetSystemRequired(true);
        nativeApi.SetSystemRequired(false);
        nativeApi.SendWakeInput();

        Assert.Equal([2], monitorStates);
        Assert.Equal([0x00000002u, 0x80000001u, 0x80000000u], executionStates);
        Assert.Equal(1, wakeInputCount);
    }
}
