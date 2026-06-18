using System.Text.Json;
using ScreenControl.Host.Display;

namespace ScreenControl.Host.Protocol;

internal sealed class JsonLineHost : IAsyncDisposable
{
    private readonly TextReader _input;
    private readonly TextWriter _output;
    private readonly DisplayCommandProcessor _processor;
    private readonly IDisplayStateMonitor _stateMonitor;
    private readonly SemaphoreSlim _writeLock = new(1, 1);
    private bool _disposed;

    public JsonLineHost(
        TextReader input,
        TextWriter output,
        DisplayCommandProcessor processor,
        IDisplayStateMonitor stateMonitor)
    {
        _input = input;
        _output = output;
        _processor = processor;
        _stateMonitor = stateMonitor;
        _stateMonitor.DisplayStateChanged += OnDisplayStateChanged;
    }

    public async Task RunAsync(CancellationToken cancellationToken)
    {
        while (await _input.ReadLineAsync(cancellationToken).ConfigureAwait(false) is { } line)
        {
            if (string.IsNullOrWhiteSpace(line))
            {
                continue;
            }

            HostResult result = await _processor.ProcessAsync(line, cancellationToken).ConfigureAwait(false);
            await WriteMessageAsync(result, cancellationToken).ConfigureAwait(false);
        }
    }

    public async ValueTask DisposeAsync()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        _stateMonitor.DisplayStateChanged -= OnDisplayStateChanged;
        await _writeLock.WaitAsync().ConfigureAwait(false);
        _writeLock.Release();
        GC.SuppressFinalize(this);
    }

    private async void OnDisplayStateChanged(object? sender, DisplayStateChangedEventArgs eventArgs)
    {
        if (_disposed)
        {
            return;
        }

        try
        {
            await WriteMessageAsync(new HostDisplayState("displayState", eventArgs.IsOn), CancellationToken.None).ConfigureAwait(false);
        }
        catch (Exception exception) when (exception is IOException or ObjectDisposedException)
        {
            await Console.Error.WriteLineAsync($"Failed to publish display state: {exception.Message}").ConfigureAwait(false);
        }
    }

    private async Task WriteMessageAsync<T>(T message, CancellationToken cancellationToken)
    {
        string json = JsonSerializer.Serialize(message);
        await _writeLock.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            await _output.WriteLineAsync(json.AsMemory(), cancellationToken).ConfigureAwait(false);
            await _output.FlushAsync(cancellationToken).ConfigureAwait(false);
        }
        finally
        {
            _writeLock.Release();
        }
    }
}
