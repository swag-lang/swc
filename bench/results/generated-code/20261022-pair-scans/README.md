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
