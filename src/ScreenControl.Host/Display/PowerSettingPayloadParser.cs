namespace ScreenControl.Host.Display;

internal static class PowerSettingPayloadParser
{
    internal static readonly Guid ConsoleDisplayStateGuid = new("6fe69556-704a-47a0-8f24-c28d936fda47");

    public static bool TryReadConsoleDisplayState(Guid settingGuid, ReadOnlySpan<byte> data, out uint state)
    {
        if (settingGuid != ConsoleDisplayStateGuid || data.Length != sizeof(uint))
        {
            state = default;
            return false;
        }

        state = BitConverter.ToUInt32(data);
        return true;
    }
}
