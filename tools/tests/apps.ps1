# Exercises workspace test defaults and worker propagation without running swc.
param([string] $Tool = (Join-Path $PSScriptRoot '..\_tool.bat'))

$ErrorActionPreference = 'Stop'
$scratchBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$scratch = Join-Path $scratchBase ('swag apps ' + [Guid]::NewGuid().ToString('N'))
$previousLog = $env:SWC_RUNNER_TEST_LOG
$previousRuntime = $env:SWAG_RUNTIME_THREADS

function Invoke-Apps([string[]] $Arguments, [string] $Workers, [string] $Runtime) {
    & (Join-Path $scratch 'tools\_tool.bat') apps @Arguments | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Application runner failed for '$Arguments'." }
    $call = Get-Content -LiteralPath $env:SWC_RUNNER_TEST_LOG
    if ($call[0] -ne $Runtime) { throw "Runtime workers: expected '$Runtime', received '$($call[0])'." }
    $workerArguments = @($call | Where-Object { $_.StartsWith('--run-arg=--compiler-workers=') })
    if ($Workers) {
        if ($workerArguments.Count -ne 1 -or $workerArguments[0] -ne "--run-arg=--compiler-workers=$Workers") {
            throw "Child workers: expected '$Workers', received '$workerArguments'."
        }
        if (!($call | Where-Object { $_ -eq "--run-arg=--compiler=$scratch\bin\swc.dm.exe" })) {
            throw 'Child compiler does not match the selected checkout compiler.'
        }
    } elseif ($workerArguments.Count) { throw 'Worker arguments reached an unrelated application command.' }
}

try {
    $null = New-Item -ItemType Directory -Path (Join-Path $scratch 'tools'), (Join-Path $scratch 'bin') -Force
    Copy-Item -LiteralPath $Tool -Destination (Join-Path $scratch 'tools\_tool.bat')
    Copy-Item -LiteralPath (Join-Path (Split-Path -Parent $Tool) 'tool.py') -Destination (Join-Path $scratch 'tools\tool.py')
    $env:SWC_RUNNER_TEST_LOG = Join-Path $scratch 'call.txt'
    $env:SWAG_RUNTIME_THREADS = $null
    Add-Type -OutputAssembly (Join-Path $scratch 'bin\swc.dm.exe') -OutputType ConsoleApplication -TypeDefinition @'
using System;
using System.IO;
public static class ApplicationCompilerProbe
{
    public static int Main(string[] args)
    {
        File.WriteAllLines(Environment.GetEnvironmentVariable("SWC_RUNNER_TEST_LOG"),
            new[] { Environment.GetEnvironmentVariable("SWAG_RUNTIME_THREADS") ?? "unset" });
        File.AppendAllLines(Environment.GetEnvironmentVariable("SWC_RUNNER_TEST_LOG"), args);
        return 0;
    }
}
'@
    $prefix = @('dm', 'test')
    Invoke-Apps $prefix '3' '3'
    foreach ($workers in @('1', '2', '0', '8')) {
        $expected = if ($workers -eq '1' -or $workers -eq '2') { $workers } else { '3' }
        Invoke-Apps ($prefix + @('--num-cores', $workers)) $expected $expected
    }
    Invoke-Apps ($prefix + @('--num-cores=1')) '1' '1'
    Invoke-Apps ($prefix + @('-j', '2', '--num-cores', '1')) '1' '1'
    Invoke-Apps @('dm', 'test', 'swagscope', '--num-cores', '1') '' '1'
    $env:SWAG_RUNTIME_THREADS = '2'
    Invoke-Apps @('dm', 'test', '--num-cores', '1') '1' '2'
    Write-Output 'Application runner: 9 regression cases passed.'

    $runner = Join-Path $scratch 'tools\_tool.bat'
    $env:SWAG_RUNTIME_THREADS = $null
    & $runner std dm test '"gui"' --test-file headless.render.swg | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Quoted standard module was rejected.' }
    $call = @(Get-Content -LiteralPath $env:SWC_RUNNER_TEST_LOG)
    if ($call[0] -ne '3' -or $call[$call.IndexOf('--workspace-module') + 1] -ne 'gui' -or
        $call -notcontains '--no-test-jit' -or $call[$call.IndexOf('--artifact-kind') + 1] -ne 'executable' -or
        $call[$call.IndexOf('--test-file') + 1] -ne 'headless.render.swg') {
        throw 'Standard tests lost their native defaults, module, filter, or runtime ceiling.'
    }

    $env:SWAG_RUNTIME_THREADS = '2'
    & $runner std dm test pixel --test-jit --no-test-native --num-cores 1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Explicit JIT test mode was rejected.' }
    $call = @(Get-Content -LiteralPath $env:SWC_RUNNER_TEST_LOG)
    if ($call[0] -ne '2' -or $call.IndexOf('--test-jit') -le $call.IndexOf('--no-test-jit') -or
        $call -notcontains '--no-test-native') {
        throw 'Explicit test mode or runtime ceiling no longer overrides the defaults.'
    }

    $env:SWAG_RUNTIME_THREADS = $null
    & $runner std dm build pixel | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Standard library build was rejected.' }
    $call = @(Get-Content -LiteralPath $env:SWC_RUNNER_TEST_LOG)
    if ($call[0] -ne 'unset' -or $call -contains '--artifact-kind' -or $call -contains '--no-test-jit') {
        throw 'Test defaults reached an ordinary library build.'
    }
    Write-Output 'Standard runner: 3 regression cases passed.'
}
finally {
    $env:SWC_RUNNER_TEST_LOG = $previousLog
    $env:SWAG_RUNTIME_THREADS = $previousRuntime
    $resolved = [IO.Path]::GetFullPath($scratch)
    if ((Split-Path -Parent $resolved) -ne $scratchBase -or !(Split-Path -Leaf $resolved).StartsWith('swag apps ')) {
        throw 'Refusing to remove a directory outside the application-test scratch folder.'
    }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
