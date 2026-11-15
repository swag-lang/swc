# Prompt 2 session, 15 November 2026

Eight optimization batches are integrated into local `master`, starting from
`7e3f5b7d6c` and ending at production integration `45fb6bf456`. The session uses
Linux x86-64, GCC 14.2.0 DevMode compilers, Release benchmark programs and three
compiler workers. The requested cutoff is 18:00 Europe/Paris (17:00 UTC).
Evidence is static unless explicitly described as a timing sample. Every landed
batch remains **unconfirmed** by the required Windows cross-language campaign.

The compiler build number, benchmark sources, workload sizes, timed boundaries,
checksums, allocation/reclamation contracts and FP policy are unchanged. Compiler
builds, preserved installations, benchmark executables, caches and probes were
kept outside the checkouts. No changes were pushed to a remote.

## Retained rounds

`I/M/C` means executed native instructions / memory operands / calls. A full
function count is used only when its removed work is unconditional on the stated
path. Each linked report contains the exact code, scope, provenance and caveats.
Every row passed all twelve checksums and a complete verbose Micro comparison,
including equal-count differences and reachable shared runtime changes.

| Round / commit | Task; historical competitor | Cause and general mechanism | Native hot work before → after | Other tasks / runtime | Correctness at landing | Decision / timing |
| --- | --- | --- | --- | --- | --- | --- |
| 1, `a9654c9f5f` | Leven; Odin | Redundant carries; local load/LEA and selected-base forwarding | Cell 17/3/0 → 15/3/0 | Other kernels and runtime unchanged | 1,702 C++; carried-store JIT/native | Landed, unconfirmed; grouped samples noisy |
| 2, `da83050d23` | Binarytrees; Java | Early frame-address copies; form the address in its final argument register | bottomUp 53/20/5 → 52/20/5; release 41/18/5 → 40/18/5 | Same cut in benchFree and two error paths; no hot loss | 1,703 C++; addressed-argument JIT/native | Landed, unconfirmed; grouped samples noisy |
| 3, `4032c0f8cb` | Nbody; Zig | Private floating homes; retain raw bits in idle GP registers | Step 314/118/0 → 316/112/0 | Other kernels/runtime unchanged | 1,705 C++; raw-bit, lane and alias cases; cold-call JIT/native | Landed, unconfirmed; explicit instruction/memory trade, grouped samples noisy |
| 4, `0ea61e3d0f` | Fannkuch; Rust | Repeated integer comparisons; prove flags across every join edge | Flip `(12+7q)/(3+4q)/0` → `(11+7q)/(3+4q)/0` | Two runtime error/read paths lose redundant comparisons | 1,707 C++; executed flags and encoder bytes; repeated-compare JIT/native | Landed, unconfirmed; grouped samples noisy |
| 5, `c6e91a0ac6` | Binarytrees; Java | Adjacent frame zeroing; paired AVX stores with upper-state cleanup | bottomUp 52/20/5 → 50/17/5; release 40/18/5 → 39/16/5 | Same zeroing reduction in shared runtime and one-time ChaCha setup; no changed arithmetic | 1,709 C++; executed buffer/lane/flags and overlap cases; safe-default JIT/native | Landed, unconfirmed; grouped samples noisy |
| 6, `8662eda16c` | Nbody; Zig | Redundant source home; reuse an invariant GP source and free a cache register | Step 316/112/0 → 315/107/0 | Only linked Nbody body changes | 1,710 C++; executed raw-payload, exit and clobber variants; copy-source JIT/native | Landed, unconfirmed; grouped samples noisy |
| 7, `c5cccbd80d` | Wordfreq; LDC | Entry/fetch placement; reuse nested padding and propagate function alignment to native sections | Outer back-edge interval 87/30/1 → 85/30/1; FNV work unchanged | Only Wordfreq loses executed NOPs; other native instruction bodies unchanged | 1,831 C++ including filesystem; 4,083 JIT + 4,083 native | Landed, unconfirmed; repairs observed placement veto, final grouped controls noisy |
| 9, `12cb2f2670` | Wordfreq; LDC | Common latch reloads; partition incoming private-spill restores | Left advancing mismatch 9/5/0 → 6/2/0; right 9/5/0 → 7/3/0 | Only linked qsort changes; tie/call paths preserve restores | 1,715 C++; eleven executed edge variants; 4,083 JIT + 4,083 native | Landed, unconfirmed; runtime not measured |

Reports: [1](../20261115-leven-carries/README.md),
[2](../20261115-frame-address-arguments/README.md),
[3](../20261115-floating-spill-cache/README.md),
[4](../20261115-join-compare/README.md),
[5](../20261115-wide-frame-zero/README.md),
[6](../20261115-invariant-spill-source/README.md),
[7](../20261115-loop-entry-branch/README.md),
[9](../20261115-call-path-reloads/README.md).

The weighting is retained rather than converting these counts into speedup:

- Leven removes two instructions per executed dynamic-programming cell.
- Binarytrees rounds 2 and 5 together remove 3,372,390 timed instructions and
  3,372,390 memory operands over 674,478 creations and releases. Cleanup is included.
