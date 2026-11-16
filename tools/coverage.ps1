<#
.SYNOPSIS
Run fast functional, stress, golden, full, or renderer parity coverage for standard modules and applications.
.DESCRIPTION
GPU hosts are the default for functional suites. Use -Renderer cpu explicitly for CI or cloud hosts
without a usable OpenGL device. Fast excludes golden and stress tests. Stress selects scale-boundary
tests. Full runs every ordinary and stress test on the selected renderer, then the goldens.

Goldens always renders on CPU: a PNG golden is a CPU reference, compared exactly and identical on
every machine. Parity is the campaign that checks a GPU against the CPU: its tests draw one scene
with both renderers and compare them with a tolerance that follows local contrast. Both campaigns
can be focused with -Workspace, -Module and -TestFile.

-Sweep adds a search to the parity campaign: every golden scene is drawn on the GPU and compared
with its CPU reference under the parity tolerance. Nothing is recorded. A scene the sweep reports
shows a divergence to reduce to a dedicated parity test and fix; the sweep itself is not that test.
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
tools\coverage.bat -Suite parity -Sweep -Workspace apps -Module swagcapture
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
    [switch] $Sweep,
    [ValidateSet('devmode', 'release')]
    [string] $Configuration = 'devmode',
    [ValidateRange(1, 3)]
    [int] $Workers = 3
)

$ErrorActionPreference = 'Stop'
$ParityTag = 'integration.renderer.opengl'
if ($Module -and $Workspace -eq 'all') { throw '-Module requires -Workspace std or apps.' }
if ($Suite -in @('gpu', 'parity') -and $Renderer -eq 'cpu') { throw "-Suite $Suite cannot be combined with -Renderer cpu." }
if ($Sweep -and $Suite -ne 'parity') { throw '-Sweep belongs to -Suite parity.' }
$previousRenderer = $env:SWAG_TEST_RENDERER
$previousSweep = $env:SWAG_TEST_PARITY_SWEEP
$result = 0
$binRoot = Join-Path $PSScriptRoot '..\bin'

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

# Runs the tests carrying `Tag` module by module. A workspace run stops at its first failing
# module, and rejects a tag none of a module's tests carries, so each owner is its own run.
function Invoke-TaggedCampaign([string] $Tag) {
    $workspaces = if ($Workspace -eq 'all') { @('std', 'apps') } else { @($Workspace) }
    foreach ($item in $workspaces) {
        $modules = @($Module)
        if (!$Module) {
            $modulesRoot = Join-Path $binRoot "$item\modules"
            if (!(Test-Path -LiteralPath $modulesRoot)) { continue }
            $pattern = 'TestTag\("' + [regex]::Escape($Tag) + '"\)'
            $modules = @(Get-ChildItem -LiteralPath $modulesRoot -Directory | Where-Object {
                    $cases = Join-Path $_.FullName 'src\tests\cases'
                    (Test-Path -LiteralPath $cases) -and
                    (Get-ChildItem -LiteralPath $cases -Recurse -File -Filter '*.swg' | Select-String -Pattern $pattern -List)
                } | ForEach-Object { $_.Name })
        }
        foreach ($name in $modules) {
            $options = @($name, '--test-tag', $Tag)
            foreach ($file in $TestFile) { $options += @('--test-file', $file) }
            Invoke-Coverage $item $options
        }
    }
}

try {
    # GPU is the default; CPU is an explicit opt-in for environments without a graphics device.
    # HeadlessHost reports GPU initialization failure instead of silently changing the backend.
    $env:SWAG_TEST_RENDERER = if ($Suite -in @('gpu', 'parity')) { 'gpu' } elseif ($Suite -eq 'goldens') { 'cpu' } else { $Renderer }
    Write-Host "[coverage] suite=$Suite renderer=$env:SWAG_TEST_RENDERER"
    if ($Suite -eq 'parity') {
        Invoke-TaggedCampaign $ParityTag
        if ($Sweep) {
            $env:SWAG_TEST_PARITY_SWEEP = '1'
            Write-Host '[coverage] parity sweep: golden scenes on the GPU against their CPU references'
            Invoke-TaggedCampaign 'golden'
        }
    } elseif ($Suite -eq 'goldens') {
        if ($Workspace -eq 'all' -and !$TestFile) { Invoke-Coverage 'goldens' @() } else { Invoke-TaggedCampaign 'golden' }
    } else {
        $options = @()
        if ($Module) { $options += $Module }
        if ($Suite -in @('fast', 'gpu')) { $options += @('--test-tag', '!golden', '--test-tag', '!stress') }
        if ($Suite -eq 'full') { $options += @('--test-tag', '!golden') }
        if ($Suite -eq 'stress') { $options += @('--test-tag', 'stress') }
        foreach ($file in $TestFile) { $options += @('--test-file', $file) }
        $workspaces = if ($Workspace -eq 'all') { @('std', 'apps') } else { @($Workspace) }
        foreach ($item in $workspaces) { Invoke-Coverage $item $options }

        # The goldens of a full pass are their own runs, because they render on CPU whatever
        # renderer the rest of the pass selected.
        if ($Suite -eq 'full') {
            $env:SWAG_TEST_RENDERER = 'cpu'
            if ($Workspace -eq 'all' -and !$TestFile) { Invoke-Coverage 'goldens' @() } else { Invoke-TaggedCampaign 'golden' }
        }
    }
} finally {
    $env:SWAG_TEST_RENDERER = $previousRenderer
    $env:SWAG_TEST_PARITY_SWEEP = $previousSweep
}
exit $result
