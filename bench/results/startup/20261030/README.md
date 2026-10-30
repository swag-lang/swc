# Swag Capture startup measurements, 2026-10-30

The optimization batches reduce startup substantially, but the requested 325 ms budget is
not established for a usable document frame. Visibility and a successful message round trip
are weaker milestones. Do not substitute the fastest subset of launches for the longer series.

## Protocol

Windows native Release Capture, built by the same checkout-local DevMode compiler with six
compiler workers. Baseline: `4fc60967f9`; final: `46a982c042`.
The baseline already includes parallel CPU resolves and batched initial window placement.
Alternating launches use separate sandbox copies of the same settings and one 677 x 303 capture.
The restored native window rectangle is (-3383, 135, -818, 1923), or 2565 x 1788 physical pixels.
The probe is DPI aware. The user's personal library is never a writable benchmark profile.
Host: Intel Core Ultra 9 185H (16 cores, 22 logical processors), about 32 GiB RAM,
Windows 11 build 26300. Intel Arc driver 32.0.101.8860 and two DisplayLink adapters
(driver 11.5.6380.0) are present. This is a single-host comparison, not a hardware-wide budget.

Time starts at process creation, excluding `tools/apps.bat dm run swagcapture -bc release`
and compiler-launch overhead. Visibility is observed through the native HWND; responsiveness
is the first successful `WM_NULL` round trip. Requested polling interval: 5 ms; scheduler
granularity adds uncertainty. These are warm-cache launches, without OS-cache flushing.
Each launch requires CPU admission at most 15% and the repository's normal memory headroom.
No task-owned build/test overlaps timing. Working set is sampled 1.5 seconds after visibility.

## Uninstrumented medians

| Series | Artifact | Visible ms | Responsive ms | CPU at visibility ms | Settled working set MiB |
| --- | --- | ---: | ---: | ---: | ---: |
| eight_pairs_before_final_timer_change | baseline | 659.0 | 685.7 | 1554.7 | 263.9 |
| eight_pairs_before_final_timer_change | candidate | 330.4 | 347.5 | 281.2 | 235.8 |
| eight_pairs_final | baseline | 659.8 | 687.7 | 1734.4 | 263.8 |
| eight_pairs_final | candidate | 324.0 | 340.4 | 296.9 | 235.9 |

All individual samples and artifact/compiler hashes are in [measurements.json](measurements.json).
The final native EXE is 12,046,336 bytes versus 11,829,760:
an increase of 216,576 bytes (1.83%).

## Document-bearing publication diagnostic

These runs attach a debugger and instrument document selection, editor painting, readback
submission, and native publication. Values include debugger disturbance and are not an
uninstrumented startup benchmark or physical display latency. The diagnostic follows the
first editor paint after `RecentView.selectLoaded` returns, its subsequent queued readback,
and the following `UpdateLayeredWindowIndirect` publication. It excludes publication of the
older empty frame still pending when the document becomes selected.

| Trace | Document selected ms | Following document publication ms |
| --- | ---: | ---: |
| baseline-content-1 | 752.7 | 794.0 |
| baseline-content-2 | 750.0 | 797.5 |
| content-1 | 385.0 | 469.7 |
| content-2 | 386.5 | 475.2 |
| document-content-1 | 436.0 | 512.3 |
| document-content-2 | 468.5 | 558.5 |

The final timer change opens the first candidate on the already-deferred enumeration turn.
Later candidates still load one per timer turn. It does not move work behind an earlier blank
window, nor does it make first visibility equivalent to a usable document frame.
The final instrumented runs are slower than the two preceding candidate traces; these few
perturbed observations do not establish the timer change's isolated wall-time benefit.
Its eliminated scheduling turn is covered by the startup regression test.

## Raster tradeoff

Shared theme atlases store seven exact icon sizes and two widget scales as checked-in PNGs;
Capture supplies its own two common sizes through `IconAtlas.setRaster`. The SVG source stays
available for custom themes, unsupported sizes and DPI changes. Generators run explicitly;
ordinary application compilation has no new generation step and needs no owning `#run`
buffer materialization. Therefore compiler.core.099 is not required by this implementation.

Exact-size PNG decoding took about 8.6 ms for all seven shared icon sizes in the separate
Release microprobe. A 96-pixel-per-cell runtime raster plus reduction took about 62-65 ms
without supersampling, or 357 ms with fourfold supersampling. The reduced small glyphs had
uneven strokes; this experiment does not establish what an arbitrary Rust application does.
Checked-in derivatives use DevMode coverage to preserve the existing goldens; Release SVG
coverage may differ by one alpha level. No golden expectations were promoted.

Other changes reuse three OpenGL vertex stages across eight shader programs, avoid repeated
layout allocations and preference application, start scheduler workers on first demand, reuse
the decoded app icon, exclude the settings container from recent documents, and parse stock
theme SVG only on a raster-cache miss.

## Validation

- Shared rendering changes: complete DevMode golden campaign, 292 passed.
- OpenGL stage reuse: six native OpenGL integration tests; layout: 34 focused tests.
- Raster APIs/fallbacks: focused GUI tests in DevMode and Release, including unsupported sizes,
  source replacement and widget fallback; latest lazy-SVG boundary: seven passed.
- All four official apps: native Release startup smokes passed.
- Final first-document scheduling change: 30 Capture file/scenario tests, 22 Capture goldens,
  and native Release Capture smoke passed. Earlier independent shared checks remain valid.

This is not a full compiler campaign: compiler code and compiler cache identity are unchanged.
Remaining work and measurement constraints live in `backlog/std.gui.md`, entry std.gui.060.
The borrowed-atlas storage issue is tracked separately as std.gui.061 before any broader
parallelization of atlas requests.

Raw probes, logs and sandbox profiles remain outside the checkout under
`%LOCALAPPDATA%/swc-agent-builds/startup-midnight-20261030` (`probe.py`, `ab-document.py`,
`trace-document.py`). Recreate the compared builds before replaying: the two temporary
benchmark worktrees are removed at the end of the session. Do not reuse their paths without
rebuilding or treat the instrumented traces as absolute timing evidence.
