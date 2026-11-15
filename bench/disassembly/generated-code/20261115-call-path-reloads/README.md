# Restore private spills only on incoming paths that need them

Prompt 2, production baseline `6cb558ed24`. Linux x86-64, GCC 14.2.0 DevMode
compiler, Release benchmark programs and three workers. All twelve tasks use
forced regeneration and separate compiler installations/caches. The benchmark
sources, work, timed boundaries, checksum contracts and FP policy are unchanged.
The compiler build number is unchanged. [Provenance](provenance.json) records
compiler, source, Micro and linked-binary hashes.

Wordfreq's quicksort kept global pointers in transient registers but restored
them at a shared scan latch, including count-mismatch paths that never call
`memcmp`. The existing post-allocation frame-reload sinking rule required an
adjacent label and every explicit incoming edge to preserve the register/home
equivalence. Those restrictions excluded a conditional fallthrough and a second
explicit incoming edge whose call had clobbered the register.

The same bounded backward proof now partitions incoming edges for a private
64-bit spill reload behind an independent unary operation. Proven forward jumps
skip the reload; unproven jumps enter a shared restore label, and physical
fallthrough executes the restore. No executed branch is added. A preceding trip's
reload is an inductive equivalence source: every transformed incoming edge either
already preserves the value or restores it. Function entry and address-taken
labels cannot supply that hypothesis. Partial register definitions, aliasing
writes and inconsistent stack depth invalidate a proof. Existing private-spill,
balanced-stack and callee-clobber rules remain in force.

The physical conditional predecessor is **not** an equivalence source: its taken
edge can bypass the reload. An executed counterexample first failed with a wrong
value using that overly broad anchor. The final rule walks that edge to a genuine
store/reload or rejects its proof. The failing log and trial patch are retained;
the final test executes the same bypass and passes.

| Executed native scan path | Before | After |
| --- | --- | --- |
| Left, advancing on a count mismatch | 9 instructions, 5 memory operands, 0 calls | 6 instructions, 2 memory operands, 0 calls |
| Right, advancing on a count mismatch | 9 instructions, 5 memory operands, 0 calls | 7 instructions, 3 memory operands, 0 calls |
| Tie followed by advancing after `memcmp` | Three left / two right restores | Same restores, before the independent INC/DEC |
| Non-advancing comparison exit | No latch restores | Unchanged |

The left scan skips `[rsp+0xA8]`, `[rsp+0xB0]` and `[rsp+0xB8]`; the right skips
`[rsp+0xC0]` and `[rsp+0xC8]`. The linked function remains 587 bytes with 132
instructions, 54 memory operands and three call sites. Its frame, saved registers,
NOP count and complete-function instruction totals are unchanged. This gain is
visible in control-flow paths rather than function totals.

An external diagnostic reproduces the unchanged deterministic words, FNV table
insertion and quicksort: 5,000 distinct words, checksum 130489, 17,606 advancing
left count mismatches and 12,564 advancing right count mismatches. Thus the timed
task executes **77,946 fewer instructions and 77,946 fewer frame reads**:
`3 * 17606 + 2 * 12564`. Its script, counts and original source hashes are retained.
This diagnostic is not substituted for the benchmark or used as timing evidence.

The source-verified Linux LDC reference (`20261114-linux-x64/d-ldc`, LDC 1.43.0,
LLVM 22.1.8) similarly keeps its count state through the common mismatch path and
restores it after `memcmp`. Its left scan at `0x1ae70..0x1ae7d` uses five
instructions and two reads; the candidate uses six and two. ABI and source
lowering differ, so this is a mechanism comparison, not a runtime ranking.

All 1,715 C++ tests pass, including eleven executed variants with four entry
controls and four raw payloads before/after optimization. They cover mixed
incoming edges, source/stack changes, partial definitions, overlapping/disjoint
writes, unknown aliases, non-private homes, initial inequality, external entry
and a branch that bypasses the reload. Positive cases also require its movement;
negative cases compare observable output because independent peepholes may
legitimately replace their original instruction. All 4,083 JIT and 4,083 native
DevMode tests and both native error suites pass with the final compiler.

All twelve checksums pass the full verbose Micro comparison. Matching overload
body multisets leaves only `Wordfreq.qsort` plus process-local build-configuration
`#run` handles absent from linked executables. Complete native comparison finds
only `Wordfreq.qsort` changed after resolving names and relocation addresses.
Other kernels and reachable shared runtime bodies retain their instructions,
memory operands, calls, NOP counts and function sizes. Complete assembly, Micro
and symbol maps for both sides of all twelve tasks are archived, including the
equal-total-count quicksort change.

The extension reuses the existing 256-instruction bounded backward walker and
its allocation buffers. Per candidate, each incoming edge costs a traversal of
at most 256 distinct instructions and their predecessor edges; the additional
restore list is linear in the join's incoming edges. The existing pass changes
one candidate and refreshes its CFG before continuing. No new whole-function
analysis or configurable threshold is added. Four alternating before/after Wordfreq
compilations and their per-child peak RSS are retained in
[compile-cost-samples.json.gz](compile-cost-samples.json.gz). The host is noisy;
these samples do not establish a compilation-speed or memory change.

This is the eighth accepted optimization batch of the session (investigation
round nine; the preceding scan-retention trial was rejected). Runtime improvement
is **not measured**. The required combined Windows cross-language campaign,
corrected indices and null bands remain pending on a compatible host; this batch
is **landed, unconfirmed**. No Windows history or inferred index was written.
