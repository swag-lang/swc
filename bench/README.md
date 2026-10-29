# The Swag Performance Benchmark

This directory answers two questions, and states how sure it is of each answer:

1. **How does Swag compare with other languages** on the same programs, compiled and run on
   the same machine in the same hour?
2. **Is the Swag compiler getting faster**, and are the programs it produces?

Every published number is a median with a 95 % confidence interval, and every comparison is a
ratio with one. A difference is called a difference only when its whole interval lies on one
side of parity. Everything else on this page explains how the samples behind those intervals
are taken so that they mean something.

## Running it

From the checkout root:

```powershell
tools\bench.bat --label "what changed"   # a full campaign, recorded
tools\bench.bat --quick                  # one sample of everything, recorded nowhere
tools\bench.bat --report-only            # rebuild history.json and bench.html
tools\bench.bat --no-build               # measure bin\swc.exe without building it
tools\bench.bat --build                  # compilation only
tools\bench.bat --run                    # execution only
```

`tools\bench.bat` runs `campaign.py`, which builds the Release compiler with `tools\release.bat`,
runs `driver.py` and regenerates the report with `mkpage.py`. A full campaign takes about forty
minutes on the benchmark laptop and needs it plugged in and otherwise idle. Other entry points:

| | |
|---|---|
| `py -3 bench/driver.py --tasks sort,nbody --out C:\tmp\c.json` | a partial sweep while working on one task; written to the file, never recorded |
| `py -3 bench/driver.py --quick --tasks sort --no-reference` | the plumbing alone, without the reference |
| `py -3 bench/reference.py show` / `verify` / `freeze NAME` | the frozen reference compiler, see below |
| `py -3 bench/compile.py --against C:\baseline\swc.exe --swc-cores 6` | A/B of the edit-build loop between two compilers, records nothing |
| `py -3 bench/microdiff.py --base C:\baseline\swc.exe` | which functions and loops of the tasks two compilers generate differently |
| `py -3 bench/allocator/run.py` | the allocator section alone |
| `python -B -m unittest discover -s bench` | the harness's own tests, on synthetic data |

`compile.py`, `parsecache.py` and `cachecheck.py` are investigation tools that record nothing;
their usage is in their own headers. `compile.py --only core_delta --machine-archive <path>` warms
the standard-library machine-code archive, seeds the supplied archive, then measures `core` after
one function changes against the restored archive.

`tools/bench.bat --out <path>` (or `driver.py --out <path>`) also preserves completed sections and tasks between measurements.
These checkpoints carry `incomplete: true` until the campaign finishes and are never published
as accepted campaigns. A command error keeps its complete report in the log and raw output.

For every generated-code optimization batch, run `microdiff.py --verbose` over all twelve tasks
against a preserved pre-change compiler. This rebuilds each task once per compiler with isolated
temporary caches and executes it once to check its checksum; it takes no timing samples. Review
changed hot loops, frame traffic, calls and dependencies, including equal-count changes and
added/removed functions. Use `--save-dir C:\tmp\micro-review` to retain both listings and build
outputs in a new directory. Static counts flag possible losses; they do not establish runtime
performance. Long timing campaigns belong at campaign milestones.

## What a campaign measures

Twelve workloads written in every language, each printing the same checksum:

| task | what it exercises |
|---|---|
| `wordfreq` | a hash table over 2 M words, then sorting |
| `csvagg` | 400 k rows parsed byte by byte, floating-point arithmetic |
| `sha256` | 8 MiB, integer arithmetic and rotations |
| `dijkstra` | 800 by 800 grid, binary heap |
| `raytrace` | 480 by 360, f64, recursion |
| `leven` | 40 queries against 6000 words |
| `chacha` | 16 MiB keystream, ChaCha20 rounds word for word from the specification |
| `nbody` | 5 bodies, 500 k steps, f64, sqrt, array of structs |
| `fannkuch` | fannkuch-redux N = 9 |
| `binarytrees` | depth 12, one allocation and one free per node |
| `lz77` | 1 MiB, hash-chain compression and decompression |
| `sort` | 300 k integers, median-of-three quicksort |

Every port implements the kernels itself, including SHA-256 and ChaCha20. Systems-language
ports use explicit byte maps and sorting; dynamic ports use their runtime's containers for
`wordfreq` and `csvagg`. **A campaign in which a port fails or disagrees on a checksum is not
recorded**: it has measured nothing.

