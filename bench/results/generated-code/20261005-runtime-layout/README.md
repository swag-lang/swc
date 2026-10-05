# Runtime regression investigation — 2026-10-05

The allocator changes are already on master. The additional native alignment
candidate `5d3338007` remains on `perf/runtime-allocator-20261004`: functional
validation passed, but the available measurements do not certify a general
execution-time improvement. The benchmark process cleanup fix `f5969a373` was
integrated separately as `c8104f60e`.

## Reproduced native regression

The first 25 paired DevMode `fannkuch` rounds measured the current compiler's
program 7.14% slower than a rebuild of `84f461783`. The unchanged-binary control
was 1.76% slower. The executable retained from campaign `20261005-111827` was
9.99% slower. These first measurements checked quiet conditions before and after
each block; they did not yet record load throughout each process.

The 1,628-byte benchmark main retained the same normalized instructions. Its
address moved from RVA `0xaee0` to `0xafd0`: the offset modulo 64 changed from 32
to 16. Function order also depends on the compiler worker count. A contiguous
partition experiment was removed because it did not demonstrate a benefit.

The remaining candidate aligns functions and COFF text contributions to 32 bytes,
with the original function order and 16-byte loop alignment. All benchmark
functions in the 24 native programs retain their normalized instructions.
Executable size grows 1.28% in median; text size grows 3.32%. The first 30
accepted candidate rounds give a paired median improvement of 8.91% against the
current `fannkuch` program, with substantial variation between blocks. Later
single-core blocks consistently support the same direction but fail the load
gate. They are diagnostic observations, not accepted performance results.

The first completed wider strict comparison was `wordfreq` DevMode: candidate/current
is +1.77%, with a +0.40% unchanged-binary control. Its median interval spans
-2.24% to +4.31%; this does not establish a regression or a gain. Other attempted
cases and the compile-time comparison retain their individual acceptance state
in the data. No partial experiment was appended to published benchmark history.

## JIT evidence and SIMD state

`nbody` performs no allocation in its timed loop. The pre-emission instructions
of its three numeric functions match before and after the allocator changes,
and match when execution moves from sema-time `#run` to script `#main`.
The script main also matches between compilers. This inspection does not cover
the original `#run` wrapper: its local `PrintMicro` attribute produced no listing.

The process-CPU marker probe did not establish systematic parallel compiler work
during the numeric loop. Its 15.625-ms CPU accounting granularity and disturbed
wall times are retained in `jit-overlap.json`; these runs are not performance
acceptance evidence.

A separate controlled probe demonstrates a real interoperability hazard. The
same non-inlined numeric function runs 5,000 steps after either leaving YMM15's
upper half dirty or executing `vzeroupper`. Both helpers preserve the native ABI,
including XMM15's lower half. The two alternated sequences give 52–57 ms dirty
versus 0.38–0.47 ms clean, always with checksum `169020000371`. Generated scalar
code mixes legacy SSE and VEX instructions. This establishes sensitivity to SIMD
state on this host, not that the published campaign regression had this cause.
The required entry, return and callback policy remains open in
`compiler.optimization.125`.

The behavior is consistent with Intel's documented
[AVX/SSE transition penalties](https://www.intel.com/content/dam/develop/external/us/en/documents/11mc12-avoiding-2bavx-sse-2btransition-2bpenalties-2brh-2bfinal-809104.pdf).
Do not change MXCSR, rounding, or floating-point semantics to hide the symptom.

## Validation and reproduction

The alignment regression fails with 16-byte alignment and passes with 32-byte
alignment through both direct-image and COFF emission. The final DevMode compiler
passes 1,342 C++ tests, 3,616 native tests and 795 linked Core tests. Both compiler
configurations build. The process cleanup change passes 48 driver/history tests
and 13 harness tests; its new test fails before the fix and passes after it.

`identity.json` records compiler and executable hashes. The previous published
campaign's private compiler was removed and its source metadata was dirty, so
the rebuilt old revision is not a byte-for-byte reconstruction of that compiler.
Every Swag compilation used at most six workers, `--rebuild`, and private caches.
Strict comparisons required at most 15% load before and after each block and at
most 15% background CPU during execution. Rejected blocks remain explicitly
separate. The one-core control uses mask `0x1`; the original control uses the
six-performance-core mask `0x55401`. These are distinct experiments.

To reproduce the SIMD-state diagnostic, copy `probes/` to an external scratch
directory, assemble `avx_state.asm` with `ml64 /c`, and link its object using
`link /DLL /NOENTRY /NODEFAULTLIB /MACHINE:X64 /EXPORT:dirtyAvx /EXPORT:cleanAvx`.
Use `avx_state.dll` as the output name. From that directory, run the Swag script
with six compiler workers and the official generated Win32 `kernel32.swg` API.
The archived script uses a relative DLL name; the measured script used the same
DLL through an absolute scratch path. Run project load admission first.

## Accepted native subset

| Program | Candidate/current | Same-binary control/current |
| --- | ---: | ---: |
| devmode/wordfreq | +1.77% | +0.40% |
| devmode/fannkuch | -5.10% | +0.22% |
| devmode/binarytrees | +4.50% | +0.07% |
| devmode/nbody | -2.08% | -0.14% |
| devmode/dijkstra | -2.87% | -1.37% |
| release/fannkuch | -0.08% | -0.61% |
| release/binarytrees | -5.91% | -0.52% |
| release/nbody | +0.09% | -0.62% |
| release/dijkstra | -0.98% | -0.61% |

These are paired medians over 32 repetitions, not a full accepted campaign.
The final quiet subset is sufficient to withhold the blanket alignment change:
`fannkuch` DevMode improves 5.10%, but `binarytrees` DevMode regresses 4.50% while
its unchanged-binary control moves only 0.07%. Investigate selective alignment
and repeat independent blocks before considering integration.

Six balanced Core rebuild rounds give candidate/baseline paired medians of 0.946 wall, 0.952 CPU, 1.007 committed peak and 1.008 resident peak. The same-binary controls are 1.004, 1.016, 1.012 and 1.010 respectively. Individual rounds vary substantially; this is not proof of a compiler speed gain.