- Nbody rounds 3 and 6 together add one instruction but remove eleven memory
  operands per step: +500,000 instructions / −5,500,000 memory operands over
  500,000 steps. Raw FP bits and arithmetic are preserved.
- Fannkuch removes one instruction per flip, 1,911,505 times; for `k=1..8`,
  `q=floor((k-1)/2)`. A longer NOP encoding adds no executed instruction.
- Wordfreq placement removes two NOP instructions per word with five added once
  at outer entry: 3,999,995 fewer executed instructions. Its four-byte FNV group
  remains eleven instructions and four reads, now constrained to one cache line.
- Wordfreq reload partitioning removes another 77,946 instructions and frame
  reads, weighted by 17,606 left and 12,564 right advancing count mismatches.

## Rejected and revised work

| Investigation | Evidence / decision |
| --- | --- |
| Round 2 broad address rematerialization | Cyclic/heap variants added traffic to worker loops. A cold-region callee-save variant added pushes/pops at leaves and allocator fallback work. Reverted; retained rule uses full-width single-use frame roots in acyclic CFGs. |
| Round 5 wide stores before cleanup | Revised to include VZEROUPPER before every following control boundary and at least two store pairs to repay it. Counts and byte tests cover the final version. |
| Round 7 broad entry alignment | Early variants added NOP work inside shared runtime loops. Narrowed to an existing pinned nested padding budget; then fixed actual native section alignment and the 48-byte FNV cache-line phase. Trial samples remain separate. |
| Round 8 scan-value retention | Correctness and all twelve checksums passed, but this duplicated an existing pre-allocation rule and undid the deliberate post-allocation scan shortening. It traded +3,419,619 instructions for −2,044,258 reads on the exact input. All trial compiler/test changes were restored. [Rejected report](../20261115-rejected-scan-retention/README.md). No timing or retained analysis. |
| Round 9 bypass anchor | An executed branch-around-reload test exposed a real wrong-value case in the trial proof. Removed the conditional-predecessor anchor; the same test passes in the final code. The failing trial log and patch are archived. |

Executed tests also exposed missing valid SETcc aliases in round 4; their exact
encodings were repaired in that batch. Two experimental fixtures needed correction
before acceptance: preserving the C ABI instead of borrowing RBX, and using
canonical constant stack adjustments supported by the unwinder. Negative cases
assert observable semantics rather than forbidding independent valid peepholes.
No known failing source or fixture is retained.

## Timing and the required next campaign

Two-block Linux A/A and alternating A/B/B/A checks used isolated processes,
harness affinity, four warmups, matching input/runtime/configuration and no own
concurrent builds/tests. Complete samples, not selected minima, are preserved in
the [first-group report](../20261115-group1-timing/README.md) and the
[later-group report](../20261115-loop-entry-branch/README.md).

The original rounds 4–6 group showed Wordfreq ratios 1.0974 and 1.1131 beyond
both corresponding A/A ranges. This triggered the round-7 emitter repair rather
than leaving the observed regression. The exact bad image had an FNV loop crossing
a cache line and a classifier group on an unsafe fetch boundary. The final repair
versus that image gives 0.8624 / 0.8522 block medians; the final grouped comparison
versus retained round 3 has no slowdown repeating beyond both A/A spreads. The
large control dispersion prevents any speedup claim. That check covers fannkuch,
binarytrees, nbody, wordfreq, chacha, raytrace, dijkstra and lz77. Round 9 adds no
timing claim.

The combined cross-language Windows campaign cannot run on this Linux host:
the Windows execution environment, MSVC/clang-cl, Windows ABI, NativeAOT and the
campaign's comparable runtime cohort are unavailable. Linux static references
and paired veto samples cannot replace it. On the next compatible host, before
another optimization batch, build the combined revision's Release compiler and
run `tools\bench.bat --no-build --swc-cores 3 --label "prompt 2 20261115 combined"`.
Capture the Windows code/provenance outside measured intervals and compare the
complete task panel and controls. No Windows results or history were modified.

## Latest published competitive context

These are historical **same-campaign raw median ratios**, Swag Release divided
by the fastest non-Swag runtime in accepted Windows campaign `20261023-175718`.
They select work; they are neither this session's outcome nor corrected indices.
All Swag native, frozen-reference and JIT variants are excluded as competitors.
The JSON companion retains full precision and the exact published progress data.

The current history uses protocol 3 `progress.run-release` versus a frozen
reference with 95% intervals. It contains **no `run_index` or `null.run.tasks`
fields**. The published progress below is not a null band. A before/after
corrected-index and null-band table for this session is unavailable; none is
invented or inferred from Linux timing.

