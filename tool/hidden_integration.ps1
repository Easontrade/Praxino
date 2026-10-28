# Runs a Flutter integration test on a throwaway desktop, so the app window
# never appears on the user's screen. Used for tests that need a real window
# (WebView2, video output) without disturbing anyone.
#
#   .\tool\hidden_integration.ps1 -Test integration_test\browser_fetch_test.dart
param(
    [string]$Test = 'integration_test\browser_fetch_test.dart',
    [int]$TimeoutSeconds = 900
)

$root = Split-Path -Parent $PSScriptRoot
$log = Join-Path $env:TEMP ("praxino-hidden-it-" + [Guid]::NewGuid().ToString('N') + ".log")
$script = Join-Path $env:TEMP ("praxino-hidden-it-" + [Guid]::NewGuid().ToString('N') + ".cmd")

$cmd = @"
@echo off
set "PATH=$env:Path"
cd /d $root
flutter test $Test -d windows > "$log" 2>&1
echo EXITCODE=%ERRORLEVEL% >> "$log"
"@
Set-Content -LiteralPath $script -Value $cmd -Encoding ascii

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class PraxinoHiddenIntegration {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct STARTUPINFO {
        public int cb; public string lpReserved; public string lpDesktop; public string lpTitle;
        public int dwX; public int dwY; public int dwXSize; public int dwYSize;
        public int dwXCountChars; public int dwYCountChars; public int dwFillAttribute;
        public int dwFlags; public short wShowWindow; public short cbReserved2;
        public IntPtr lpReserved2; public IntPtr hStdInput; public IntPtr hStdOutput; public IntPtr hStdError;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct PROCESS_INFORMATION {
        public IntPtr hProcess; public IntPtr hThread; public int dwProcessId; public int dwThreadId;
    }
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern IntPtr CreateDesktop(string name, IntPtr device, IntPtr devmode, int flags, uint access, IntPtr security);
    [DllImport("user32.dll", SetLastError = true)] public static extern bool CloseDesktop(IntPtr desktop);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool CreateProcess(string application, string commandLine, IntPtr pa, IntPtr ta,
        bool inherit, uint flags, IntPtr env, string cwd, ref STARTUPINFO si, out PROCESS_INFORMATION pi);
    [DllImport("kernel32.dll")] public static extern uint WaitForSingleObject(IntPtr handle, uint ms);
    [DllImport("kernel32.dll")] public static extern bool GetExitCodeProcess(IntPtr process, out uint code);
    [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr handle);

    public static int Run(string command, int waitMs, out uint exitCode) {
        exitCode = 1;
        string name = "PraxinoHidden_" + Guid.NewGuid().ToString("N");
        IntPtr desktop = CreateDesktop(name, IntPtr.Zero, IntPtr.Zero, 0, 0x000F01FF, IntPtr.Zero);
        if (desktop == IntPtr.Zero) return -1;
        STARTUPINFO si = new STARTUPINFO();
        si.cb = Marshal.SizeOf(si);
        si.lpDesktop = name;
        PROCESS_INFORMATION pi;
        bool started = CreateProcess(null, "cmd.exe /c \"" + command + "\"", IntPtr.Zero, IntPtr.Zero,
            false, 0, IntPtr.Zero, null, ref si, out pi);
        if (!started) { CloseDesktop(desktop); return -2; }
        uint wait = WaitForSingleObject(pi.hProcess, (uint)waitMs);
        GetExitCodeProcess(pi.hProcess, out exitCode);
        CloseHandle(pi.hThread);
        CloseHandle(pi.hProcess);
        CloseDesktop(desktop);
        return wait == 258 ? -3 : 0;
    }
}
"@

$exit = [uint32]0
$launcher = [PraxinoHiddenIntegration]::Run($script, $TimeoutSeconds * 1000, [ref]$exit)
if (Test-Path $log) { Get-Content -LiteralPath $log | Select-Object -Last 40 }
Remove-Item -LiteralPath $script -ErrorAction SilentlyContinue
Write-Output "hidden_integration launcher=$launcher exit=$exit log=$log"
if ($launcher -ne 0 -or $exit -ne 0) { exit 1 }
