<#
.SYNOPSIS
Run fast functional, stress, golden, full, or GPU parity coverage for standard modules and applications.
.DESCRIPTION
GPU hosts are the default for every suite. Use -Renderer cpu explicitly for CI or cloud hosts
without a usable OpenGL device. Fast excludes golden and stress tests. Stress selects scale-boundary
tests. Full includes all ordinary tests, stress and goldens. Parity selects the renderer-integration
campaign.

Goldens compares what the selected renderer draws against the CPU references. On a GPU the
comparison tolerates what separates one graphics device from another, so the campaign is fast and
only isolates real differences. Each test that differs is then rendered again on CPU, which
settles it: a CPU render that differs too moved the reference and leaves a .actual.png to review
and accept; a CPU render that still matches leaves the GPU alone at fault, a renderer divergence
to fix. -Workspace, -Module and -TestFile focus the golden campaign like any other suite.
.EXAMPLE
tools\coverage.bat -Workspace apps -Module swagcapture
.EXAMPLE
tools\coverage.bat -Suite stress -Workspace apps -Module swagscope
.EXAMPLE
tools\coverage.bat -DevMode -Suite goldens
.EXAMPLE
tools\coverage.bat -DevMode -Suite goldens -Workspace std -Module gui -TestFile menu.swg
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
if ($Suite -eq 'parity' -and ($Module -or $TestFile -or $Workspace -ne 'all')) {
    throw 'Parity is a complete campaign; use std.bat for a focused test.'
}
$previousRenderer = $env:SWAG_TEST_RENDERER
$result = 0
$binRoot = Join-Path $PSScriptRoot '..\bin'

function Invoke-Coverage([string] $Tool, [string[]] $Options, [switch] $Capture) {
    $arguments = @()
    if ($DevMode) { $arguments += 'dm' }
    $arguments += 'test'
    $arguments += $Options
    $arguments += @('-bc', $Configuration, '--num-cores', "$Workers")
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $launcher = Join-Path $PSScriptRoot "$Tool.bat"
    $lines = @()
    if ($Capture) {
        # The golden campaign reads the failing test sources back from the output. Windows
        # PowerShell turns a redirected native error line into an error record, which must not
        # stop the launcher while both streams are merged.
        $ErrorActionPreference = 'Continue'
        & $launcher @arguments 2>&1 | ForEach-Object {
            $line = if ($_ -is [System.Management.Automation.ErrorRecord]) { "$($_.TargetObject)" } else { "$_" }
            Write-Host $line
            $lines += $line
        }
        $code = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
    } else {
        & $launcher @arguments
        $code = $LASTEXITCODE
    }
    Write-Host ("[coverage] {0}: {1:N2}s, exit {2}" -f $Tool, $watch.Elapsed.TotalSeconds, $code)
    if ($code -ne 0) { $script:result = 1 }
    return ,$lines
}

