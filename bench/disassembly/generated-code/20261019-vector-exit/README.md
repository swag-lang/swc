# Share a carried vector with its loop-exit value

Prompt 2, based on `dbacddc8c6`. DevMode compiler, Release programs. The existing
same-value coalescer now considers full-vector copies whose source is also used
after the enclosing loop. Integer confinement, definition/liveness interference
proofs, nested-loop restrictions, preserved copies and forbidden registers remain
in force. No new analysis is added; vector candidates skip the confinement walk.

ChaCha's four new state vectors remain live after their latch copies because the
output step consumes them. Treating each source and its carried destination as
interfering kept four moves per double round. They hold the same bits wherever
both are live, so joining them removes the moves before register allocation.

| Executed region | Before | After | Memory operands |
| --- | ---: | ---: | ---: |
| ChaCha double round | 51 instructions | 47 instructions | 0 / 0 |
| Outer block loop, excluding repeated double rounds | 34 instructions | 34 instructions | 18 / 18 |

The original workload runs 262,144 blocks and ten double rounds per block:
10,485,760 register moves disappear from the timed region. Final PE disassembly
confirms the four `vmovups` instructions disappear. See the retained loop listings.
The checksum remains `633277775`.

The latest accepted complete campaign used for selection is `20261018-194437`,
commit `333f92f7a1`. Its fastest non-Swag ChaCha runtime is Odin, 26.9627 ms,
against Swag's 22.3771 ms (ratio 0.82993). The installed Odin reports
`dev-2026-09-nightly:a2fb372`; the benchmark recipe is `-file -o:speed`.
Its retained executable runs 106 scalar instructions and nine frame-memory
operands per equivalent double round. Both ports perform the same unsigned
32-bit rounds and exclude input generation and allocation from this region.
This comparison motivates the register-residency work; it is not a new timing.

All twelve original benchmark checksums match before and after. Their function
and loop instruction/memory/call counts change only in `Chacha.__main_0` after
grouping overloaded functions and generated lambda/expression ordinals that vary
between compilations. In particular, nbody, raytrace, SHA-256, the allocator fast
paths and all other benchmark loops acquire no extra work. The raw comparison
and its normalized summary are retained beside this report.

Validation:

- 1,537 C++ tests pass, including the new vector loop-exit case and a counterexample
  where the old carried value is still observed, under all three call conventions.
- Without the change, the new C++ test fails; with it, 1,475 non-filesystem C++
  tests pass on the final binary.
- The complete native Release suite passes 3,858 tests, including its expected
  recovery-failure probes.
- JIT Release `--file-filter simd.swg` passes one test.
- Backlog validation, clang-format and `git diff --check` pass.

Three alternating six-worker `core_rebuild` pairs compare compilation cost.
Candidate / baseline median wall times are 3,682.0 / 3,787.8 ms. Peak committed
memory is 993.2 / 1,005.8 MiB; peak working set is 971.9 / 965.8 MiB. Median paired
baseline / candidate ratios are 1.015 wall, 1.014 CPU, 0.990 commit and 0.995
working set. This small panel establishes no compiler-time or memory improvement.

Runtime timing: not measured. Status: landed on static evidence, unconfirmed by
a full corrected campaign.
