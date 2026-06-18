namespace ScreenControl.Host.Display;

internal sealed class SystemWakeLock : IDisposable
{
    private readonly IWindowsDisplayNativeApi _nativeApi;
    private bool _disposed;

    public SystemWakeLock(IWindowsDisplayNativeApi nativeApi)
    {
        _nativeApi = nativeApi;
        _nativeApi.SetSystemRequired(true);
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _nativeApi.SetSystemRequired(false);
        _disposed = true;
    }
}
