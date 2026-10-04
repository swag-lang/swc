# The Swag Performance Benchmark

This directory answers one question over time: **is the compiler getting better?**

Run these commands from the checkout root. The examples cap compiler workers at six;
the campaign and standalone drivers use the compiler's default worker count when
`--swc-cores` is omitted or zero.

```powershell
bin\swc.exe --num-cores 6 tools\bench.swgs --swc-cores 6 --label "what changed since last time"
```

That rebuilds `swc.exe` in Release, measures it against every other toolchain, appends the
result to `history.json`, and regenerates `bench.html`. Each campaign owns a build directory
under `%LOCALAPPDATA%/swc-bench-builds`, including its compiler, runtime sources and MSBuild
intermediates. This lets the script's original compiler stay running while the fresh compiler
is linked and measured. The standard library comes from this checkout's `bin/` through
`SWAG_PATH`. The private build is removed after measurement, including on build or measurement
failure. MSBuild and C++ compilation are capped at six workers.

| | |
|---|---|
| `bin\swc.exe --num-cores 6 tools\bench.swgs --quick --swc-cores 6` | one sample, no reference warm-up; proves the plumbing works and is **not** recorded |
| `bin\swc.exe --num-cores 6 tools\bench.swgs --build --swc-cores 6` | measure compiler time only; execution is skipped, and only compilation series are added to the history and report |
| `bin\swc.exe --num-cores 6 tools\bench.swgs --run --swc-cores 6` | measure program execution only; AOT programs are built outside the clock, and only execution series are added to the history and report |
| `bin\swc.exe --num-cores 6 tools\bench.swgs --report-only` | rebuild the normalized history and page from raw campaigns, measure nothing |
| `bin\swc.exe --num-cores 6 tools\bench.swgs --no-build --swc-cores 6` | measure the binary already in `bin/`, useful when iterating on the harness |
| `py -3 bench/driver.py --tasks chacha --quick` | sweep one task while working on it; a partial sweep is **never** recorded |
| `py -3 bench/driver.py --tasks chacha --quick --swc-cores 6` | cap every Swag compiler started by the sweep at six workers |
| `py -3 bench/compile.py --against "C:\path\outside-checkout\baseline\swc.exe" --swc-cores 6 --admit` | A/B the edit-build loop between two compilers, order alternated; records nothing |
| `py -3 bench/compile.py --swc-cores 6 --admit` | measure with an explicit worker cap and shared-machine admission before every compiler invocation; records nothing |

Most of a campaign is spent on the controls, not on swc: the NativeAOT, Swift and Zig
builds, and CPython and Lua on the longer tasks. Those are measured once or a few times; swc
gets the samples. Before a recorded measurement, the driver waits for three consecutive CPU
samples below 15%, then performs the normal 30-second reference warm-up. Reference and
build-control checks reject campaigns with detected interference; they cannot prove that no
other process ran. Use a quiet machine and leave it undisturbed for the sweep. `--quick` skips
the idle gate and reference warm-up and writes no benchmark history.

## What is measured

Twelve equivalent workloads in Swag, C++, Rust, Zig, D, Odin, Go, Swift, C#, Java,
JavaScript, Lua, Python, PHP and Ruby: `wordfreq`, `csvagg`, `sha256`, `dijkstra`, `raytrace`, `leven`, `chacha`, and
since 2026-09-29 `nbody` (f64 physics over an array of structs), `fannkuch` (permutations of
small arrays), `binarytrees` (one heap allocation per node), `lz77` (hash-chain compression
and decompression) and `sort` (a specified quicksort on signed indices). Systems-language ports
use explicit byte maps, heaps and sorting. Dynamic ports also use their runtime's containers
and key sorting for `wordfreq` and `csvagg`; those results include that implementation choice.
All ports implement the numeric kernels themselves, including SHA-256 and ChaCha20, without
delegating them to a native cryptography library. `chacha` is
the one written against a published specification rather than invented
here: the same ChaCha20 rounds every port implements word for word, which is what makes it a
consistent reading of 32-bit lane arithmetic and of whatever each compiler does with it. Every port prints the same checksum, and **a campaign that reports a checksum mismatch
has measured nothing** — fix the ports before believing any number.

