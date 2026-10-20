# Sort and LZ77 generated-code work

The session targets the timed sort and LZ77 workloads without editing their sources,
inputs, checksums or timed boundaries. Baseline source was `71f642e258`; its Release
compiler and runtime were preserved outside the checkout. The first four batches
are integrated in `18e7b8a166`, including concurrent prompt 4 changes. The Release
compiler measured by the first campaign was built from that combined revision.

| Batch | Mechanism | Static evidence in the executed path | Correctness |
| --- | --- | --- | --- |
| `e35b5cb833` | Reuse the first scan's compared value across read-only control flow | One fewer reload per partition swap | 1,549 C++ tests, 4 Release JIT/native cases, all 12 checksums |
| `78eafb8a84` | Parallel shift/add for `x * (2^k + 1) + y` | Three hash stages: 12 to 6 modeled arithmetic dependency cycles; whole hash 12 to 15 instructions, with no extra memory or spill | 1,556 C++ tests, 3 Release JIT/native cases, all 12 checksums |
| `c68640e492` | Retain the second scan's value through an equivalent pointer copy | Partition swap falls from 4 to 2 memory operations overall: two stores, no reload | 1,556 C++ tests, 4 Release JIT/native cases, all 12 checksums |
| `ea56174785` | Root `[base + (induction - fixed)]` at `base - fixed` | Decompression 8 to 6 instructions per output byte, same 2 memory operations | 1,557 C++ tests, Release JIT/native replay across 42 overlapping and zero-length cases, all 12 checksums |

All native regression runs used the DevMode compiler, Release programs,
`--validate-micro`, and six compiler workers. Final native code was inspected.
The compiler version/build identity was not changed. Captures and output caches
were kept separate between compilers.

The scan read becomes a load and a register comparison. Each scan advance has
four encoded instructions instead of three, but LLVM-MCA 20.1.8's Meteor Lake
model gives both forms three uops and the same 110 cycles over 100 iterations.
This is a model, not a measured speedup. No frame growth, spills, added calls or
saved registers were introduced in qsort.

Two incidental loop rotations duplicate an entry test in the listing: LZ77's
untimed data-generation copy and `Allocator.releaseAll`. For k executed body trips,
the allocator's old shape has 11k + 3 instructions and the new one 10k + 3, with
the same k + 1 header loads. The additional textual memory operand is the duplicated
entry test. Allocation fast paths retain their work. Function and enclosing-loop
totals alone must not be read as dynamic costs.

The hash's single-block LLVM-MCA model changes from 21 to 15 cycles and reciprocal
throughput from 3.0 to 2.3. Inputs, shifts and intermediate arithmetic keep their
original widths; flags, shared products and independently live addends retain their
original code. No general power-of-two-minus-one rewrite was retained: a naked
shift/subtraction rewrite would lose an existing bounded-remainder proof.

Analysis cost: compared-load search is bounded to 96 instructions; candidate
reloads require bounded predecessor traversal and stable SSA addresses. The scan
value may be reused through one proved full-width base copy. Scaled-add matching
uses at most two product sides, one copy and the existing 32-instruction window.
Invariant-subtraction rooting reuses LICM's loop and dominance facts and checks
that the computation dominates every loop tail and exit.

## Measurements

Initial paired sort/LZ77/wordfreq measurements were noisy and stayed inside
unchanged A/A controls. They neither confirmed a speedup nor supplied a veto.
All paired samples are retained in `paired-initial.json`.

The full campaign of `18e7b8a166` agreed on every checksum across every runtime
and completed all fourteen allocator workloads. The harness rejected its timings:
the reference workload departed **67.4%** from a neighbouring probe around leven,
beyond the 40% limit. Compilation measurements without a confirming pair were
omitted individually. The complete unaltered record is
[20261020-072804.json](../../rejected/20261020-072804.json).

No new history entry or corrected execution index is derived from that rejected
campaign. The latest accepted campaign remains `20261019-181609`; all four batches
above are **landed, unconfirmed**. The preserved baseline Release SHA-256 is
`177851dd23113d633f92dc301bfda972d60ca7654a8bb4cba94d2832218a1ab7`;
the measured combined Release SHA-256 is
`6197fa1ff94beea91f152b043d2307c79b145c789dfd687b0d5ac9f43272e739`.
No session builds or tests overlapped the campaign.

