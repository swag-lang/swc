# Check suite selection and failure propagation without compiling.
$ErrorActionPreference = 'Stop'
$scratchBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$scratch = Join-Path $scratchBase ('swag coverage ' + [Guid]::NewGuid().ToString('N'))
$oldLog = $env:SWAG_COVERAGE_LOG
$oldFailure = $env:SWAG_COVERAGE_FAILURE

function Invoke-Launcher([string[]] $Options, [int] $ExpectedExit = 0) {
    Set-Content -LiteralPath $env:SWAG_COVERAGE_LOG -Value ''
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scratch 'tools\coverage.ps1') @Options | Out-Null
    if ($LASTEXITCODE -ne $ExpectedExit) { throw "coverage $Options exited $LASTEXITCODE, expected $ExpectedExit." }
    return ,@(Get-Content -LiteralPath $env:SWAG_COVERAGE_LOG | Where-Object { $_ })
}

function Assert-Calls([string[]] $Calls, [string[]] $Prefixes, [string] $What) {
    if ($Calls.Count -ne $Prefixes.Count) { throw "$What dispatched $($Calls.Count) commands: $Calls" }
    for ($index = 0; $index -lt $Prefixes.Count; $index++) {
        if (!$Calls[$index].StartsWith($Prefixes[$index])) { throw "$What ran '$($Calls[$index])', expected '$($Prefixes[$index])'." }
        if (!$Calls[$index].Contains('--num-cores 0')) { throw "$What lost automatic worker selection: $($Calls[$index])" }
    }
}

try {
    $tools = Join-Path $scratch 'tools'
    $null = New-Item -ItemType Directory -Path $tools
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\coverage.ps1') -Destination $tools
    foreach ($tool in @('std', 'apps', 'goldens')) {
        @"
@echo off
echo $tool^|%* >>"%SWAG_COVERAGE_LOG%"
if "%SWAG_COVERAGE_FAILURE%"=="$tool" exit /b 7
exit /b 0
"@ | Set-Content -LiteralPath (Join-Path $tools "$tool.bat")
    }

    # One module owns renderer parity tests, another owns goldens, a third owns neither.
    $fixtures = @{
        'std\modules\pixel\src\tests\cases\integration\parity.ogl.swg' = '#[Swag.TestTag("integration.renderer.opengl")]'
        'std\modules\core\src\tests\cases\functional\text.swg'         = '#test {}'
        'apps\modules\swagscope\src\tests\cases\golden\explorer.swg'   = '#[Swag.TestTag("golden")]'
    }
    foreach ($fixture in $fixtures.GetEnumerator()) {
        $path = Join-Path $scratch (Join-Path 'bin' $fixture.Key)
        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force
        Set-Content -LiteralPath $path -Value $fixture.Value -Encoding Ascii
    }

    $env:SWAG_COVERAGE_LOG = Join-Path $scratch 'calls.txt'
    $env:SWAG_COVERAGE_FAILURE = $null
    $calls = Invoke-Launcher @('-Suite', 'fast', '-Configuration', 'release')
    Assert-Calls $calls @('std|test --test-tag !golden --test-tag !stress', 'apps|test --test-tag !golden --test-tag !stress') 'The fast pass'

    # The full pass includes goldens in the same invocation as the rest of each workspace.
    Assert-Calls (Invoke-Launcher @('-Suite', 'full', '-Configuration', 'release')) @('std|test -bc release ', 'apps|test -bc release ') 'The full pass'
    Assert-Calls (Invoke-Launcher @('-Suite', 'full', '-Workspace', 'apps', '-Module', 'swagscope', '-Configuration', 'release')) @('apps|test swagscope -bc release ') 'The full module pass'
    Assert-Calls (Invoke-Launcher @('-Suite', 'goldens')) @('goldens|test') 'The golden campaign'
    Assert-Calls (Invoke-Launcher @('-Suite', 'goldens', '-Workspace', 'apps')) @('apps|test swagscope --test-tag golden ') 'The workspace golden campaign'
    Assert-Calls (Invoke-Launcher @('-Suite', 'goldens', '-Workspace', 'apps', '-Module', 'swagscope', '-TestFile', 'explorer.swg')) @('apps|test swagscope --test-tag golden --test-file explorer.swg ') 'The focused golden campaign'

    Assert-Calls (Invoke-Launcher @('-Suite', 'parity')) @('std|test pixel --test-tag integration.renderer.opengl ') 'The parity campaign'
    $null = Invoke-Launcher @('-Suite', 'gpu') 1
    $null = Invoke-Launcher @('-Renderer', 'gpu') 1
    $null = Invoke-Launcher @('-Suite', 'parity', '-Sweep') 1

    $env:SWAG_COVERAGE_FAILURE = 'std'
    $calls = Invoke-Launcher @('-Suite', 'fast') 1
    if (!($calls | Where-Object { $_.StartsWith('apps|') })) { throw 'A failure prevented the remaining workspace from running.' }
    Write-Output 'Coverage runner: suite selection, parity discovery and failure propagation passed.'
} finally {
    $env:SWAG_COVERAGE_LOG = $oldLog
    $env:SWAG_COVERAGE_FAILURE = $oldFailure
    $resolved = [IO.Path]::GetFullPath($scratch)
    if (!$resolved.StartsWith($scratchBase, [StringComparison]::OrdinalIgnoreCase)) { throw 'Scratch path escaped the temporary directory.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
