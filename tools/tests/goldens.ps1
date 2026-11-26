# Check argument and exit-code forwarding to the shared golden launcher.
param([string] $Tool = (Join-Path $PSScriptRoot '..\goldens.bat'))

$ErrorActionPreference = 'Stop'
$scratchBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$scratch = Join-Path $scratchBase ('swag-goldens-' + [Guid]::NewGuid().ToString('N'))

try {
    $null = New-Item -ItemType Directory -Path $scratch
    $launcher = Join-Path $scratch 'goldens.bat'
    Copy-Item -LiteralPath $Tool -Destination $launcher
    @'
import json
import sys

print(json.dumps(sys.argv[1:]))
raise SystemExit(7 if '--force-failure' in sys.argv else 0)
'@ | Set-Content -LiteralPath (Join-Path $scratch 'tool.py') -Encoding Ascii

    $actual = & $launcher dm test --test-file 'two words.swg' --num-cores 1
    if ($LASTEXITCODE -ne 0) { throw "Golden test command exited $LASTEXITCODE." }
    $expected = @('goldens', 'dm', 'test', '--test-file', 'two words.swg', '--num-cores', '1')
    if ((($actual | ConvertFrom-Json) -join '|') -ne ($expected -join '|')) { throw "Unexpected arguments: $actual" }

    $actual = & $launcher accept
    if ($LASTEXITCODE -ne 0 -or (($actual | ConvertFrom-Json) -join '|') -ne 'goldens|accept') {
        throw "Unexpected golden accept result: $actual"
    }

    & $launcher test --force-failure | Out-Null
    if ($LASTEXITCODE -ne 7) { throw "Expected exit 7, received $LASTEXITCODE." }
    Write-Output 'Golden launcher: argument and exit-code forwarding passed.'
}
finally {
    $resolved = [IO.Path]::GetFullPath($scratch)
    if ((Split-Path -Parent $resolved) -ne $scratchBase -or -not (Split-Path -Leaf $resolved).StartsWith('swag-goldens-')) {
        throw 'Scratch path escaped the temporary directory.'
    }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
