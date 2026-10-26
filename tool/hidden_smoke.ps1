param(
    [string]$Exe = (Join-Path (Split-Path -Parent $PSScriptRoot) "build\windows\x64\runner\Debug\praxino.exe"),
    [int]$WaitSeconds = 6
)

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class PraxinoHiddenDesktop {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct STARTUPINFO {
        public int cb;
        public string lpReserved;
        public string lpDesktop;
        public string lpTitle;
        public int dwX;
        public int dwY;
        public int dwXSize;
        public int dwYSize;
        public int dwXCountChars;
        public int dwYCountChars;
        public int dwFillAttribute;
        public int dwFlags;
        public short wShowWindow;
        public short cbReserved2;
        public IntPtr lpReserved2;
        public IntPtr hStdInput;
        public IntPtr hStdOutput;
        public IntPtr hStdError;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct PROCESS_INFORMATION {
        public IntPtr hProcess;
        public IntPtr hThread;
        public int dwProcessId;
        public int dwThreadId;
    }

    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern IntPtr CreateDesktop(string name, IntPtr device, IntPtr devmode,
        int flags, uint access, IntPtr security);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool CloseDesktop(IntPtr desktop);

    [DllImport("user32.dll")]
    public static extern bool EnumDesktopWindows(IntPtr desktop, EnumWindowsProc callback, IntPtr param);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool CreateProcess(string application, string commandLine,
        IntPtr processAttributes, IntPtr threadAttributes, bool inheritHandles,
        uint creationFlags, IntPtr environment, string currentDirectory,
        ref STARTUPINFO startupInfo, out PROCESS_INFORMATION processInformation);

    [DllImport("kernel32.dll")]
    public static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);

    [DllImport("kernel32.dll")]
    public static extern bool GetExitCodeProcess(IntPtr process, out uint exitCode);

    [DllImport("kernel32.dll")]
    public static extern bool TerminateProcess(IntPtr process, uint exitCode);

    [DllImport("kernel32.dll")]
    public static extern bool CloseHandle(IntPtr handle);

    public static int Run(string exe, int waitMs, out int windows) {
        windows = 0;
        string name = "PraxinoHidden_" + Guid.NewGuid().ToString("N");
        IntPtr desktop = CreateDesktop(name, IntPtr.Zero, IntPtr.Zero, 0, 0x000F01FF, IntPtr.Zero);
        if (desktop == IntPtr.Zero) return -1;

        STARTUPINFO si = new STARTUPINFO();
        si.cb = Marshal.SizeOf(si);
        si.lpDesktop = name;
        PROCESS_INFORMATION pi;
        bool started = CreateProcess(exe, "\"" + exe + "\"", IntPtr.Zero, IntPtr.Zero,
            false, 0, IntPtr.Zero, System.IO.Path.GetDirectoryName(exe), ref si, out pi);
        if (!started) {
            CloseDesktop(desktop);
            return -2;
        }

        uint wait = WaitForSingleObject(pi.hProcess, (uint)waitMs);
        if (wait == 258) {
            int count = 0;
            EnumDesktopWindows(desktop, delegate(IntPtr hWnd, IntPtr param) {
                count++;
                return true;
            }, IntPtr.Zero);
            windows = count;
            TerminateProcess(pi.hProcess, 0);
            WaitForSingleObject(pi.hProcess, 2000);
        } else {
            uint exit;
            GetExitCodeProcess(pi.hProcess, out exit);
            windows = -1;
        }

        CloseHandle(pi.hThread);
        CloseHandle(pi.hProcess);
        CloseDesktop(desktop);
        return windows > 0 ? 0 : 2;
    }
}
"@

$windows = 0
$code = [PraxinoHiddenDesktop]::Run($Exe, $WaitSeconds * 1000, [ref]$windows)
Write-Output "hidden_desktop_exit=$code windows=$windows"
exit $code

