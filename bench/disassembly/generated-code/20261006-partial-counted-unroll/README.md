# Partially unroll exact counted loops without carried spill stores

Large straight-line counted loops with an even exact trip count can execute two
bodies per latch. The original counter advances between bodies, and independent
temporaries use the full unroller's fresh-name rules. Eligibility retains the
original complete-unroll path and rejects internal labels/branches, calls and
CPU-flag consumers. Original relocations are attached to each cloned instruction.
The body is bounded to 16-96 instructions; loops that fit the existing total
full-unroll budget keep its previous treatment.

A private 64-bit integer spill home written in the loop but read only afterwards
can also use the existing caller-saved XMM cache. Its last value is written back
at the exclusive exits. This uses the same alias, overlap, stack and liveness
proof as carried spill caching. It removes the one new per-two-round SHA store.

On SHA-256, two compression rounds now execute 95 final Micro instructions and
four memory reads, against 100 / four before. Neither loop accesses the frame.
This is five fewer executed instructions per two rounds, not a measured 5% time
improvement. A four-round prototype had 180 executed instructions and four frame
stores per group (including its back-edge register copy); it was not retained.

Whole-program totals include duplicated loop bodies and work outside hot loops:

| Program | Instructions before/after | Memory before/after | Explicit RSP before/after |
| --- | --- | --- | --- |
| wordfreq | 579 / 580 | 190 / 190 | 26 / 26 |
| csvagg | 950 / 951 | 240 / 239 | 78 / 77 |
| sha256 | 368 / 410 | 103 / 111 | 30 / 36 |
| dijkstra | 469 / 494 | 204 / 207 | 6 / 6 |
| raytrace | 467 / 467 | 145 / 145 | 65 / 65 |
| leven | 447 / 447 | 109 / 109 | 29 / 29 |
| chacha | 493 / 493 | 175 / 175 | 31 / 31 |

Dijkstra duplicates its input-generation body; its heap processing retains the
same counts. SHA's six additional explicit frame accesses occur outside the
compression loop. Wider unrolling and those outer accesses remain follow-ups.
The 334-function H.264 corpus changes only Pps.buildDequant's counts (+25
instructions, +7 memory operations, +2 explicit RSP accesses). The other 333
function counts match. This corpus comparison uses the preceding spill-cache
snapshot and also includes intervening master/inlining changes.

Validation: Release compiler, Release programs; 287 optimizer tests pass in JIT
and native execution, all seven benchmark checksums agree before/after, and the
23 H.264 tests pass. New tests cover carried values, overlapping array writes,
escaping results, signed 32-bit counters and a non-unit step. No timing campaign
was run. The retained compiler hashes and source hashes identify the comparison;
the baseline executable was built at 9f43f1709 and the candidate includes master
through 4397224a6 plus this lot.

The constant-pool diagnosis previously kept in compiler.optimization.037 was
also checked against the current H.264 dump: both halfHorizontal coefficient
loads and broadcasts already precede the row loop; intraPredict8x8 remains at
972 instructions / 429 memory operations. That old diagnosis was retired, not
claimed as a new optimization in this lot.
