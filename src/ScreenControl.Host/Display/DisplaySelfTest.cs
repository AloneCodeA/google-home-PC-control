namespace ScreenControl.Host.Display;

internal sealed class DisplaySelfTest(
    IDisplayPowerController displayPowerController,
    IAsyncDelay delay)
{
    public async Task RunAsync(TimeSpan offDuration, CancellationToken cancellationToken)
    {
        await displayPowerController.SetDisplayPowerAsync(false, cancellationToken).ConfigureAwait(false);
        try
        {
            await delay.WaitAsync(offDuration, cancellationToken).ConfigureAwait(false);
        }
        finally
        {
            await displayPowerController.SetDisplayPowerAsync(true, CancellationToken.None).ConfigureAwait(false);
        }
    }
}
