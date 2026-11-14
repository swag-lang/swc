# Generated-code campaign - 2026-09-07

Four backend improvements are retained: square roots define their destination without reading
its previous value, a square-root result can directly define the register receiving its only copy,
two AND expressions sharing an operand can factor that operand before XOR, and identical
RIP-relative loads reuse a live value with exact relocation identity. The emitted hot loops improve
without added memory traffic. **The campaign's runtime-ratio targets are not
established.** No timing campaign is recorded here.

The work runs in `swc-perf-20260907`, branch `codex/generated-perf-20260907`, from `8d3f0498b`.
The baseline compiler is DevMode build 390; the final compiler is DevMode build 394. Build 392
contains the first three changes; build 393 adds relocation-aware forwarding, and build 394 adds
the scalar-lane guard described below. Benchmark programs use `release`. [Binary and benchmark-source hashes](identity.json) identify both inputs.
The benchmark sources are unchanged; dump copies only add `Swag.PrintMicro("post-emit")`.

## Emitted code

Counts exclude labels and include the loop's terminating branch. Memory counts include explicit
loads, stores and memory-operand operations, including indexed compares; they exclude LEA and
implicit call-stack traffic. A loop span containing another loop is never added to that inner
loop's count. The census is static code shape, not a dynamic instruction or timing measurement.

| Hot loop | Swag before | Swag after | clang-cl | MSVC |
| --- | ---: | ---: | ---: | ---: |
| SHA-256 compression, one round | 74 / 5 | 72 / 5 | 74 / 5 | 56 / 2 |
| Raytrace, one pixel | 53 / 6 | 52 / 6 | 42 / 6 | 49 / 6 |
| Dijkstra, heap sift-up | 31 / 20 | 26 / 15 | 16 / 8 | 15 / 8 |

Each cell is instructions / memory operations. MSVC's SHA-256 body contains four rounds:
224 instructions and eight memory operations, normalized above. Its Raytrace span includes the
two instructions of the negative-input `sqrt` fallback; that branch is not taken for the pixel
normalization. The C++ counts use current `/O2 /EHsc /std:c++20` assembly from both compilers.
These are different compilers' complete loop shapes, not a claim that every other choice matches.

Raytrace's called `intersect` function separately shrinks from 210 to 202 instructions, with
37 memory operations unchanged. `trace` shrinks from 218 to 217, with 74 memory operations.
The metadata correction removes six copies across the three functions; directing square-root
results into their final registers removes four more in `intersect`.

The [complete per-function and backward-loop census](loop-counts.json) covers all seven tasks
and their helper functions. Dijkstra's sift-down loop also improves from 45 / 26 to 39 / 20, and
Wordfreq's partition span improves from 36 / 12 to 34 / 10. CSV aggregation, Leven and ChaCha
have unchanged counts. No counted loop adds instructions or memory operations. The changed
[Swag excerpts](swag-excerpts.txt) and [C++ loop excerpts](cpp-excerpts.txt) retain the evidence.

## Correctness contracts

The shared `MicroInstrDef::resolvedRegModes` now supplies use/def information to the instruction
collector, register verifier and pre-allocation peephole. The current encoder uses SQRTPS/SQRTPD,
which replace every destination lane. The explicit source remains a use, including when source
and destination are the same register. CVTTSS2SI/CVTTSD2SI keep their existing pure-destination
contract through the same helper.

The square-root copy fold uses the existing pure-result rule's width, register-class, single-use
and preserved-copy checks. MOVSS/MOVSD preserve the destination's higher lanes, whereas packed
square roots overwrite them: retargeting is restricted to functions whose floating reads all
stay within the scalar width. Unknown or wider consumers retain the original copy. A reduced
Micro test storing the full packed destination failed before this guard and passes with it.
The guard leaves every benchmark function's instruction and memory counts unchanged. The Boolean fold proves that the common operand has the same SSA value
at both initial reads and at the final operation. It retains the other operands' original read
positions, rejects overlapping temporaries and multiple result uses, stays within one bounded
basic-block window, and requires both replaced intermediate flag results to be dead. The final
AND computes the same result and defined flags as the former XOR.

The load-forwarding pass already recognized relocated loads, but its generic claim guard rejected
all of them. The guarded rewrite now explicitly permits an identified relative relocation and
invalidates that relocation when replacing its load. `MicroRelocation::hasSameTarget` compares
kind, address, symbol, constant reference, shard and offset exactly; the former compressed key
could conflate different targets. The cache still flushes on control flow, calls and potentially
aliasing writes, and evicts overwritten source registers.

