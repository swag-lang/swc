<#
.SYNOPSIS
Runs native GUI scenarios on a private Windows desktop without switching the user's desktop.
.EXAMPLE
powershell -NoProfile -ExecutionPolicy Bypass -File tools/test-desktop.ps1 -Module swagscope
#>
[CmdletBinding()]
param(
    [ValidateSet('apps', 'std')][string] $Workspace = 'apps',
    [ValidateSet('test', 'smoke')][string] $Action = 'test',
    [Parameter(Mandatory)][ValidatePattern('^[a-z0-9]+$')][string] $Module,
    [switch] $DevMode,
    [ValidateSet('devmode', 'release')][string] $Configuration = 'devmode',
    [ValidatePattern('^[a-zA-Z0-9_.-]*$')][string] $TestFile = '',
    [ValidatePattern('^integration\.[a-z.]+$')][string] $TestTag = 'integration.application.smoke',
    [ValidateRange(1, 300)][int] $RunTimeout = 60
)
$ErrorActionPreference = 'Stop'
$repository = Split-Path $PSScriptRoot -Parent
if ($Action -eq 'test') {
    $testRoot = Join-Path $repository "bin/$Workspace/modules/$Module/src"
    $tagPattern = 'Swag\.TestTag\("' + [regex]::Escape($TestTag) + '"\)'
    $selected = @(Get-ChildItem -LiteralPath $testRoot -Recurse -Filter '*.test.swg' |
        Where-Object { (!$TestFile -or $_.FullName.Contains($TestFile)) -and
            (Select-String -LiteralPath $_.FullName -Pattern $tagPattern -Quiet) })
    if ($selected.Count -eq 0) { throw "No test file selects tag '$TestTag' and file filter '$TestFile' in $Module" }
} elseif ($Workspace -ne 'apps' -or $TestFile -or $PSBoundParameters.ContainsKey('TestTag')) {
    throw 'Startup smoke accepts an application and no test filters'
}
$runDirectory = Join-Path ([IO.Path]::GetTempPath()) ('swag-desktop-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runDirectory | Out-Null
$requestPath = Join-Path $runDirectory 'request.xml'
$runnerPath = Join-Path $runDirectory 'run.ps1'
$logPath = Join-Path $runDirectory 'run.log'
$arguments = @()
if ($DevMode) { $arguments += 'dm' }
$arguments += @($Action, $Module, '-bc', $Configuration, '--run-timeout', $RunTimeout.ToString())
if ($Action -eq 'test') { $arguments += @('--test-tag', $TestTag) }
if ($TestFile) { $arguments += @('--test-file', $TestFile) }
@{ Tool = Join-Path $PSScriptRoot ($Workspace + '.bat'); Arguments = $arguments; Log = $logPath } |
    Export-Clixml -LiteralPath $requestPath
@'
param([string] $Request)
$ErrorActionPreference = 'Stop'
$requestData = Import-Clixml -LiteralPath $Request
try {
    # Windows PowerShell wraps native stderr as error records; the compiler's exit code owns
    # failure, including when ordinary progress is written to stderr.
    $ErrorActionPreference = 'Continue'
    $toolArguments = @($requestData.Arguments)
    [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
    & $requestData.Tool @toolArguments 2>&1 | ForEach-Object {
        if ($_ -is [Management.Automation.ErrorRecord]) { $_.Exception.Message } else { $_.ToString() }
    } |
        Out-File -LiteralPath $requestData.Log -Encoding utf8
    exit $LASTEXITCODE
} catch {
    $_ | Out-String | Add-Content -LiteralPath $requestData.Log
    exit 1
}
'@ | Set-Content -LiteralPath $runnerPath -Encoding UTF8

# A job owns every descendant, including thumbnail workers. Closing it after a timeout or an
# interrupted launcher cannot leave test windows or compilers running on the private desktop.
Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
public static class SwagTestDesktop {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct StartupInfo {
        public int cb; public string reserved, desktop, title;
        public int x, y, width, height, charsX, charsY, fill, flags;
        public short show, reservedSize; public IntPtr reservedBytes, input, output, error;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct ProcessInfo { public IntPtr process, thread; public uint processId, threadId; }
    [StructLayout(LayoutKind.Sequential)]
    struct BasicLimits {
        public long processTime, jobTime; public uint flags;
        public UIntPtr minWorkingSet, maxWorkingSet; public uint activeProcesses;
        public UIntPtr affinity; public uint priority, scheduling;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct IoCounters { public ulong readOps, writeOps, otherOps, readBytes, writeBytes, otherBytes; }
    [StructLayout(LayoutKind.Sequential)]
    struct ExtendedLimits {
        public BasicLimits basic; public IoCounters io;
        public UIntPtr processMemory, jobMemory, peakProcessMemory, peakJobMemory;
    }
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern IntPtr CreateDesktop(string name, IntPtr device, IntPtr mode, uint flags, uint access, IntPtr security);
    [DllImport("user32.dll")] static extern bool CloseDesktop(IntPtr desktop);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool CreateProcess(string executable, StringBuilder command, IntPtr processSecurity,
        IntPtr threadSecurity, bool inherit, uint flags, IntPtr environment, string directory,
        ref StartupInfo startup, out ProcessInfo process);
    [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr CreateJobObject(IntPtr security, string name);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool SetInformationJobObject(IntPtr job, int kind, ref ExtendedLimits limits, int size);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
    [DllImport("kernel32.dll", SetLastError = true)] static extern uint ResumeThread(IntPtr thread);
    [DllImport("kernel32.dll", SetLastError = true)] static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool GetExitCodeProcess(IntPtr process, out uint code);
    [DllImport("kernel32.dll")] static extern bool TerminateProcess(IntPtr process, uint code);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    static void Check(bool result) { if (!result) throw new Win32Exception(Marshal.GetLastWin32Error()); }
    public static int Run(string executable, string command, string directory) {
        string name = "SwagTests-" + Guid.NewGuid().ToString("N");
        IntPtr desktop = CreateDesktop(name, IntPtr.Zero, IntPtr.Zero, 0, 0x10000000, IntPtr.Zero);
        Check(desktop != IntPtr.Zero);
        IntPtr job = IntPtr.Zero;
        ProcessInfo process = new ProcessInfo();
        try {
            job = CreateJobObject(IntPtr.Zero, null); Check(job != IntPtr.Zero);
            var limits = new ExtendedLimits(); limits.basic.flags = 0x2000; // KILL_ON_JOB_CLOSE
            Check(SetInformationJobObject(job, 9, ref limits, Marshal.SizeOf(limits)));
            var startup = new StartupInfo(); startup.cb = Marshal.SizeOf(startup); startup.desktop = name;
            Check(CreateProcess(executable, new StringBuilder(command), IntPtr.Zero, IntPtr.Zero, false,
                0x08000004, IntPtr.Zero, directory, ref startup, out process)); // NO_WINDOW | SUSPENDED
            if (!AssignProcessToJobObject(job, process.process)) {
                int error = Marshal.GetLastWin32Error(); TerminateProcess(process.process, 1);
                throw new Win32Exception(error);
            }
            Check(ResumeThread(process.thread) != UInt32.MaxValue);
            // Compilation has its own budget; each executable also has --run-timeout.
            uint wait = WaitForSingleObject(process.process, 900000);
            if (wait == 258) throw new TimeoutException("Desktop test command exceeded 15 minutes");
            Check(wait == 0);
            uint code; Check(GetExitCodeProcess(process.process, out code));
            return unchecked((int)code);
        } finally {
            if (job != IntPtr.Zero) CloseHandle(job);
            if (process.thread != IntPtr.Zero) CloseHandle(process.thread);
            if (process.process != IntPtr.Zero) CloseHandle(process.process);
            CloseDesktop(desktop);
        }
    }
}
'@
$powershell = (Get-Command powershell.exe).Source
$command = '"' + $powershell + '" -NoProfile -ExecutionPolicy Bypass -File "' + $runnerPath + '" -Request "' + $requestPath + '"'
Write-Host "Native scenarios run on a private desktop. Log: $logPath"
try {
    $result = [SwagTestDesktop]::Run($powershell, $command, $repository)
    if (Test-Path -LiteralPath $logPath) { Get-Content -LiteralPath $logPath }
    exit $result
} finally {
    Write-Host "Artifacts: $runDirectory"
}
