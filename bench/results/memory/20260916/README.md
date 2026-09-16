# Compiler memory campaign - 2026-09-16

## Batch 1: compact sanitizer records

Reorder fields without removing facts or changing the analysis. `SanitizerLocation` shrinks
from 32 to 24 bytes and keeps its previous comparison order. `SanitizerRegInfo` shrinks from
176 to 128 bytes in the Release compiler, and from 208 to 152 in DevMode. Static assertions
protect the new layouts. Optimizer settings and generated-code transformations are unchanged.

The isolated comparison uses master `2eefc93ce` (build 688) and that revision plus this
layout change (build 689). Both compiler executables were built with normal project settings;
performance measurements use the Release compiler. SHA-256:

- Baseline: `56F37503F5B82CBAC65725EE0C350E9B926113183AECE229702C6508EE79B184`.
- Candidate: `E260B74FF954C761E5A46E46C0E258B085FF9E8FE08341A1EBDCAA2DB2D3BE4F`.
- Candidate DevMode: `3BA82C30FF5D89EA42BD631D978198DA574DB78C5C271C59F6EECE4DB541F3BC`.

### Measurements

The workload rebuilds `bin/std` module `core`, separately with `-bc devmode` and `-bc release`,
using `--rebuild --silent --num-cores 6`. Each round alternates A/B and B/A. Every command
passes the machine-load guard with a stricter 20% CPU threshold and the normal memory limits.
The Windows job harness in `bench/winproc.py` records elapsed time, process CPU time, peak
working set and peak committed memory for the job. MiB means 1,048,576 bytes.

The first five-pair unpinned series was inconclusive for devmode speed: median paired elapsed
time rose 7.1%, while CPU time rose 1.1%. Hybrid-core placement and concurrent work produced
large variation. It remains in [layout-unpinned.json](layout-unpinned.json); no samples were
discarded. A separate seven-pair series fixes the same six performance cores for both binaries
using the harness's topology-derived mask. This affinity is only a measurement control, not a
compiler behavior change. [All controlled samples](layout-pinned.json).

| Program configuration | Baseline peak WS MiB | Candidate peak WS MiB | Paired peak WS change | Paired commit change | Paired elapsed change | Paired CPU change |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| devmode | 662.7 | 569.9 | -14.4% | -13.8% | -1.4% | -6.5% |
| release | 330.1 | 325.8 | -2.4% | -2.1% | -5.4% | -6.1% |

Absolute values are medians; changes are medians of same-round B/A ratios. Shared-machine
activity can start after admission, so the raw elapsed times still vary substantially.
The controlled series shows no median compile-time regression in either configuration.
These are results for this workload and host, not a guarantee for every input.

PE section sizes and hashes are retained with each controlled sample. Even two baseline
rebuilds differ in native byte ordering and occasionally `.text` size; byte identity is not
claimed. This change preserves all analysis data, checks and code-generation passes.

### Functional validation

- Release and DevMode compiler builds passed.
- DevMode compiler C++ suite: 860 tests passed.
- Static sanity suite, program devmode: 57 tests passed with each compiler executable.
- DevMode compiler native suite, program devmode: 3,249 tests passed, including execution of
  the linked executable; the tool's expected recovery probes also passed.
- Native suite, program release: 3,248 passed, one failed in `types/type_patterns.swg:254`.
  The frozen baseline reproduces the same access violation at address `0x6B` when running
  that file alone (nine tests passed, one failed). This is a pre-existing failure, not a green
  release-native campaign. The existing nullable dynamic-pattern test is the reproducer.

[Validation commands and exit codes](layout-validation.json). Later batches retain the direct
regression boundary and rotate additional coverage, rather than rerunning the whole campaign.

Integration with master `e71844062` uses compiler build 695. Both compiler builds and the
57-test DevMode sanity suite passed again. The isolated release pattern failure persisted
at that point and was then fixed in the corrective batch below.

## Corrective batch: inline dynamic-pattern bindings

The release-native failure above came from AST cloning. A typed switch case declares its
binding on the `SwitchCaseStmt`, which the clone's local-declaration predicate omitted.
An automatic inline expansion consequently pinned a read to the original callee's variable
instead of resolving it to the cloned case binding. Recognizing this declaration kind fixes
the cause without disabling inlining or adding generated instructions.

