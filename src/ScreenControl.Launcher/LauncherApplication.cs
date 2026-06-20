using System.Diagnostics;
using System.Text;

namespace ScreenControl.Launcher;

internal static class LauncherApplication
{
    private const int UsageExitCode = 64;
    private const int FailureExitCode = 1;

    internal static int Run(IReadOnlyList<string> args, string logPath)
    {
        ArgumentNullException.ThrowIfNull(args);
        ArgumentException.ThrowIfNullOrWhiteSpace(logPath);

        if (args.Count < 2)
        {
            WriteLog(
                logPath,
                "Usage: ScreenControl.Launcher.exe <powershellPath> <scriptPath> [scriptArgs...]");
            return UsageExitCode;
        }

        try
        {
            string powershellPath = Path.GetFullPath(args[0]);
            string scriptPath = Path.GetFullPath(args[1]);
            ValidateFileExists(powershellPath, "PowerShell executable");
            ValidateFileExists(scriptPath, "PowerShell script");

            ProcessStartInfo startInfo = CreatePowerShellStartInfo(
                powershellPath,
                scriptPath,
                args.Skip(2));

            using KillOnCloseJob job = new();
            using Process process = Process.Start(startInfo)
                ?? throw new InvalidOperationException("PowerShell did not return a process handle.");

            try
            {
                job.Assign(process);
                process.WaitForExit();
                return process.ExitCode;
            }
            catch
            {
                if (!process.HasExited)
                {
                    process.Kill(entireProcessTree: true);
                    process.WaitForExit();
                }

                throw;
            }
        }
        catch (Exception exception)
        {
            WriteLog(logPath, $"Launcher failed: {exception}");
            return FailureExitCode;
        }
    }

    internal static ProcessStartInfo CreatePowerShellStartInfo(
        string powershellPath,
        string scriptPath,
        IEnumerable<string> scriptArguments)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(powershellPath);
        ArgumentException.ThrowIfNullOrWhiteSpace(scriptPath);
        ArgumentNullException.ThrowIfNull(scriptArguments);

        ProcessStartInfo startInfo = new()
        {
            FileName = powershellPath,
            WorkingDirectory = Path.GetDirectoryName(Path.GetFullPath(scriptPath))
                ?? AppContext.BaseDirectory,
            UseShellExecute = false,
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden,
        };

        startInfo.ArgumentList.Add("-NoProfile");
        startInfo.ArgumentList.Add("-NonInteractive");
        startInfo.ArgumentList.Add("-ExecutionPolicy");
        startInfo.ArgumentList.Add("Bypass");
        startInfo.ArgumentList.Add("-File");
        startInfo.ArgumentList.Add(scriptPath);

        foreach (string argument in scriptArguments)
        {
            startInfo.ArgumentList.Add(argument);
        }

        return startInfo;
    }

    private static void ValidateFileExists(string path, string description)
    {
        if (!File.Exists(path))
        {
            throw new FileNotFoundException($"{description} does not exist: {path}", path);
        }
    }

    private static void WriteLog(string logPath, string message)
    {
        try
        {
            string fullLogPath = Path.GetFullPath(logPath);
            string? logDirectory = Path.GetDirectoryName(fullLogPath);
            if (!string.IsNullOrWhiteSpace(logDirectory))
            {
                Directory.CreateDirectory(logDirectory);
            }

            string line = $"[{DateTimeOffset.Now:yyyy-MM-dd HH:mm:ss.fff zzz}] {message}{Environment.NewLine}";
            File.AppendAllText(fullLogPath, line, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
        }
        catch
        {
            // The launcher must preserve its defined exit code even if diagnostics cannot be written.
        }
    }
}
