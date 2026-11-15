# Reuse unchanged integer sources of private floating spills

Prompt 2, production baseline `35a0c7e69f`. DevMode GCC 14.2.0 compiler on Linux
x86-64; Release benchmark programs, three workers, forced regeneration and separate
installations and caches. [Provenance](provenance.json) identifies both compilers,
all twelve linked binaries and changed source files. Benchmark sources, workloads,
checksums, FP policy and compiler build number are unchanged.

A private 64-bit spill may reuse the integer register that already contains its raw
payload. The source must have no definition anywhere in the original natural loop,
including partial and implicit definitions. A bounded backward search follows only
raw full-width copies, stops at control flow or calls, and rejects arithmetic,
partial copies and memory definitions. The unique spill write must dominate every
read and every exit predecessor. Calls, overlapping accesses, aliases, shared exits
and unproven frame ownership retain the existing behavior. Rewritten reads preserve
the scalar memory load's zeroed upper SIMD lane. A deferred exit write retains the
observable memory value. No additional register is allocated.

| Linked native Nbody timestep | Instructions | Memory operands | Calls |
| --- | ---: | ---: | ---: |
| Baseline `0x411ac0..0x412255` inclusive | 316 | 112 | 0 |
| Candidate `0x40a810..0x40af8c` inclusive | 315 | 107 | 0 |

There are no NOPs in either counted range. One redundant GP-to-SIMD-to-GP
cache copy disappears; another invariant mass no longer needs its store/reload.
The freed register also caches a different private floating home. That latter
change unfolds one scalar memory subtraction into a register transfer plus a
register subtraction; it is included in the totals. Over the unchanged 500,000
steps the net reduction is 500,000 instructions and 2,500,000 memory operands.
Calls, frame size, saved registers, roots and divisions are unchanged. Final dead
exit writebacks disappear through the existing passes. The checksum is
`169096566666`.

The source-verified Linux Zig 0.15.2 x86-64-v3 reference has 286 instructions,
107 memory operands and no calls per timestep. Its different root packing and FP
scheduling still prevent an instruction-count-only performance conclusion. Zig is
also the historical Windows leader for this task, at 1.054x Swag/Zig in accepted
campaign `20261023-175718`; that is not a current campaign measurement.

All 1,710 C++ tests pass. The new executed test compares complete output buffers
before/after optimization for positive/negative zero, quiet/signaling NaNs and
arbitrary payloads, with all register banks occupied. Its ten variants cover raw
copy chains, modified/partially modified integer sources, reads before writes,
early/shared exits, narrow copies, intervening memory definitions and multiple
writers. `float_copy_sources.swg` passes JIT and native DevMode, as do the launcher's
ownership/pointer error stages. The final full verbose twelve-task Micro comparison
passes every checksum. After matching overload body multisets and generated names,
Nbody is the only changed native function; every other kernel and shared runtime
path retains its code. The remaining `__run_expr_*` immediate differences are
compiler-side build-configuration bridge handles, absent from linked executables.
Complete Micro listings, the changed native function and ELF symbol maps are retained.

Periodic broader validation on retained batch 5 (`35a0c7e69f`) also passes:
1,826 C++ tests including filesystem cases, and 4,083 JIT plus 4,083 native DevMode
tests. These logs are retained separately and do not claim coverage of batch 6.

Analysis adds two masks to the existing loop scan, at most sixteen backward
instructions per eligible unique writer, and existing dominance queries per
access/exit. Four alternating Nbody compilation pairs took baseline
0.340/0.333/0.319/0.351 seconds and candidate 0.342/0.359/0.440/0.336 seconds.
Peak RSS ranged 183,040–195,500 KiB and 196,784–209,356 KiB respectively.
These short noisy samples are retained, not a measured compile-time claim.

Runtime timing is **not measured** at landing; this batch is **landed, unconfirmed**.
The grouped Windows campaign and corrected indices/null bands remain pending a
compatible host. Linux static captures do not update Windows history.