The existing `types/type_patterns.swg` is the regression: it fails before the fix with the
frozen build 695 and passes all ten tests after it, with both DevMode and Release compilers
(build 697), program configuration release, in JIT and the linked executable. The complete
DevMode-compiler native release suite now passes all 3,255 tests and its recovery probes.
The temporary backlog entry was removed after fixing the defect; the repository validator
passes. No replacement or duplicate regression file was needed.

A three-pair core rebuild comparison against build 695 is retained in
[pattern-binding-ab.json](pattern-binding-ab.json): paired elapsed ratios are 0.966 in
devmode and 1.001 in release; paired CPU ratios are 0.937 and 0.970. Peak working set varies
by +2.1% and +1.7%. This is a correctness fix, not a claimed memory improvement.
[Validation commands](pattern-validation.json).

After integration with master `1ad9da4a2`, both compiler builds passed at build 699 and
the ten-test file passed again with both executables in release.

## Corrective batch: relocatable reflected method pointers

Constant extraction read the current bytes of a reflected method pointer as a permanent
constant. Before publication those bytes are zero. In release, this rejected a valid cast to
a non-null function and made an already compiled reflection reader keep returning null even
after the method was ready. Preserve loads from function-relocated pointer slots, including
indexed slots; aggregate materialization still preserves its embedded relocations.

Both existing regressions (`typeinfo_optional_call_graph.swg` and
`deferred_method_pointer.swg`) fail with frozen builds 695 and 700, and pass with build 703.
The DevMode compiler's complete JIT release suite passes all 1,487 tests. Both compiler builds
passed. [Commands and outcomes](method-reloc-validation.json).

Seven alternating core rebuild pairs compare build 700 with the isolated fix at build 703,
using the same admission, affinity and six-worker controls as batch 1. Paired median elapsed
ratios are 1.010 (devmode) and 0.970 (release); CPU ratios are 1.024 and 0.990. Peak working-set
ratios are 0.996 and 1.011, committed-memory ratios 0.985 and 0.998. Concurrent activity still
causes large outliers. This fixes correctness; it is not a claimed performance improvement.
[Every sample, including the outliers](method-reloc-ab.json).
Integration with master `ecd10b479` uses build 706. Both compiler builds and the
1,487-test DevMode-compiler JIT release suite passed again.

## Rejected candidate: move first-arrival sanitizer states

Moving a consumed edge into its first destination avoided a deep copy, but kept the source
hash-table capacities instead of constructing the compact destination tables used by copy
assignment. The five-pair comparison of builds 706 and 707 increased paired peak working set
by 4.3% in devmode and 0.8% in release; committed memory rose 5.6% and 1.3%. Paired elapsed
changes were -1.0% and +1.7%, CPU changes -1.5% and +1.0%. The 57 sanity tests and 410 native
control-flow tests passed, including the linked executable. The candidate was reverted and
was not merged. [All samples](transfer-rejected.json).

## Rejected candidate: move micro builders from symbols into codegen jobs

Owning each builder in its codegen object would avoid retaining the empty builder on
every function symbol. The five-pair core comparison of builds 708 and 709 instead raised
devmode paired peak working set by 5.6% and committed memory by 6.1%. Release used 6.1%
less working set and 7.2% less commit, but paired elapsed time rose 30.8% and CPU 18.8%
under substantial concurrent load. Devmode elapsed and CPU ratios were 0.920 and 0.904.
The ownership change was rejected; its devmode memory result alone disqualifies it.
[All twenty samples](builder-ownership-rejected.json).

Before rejection, both compiler builds passed, as did 864 C++ tests, 1,487 JIT release
tests, 83 native closure tests in devmode including the linked executable, and four
14-test reflection runs (twice per compiler). The buffer-release and PagedStore fixes
discovered during this experiment are retained separately for further validation.

## Intermediate candidate: packed sanitizer values

Build 711 combined 24-byte sanitizer values (previously 32 bytes), consumption of converged
states during the final checking pass, explicit release of micro-builder container buffers,
and the PagedStore allocation-policy correction. Build 708 is the same starting compiler
with the three initial regression tests only. The candidate Release executable SHA-256 is
`30395E69A1F8A1689FE1574996E1F55F649A0D6E981566AA9F6D6E6715DB67CD`; baseline SHA-256 is
`F8C258072B6C7A79FC842145E988540601A6C4B520F64E69C33216F14AEA1B40`.

