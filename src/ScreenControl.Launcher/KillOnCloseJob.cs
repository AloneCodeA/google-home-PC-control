using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace ScreenControl.Launcher;

internal sealed class KillOnCloseJob : IDisposable
{
    private const uint JobObjectLimitKillOnJobClose = 0x00002000;
    private const int JobObjectExtendedLimitInformationClass = 9;

    private readonly SafeFileHandle handle;
    private bool disposed;

    internal KillOnCloseJob()
    {
        IntPtr nativeHandle = CreateJobObject(IntPtr.Zero, null);
        if (nativeHandle == IntPtr.Zero || nativeHandle == new IntPtr(-1))
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(), "CreateJobObject failed.");
        }

        handle = new SafeFileHandle(nativeHandle, ownsHandle: true);
        ConfigureKillOnClose();
    }

    internal void Assign(Process process)
    {
        ArgumentNullException.ThrowIfNull(process);
        ObjectDisposedException.ThrowIf(disposed, this);

        if (!AssignProcessToJobObject(handle, process.Handle))
        {
            throw new Win32Exception(
                Marshal.GetLastWin32Error(),
                $"AssignProcessToJobObject failed for process {process.Id}.");
        }
    }

    /// <summary>
    /// Closes the native job handle and terminates processes assigned to the job.
    /// </summary>
    public void Dispose()
    {
        if (disposed)
        {
            return;
        }

        handle.Dispose();
        disposed = true;
    }

    private void ConfigureKillOnClose()
    {
        JobObjectExtendedLimitInformation information = new();
        information.BasicLimitInformation.LimitFlags = JobObjectLimitKillOnJobClose;
        int informationLength = Marshal.SizeOf<JobObjectExtendedLimitInformation>();
        IntPtr informationPointer = Marshal.AllocHGlobal(informationLength);

        try
        {
            Marshal.StructureToPtr(information, informationPointer, fDeleteOld: false);
            if (!SetInformationJobObject(
                    handle,
                    JobObjectExtendedLimitInformationClass,
                    informationPointer,
                    checked((uint)informationLength)))
            {
                throw new Win32Exception(
                    Marshal.GetLastWin32Error(),
                    "SetInformationJobObject failed.");
            }
        }
        catch
        {
            handle.Dispose();
            disposed = true;
            throw;
        }
        finally
        {
            Marshal.FreeHGlobal(informationPointer);
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct JobObjectBasicLimitInformation
    {
        internal long PerProcessUserTimeLimit;
        internal long PerJobUserTimeLimit;
        internal uint LimitFlags;
        internal UIntPtr MinimumWorkingSetSize;
        internal UIntPtr MaximumWorkingSetSize;
        internal uint ActiveProcessLimit;
        internal UIntPtr Affinity;
        internal uint PriorityClass;
        internal uint SchedulingClass;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct IoCounters
    {
        internal ulong ReadOperationCount;
        internal ulong WriteOperationCount;
        internal ulong OtherOperationCount;
        internal ulong ReadTransferCount;
        internal ulong WriteTransferCount;
        internal ulong OtherTransferCount;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct JobObjectExtendedLimitInformation
    {
        internal JobObjectBasicLimitInformation BasicLimitInformation;
        internal IoCounters IoInfo;
        internal UIntPtr ProcessMemoryLimit;
        internal UIntPtr JobMemoryLimit;
        internal UIntPtr PeakProcessMemoryUsed;
        internal UIntPtr PeakJobMemoryUsed;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr CreateJobObject(IntPtr securityAttributes, string? name);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetInformationJobObject(
        SafeFileHandle job,
        int informationClass,
        IntPtr information,
        uint informationLength);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool AssignProcessToJobObject(SafeFileHandle job, IntPtr process);
}