Twenty-two runtime configurations: Swag release and devmode, native and on its JIT; C++ with
clang-cl and MSVC, Rust, Zig, D (LDC), Odin, Go, Swift, C# NativeAOT and CoreCLR, Java HotSpot,
Node (V8), LuaJIT, Lua, CPython, PHP interpreted and with its tracing JIT, Ruby.

Each campaign also measures:

- `hello`: a small program built by every compiler, and the time to its first output on every
  JIT and interpreter;
- the edit-build loop of the compiler itself (below);
- the Swag allocator against mimalloc and the C runtime heap (below).

## The protocol

Protocol 3 replaced protocol 2 on 2026-10-21. Protocol 2 kept the fastest sample of each
series and corrected Swag's numbers between campaigns by the median movement of the other
languages. That correction did not hold: across 52 campaigns Swag's build time followed the
other compilers' movements with an elasticity of 0.29, so when the machine moved them by 25 %,
the corrected Swag value jumped by 20 % with no change in the compiler. Every rule below
exists because something like that was measured.

### 1. Progress is a paired ratio against a frozen reference

The question "did the compiler get faster" is never answered by comparing two campaigns.
A frozen Swag compiler, the **reference**, is measured in every campaign next to the compiler
under test: in every round each Swag runtime is sampled back to back with its reference
counterpart, in a random order. Progress is the median of those per-round ratios, per task,
and their geometric mean over the panel. Whatever the machine does that hour, both members of
a pair see it, so no correction is needed and none is applied.

The reference is a complete installation (compiler, runtime, standard library sources and the
Swag task sources as of its commit) kept outside the checkout, in
`%LOCALAPPDATA%\SwagBench\references\<name>` (`BENCH_REFERENCE_ROOT` overrides it). Its digests
are committed in `reference.json`, and every campaign verifies them byte for byte before
measuring. `py -3 bench/reference.py freeze <name>` freezes `bin\swc.exe` with the runtime,
library and task sources taken from the HEAD commit, not from the working tree, so other
sessions' uncommitted edits cannot leak into it. A reference is never overwritten: a new one
gets a new name and starts a new progress series. On another machine, rebuild the reference's
commit and freeze it under the same name; the digests then say whether it is the same compiler.

Since the reference carries its own sources, it keeps compiling the programs it was frozen
with after the current sources move on. Progress therefore compares the compiler and its
library as a product; tasks whose Swag source changed in substance should start a new
reference.

### 2. Swag is measured from a private installation

Other sessions rebuild `bin\swc.exe`, edit `bin\runtime` and `bin\std`, and share the
compiler's machine-code cache under `%TEMP%\swag`. Any of those during a sweep changes what is
measured without changing what is recorded. A campaign therefore starts by copying the
compiler, its runtime and its library into `bench\out\installs\subject` and measures that copy,
with its own temporary folders. The compiler finds its runtime and library beside itself.

### 3. A warm toolchain and a clean project, for every language

Each recipe is built once outside the clock. Every timed sample then starts from the same
state: the project's outputs removed, and the toolchain's own caches restored to what that
warm-up left. That is the state of a developer who built something before and now builds this
project from scratch.

| toolchain | toolchain state restored before every sample | project state |
|---|---|---|
| Swag | the machine-code cache of the runtime and imported APIs | output folder removed |
| Go | a build cache holding only the standard-library packages the task imports | executable removed; `go build` without `-a` |
| Zig | the global cache (compiler_rt, libc bindings) | local cache and output removed |
| C# | NuGet packages (machine-wide) | `bin` and `obj\Release` removed |
| Swift, Rust, C++, D, Odin, Java | nothing to restore: their libraries ship precompiled or are parsed every time | outputs removed |

Restoring a snapshot instead of letting a cache evolve matters for Swag in particular: its
machine-code cache key depends on the order in which the compiler's workers finish, so two
identical builds can still add entries, and a cache left to grow across samples makes every
sample a little different (measured 2026-10-21: an archive grown to 20 MB added 20 MB of peak
memory and 12 to 15 % of time to a devmode build).

### 4. Every sample is checked for interference