| Task | Fastest non-Swag runtime | Historical raw ratio | Published frozen-reference progress [95% interval] |
| --- | --- | ---: | --- |
| binarytrees | java-hotspot | 1.480967x | 0.995542 [0.972018, 1.011969] |
| nbody | zig | 1.053572x | 0.871009 [0.841109, 0.929057] |
| sort | cpp-msvc | 1.032565x | 0.977414 [0.947441, 1.020225] |
| fannkuch | rust | 1.029304x | 0.971822 [0.919293, 1.027658] |
| leven | odin | 0.947307x | 1.034838 [0.929659, 1.080395] |
| lz77 | cpp-clang-cl | 0.928792x | 0.941609 [0.916551, 0.962112] |
| wordfreq | d-ldc | 0.903224x | 0.975840 [0.928199, 0.994889] |
| dijkstra | cpp-msvc | 0.897737x | 1.020576 [0.944997, 1.074953] |
| sha256 | zig | 0.872294x | 1.023681 [0.990847, 1.080543] |
| raytrace | cpp-msvc | 0.855369x | 1.000144 [0.865933, 1.075212] |
| csvagg | odin | 0.855242x | 0.862971 [0.832600, 0.904132] |
| chacha | cpp-clang-cl | 0.855044x | 1.013531 [0.983436, 1.040656] |

The full twelve-task geometric mean is **0.964184x**. For the original seven
tasks only, the separately labelled historical competitive mean is **0.883176x**;
it is not spliced into a before/after improvement. Historically Binarytrees at
1.480967x misses the 1.25x per-task milestone; the twelve-task mean meets 1.15x.
The final revision's competitive ratios and milestone status remain unmeasured.

The provisional Linux static shortlist below is a hypothesis about specific
captured paths, not a measured runtime winner or an exhaustive compiler ranking.
ISA variants remain labelled; ABI, GC/manual release, safety and FP contracts
limit whole-task comparisons. The source-verified competitor references are in
`20261114-linux-x64`; its twelve old Swag attribute fingerprints were stale, so
fresh baseline/candidate Swag captures are used throughout this session.

| Task | Static candidate(s), provisional | Limit |
| --- | --- | --- |
| Wordfreq | Swag / Clang / LDC | Compact Swag FNV; sorting, comparisons and dependent multiply latency remain decisive. |
| Csvagg | Swag / GCC | Parsing, aggregation and ordering cannot be ranked from hashing alone. |
| Sha256 | Swag | Strong compact two-round kernel; setup and contracts still matter. |
| Dijkstra | Swag / Clang | Heap growth and data-dependent sift/relaxation work. |
| Raytrace | GCC | Compact intersection loop; square roots, branches and FP policy. |
| Leven | Clang / GCC / Swag | Cell versus row-copy work and dependency latency; Swag's cell is now shorter. |
| ChaCha | Swag / Clang-v3 | Compact register-only SIMD kernel; ISA and setup differ. |
| Nbody | Clang-v3 / Zig-v3 | Fewer instructions versus memory/dependency work, with different FP scheduling. |
| Fannkuch | Swag / Clang | Copy widths, rotations and permutation-dependent trip counts. |
| Binarytrees | Java C2 / CoreCLR | Bump allocation/GC and manual per-node reclamation differ. |
| Lz77 | Swag / GCC | Match lengths and nested search frequencies need dynamic weighting. |
| Sort | Swag / Clang | Three-instruction memory scans versus retained values and shorter partition work. |

## Final validation, preservation and handoff

The final combined compiler passes **1,832 C++ tests including filesystem cases**,
and its final production code passes **4,083 JIT + 4,083 native DevMode tests**
plus native owning/pointer error suites. A final cross-configuration pass also
executes **4,044 JIT + 4,044 native Release tests**, with both native error suites
passing; the smaller count reflects configuration-selected cases. All twelve
Release benchmark checksums
pass for every accepted batch. The session-level direct initial/final comparison
and its [complete native review](combined-native-review.json.gz) are retained
here separately from per-batch proof. No function is added or removed. All
changed loop intervals keep or reduce their instruction/memory counts except
the explicitly weighted Nbody trade; the reachable shared-runtime changes are
the same general zeroing, argument and comparison reductions already reviewed.
[Changed-function summary](combined-changed-functions.json) records the scope.
The C++ formatter was applied only to changed ranges, retaining CRLF source files.
No whole-repository formatting or unrelated test campaign was performed.

`compiler.optimization.055` is removed because the common latch restores are
gone; stale claims that Nbody's five mass loads remained blocked were removed
earlier. Other unresolved entries keep their identities and next actions. The
rejected scan experiment is a report, not a new backlog item.

Each report preserves source/compiler/binary identities, checksums, code and
analysis costs. Gzip/JSON integrity checks pass for the session's evidence.
Compilation probes retain every before/after sample and child peak RSS; their
noise supports no compiler-speed or memory claim. The campaign worktree/branch
and external temporary trees are removed after the final evidence commit.

The stopping condition is the requested time budget, not completion of the runtime
milestones. The first next action is the compatible-host combined Windows campaign;
Binarytrees' allocator/runtime difference and Fannkuch's proven-disjoint copy
opportunity remain substantive leads. Do not restore the already rejected guarded
copy or duplicate scan-retention experiments without new evidence.
