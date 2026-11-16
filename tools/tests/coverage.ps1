# Check suite selection, failure propagation, and environment isolation without compiling.
$ErrorActionPreference = 'Stop'
$scratchBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$scratch = Join-Path $scratchBase ('swag coverage ' + [Guid]::NewGuid().ToString('N'))
$oldLog = $env:SWAG_COVERAGE_LOG
$oldFailure = $env:SWAG_COVERAGE_FAILURE
$oldRenderer = $env:SWAG_TEST_RENDERER
try {
    $null = New-Item -ItemType Directory -Path $scratch
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\coverage.ps1') -Destination $scratch
    foreach ($tool in @('std', 'apps', 'goldens')) {
        @"
@echo off
echo $tool^|%SWAG_TEST_RENDERER%^|%* >>"%SWAG_COVERAGE_LOG%"
if "%SWAG_COVERAGE_FAILURE%"=="$tool" if defined SWAG_COVERAGE_SOURCE echo source:  %SWAG_COVERAGE_SOURCE%
if "%SWAG_COVERAGE_FAILURE%"=="$tool" exit /b 7
exit /b 0
"@ | Set-Content -LiteralPath (Join-Path $scratch "$tool.bat")
    }
    $env:SWAG_COVERAGE_LOG = Join-Path $scratch 'calls.txt'
    $env:SWAG_COVERAGE_FAILURE = $null
    $env:SWAG_TEST_RENDERER = 'original'
    foreach ($suite in @('fast', 'gpu', 'full', 'goldens', 'parity')) {
        Set-Content -LiteralPath $env:SWAG_COVERAGE_LOG -Value ''
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scratch 'coverage.ps1') -DevMode -Suite $suite | Out-Null
        if ($LASTEXITCODE) { throw "Suite $suite failed." }
        $calls = @(Get-Content -LiteralPath $env:SWAG_COVERAGE_LOG | Where-Object { $_ })
        $expectedCount = if ($suite -in @('goldens', 'parity')) { 1 } else { 2 }
        if ($calls.Count -ne $expectedCount) { throw "Suite $suite dispatched $($calls.Count) commands." }
        $renderer = 'gpu'
        foreach ($call in $calls) {
            if (!$call.Contains("|$renderer|dm test") -or !$call.Contains('--num-cores 3')) { throw "Wrong environment or compiler: $call" }
            if (($suite -in @('fast', 'gpu')) -ne $call.Contains('--test-tag !golden')) { throw "Wrong fast filter: $call" }
        }
        if ($suite -eq 'parity' -and !$calls[0].Contains('pixel --test-tag integration.renderer.opengl')) { throw 'Parity selection changed.' }
        if ($suite -eq 'goldens' -and !$calls[0].StartsWith('goldens|')) { throw 'Golden campaign was narrowed.' }
    }
    Set-Content -LiteralPath $env:SWAG_COVERAGE_LOG -Value ''
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scratch 'coverage.ps1') -DevMode -Renderer cpu | Out-Null
    if ($LASTEXITCODE) { throw 'The explicit CPU campaign failed.' }
    $calls = @(Get-Content -LiteralPath $env:SWAG_COVERAGE_LOG | Where-Object { $_ })
    if ($calls.Count -ne 2 -or @($calls | Where-Object { !$_.StartsWith('std|cpu|') -and !$_.StartsWith('apps|cpu|') }).Count) {
        throw 'The explicit CPU campaign did not select CPU hosts for every workspace.'
    }
    $env:SWAG_COVERAGE_FAILURE = 'std'
    Set-Content -LiteralPath $env:SWAG_COVERAGE_LOG -Value ''
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scratch 'coverage.ps1') -Suite fast | Out-Null
    if ($LASTEXITCODE -ne 1) { throw 'A failed workspace was hidden.' }
    if (!(Get-Content -LiteralPath $env:SWAG_COVERAGE_LOG | Where-Object { $_.StartsWith('apps|') })) { throw 'A failure prevented the remaining workspace from running.' }
    if ($env:SWAG_TEST_RENDERER -ne 'original') { throw 'Renderer selection escaped the launcher.' }

    # A golden the GPU run reports is rendered again on CPU, and only its own test source.
    $env:SWAG_COVERAGE_FAILURE = 'goldens'
    $env:SWAG_COVERAGE_SOURCE = 'C:\checkout\bin\std\modules\gui\src\tests\cases\golden\menu.swg:12:5'
    Set-Content -LiteralPath $env:SWAG_COVERAGE_LOG -Value ''
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scratch 'coverage.ps1') -DevMode -Suite goldens | Out-Null
    if ($LASTEXITCODE -ne 1) { throw 'A failed golden campaign was hidden.' }
    $calls = @(Get-Content -LiteralPath $env:SWAG_COVERAGE_LOG | Where-Object { $_ })
    if ($calls.Count -ne 2 -or !$calls[0].StartsWith('goldens|gpu|')) { throw "The golden campaign did not confirm its failure: $calls" }
    if (!$calls[1].StartsWith('std|cpu|dm test gui --test-tag golden --test-file golden\menu.swg ')) { throw "Wrong CPU confirmation: $($calls[1])" }
    Set-Content -LiteralPath $env:SWAG_COVERAGE_LOG -Value ''
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scratch 'coverage.ps1') -DevMode -Suite goldens -Renderer cpu | Out-Null
    if (@(Get-Content -LiteralPath $env:SWAG_COVERAGE_LOG | Where-Object { $_ }).Count -ne 1) { throw 'A CPU golden campaign confirmed itself.' }
    $env:SWAG_COVERAGE_SOURCE = $null
    $env:SWAG_COVERAGE_FAILURE = 'apps'
    Set-Content -LiteralPath $env:SWAG_COVERAGE_LOG -Value ''
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scratch 'coverage.ps1') -Suite goldens -Workspace apps -Module swagscope -TestFile explorer.swg | Out-Null
    $calls = @(Get-Content -LiteralPath $env:SWAG_COVERAGE_LOG | Where-Object { $_ })
    if ($calls.Count -ne 1 -or !$calls[0].StartsWith('apps|gpu|test swagscope --test-tag golden --test-file explorer.swg ')) { throw "Wrong focused golden campaign: $calls" }
    Write-Output 'Coverage runner: suite selection, golden confirmation, failure propagation and environment isolation passed.'
} finally {
    $env:SWAG_COVERAGE_LOG = $oldLog
    $env:SWAG_COVERAGE_FAILURE = $oldFailure
    $env:SWAG_COVERAGE_SOURCE = $null
    $env:SWAG_TEST_RENDERER = $oldRenderer
    $resolved = [IO.Path]::GetFullPath($scratch)
    if (!$resolved.StartsWith($scratchBase, [StringComparison]::OrdinalIgnoreCase)) { throw 'Scratch path escaped the temporary directory.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
