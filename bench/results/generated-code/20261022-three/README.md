# CSV aggregation, nbody and sort

Prompt 2 starts at `2e8511af06`. The benchmark sources, workloads, checksums and
measured boundaries remain unchanged. DevMode compiler, Release benchmark programs.
Temporary installations, caches, listings and build outputs are outside the checkout.

## Overlapping dynamic comparison tails

`Swag.memcmp` compares the remaining range with a head and a tail of the largest
fitting scalar width. Both reads stay in the requested range; the head mismatch
wins when their ranges overlap. Exact-width ranges skip the redundant tail read.
Keeping the consumed offset rather than the original remaining length across the
head comparison avoids adding an integer clobber to this leaf's calling contract.

The equal-key paths in the emitted x64 code have these executed instruction and
memory-operand counts, including entry and return, excluding alignment NOPs:

| Key length | Before instructions | After instructions | Before reads | After reads |
| --- | ---: | ---: | ---: | ---: |
| 1 | 25 | 20 | 2 | 2 |
| 2 | 28 | 24 | 2 | 2 |
| 3 | 32 | 26 | 4 | 4 |
| 4 | 28 | 22 | 2 | 2 |
| 5 | 32 | 29 | 4 | 4 |
| 6 | 35 | 29 | 4 | 4 |
| 7 | 39 | 29 | 6 | 4 |

CSV's eight region strings have lengths 4, 4, 4, 5, 6, 6, 7 and 4. Its successful
comparison therefore saves an average 6.125 instructions and 0.25 memory operands
per row, about 2.45 million instructions and 100,000 reads over 400,000 rows. A
mismatch in the head retains its ordering and skips the overlapping tail.

All twelve Release benchmark checksums pass. Task kernels and their callers are
unchanged, including their saved registers and spills; only the shared dynamic
comparison body changes after overload ordinals and generated names are paired.
The vector loop retains its work. The six focused `memory_dynamic` tests pass
through JIT and native in DevMode, including all mismatch positions, unaligned
sizes through 65 bytes, and opposite-order mismatches in overlapping ranges.

A 24-round pinned alternating comparison of the final binaries is exploratory:
CSV candidate/base median 1.0418 with range 0.8181..1.7084 and unchanged A/A median
0.9721; wordfreq candidate/base median 0.9816 with range 0.7625..1.2412 and A/A
median 0.9866. These dispersed observations do not establish a speedup or a
reproducible slowdown. The batch is accepted on executed static work and remains
**landed, unconfirmed** until the grouped campaign.

## Dead floating clears

The physical-register lane-demand analysis now removes a clear only when no lane
of its result can reach an observation. Full definitions on every successor can
kill that demand; partial scalar copies, aliased arithmetic inputs, calls,
materialized control flow, claimed rewrites and unknown operations retain it.
Clear removal runs after floating memory folding so a pending erased lifetime
marker cannot obscure that sweep's reload fusion.

Nbody's actual native timestep changes from **390 to 375 instructions**, with
**145 memory operands**, five packed roots and five packed divisions unchanged.
It executes 500,000 times: the batch removes 7.5 million zeroing instructions,
without changing arithmetic, memory traffic, saved registers, spills or calls.
The full main changes 753/339 to 738/339 instructions/memory operands. The
out-of-line `advance`, unused by the fully inlined benchmark, loses one clear.
[Before](nbody-clear-base.asm) and [after](nbody-clear-new.asm) are emitted x64.

All twelve Release checksums pass. Other benchmark kernels and shared runtime
paths are unchanged after overload ordinals and generated names are paired.
The complete Micro comparison is in [clear-microdiff.txt](clear-microdiff.txt).
Correctness: 1,542 in-memory C++ tests pass, including executed vector-lane and
both-branch observations before/after optimization; 324 optimizer source tests
pass through JIT and native in Release with `--validate-micro`. The final compiler
has no temporary tracing instrumentation. Compiler build identity is unchanged.

The analysis uses the existing four-bit lane lattice over the CFG, restricted
to functions with unclaimed floating clears. This adds a candidate scan and one
lane-demand solve after memory folding; unsupported control flow declines it.
Timing is **not measured** for this batch; its runtime gain remains unconfirmed.

## Repeated integer comparison exits

A taken conditional edge can bypass an identical ordered integer comparison at
its destination when the destination branch has the same or opposite condition.
Both comparisons read the same physical registers at the same width, so this
also preserves carry, overflow and every other arithmetic flag. Floating,
different-width, swapped-operand and intervening-flag-writer cases retain their
code. The transformation runs after register allocation; a pre-allocation trial
added a saved register and was discarded.

