using System.Text.Json.Serialization;

namespace ScreenControl.Host.Protocol;

internal sealed record HostDisplayState(
    [property: JsonPropertyName("type")] string Type,
    [property: JsonPropertyName("isOn")] bool IsOn);
