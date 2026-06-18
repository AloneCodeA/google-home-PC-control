using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace ScreenControl.Host.Display;

internal sealed class PowerSettingNotificationWindow : NativeWindow, IDisposable
{
    private const int WmPowerBroadcast = 0x0218;
    private const int PbtPowerSettingChange = 0x8013;
    private const int DeviceNotifyWindowHandle = 0;
    private const int PowerSettingDataOffset = 20;
    private static readonly IntPtr MessageOnlyWindowParent = new(-3);

    private readonly Action<uint> _onDisplayState;
    private IntPtr _registrationHandle;
    private bool _disposed;

    public PowerSettingNotificationWindow(Action<uint> onDisplayState)
    {
        ArgumentNullException.ThrowIfNull(onDisplayState);
        _onDisplayState = onDisplayState;

        CreateHandle(new CreateParams
        {
            Caption = "Google Home Screen Control Power Notifications",
            Parent = MessageOnlyWindowParent,
        });

        Guid settingGuid = PowerSettingPayloadParser.ConsoleDisplayStateGuid;
        _registrationHandle = RegisterPowerSettingNotification(Handle, ref settingGuid, DeviceNotifyWindowHandle);
        if (_registrationHandle == IntPtr.Zero)
        {
            int error = Marshal.GetLastWin32Error();
            DestroyHandle();
            throw new Win32Exception(error, "RegisterPowerSettingNotification failed.");
        }
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        if (_registrationHandle != IntPtr.Zero)
        {
            _ = UnregisterPowerSettingNotification(_registrationHandle);
            _registrationHandle = IntPtr.Zero;
        }

        DestroyHandle();
        _disposed = true;
    }

    protected override void WndProc(ref Message message)
    {
        if (message.Msg == WmPowerBroadcast && message.WParam.ToInt32() == PbtPowerSettingChange)
        {
            ProcessPowerSettingChange(message.LParam);
        }

        base.WndProc(ref message);
    }

    private void ProcessPowerSettingChange(IntPtr payloadPointer)
    {
        if (payloadPointer == IntPtr.Zero)
        {
            return;
        }

        Guid settingGuid = Marshal.PtrToStructure<Guid>(payloadPointer);
        int dataLength = Marshal.ReadInt32(payloadPointer, sizeof(int) * 4);
        if (dataLength < 0 || dataLength > 64)
        {
            return;
        }

        byte[] data = new byte[dataLength];
        Marshal.Copy(IntPtr.Add(payloadPointer, PowerSettingDataOffset), data, 0, dataLength);
        if (PowerSettingPayloadParser.TryReadConsoleDisplayState(settingGuid, data, out uint state))
        {
            _onDisplayState(state);
        }
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr RegisterPowerSettingNotification(
        IntPtr recipientHandle,
        ref Guid powerSettingGuid,
        int flags);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnregisterPowerSettingNotification(IntPtr registrationHandle);
}
