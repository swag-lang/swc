# Moved-pointer write proofs and sanitizer cost, 2026-10-16

## Retained behavior

`48b13fb2c` rejects writes through pointers retained into local storage abandoned by
`#move` or `#relocate`. It preserves direct reinitialization, pointers formed after
abandonment, conditional pointer refresh, independent pointees, and `opPostMove`
repair. Ordinary calls still conservatively clear moved-from proofs. Runtime poison
does not detect a stale pointer's write; these new findings are static diagnostics.

The borrow-age flag occupies existing padding: `SanitizerValue` remains 32 bytes and
register/state records do not grow. It travels in the existing dataflow; no heap map,
whole-program pass or runtime guard was added. Functions with no invalidation skip
move-check dispatch. Distinct owned frame slots no longer produce an impossible
self-assignment branch, preserving relocation's copied pointer facts at its join.
References, incoming parameters, and caller return storage keep that guard.

## Correctness

- DevMode compiler, program devmode: focused fixture (9 sound tests plus expected
  diagnostic cases), full sanity (85), safety (142 plus 15 expected JIT panics),
  full native (3,886), and C++ source tests (1,417), all passed.
- Release compiler: sanity (85) in devmode, and the focused fixture (9 sound tests
  plus expected diagnostics) with program configuration release, all passed.
- The corpus CWE-672 write is now live and expects `sanity_err_write_after_move`;
  `compiler.safety.005` is resolved. The old read diagnostic remains distinct.
- Native and C++ checks were repeated after the relocation change. No test uses
  an elapsed-time assertion. SWC_BUILD_NUM remains 1173.
- These binaries were built at `48b13fb2c`; later conflict-free integration and
  concurrent master commits are not an additional whole-tree validation claim.

## Normal compiler A/B controls

Baseline: `6eef68f9b`. Candidate: `48b13fb2c`. Both are normal MSVC Release builds,
with their own adjacent runtime copies, no debug-information request, six compiler
workers, and `SWAG_PATH` pointing at this worktree's bin directory. Each command
uses `--rebuild`. Core sources were unchanged throughout this panel.

Command: `build --workspace bin/std --workspace-module core --build-cfg devmode
--rebuild --num-cores 6`. Order is A/B/B/A, repeated three times.
`bench/winproc.py` measures wall time, compiler-process CPU time, process-tree peak
committed memory, and compiler peak working set. CPU is not process-tree CPU time.
Each invocation passed the shared machine admission gate independently.

| Sample | Compiler | Wall ms | CPU ms | Peak job bytes | Peak working set bytes |
| ---: | --- | ---: | ---: | ---: | ---: |
| 0 | baseline | 4439.667 | 17437.500 | 579854336 | 554205184 |
| 1 | candidate | 5405.361 | 22890.625 | 584019968 | 559009792 |
| 2 | candidate | 12571.036 | 49687.500 | 565473280 | 537878528 |
| 3 | baseline | 7832.567 | 26578.125 | 576540672 | 547790848 |
| 4 | baseline | 8780.281 | 43609.375 | 591650816 | 567218176 |
| 5 | candidate | 9137.528 | 43593.750 | 598441984 | 564744192 |
| 6 | candidate | 4926.892 | 19421.875 | 598188032 | 555888640 |
| 7 | baseline | 53480.143 | 178703.125 | 560132096 | 530481152 |
| 8 | baseline | 20963.208 | 84921.875 | 592621568 | 563109888 |
| 9 | candidate | 2910.130 | 13406.250 | 594141184 | 563048448 |
| 10 | candidate | 4632.936 | 20093.750 | 583413760 | 557424640 |
| 11 | baseline | 4656.009 | 19750.000 | 582049792 | 559022080 |

The unchanged A/A controls failed to stay stable: the baseline ranged from about
4 to 53 seconds, and the candidate from about 3 to 13 seconds. Process CPU time
also drifted strongly. These data support no compiler-wide speedup, slowdown, or
tight regression bound. The optional full-std A/B repetition was stopped before
its first sample completed; it is not a result. Subsequent builds use --rebuild.

