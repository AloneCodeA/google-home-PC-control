using ScreenControl.Host.Display;
using ScreenControl.Host.Protocol;
using System.Text;

namespace ScreenControl.Host.Tests;

public sealed class JsonLineHostTests
{
    [Fact]
    public async Task RunAsync_WithOneCommand_WritesOneCorrelatedJsonResult()
    {
        using var input = new StringReader(
            """
            {"type":"setDisplayPower","requestId":"request-1","isOn":true}

            """);
        using var output = new StringWriter();
        var monitor = new StubDisplayStateMonitor();
        var processor = new DisplayCommandProcessor(new RecordingDisplayPowerController());
        await using var host = new JsonLineHost(input, output, processor, monitor);

        await host.RunAsync(CancellationToken.None);

        Assert.Equal(
            "{\"type\":\"result\",\"requestId\":\"request-1\",\"success\":true,\"error\":null}" + Environment.NewLine,
            output.ToString());
    }

    [Fact]
    public async Task DisplayStateChanged_WritesStateEventAsOneJsonLine()
    {
        using var input = new StringReader(string.Empty);
        using var output = new NotifyingStringWriter();
        var monitor = new StubDisplayStateMonitor();
        var processor = new DisplayCommandProcessor(new RecordingDisplayPowerController());
        await using var host = new JsonLineHost(input, output, processor, monitor);

        monitor.Raise(false);
        string line = await output.WaitForLineAsync(TimeSpan.FromSeconds(2));

        Assert.Equal("{\"type\":\"displayState\",\"isOn\":false}", line);
    }

    private sealed class RecordingDisplayPowerController : IDisplayPowerController
    {
        public Task SetDisplayPowerAsync(bool isOn, CancellationToken cancellationToken)
        {
            return Task.CompletedTask;
        }
    }

    private sealed class StubDisplayStateMonitor : IDisplayStateMonitor
    {
        public bool? IsDisplayOn => true;

        public event EventHandler<DisplayStateChangedEventArgs>? DisplayStateChanged;

        public void Raise(bool isOn)
        {
            DisplayStateChanged?.Invoke(this, new DisplayStateChangedEventArgs(isOn));
        }

        public void Dispose()
        {
        }
    }

    private sealed class NotifyingStringWriter : StringWriter
    {
        private readonly TaskCompletionSource<string> _lineWritten = new(TaskCreationOptions.RunContinuationsAsynchronously);

        public override Encoding Encoding => Encoding.UTF8;

        public override Task WriteLineAsync(ReadOnlyMemory<char> buffer, CancellationToken cancellationToken = default)
        {
            _lineWritten.TrySetResult(buffer.ToString());
            return base.WriteLineAsync(buffer, cancellationToken);
        }

        public async Task<string> WaitForLineAsync(TimeSpan timeout)
        {
            return await _lineWritten.Task.WaitAsync(timeout);
        }
    }
}
