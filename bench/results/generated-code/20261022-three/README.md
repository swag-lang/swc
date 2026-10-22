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

## Amortize bounds in byte sentinel scans

A bounded unsigned byte scan now tests the bound once per four bytes. Every byte
comparison still branches immediately on the sentinel, in source order: there is
no wider load, read ahead or read after the first match. A free transient integer
register holds the last safe group start; otherwise the original loop stays.
The original scalar loop handles short tails. Flag-neutral exit stubs preserve
the index and comparison flags; later peepholes may use INC only when those flags
are dead. Signed/narrow bounds, nonunit steps/scales, mismatched exits, displaced
address overflow, multiple header entries and unavailable scratch registers decline
it. O2 uses the existing partial-unroll factor and its existing cap.

CSV's four scans change from **five instructions per missed byte to eleven per
four missed bytes**, excluding alignment padding. Entry checks, the scalar tail
and early-exit stubs are included in an [executed instruction model](scan-cost.json)
over the unchanged 400,000-row generator: **112,710,023 to 78,185,533 instructions**
for these scans, a reduction of 34,524,490. Both sides read the same 22,862,004 bytes.
The full main grows 852 to 952 static instructions and 221 to 237 static memory
operands because the scalar tails remain; its frame, spills, saved registers,
arithmetic and eleven calls are unchanged. See emitted x64 [before](csv-scans-base.asm)
and [after](csv-scans-new.asm). These counts are static evidence, not a timing claim.

All twelve checksums pass. After overload/name pairing, every other task kernel
and shared runtime path keeps its code; only the CSV scan regions change, plus
process-local handles in compiler-side build-configuration adapters. The [full
Micro comparison](scan-microdiff.txt) records every path. All 1,549 in-memory C++
tests pass: thirteen recognition/rejection shapes and 5,316 executions before/after
optimization check byte alignment, every early-match lane, short tails, empty and
inverted bounds, the final index and live exit flags. The native source fixture
checks 15,538 scan answers through JIT and native Release with Micro validation.

The previous call-copy liveness walk is shared with legalization instead of
keeping two CFG walks, preserving legalization's implicit-backedge-use policy.
Executed physical-IR tests now share the existing JIT emission seam, and the older
comparison-exit fixtures use an ordinary scratch register instead of RSP. Full
comparison and correctness checks cover these mechanical changes as well.
Timing remains **unconfirmed** until an accepted grouped campaign.

## Reuse whole-vector lane differences

When an unpack combines the low and high scalar differences of the same two
vectors, the instruction combiner now reuses one packed subtraction. Scalar
consumers keep the low result or extract the high result from that vector.
SSA checks retain the ordered inputs, follow scalar copies, and require the full
inputs to remain available. Observed upper lanes, meaningful phis, destructive
uses, calls, redefined inputs, narrow copies and mismatched lanes decline the
transformation. Fresh result names preserve destination/input aliases. The
existing vectorization, finite-value math and non-destructive encoder gates
apply; there is no new arithmetic reassociation or approximation.

This runs after ordinary instruction combines settle. Packed loop promotion
exposes the inputs during the cleanup after SLP, so recognizing it inside SLP
alone has no effect. A direct-input-only prototype transformed one pair but
added register traffic (361 to 363 instructions, 145 to 146 memory operands);
it was not accepted. Following SSA scalar copies exposes all ten pairs.

Nbody's actual timestep changes **361 to 340 emitted instructions** and
**145 to 128 memory operands**, retaining five packed roots, five packed
divisions and no calls. Its 500,000 iterations remove **10.5 million
instructions and 8.5 million memory operands**. Stack operands fall 117 to
100; body-address operands remain 27. Register allocation and existing FMA
selection change, so these are final machine-code counts, not an estimate
from replaced Micro nodes. The checksum remains 169096566666. See emitted
x64 [before](nbody-lanes-base.asm) and [after](nbody-lanes-new.asm).

