# Capture in Rust

This is an experimental Windows port of Swag Capture, initially based on
repository commit `dec813751c`. Its source lives under `bench/clone/capture-rust`
and it does not replace the Swag application. It is **not yet an exact clone** and
must not be used to claim equivalent-workload performance against Swag Capture.

The implementation includes the annotation canvas, selection and grouping,
undo/redo, image effects, clipboard images, desktop capture, the command lens,
an inspector, a capture library, English/French strings and Encre/Papier palettes.
The original icon, fonts and translation tables are embedded at compile time.
Settings and captures default to `%LOCALAPPDATA%/SwagCaptureRust`.

The Capture icon atlas is embedded as SVG source, then rasterized once at 4x into
a 768 × 480 GPU texture on first paint. This is a cached runtime raster, not a
pre-rasterized bitmap atlas embedded in a theme. Its first-use cost, retained GPU
memory and appearance across monitor scales have not been compared directly with
Swag's atlas path; do not infer relative icon quality from the PE size census.

The Rust SCC reader is tested against Capture's immutable all-forms fixture.
It preserves unmodeled fields within recognized form records, but this is not a
promise of lossless compatibility with arbitrary SCC files. Advanced object
properties and selection behavior, some library operations, global hotkeys,
tray integration, pinned captures and exact visual parity are incomplete.
The graphics and widget implementation uses egui/eframe and differs from Swag's
GUI library. The exported-image renderer also differs.

The line renderer now uses the source cap geometry for all eight endpoint styles,
start/end scales, quadratic curves, dash spacing and a separate outline color and
width. One coverage mask applies opacity once across the shaft and its caps. The
canvas and image export share this renderer; cached stroke textures are released
when their forms change or leave the document. Arrowheads also participate in
selection. This is not a pixel-for-pixel port of the Swag rasterizer: dash-end
styles, miter-bevel fallback and exact shadow filtering remain different.

The line inspector exposes the actual stroke and outline colors, visual endpoint
choices and straight/curved and shadow segments. The command lens groups actions
by editor/library context, displays keyboard shortcuts and supports Up/Down/Enter.
The library uses the source application name when a capture has no explicit title,
and newly saved SCC previews include annotations. Existing previews are not rewritten.

## Build and run

Requirements: Windows x64, Rust's MSVC toolchain, Visual Studio C++ build tools
and the Windows SDK resource compiler. Cargo.lock pins dependency versions.

From the Swag repository root:

```powershell
$captureOutput = "$env:LOCALAPPDATA/swc-agent-builds/capture-rust-20261030"
$runner = (Resolve-Path .\bench\clone\capture-rust.ps1).Path
powershell -NoProfile -ExecutionPolicy Bypass -File $runner -Action build -OutputRoot $captureOutput
powershell -NoProfile -ExecutionPolicy Bypass -File $runner -Action run -OutputRoot $captureOutput
```

The executable is at
`$captureOutput/target/x86_64-pc-windows-msvc/release/swagcapture-rust-preview.exe`.
Build artifacts, generated resources, screenshots and measurement reports stay
outside the checkout. The launcher checks shared-machine headroom before each
build, test or automated runtime scenario. Retry an unadmitted command later.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File $runner -Action test -OutputRoot $captureOutput
powershell -NoProfile -ExecutionPolicy Bypass -File $runner -Action smoke -OutputRoot $captureOutput
powershell -NoProfile -ExecutionPolicy Bypass -File $runner -Action capture-smoke -OutputRoot $captureOutput
powershell -NoProfile -ExecutionPolicy Bypass -File $runner -Action library-smoke -OutputRoot $captureOutput
powershell -NoProfile -ExecutionPolicy Bypass -File $runner -Action render -OutputRoot $captureOutput
powershell -NoProfile -ExecutionPolicy Bypass -File $runner -Action package -OutputRoot $captureOutput
```

`package` inspects normal and delayed PE imports, rejects non-system DLL imports,
and copies one file to `$captureOutput/package/swagcapture-rust.exe`. The CRT is
linked statically. Fonts, translations, icon and dependency notices are embedded;
there are no companion application DLLs or resource folders to distribute.
Windows system DLLs and the installed graphics driver are still used. Notices
are accessible from About, or with `--licenses <output-path>`.

The native capture smoke exercises desktop capture, area acceptance, cancellation
and an invalid capture rectangle. It checks window restoration and the overlay's
mapping of screen pixels to selection pixels. It uses an isolated profile and
does not change the clipboard. The area rectangle is supplied by the scenario
through the same completion handler as the interactive selector.

The library indexes SCC headers on a worker and reads the stored PNG previews
only for visible rows. It keeps at most 64 GPU thumbnails and bounds queued
decoded previews. Invalid entries retain an error instead of being retried every
frame. The native library smoke indexes the configured library and scrolls to
the beginning, middle and end, requiring visible thumbnails at the final item.

## Import the Swag Capture profile

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File $runner -Action import-settings -OutputRoot $captureOutput
powershell -NoProfile -ExecutionPolicy Bypass -File $runner -Action startup-smoke -OutputRoot $captureOutput
powershell -NoProfile -ExecutionPolicy Bypass -File $runner -Action audit-library -OutputRoot $captureOutput
```

The import reads `Documents/Swag Capture/settings.scc`, copies it unchanged to
`%LOCALAPPDATA%/SwagCaptureRust/swag-settings.scc`, and creates the Rust settings
file alongside it. `-SettingsPath` selects a different source. The source file
is never rewritten. The library points to the same capture directory; captures
are not duplicated. Editing and saving in either application therefore affects
that shared library.

Theme, language, tool, snap, inspector visibility, window geometry, cursor,
capture delay, capture destinations, hiding the editor, the capture crosshair
and tool style presets are imported. At each normal startup, the
newest readable capture by modification time opens, matching Swag Capture's
startup selection. `startup-smoke` verifies that path through the native UI,
saves `startup.json` and `startup.png`, then exits without editing the capture.
The source state is also retained as `swag-state.json`; settings for features
that have not yet been ported are preserved there but are not implemented.
`audit-library` reads every capture without changing it and writes individual
load results to `library-audit.json`. This verifies format compatibility, not
visual equivalence of every annotation.

## Measurement boundaries

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File $runner -Action measure -Samples 3 -OutputRoot $captureOutput
```

The warm build, including external dependencies, is outside the measured samples.
For each sample, `cargo clean -p swagcapture-rust` removes only this package;
the timed offline build recompiles the application and links the executable using
cached dependencies. A second sample measures Cargo's no-change invocation.
Release uses optimization level 3, 16 codegen units, panic abort, stripped symbols,
static CRT and no cross-crate LTO. Cargo timing reports are saved with the build.

These are application **build-and-link** times, not a perfectly library-free
compiler measurement: application-instantiated generic code, embedded resources,
the build script and final static linking are included. The executable size is
the size of the complete distributable, including linked libraries and assets;
it cannot simultaneously represent only application code and the full standalone
executable. Comparing application-only machine code would require a separate
symbol/section attribution analysis.

The runtime scenario animates pan and zoom over 120 annotations. Its reported
frame timings cover the application UI update and exclude egui tessellation,
GPU work, presentation and input-to-display latency. Process memory includes
libraries and graphics allocations visible to Windows. It is a reproducible
profiling scenario, **not an end-to-end responsiveness benchmark**.

Both JSON reports explicitly contain `parity_verified: false`. No Swag/Rust
performance ratio is produced. A valid comparison requires equivalent behavior,
documents, interactions, DPI, renderer settings and measurement boundaries on
both sides before using these numbers to draw conclusions.
