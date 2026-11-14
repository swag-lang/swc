# Reuse a local value instead of its duplicate spill home

Prompt 2, based on `f9ad11b570`. DevMode compiler, Release programs. A post-RA
rule redirects 64-bit spill reloads to an identical value already stored through
the stable local-frame base. It requires the two stores to be adjacent, proves
their entry-relative locations disjoint, and stops at control flow, calls,
unknown writes, aliases, or redefinitions of either frame base. It leaves the
spill store until the existing all-path dead-store proof can remove it.

That proof now normalizes stack accesses across known stack adjustments, models
pushes and pops, and uses the actual scalar memory width for arithmetic and FMA
operands. It can cross a direct internal Swag call only when ABI normalization
proves all arguments and the return use registers, with no hidden transport or
shadow space, and the private home is above the callee stack pointer. Foreign,
indirect, closure, fallible, indirect-value and stack-argument calls remain
barriers. Internal variadics carry one register pointer to their packed slice.

| Executed region | Instructions before / after | Memory operands before / after |
| --- | ---: | ---: |
| nbody step | 403 / 396 | 170 / 163 |
| csvagg scan loop | 410 / 407 | 82 / 78 |
| SHA-256 outer block loop | 194 / 193 | 61 / 60 |
| Leven loop 15 | 106 / 105 | 30 / 29 |
| Leven loop 16 | 133 / 130 | 45 / 42 |
| LZ77 loop 10 | 124 / 122 | 17 / 15 |
| LZ77 loop 11 | 131 / 129 | 20 / 18 |

The original nbody workload runs 500,000 timesteps. Seven duplicate spill writes
disappear per step: 3,500,000 fewer executed writes. The retained final PE
assembly confirms the same 403 / 170 to 396 / 163 counts, with no calls in the
loop. Its checksum remains `169096566666`. Main as a whole shrinks from 735
instructions / 334 memory operands to 728 / 327, with three calls in both.
The frame size and the arithmetic dependency chain are unchanged.

Selection used the accepted `20261018-194437` campaign: nbody's Swag / fastest
other ratio is 1.23175, against Zig's 17.1885 ms. The installed Zig is 0.15.2;
its actual recipe is ReleaseFast, x86_64-windows-msvc, linked with the CRT.
The competing source and PE both use the same pair interactions and position
updates. Its packed/scalar square-root and division shape differs. Earlier
experiments packing all ten interactions were neutral on this latency-bound
step; this batch changes only redundant frame traffic.

All twelve checksums match. After grouping overloads and generated lambda/run
expression ordinals, only the six task main functions listed in `normalized.txt`
change their instruction/memory/loop counts. Dijkstra main loses three cold
spill stores; its loops are unchanged. No reachable benchmark hot loop gains
instructions, memory operands or calls; allocator fast paths are unchanged.
The raw comparison retains false LOSS rows caused by overload order, alongside
the normalized summary rather than hiding them.

Analysis cost: one linear entry/base scan, at most 512 instructions per duplicate
store candidate, and lazy stack-depth maps. The existing dead-spill CFG walk
retains its 4,096-visit bound per candidate; a lazily computed ABI call-reference
set adds work proportional to call signatures. All incomplete proofs decline.

Validation:

- 1,539 full C++ tests pass. New cases cover normalized stack addresses, pop
  readers, partial arithmetic/FMA aliases, hidden and stack call transport,
  integer/floating reloads, opaque/indexed aliases and control-flow barriers.
- With the implementation disabled, exactly the two new test families fail;
  the earlier 1,475 non-filesystem tests still pass.
- Final non-filesystem C++ run: 1,477 pass, including the additional stack-base
  alias and conflicting-join cases.
- Complete native Release suite: 3,858 pass; expected recovery-failure probes
  complete and the tool exits zero.
- Complete JIT Release suite: 1,539 pass.
- Repository/backlog validator, clang-format dry run and `git diff --check` pass.

Three alternating six-worker `core_rebuild` pairs compare compilation cost.
Candidate / baseline median wall times are 6,178.6 / 5,675.6 ms; median CPU times
are 28,250.0 / 24,781.2 ms. Peak commit is 998.6 / 994.5 MiB and working set
974.1 / 969.6 MiB. Median paired baseline / candidate ratios are 0.906 wall,
0.837 CPU, 0.984 commit and 0.995 working set. The last baseline sample rises to
7,719.4 ms / 35,640.6 CPU ms, so this small, drifting panel cannot establish a
stable compiler-cost ratio. The additional bounded analysis remains a potential
compilation cost; the accepted benefit is generated work, not compilation speed.

Runtime timing: not measured. Status: static improvement, unconfirmed until the
session's corrected cross-language campaign.