baseline SHA256: `aa6251eb280969c0faec354014697b4a85310222caa22db27801df864a0c79c4`.

candidate SHA256: `b4f1964fbe513748ce40a4be762fbcb7595e75fca83413c9fe2dabe25e11f1bc`.

## External sanitizer attribution

The observer uses QueryThreadCycleTime around setup, propagation and checking.
An outer scope measures the entire sanity pass, including construction, cleanup,
and marker removal. A scope in main emits one final report after worker shutdown.
Nothing is added to the shipped compiler. Only three copied translation units are
instrumented and relinked against the matching normal Release objects.

The payload snapshot has its own timed phase. The pass percentages below subtract
that snapshot from pass cycles; cycle queries, counter increments, aggregation,
and any changed optimization remain observer effects. The shared-machine controls
cannot provide a tight bound on their uninstrumented overhead. Percentages are
observed CPU-cycle shares, not wall-time shares or a claimed compiler speedup.

| Workload | Wall ms | Compiler CPU ms | Peak job bytes | Peak working set bytes | Pass cycles / process cycles | Propagation visits | Checking visits | Check calls | Stored states | Capped runs | Largest logical state payload |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| core-devmode | 6421.551 | 26578.125 | 589361152 | 558141440 | 5.53% | 1067628 | 920575 | 789517 | 80501 | 0 | 1316364 bytes |
| std-release | 103636.422 | 485234.375 | 1786060800 | 1719545856 | 2.81% | 4374573 | 3577685 | 3637426 | 320683 | 0 | 1947784 bytes |

`functions` counts analysis invocations, including early returns, rather than unique
source definitions. The instruction limit remains 20,000 and the propagation limit
400,000; neither was loosened. Zero capped runs describes the analyses that entered
the worklist, not a count of functions skipped before it.

Logical state payload is the retained state-vector capacity plus occupied register
and stack key/value payload at convergence. It excludes table spare capacity,
hash buckets/nodes, transient copies and allocator overhead. It is not a heap peak.
Exact retained-capacity attribution remains open in compiler.safety.019.

Setup accounts for about 26% of measured engine phases, propagation about 49%, and
checking about 24%; transfer runs in both propagation and checking. These counters
point to transfer/state work for the next focused profile, rather than weakening
checks, lowering limits, or introducing a timing threshold in correctness tests.

Raw observer output:

```text
core-devmode safety-profile: pass_cycles=4561322600 functions=5009 setup=1187328627 propagation=2169049514 checking=1100896682 observer=10390782 process=82355972038 steps=1067628 check_steps=920575 check_calls=789517 states=80501 capped=0 max_converged_payload=1316364
std-release safety-profile: pass_cycles=42017454524 functions=26919 setup=10668614209 propagation=20619435078 checking=9523685992 observer=125819964 process=1490421433049 steps=4374573 check_steps=3577685 check_calls=3637426 states=320683 capped=0 max_converged_payload=1947784
```

## Reproduction

Build the normal Release compiler in this checkout after load admission, with
`/m:6 /p:SwcCompileJobs=6`, and preserve it with its runtime outside the checkout.
Use fresh rebuilds for comparisons while SWC_BUILD_NUM is unchanged.

Prepare the observer with
`python bench/results/safety/20261016-sanity-profile/make-profile.py <absolute-external-directory>`.
The script copies the runtime, preserves the normal optimization flags, disables
PCH use for the three observer objects, and writes all objects/PDBs/maps/executables
outside the checkout. It leaves normal objects read-only. After another admission
check, run the generated build-instrumented.bat from the checkout root.

Set SWAG_PATH to this checkout's bin. Run the external profile-candidate/swc.exe
with `build --workspace <checkout>/bin/std --workspace-module core --build-cfg devmode
--rebuild --num-cores 6`, then repeat without --workspace-module and with --build-cfg
release. Capture the final safety-profile line and use bench/winproc.py for wall,
compiler-process CPU, and peak memory. Admit each command separately.

The regenerated language reference describes stale writes, valid reinitialization,
post-move repair and the ordinary-call boundary. tools/help.swgs dm completed;
its runtime page also incorporates the earlier retained summary/detail fixes.
