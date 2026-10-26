param(
    [string]$Exe = (Join-Path (Split-Path -Parent $PSScriptRoot) "build\windows\x64\runner\Release\praxino.exe")
)

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class PraxinoSingleInstance {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct STARTUPINFO {
        public int cb; public string lpReserved; public string lpDesktop; public string lpTitle;
        public int dwX; public int dwY; public int dwXSize; public int dwYSize;
        public int dwXCountChars; public int dwYCountChars; public int dwFillAttribute; public int dwFlags;
        public short wShowWindow; public short cbReserved2;
        public IntPtr lpReserved2; public IntPtr hStdInput; public IntPtr hStdOutput; public IntPtr hStdError;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct PROCESS_INFORMATION {
        public IntPtr hProcess; public IntPtr hThread; public int dwProcessId; public int dwThreadId;
    }

    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern IntPtr CreateDesktop(string name, IntPtr device, IntPtr devmode, int flags, uint access, IntPtr security);
    [DllImport("user32.dll")] public static extern bool CloseDesktop(IntPtr desktop);
    [DllImport("user32.dll")] public static extern bool EnumDesktopWindows(IntPtr desktop, EnumWindowsProc callback, IntPtr param);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool CreateProcess(string application, string commandLine, IntPtr pa, IntPtr ta,
        bool inherit, uint flags, IntPtr env, string cwd, ref STARTUPINFO si, out PROCESS_INFORMATION pi);
    [DllImport("kernel32.dll")] public static extern uint WaitForSingleObject(IntPtr handle, uint ms);
    [DllImport("kernel32.dll")] public static extern bool TerminateProcess(IntPtr process, uint code);
    [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr handle);

    static bool Start(string exe, string desktop, out PROCESS_INFORMATION pi) {
        STARTUPINFO si = new STARTUPINFO();
        si.cb = Marshal.SizeOf(si);
        si.lpDesktop = desktop;
        return CreateProcess(exe, "\"" + exe + "\"", IntPtr.Zero, IntPtr.Zero, false, 0,
            IntPtr.Zero, System.IO.Path.GetDirectoryName(exe), ref si, out pi);
    }

    public static int Run(string exe, out int windows, out bool secondExited) {
        windows = 0;
        secondExited = false;
        string name = "PraxinoSingle_" + Guid.NewGuid().ToString("N");
        IntPtr desktop = CreateDesktop(name, IntPtr.Zero, IntPtr.Zero, 0, 0x000F01FF, IntPtr.Zero);
        if (desktop == IntPtr.Zero) return -1;

        PROCESS_INFORMATION first, second;
        if (!Start(exe, name, out first)) { CloseDesktop(desktop); return -2; }
        WaitForSingleObject(first.hProcess, 3500);

        if (!Start(exe, name, out second)) {
            TerminateProcess(first.hProcess, 0); CloseHandle(first.hProcess); CloseHandle(first.hThread);
            CloseDesktop(desktop); return -3;
        }
        uint secondWait = WaitForSingleObject(second.hProcess, 2500);
        secondExited = secondWait != 258;

        int count = 0;
        EnumDesktopWindows(desktop, delegate(IntPtr hWnd, IntPtr param) { count++; return true; }, IntPtr.Zero);
        windows = count;

        TerminateProcess(first.hProcess, 0);
        if (!secondExited) TerminateProcess(second.hProcess, 0);
        WaitForSingleObject(first.hProcess, 2000);
        if (!secondExited) WaitForSingleObject(second.hProcess, 2000);
        CloseHandle(first.hProcess); CloseHandle(first.hThread);
        CloseHandle(second.hProcess); CloseHandle(second.hThread);
        CloseDesktop(desktop);
        return 0;
    }
}
"@

$windows = 0
$secondExited = $false
$code = [PraxinoSingleInstance]::Run($Exe, [ref]$windows, [ref]$secondExited)
Write-Output "single_instance_exit=$code windows=$windows second_exited=$secondExited"
if ($code -ne 0 -or -not $secondExited) { exit 1 }
exit 0
