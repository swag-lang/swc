<#
.SYNOPSIS
Run functional, golden, or renderer parity coverage for standard modules and applications.
.DESCRIPTION
Functional coverage includes stress tests and excludes goldens. The fast alias selects functional
coverage. The legacy full suite adds goldens in Release. The -DevMode switch selects the DevMode
compiler executable. -Configuration selects the program configuration independently.

Goldens uses CPU pixels for its references. Parity checks a GPU against the CPU: its tests draw one scene
with both renderers and compare them with a tolerance that follows local contrast. Both campaigns
can be focused with -Workspace, -Module and -TestFile.

.EXAMPLE
tools\coverage.bat -Workspace apps -Module swagcapture
.EXAMPLE
tools\coverage.bat -Suite functional -Workspace apps -Module swagscope -TestFile largefile.swg
.EXAMPLE
tools\coverage.bat -Suite goldens -Configuration release
.EXAMPLE
tools\coverage.bat -Suite goldens -Configuration release -Workspace std -Module gui -TestFile menu.swg
.EXAMPLE
tools\coverage.bat -DevMode -Suite parity
#>
[CmdletBinding()]
param(
    [ValidateSet('functional', 'goldens', 'parity', 'fast', 'full')]
    [string] $Suite = 'functional',
    [ValidateSet('all', 'std', 'apps')]
    [string] $Workspace = 'all',
    [string] $Module,
    [string[]] $TestFile,
    [switch] $DevMode,
    [ValidateSet('devmode', 'release')]
    [string] $Configuration = 'devmode',
    [ValidateRange(0, 2147483647)]
    [int] $Workers = 0
)

$ErrorActionPreference = 'Stop'
$ParityTag = 'integration.renderer.opengl'
if ($Suite -eq 'fast') { $Suite = 'functional' }
if ($Suite -in @('goldens', 'full') -and !$PSBoundParameters.ContainsKey('Configuration')) {
    $Configuration = 'release'
}
if ($Suite -eq 'goldens' -and $Configuration -ne 'release') {
    throw 'The goldens suite requires -Configuration release.'
}
if ($Module -and $Workspace -eq 'all') { throw '-Module requires -Workspace std or apps.' }
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

Write-Host "[coverage] suite=$Suite"
if ($Suite -eq 'parity') {
    Invoke-TaggedCampaign $ParityTag
} elseif ($Suite -eq 'goldens') {
    if ($Workspace -eq 'all' -and !$TestFile) { Invoke-Coverage 'goldens' @() } else { Invoke-TaggedCampaign 'golden' }
} else {
    $options = @()
    if ($Module) { $options += $Module }
    if ($Suite -eq 'functional' -or ($Suite -eq 'full' -and $Configuration -eq 'devmode')) {
        $options += @('--test-tag', '!golden')
    }
    foreach ($file in $TestFile) { $options += @('--test-file', $file) }
    $workspaces = if ($Workspace -eq 'all') { @('std', 'apps') } else { @($Workspace) }
    foreach ($item in $workspaces) { Invoke-Coverage $item $options }
}
exit $result
