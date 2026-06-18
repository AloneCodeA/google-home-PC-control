using System.Text.Json;
using ScreenControl.Host.Display;

namespace ScreenControl.Host.Protocol;

/// <summary>
/// Validates protocol requests and dispatches display power commands.
/// </summary>
public sealed class DisplayCommandProcessor
{
    private readonly IDisplayPowerController _displayPowerController;

    /// <summary>
    /// Initializes a new instance of the <see cref="DisplayCommandProcessor"/> class.
    /// </summary>
    /// <param name="displayPowerController">The display controller that owns Windows power operations.</param>
    public DisplayCommandProcessor(IDisplayPowerController displayPowerController)
    {
        _displayPowerController = displayPowerController;
    }

    /// <summary>
    /// Processes one UTF-8 JSON Lines request payload.
    /// </summary>
    /// <param name="requestJson">A single JSON object without the line terminator.</param>
    /// <param name="cancellationToken">Cancels command execution.</param>
    /// <returns>The correlated command result.</returns>
    public async Task<HostResult> ProcessAsync(string requestJson, CancellationToken cancellationToken)
    {
        SetDisplayPowerRequest? request;
        try
        {
            request = JsonSerializer.Deserialize<SetDisplayPowerRequest>(requestJson);
        }
        catch (JsonException)
        {
            return new HostResult("result", string.Empty, false, "Invalid command payload.");
        }

        if (request is null)
        {
            return new HostResult("result", string.Empty, false, "Invalid command payload.");
        }

        if (!string.Equals(request.Type, "setDisplayPower", StringComparison.Ordinal))
        {
            return new HostResult("result", request.RequestId ?? string.Empty, false, $"Unsupported command type '{request.Type}'.");
        }

        if (string.IsNullOrWhiteSpace(request.RequestId))
        {
            return new HostResult("result", string.Empty, false, "requestId is required.");
        }

        if (request.IsOn is null)
        {
            return new HostResult("result", request.RequestId, false, "isOn is required.");
        }

        try
        {
            await _displayPowerController.SetDisplayPowerAsync(request.IsOn.Value, cancellationToken).ConfigureAwait(false);
            return new HostResult("result", request.RequestId, true, null);
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            return new HostResult("result", request.RequestId, false, $"Display command failed: {exception.Message}");
        }
    }

    private sealed record SetDisplayPowerRequest(
        [property: System.Text.Json.Serialization.JsonPropertyName("type")] string? Type,
        [property: System.Text.Json.Serialization.JsonPropertyName("requestId")] string? RequestId,
        [property: System.Text.Json.Serialization.JsonPropertyName("isOn")] bool? IsOn);
}
