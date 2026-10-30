# Exercises golden-workspace discovery and failure propagation without a compiler or UI.
$ErrorActionPreference = 'Stop'
$scratchBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$scratch = Join-Path $scratchBase ('swag-goldens-' + [Guid]::NewGuid().ToString('N'))
$toolSource = Join-Path $PSScriptRoot '..\goldens.bat'

function Write-Runner([string]$Workspace, [int]$ExitCode = 0) {
    $body = "@echo off`r`n>>`"%~dp0calls.txt`" echo $Workspace %*`r`nexit /b $ExitCode`r`n"
    Set-Content -LiteralPath (Join-Path $scratch "tools\$Workspace.bat") -Value $body -Encoding Ascii
}

function Assert-Campaign([int]$ExitCode, [string[]]$Workspaces) {
    $calls = Join-Path $scratch 'tools\calls.txt'
    if (Test-Path -LiteralPath $calls) { Remove-Item -LiteralPath $calls }
    & (Join-Path $scratch 'tools\goldens.bat') dm test --run-timeout 17 | Out-Null
    if ($LASTEXITCODE -ne $ExitCode) { throw "Expected exit $ExitCode, received $LASTEXITCODE" }
    $actual = @(Get-Content -LiteralPath $calls)
    $expected = @($Workspaces | ForEach-Object { "$_ dm test --test-tag golden --run-timeout 17" })
    if (($actual -join '|') -ne ($expected -join '|')) { throw "Unexpected workspace calls: $actual" }
}

try {
    $null = New-Item -ItemType Directory -Path (Join-Path $scratch 'tools'), (Join-Path $scratch 'bin') -Force
    Copy-Item -LiteralPath $toolSource -Destination (Join-Path $scratch 'tools\goldens.bat')
    $null = New-Item -ItemType File -Path (Join-Path $scratch 'bin\swc.dm.exe')
    foreach ($workspace in @('std', 'examples', 'apps', 'reference')) {
        $module = Join-Path $scratch "bin\$workspace\modules\fixture\src"
        $null = New-Item -ItemType Directory -Path $module -Force
        Set-Content -LiteralPath (Join-Path $module 'fixture.test.swg') -Value '#test {}' -Encoding Ascii
        Set-Content -LiteralPath (Join-Path $module 'documentation.swg') -Value '/** #[Swag.TestTag("golden")] */' -Encoding Ascii
        Write-Runner $workspace
    }

    foreach ($workspace in @('std', 'apps')) {
        Set-Content -LiteralPath (Join-Path $scratch "bin\$workspace\modules\fixture\src\fixture.test.swg") -Value '#[Swag.TestTag("golden")]' -Encoding Ascii
    }
    Assert-Campaign 0 @('std', 'apps')

    foreach ($workspace in @('examples', 'reference')) {
        Set-Content -LiteralPath (Join-Path $scratch "bin\$workspace\modules\fixture\src\fixture.test.swg") -Value '#[Swag.TestTag("golden")]' -Encoding Ascii
    }
    Assert-Campaign 0 @('std', 'examples', 'apps', 'reference')

    Write-Runner 'examples' 7
    Assert-Campaign 1 @('std', 'examples')
    Write-Output 'Golden runner: 3 regression cases passed.'
}
finally {
    $resolved = [IO.Path]::GetFullPath($scratch)
    if ((Split-Path -Parent $resolved) -ne $scratchBase -or -not (Split-Path -Leaf $resolved).StartsWith('swag-goldens-')) {
        throw 'Refusing to remove a directory outside the golden-test scratch folder.'
    }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