# Finds the golden test sources a run reported as failing, grouped by workspace and module.
# A failure reported from a shared helper does not name its test: that module maps to $null,
# which confirms all of its golden tests.
function Get-FailedGoldenSources([string[]] $Lines) {
    $groups = @{}
    $pattern = 'source:\s+.*\\bin\\(?<workspace>[^\\]+)\\modules\\(?<module>[^\\]+)\\src\\(?<file>[^:]+\.swg):\d+'
    foreach ($line in $Lines) {
        $match = [regex]::Match($line, $pattern)
        if (!$match.Success) { continue }
        $key = $match.Groups['workspace'].Value + '|' + $match.Groups['module'].Value
        if (!$groups.ContainsKey($key)) { $groups[$key] = New-Object System.Collections.Generic.List[string] }
        if ($null -eq $groups[$key]) { continue }
        $file = $match.Groups['file'].Value
        if (!$file.StartsWith('tests\cases\')) { $groups[$key] = $null; continue }
        $file = $file.Substring('tests\cases\'.Length)
        if (!$groups[$key].Contains($file)) { $groups[$key].Add($file) }
    }
    return $groups
}

# Says what each difference turned out to be, from the files the two passes left behind.
function Write-GoldenVerdict([datetime] $Since) {
    if (!(Test-Path -LiteralPath $binRoot)) { return }
    $pending = @(Get-ChildItem -LiteralPath $binRoot -Recurse -File -Filter '*.png' |
        Where-Object { ($_.Name -like '*.actual.png' -or $_.Name -like '*.actual.gpu.png') -and $_.LastWriteTime -ge $Since })
    $moved = @($pending | Where-Object { $_.Name -notlike '*.actual.gpu.png' })
    $movedGoldens = @($moved | ForEach-Object { $_.FullName -replace '\.actual\.png$', '.png' })
    $diverging = @($pending | Where-Object { $_.Name -like '*.actual.gpu.png' } |
        Where-Object { $movedGoldens -notcontains ($_.FullName -replace '\.actual\.gpu\.png$', '.png') })
    Write-Host "[coverage] goldens: $($moved.Count) reference(s) moved, $($diverging.Count) GPU divergence(s)"
    foreach ($file in $moved) { Write-Host "[coverage]   moved    : $($file.FullName)" }
    foreach ($file in $diverging) { Write-Host "[coverage]   diverges : $($file.FullName)" }
    if ($moved.Count) { Write-Host '[coverage] review each moved reference, then promote with tools\goldens.bat accept' }
    if ($diverging.Count) { Write-Host '[coverage] a divergence matches its reference on CPU: the renderers disagree, and the GPU is presumed right' }
}

try {
    # GPU is the default; CPU is an explicit opt-in for environments without a graphics device.
    # HeadlessHost reports GPU initialization failure instead of silently changing the backend.
    if ($Suite -eq 'gpu' -and $Renderer -eq 'cpu') { throw '-Suite gpu cannot be combined with -Renderer cpu.' }
    $env:SWAG_TEST_RENDERER = if ($Suite -eq 'gpu') { 'gpu' } else { $Renderer }
    Write-Host "[coverage] suite=$Suite renderer=$env:SWAG_TEST_RENDERER"
    if ($Suite -eq 'parity') {
        $null = Invoke-Coverage 'std' @('pixel', '--test-tag', 'integration.renderer.opengl')
    } elseif ($Suite -eq 'goldens') {
        $started = Get-Date
        $lines = @()
        if ($Workspace -eq 'all') {
            $lines += Invoke-Coverage 'goldens' @() -Capture
        } else {
            # A workspace run stops at its first failing module, so each golden owner is its own
            # run: one module that differs must not hide the modules after it.
            $modules = @($Module)
            if (!$Module) {
                $modules = @(Get-ChildItem -LiteralPath (Join-Path $binRoot "$Workspace\modules") -Directory |
                    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'src\tests\cases\golden') } |
                    ForEach-Object { $_.Name })
            }
            foreach ($name in $modules) {
                $options = @($name, '--test-tag', 'golden')
                foreach ($file in $TestFile) { $options += @('--test-file', $file) }
                $lines += Invoke-Coverage $Workspace $options -Capture
            }
        }

        # A GPU difference alone says nothing about which side moved. The CPU render of the
        # same tests does: only the failing sources are run again, so the confirmation stays short.
        $failed = Get-FailedGoldenSources $lines
        if ($env:SWAG_TEST_RENDERER -ne 'cpu' -and $failed.Count) {
            $env:SWAG_TEST_RENDERER = 'cpu'
            Write-Host "[coverage] confirming $($failed.Count) module(s) on the CPU renderer"
            foreach ($key in ($failed.Keys | Sort-Object)) {
                $workspace, $name = $key -split '\|'
                $options = @($name, '--test-tag', 'golden')
                foreach ($file in $failed[$key]) { $options += @('--test-file', $file) }
                $null = Invoke-Coverage $workspace $options -Capture
            }
        }

        if ($result) { Write-GoldenVerdict $started }
    } else {
        $options = @()
        if ($Module) { $options += $Module }
        if ($Suite -in @('fast', 'gpu')) { $options += @('--test-tag', '!golden', '--test-tag', '!stress') }
        if ($Suite -eq 'stress') { $options += @('--test-tag', 'stress') }
        foreach ($file in $TestFile) { $options += @('--test-file', $file) }
        $workspaces = if ($Workspace -eq 'all') { @('std', 'apps') } else { @($Workspace) }
        foreach ($item in $workspaces) { $null = Invoke-Coverage $item $options }
    }
} finally {
    $env:SWAG_TEST_RENDERER = $previousRenderer
}
exit $result
