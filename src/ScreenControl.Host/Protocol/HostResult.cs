using System.Text.Json.Serialization;

namespace ScreenControl.Host.Protocol;

/// <summary>
/// Describes the result of a display-host command.
/// </summary>
/// <param name="Type">The protocol message type.</param>
/// <param name="RequestId">The identifier supplied by the caller.</param>
/// <param name="Success">Whether the command completed successfully.</param>
/// <param name="Error">A stable error message when the command fails.</param>
public sealed record HostResult(
    [property: JsonPropertyName("type")] string Type,
    [property: JsonPropertyName("requestId")] string RequestId,
    [property: JsonPropertyName("success")] bool Success,
    [property: JsonPropertyName("error")] string? Error);