Two cores of somebody else's work slow a pinned run of the reference workload by 17 %; eight
cores, by 150 % (measured 2026-10-21; the power budget and the turbo frequency are shared). A
check before the campaign cannot see a build another session starts ten minutes later. Each
sample therefore measures the CPU the rest of the machine used while it ran: total busy time
of every processor, minus the CPU of the job running the sample, minus the driver's.

Launching a process is not free for the rest of the machine either: on the benchmark laptop a
burst of pinned 40 ms runs kept about three more performance cores busy outside the job, the
antivirus, event-tracing collectors and the editor reacting to every process start. That load
comes with our own launches, so each family of measurements (builds, runs, hello, loop) keeps a
running median of its readings, and a sample is **contended** when it reads more than
2.5 cores above that median. A contended sample is set aside, the driver waits up to 15 s for
two quiet seconds, and the sample is taken again, up to four times. A sample still contended after
that is kept and flagged; a campaign with more than 5 % of flagged samples is archived under
`results\rejected` instead of recorded. Set-aside samples stay in the raw file.

The system counters advance in 15.6 ms ticks, so the estimate is coarse on short samples: it
catches a visitor that keeps cores busy, not a single short burst. Excluding the benchmark
folders and toolchains from real-time antivirus scanning (an administrator setting) reduces
the launch load and the noise with it; record such a change in the campaign label.

### 5. Execution is pinned to the performance cores

The benchmark laptop is an Intel Core Ultra 9 185H: six performance cores with two threads
each (logical processors 0-1 and 10-19), eight efficiency cores (2-9) and two low-power cores
(20-21). The same 37 ms run takes 37 ms on a performance core, 59 ms on an efficiency core and
90 ms on a low-power core (measured 2026-10-21, `GetSystemCpuSetInformation` numbering). Every
execution sample runs pinned to one logical processor per performance core, the mask derived
from the machine at start. Builds are not pinned: a compiler is meant to use the whole machine,
and Swag uses its default worker count unless `--swc-cores` caps it (the cap is recorded).

### 6. Rounds in a random order, samples until the evidence suffices

A measurement is a set of units sampled in rounds: a unit is one runtime, or a Swag runtime and
its reference. Each round visits every unit still owed samples, in an order drawn from a seed
recorded with the campaign. A slow stretch of machine time is thereby shared by everyone.

The first round is a pilot that prices each series. Each series then samples until the 95 %
interval of its median is narrower than its target, or its time budget is spent, or it reaches
its maximum count, whichever comes first, and never stops below its minimum:

| series | pilot | minimum | maximum | target half-width | budget |
|---|---|---|---|---|---|
| Swag run or reference | < 1 s | 10 | 30 | 1 % | 4 s |
| Swag run or reference | ≥ 1 s | 5 | 10 | 1 % | 30 s |
| other run | < 1 s | 7 | 20 | 2 % | 2.5 s |
| other run | ≥ 1 s | 3 | 5 | 3 % | 20 s |
| Swag build or reference | < 2.5 s | 8 | 20 | 1.5 % | 5 s |
| other build | < 1.5 s | 5 | 12 | 3 % | 5 s |
| other build | ≥ 1.5 s | 3 | 5 | 5 % | 25 s |
| edit-build loop | < 5 s | 5 | 12 | 2 % | 15 s |
| edit-build loop | ≥ 5 s | 3 | 5 | 3 % | 60 s |

Every execution sample is a fresh process. Input generation is outside each program's own
timer; JIT compilation triggered by the timed kernel is inside it, except for Swag's JIT, which
compiles before the program starts. A self-timed sample under half of the next one is a timer
fault (Go's `time.Now` once read 0.5 ms for a 10.5 ms run; every port now reads the
performance counter) and is set aside.

### 7. Medians and intervals

| quantity | estimator | 95 % interval |
|---|---|---|
| one series | median | order statistics: [x(j), x(n-j+1)], exact from six samples |
| Swag vs another language, one task | ratio of the two medians | errors added in log space |
| Swag vs the reference, one task | median of the per-round ratios | order statistics on the ratios |
| a panel of tasks | geometric mean of the per-task ratios | per-task errors combined |

