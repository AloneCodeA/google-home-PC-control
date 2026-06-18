using System.Diagnostics;
using System.Text.Json;

namespace ScreenControl.Host.Tests;

public sealed class HostProcessTests
{
    [Fact]
    public async Task HostProcess_WithHelp_PrintsSupportedModesWithoutStartingProtocol()
    {
        string executablePath = Path.Combine(AppContext.BaseDirectory, "ScreenControl.Host.exe");
        using var process = new Process
        {
            StartInfo = new ProcessStartInfo
            {
                FileName = executablePath,
                Arguments = "--help",
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
            },
        };

        Assert.True(process.Start());
        string standardOutput = await process.StandardOutput.ReadToEndAsync();
        string standardError = await process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(5));

        Assert.Equal(0, process.ExitCode);
        Assert.Contains("--self-test", standardOutput, StringComparison.Ordinal);
        Assert.DoesNotContain("displayState", standardOutput, StringComparison.Ordinal);
        Assert.Equal(string.Empty, standardError);
    }

    [Fact]
    public async Task HostProcess_WithUnknownCommand_WritesProtocolFailureAndExitsCleanly()
    {
        string executablePath = Path.Combine(AppContext.BaseDirectory, "ScreenControl.Host.exe");
        using var process = new Process
        {
            StartInfo = new ProcessStartInfo
            {
                FileName = executablePath,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardInput = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
            },
        };

        Assert.True(process.Start());
        await process.StandardInput.WriteLineAsync(
            """
            {"type":"unknown","requestId":"process-1","isOn":true}
            """);
        process.StandardInput.Close();

        string standardOutput = await process.StandardOutput.ReadToEndAsync();
        string standardError = await process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(5));

        Assert.Equal(0, process.ExitCode);
        string[] outputLines = standardOutput.Split(
            ["\r\n", "\n"],
            StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        JsonElement result = outputLines
            .Select(line => JsonDocument.Parse(line).RootElement.Clone())
            .Single(element => element.TryGetProperty("requestId", out JsonElement requestId) && requestId.GetString() == "process-1");
        Assert.Equal("result", result.GetProperty("type").GetString());
        Assert.False(result.GetProperty("success").GetBoolean());
        Assert.Equal("Unsupported command type 'unknown'.", result.GetProperty("error").GetString());
        Assert.Equal(string.Empty, standardError);
    }
}
