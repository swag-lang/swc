[CmdletBinding()]
param(
    [ValidateSet('build', 'test', 'run', 'smoke', 'startup-smoke', 'library-smoke', 'capture-smoke', 'audit-library', 'render', 'measure', 'package', 'import-settings')]
    [string] $Action = 'build',
    [ValidateSet('release', 'dev')]
    [string] $Profile = 'release',
    [ValidateRange(1, 20)]
    [int] $Samples = 3,
    [string] $OutputRoot,
    [string] $SettingsPath,
    [string[]] $AppArgs = @()
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$project = Join-Path $PSScriptRoot 'capture-rust'
if (-not $OutputRoot) {
    $OutputRoot = Join-Path $env:LOCALAPPDATA 'swc-agent-builds/clone/capture-rust'
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
if ($OutputRoot.StartsWith($repoRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The output directory must be outside the checkout.'
}
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
$env:CARGO_TARGET_DIR = Join-Path $OutputRoot 'target'
$configuration = if ($Profile -eq 'release') { 'release' } else { 'debug' }
$binary = Join-Path $env:CARGO_TARGET_DIR "x86_64-pc-windows-msvc/$configuration/swagcapture-rust-preview.exe"
$profileArgs = if ($Profile -eq 'release') { @('--release') } else { @() }

function Admit-Work {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot '.agents/skills/modify-swag-codebase/scripts/check-machine-load.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Machine load did not admit this command. Retry when resources are available.' }
}
function Invoke-Cargo([string[]] $Arguments) {
    & cargo @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Cargo failed with exit code $LASTEXITCODE." }
}
function Invoke-App([string[]] $Arguments, [bool] $Visible = $false, [int] $TimeoutSeconds = 60) {
    if (-not (Test-Path -LiteralPath $binary)) { throw 'Build the application first.' }
    # Start-Process forwards one Windows command line. Quote each argument separately.
    $quoted = @($Arguments | ForEach-Object { '"' + ($_ -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"' })
    $options = @{ FilePath = $binary; WorkingDirectory = $OutputRoot; PassThru = $true }
    if ($quoted.Count) { $options.ArgumentList = $quoted }
    if (-not $Visible) { $options.WindowStyle = 'Hidden' }
    $process = Start-Process @options
    if ($Visible) { return }
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) { $process.Kill(); throw "The application exceeded the $TimeoutSeconds second execution limit." }
    if ($process.ExitCode -ne 0) { throw "Application failed with exit code $($process.ExitCode)." }
}

Push-Location $project
try {
    switch ($Action) {
        build { Admit-Work; Invoke-Cargo (@('build', '--locked', '--timings') + $profileArgs) }
        test { Admit-Work; Invoke-Cargo (@('test', '--locked') + $profileArgs) }
        run { Invoke-App $AppArgs $true }
        import-settings {
            Admit-Work
            if (-not $SettingsPath) { $SettingsPath = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Swag Capture/settings.scc' }
            Invoke-App @('--import-settings', $SettingsPath)
        }
        smoke {
            Admit-Work
            Invoke-App (@('--demo', '--smoke', '--frames', '30', '--data-dir', (Join-Path $OutputRoot 'smoke-data'),
                '--report', (Join-Path $OutputRoot 'smoke.json'), '--screenshot', (Join-Path $OutputRoot 'native.png')) + $AppArgs)
            $report = Get-Content -Raw (Join-Path $OutputRoot 'smoke.json') | ConvertFrom-Json
            if ($report.errors) { throw $report.errors }
            if (-not (Test-Path (Join-Path $OutputRoot 'native.png'))) { throw 'The native renderer did not produce its screenshot.' }
        }
        startup-smoke {
            Admit-Work
            Invoke-App (@('--smoke', '--frames', '30', '--report', (Join-Path $OutputRoot 'startup.json'),
                '--screenshot', (Join-Path $OutputRoot 'startup.png')) + $AppArgs)
            $report = Get-Content -Raw (Join-Path $OutputRoot 'startup.json') | ConvertFrom-Json
            if ($report.errors) { throw $report.errors }
            if (-not $report.opened_capture) { throw 'Startup did not open a library capture.' }
            if (-not (Test-Path (Join-Path $OutputRoot 'startup.png'))) { throw 'Startup did not produce its screenshot.' }
        }
        audit-library {
            Admit-Work
            Invoke-App (@('--audit-library', '--report', (Join-Path $OutputRoot 'library-audit.json')) + $AppArgs) $false 300
            $entries = Get-Content -Raw (Join-Path $OutputRoot 'library-audit.json') | ConvertFrom-Json
            $errors = @($entries | Where-Object { $_.error })
            Write-Output "Loaded $($entries.Count - $errors.Count) of $($entries.Count) captures."
            $errors | Group-Object error | Select-Object Count, Name
        }
        library-smoke {
            Admit-Work
            Invoke-App (@('--smoke', '--library-smoke', '--frames', '30', '--report', (Join-Path $OutputRoot 'library-smoke.json'),
                '--screenshot', (Join-Path $OutputRoot 'library.png')) + $AppArgs) $false 180
            $report = Get-Content -Raw (Join-Path $OutputRoot 'library-smoke.json') | ConvertFrom-Json
            if ($report.errors) { throw $report.errors }
            if (-not $report.library_indexed -or $report.library_smoke_stage -lt 3 -or $report.library_visible_images -eq 0 -or $report.library_last_visible -ne ($report.library_entries - 1)) {
                throw 'The library did not complete indexing and scrolling.'
            }
            $report | Select-Object library_entries, library_previews_loaded, working_set_bytes, ui_update_p95_ms
        }
        capture-smoke {
            Admit-Work
            Invoke-App (@('--smoke', '--capture-smoke', '--frames', '30', '--data-dir', (Join-Path $OutputRoot 'capture-smoke-data'),
                '--report', (Join-Path $OutputRoot 'capture-smoke.json'), '--screenshot', (Join-Path $OutputRoot 'capture-result.png')) + $AppArgs) $false 90
            $report = Get-Content -Raw (Join-Path $OutputRoot 'capture-smoke.json') | ConvertFrom-Json
            if ($report.errors) { throw $report.errors }
            if ($report.capture_checks.Count -ne 4) { throw 'The capture lifecycle scenarios did not complete.' }
            $report.capture_checks
        }
        render {
            Admit-Work
            Invoke-App (@('--render-ui', (Join-Path $OutputRoot 'encre.png'), '--data-dir', (Join-Path $OutputRoot 'render-encre')) + $AppArgs)
            Admit-Work
            Invoke-App (@('--render-ui', (Join-Path $OutputRoot 'papier.fr.png'), '--light', '--french', '--data-dir', (Join-Path $OutputRoot 'render-papier')) + $AppArgs)
        }
        measure {
            # Warm dependencies and complete the application once, outside measured samples.
            Admit-Work
            Invoke-Cargo (@('build', '--locked') + $profileArgs)
            $records = @()
            for ($i = 0; $i -lt $Samples; $i++) {
                # Only the application's package is removed. Libraries stay compiled.
                Invoke-Cargo (@('clean', '-p', 'swagcapture-rust') + $profileArgs)
                Admit-Work
                $watch = [Diagnostics.Stopwatch]::StartNew()
                Invoke-Cargo (@('build', '--locked', '--offline', '--timings') + $profileArgs)
                $watch.Stop()
                $records += [pscustomobject]@{ kind = 'application-rebuild-and-link'; sample = $i; milliseconds = $watch.Elapsed.TotalMilliseconds }
                Admit-Work
                $watch.Restart()
                Invoke-Cargo (@('build', '--locked', '--offline') + $profileArgs)
                $watch.Stop()
                $records += [pscustomobject]@{ kind = 'no-change'; sample = $i; milliseconds = $watch.Elapsed.TotalMilliseconds }
            }
            $report = [ordered]@{
                source_commit = (& git rev-parse HEAD)
                source_dirty = [bool](& git status --porcelain -- .)
                rustc = (& rustc --version)
                cargo = (& cargo --version)
                profile = $Profile
                target = 'x86_64-pc-windows-msvc'
                crt_static = $true
                cross_crate_lto = $false
                samples = $records
                executable_bytes = (Get-Item -LiteralPath $binary).Length
                parity_verified = $false
                scope = 'Application rebuild with cached dependencies, resource compilation and final static link; not a library-free compiler measurement.'
            }
            $report | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 (Join-Path $OutputRoot 'build-measurements.json')
            Admit-Work
            Invoke-App @('--benchmark', '--objects', '120', '--frames', '600', '--data-dir', (Join-Path $OutputRoot 'benchmark-data'), '--report', (Join-Path $OutputRoot 'runtime-measurements.json'))
        }
        package {
            Admit-Work
            if (-not (Test-Path -LiteralPath $binary)) { throw 'Build the application first.' }
            & py -3 (Join-Path $project 'inspect-pe.py') $binary --output (Join-Path $OutputRoot 'pe-imports.json')
            if ($LASTEXITCODE -ne 0) { throw 'The executable imports a non-system DLL.' }
            $package = Join-Path $OutputRoot 'package'
            New-Item -ItemType Directory -Path $package -Force | Out-Null
            Copy-Item -LiteralPath $binary -Destination (Join-Path $package 'swagcapture-rust.exe')
            Write-Output (Join-Path $package 'swagcapture-rust.exe')
        }
    }
}
finally { Pop-Location }
