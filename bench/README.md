# The Swag Performance Benchmark

This directory answers one question over time: **is the compiler getting better?**

```
tools\bench.bat --label "what changed since last time"
```

That rebuilds `swc.exe` in Release, measures it against every other toolchain, appends the
result to `history.json`, and regenerates `bench.html`. Nothing else is needed.

| | |
|---|---|
| `tools\bench.bat --quick` | one sample, no warm-up; proves the plumbing works and is **not** recorded |
| `tools\bench.bat --report-only` | rebuild the normalized history and page from raw campaigns, measure nothing |
| `tools\bench.bat --no-build` | measure the binary already in `bin/`, useful when iterating on the harness |
| `py driver.py --tasks chacha --quick` | sweep one task while working on it; a partial sweep is **never** recorded |

A full campaign takes roughly twenty minutes: a ninety-second warm-up, the NativeAOT
publishes, and CPython on the two rescaled tasks. It will not start while something else
is using the machine, and it throws itself away if something starts halfway through — so
run it and leave the machine alone, rather than run it and work beside it.

## What is measured

Seven programs, written by hand and identically in swag, C++, Rust, Swift, C#, JavaScript, Lua
and Python. None of them uses a standard library container: each reimplements its own hash
map, heap or matrix, so the benchmark measures the compiler rather than somebody's hash
table. `chacha` is the one written against a published specification rather than invented
here: the same ChaCha20 rounds every port implements word for word, which is what makes it a
fair reading of 32-bit lane arithmetic and of whatever each compiler does with it. Every port prints the same checksum, and **a campaign that reports a checksum mismatch
has measured nothing** — fix the ports before believing any number.

Fourteen runtimes in total: swag native and JIT in both configurations, two C++ compilers,
Rust, Swift, C# ahead-of-time and jitted, V8, LuaJIT, Lua and CPython.

## The rules that keep the numbers honest

Every one of these was measured, on the ratio between two binaries that never change —
the only thing this bench is entitled to claim. Every one of them moved that ratio.

**Helper processes are reaped.** Compilers leave children behind — 46 orphaned `cl.exe` once
accumulated over a single campaign and loaded the machine enough to make the next run up to
2.4 times slower. `winproc.run` puts every child in a job object and terminates it after the
wait. Do not bypass that.

**Timed runs are pinned to the performance cores.** This machine is a hybrid: six P cores,
eight E cores, two low-power cores. Left to the scheduler, a short process lands on the wrong
kind of core often enough to move the ratio between two unchanged binaries by 10 % from one
block of measurements to the next; pinned, by 2 %. The mask is derived from the machine
through `GetSystemCpuSetInformation`, never hardcoded, and is one logical processor per
physical P core — pinning to a *single* core was measured to be worse on both counts, since
it is not the favoured core and its ratio is no steadier. Builds are never pinned: they are
meant to use the whole machine.

**Repetitions are interleaved, and the order rotates.** Repetition 0 of every runtime, then
repetition 1, keeping the minimum. Grouped per runtime, a slow stretch of machine time lands
entirely on one language and invents a result. And with a *fixed* order inside the cycle, the
runtime listed first is always measured at the same point of the machine's thermal ramp, which
is a systematic advantage rather than a result — so the cycle rotates.

**Samples are budgeted, not counted.** Each runtime is sampled until it has spent
`RUN_BUDGET_MS` of measured time on that task, between 3 and 24 samples, and 2 when a single
sample already runs longer than twenty seconds. A 50 ms task gets 24 samples where CPython
gets 3. The samples of a runtime are spread evenly over the whole window rather than bunched
at one end, so every runtime covers the same minutes whatever its sample count. Five fixed
repetitions gave a ratio spread of 10 %; the budget gives 2 %, and costs less, because the
five repetitions were being spent on CPython where they bought nothing.

**Every sample is kept**, not only the minimum that becomes the result. A campaign that cannot
say how sure it is has not measured anything.

**The machine has to belong to the campaign.** Two gates, because the first one alone was not
enough:

*Before it starts*, the driver samples system-wide CPU with `GetSystemTimes`. Nothing of ours
is running, so whatever it reads is somebody else's. It waits for three consecutive seconds
under 15 % and refuses to measure at all if the machine stays busy for five minutes. Waiting a
minute is cheaper than discovering the contention twenty minutes later.

*While it runs*, a fixed reference workload is timed before every task and at both ends of the
sweep. Each probe is compared with its **neighbours in time**, not with the whole timeline: a
campaign settles as it runs, opening warmer than it ends, and that ramp moves a task's Swag
measurement and its controls together, which is what the per-task correction exists for. A
visitor behaves differently — it arrives, hits one task, and leaves. When a probe departs from
its neighbours by more than 40 % the campaign goes to `results/rejected/` and never enters the
history, kept because deleting a measurement one dislikes is how a benchmark starts lying, but
not published.