All twelve Release checksums pass. After pairing overloads and generated
names, all eleven other task kernels and shared runtime paths retain their
code. Compiler-side build-configuration adapters differ only in process-local
handles. The [full Micro comparison](lanes-microdiff.txt) includes every path.
The scalar-lane proof rebuilds SSA after each disappearing unpack: at most
one rebuild per accepted pair, plus a final scan. Its extra cost is O(P*N)
instruction/use work plus the existing SSA construction cost for P pairs in
an N-instruction function; functions without an unpack stop at the cheap scan.
All 1,551 C++ tests pass, including twenty recognition/rejection graphs and
144 before/after machine-code executions. The execution test compares both
scalar results and both packed lanes bit for bit, including signed zeros,
small/large finite inputs, and destinations that alias their inputs. A source
fixture that did not activate the new fold was removed rather than counted
as positive coverage; the benchmark checksums cover the native source boundary.
Runtime timing remains **unconfirmed** until an accepted grouped campaign.

## Compare scans in memory, reload only for a swap

A read-only indexed scan whose last value feeds later work now compares in
memory and reloads that value at a proven common observation point. Every
incoming path to the reload must carry the same original read and address;
dominance alone would miss a killed value merging back or a reload reentered
after a write. Uses, partial definitions, address changes, writes, calls and
returns stop motion. Full definitions may kill a path. Integer result-width
classification is shared with the existing post-RA dead-copy check. Only
ordinary integer loads, matching compare widths, 64-bit addresses and unit
steps qualify. Multiple frontiers, bypasses and unsupported CFGs decline it.
All matching scans are handled before the pass indexes loop rotations, so
the post-RA sweep budget does not leave other loops unrotated.

Sort's two scans change **four to three emitted instructions per missed
element**. Both final values are reloaded only on the swap path, before the
first write, including when the two addresses alias. The rest of qsort keeps
its code: **95 to 93 static instructions**, **23 to 25 explicit memory
operands**, three saved integer registers and two calls. See emitted x64
[before](sort-values-base.asm) and [after](sort-values-new.asm).

The [execution-count model](sort-values-cost.json) reproduces the unchanged
300,000-element generator and checksum 599499929. It counts 3,377,515 missed
probes, 1,043,181 partition episodes and 1,022,129 swaps. Including entry and
final probes and both reloads, scan work changes **19,769,146 to 16,349,527
instructions**: 3,419,619 fewer. It adds **2,044,258 reads** of the final probed
addresses. This instruction/read trade is explicit; the model does not assign
cycle costs or establish a speedup.

All 1,556 C++ tests pass, including twenty recognition/rejection shapes and
2,522 before/after machine-code executions checking forward/backward scans,
early stops, live exit flags, aliases, discarded values and a partial-register
kill. All twelve Release checksums match. After overload/name pairing,
all eleven other kernels and native runtime functions retain their code;
compiler-side build adapters differ only in process-local handles. See the
[complete Micro comparison](sort-values-microdiff.txt). Analysis is lazy after
matching the exact loop shape. Each accepted split rebuilds the CFG/order and
liveness; the frontier and reverse equivalence walks visit each edge once.
The extra work is O(P*(N+E)) plus existing dominator construction for P splits
in an N-instruction/E-edge function.

Two short, 32-round diagnostics retained every sample and checked all binary
hashes and checksums. They interleave new/old/competitor and reverse that order
on alternate rounds, with an unchanged new/new control. These are **not full
accepted campaigns** and compare existing competitor binaries from the prior
accepted campaign, rather than rebuilding every language in the same hour.

| Diagnostic | New/old ratio, 95% CI | New/competitor ratio, 95% CI | A/A ratio, 95% CI |
| --- | --- | --- | --- |
| [Nbody lane fold](nbody-lanes-probe.json) | 0.9394 [0.8365, 0.9911] | Zig: 1.026 [0.9286, 1.115] | 1.032 [0.9320, 1.133] |
| [Sort scan values](sort-values-probe.json) | 0.9928 [0.9563, 1.064] | MSVC: 0.9936 [0.8556, 1.051] | 0.9425 [0.8631, 1.043] |

Median measured foreign load was 3.86 and 3.41 cores respectively. Both targets
are near their competitors in these probes; neither superiority nor a runtime
gain beyond the broad A/A bands is established. Both batches are **landed,
unconfirmed**, with no timing veto observed.
