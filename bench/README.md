# The Swag Performance Benchmark

This directory answers one question over time: **is the compiler getting better?**

```
tools\run-benchmark-campaign.bat --label "what changed since last time"
```

That rebuilds `swc.exe` in Release, measures it against every other toolchain, appends the
result to `history.json`, and regenerates `bench.html`. Nothing else is needed.

| | |
|---|---|
| `tools\run-benchmark-campaign.bat --quick` | one repetition, no cooldown; proves the plumbing works and is **not** recorded |
| `tools\run-benchmark-campaign.bat --report-only` | rebuild the normalized history and page from raw campaigns, measure nothing |
| `tools\run-benchmark-campaign.bat --no-build` | measure the binary already in `bin/`, useful when iterating on the harness |

A full campaign takes roughly twenty-five minutes, most of it in the two-minute cooldown,
the NativeAOT publishes and CPython.

## What is measured

Six programs, written by hand and identically in swag, C++, Rust, Swift, C#, JavaScript, Lua
and Python. None of them uses a standard library container: each reimplements its own hash
map, heap or matrix, so the benchmark measures the compiler rather than somebody's hash
table. Every port prints the same checksum, and **a campaign that reports a checksum mismatch
has measured nothing** — fix the ports before believing any number.

Fourteen runtimes in total: swag native and JIT in both configurations, two C++ compilers,
Rust, Swift, C# ahead-of-time and jitted, V8, LuaJIT, Lua and CPython.

## Two rules that keep the numbers honest

Both of these were discovered the hard way; both changed the results.

**Helper processes are reaped.** Compilers leave children behind — 46 orphaned `cl.exe` once
accumulated over a single campaign and loaded the machine enough to make the next run up to
2.4 times slower. `winproc.run` puts every child in a job object and terminates it after the
wait. Do not bypass that.

**Repetitions are interleaved, not grouped.** Repetition 0 of every runtime, then repetition 1,
and so on, keeping the minimum. Grouped per runtime, a slow stretch of machine time lands
entirely on one language and invents a result.

Each campaign also times a fixed reference workload before and after the sweep and records the
drift between them. Around ten percent is normal on a laptop. Much more than that means the
machine was busy, and the campaign should be discarded rather than published.

Never present two half-campaigns measured at different moments side by side: the gap between
them is machine noise, not a result.

## How machine variation is removed

`history.json` keeps **swc only**. The other languages do not change between campaigns; they
are re-measured every time solely as a control group.

Raw milliseconds are not comparable across campaigns — the same machine drifts by more than
ten percent between sessions. The oldest complete campaign recorded from a clean tree is the
stable baseline. For each task and later campaign, the harness computes every non-Swag
runtime's ratio to that baseline and takes their logarithmic median: ten controls for execution
and six for compilation. That is the context factor. A Swag time is divided by the factor before
it enters the history.

The correction is per task because the machine can warm up during a sweep, and execution and
compilation get separate factors. The median makes the result insensitive to one noisy runtime
or one independently upgraded toolchain. `history.json` records the factors, control counts,
and median dispersion so the correction remains auditable. A context factor below one means
the controls ran faster than at baseline, so the raw Swag value is raised before comparison.

Compiler memory is the exception. It does not drift with machine state, so it is plotted raw.

The files under `results/` are authoritative. `history.py` rebuilds every compact entry from
those raw campaigns whenever the report is generated, so normalization changes can be applied
retroactively without altering a measurement.

A campaign measured on a modified working tree is recorded with `dirty: true` and marked with
an asterisk in the report, because its commit alone will not reproduce it.

## Files

| | |
|---|---|
| `../tools/run-benchmark-campaign.bat` | the entry point |
| `campaign.py` | rebuild, measure, report |
| `driver.py` | the sweep itself |
| `toolchains.py` | where each toolchain lives and how it builds a task |
| `winproc.py` | process timing and peak memory, through a job object |
| `history.py` | the compact, normalised record |
| `mkpage.py`, `page_template.html` | the report; every figure comes from JSON, never from an edit |
| `results/` | one raw campaign per file, kept whole so a past number can be re-derived |
| `src/` | the six tasks in every language |

## Extending it

- **A new task**: add it to every language under `src/`, then to `TASKS` in `toolchains.py`
  and `mkpage.py`. It must print `CHECK=<n> MS=<f>` and exclude data generation from the timed
  section. Confirm every port agrees on the checksum before recording anything.
- **A new language**: add its recipe in `toolchains.py` and its id to the order lists in
  `driver.py`. Give it the release settings its users would ship, and note whether it keeps
  bounds checks — swag release and C++ do not, the others do.
- **Never change what a task computes.** That silently resets the history, because the past
  numbers stop describing the same work.

## Requirements

MSVC and clang-cl come from Visual Studio; the others are looked up under the user profile.
Any of them can be overridden when it lives somewhere unusual: `BENCH_VS_ROOT`, `BENCH_RUSTC`,
`BENCH_DOTNET`, `BENCH_SWIFTC`, `BENCH_SWIFT_ROOT`, `BENCH_NODE`, `BENCH_LUA`, `BENCH_LUAJIT`,
`BENCH_PY`, and `BENCH_SWC` for the compiler under test. A toolchain that cannot be found is
named and skipped, never guessed at, and the report records which ones were absent.

The page follows [design-swag-identity](../.agents/skills/design-swag-identity/SKILL.md): one
accent, the 45 degree cut on repeated elements, hairline tables, both palettes, no script.
