# Generated-code audit - 2026-09-16

The session used the separate `swc-micro-release` worktree and Release `swc.exe`,
with `-bc release` and six workers. Each validated optimization batch was merged
into local `master`. The probes were deliberately small, so each missing rewrite
could be isolated and checked before moving to the next one.

## Machine-code measurements

The exact same [51 Swag functions](scalars.swg) were compiled with baseline build
688 and checkpoint build 731. [Equivalent C++ functions](scalars.cpp) were compiled
with clang 21.1.6, `-O2 -target x86_64-pc-windows-msvc`. The baseline is
`2eefc93ce4316be7ce6538e660e642a4a021ac28`. Compiler and artifact hashes are in
[identity.json](identity.json).

The [complete counts](counts.csv) and [counted assembly](assembly.txt) use native
x64 instructions on both sides. Counts include RET and exclude inter-function
alignment and runtime functions. These probes contain no loops or internal
branches. Ten-byte MOVABS instructions are counted in full.

| Corpus | Instructions | Bytes |
| --- | ---: | ---: |
| Swag baseline | 319 | 994 |
| Swag checkpoint | 209 | 592 |
| LLVM reference | 192 | 559 |

Swag reduces total bytes by 40.4% and instructions by 34.5% in this selected corpus.
46 functions become smaller, five retain their size, and none grows. Compared
with LLVM, 38 have equal size, five are smaller, and eight remain larger. These
are static size measurements on examples selected during optimization, not a
representative workload average or a runtime speed claim.

| Example | Baseline bytes | Checkpoint bytes | LLVM bytes |
| --- | ---: | ---: | ---: |
| `(a & b) | (a & c)` | 25 | 10 | 10 |
| `a | (a & b)` | 16 | 4 | 4 |
| `(a & 255) | (a & 65280)` | 21 | 4 | 4 |
| `(a & c) | (b & ~c)` | 25 | 16 | 13 |
| `a < b ? 256 : 0` | 24 | 12 | 12 |
| `a < b ? 0x100000000 : 0` | 29 | 13 | 13 |
| `(a & 255) == 0 ? 1 : 0` | 18 | 8 | 8 |
| `a - b == 0 ? 1 : 0` | 17 | 9 | 9 |
| `a < 128 ? a : 0` | 20 | 14 | 14 |
| `a / 3` | 29 | 23 | 23 |

## Changes

The 27 optimization batches cover bitwise factoring, absorption and cancellation;
constant masks and bitwise selection; low-half integer multiplication; negation
and arithmetic cancellation; zero extension and shift widths; physical copy
forwarding into comparisons, extensions, addresses and conditional moves; late
copy/add and shift round-trip elimination; and boolean/mask materialization.
Every rewrite retains width, flag, liveness and fixed-register constraints.

A reduced mask example also exposed an existing truncation of inferred runtime
conditionals containing wide integer literals. Its type is now settled from both
integer branches before a local captures it. A later full native run found that
the first implementation also narrowed floating literals; the correction limits
that rule to integers and preserves the existing f64 inference contract.

## Validation

All compiler builds and project commands used fresh CPU/memory admission and six
workers. Focused tests rotated between arithmetic, casts, calls, loops, ABI and
register-pressure cases, plus selected core, pixel, UTF-8 and SHA-256 consumers.
New native regression files accompany the optimization families under
`bin/unittests/native/optimizer`.

Periodic broader checks passed 3,268 native tests at build 712, all 735 core tests
at build 714, and all 1,487 JIT tests at build 722. The late native checkpoint found
the floating-inference regression described above; its reduced test and the
existing short-function inference test pass after correction. The integrated checkpoint build 731 passes all 3,277 native tests and the three expected-failure recovery probes. A transient null-capture diagnosis is retained as compiler.core.052 below; no speculative fix is included.

The full repository campaign, DevMode compiler and C++ unit tests were deliberately
not run in this session. Two earlier C++ expectation families were updated for the
changed emitted forms; their execution remains part of the later global campaign.
Core rebuild time and peak working set were sampled during iteration, but machine
load caused large timing variation, so no compile-time speedup is asserted here.

## Reproduce

Run the repository load admission check before each compilation. Use an external
scratch directory for libraries, objects, extraction files and compiler copies.

```powershell
& <compiler>/swc.exe build -f <report>/scalars.swg -ak static-library -n scalars `
  -bc release --num-cores 6 --out-dir <scratch>/out --work-dir <scratch>/work
clang -O2 -c -target x86_64-pc-windows-msvc <report>/scalars.cpp -o <scratch>/scalars.obj
llvm-objdump -d --x86-asm-syntax=intel <scratch>/scalars.obj
```

Extract the COFF members of the Swag library before disassembling them: the current
Swag archive long-name table is not accepted directly by LLVM's archive reader
(`compiler.core.050`). The counted function bodies and per-instruction byte sizes
are preserved in [counts.json](counts.json). The unused arguments are intentional:
all probes retain the same three-argument ABI on both compilers.

## Remaining leads

The remaining measurements are tracked in compiler.optimization.041. The eight larger cases isolate physical return copies and constant division/remainder
register choices (`blend`, `div7`, `mod7`, `moduloThree`, `moduloTen`), carry-based
boolean arithmetic (`boolMask`, `flagAdd`), and high-byte extraction (`highByte`).
The interval allocator currently records physical copy-source hints but skips
physical copy destinations. A bounded trial of the symmetric destination hint
should compare all probe outputs and register-pressure tests before adoption.
No unvalidated allocator or new ADC/SBB encoding change is included.

## Intermittent diagnostic retained for follow-up

The late build-728 full native run also diagnosed twelve null dereferences in
`native/inline/binding_visit_growth.swg`. Builds 712 and 714 passed its isolated
source; build 718 failed with the original scratch output/work roots, then passed
with fresh roots. An identical source copied outside the checkout also passed.
Build 730 with temporary pre-sanity tracing passed. The tracing was removed before
checkpoint build 731, which passes the complete native suite. This does not establish
whether work-directory state, scheduling, or another input caused the difference.
`compiler.core.052` preserves the investigation; the failure is not claimed fixed.
