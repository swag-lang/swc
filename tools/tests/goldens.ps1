# Exercises golden-module discovery and failure aggregation without a compiler or UI.
param([string] $Tool = (Join-Path $PSScriptRoot '..\goldens.bat'))

$ErrorActionPreference = 'Stop'
$scratchBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$scratch = Join-Path $scratchBase ('swag-goldens-' + [Guid]::NewGuid().ToString('N'))

function Write-Runner([string]$Workspace, [int]$ExitCode = 0) {
    $body = "@echo off`r`n>>`"%~dp0calls.txt`" echo $Workspace %*`r`nexit /b $ExitCode`r`n"
    Set-Content -LiteralPath (Join-Path $scratch "tools\$Workspace.bat") -Value $body -Encoding Ascii
}

function Assert-Campaign([int]$ExitCode, [string[]]$Modules) {
    $calls = Join-Path $scratch 'tools\calls.txt'
    if (Test-Path -LiteralPath $calls) { Remove-Item -LiteralPath $calls }
    & (Join-Path $scratch 'tools\goldens.bat') dm test --run-timeout 17 --num-cores 1 | Out-Null
    if ($LASTEXITCODE -ne $ExitCode) { throw "Expected exit $ExitCode, received $LASTEXITCODE" }
    $actual = @(if (Test-Path -LiteralPath $calls) { Get-Content -LiteralPath $calls })
    $expected = @($Modules | ForEach-Object {
        $workspace, $module = $_ -split '/'
        "$workspace dm test `"$module`" --test-tag golden --run-timeout 17 --num-cores 1"
    })
    if (($actual -join '|') -ne ($expected -join '|')) { throw "Unexpected module calls: $actual" }
}

try {
    $null = New-Item -ItemType Directory -Path (Join-Path $scratch 'tools'), (Join-Path $scratch 'bin') -Force
    Copy-Item -LiteralPath $Tool -Destination (Join-Path $scratch 'tools\goldens.bat')
    $null = New-Item -ItemType File -Path (Join-Path $scratch 'bin\swc.dm.exe')
    foreach ($workspace in @('std', 'examples', 'apps', 'reference')) {
        $module = Join-Path $scratch "bin\$workspace\modules\fixture\src"
        $null = New-Item -ItemType Directory -Path $module -Force
        Set-Content -LiteralPath (Join-Path $module 'fixture.test.swg') -Value '#test {}' -Encoding Ascii
        Set-Content -LiteralPath (Join-Path $module 'documentation.swg') -Value '/** #[Swag.TestTag("golden")] */' -Encoding Ascii
        Write-Runner $workspace
    }
    Assert-Campaign 0 @()

    foreach ($workspace in @('std', 'apps')) {
        Set-Content -LiteralPath (Join-Path $scratch "bin\$workspace\modules\fixture\src\fixture.test.swg") -Value '#[Swag.TestTag("golden")]' -Encoding Ascii
    }
    Assert-Campaign 0 @('std/fixture', 'apps/fixture')

    foreach ($workspace in @('examples', 'reference')) {
        Set-Content -LiteralPath (Join-Path $scratch "bin\$workspace\modules\fixture\src\fixture.test.swg") -Value '#[Swag.TestTag("golden")]' -Encoding Ascii
    }
    Assert-Campaign 0 @('std/fixture', 'examples/fixture', 'apps/fixture', 'reference/fixture')

    Write-Runner 'examples' 7
    Assert-Campaign 1 @('std/fixture', 'examples/fixture', 'apps/fixture', 'reference/fixture')

    $nested = Join-Path $scratch 'bin\std\modules\followup\src\nested'
    $null = New-Item -ItemType Directory -Path $nested -Force
    Set-Content -LiteralPath (Join-Path $nested 'followup.test.swg') -Value '#[Swag.TestTag("golden")]' -Encoding Ascii
    Write-Runner 'std' 7
    Write-Runner 'examples'
    Assert-Campaign 1 @('std/fixture', 'std/followup', 'examples/fixture', 'apps/fixture', 'reference/fixture')

    Write-Runner 'std'
    Assert-Campaign 0 @('std/fixture', 'std/followup', 'examples/fixture', 'apps/fixture', 'reference/fixture')
    Write-Output 'Golden runner: 6 regression cases passed.'
}
finally {
    $resolved = [IO.Path]::GetFullPath($scratch)
    if ((Split-Path -Parent $resolved) -ne $scratchBase -or -not (Split-Path -Leaf $resolved).StartsWith('swag-goldens-')) {
        throw 'Refusing to remove a directory outside the golden-test scratch folder.'
    }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