C++ regression tests fail when each corresponding optimization is removed. They cover both
32- and 64-bit forms, physical and virtual square-root destinations, source/destination aliasing,
retained copies and other uses, changed common inputs, early copies, and live intermediate flags.
The native suite's `optimizer/bitwise_factoring.swg` exercises zero, all-one and mixed-bit results
through uninlined calls, plus changed and reused intermediate values. Relocation tests cover
distinct target fields, widths, calls, stores, overwritten registers and labels, and check that
only the replaced load loses its relocation. `global_load_forwarding.swg` exercises repeated and
distinct initialized/zero-initialized globals, including writes through an alias, in JIT and native code.

## Rejected experiments and remaining leads

Partial unrolling did not earn acceptance. Four SHA-256 rounds emitted 296 instructions and
25 memory operations (74 / 6.25 per round); two emitted 146 / 12 (73 / 6 per round), against the
baseline 74 / 5. The extra frame traffic outweighed the smaller input-decode improvement. Both
prototypes were reverted, and `Pass.LoopUnroll.cpp` is unchanged. The result and next register
residency question update [compiler.optimization.032](../../../../backlog/compiler.optimization.md).

The same backlog records the cross-file `mapProbe` inlining boundary in CSV aggregation (.033)
and the remaining Dijkstra aliasing/control-flow reuse boundary (.034). After local forwarding,
five global-pointer reads and ten heap-element accesses remain in sift-up; keeping them across
stores or branches requires stronger memory-availability proofs.

## Reproduce

Build each revision's checkout-local DevMode compiler with MSBuild `/m:6`,
`/p:Configuration=DevMode /p:Platform=x64 /p:SwcCompileJobs=6`, after the repository load check.
Keep the baseline executable before building the candidate. Compile the unchanged C++ tasks with
both `clang-cl` and `cl`, using `/nologo /O2 /EHsc /std:c++20 /FA /c` and distinct `/Fa` and `/Fo`
outputs. Compile temporary Swag copies with the print attribute, `common.swg`, and `bytemap.swg`
for the map tasks:

```text
bin/swc.dm.exe build --num-cores 6 --build-cfg release -n <task> -od <out> -wd <out> -f <common-copy> -f <task-copy> [-f <bytemap-copy>]
```

Strip ANSI colors. Reset instruction-reference maps at every function. A jump target is the last
number on its instruction line. Count from the target label through the backward branch, skipping
labels; inspect the source annotation to select the actual hot loop.

## Validation

The final build 394 passes the following checks. Configuration names below refer to the compiled
Swag programs; the compiler itself is DevMode.

| Check | Result |
| --- | --- |
| Standalone C++ regressions | 622 passed |
| Complete native suite, JIT and native execution | 3,020 passed in each of devmode and release |
| Focused JIT square-root regression | Passed |
| Standalone script smokes | All 21 passed in each configuration |
| AoC2019 example smoke | Passed in both configurations |
| Language-reference tests | 458 passed in each configuration |
| Seven benchmark checksums | Swag devmode/release agree with both C++ references |

Both new native regression files pass in both execution modes and configurations. Only
[checksums](checksums.json) are retained from the benchmark driver correctness smokes; no timing
comparison is claimed. [Validation records](validation.json) and [logs](validation.log) preserve
the commands' results, including the subsequent application tests.

Whole campaigns ran with builds 391, 392 and 393; builds 392 and 393 also ran the all-configuration
campaign. Compiler and standard-module suites passed before four pre-existing Swag Capture
goldens stopped each campaign. A clean rebuild with baseline build 390 reproduced all four:
`main.menu.view`, `library.menu.view`, `library.menu.sort` and `library.menu.filter`. Their actual
images are [byte-identical](capture-hashes.json) to the candidates', matching `app.capture.026`.
No golden was promoted. The final scalar-lane guard narrows the optimization and was validated
with the build 394 checks above; a complete build 394 campaign was not repeated. The whole
application and example ladder is not claimed green, and no Release compiler or timing campaign
was run.

Subsequent application checks passed Swag Scope release (219 tests) and Swag Vault release
(74 tests). Swag Scope devmode passed 217 and failed two video tests: the seek-overlay assertion
at `viewer.video.test.swg:598` and voice-start wait at line 112. Their baseline behavior remains
unverified; [app.scope.video.017](../../../../backlog/app.scope.video.md) records the investigation.
Swag Vault devmode was not started after this failure and the campaign's cutoff.
