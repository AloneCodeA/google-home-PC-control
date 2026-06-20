namespace ScreenControl.Launcher;

internal static class Program
{
    private static int Main(string[] args)
    {
        string logPath = Path.Combine(AppContext.BaseDirectory, "launcher.log");
        return LauncherApplication.Run(args, logPath);
    }
}
