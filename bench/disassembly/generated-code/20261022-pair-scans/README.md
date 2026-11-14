# Bound groups of ordered byte-pair comparisons

The baseline is master `74ba1680d3`, preserved with its runtime before this
batch. Both sides build the unchanged Release benchmark sources with six
workers and separate caches. The baseline compiler is Release; the candidate
compiler is DevMode, with the same generated-program optimization contract.

A bounded byte-pair scan now shares one bound test across four ordered byte
comparisons. Each byte still branches immediately on its original condition;
there are no wider loads, reads after the first stop, or changed checksums.
Both signed and unsigned 64-bit bounds are supported. Narrow operands,
nonunit steps/scales, extra header entries, different exits, overwritten
addresses, and displaced-address overflow decline the transformation.

An unused transient register carries the last safe group start. Under pressure,
a scan-local byte temporary may instead carry the remaining distance between
groups, only when its full value is dead at the common exit. The original
scalar tail keeps its rotated form. Bound and byte exits retain their original
comparison flags. Eligibility is a data-flow/control-flow property and uses the
existing configured partial-unroll factor; it contains no workload constants.

## Static evidence

LZ77's candidate match scan changes **24 to 18 emitted instructions per four
equal bytes**, with the same eight byte reads and no spills, saved registers,
new calls, or changed arithmetic elsewhere. The scalar tail remains six
instructions per equal byte. See [before](lz77-base.asm) and
[after](lz77-new.asm); alignment NOPs are excluded from these counts.

The unchanged generator performs 1,376,206 candidate scans and compares
8,828,260 matching bytes. The [cost model](cost.json) includes entry guards,
early exits, group tests, scalar tails and exit stubs. The original scan executes
59,850,587 instructions. Without assuming a remaining bound beyond each recorded
match, the candidate executes **at most 55,246,502**: at least 4,604,085 fewer
instructions (7.69%). A full-group bound at each eligible mismatch gives
51,222,463. These are instruction bounds, not a cycle model or measured speedup.
The model's compression checksum is the benchmark's 622942003053.

All twelve Release benchmark checksums match. After pairing overloads and
normalizing generated names, every other task kernel and native runtime body
has identical instructions. LZ77 changes only this scan and its branch targets;
its frame, register allocation, other loops and calls retain their code. The
[complete Micro comparison](microdiff.txt) includes apparent overload swaps and
compiler-side build-configuration adapters whose names/handles differ between
compiler processes; these are not new native runtime costs.

## Correctness and cost

All **1,559 in-memory C++ tests pass**, including 60 pair-scan recognition and
rejection graphs and 4,368 before/after pairs (8,736 emitted-code executions).
They observe the full loaded value when live, the final index, equality, carry
and signed comparison flags. Cases include signed/unsigned endpoints, sign and
unsigned-wrap boundaries, short tails, every stopping lane, and pressure that
requires temporary reuse. Positive cases assert that grouping actually occurred.

The native `bounded_pair_scans.swg` fixture passes through JIT and native
Release with the DevMode compiler: 6,550 expected answers per execution mode,
including empty/inverted ranges and both equality conditions. 
The extra analysis remains the existing lazy physical-liveness/CFG computation
and one jump-count scan after an exact shape match. For P accepted groups in an
N-instruction/E-edge function, repeated pass invocations retain O(P*(N+E))
analysis work. Each group emits O(F) instructions for configured factor F.

Timing: **not measured**. This is an accepted static improvement pending the
session's full paired campaign. No benchmark source or workload changed.

## Integrated Release boundary

The Release compiler rebuilt after synchronization with master at `ddc8841e2a`
also passes the focused source fixture through JIT and native Release. Its
[twelve-task comparison](integrated-microdiff.txt) again changes only LZ77's
match scan after overload/generated-name pairing, with all checksums matching.
The target's final Micro instructions match the DevMode-driven candidate above.

Release compiler SHA-256: `3a8a2771423198486205953bbfd1d8c347fc2889200776e74f0c6993713458ca`.

## Reject a moving base and retain packed operand records

The pair scan now declines a first load whose base is also its stepped index:
its address advances twice per iteration, so adding one byte per cloned lane
would change the computation. Both the recognition test and an emitted-code
counterexample fail before the guard: an eight-element scan stops after its
second comparison. With the guard the original scan reaches the bound.

Indexed loads carry seven useful operands; generated records may contain
exactly seven. Both grouping and scan-value sinking now copy those seven
fields, including when the load's operand record is last in storage.

All **1,560 in-memory C++ tests pass**, including 68 pair-scan graph variants,
8,736 paired executions, and two executions of the moving-base counterexample.
All twelve Release benchmark checksums match. The [new full comparison](alias-microdiff.txt)
has identical task kernels and shared native runtime code to the integrated
candidate after overload/generated-name pairing. The original static gain
and its executed-work bounds are preserved. This follow-up adds no analysis.

## Session validation and interrupted compilation campaign

The combined compiler sources at `2b4aa93c37` were rebuilt as Release. Their
[final twelve-task comparison](session-final-microdiff.txt) preserves every task
kernel and native runtime body of the corrected candidate after pairing; all
checksums pass. The full standard-library documentation command also passes
through all twelve modules with fresh caches, with both DevMode and Release
compilers. Release was checked again after synchronization. All 47 benchmark
harness tests pass.

The first combined build/run campaign was stopped after `doc_std/subject`
exited with code 3 and a Windows exception report before writing HTML. Its
[retained log](full-campaign-stopped.log) contains only the old driver's
truncated excerpt, so the failing instruction and compiler task are unavailable.
The original Release subject subsequently passed twice; the preserved pre-change
compiler passed; the corrected DevMode and Release compilers passed; and the
final combined Release compiler passed. These passes do not establish the cause
of the original fault. It remains an investigation lead, not a claimed fix or
an accepted full compilation campaign.

The moving-base counterexample above is independently reproduced and repaired;
no matching reproducer connects it to that documentation fault. Failure output
is now retained in full, and explicit `--out` files retain incomplete checkpoints
between tasks. Neither incomplete nor failed campaigns are published as accepted
measurements. The session resumes with all twelve execution tasks, ordered to
measure the near-tie workloads first, with the same frozen reference and six
Swag compiler workers. Compilation throughput is not inferred from that panel.

Final Release compiler SHA-256: `87b72b50a2f51dbf5fdbbeafc6d6e98c6cc49e307dcfcb34ffe827b85dc8eaae`.
