# Cache private floating spills in idle integer registers

Prompt 2, production baseline `f8143cb098`. DevMode GCC 14.2.0 compiler on Linux x86-64;
Release benchmark programs, three workers, forced regeneration and separate installations,
outputs and temporary roots. [Provenance](provenance.json) records compiler/binary hashes
and native function ranges. Workloads, arithmetic, checksums and build number are unchanged.

Private full-width 64-bit floating spill homes may retain their raw bits in idle integer
registers. Only already saved GP registers or caller-saved GP registers proven unavailable
to other loop values are used. Integer homes retain their previous register preference.
MOVQ preserves every payload bit and clears the upper SIMD lane like the original scalar
memory load; this does not introduce FP arithmetic or reassociation. Partial or overlapping
accesses, live registers, unbounded aliases and unsupported frame bases retain memory homes.

A narrow companion proof distinguishes a bounded read-only local-address copy from an
escaped pointer. It follows constant offsets within one straight-line region until an
unconditional full overwrite. Each read must fit a known source object. Calls, branches,
stored addresses, unknown offsets, partial overwrites and accesses to spill space fail the
proof. Direct indexed local accesses outside the rewritten loop cannot observe its deferred
writes; inside the loop they remain a barrier. The broader source-object promotion/hoist
privacy model remains conservative.

| Linked native timestep | Instructions | Memory operands | Calls |
| --- | ---: | ---: | ---: |
| Baseline `0x411b90..0x412334` inclusive | 314 | 118 | 0 |
| Candidate `0x40a820..0x40afb5` inclusive | 316 | 112 | 0 |

Two stores and four reads become six raw-bit register transfers. Two reads previously folded
into arithmetic now need explicit transfers, explaining the extra two instructions. Over the
unchanged 500,000 steps this trades 1,000,000 instructions for 3,000,000 fewer memory operands.
For these sites the approximate x86 work changes from two store-address/data pairs, four load
operations and two arithmetic operations to six register transfers and two arithmetic operations.
This reduces memory-port work, but bank-transfer latency and port contention require a timing
check. There are no new saves, restores, frame slots, calls, roots or divisions. Dead entry seeds
and exit writes disappear in the final code. The checksum remains `169096566666`.

Zig is the historical Windows leader for nbody in accepted campaign `20261023-175718`
(1.054x Swag/Zig). The source-verified Linux Zig 0.15.2 x86-64-v3 snapshot has 286 instructions,
107 memory operands and no calls in its `0x1001c50..0x100224e` timestep. Its lower memory traffic supports the register-pressure hypothesis, but it differs in
root packing and FP scheduling. This comparison is static; it is not a current Windows ratio.
The current Swag compiler already keeps all five masses in GP registers before the loop;
the old backlog claim that these mass loads were blocked has been removed.

Validation: all 1,705 C++ tests pass, including executed raw-bit/upper-lane tests for positive
and negative zero, quiet/signaling NaNs and arbitrary payloads. Fourteen structural alias cases
cover copies before/inside loops, bounded offsets, escaping/partial copies, unknown extents,
calls, control flow, spill overlap and indexed memory. `private_spill_cold_call.swg` passes JIT
and native DevMode with mutable snapshots, call clobbers and early exits. All twelve Release
benchmark checksums pass the full verbose Micro comparison.

After matching overload bodies, all other task kernels and reachable runtime paths retain
their code. Raw overload ordinals and generated lambda names vary between installations.
Compiler-side build-configuration `#run` bridges have process-dependent immediate handles;
these are not linked into the native executables. The compressed complete comparison,
normalized differences, changed Micro function, native function and ELF symbol maps are retained.

The copy proof adds a straight-line scan per candidate and source-object checks per alias read:
worst case O(copies × instructions × objects), restricted to local-base escapes. The private-spill
cache retains its existing CFG/liveness and slot-overlap analyses. Timing is **not measured** at
landing; this batch is **landed, unconfirmed**. Linux paired veto samples follow separately.
The full grouped Windows campaign cannot run on this Linux host; corrected Windows indices and
null bands remain pending a compatible host, with no inferred history entry.
