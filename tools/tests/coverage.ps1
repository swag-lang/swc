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
    Write-Output 'Coverage runner: suite selection, failure propagation and environment isolation passed.'
} finally {
    $env:SWAG_COVERAGE_LOG = $oldLog
    $env:SWAG_COVERAGE_FAILURE = $oldFailure
    $env:SWAG_TEST_RENDERER = $oldRenderer
    $resolved = [IO.Path]::GetFullPath($scratch)
    if (!$resolved.StartsWith($scratchBase, [StringComparison]::OrdinalIgnoreCase)) { throw 'Scratch path escaped the temporary directory.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
