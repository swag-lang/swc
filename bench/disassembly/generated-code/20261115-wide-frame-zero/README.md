# Group adjacent frame zero stores with AVX

Prompt 2, baseline `bf38044d96`. DevMode GCC 14.2.0 compiler on Linux x86-64;
Release benchmark programs, three workers, forced regeneration with separate runtime
installations, caches and output roots. [Provenance](provenance.json) records compiler,
binary and function identities plus native instruction counts. Source workloads,
arithmetic, checksums and build number are unchanged.

A physical floating-register clear already zeros its upper YMM half through VEX semantics.
An uninterrupted run of contiguous, nonvolatile 16-byte frame stores from that register may
therefore use 32-byte AVX stores. The rule needs at least two pairs: saved instructions repay
one `vzeroupper` cleanup. Gaps, overlap, changed sources or bases, labels, scalar accesses,
volatile accesses, unencodable displacements and wrapping byte ranges retain the old stores.
This needs AVX, already required by the existing floating encoder, and adds no AVX2 dependency.
There is no wide value, register-allocation change or additional register reservation.

The appended `StoreZero32MemReg` opcode keeps the source's 128-bit width and declares a
32-byte memory footprint. Frame-range/overlap analysis and late stack compaction consume
that footprint. Emission adds `vzeroupper` at the end of each contiguous wide-store run,
before every possible following branch, label or call; it preserves all low XMM values
and CPU flags. GCC 14.2.0's independently compiled `memset(p, 0, 96)` with `-mavx` uses the
same XMM-clear / three YMM-store / upper-state-cleanup shape ([assembly](gcc-zero96.asm.gz)).
The exact encodings, extended registers and cleanup boundaries have byte-level tests.

| Actual linked native function | Instructions | Memory operands | Calls | Bytes |
| --- | ---: | ---: | ---: | ---: |
| `Binarytrees.bottomUp` | 52 → 50 | 20 → 17 | 5 → 5 | 201 → 186 |
| `Binarytrees.release` | 40 → 39 | 18 → 16 | 5 → 5 | 168 → 159 |

The reductions are unconditional per node, on both leaf and internal paths. Over the original
674,478 creations and releases, this removes **2,023,434 timed instructions** and
**3,372,390 memory operands**. Each candidate count includes its new `vzeroupper`.
Memory byte coverage, initialized fields/padding, saved registers, frame sizes, allocation,
reclamation and calls are unchanged. Checksum remains `674478`.

Java HotSpot remains the historical Windows leader (`20261023-175718`, 1.481x Swag/Java).
Its reusable Linux C2 reference uses a 24-byte thread-local bump allocation and inlines
recursive levels; it does not perform Swag's per-node manual release traversal. This batch
reduces request initialization, without claiming to close that allocator/runtime difference
or to establish a current Windows ratio.

## Validation and complete scope

All 1,709 C++ tests pass. Sixteen executed store cases compare complete guarded buffers and
live XMM/CPU-flag observations, including unaligned locations, odd tails, nonwrapping negative
offsets, wrapping ranges, gaps, overlap, changed sources/bases and volatile/control boundaries.
Four loop cases check that a write's upper 16 bytes block overlapping reload/carry promotion
while a disjoint home still promotes. `struct_safe_defaults.swg` passes six JIT and six native
DevMode tests. All twelve Release benchmark checksums pass the complete verbose comparison.

Every changed compiled function was checked by expanding a wide store back into its two
original writes and giving branch targets stable block ordinals. The full function bodies,
including calls, registers, frame offsets and branches, then match exactly for all twelve
tasks, apart from unlinked process-local `#run` build-configuration handles. The
[expansion review](wide-expansion-review.json) records 34–39 wide stores per task image's
compiled Micro functions. Atomic overload ordinals and generated hashes are paired separately.

Other task kernels retain their arithmetic, loads and control flow. ChaCha's single state
initialization replaces four stores with two plus cleanup; its compression operations are
unchanged. The enclosing native range also loses two padding NOPs, which is recorded but
not credited as the primary gain. Shared scratch allocation/free, error storage, number
formatting and host introspection use the same shorter zero-store runs. Their linked native
functions and symbol maps are retained; the Micro listings also retain changed functions
pruned from the native images. All compared native loop ranges keep or reduce their instruction counts,
including padding ([review](native-loop-review.json)); calls and nonzero memory operations
are unchanged. The large normalized diff includes label renumbering; the expansion check
separates it from actual rewrites.

The added scan is linear in an uninterrupted store run, with disjoint runs visited once;
fixed memory-footprint handling is constant work per analyzed access. The early experiment
without upper-state cleanup was revised before landing. Single-pair runs are excluded so
cleanup is amortized. Timing is **not measured**; this batch is **landed, unconfirmed**.
A comparable grouped Windows campaign, corrected indices and null bands remain pending
a compatible host. No inferred Windows history entry is written.