Below six samples the observed range has a known smaller coverage; it is converted to a
log-space error and widened to 95 %, so a three-sample series reads as uncertain as it is.
Every error has a floor of 0.2 %. The interval describes measurement noise on this panel; it
says nothing of how representative twelve programs are of all programs. Simulated on
lognormal samples, the intervals cover the truth 97 % of the time for a median of twelve
samples, 96 % for twelve paired ratios under a 15 % shared drift, 98 % for a twelve-task
geometric mean, and 88 % for a median of three, the floor the slowest interpreters get;
`tests/test_stats.py` keeps those checks.

A ratio is **faster** when its whole interval is below 1, **slower** when it is above 1, and
**no measurable difference** otherwise. These are the only verdicts the report draws.

### 8. The machine has to be in a known state

A campaign refuses to start on battery or with battery saver on, waits for three consecutive
quiet seconds (under 1.5 foreign cores) before starting, and warms up for thirty seconds on a
reference workload. It records the processor, memory, Windows build, power source and power
mode at start and at end, the toolchain versions, the sampling seed, both compilers' digests
and every sample with its interference reading. A campaign whose power state changed is
rejected. Measuring a modified tree is legitimate and is recorded as `dirty`.

## Reading the report

`bench.html` leads with five cards: native execution in release and devmode, JIT execution,
and compilation in release and devmode. Each compares Swag with its strongest rival in that
family: the runtime against which Swag's geometric mean is worst. The value is the time
difference (negative: Swag takes less time), the verdict, the interval, and how many tasks are
faster, not measurably different, or slower.

- **Progress against the reference** lists every paired series: execution in four modes,
  compilation in two, peak compiler memory, executable size, the edit-build loop and the hello
  programs; the curves show each campaign's geometric mean with the interval as a band.
- **Swag vs each language** is the full matrix of geometric means.
- **Execution** and **Compilation** rank the runtimes per task by median; hovering a time shows
  its interval and sample count.
- **Campaign and method** shows the machine, the power mode, the interference counts, the
  reference and every toolchain version.

The repository README carries a generated summary between `bench:begin` and `bench:end`.

## The edit-build loop

The tasks price a compiler on small programs. These workloads price what a developer waits
for, on the standard library each installation carries, for the compiler under test and the
reference alike:

| workload | command | state before each sample |
|---|---|---|
| `core_rebuild` | `swc build --workspace std -m core -bc devmode --rebuild` | none: the rebuild ignores outputs and caches |
| `core_noop` | the same without `--rebuild` | a build just made |
| `core_touch` | the same | a build just made, then one source's write time advanced |
| `doc_std` | `swc doc --workspace std --rebuild` | output folder emptied |
| `format_tree` | `swc format` | a fresh copy of the installation's runtime, library and task sources |

## The allocator

The execution phase measures the Swag runtime allocator against the vendored
[mimalloc](../src/Support/Memory/mimalloc/readme.md), compiled with MSVC `/O2`, and the C runtime
heap, on fourteen workloads from single blocks to cross-thread freeing. Each workload runs in a
fresh process pinned to the performance cores, five rounds with the three executables in
rotating order, and the section keeps the median of each. The Swag program allocates through
`Memory.alloc` and `Memory.free`, the path ordinary code takes.

## Build recipes

Compilation times measure a complete command from source to a runnable artifact, including the
language's usual startup code, selected imports, header parsing, optimization and linking. The
programs match in behavior and algorithm; they do not make the compilers process an equal
amount of library source. C++ parses CRT and Windows headers, Rust links `std`, D and Odin
import runtime packages, and Swag compiles its runtime, minus what its machine-code cache
holds. A ratio across languages is a ratio of these recipes, not of front-end speed. Java and
C# CoreCLR produce bytecode; the native rows include machine-code generation and linking.

| toolchain | recipe |
|---|---|
| Swag | `swc build -bc release` (or `devmode`), Win32 API imported from its published interface |
| C++ | `clang-cl` and `cl`, `/O2 /EHsc /std:c++20` |
| Rust | `rustc --edition 2021 -C opt-level=3 -C codegen-units=1 -C panic=abort` |
| Zig | `zig build-exe -O ReleaseFast -target x86_64-windows-msvc -lc` |
| D | `ldc2 -O3 -release -boundscheck=off` |
| Odin | `odin build -file -o:speed` |
| Go | `go build`, bounds checks kept |
| Swift | `swiftc -O -wmo` |
| C# | `dotnet publish -c Release` (NativeAOT), `dotnet build -c Release` (CoreCLR) |
| Java | `javac`, run on HotSpot's default tiered JIT |