Compilation times measure a complete command from source to a runnable artifact, including the language's
usual startup code, selected imports, header parsing, optimization and linking. The programs match
in observable behavior and algorithm; they do not make the compilers process an equal amount of
library source. For example, Swag's `Swag.print` is built in, Rust uses `std`, C++ parses CRT and
Windows headers, and D and Odin import runtime packages. The shared C++ header even includes
`<cmath>` for tasks that do not use it. A ratio across languages is therefore a
ratio of these particular build recipes, not an isolated ratio of compiler front-end speed.
The report's compilation speedup takes the fastest non-Swag build time for each task, divides
it by Swag release build time, then takes the geometric mean of those ratios. Every task has
equal weight, regardless of its duration. A value of 2x means Swag builds twice as fast on
average; 1x means parity; below 1x means Swag is slower. Every Swag mode is excluded from the
reference, and the fastest competitor can differ by task. All other build configurations,
including bytecode generation, participate if they have valid times for every displayed task.
The headline uses the latest accepted build campaign and all displayed tasks. Rankings show
the winner's time in milliseconds, followed by each other runtime's time / winner time;
2 means twice as slow. Execution rankings use the same display within each runtime group.
Charts and the detailed raw-time matrices keep milliseconds. The separate `hello` workload
is excluded from the aggregate.
The `hello` column is a separate small program with a different import set; it is useful as a
second data point, but subtracting it from a task does not remove library overhead reliably.
For a compiler improvement claim, `py -3 bench/compile.py --against <external-baseline-swc>` compares two compiler
binaries back to back on the same checkout. Both receive identical sources and imports, and the
order alternates each round. This is a tighter comparison than a cross-language build ratio.
Keep preserved compiler binaries outside the checkout and configure each one's runtime and
standard-library resources explicitly. A baseline comparison needs the intended source and
resource versions as well as the executable.

Twenty-two runtime configurations in total: Swag native and JIT in both configurations, two C++
compilers, Rust, Zig, D through LDC, Odin, Go, Swift, C# ahead-of-time and jitted, Java HotSpot,
V8, LuaJIT, Lua, CPython, PHP interpreted and tracing JIT, and Ruby interpreted.

