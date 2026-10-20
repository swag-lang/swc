# Runtime and exported API machine-code cache

This records the opt-in implementation at commit `35e65ba5d6`. Its compiler options
and reproduction commands describe that revision. Later work makes reuse automatic
and removes those public switches; the raw measurements below remain unchanged.

The experimental `--machine-cache` option reuses compiled runtime and imported API
functions. It avoids backend optimization, register allocation and encoding. Source
loading, parsing, semantic analysis and initial IR generation still run. The earlier
syntax-only `--parse-cache` experiment remains separate and disabled by default.

## Result

Warm compilation is faster on all four measured consumers. GUI's initial nine pairs
were inconclusive, so a second series used 25 pairs and a stricter admission threshold.
The option remains opt-in while the semantic-interface layer is unfinished.

| Consumer | Extra API bytes | Pairs | Disabled median | Warm median | Paired wall reduction | Descriptive 95% reduction interval | Paired CPU reduction |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| runtime | 0 | 9 | 362.7 ms | 233.7 ms | 33.7% | 17.9–44.8% | 51.8% |
| core closure | 735,686 | 9 | 597.5 ms | 455.6 ms | 24.4% | 17.8–30.5% | 22.9% |
| pixel closure | 1,332,168 | 9 | 752.7 ms | 647.4 ms | 15.6% | 6.9–21.5% | 19.6% |
| gui closure, confirmation | 1,627,759 | 25 | 770.6 ms | 736.5 ms | 4.5% | 1.1–6.1% | 9.5% |

Every consumer also reads 463,486 runtime bytes. All three API closures exceed the
runtime's size. The final GUI series had 19 faster warm pairs out of 25; an individual
invocation is not guaranteed to improve on a shared machine. Its initial series had
a paired wall reduction of 0.2%, with an interval spanning a 14.5% slowdown to a 22.1%
speedup. Both series remain in the raw data. The later series supports a small gain;
the initial one alone would not justify that conclusion.

Median paired compiler peak-memory reductions are 15.6% for runtime, 6.5% for core,
3.7% for pixel and 2.2% for the GUI confirmation. This is compiler process/job memory,
not a measurement of the generated program's memory use.

- [initial.json](initial.json): all four nine-pair series, run `parsecache-20261020-124343`.
- [gui-confirmation.json](gui-confirmation.json): the 25-pair GUI series, run `parsecache-20261020-130209`.
- [summary.json](summary.json): medians, paired ratios, bootstrap intervals and slower-pair counts.
- [verification-devmode.json](verification-devmode.json) and
  [verification-release.json](verification-release.json): cache integration checks.

The `populate` and `reuse` fields retain the separate pilot timings. Population is
the first enabled build of each graph, not an empty-cache observation after every
previous graph. Only the first graph in a run starts with an empty archive. The GUI
confirmation's empty-cache pilot took 800.5 ms and its first reuse took 768.1 ms;
these single observations are not a paired estimate of cold-cache overhead.

## Method

- One byte-identical Release compiler for both sides, SHA-256
  `4c1777b48ccd3a494d3a393493ec486a62097d8fe26511d85d3e91880b7b7e8a`.
  This compares cache disabled with cache enabled; it does not compare an older
  executable with the new one.
- Windows 11 build 26300, Intel Core Ultra 9 185H, 31.4 GiB physical memory.
  Six compiler workers, pinned to one logical processor per performance core.
- Complete native builds in the `devmode` program configuration, including process
  startup, archive loading, fingerprinting, reference fixups, remaining emission,
  native linking and archive publication at shutdown.
- Fresh native output directory per sample. Dependency production is outside the
  timer; generated APIs and native libraries were rebuilt with this compiler first.
- Private cache directory per run, shared across that run's consumers. Population
  and a pilot reuse precede alternating disabled/warm pairs. Both pilot programs
  are executed outside the timer and must print `42`.
- Both experimental caches are disabled on the control side; only machine-code
  reuse is enabled on the warm side. Unsupported functions and conservative misses
  follow ordinary emission, with that cost included.
- Every invocation passes the repository's CPU and memory admission check. The
  initial run requires average CPU at most 15%; the GUI confirmation requires 10%.
  No other build or test from this task overlaps a timed run. Other users of the
  shared machine can still start work after admission.

Ratios are medians of paired warm/disabled times. Separate off/warm medians can
produce a different ratio when machine speed drifts. Descriptive 95% bootstrap
intervals resample whole pairs 20,000 times with seed 20261020. They describe the
observed samples; they cannot remove shared-machine interference. Every sample is
retained, including the initial runtime control that took 5.45 seconds and the
initial GUI series whose paired median was inconclusive.

Reproduce after preparing matching dependencies:

```powershell
py -3 bench/parsecache.py --scratch "C:\path\outside-checkout" --cache machine --reps 9 --max-cpu 15
py -3 bench/parsecache.py --scratch "C:\path\outside-checkout" --cache machine --only gui --reps 25 --max-cpu 10
py -3 bench/cachecheck.py --scratch "C:\path\outside-checkout"
py -3 bench/cachecheck.py --scratch "C:\path\outside-checkout" --dm
```

## Correctness boundaries

Both DevMode and Release compiler builds passed. The DevMode compiler passed all
1,497 C++ unit tests, including key invariants for pointer aliasing, global address
distances, callee effects, nullability and untyped compile-time evaluators. A negative
control removing function-reference alias identities failed the corresponding test.

`bench/cachecheck.py` passed with both compiler executables: cold/warm native and JIT
calls, changed generic API bodies and constants, changed consumer layout, changed
callee effects, changed program configuration, changed compiler write stamp,
damaged/truncated archives, source diagnostics and concurrent publication. The
workspace `consumer_exe` snapshot passed seven native tests with each compiler,
covering shared/static artifacts and a diamond import graph. The final GUI standard
dependency closure also built with both caches disabled.

The archive uses a compiler identity containing executable path, size, write stamp
and version. Normal compiler rebuilds select a new archive. Input keys include
lowered code, ABI, backend controls, relevant semantic effects, constant graphs and
source bindings. Relocations rebind to current-process objects. Checksummed records
fall back to ordinary emission when damaged; concurrent publishers merge under the
directory lock and publish atomically.

## Limits

The option remains experimental and disabled by default. Debug-information builds,
rebuilds, requested micro listings, optimizer statistics and full development
validation bypass it. Global-layout or source-context differences can cause new
variants even with unchanged source, so warm reuse can still publish an archive.

This establishes a reusable machine-code layer. It does not establish a serialized
semantic module interface or eliminate the runtime's front-end fixed cost. Those
remaining outcomes stay in `compiler.core.030`, `compiler.core.006` and
`compiler.core.001` in the compiler backlog.
