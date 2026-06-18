namespace ScreenControl.Host.Display;

internal sealed class SystemAsyncDelay : IAsyncDelay
{
    public Task WaitAsync(TimeSpan duration, CancellationToken cancellationToken)
    {
        return Task.Delay(duration, cancellationToken);
    }
}
