# Protect a repeated loop entry and its nested fetch window

Prompt 2, production baseline `7de28dd2de`. GCC 14.2.0 DevMode compiler on
Linux x86-64; Release benchmark programs, three workers, forced regeneration,
separate installations and caches. [Provenance](provenance.json) identifies both
compilers, all twelve linked binaries, complete assembly/Micro hashes and sources.
Benchmark computations, workloads, timed boundaries, checksums and FP policy are
unchanged. The compiler build number is unchanged.

The grouped Linux veto after batches 4–6 exposed a Wordfreq placement defect.
Against the retained batch-3 executable, its two block median ratios were 1.0974
and 1.1131, versus A/A ranges 0.9761–1.0605 and 0.9837–1.0873. Inspection of the
actual linked executables found identical hot instructions at different fetch
positions: the byte-classifier CMP/Jcc crossed a 64-byte boundary in the slower
image, and its 48-byte FNV loop crossed a cache line. The original reference and
regression functions, symbol maps and every timing sample are retained here.

The emitter already protects closing loop branches using the same boundary rule
as LLVM MCAssembler: a fused group must neither cross nor end on its 32-byte
boundary. It now also considers the first internal forward branch in a loop's
entry block. An enclosing header may move only when:

- the entry group fits the first 32 bytes and there is no intervening label or branch;
- every closing group remains safe in either 16-byte phase;
- an already pinned nested header can absorb at least sixteen existing padding bytes;
- the containing header has not already been pinned.

This moves padding from a repeatedly executed nested entry to the containing loop's
entry. Flat scans, retry loops, exit tests and conflicting branch phases retain
their layout. A nested loop of 33–64 bytes on a 32-byte phase may additionally use
the other half of a cache line. That extra half-line shift occurs before the outer
loop. Existing wider nested phase constraints block this extension. The widest
pinned window becomes the function's required alignment.

The native builders previously aligned function offsets but retained the section's
default 32-byte alignment. That does not preserve a 64-byte function constraint
after sections are combined. Both the common native image builder and COFF object
writer now raise the section alignment from startup/functions as well. Existing
cache metadata already stores power-of-two function alignment; JIT allocations
already start on executable-page boundaries. No new cache format or JIT allocation
path is introduced.

| Linked Wordfreq region | Baseline | Candidate |
| --- | --- | --- |
| Complete main | 1,742 bytes | 1,774 bytes |
| Outer linear back-edge interval | 87 instructions, 6 NOPs, 30 memory operands | 85 instructions, 4 NOPs, 30 memory operands |
| Classifier CMP/Jcc relative start | 638, phase 30 modulo 32 | 686, phase 14 modulo 32 |
| FNV four-byte interval | 11 instructions, 4 reads, 0 calls | unchanged |
| Required function alignment | 32 bytes | 64 bytes |

The candidate's actual main begins at `0x40a8c0`, and its first FNV loop is
`0x40abc0..0x40abee` inclusive: the 48-byte interval fits one cache line. Its
classifier group is also clear of both 32- and 64-byte boundaries. The ordinary
baseline capture happened to have a cache-line-aligned FNV loop; the previously
timed regression image had the same loop at `0x40ab60..0x40ab8e`, crossing
`0x40ab80`. The new requirement makes the good phase a placement constraint.

The two removed NOPs execute once per word, not once per scanned byte or FNV
iteration. There are exactly 2,000,000 nonempty words and an ending separator.
The wider outer entry adds five NOP instructions once, giving 3,999,995 fewer
executed instructions in the timed region. Arithmetic, loads, stores, calls,
register assignment and branch destinations are otherwise unchanged. This is a
weighted execution count, not a claim that every instruction in the linear
back-edge interval executes on every byte.

All twelve checksums pass the complete verbose Micro comparison. Matching overload
body multisets removes ordinal/name changes; remaining build-configuration `#run`
handles are compiler-side and absent from linked code. Complete native comparison
finds no changed non-NOP instruction body. Wordfreq is the only task with changed
loop instruction counts or function size/NOP counts. Allocator fast paths, retry
loops and all other task kernels retain their instruction/memory/call counts.
Complete assembly and symbol maps for both sides of every task are retained.

Validation passes all 1,831 C++ tests including filesystem cases, and 4,083 JIT
plus 4,083 native DevMode tests. New emitter cases cover internal entry branches,
flat/exit counterexamples and a nested 48-byte loop's 64-byte placement. Six
in-memory native artifact cases check 32/64/128-byte constraints owned by startup
or ordinary functions in the common image and serialized COFF section.

Earlier trials were narrowed before acceptance. Protecting arbitrary forward
entry branches added padding inside page-reclamation work. Restricting them to
internal branches still added entry NOPs to four shared runtime functions. Reusing
existing nested padding removes those costs. A 32-byte-only repair remained
sensitive to the FNV loop's cache-line phase; its comparison samples are retained
as trial evidence, not substituted for the final revision's samples.

The final grouped Linux check covers fannkuch, binarytrees, nbody, wordfreq,
chacha, raytrace, dijkstra and lz77 against the same retained batch-3 executables.
Each task has two blocks of six A/A and alternating A/B/B/A pairs, four warmups,
process isolation and harness affinity. Own builds/tests were idle. No final
slowdown repeats beyond both blocks' A/A spread; the controls include large
outliers and do not establish a speedup. [Timing summary](timing-summary.json)
and the complete original, trial, repair and final samples preserve the uncertainty.
These are Linux veto checks, not a cross-language campaign or corrected indices.

The extra analysis uses existing jump/label tables. Its worst-case additional
scan is O(J²(J+L)), for J jumps and L label slots, with the short entry-prefix
checks rejecting most pairs before the inner scans. Labels and pin candidates
each retain two additional 32-bit fields. The before/after compilation and peak
RSS samples are retained separately; no compiler-speed claim is made.

All landed batches remain **unconfirmed** by the required full Windows campaign.
That campaign, corrected task indices and null bands require a compatible host;
no inferred Windows history or `run_index` was written.