| Workload | Program configuration | Paired peak WS change | Paired commit change | Paired elapsed change | Paired CPU change |
| --- | --- | ---: | ---: | ---: | ---: |
| core, five pairs | devmode | -6.1% | -5.8% | +5.9% | -0.5% |
| core, five pairs | release | -2.9% | -2.3% | +1.4% | -2.4% |
| gui, three pairs | devmode | -0.04% | -1.4% | +4.2% | +4.3% |
| gui, three pairs | release | +1.2% | +1.2% | +72.4% | +0.8% |

[Core samples](compact-values-core-intermediate.json) and
[GUI samples](compact-values-gui-intermediate.json) retain every observation, including
large scheduling outliers. This bundle was not merged: the larger workload did not
establish a memory and time improvement. These combined measurements do not isolate the
cause to value packing. That representation change was nevertheless removed from the next
candidate, which keeps full-sized values and investigates container padding instead.

Both compiler builds passed. Validation passed 864 C++ tests, 57 sanity tests with each
compiler executable, 20 release native floating-point tests, and 255 devmode native intrinsic
tests; both native selections also ran their linked executable. The initial three C++
regressions failed with build 708 (861 other tests passed).
[Commands and outcomes](compact-values-validation.json).

## Rejected candidate: compact containers and consume final sanitizer states

Build 713 removes empty-allocator padding from SmallVector, directly constructs sanitizer
states and consumes them during the final checking pass. It also contains the two storage
corrections described below. The baseline is build 708, with the SHA-256 recorded above;
the candidate Release executable SHA-256 is
`E49D05B4F2FCE1C99CBE971A170597D02088E5611778ACAD42EAABE841E13B71`.

| Workload | Program configuration | Complete pairs | Paired peak WS change | Paired commit change | Paired elapsed change | Paired CPU change |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| core | devmode | 7 | -4.24% | -2.32% | -0.20% | -3.82% |
| core | release | 7 | -5.53% | -3.87% | -4.73% | +0.38% |
| gui | devmode | 2 | -5.26% | -4.08% | +34.15% | +41.30% |
| gui | release | 1 | -4.73% | -4.18% | +27.65% | +18.80% |

[All 28 core samples](compact-containers-core-rejected.json) and
[all seven GUI samples](compact-containers-gui-rejected.json) are preserved. The second GUI
release pair is incomplete: its candidate sample is retained but excluded from paired ratios.
The user requested completion during this series. Although shared-machine activity introduces
noise, the GUI results do not establish the required absence of a speed regression. The
SmallVector layout and sanitizer changes are therefore reverted, not merged. These combined
measurements cannot attribute the slowdown to any individual change.

Both compiler builds passed before rejection, along with 864 C++ tests, 57 sanity tests,
279 positive semantic source files and 304 expected-error semantic files. The preceding build
712 also passed 149 release native generic tests and execution of the linked executable.
[Commands and outcomes for this experimental bundle](containers-validation.json).

## Final corrective batch: release builder storage and preserve page allocation policy

MicroBuilder::releaseMemory used initializer-list assignment for vectors and hash containers,
which cleared elements while retaining their backing storage. Explicit empty containers now
release that storage; empty hash tables avoid needless replacement. A regression verifies
released capacities and successful builder reuse.

PagedStore move construction and move assignment omitted proximityPages_, so subsequent pages
could silently switch allocation policy after a move. Both operations now preserve the policy.
Two regressions cover move construction, move assignment, existing contents and moved-from reuse.
The three initial regressions failed with baseline build 708 (861 other C++ tests passed).

This final batch retains only these correctness fixes. It does not change SmallVector layout,
sanitizer state propagation, optimizer settings or generated-code transformations. Measurements
of the rejected combined bundle above are not claimed as gains for these fixes.

Final integration uses compiler build 729. At the user's explicit request to stop immediately,
the final Release and DevMode rebuilds were interrupted and integration tests were not run.
Earlier green results above cover the storage fixes within the experimental bundles; they
do not constitute completed validation of this final integrated revision.
