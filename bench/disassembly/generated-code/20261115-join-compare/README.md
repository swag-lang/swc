# Reuse identical integer comparison flags at joins

Prompt 2, production baseline `e4988feb13` (same compiler sources as `5d38c841ae`).
DevMode GCC 14.2.0 on Linux x86-64, Release benchmark programs, three workers, forced
regeneration and separate runtime installations, outputs and scratch. Workloads,
arithmetic, checksums and build number are unchanged. [Provenance](provenance.json)
records compiler/binary hashes, native functions and permutation trip counts.

A register comparison/test immediately after a label may disappear when every incoming
path reaches an identical integer producer without changing its operands or CPU flags.
The backward proof checks exact opcode, operands and width. It rejects unknown entries,
calls, partial writes, different producers, address-taken labels and paths that exhaust
a fixed analysis budget. The complete proof region is claimed against other queued
rewrites. Memory and floating comparisons are excluded. Cycles without a terminating
producer conservatively exhaust the budget; there is no optimistic visited-node rule.
The traversal and its pending work are capped at 64 instruction visits per candidate,
reusing the cached CFG; this adds bounded work per eligible comparison.

Fannkuch's flip loop initially tests `k` for zero and tests it again at the inner-loop
header. Its back edge also arrives with that same comparison's flags. The second test
is removed in the actual linked function at `0x40d850` before, `0x407450` after.
For valid permutation elements `k = 1..8`, with `q = floor((k - 1) / 2)`:

| Executed flip path | Instructions | Memory operands | Calls |
| --- | ---: | ---: | ---: |
| Baseline, header through back-edge test/branch | `12 + 7q` | `3 + 4q` | 0 |
| Candidate, same path | `11 + 7q` | `3 + 4q` | 0 |

The original nine-element permutation set has 362,880 permutations and 1,911,505 flips,
so this removes exactly 1,911,505 timed instructions. Checksum remains `8629030`.
Saved registers, spills, swaps and copy loops are unchanged. The full function remains
867 bytes: one existing alignment NOP grows by three bytes before the generic swap
body; its executed instruction count does not increase. The new header branch reuses
older flags, so this static result does not establish a macro-fusion or timing benefit.

Rust is the historical Windows leader in accepted campaign `20261023-175718` (Swag/Rust
1.029x). The source-verified Linux Rust 1.100.0 x86-64-v3 snapshot uses one zero test at
`0x16bc6` before its range check and swaps. Its vector copy and specialized rotations
remain separate opportunities; the retained change removes a redundant test without
adding a repeated overlap guard. Linux listings do not establish a current Windows ratio.

All 1,707 C++ tests pass. Executed paired fixtures observe signed, unsigned, overflow
and zero flags through both join edges over zero, adjacent values and signed extrema;
negative cases change values, widths, immediate operands or flags. Separate cases check
calls, partial writes, cycles and address-taken labels. `repeated_compare_exits.swg`
passes JIT and native DevMode, including signed extremes. All twelve Release benchmark
checksums pass the complete verbose Micro comparison.

All other benchmark kernels retain their code. Two shared runtime bodies lose the same
redundancy: `__printString` loses a zero comparison after an unsuccessful write (its
275-byte native body becomes 272 bytes), and `__linuxReadProc` loses a sign comparison
after a read-result branch. The latter is present in Micro but pruned from the inspected
wordfreq native image. These changes add no memory traffic or calls. Full normalized
differences, equal-count review, changed Micro functions, native functions and symbol
maps are compressed here. Atomic overload ordinals and generated runtime hashes are
paired; unlinked compile-time build-configuration bridges have process-local metadata.

The executed fixture also exposed an encoder assertion for valid `SETcc Zero`.
The encoder now supports its missing Zero/NotZero and parity aliases and NotOverflow,
with five exact-byte encoder cases. Existing condition encodings remain unchanged.
No diagnostic instrumentation remains. Timing is **not measured** for this batch;
it is **landed, unconfirmed**. The grouped Windows campaign remains pending a compatible
host; no inferred corrected index or history entry is written.
