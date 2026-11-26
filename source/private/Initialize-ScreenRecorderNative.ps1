function Initialize-ScreenRecorderNative
{
    <#
        .SYNOPSIS
            Load the Windows API helper psScreenRecorder uses to find monitors, windows and the cursor, and return it

        .DESCRIPTION
            Compiles a small C# class the first time it's needed in a session, and returns its type. Call its
            methods through what this returns, not by a fixed type name. Windows only.

            The class's namespace includes a hash of its source, such as PsScreenRecorder.H1a2b3c4d5e.Native.
            .NET can't unload a compiled type, so if an older version of the module compiled its helper earlier
            in the same session, a fixed name would find that old helper, missing anything added since. With
            the hash, a changed helper compiles under a new name alongside the old one.

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
              SelectRegion()           show an overlay over every monitor and let the person drag out an area.
                                       Returns [x, y, width, height], or null if cancelled with Esc or a right-click

            The overlay is a plain Win32 window rather than WinForms, so it can be made per-monitor DPI aware
            itself and report physical pixels. It reads the mouse only from its window messages, which lets
            tests drive it by posting messages to it. It's excluded from screen capture where Windows allows.

        .NOTES
            Author: Adrian Andersson

            Add-Type is not available in Constrained Language Mode. Under CLM, psScreenRecorder can still
            capture by monitor index or window title through ffmpeg, without this helper.

        .EXAMPLE
            $native = Initialize-ScreenRecorderNative
            $native::GetMonitors()

            #### DESCRIPTION
            List the monitors, in physical pixels.
    #>

    [CmdletBinding()]
    [OutputType([type])]
    PARAM()
    begin{
        write-verbose "===========Executing $($MyInvocation.InvocationName)==========="
    }
    process{
        if(!$IsWindows)
        {
            throw 'The native helper is only available on Windows'
        }
        if($script:psScreenRecorderNative)
        {
            return $script:psScreenRecorderNative
        }
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

        //------------------------------------------------------------------------------------------------
        //Region selection overlay
        //------------------------------------------------------------------------------------------------
        delegate IntPtr WndProcDelegate(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct WNDCLASSEX
        {
            public uint cbSize;
            public uint style;
            public WndProcDelegate lpfnWndProc;
            public int cbClsExtra;
            public int cbWndExtra;
            public IntPtr hInstance;
            public IntPtr hIcon;
            public IntPtr hCursor;
            public IntPtr hbrBackground;
            public string lpszMenuName;
            public string lpszClassName;
            public IntPtr hIconSm;
        }

        [StructLayout(LayoutKind.Sequential)]
        struct MSG
        {
            public IntPtr hwnd;
            public uint message;
            public IntPtr wParam;
            public IntPtr lParam;
            public uint time;
            public POINT pt;
        }

        [StructLayout(LayoutKind.Sequential)]
        struct PAINTSTRUCT
        {
            public IntPtr hdc;
            public bool fErase;
            public RECT rcPaint;
            public bool fRestore;
            public bool fIncUpdate;
            [MarshalAs(UnmanagedType.ByValArray, SizeConst = 32)]
            public byte[] rgbReserved;
        }

        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern ushort RegisterClassEx(ref WNDCLASSEX lpwcx);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool UnregisterClass(string lpClassName, IntPtr hInstance);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr CreateWindowEx(uint dwExStyle, string lpClassName, string lpWindowName, uint dwStyle, int x, int y, int nWidth, int nHeight, IntPtr hWndParent, IntPtr hMenu, IntPtr hInstance, IntPtr lpParam);
        [DllImport("user32.dll")] static extern bool DestroyWindow(IntPtr hWnd);
        [DllImport("user32.dll")] static extern IntPtr DefWindowProc(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
        [DllImport("user32.dll")] static extern int GetMessage(out MSG lpMsg, IntPtr hWnd, uint wMsgFilterMin, uint wMsgFilterMax);
        [DllImport("user32.dll")] static extern bool TranslateMessage(ref MSG lpMsg);
        [DllImport("user32.dll")] static extern IntPtr DispatchMessage(ref MSG lpMsg);
        [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
        [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr hWnd);
        [DllImport("user32.dll")] static extern bool SetLayeredWindowAttributes(IntPtr hwnd, uint crKey, byte bAlpha, uint dwFlags);
        [DllImport("user32.dll")] static extern bool SetWindowDisplayAffinity(IntPtr hWnd, uint dwAffinity);
        [DllImport("user32.dll")] static extern IntPtr SetCapture(IntPtr hWnd);
        [DllImport("user32.dll")] static extern bool ReleaseCapture();
        [DllImport("user32.dll")] static extern bool InvalidateRect(IntPtr hWnd, IntPtr lpRect, bool bErase);
        [DllImport("user32.dll")] static extern IntPtr BeginPaint(IntPtr hwnd, out PAINTSTRUCT lpPaint);
        [DllImport("user32.dll")] static extern bool EndPaint(IntPtr hWnd, ref PAINTSTRUCT lpPaint);
        [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr hWnd, out RECT lpRect);
        [DllImport("user32.dll")] static extern int FillRect(IntPtr hDC, ref RECT lprc, IntPtr hbr);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int DrawText(IntPtr hdc, string lpchText, int cchText, ref RECT lprc, uint format);
        [DllImport("user32.dll")] static extern IntPtr LoadCursor(IntPtr hInstance, IntPtr lpCursorName);
        [DllImport("user32.dll")] static extern int GetSystemMetrics(int nIndex);
        [DllImport("user32.dll")] static extern IntPtr SetTimer(IntPtr hWnd, IntPtr nIDEvent, uint uElapse, IntPtr lpTimerFunc);
        [DllImport("user32.dll")] static extern bool KillTimer(IntPtr hWnd, IntPtr uIDEvent);
        [DllImport("user32.dll")] static extern short GetAsyncKeyState(int vKey);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr GetModuleHandle(string lpModuleName);
        [DllImport("gdi32.dll")] static extern IntPtr CreateSolidBrush(uint crColor);
        [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr hObject);
        [DllImport("gdi32.dll")] static extern IntPtr CreateCompatibleDC(IntPtr hdc);
        [DllImport("gdi32.dll")] static extern IntPtr CreateCompatibleBitmap(IntPtr hdc, int cx, int cy);
        [DllImport("gdi32.dll")] static extern IntPtr SelectObject(IntPtr hdc, IntPtr h);
        [DllImport("gdi32.dll")] static extern bool DeleteDC(IntPtr hdc);
        [DllImport("gdi32.dll")] static extern bool BitBlt(IntPtr hdc, int x, int y, int cx, int cy, IntPtr hdcSrc, int x1, int y1, uint rop);
        [DllImport("gdi32.dll")] static extern int SetBkMode(IntPtr hdc, int mode);
        [DllImport("gdi32.dll")] static extern uint SetTextColor(IntPtr hdc, uint color);
        [DllImport("gdi32.dll", CharSet = CharSet.Unicode)] static extern IntPtr CreateFont(int cHeight, int cWidth, int cEscapement, int cOrientation, int cWeight, uint bItalic, uint bUnderline, uint bStrikeOut, uint iCharSet, uint iOutPrecision, uint iClipPrecision, uint iQuality, uint iPitchAndFamily, string pszFaceName);

        public const string SelectorClassName = "PsScreenRecorderRegionSelector";
        const uint WS_POPUP = 0x80000000;
        const uint WS_EX_LAYERED = 0x00080000, WS_EX_TOPMOST = 0x00000008;
        const uint LWA_COLORKEY = 0x1, LWA_ALPHA = 0x2;
        const uint WDA_EXCLUDEFROMCAPTURE = 0x11;
        const uint WM_PAINT = 0x000F, WM_ERASEBKGND = 0x0014, WM_KEYDOWN = 0x0100, WM_TIMER = 0x0113;
        const uint WM_MOUSEMOVE = 0x0200, WM_LBUTTONDOWN = 0x0201, WM_LBUTTONUP = 0x0202, WM_RBUTTONDOWN = 0x0204;
        const int VK_ESCAPE = 0x1B;
        //Magenta is drawn fully transparent, so the selected area shows through clear while the rest is dimmed
        const uint ColorKey = 0x00FF00FF;
        const byte DimAlpha = 110;
        const int MinimumSize = 4;

        static WndProcDelegate selectorProc;
        static bool selecting, selectionDone, selectionCancelled;
        static int startX, startY, currentX, currentY;
        static IntPtr selectorFont = IntPtr.Zero;

        static int LowWord(IntPtr value) { return (short)((long)value & 0xFFFF); }
        static int HighWord(IntPtr value) { return (short)(((long)value >> 16) & 0xFFFF); }

        static RECT SelectionRect()
        {
            return new RECT
            {
                Left = Math.Min(startX, currentX),
                Top = Math.Min(startY, currentY),
                Right = Math.Max(startX, currentX),
                Bottom = Math.Max(startY, currentY)
            };
        }

        static void PaintSelector(IntPtr hWnd)
        {
            PAINTSTRUCT paint;
            IntPtr hdc = BeginPaint(hWnd, out paint);
            RECT client;
            GetClientRect(hWnd, out client);
            //Draw into a buffer first, so the selection doesn't flicker while dragging
            IntPtr buffer = CreateCompatibleDC(hdc);
            IntPtr bitmap = CreateCompatibleBitmap(hdc, client.Right, client.Bottom);
            IntPtr oldBitmap = SelectObject(buffer, bitmap);
            IntPtr oldFont = SelectObject(buffer, selectorFont);
            SetBkMode(buffer, 1);
            SetTextColor(buffer, 0x00FFFFFF);

            IntPtr dim = CreateSolidBrush(0x00000000);
            FillRect(buffer, ref client, dim);
            DeleteObject(dim);

            if (selecting)
            {
                RECT selection = SelectionRect();
                RECT border = new RECT { Left = selection.Left - 2, Top = selection.Top - 2, Right = selection.Right + 2, Bottom = selection.Bottom + 2 };
                IntPtr red = CreateSolidBrush(0x000000FF);
                FillRect(buffer, ref border, red);
                DeleteObject(red);
                IntPtr clear = CreateSolidBrush(ColorKey);
                FillRect(buffer, ref selection, clear);
                DeleteObject(clear);
                string size = String.Format("{0} x {1}", selection.Right - selection.Left, selection.Bottom - selection.Top);
                RECT label = new RECT { Left = selection.Left, Top = selection.Bottom + 8, Right = selection.Left + 600, Bottom = selection.Bottom + 60 };
                DrawText(buffer, size, -1, ref label, 0x20 /*DT_SINGLELINE*/);
            }
            else
            {
                RECT centre = client;
                DrawText(buffer, "Drag to select the area to record. Right-click or Esc to cancel.", -1, ref centre, 0x1 | 0x4 | 0x20 /*centred, single line*/);
            }

            BitBlt(hdc, 0, 0, client.Right, client.Bottom, buffer, 0, 0, 0x00CC0020 /*SRCCOPY*/);
            SelectObject(buffer, oldFont);
            SelectObject(buffer, oldBitmap);
            DeleteObject(bitmap);
            DeleteDC(buffer);
            EndPaint(hWnd, ref paint);
        }

        static void CancelSelection()
        {
            selecting = false;
            selectionCancelled = true;
            selectionDone = true;
        }

        static IntPtr SelectorWndProc(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam)
        {
            switch (msg)
            {
                case WM_LBUTTONDOWN:
                    selecting = true;
                    startX = currentX = LowWord(lParam);
                    startY = currentY = HighWord(lParam);
                    SetCapture(hWnd);
                    InvalidateRect(hWnd, IntPtr.Zero, false);
                    return IntPtr.Zero;
                case WM_MOUSEMOVE:
                    if (selecting)
                    {
                        currentX = LowWord(lParam);
                        currentY = HighWord(lParam);
                        InvalidateRect(hWnd, IntPtr.Zero, false);
                    }
                    return IntPtr.Zero;
                case WM_LBUTTONUP:
                    if (selecting)
                    {
                        currentX = LowWord(lParam);
                        currentY = HighWord(lParam);
                        ReleaseCapture();
                        //A click without a drag is ignored, rather than recording a sliver
                        if (Math.Abs(currentX - startX) >= MinimumSize && Math.Abs(currentY - startY) >= MinimumSize)
                        {
                            selectionDone = true;
                        }
                        else
                        {
                            selecting = false;
                            InvalidateRect(hWnd, IntPtr.Zero, false);
                        }
                    }
                    return IntPtr.Zero;
                case WM_RBUTTONDOWN:
                    CancelSelection();
                    return IntPtr.Zero;
                case WM_KEYDOWN:
                    if ((int)wParam == VK_ESCAPE) { CancelSelection(); }
                    return IntPtr.Zero;
                case WM_TIMER:
                    //The terminal may keep keyboard focus, so Esc is also checked directly
                    if ((GetAsyncKeyState(VK_ESCAPE) & 0x8000) != 0) { CancelSelection(); }
                    return IntPtr.Zero;
                case WM_ERASEBKGND:
                    return new IntPtr(1);
                case WM_PAINT:
                    PaintSelector(hWnd);
                    return IntPtr.Zero;
            }
            return DefWindowProc(hWnd, msg, wParam, lParam);
        }

        public static int[] SelectRegion()
        {
            return WithDpiAwareness(() =>
            {
                selecting = false;
                selectionDone = false;
                selectionCancelled = false;
                //The virtual desktop, every monitor together, in physical pixels
                int originX = GetSystemMetrics(76), originY = GetSystemMetrics(77);
                int width = GetSystemMetrics(78), height = GetSystemMetrics(79);

                IntPtr instance = GetModuleHandle(null);
                selectorProc = SelectorWndProc;
                var windowClass = new WNDCLASSEX
                {
                    cbSize = (uint)Marshal.SizeOf(typeof(WNDCLASSEX)),
                    lpfnWndProc = selectorProc,
                    hInstance = instance,
                    hCursor = LoadCursor(IntPtr.Zero, new IntPtr(32515)), //IDC_CROSS
                    lpszClassName = SelectorClassName
                };
                RegisterClassEx(ref windowClass);
                if (selectorFont == IntPtr.Zero)
                {
                    selectorFont = CreateFont(-28, 0, 0, 0, 600, 0, 0, 0, 1, 0, 0, 5, 0, "Segoe UI");
                }

                IntPtr window = CreateWindowEx(WS_EX_LAYERED | WS_EX_TOPMOST | (uint)WS_EX_TOOLWINDOW, SelectorClassName, "Select an area to record", WS_POPUP, originX, originY, width, height, IntPtr.Zero, IntPtr.Zero, instance, IntPtr.Zero);
                if (window == IntPtr.Zero)
                {
                    UnregisterClass(SelectorClassName, instance);
                    throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
                }
                try
                {
                    SetLayeredWindowAttributes(window, ColorKey, DimAlpha, LWA_COLORKEY | LWA_ALPHA);
                    SetWindowDisplayAffinity(window, WDA_EXCLUDEFROMCAPTURE);
                    ShowWindow(window, 5);
                    SetForegroundWindow(window);
                    SetTimer(window, new IntPtr(1), 50, IntPtr.Zero);

                    MSG message;
                    while (!selectionDone && GetMessage(out message, IntPtr.Zero, 0, 0) > 0)
                    {
                        TranslateMessage(ref message);
                        DispatchMessage(ref message);
                    }
                }
                finally
                {
                    KillTimer(window, new IntPtr(1));
                    ReleaseCapture();
                    DestroyWindow(window);
                    UnregisterClass(SelectorClassName, instance);
                }

                if (selectionCancelled) { return null; }
                RECT selection = SelectionRect();
                return new int[] { selection.Left + originX, selection.Top + originY, selection.Right - selection.Left, selection.Bottom - selection.Top };
            });
        }
    }
}
'@
        #Name the namespace after the source, so a changed helper never collides with an older one already loaded
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try{
            $hash = [Convert]::ToHexString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($source)), 0, 5).ToLowerInvariant()
        }finally{
            $sha.Dispose()
        }
        $namespace = "PsScreenRecorder.H$hash"
        $typeName = "$namespace.Native"
        [type]$native = $typeName -as [type]
        if($native)
        {
            write-verbose "Native helper $typeName is already loaded"
        }else{
            write-verbose "Compiling the native helper as $typeName"
            Add-Type -TypeDefinition $source.Replace('namespace PsScreenRecorder', "namespace $namespace") -Language CSharp -ErrorAction Stop
            $native = $typeName -as [type]
        }
        $script:psScreenRecorderNative = $native
        [type]$native
    }
}
