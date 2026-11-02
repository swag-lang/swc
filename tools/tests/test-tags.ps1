# Exercise the compiler and generated runtime through the same tag-selection cases.
param([string] $Compiler = (Join-Path $PSScriptRoot '..\..\bin\swc.dm.exe'))
$ErrorActionPreference = 'Stop'
$Compiler = (Resolve-Path -LiteralPath $Compiler).Path
$scratchBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$scratch = Join-Path $scratchBase ('swag test tags ' + [Guid]::NewGuid().ToString('N'))
$previousWorkers = $env:SWAG_RUNTIME_THREADS
try {
    $source = Join-Path $scratch 'modules\tags\src\tests'
    $null = New-Item -ItemType Directory -Path $source -Force
    @'
#run
{
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.moduleNamespace = "TagProbe"
    cfg.backendKind = .Executable
}
'@ | Set-Content -LiteralPath (Join-Path $scratch 'modules\tags\module.swg')
    @'
#global if #command == Swag.CompilerCommand.Test
#test { Swag.print("tag-probe:plain\n") }
#[Swag.TestTag("golden")]
#test { Swag.print("tag-probe:golden\n") }
#[Swag.TestTag("slow")]
#test { Swag.print("tag-probe:slow\n") }
#[Swag.TestTag("integration.probe")]
#test { Swag.print("tag-probe:integration\n") }
'@ | Set-Content -LiteralPath (Join-Path $source 'selection.test.swg')
    $cases = @(
        @{ Filters = @(); Expected = @('plain', 'golden', 'slow') },
        @{ Filters = @('!golden'); Expected = @('plain', 'slow') },
        @{ Filters = @('golden', 'slow'); Expected = @('golden', 'slow') },
        @{ Filters = @('golden', '!golden', 'slow'); Expected = @('slow') },
        @{ Filters = @('!golden', 'integration.probe'); Expected = @('integration') }
    )
    $env:SWAG_RUNTIME_THREADS = '3'
    foreach ($mode in @('native', 'jit')) {
        foreach ($case in $cases) {
            $arguments = @('test', '--workspace', $scratch, '--workspace-module', 'tags', '--num-cores', '3', '--log-ascii')
            $arguments += if ($mode -eq 'native') { @('--no-test-jit') } else { @('--test-jit', '--no-test-native', '--no-output') }
            foreach ($tag in $case.Filters) { $arguments += @('--test-tag', $tag) }
            $ErrorActionPreference = 'Continue'
            $output = & $Compiler @arguments 2>&1 | Out-String
            $code = $LASTEXITCODE
            $ErrorActionPreference = 'Stop'
            if ($code) { throw "$mode selection failed: $output" }
            $found = @([regex]::Matches($output, 'tag-probe:(plain|golden|slow|integration)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object)
            $expected = @($case.Expected | Sort-Object)
            if (($found -join ',') -ne ($expected -join ',')) { throw "$mode selection: expected $expected, received $found.`n$output" }
        }
    }
    Write-Output 'Test tags: 10 native/JIT selection cases passed.'
} finally {
    $env:SWAG_RUNTIME_THREADS = $previousWorkers
    $resolved = [IO.Path]::GetFullPath($scratch)
    if (!$resolved.StartsWith($scratchBase, [StringComparison]::OrdinalIgnoreCase)) { throw 'Scratch path escaped the temporary directory.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