Go uses the standard optimizing `go build` recipe, with `-a` and a fresh private `GOCACHE`:
the timing includes rebuilding its standard-library dependencies. Bounds checks remain enabled
and may be eliminated by the compiler. Java uses `javac` followed by HotSpot's default tiered
JIT, with bounds checks and garbage collection enabled. Its build result is bytecode, not a
native executable; artifact size sums all generated class files and excludes the installed JVM,
just as the C# IL size excludes .NET. See the [Go build options](https://pkg.go.dev/cmd/go)
and [Java launcher documentation](https://docs.oracle.com/en/java/javase/25/docs/specs/man/java.html).

PHP runs with a clean configuration (`-n`), no memory limit, and no optional extensions in the
interpreted row. The JIT row explicitly loads OPcache, enables it for CLI, reserves a 64 MiB
JIT buffer and selects tracing; it refuses to run if the JIT is inactive. Ruby uses its
interpreter with gem startup disabled; it does not claim a YJIT measurement on Windows.
Both retain their normal array and object checks. The
[PHP OPcache options](https://www.php.net/manual/en/opcache.configuration.php) document the JIT switches.

Every execution sample starts a fresh process, including Java and PHP JIT. Input generation is
outside `MS`; JIT compilation triggered by the timed kernel is inside it. These are short-lived
program measurements, not warmed, long-running server throughput. Swag JIT compiles the kernel
before entering its timer; the existing wall-time and hello measurements also expose startup.
Garbage-collected runtimes retain their normal collection policy, including collections during
the timer; the harness does not force a collection after every tree.

Zig, D and Odin also have hello-world programs for a small-program build measurement. Their release recipes
are `zig build-exe -O ReleaseFast -target x86_64-windows-msvc -lc`,
`ldc2 -O3 -release -boundscheck=off`, and `odin build -file -o:speed`.
Zig and D disable bounds checks in these configurations. Odin retains its default checks on
fixed arrays; raw allocated pointers carry no bounds, as in the C++ ports. All three use the
CRT allocator and Windows performance counter. D does not use garbage-collected containers.

Each Zig build clears its private local and global caches to measure a fresh compilation,
including the standard-library code it needs, rather than retrieving a previously linked binary.
The MSVC target uses the installed Windows SDK and runtime libraries instead of building a
separate MinGW C runtime. Every available language is remeasured on every campaign.

The Swag ports use the standard Win32 module for the same platform services that the C++, D and
Odin ports import. The campaign publishes Win32 in `release` and `devmode` once before any timed
sample, then passes its published `kernel32.swg` API directly to every Swag command. A Swag build therefore
measures consuming the already-built API, never loading a benchmark module setup and never checking
or compiling the dependency's source workspace inside the timed command. Only the published
`kernel32.swg` interface is passed because the benchmark uses only the performance counter, just
as the Zig port declares only those native entry points.

## The edit-build loop

The tasks and the hello world price a compiler on a small program. None of them
contains what an edit-build loop costs a person, so the campaign also measures the compiler
under test on the repository's own sources — what the tools in `../tools` actually run:

| workload | command | what it isolates |
|---|---|---|
| `core_rebuild` | `swc build --workspace bin/std -m core --rebuild` | the complete core module from source, through every compiler stage |
| `core_noop` | the same, right after it, nothing changed | the up-to-date check and whatever runs before it |
| `core_touch` | the same, after one file's write time moved | what one save costs — today, the whole module again |
| `hello_build` | `swc build -f hello.swg` | a small program, source to linked executable |
| `doc_std` | `swc doc --workspace bin/std --doc-output-dir bench/out/doc --rebuild` | the standard library's documentation, into `bench/out/doc` |
| `format_tree` | `swc format -d bench/out/format` | the fixed baseline source trees in `toolchains.FORMAT_TREES`, on a private copy with their `.swc-format` configuration |

The formatting benchmark keeps its baseline tree selection: the six `bin` workspaces,
`tools`, `bench/src`, and `bin/help/tools`. The maintenance tool additionally formats
each dedicated benchmark's `module.swg` and `src`. Those extra modules and historical
sources under `bench/results` are outside this timed workload.

Each workload is prepared outside the clock: outputs are removed, a warm build is made,
a source write time is advanced, or sources are mirrored as needed. Every sample is kept
and the minimum is reported. Compiler processes are not pinned. By default they use the
compiler's own worker count; `--swc-cores N` supplies an explicit cap, including for
untimed preparation builds.

Memory has two separate meanings: `peak_bytes` is the peak committed memory of the process
tree, including compiler helpers; `peak_working_set_bytes` is the timed process's peak resident
memory, reported by Windows after it exits. The edit-build history preserves both as `peak_mb`
and `peak_working_set_mb`, without adjusting them by the timing context. Older campaigns have no
resident-memory measurement; their committed-memory values are never substituted for it.

In the history each workload is corrected by the campaign's compilation context, exactly as
the tasks are, and indexed against the first clean campaign that measured it. The three
`core` workloads build `bin/std` in place, in `devmode`, which leaves that module built the
way `std.swgs` would leave it.

Between campaigns, `compile.py` answers the round-by-round question: it runs the same
workloads on one compiler, or on two with the order alternated every round, and reports the
median of the per-round ratios beside the minimums — a pair measured back to back shares the
machine's drift, where two minimums taken minutes apart do not.

## The allocator

The execution phase also measures the Swag runtime allocator against the vendored
[mimalloc](../src/Support/Memory/mimalloc/readme.md), compiled with MSVC `/O2`, and against the C
runtime heap. One Swag program, `allocator/src/allocbench.swg`, and one C program,
`allocator/src/allocbench.c`, run the same fourteen workloads: one block allocated and freed,
binary trees, a 50 000-block mixed-size churn, 4-64 KiB and 64 KiB-1 MiB live sets, buffers
doubled by reallocation, a few live blocks of many sizes, a live set growing to four million
blocks, the churns again on four threads, and
producer/consumer pairs whose frees are all remote. The Swag program allocates through
`Memory.alloc` and `Memory.free`, the path ordinary code takes, so its time includes the
context lookup and the interface call; its peak working set includes the `core` module it
imports.

Each workload runs in a fresh process pinned to the performance cores, five rounds with the
three executables in rotating order, and the section keeps the median of each. The
competitors are measured in the same rounds, so Swag's ratio to each needs no machine
correction: the history follows the geometric mean of those ratios, for time and for peak
working set, and the page draws how they move from campaign to campaign. A workload that one
implementation failed is left out of the means.

Between campaigns, `allocator/run.py` measures the same thing without recording it, and
`--against` adds a column for an executable built with an earlier runtime.

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

**Samples are budgeted, not counted.** Each Swag runtime is sampled until it has spent
`RUN_BUDGET_MS` of measured time on that task, between 3 and 16 samples. A control only
feeds the machine correction, a median over more than a dozen controls, so it gets
`CONTROL_RUN_BUDGET_MS`, between 2 and 6 samples. A run longer than `RUN_SLOW_MS` keeps its
pilot sample alone: CPython and Lua on the long tasks are measured once. Builds follow the
same split, and a build longer than `BUILD_SLOW_MS` (NativeAOT, Swift, the documentation) is
done once. The samples of a runtime are spread evenly over the whole window rather than
bunched at one end, so every runtime covers the same minutes whatever its sample count. Five
fixed repetitions gave a ratio spread of 10 %; a budget gives 2 %, and costs less.

**Every sample is kept**, including each compiler build, not only the minimum that becomes the
result. Earlier campaigns recorded only build minima, so their within-campaign build spread
cannot be reconstructed.

**The machine has to belong to the campaign.** Two gates, because the first one alone was not
enough:

*Before it starts*, the driver samples system-wide CPU with `GetSystemTimes`. Nothing of ours
is running, so whatever it reads is somebody else's. It waits for three consecutive seconds
under 15 % and refuses to measure at all if the machine stays busy for five minutes. Waiting a
minute is cheaper than discovering the contention twenty minutes later.

*While it runs*, a fixed execution reference workload is timed before every task and at both ends of the
sweep. Each probe is compared with its **neighbours in time**, not with the whole timeline: a
campaign settles as it runs, opening warmer than it ends, and that ramp moves a task's Swag
measurement and its controls together, which is what the per-task correction exists for. A
visitor behaves differently — it arrives, hits one task, and leaves. When a probe departs from
its neighbours by more than 40 % the campaign goes to `results/rejected/` and never enters the
history, kept because deleting a measurement one dislikes is how a benchmark starts lying, but
not published.

That execution probe cannot detect interference limited to compilers. Before publication, the
driver also compares each unchanged compiler control's geometric build-time movement with the
previous accepted build campaign, over the tasks both campaigns measured. If the upper and lower quartiles
differ by more than 25 %, the campaign is archived under `results/rejected/`. On 2026-09-25,
MSVC, clang-cl, Rust, D and Odin slowed by 40–65 % between two unchanged-code campaigns while
Zig and .NET stayed near their previous times; the old execution probe accepted this split and
the displayed MSVC/Swag build ratio jumped from 2.3 to 3.9. The build control check catches it.
The two split campaigns measure about 54 % by this check; adjacent accepted nine-control
campaigns around them stay below 10 %.
The split campaigns `20260924-172317` and `20260925-055026` are preserved in
`results/rejected/`; neither contributes to the published history. The first campaign and
campaigns with fewer than six matching controls have no such comparison.

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
runtime's ratio to that baseline and takes their logarithmic median, using only runtimes measured
in both campaigns. That is the context factor. A Swag time is divided by the factor before
it enters the history.

The correction is per task because the machine can warm up during a sweep, and execution and
compilation get separate factors. The median makes the result insensitive to one noisy runtime
or one independently upgraded toolchain. `history.json` records the factors, control counts,
and median dispersion so the correction remains auditable. A context factor below one means
the controls ran faster than at baseline, so the raw Swag value is raised before comparison.

Compiler memory is the exception. It does not drift with machine state, so it is plotted raw.
The execution and build headline ratios compare runtimes within one accepted campaign. Both
use geometric means, but execution reports Swag time / fastest time (lower is better), while
compilation reports fastest non-Swag time / Swag time (higher is better). Neither is an index
against a historical compiler baseline. Machine correction remains in the history's time and
index curves. A cross-language build ratio can still move with machine effects on different
compilers; read compiler progress from those corrected curves and their resolution bands.

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
1.00, and the page names that campaign under the task. History aggregates and history headline
ratios retain the baseline's fixed task panel. The current report's matrices and headline ratios
instead cover the tasks measured by both selected latest build and execution campaigns.

The files under `results/` are authoritative. `history.py` rebuilds every compact entry from
those raw campaigns whenever the report is generated, so normalization changes can be applied
retroactively without altering a measurement.

A campaign measured on a modified working tree is recorded with `dirty: true` and marked with
an asterisk in the report, because its commit alone will not reproduce it.

## Files

| | |
|---|---|
| `../tools/bench.swgs` | the entry point |
| `campaign.py` | rebuild, measure, report |
| `driver.py` | the sweep itself |
| `compile.py` | the edit-build loop alone, on one compiler or A/B between two; records nothing |
| `allocbench.py`, `allocator/` | the allocator against mimalloc and the C heap; `allocator/run.py` records nothing |
| `toolchains.py` | where each toolchain lives and how it builds a task |
| `winproc.py` | process timing, peak memory, core pinning, and how busy the machine is |
| `history.py` | the compact, normalised record |
| `mkpage.py`, `page_template.html` | the report; every figure comes from JSON, never from an edit |
| `results/` | one raw campaign per file, kept whole so a past number can be re-derived |
| `src/` | the tasks in every language |

## After a campaign

`mkpage.py` also refreshes an optional repository `README.md` when it contains `bench:begin`
and `bench:end` markers, using the same campaign as the report. That block is generated and
should not be edited by hand.

`bench.html` carries measurements, not commentary: one matrix per measure with a task per row,
charts for the aggregates, and one history row per task. A new task adds a row everywhere and
nothing else; explanations belong in this file.

The legend at the top defines the coloured letter badges used in matrix headers and rankings.
A language keeps its letter across modes; each runtime configuration keeps a distinct colour.
Letters prefer the language's initial, with stable alternatives where initials collide. Full
names and modes remain available as tooltips and accessible labels. Only runtimes measured in
the selected campaigns appear: adding support never inserts invented values into old results.

## Extending it

- **A new task**: add it to every language under `src/`, then to `TASKS` in `toolchains.py`
  and its one-line description to `TASK_INFO` in `mkpage.py`. It must print `CHECK=<n> MS=<f>` and exclude data generation from the timed
  section. Confirm every port agrees on the checksum before recording anything.
- **A new language**: add its recipe in `toolchains.py` and its id to the order lists in
  `driver.py` and `mkpage.py`. Give it the release settings its users would ship, document its
  bounds-check policy, and verify every checksum with `--quick` before recording a campaign.
- **Never change what a task computes.** That silently resets the history, because the past
  numbers stop describing the same work.

## Requirements

MSVC and clang-cl come from Visual Studio; the others are looked up under the user profile.
Any of them can be overridden when it lives somewhere unusual: `BENCH_VS_ROOT`, `BENCH_RUSTC`,
`BENCH_DOTNET`, `BENCH_SWIFTC`, `BENCH_SWIFT_ROOT`, `BENCH_NODE`, `BENCH_LUA`, `BENCH_LUAJIT`,
`BENCH_PY`, `BENCH_ZIG`, `BENCH_LDC2`, and `BENCH_ODIN`. The standalone `driver.py`,
`compile.py`, and `allocator/run.py` also accept `BENCH_SWC`; their explicit `--swc` argument
takes precedence. A campaign selects its private Release build, or this checkout's `bin/swc.exe`
with `--no-build`, independently of `BENCH_SWC`.
The added runtimes accept `BENCH_GO`, `BENCH_JAVAC`, `BENCH_JAVA`, `BENCH_PHP`,
`BENCH_PHP_OPCACHE` (the OPcache DLL), and `BENCH_RUBY`.
Zig, LDC and Odin are discovered through their override first, then `PATH`, then the
per-user installations at `%LOCALAPPDATA%\Programs\Zig\zig.exe`,
`%LOCALAPPDATA%\Programs\LDC\bin\ldc2.exe`, and `%LOCALAPPDATA%\Programs\Odin\odin.exe`.
Extract each complete compiler distribution into that directory, keeping its libraries and
support files beside it. Point each override at its compiler executable.
The new ports have been checked with Zig 0.15.2, LDC 1.43.0 and Odin dev-2026-09.
Go, Java, PHP and Ruby also use `PATH` and portable distributions under
`%LOCALAPPDATA%\Programs`: `Go\bin\go.exe`, `Java\bin\javac.exe` and `java.exe`,
`PHP\php.exe` with `PHP\ext\php_opcache.dll`, and `Ruby\bin\ruby.exe`.
Go additionally checks `C:\Program Files\Go`; Java respects `JAVA_HOME` and prefers the
runtime beside the selected compiler. Java needs both executables; a missing OPcache DLL
skips only PHP JIT. No runtime is downloaded by a benchmark campaign.
These ports have been checked with Go 1.27.1, Temurin 25.0.4.1, PHP 8.4.26 and Ruby 4.0.7.
Visual Studio's x64 build tools and clang-cl are required for the build environment and reference
calibration. Other missing toolchains are named and skipped, and the report records which ones
were absent.

The page follows [design-swag-identity](../.agents/skills/design-swag-identity/SKILL.md): one
accent, the 45 degree cut on repeated elements, hairline tables, both palettes, no script.
