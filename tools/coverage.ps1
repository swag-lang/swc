<#
.SYNOPSIS
Run fast functional, stress, golden, full, or GPU parity coverage for standard modules and applications.
.DESCRIPTION
GPU hosts are the default for every suite. Use -Renderer cpu explicitly for CI or cloud hosts
without a usable OpenGL device. Fast excludes golden and stress tests. Stress selects scale-boundary
tests. Full includes all ordinary tests, stress and goldens. Goldens and parity select complete
visual and renderer-integration campaigns.
.EXAMPLE
tools\coverage.bat -DevMode -Workspace apps -Module swagcapture
.EXAMPLE
tools\coverage.bat -DevMode -Suite stress -Workspace apps -Module swagscope
.EXAMPLE
tools\coverage.bat -DevMode -Suite parity
.EXAMPLE
tools\coverage.bat -DevMode -Renderer cpu
#>
[CmdletBinding()]
param(
[ValidateSet('fast', 'gpu', 'full', 'stress', 'goldens', 'parity')]
    [string] $Suite = 'fast',
    [ValidateSet('all', 'std', 'apps')]
    [string] $Workspace = 'all',
    [string] $Module,
    [string[]] $TestFile,
    [ValidateSet('cpu', 'gpu')]
    [string] $Renderer = 'gpu',
    [switch] $DevMode,
    [ValidateSet('devmode', 'release')]
    [string] $Configuration = 'devmode',
    [ValidateRange(1, 3)]
    [int] $Workers = 3
)

$ErrorActionPreference = 'Stop'
if ($Module -and $Workspace -eq 'all') { throw '-Module requires -Workspace std or apps.' }
if ($Suite -in @('goldens', 'parity') -and ($Module -or $TestFile -or $Workspace -ne 'all')) {
    throw 'Goldens and parity are complete campaigns; use std.bat or apps.bat for a focused test.'
}
$previousRenderer = $env:SWAG_TEST_RENDERER
$result = 0

function Invoke-Coverage([string] $Tool, [string[]] $Options) {
    $arguments = @()
    if ($DevMode) { $arguments += 'dm' }
    $arguments += 'test'
    $arguments += $Options
    $arguments += @('-bc', $Configuration, '--num-cores', "$Workers")
    $watch = [Diagnostics.Stopwatch]::StartNew()
    & (Join-Path $PSScriptRoot "$Tool.bat") @arguments
    $code = $LASTEXITCODE
    Write-Host ("[coverage] {0}: {1:N2}s, exit {2}" -f $Tool, $watch.Elapsed.TotalSeconds, $code)
    if ($code -ne 0) { $script:result = 1 }
}

try {
    # GPU is the default; CPU is an explicit opt-in for environments without a graphics device.
    # HeadlessHost reports GPU initialization failure instead of silently changing the backend.
    if ($Suite -eq 'gpu' -and $Renderer -eq 'cpu') { throw '-Suite gpu cannot be combined with -Renderer cpu.' }
    $env:SWAG_TEST_RENDERER = if ($Suite -eq 'gpu') { 'gpu' } else { $Renderer }
    Write-Host "[coverage] suite=$Suite renderer=$env:SWAG_TEST_RENDERER"
    if ($Suite -eq 'goldens') {
        Invoke-Coverage 'goldens' @()
    } elseif ($Suite -eq 'parity') {
        Invoke-Coverage 'std' @('pixel', '--test-tag', 'integration.renderer.opengl')
    } else {
        $options = @()
        if ($Module) { $options += $Module }
        if ($Suite -in @('fast', 'gpu')) { $options += @('--test-tag', '!golden', '--test-tag', '!stress') }
        if ($Suite -eq 'stress') { $options += @('--test-tag', 'stress') }
        foreach ($file in $TestFile) { $options += @('--test-file', $file) }
        $workspaces = if ($Workspace -eq 'all') { @('std', 'apps') } else { @($Workspace) }
        foreach ($item in $workspaces) { Invoke-Coverage $item $options }
    }
} finally {
    $env:SWAG_TEST_RENDERER = $previousRenderer
}
exit $result
