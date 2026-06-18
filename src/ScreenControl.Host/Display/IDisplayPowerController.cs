namespace ScreenControl.Host.Display;

/// <summary>
/// Controls the power state of all displays attached to the current Windows session.
/// </summary>
public interface IDisplayPowerController
{
    /// <summary>
    /// Changes the power state of all attached displays.
    /// </summary>
    /// <param name="isOn"><see langword="true"/> to turn displays on; otherwise, <see langword="false"/>.</param>
    /// <param name="cancellationToken">Cancels the operation before it is dispatched.</param>
    /// <returns>A task that completes after the request has been dispatched.</returns>
    Task SetDisplayPowerAsync(bool isOn, CancellationToken cancellationToken);
}
