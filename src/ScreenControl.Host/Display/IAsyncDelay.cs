namespace ScreenControl.Host.Display;

internal interface IAsyncDelay
{
    Task WaitAsync(TimeSpan duration, CancellationToken cancellationToken);
}
