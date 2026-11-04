# Exercises suite routing, failure propagation, and dynamic fixture preparation without swc.
param([string] $Tool = (Join-Path $PSScriptRoot '..\unittests.bat'))

$ErrorActionPreference = 'Stop'
$scratchBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$scratch = Join-Path $scratchBase ('swag unittest ' + [Guid]::NewGuid().ToString('N'))
$previousLog = $env:SWC_RUNNER_TEST_LOG
$previousFailure = $env:SWC_RUNNER_TEST_FAILURE

function Invoke-Suite([string[]] $Arguments, [int] $ExpectedExit, [string] $Failure = '') {
    $env:SWC_RUNNER_TEST_FAILURE = $Failure
    Set-Content -LiteralPath $env:SWC_RUNNER_TEST_LOG -Value '' -NoNewline
    & (Join-Path $scratch 'tools\unittests.bat') @Arguments | Out-Null
    if ($LASTEXITCODE -ne $ExpectedExit) {
        throw "Expected exit $ExpectedExit for '$Arguments', received $LASTEXITCODE"
    }
    $script:calls = @(Get-Content -LiteralPath $env:SWC_RUNNER_TEST_LOG)
}

function Assert-Call([int] $Index, [string] $Text) {
    if ($Index -ge $script:calls.Count -or !$script:calls[$Index].Contains($Text)) {
        throw "Call $Index does not contain '$Text': $($script:calls -join '; ')"
    }
}

try {
    $null = New-Item -ItemType Directory -Path (Join-Path $scratch 'tools'), (Join-Path $scratch 'bin') -Force
    Copy-Item -LiteralPath $Tool -Destination (Join-Path $scratch 'tools\unittests.bat')
    Copy-Item -LiteralPath (Join-Path (Split-Path -Parent $Tool) 'tool.py') -Destination (Join-Path $scratch 'tools\tool.py')
    $env:SWC_RUNNER_TEST_LOG = Join-Path $scratch 'calls.txt'
    $compilerSource = @'
using System;
using System.IO;
public static class CompilerProbe
{
    public static int Main(string[] args)
    {
        string call = String.Join("\t", args);
        File.AppendAllText(Environment.GetEnvironmentVariable("SWC_RUNNER_TEST_LOG"), call + Environment.NewLine);
        string failure = Environment.GetEnvironmentVariable("SWC_RUNNER_TEST_FAILURE");
        if (!String.IsNullOrEmpty(failure) && call.Contains(failure))
            return 7;
        if (args.Length != 0 && args[0] == "unittest")
            foreach (string arg in args)
                if (arg == "-bc" || arg.StartsWith("--build-cfg"))
                    return 13;
        if (call.Contains("import_core_without_using.swgs"))
            Console.WriteLine("SWAG_IMPORTED_CORE_WITHOUT_USING_RAN");
        return 0;
    }
}
'@
    Add-Type -TypeDefinition $compilerSource -OutputAssembly (Join-Path $scratch 'bin\swc.dm.exe') -OutputType ConsoleApplication
    Copy-Item -LiteralPath (Join-Path $scratch 'bin\swc.dm.exe') -Destination (Join-Path $scratch 'bin\swc.exe')

    foreach ($module in @('runtime_context_dynamic_consumer', 'runtime_context_dynamic_dll')) {
        $null = New-Item -ItemType Directory -Path (Join-Path $scratch "bin\unittests\workspace\modules\$module") -Force
    }

    foreach ($configuration in @(@('-bc', 'release'), @('--build-cfg', 'devmode'), @('--build-cfg=release'))) {
        Invoke-Suite (@('dm', 'cpp') + $configuration + @('--num-cores', '1')) 0
        Assert-Call 0 "unittest`t--dev-full"
        Assert-Call 0 "--num-cores`t1"
        if ($calls.Count -ne 1 -or $calls[0] -match '-bc|--build-cfg') {
            throw 'Program configuration reached the C++ test command.'
        }
    }
    Invoke-Suite @('dm', 'cpp') 7 'unittest'
    Invoke-Suite @('dm', '-bc', 'release') 7 'unittest'
    if ($calls.Count -ne 1) { throw 'The campaign continued after a C++ test failure.' }

    foreach ($suite in @('lexer', 'parser', 'sema')) {
        Invoke-Suite @('dm', $suite, '-bc', 'release') 7 "unittests\$suite"
        if ($calls.Count -ne 1) { throw "The $suite suite continued after its first failure." }
        Invoke-Suite @('dm', $suite, '-bc', 'release') 7 "errors\$suite"
        if ($calls.Count -ne 2) { throw "The $suite suite did not reach its error fixtures." }
    }

    foreach ($configuration in @('release', 'devmode')) {
        Invoke-Suite @('dm', 'workspace', '-bc', $configuration, '--num-cores', '1') 0
        Assert-Call 0 "build`t--workspace"
        Assert-Call 0 "--workspace-module`truntime_context_dynamic_dll"
        Assert-Call 0 "--build-cfg`t$configuration"
        Assert-Call 0 "--num-cores`t1"
        Assert-Call 1 "--workspace-module`truntime_context_dynamic_consumer"
        Assert-Call 1 "shared-library\$configuration\x86_64\runtime_context_dynamic_dll.dll"
        Assert-Call 3 "--num-cores`t1"
    }
    Invoke-Suite @('dm', 'workspace', '-bc', 'release') 7 "build`t--workspace"
    if ($calls.Count -ne 1) { throw 'Workspace tests continued after fixture preparation failed.' }
    Invoke-Suite @('dm', 'workspace', '-bc', 'release') 7 "test`t--workspace"
    if ($calls.Count -ne 2) { throw 'Workspace tests continued after the consumer failed.' }
    Write-Output 'Compiler suite runner: 15 regression cases passed.'
}
finally {
    $env:SWC_RUNNER_TEST_LOG = $previousLog
    $env:SWC_RUNNER_TEST_FAILURE = $previousFailure
    $resolved = [IO.Path]::GetFullPath($scratch)
    if ((Split-Path -Parent $resolved) -ne $scratchBase -or !(Split-Path -Leaf $resolved).StartsWith('swag unittest ')) {
        throw 'Refusing to remove a directory outside the suite-test scratch folder.'
    }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