Rust, Swift, Go, C#, Java and Odin keep their bounds checks (Odin on fixed arrays); Swag
release, C++, Zig ReleaseFast and D `-boundscheck=off` do not. PHP runs with a clean
configuration (`-n`); its JIT row loads OPcache with tracing and refuses to run without it.
Ruby runs its interpreter with gems disabled. Garbage-collected runtimes keep their normal
collection policy. These are short-lived program measurements, not warmed server throughput.

## Files

| | |
|---|---|
| `../tools/bench.bat` | the entry point |
| `campaign.py` | builds the compiler, measures, reports |
| `driver.py` | one campaign |
| `sampler.py` | rounds, pairs, stopping rules, interference retries |
| `machine.py` | interference estimate, quiet waits, machine and power description |
| `installs.py` | the private installation of the compiler under test and the frozen reference |
| `reference.py`, `reference.json` | managing the reference, and the committed manifest of the current one |
| `toolchains.py` | where each toolchain lives, how it builds and runs, its warm state |
| `stats.py` | medians, intervals, ratios, geometric means, verdicts |
| `history.py` | what a campaign concludes; `history.json` is rebuilt from `results/` |
| `mkpage.py`, `page_template.html` | the report; every figure comes from the raw campaigns |
| `winproc.py` | process timing in a job object, peak memory, CPU accounting, pinning |
| `results/` | one raw campaign per file, every sample kept; `rejected/` and earlier protocols beside |
| `src/` | the tasks in every language |

Every compiler helper process runs in a job object and is terminated with it: 46 orphaned
`cl.exe` once accumulated over one campaign and slowed the next one by up to 2.4 times.

## Earlier protocols

`history.PROTOCOL` states how a campaign was measured; campaigns of different protocols are
never mixed. Protocol 1 (`results/protocol1/`) took five unpinned samples. Protocol 2
(`results/protocol2/`) kept the fastest confirmed sample and normalized Swag between campaigns
by the other languages; its raw campaigns are kept as evidence and read by nothing. Raise the
protocol number whenever a change makes new campaigns incomparable with old ones, and move the
old campaigns aside in the same commit.

## Extending it

- **A new task**: add it to every language under `src/`, to `TASKS` in `toolchains.py` and to
  `TASK_INFO` in `mkpage.py`. It must print `CHECK=<n> MS=<f>` and keep data generation out of
  its timer. Confirm every port agrees on the checksum before recording anything. The
  reference has no source for it: freeze a new reference.
- **A new language**: add its recipe in `toolchains.py` (with its warm state if it keeps a
  cache), its version command, and its id to `AOT_CONTROLS` or `JIT_CONTROLS` and `mkpage.py`.
  Give it the release settings its users would ship and document its bounds-check policy.
- **Never change what a task computes** without a new reference: the progress series would no
  longer describe the same work.

## Requirements

MSVC and clang-cl come from Visual Studio; the others are looked up under the user profile and
`PATH`. Overrides: `BENCH_VS_ROOT`, `BENCH_RUSTC`, `BENCH_DOTNET`, `BENCH_SWIFTC`,
`BENCH_SWIFT_ROOT`, `BENCH_NODE`, `BENCH_LUA`, `BENCH_LUAJIT`, `BENCH_PY`, `BENCH_ZIG`,
`BENCH_LDC2`, `BENCH_ODIN`, `BENCH_GO`, `BENCH_JAVAC`, `BENCH_JAVA`, `BENCH_PHP`,
`BENCH_PHP_OPCACHE`, `BENCH_RUBY`; `BENCH_SWC` names the compiler for the standalone drivers,
and `BENCH_REFERENCE_ROOT` the reference store. Zig, LDC and Odin are also found under
`%LOCALAPPDATA%\Programs\{Zig,LDC\bin,Odin}`; Go, Java, PHP and Ruby under
`%LOCALAPPDATA%\Programs` as well. A missing toolchain is named and skipped; no runtime is ever
downloaded by a campaign.

The page follows [design-swag-identity](../.agents/skills/design-swag-identity/SKILL.md).