The next candidate for constant unsigned division follows the even-divisor
pre-shift construction in [LLVM's DivisionByConstantInfo](https://llvm.org/doxygen/DivisionByConstantInfo_8cpp_source.html).
It is not part of the four-batch compiler above.

## Eligibility repairs after the first campaign

The comparison reload proof now rejects materialized labels on a traversed path,
and LICM rejects loops with a materialized body entry. Such an entry can bypass
the read or the new preheader even when ordinary CFG predecessors appear closed.
The all-path scan fixture also retains an atomic/volatile-load boundary.

Scaled-add reassociation now accepts only leaf addends through bounded copies
and extensions. A weighted accumulation such as `acc += byte * 33` must keep one
addition on the loop-carried accumulator path; the reassociated form would put two
there. Computed addends and partial definitions retain their original arithmetic.
The LZ77 hash's byte loads remain eligible.

All three new internal regression groups failed with the pre-repair implementation.
After repair, all 1,561 C++ tests passed. The complete optimizer source directory
passed 316 tests through JIT and 316 natively in DevMode with `--validate-micro`.
All twelve Release benchmark checksums and instruction/memory/call/loop counts
match the four-batch compiler after overloaded runtime bodies are paired.
These repairs therefore preserve the target changes reported above.

## Copied zero-test exits

A copied raw integer followed by its exact-width zero test can send its taken
edge straight past an equivalent join test. This changes LZ77 verification from
13 to 9 instructions per byte, with two reads, no calls and unchanged frame,
saved registers and spills. Eight instructions execute on each matching byte,
instead of twelve; the mismatch clear remains conditional.

Canonical setcc chains require an additional flag proof: their original
comparison need not leave the join's zero-test flags. A reduced internal carry
reader fails before this correction and passes after it. Raw copied zero tests
retain equivalent flags and permit live consumers. Following the actual exit's
control flow keeps waitWork and dynamic-view hot paths unchanged and removes one
instruction from parkWorkObserver; it avoids the conservative prototype's extra
tests. The eligibility adds only adjacent matching plus a flag-liveness query
for canonical exits.

All twelve checksums pass. The final comparison is in `microdiff-batch5.json`.
Other timed benchmark kernels retain their work. Shared equality/reallocation
paths shrink without added memory operations or calls. Allocator.configure's
cold first-false path gains one instruction, while its early true path skips
the remaining conditional moves; this is outside the benchmark timed regions.

Validation: 1,506 in-memory C++ tests; 2,312 prefix/initial-state/mismatch cases
through JIT and native in Release and DevMode with micro validation; all twelve
Release checksum/code captures and final native-loop inspection. The full C++
pre-correction run has only the expected new carry-reader failure (1,567 pass).
Timing is not measured for this batch.

## Even-divisor pre-shifts

An unsigned even constant that needs a multiply-high correction now removes its
power-of-two factor first and computes the odd-divisor multiplier with the newly
proved leading zero bits. This is a general divisor property. Quotients use the
shifted dividend; remainders retain the original dividend and original divisor.
Odd divisors and already correction-free multipliers retain their expansion.

Sort's checksum loop changes from 59 to 52 instructions per two input values,
with the same two reads, no calls and unchanged saved registers, frame and spills.
The emitted native loop uses `shr 3; mulhi 0x20c49ba5e353f7cf; shr 4` for `/1000`,
then reconstructs the remainder with the original value. This matches the relevant
D-LDC construction without changing the benchmark source. CSV's affected loop
changes from 407 to 402 instructions, and Dijkstra's affected inner loop from
182 to 174, with unchanged memory operations and calls. Allocator.maybePurge
loses two instructions outside its loops. No other generated body or loop cost
changes after overloaded bodies are paired; see `microdiff-batch6.json`.

Validation: all 1,507 in-memory C++ tests, including width/remainder/live-flags
eligibility; two native source tests through JIT and native with micro validation;
512 pseudorandom inputs per width plus zero, signed boundaries, maximum unsigned
values and divisor/multiple neighbours, compared with unoptimized dynamic division.
All twelve Release checksum/code captures pass; the final native checksum loop
was inspected. Analysis adds at most one width-bounded multiplier computation for
an eligible even divisor. Timing remains unconfirmed pending the grouped campaign.


## Finite signed counter ranges

A straight-line natural loop with one signed constant-limit latch now proves a
nonnegative finite range for its counter. Full-width positive increments must
form one SSA chain; every initial phi input must be a nonnegative literal. The
maximum entry value and the entire step must fit the signed width, including the
final trip. Internal branches, external or materialized entries, unknown seeds,
partial definitions, dynamic limits and live arithmetic flags retain their code.
Copies may forward a proved counter value at the same width.

The range supplies leading-zero facts to unsigned constant division. A positive
64-bit operation narrows to 32 bits only when both its dividend range and divisor
fit u32, preserving the full observed result by zero extension. Divisors larger
than the proved dividend range produce zero quotients or unchanged remainders.
The new facts are local to this pass invocation and the original instruction IDs.

Sort's checksum loop changes from 52 to 43 instructions per two values (59 before
the two division batches), with two reads and no calls. Its native `%7` uses a
plain wide product by `0x24924925` and a shift, removing the signed multiply-high
correction. The prologue, saved registers, stack accesses and frame stay unchanged.
All eleven other benchmark bodies and loops retain their instruction/memory/call
profiles after pairing overloads; all twelve checksums pass. See
`microdiff-batch7.json`. The proof scans eligible loop bodies and phi inputs once,
only when an existing nonnegative proof fails; copy queries retain the existing
depth limit. It reuses cached SSA, dominators and natural loops.

Both new structural C++ groups fail before this change, with the other 1,508
passing. All 1,510 pass after it. The focused source passes JIT and native in
Release, including negative starts, signed wrap boundaries, and positive 64-bit
dividends/divisors above s32 but within u32. The complete optimizer directory
passes 320 JIT and 320 native tests in DevMode with micro validation. Native loop
instructions and all twelve checksum/code captures were inspected.

## Second measurement attempt

The Release compiler at `60ce9cd521`, including copied zero-test exits and even
divisors, has SHA-256
`81250d8e7f15f42ae1d073196f13e9746db4011af98dbeb2b3b50787c011716b`.
Its twelve Release checksum/code captures match the validated DevMode compiler.
The integrated group passes 1,508 in-memory C++ tests and 319 optimizer tests
through both JIT and native in DevMode with micro validation.

Its default full campaign started at 10:18 Paris and was stopped at 10:44 after
the completed reference probes already made rejection unavoidable: SHA-256's
115.3 ms probe follows CSV's 44.0 ms, a departure of about 162%, beyond the 40%
limit. No later sample can remove that adjacent departure. Only this session's
verified benchmark process tree was stopped. No session build or test overlapped
these measurements. Wordfreq, CSV, SHA-256 and Dijkstra checksums agreed across
all runtimes before stopping. The unrecorded partial console is retained in
`group6-aborted-console.txt`; no history entry or performance claim comes from it.
The finite-counter batch above was built and tested after this attempt stopped.
