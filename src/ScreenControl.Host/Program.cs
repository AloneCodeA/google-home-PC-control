using System.Text;
using System.Windows.Forms;
using ScreenControl.Host.Display;
using ScreenControl.Host.Protocol;

namespace ScreenControl.Host;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        Console.InputEncoding = new UTF8Encoding(encoderShouldEmitUTF8Identifier: false);
        Console.OutputEncoding = new UTF8Encoding(encoderShouldEmitUTF8Identifier: false);

        if (args.Contains("--help", StringComparer.Ordinal))
        {
            Console.WriteLine("Usage: ScreenControl.Host.exe [--self-test]");
            Console.WriteLine("  no arguments  Run the JSON Lines protocol host.");
            Console.WriteLine("  --self-test   Turn all displays off and restore them after five seconds.");
            return 0;
        }

        using var cancellationSource = new CancellationTokenSource();

        ConsoleCancelEventHandler cancelHandler = (_, eventArgs) =>
        {
            eventArgs.Cancel = true;
            cancellationSource.Cancel();
        };
        Console.CancelKeyPress += cancelHandler;

        try
        {
            using var stateMonitor = new WindowsDisplayStateMonitor();
            var nativeApi = new WindowsDisplayNativeApi();
            using var wakeLock = new SystemWakeLock(nativeApi);
            var displayController = new WindowsDisplayPowerController(nativeApi, stateMonitor, new SystemAsyncDelay());

            if (args.Contains("--self-test", StringComparer.Ordinal))
            {
                var selfTest = new DisplaySelfTest(displayController, new SystemAsyncDelay());
                WaitWithMessagePump(selfTest.RunAsync(TimeSpan.FromSeconds(5), cancellationSource.Token));
                return 0;
            }

            var processor = new DisplayCommandProcessor(displayController);
            var host = new JsonLineHost(Console.In, Console.Out, processor, stateMonitor);

            try
            {
                Task hostTask = Task.Run(() => host.RunAsync(cancellationSource.Token), CancellationToken.None);
                WaitWithMessagePump(hostTask);
            }
            finally
            {
                host.DisposeAsync().AsTask().GetAwaiter().GetResult();
            }

            return 0;
        }
        catch (OperationCanceledException) when (cancellationSource.IsCancellationRequested)
        {
            return 0;
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine($"Screen control host failed: {exception.Message}");
            return 1;
        }
        finally
        {
            Console.CancelKeyPress -= cancelHandler;
        }
    }

    private static void WaitWithMessagePump(Task task)
    {
        while (!task.IsCompleted)
        {
            Application.DoEvents();
            Thread.Sleep(25);
        }

        task.GetAwaiter().GetResult();
    }
}
