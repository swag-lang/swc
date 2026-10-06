# Carry adjacent loop elements in registers

The pending store-forwarding prototype from `dc9290f89` is retained and extended to
values previously read. A single-block rotated loop carries the value of the element
that a later access read or stored on its preceding trip. Every other store must miss
that element at both relevant index values. Unknown writers, calls, changing stack
pointers, extra loop entries and unsupported address forms prevent the rewrite.
Volatile loads carry the memory-writer flag and therefore also prevent forwarding.

The initial preload lies on the path that enters the first iteration. No preload
executes for a zero-trip loop. All loop plans are collected before storage changes;
producer references survive until every dependent copy is inserted. This handles
chains of adjacent reads and multiple loops in one function.

Compared with the prototype, this implementation checks full-width address roots,
uses wrapping unsigned arithmetic for offsets, strides and disjoint byte ranges,
and runs once after vectorization instead of rescanning every optimization sweep.
The ordinary cleanup loop simplifies the inserted copies.

## Release evidence

The current Levenshtein inner DP loop changes from **18 instructions / 5 memory
operations** to **19 / 3**. Both repeated row loads disappear: the previously stored
`row1[y + 1]` supplies `row1[y]`, and the previously loaded `row0[y + 1]` supplies
`row0[y]`. Neither version accesses the frame inside this loop.

This removes two memory operations on each iteration and the store-to-load recurrence.
It is a structural gain; no runtime timing gain is claimed. The former rejection for
noisy timings does not apply to the user's current static acceptance criterion.

The tradeoff remains visible: the whole main function changes from 438 to 445
instructions, 112 to 115 memory operations and 31 to 35 explicit RSP memory operations.
Initial loads and outer-region register pressure cost work outside the hot loop.
Those remaining allocation opportunities are tracked under compiler.optimization.005.
The full Micro diff and the exact hot-loop instructions are retained here.

The baseline compiler contains `cd799b15d` plus the late-address folding change
`1b38ffc29`; the candidate starts at `a86c11df9`. The intervening merge includes
CodeGen/Sema changes and command-line Micro listing selection. Compiler hashes and
unchanged-source checksum results are recorded in `structural-evidence.json`.

## Validation

- Release compiler build and 281 optimizer tests through JIT and native, including
  the three added regression tests: store recurrence, unknown aliasing writes,
  ascending/descending read windows, chained producers and multiple loops.
- Official unchanged benchmark programs retain matching checksums: Levenshtein 67441,
  SHA-256 2503168387 and LZ77 622942003053.
- The same 334-function H.264 cohort as the previous two lots has identical emitted
  Micro bodies after normalizing printed relocation addresses and record order.
  Its instructions and memory-operation counts are unchanged; its runtime suite
  was not repeated for this lot.

All compiled programs use Release, six compiler workers, rebuilt artifacts and fresh
machine-load admission. The imported internal C++ fixtures are retained for the normal
C++ campaign; no DevMode compiler was built or used for this lot.
