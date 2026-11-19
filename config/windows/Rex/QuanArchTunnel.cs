using System;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;

internal static class QuanArchTunnel
{
    [StructLayout(LayoutKind.Sequential)]
    private struct JobLimits
    {
        public long ProcessTime, JobTime;
        public uint Flags;
        public UIntPtr MinimumWorkingSet, MaximumWorkingSet;
        public uint ActiveProcessLimit;
        public UIntPtr Affinity;
        public uint Priority, SchedulingClass;
        public ulong ReadOperations, WriteOperations, OtherOperations, ReadBytes, WriteBytes, OtherBytes;
        public UIntPtr ProcessMemoryLimit, JobMemoryLimit, PeakProcessMemory, PeakJobMemory;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr CreateJobObject(IntPtr attributes, string name);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetInformationJobObject(IntPtr job, int kind, ref JobLimits limits, uint size);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr handle);
    [DllImport("kernel32.dll")]
    private static extern IntPtr GetCurrentProcess();

    private static void SuperviseChildren()
    {
        const int extendedLimitInformation = 9;
        const uint killOnJobClose = 0x2000;
        var job = CreateJobObject(IntPtr.Zero, null);
        if (job == IntPtr.Zero) throw new Win32Exception();
        var limits = new JobLimits { Flags = killOnJobClose };
        if (!SetInformationJobObject(job, extendedLimitInformation, ref limits, (uint)Marshal.SizeOf(typeof(JobLimits))) ||
            !AssignProcessToJobObject(job, GetCurrentProcess()))
        {
            int error = Marshal.GetLastWin32Error();
            CloseHandle(job);
            throw new Win32Exception(error);
        }
        // Keep the non-inheritable handle until process exit so stopping the
        // scheduled launcher also kills its SSH child, even on forced stop.
    }

    private static int Main()
    {
        var start = new ProcessStartInfo
        {
            FileName = Path.Combine(Environment.SystemDirectory, @"OpenSSH\ssh.exe"),
            Arguments = "-F NUL -N -T -o BatchMode=yes -o StrictHostKeyChecking=yes -o UpdateHostKeys=no " +
                "-o ExitOnForwardFailure=yes -o ConnectTimeout=5 -o ServerAliveInterval=15 " +
                "-o ServerAliveCountMax=3 -L 127.0.0.1:7297:/run/user/1000/rex/server.sock quando@192.168.1.200",
            UseShellExecute = false,
            CreateNoWindow = true
        };
        try
        {
            SuperviseChildren();
            using (var ssh = Process.Start(start))
            {
                ssh.WaitForExit();
                return ssh.ExitCode;
            }
        }
        catch (Win32Exception error)
        {
            return error.NativeErrorCode;
        }
    }
}
