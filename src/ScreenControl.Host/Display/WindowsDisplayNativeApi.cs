using System.ComponentModel;
using System.Runtime.InteropServices;

namespace ScreenControl.Host.Display;

internal sealed class WindowsDisplayNativeApi : IWindowsDisplayNativeApi
{
    private const uint EsContinuous = 0x80000000;
    private const uint EsSystemRequired = 0x00000001;
    private const uint EsDisplayRequired = 0x00000002;
    private const uint InputMouse = 0;
    private const uint MouseEventMove = 0x0001;
    private const uint WmSysCommand = 0x0112;
    private const int ScMonitorPower = 0xF170;
    private static readonly IntPtr HwndBroadcast = new(0xFFFF);

    private readonly Action<int> _sendMonitorPowerCommand;
    private readonly Action<uint> _setExecutionState;
    private readonly Action _sendWakeInput;

    public WindowsDisplayNativeApi()
        : this(SendMonitorPowerCommandNative, SetExecutionStateNative, SendWakeInputNative)
    {
    }

    internal WindowsDisplayNativeApi(
        Action<int> sendMonitorPowerCommand,
        Action<uint> setExecutionState,
        Action sendWakeInput)
    {
        _sendMonitorPowerCommand = sendMonitorPowerCommand;
        _setExecutionState = setExecutionState;
        _sendWakeInput = sendWakeInput;
    }

    public void SendMonitorPowerCommand(int powerState)
    {
        _sendMonitorPowerCommand(powerState);
    }

    public void PulseDisplayRequired()
    {
        _setExecutionState(EsDisplayRequired);
    }

    public void SendWakeInput()
    {
        _sendWakeInput();
    }

    public void SetSystemRequired(bool isRequired)
    {
        _setExecutionState(isRequired ? EsContinuous | EsSystemRequired : EsContinuous);
    }

    private static void SendMonitorPowerCommandNative(int powerState)
    {
        _ = SendMessage(HwndBroadcast, WmSysCommand, new IntPtr(ScMonitorPower), new IntPtr(powerState));
    }

    private static void SetExecutionStateNative(uint executionState)
    {
        if (SetThreadExecutionState(executionState) == 0)
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(), "SetThreadExecutionState failed.");
        }
    }

    private static void SendWakeInputNative()
    {
        Input[] inputs =
        [
            new Input { Type = InputMouse, MouseInput = new MouseInput { Dx = 1, Flags = MouseEventMove } },
            new Input { Type = InputMouse, MouseInput = new MouseInput { Dx = -1, Flags = MouseEventMove } },
        ];

        uint sent = SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<Input>());
        if (sent != inputs.Length)
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(), "SendInput failed to wake the displays.");
        }
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr SendMessage(IntPtr windowHandle, uint message, IntPtr wParam, IntPtr lParam);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern uint SetThreadExecutionState(uint executionState);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint inputCount, Input[] inputs, int inputSize);

    [StructLayout(LayoutKind.Sequential)]
    private struct Input
    {
        public uint Type;
        public MouseInput MouseInput;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MouseInput
    {
        public int Dx;
        public int Dy;
        public uint MouseData;
        public uint Flags;
        public uint Time;
        public UIntPtr ExtraInfo;
    }
}