Endpoints alone were not enough, and that is not hypothetical: a build launched from another
window multiplied *every* compilation of `raytrace` by ten — clang-cl went from 408 ms to
4351 ms — and was over before the closing calibration ran. The campaign read clean from both
ends and was fiction in the middle. Against that timeline the neighbour test reads 950 %, where
a clean campaign reads 14 to 23 %.

Never present two half-campaigns measured at different moments side by side: the gap between
them is machine noise, not a result.

## The protocol number

`history.PROTOCOL` states how a campaign was measured. Campaigns of different protocols are
not comparable and never share a history: `load_results` reads only the current one, and the
earlier campaigns sit in `results/protocol1/`, kept as evidence and read by nothing.

Protocol 1 took five repetitions on whatever core the scheduler chose, with `sha256` on
512 KiB and `chacha` on 1 MiB. Those two ran in 3.5 and 1.9 ms, where the resolution of the
machine is ±10 % and ±27 % — they were measuring the machine. Both were scaled sixteenfold,
which changes their checksum and therefore resets their history; that is the price of the two
tasks meaning anything at all. **Raise the protocol number whenever a change makes new
campaigns incomparable with old ones**, and move the old campaigns aside in the same commit.

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
So are the three headline ratios: they compare Swag with runtimes measured in the same
campaign, so the machine cancels out of them and they are recorded uncorrected.

## What the bench can actually see

The correction is not perfect, and the page says by how much. Every control is passed through
the whole correction as if it were the compiler under test, corrected by the median of the
*other* controls so it cannot flatten itself. Its code never changes, so it should read exactly
1.00; the spread it reads instead is the resolution of the harness, drawn as a grey band behind
every history curve. **A movement smaller than that band has not been measured** — no matter how
convincing it looks.

Under protocol 1 that band was Â±4 % on the execution index and Â±20 % on the compilation index,
and per task it tracked the duration of the task: Â±6 % on `wordfreq` (78 ms) against Â±27 % on
`chacha` (1.9 ms). Two protocol 2 campaigns of one byte-identical `swc.exe` give Â±2.4 % on the
execution index and Â±10.5 % on the compilation index, and the compiler itself reads â0.2 % between
them â the right answer being zero. `chacha` went from Â±27 % to Â±3.4 %.

Two cautions on those figures. They come from **two** campaigns, so each is one observation
where the protocol 1 numbers were the median of fifteen; and **compilation is still the weak
half** at Â±10.5 %, because a build is dominated by file system work that repetition averages
badly. Read a movement of the compilation curve below about 10 % as nothing at all.

This is also why an optimization that an A/B on one machine within the same minute shows clearly
can leave no trace here: a campaign compares two moments hours or days apart, and the A/B does
not.

The journal carries a second, different number. **The sample spread** is a runtime against
itself *inside* one campaign; the band is what separates two campaigns. A quiet campaign with a
wide band means the bench is blunt; a noisy campaign means the machine was not quiet, and its
point deserves less trust than its neighbours.

## A task added after the baseline

The baseline is fixed, so a task added later has no baseline value and cannot be indexed against
it. It is indexed instead against the first reproducible campaign that measured it, which reads
1.00, and the page names that campaign under the task. Aggregates — the geometric index, the
corrected geometric millisecond, the headline ratios — deliberately ignore such a task until it
is present in the baseline: including it would step the aggregate on the campaign it first
appeared in, and that step would read as a compiler movement.

The files under `results/` are authoritative. `history.py` rebuilds every compact entry from
those raw campaigns whenever the report is generated, so normalization changes can be applied
retroactively without altering a measurement.

A campaign measured on a modified working tree is recorded with `dirty: true` and marked with
an asterisk in the report, because its commit alone will not reproduce it.

## Files

| | |
|---|---|
| `../tools/bench.bat` | the entry point |
| `campaign.py` | rebuild, measure, report |
| `driver.py` | the sweep itself |
| `toolchains.py` | where each toolchain lives and how it builds a task |
| `winproc.py` | process timing, peak memory, core pinning, and how busy the machine is |
| `history.py` | the compact, normalised record |
| `mkpage.py`, `page_template.html` | the report; every figure comes from JSON, never from an edit |
| `results/` | one raw campaign per file, kept whole so a past number can be re-derived |
| `src/` | the seven tasks in every language |

## After a campaign

The repository [README](../README.md) quotes one campaign in full — both tables and the four
ratios that follow them. Those numbers are hand-copied, so a campaign that moves them is only
half recorded until the README is refreshed from the new `results/` file and its stamp updated.

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
