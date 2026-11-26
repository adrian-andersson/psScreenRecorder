function Initialize-ScreenRecorderNative
{
    <#
        .SYNOPSIS
            Load the Windows API helper psScreenRecorder uses to find monitors, windows and the cursor

        .DESCRIPTION
            Compiles a small C# class, PsScreenRecorder.Native, the first time it's needed in a session.
            Windows only.

            The problem it solves: pwsh is not DPI aware, so on a scaled display Windows hands it
            made-up "logical" coordinates. Version 1 tried to scale those back with one factor for the
            whole desktop, which can't work when monitors have different scaling.

            Instead, every call here switches the current thread to per-monitor DPI awareness (V2) for
            the duration of the call, then switches it back. While it's switched, Windows reports real,
            physical pixels: the same coordinates ffmpeg captures in. No scale maths is needed. Only the
            thread is changed, never the process, so the PowerShell host is left as it was.

            Methods (all return physical pixels):
              GetMonitors()            every monitor: handle, device name, bounds, primary, DPI
              GetWindows()             visible top-level windows with a title, in z-order, top first
              GetWindow(handle)        one window, or null if it's gone
              GetForegroundWindow()    handle of the window with focus
              GetCursorPosition()      the mouse pointer, as [x, y]
              KillWithThisProcess(h)   end the process with handle h when this PowerShell process ends, however
                                       it ends, by putting it in a Job Object set to kill on close

        .NOTES
            Author: Adrian Andersson

            Add-Type is not available in Constrained Language Mode. Under CLM, psScreenRecorder can still
            capture by monitor index or window title through ffmpeg, without this helper.

        .EXAMPLE
            Initialize-ScreenRecorderNative
            [PsScreenRecorder.Native]::GetMonitors()

            #### DESCRIPTION
            List the monitors, in physical pixels.
    #>

    [CmdletBinding()]
    PARAM()
    begin{
        write-verbose "===========Executing $($MyInvocation.InvocationName)==========="
    }
    process{
        if(!$IsWindows)
        {
            throw 'The native helper is only available on Windows'
        }
        if('PsScreenRecorder.Native' -as [type])
        {
            write-verbose 'Native helper already loaded'
            return
        }
        write-verbose 'Compiling the native helper'
        $source = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace PsScreenRecorder
{
    public class MonitorInfo
    {
        public long Handle;
        public string DeviceName;
        public int Left, Top, Right, Bottom;
        public bool IsPrimary;
        public int Dpi;
        public int Width { get { return Right - Left; } }
        public int Height { get { return Bottom - Top; } }
    }

    public class WindowInfo
    {
        public long Handle;
        public string Title;
        public string ClassName;
        public int ProcessId;
        public int Left, Top, Right, Bottom;
        public bool IsMinimized;
        public int Width { get { return Right - Left; } }
        public int Height { get { return Bottom - Top; } }
    }

    public static class Native
    {
        [StructLayout(LayoutKind.Sequential)]
        struct RECT { public int Left, Top, Right, Bottom; }

        [StructLayout(LayoutKind.Sequential)]
        struct POINT { public int X, Y; }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct MONITORINFOEX
        {
            public int cbSize;
            public RECT rcMonitor;
            public RECT rcWork;
            public uint dwFlags;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
            public string szDevice;
        }

        delegate bool MonitorEnumProc(IntPtr hMonitor, IntPtr hdc, IntPtr lprcMonitor, IntPtr dwData);
        delegate bool WindowEnumProc(IntPtr hWnd, IntPtr lParam);

        [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr dpiContext);
        [DllImport("user32.dll")] static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr lprcClip, MonitorEnumProc lpfnEnum, IntPtr dwData);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFOEX lpmi);
        [DllImport("shcore.dll")] static extern int GetDpiForMonitor(IntPtr hmonitor, int dpiType, out uint dpiX, out uint dpiY);
        [DllImport("user32.dll")] static extern bool EnumWindows(WindowEnumProc lpEnumFunc, IntPtr lParam);
        [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hWnd);
        [DllImport("user32.dll")] static extern bool IsWindow(IntPtr hWnd);
        [DllImport("user32.dll")] static extern bool IsIconic(IntPtr hWnd);
        [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr hWnd, uint uCmd);
        [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr hWnd, int nIndex);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
        [DllImport("user32.dll")] static extern int GetWindowTextLength(IntPtr hWnd);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);
        [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
        [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
        [DllImport("user32.dll", EntryPoint = "GetForegroundWindow")] static extern IntPtr NativeGetForegroundWindow();
        [DllImport("user32.dll")] static extern bool GetCursorPos(out POINT lpPoint);
        [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr hwnd, int dwAttribute, out RECT pvAttribute, int cbAttribute);
        [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr hwnd, int dwAttribute, out int pvAttribute, int cbAttribute);

        //DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2
        static readonly IntPtr PerMonitorAwareV2 = new IntPtr(-4);
        const uint GW_OWNER = 4;
        const int GWL_EXSTYLE = -20;
        const int WS_EX_TOOLWINDOW = 0x00000080;
        const int DWMWA_EXTENDED_FRAME_BOUNDS = 9;
        const int DWMWA_CLOAKED = 14;
        const uint MONITORINFOF_PRIMARY = 1;

        //Run an action with the thread switched to per-monitor DPI awareness, then switch it back
        static T WithDpiAwareness<T>(Func<T> action)
        {
            IntPtr previous = SetThreadDpiAwarenessContext(PerMonitorAwareV2);
            try { return action(); }
            finally { if (previous != IntPtr.Zero) { SetThreadDpiAwarenessContext(previous); } }
        }

        public static MonitorInfo[] GetMonitors()
        {
            return WithDpiAwareness(() =>
            {
                var monitors = new List<MonitorInfo>();
                EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, (IntPtr hMonitor, IntPtr hdc, IntPtr rect, IntPtr data) =>
                {
                    var info = new MONITORINFOEX();
                    info.cbSize = Marshal.SizeOf(typeof(MONITORINFOEX));
                    if (GetMonitorInfo(hMonitor, ref info))
                    {
                        uint dpiX, dpiY;
                        int dpi = GetDpiForMonitor(hMonitor, 0, out dpiX, out dpiY) == 0 ? (int)dpiX : 96;
                        monitors.Add(new MonitorInfo
                        {
                            Handle = hMonitor.ToInt64(),
                            DeviceName = info.szDevice,
                            Left = info.rcMonitor.Left,
                            Top = info.rcMonitor.Top,
                            Right = info.rcMonitor.Right,
                            Bottom = info.rcMonitor.Bottom,
                            IsPrimary = (info.dwFlags & MONITORINFOF_PRIMARY) != 0,
                            Dpi = dpi
                        });
                    }
                    return true;
                }, IntPtr.Zero);
                return monitors.ToArray();
            });
        }

        //The window's visible bounds. GetWindowRect includes the invisible resize border Windows 10 and 11 add
        static bool TryGetBounds(IntPtr hWnd, out RECT bounds)
        {
            if (DwmGetWindowAttribute(hWnd, DWMWA_EXTENDED_FRAME_BOUNDS, out bounds, Marshal.SizeOf(typeof(RECT))) == 0)
            {
                return true;
            }
            return GetWindowRect(hWnd, out bounds);
        }

        static WindowInfo Describe(IntPtr hWnd)
        {
            RECT bounds;
            if (!TryGetBounds(hWnd, out bounds)) { return null; }
            int length = GetWindowTextLength(hWnd);
            var title = new StringBuilder(length + 1);
            GetWindowText(hWnd, title, title.Capacity);
            var className = new StringBuilder(256);
            GetClassName(hWnd, className, className.Capacity);
            uint processId;
            GetWindowThreadProcessId(hWnd, out processId);
            return new WindowInfo
            {
                Handle = hWnd.ToInt64(),
                Title = title.ToString(),
                ClassName = className.ToString(),
                ProcessId = (int)processId,
                Left = bounds.Left,
                Top = bounds.Top,
                Right = bounds.Right,
                Bottom = bounds.Bottom,
                IsMinimized = IsIconic(hWnd)
            };
        }

        //Windows a person would call a window: visible, titled, not owned by another window, not a tool
        //window, and not cloaked (suspended store apps and windows on other virtual desktops are cloaked)
        static bool IsUserWindow(IntPtr hWnd)
        {
            if (!IsWindowVisible(hWnd)) { return false; }
            if (GetWindowTextLength(hWnd) == 0) { return false; }
            if (GetWindow(hWnd, GW_OWNER) != IntPtr.Zero) { return false; }
            if ((GetWindowLong(hWnd, GWL_EXSTYLE) & WS_EX_TOOLWINDOW) != 0) { return false; }
            int cloaked;
            if (DwmGetWindowAttribute(hWnd, DWMWA_CLOAKED, out cloaked, sizeof(int)) == 0 && cloaked != 0) { return false; }
            return true;
        }

        public static WindowInfo[] GetWindows()
        {
            return WithDpiAwareness(() =>
            {
                var windows = new List<WindowInfo>();
                EnumWindows((IntPtr hWnd, IntPtr lParam) =>
                {
                    if (IsUserWindow(hWnd))
                    {
                        var info = Describe(hWnd);
                        if (info != null) { windows.Add(info); }
                    }
                    return true;
                }, IntPtr.Zero);
                return windows.ToArray();
            });
        }

        public static WindowInfo GetWindow(long handle)
        {
            return WithDpiAwareness(() =>
            {
                var hWnd = new IntPtr(handle);
                return IsWindow(hWnd) ? Describe(hWnd) : null;
            });
        }

        public static long GetForegroundWindow()
        {
            return NativeGetForegroundWindow().ToInt64();
        }

        public static int[] GetCursorPosition()
        {
            return WithDpiAwareness(() =>
            {
                POINT point;
                return GetCursorPos(out point) ? new int[] { point.X, point.Y } : null;
            });
        }

        [StructLayout(LayoutKind.Sequential)]
        struct JOBOBJECT_BASIC_LIMIT_INFORMATION
        {
            public long PerProcessUserTimeLimit;
            public long PerJobUserTimeLimit;
            public uint LimitFlags;
            public UIntPtr MinimumWorkingSetSize;
            public UIntPtr MaximumWorkingSetSize;
            public uint ActiveProcessLimit;
            public UIntPtr Affinity;
            public uint PriorityClass;
            public uint SchedulingClass;
        }

        [StructLayout(LayoutKind.Sequential)]
        struct IO_COUNTERS
        {
            public ulong ReadOperationCount, WriteOperationCount, OtherOperationCount;
            public ulong ReadTransferCount, WriteTransferCount, OtherTransferCount;
        }

        [StructLayout(LayoutKind.Sequential)]
        struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION
        {
            public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
            public IO_COUNTERS IoInfo;
            public UIntPtr ProcessMemoryLimit;
            public UIntPtr JobMemoryLimit;
            public UIntPtr PeakProcessMemoryUsed;
            public UIntPtr PeakJobMemoryUsed;
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr CreateJobObject(IntPtr lpJobAttributes, string lpName);
        [DllImport("kernel32.dll")] static extern bool SetInformationJobObject(IntPtr hJob, int infoClass, ref JOBOBJECT_EXTENDED_LIMIT_INFORMATION info, uint length);
        [DllImport("kernel32.dll")] static extern bool AssignProcessToJobObject(IntPtr hJob, IntPtr hProcess);

        const int JobObjectExtendedLimitInformation = 9;
        const uint JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x2000;
        //One job for the whole session. Only this process holds its handle, so Windows closes it, and ends
        //everything in the job, when this process ends: by exit, crash, closing the window or Task Manager
        static IntPtr cleanupJob = IntPtr.Zero;
        static readonly object jobLock = new object();

        public static bool KillWithThisProcess(IntPtr processHandle)
        {
            lock (jobLock)
            {
                if (cleanupJob == IntPtr.Zero)
                {
                    IntPtr job = CreateJobObject(IntPtr.Zero, null);
                    if (job == IntPtr.Zero) { return false; }
                    var info = new JOBOBJECT_EXTENDED_LIMIT_INFORMATION();
                    info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
                    if (!SetInformationJobObject(job, JobObjectExtendedLimitInformation, ref info, (uint)Marshal.SizeOf(typeof(JOBOBJECT_EXTENDED_LIMIT_INFORMATION))))
                    {
                        return false;
                    }
                    cleanupJob = job;
                }
            }
            return AssignProcessToJobObject(cleanupJob, processHandle);
        }
    }
}
'@
        Add-Type -TypeDefinition $source -Language CSharp -ErrorAction Stop
    }
}