Sort's qsort retains 99 instructions, 23 memory operands and two call sites.
Its five saved registers, frame, spills, scans and swap instructions are unchanged.
The no-swap partition exit bypasses one compare and one conditional jump: **two
fewer executed instructions on that exit**, with no added work on any other path.
This now matches MSVC's direct exit shape, while retaining Swag's two-store swap
without reloading the values scanned. [Before](sort-exit-base.asm) and
[after](sort-exit-new.asm) show the emitted native branch targets.

All twelve Release checksums pass; no other task kernel or runtime path changes
after overload ordinals and generated names are paired. The complete comparison
is in [thread-microdiff.txt](thread-microdiff.txt). All 1,544 in-memory C++ tests
pass, including signed/unsigned conditions at four widths and negative flag cases.
The new `repeated_compare_exits` source test passes through JIT and native Release
with Micro validation, covering 16,641 signed cursor ranges and extreme inputs.
The analysis indexes labels and scans candidate edges in linear time. Timing is
**not measured** for this batch; the grouped campaign owns the runtime verdict.

## Copies across calls

After ABI arguments have been staged, a full-width copy between independent
virtual integer registers can precede the call. The source must be dead on every
successor after the copy, including loop back edges; physical operands, partial
writes and copies involving an indirect call target are left in place. This runs
once on converged pre-allocation code and preserves the order of copy chains.

Sort's recursive qsort changes **99 to 95 emitted instructions**, with its 23
explicit memory operands and two call sites unchanged. Its cursors now use
transient registers: only three persistent registers are saved, instead of five.
Every invocation avoids two pushes and two pops, including the insertion-sort
leaves. Scans, swaps, arithmetic and recursion stay the same. See emitted x64
[before](sort-copy-base.asm) and [after](sort-copy-new.asm).

All twelve checksums pass; [the full Micro comparison](copy-microdiff.txt) covers
both kernels and reachable runtime code. Wordfreq's qsort has the same executed
instructions, spills, memory accesses and calls, with renamed registers and its
recursive cursor copy moved before the call. The other eleven task kernels are
unchanged. Shared runtime differences were inspected: allocator release and task
recycling add one entry copy, with their loop body counts and spill traffic
unchanged; thread joining adds one argument copy; TLS heap initialization trades
one saved register for an entry branch/copy. Error-context traversal retains its
counts, and error-message traversal loses a saved register and two instructions.
Heap retirement moves one existing spill reload before a call. These paths are
outside the benchmark kernels' timed regions. Atomic overload order and generated
function hashes were paired before review; they do not represent changes.

All 1,545 in-memory C++ tests pass. The new source fixture passes through JIT and
native Release with Micro validation, checking call arguments, the loop-carried
result, and an observable trace for 2,145 input/iteration combinations. No temporary
instrumentation remains. A grouped full timing campaign was started after the
previous three batches, then interrupted because persistent external contention
produced edit-loop median intervals of +/-42.4% and +/-87.8%. Its log is preserved
outside the checkout. No result from that attempt is published or counted as a
win. Runtime gains remain **unconfirmed** until an accepted campaign.

## Preserve pairs through root products

The independent-root packer now recognizes two scalar products using the low and
high lanes of the same packed square root and its original packed inputs. It
emits one packed multiply instead of two scalar multiplies, a high-lane extraction
and the denominator repack. SSA checks preserve the ordered operands and their
values at the insertion point. Shared products, numerator dependencies, mismatched
lanes, redefined inputs, unknown values and nonmatching roots retain the old form.
This uses the existing vectorization and finite-value math gates; it adds no new
floating-point reassociation or approximation.

Nbody's actual timestep changes **375 to 361 emitted instructions**, retaining
**145 memory operands**, five packed roots, five packed divisions, frame layout,
spills and calls. It executes 500,000 times, removing **7 million instructions**.
There are five new packed multiplies, five fewer high-lane shifts and five fewer
unpacks. One existing norm FMA becomes a multiply plus add under the same build
contract, costing one instruction against the ideal fifteen-instruction cut; the
net saving is fourteen. The benchmark checksum remains 169096566666. See emitted
x64 [before](nbody-products-base.asm) and [after](nbody-products-new.asm).

All twelve Release checksums pass. After pairing overloads and generated names,
all other native task kernels and runtime paths retain their code. Compiler-side
`#run` build-configuration adapters carry different process-local handles; their
instruction and memory counts are unchanged. The [complete Micro comparison](products-microdiff.txt)
includes these artifacts. All 1,547 in-memory C++ tests pass, including seven graph
variants for valid pairing and rejected dependencies. The new native source fixture
passes through JIT and native Release with Micro validation; 364 pairs match a
non-optimized scalar function, including very small and large finite magnitudes.
The incidental non-indexable-literal diagnostic was reviewed and corrected before
fixing the rejected test source, with focused diagnostic coverage. Timing remains
**unconfirmed** until an accepted grouped campaign.
