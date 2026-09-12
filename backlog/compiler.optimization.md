# Optimization Backlog

Backend optimization passes, register allocation, and the performance of the code `swc` generates.
Frontend and lowering defects are [compiler.core.md](compiler.core.md).

Entries are ordered from the most recently updated down. [README.md](README.md) defines
the shared backlog conventions.

Several entries address register residency, loop-entry shape, spill traffic, aliasing and
inline argument materialization. Earlier measurements used the whole-hull allocator; optimizing
builds now use interval splitting, so those measurements identify workloads to recheck rather than
current performance guarantees. `MicroSsaState` reconstructs SSA and phi values for analysis, while
the executable Micro instruction stream has no explicit phi instruction. Since build 438 a call the
straight-line path steps over — a safety panic, a cold refill — no longer constrains the split
allocator: a value crossing it in a caller-saved register is parked in its home inside the cold
block, and the hot path keeps the register.

### compiler.optimization.029 — The pre-RA optimization loop rebuilds SSA after every mutating pass

- Recorded: 2026-09-05 22:13
- Updated: 2026-09-11 22:17 — Use the current benchmark entry points for core and hello-world measurements.
- Area: compiler/backend, compilation time
- Found while: the compile-speed campaign, profiling `bench/compile.py core_rebuild` (std/core in
  `devmode`, six worker cores, Release 0.1.367 with a PDB, a user-mode sampling profiler).
- Observation: `runLoopPasses` is the largest single item of a full rebuild — 13.9 % of all
  thread samples, about 40 % of the CPU actually spent (a third of the samples are workers
  parked on the job queue) — and it is the largest item of a hello world build too (22 %) and of
  `swc sema` on an empty file (14 %, the JIT lowering of the prelude's `#run`). Inside it the
  SSA state is the cost: `MicroSsaState::build`, `ensureFor`, `renameBlock`, `reachingDef` and
  `createPhi` add up to about 8.5 % of samples, more than any transform. `runPass` invalidates the
  whole shared SSA state as soon as a pass reports `passChanged`, so every sweep of the fixed
  point rebuilds it from scratch for the next pass that asks, however local the mutation was.
  `devmode` is `O1`, "everything that does not cost compilation time", and this does.
- Updated evidence (2026-09-06): external sampling of Release compiler 0.1.383 rebuilding a
  private copy of tracked `bin/std` sources, six workers, still finds SSA construction prominent.
  For `core` in `devmode`, 30 of 151 samples inside `JobManager::executeJob` include
  `MicroSsaState::build`; in `release`, 25 of 131 do. The corresponding `CodeGenJob` counts are
  110 and 99. These are inclusive stack counts, with each sample counted once per function;
  they are attribution evidence, not independent percentages to add or unprofiled timings.
  Repeated builds by the same baseline compiler also produce different raw PE `.text` hashes,
  so a whole-section hash alone cannot establish whether an SSA change preserves code quality.
- Updated evidence (2026-09-07): Release compiler 0.1.390, six workers, an isolated Pixel rebuild
  gave 518 CPU-weighted external stack samples. SSA construction accounted for 22.15% of the
  sampled CPU, renaming for 11.63%, and the entry-snapshot call in `renameBlock` for 5.82%.
  The corresponding GUI-only profile attributed 12.94% to SSA construction. These are inclusive
  shares, not costs to add together. Each block snapshots every active tracked register, and
  each mutating pass can repeat the work. Reusing block scratch storage alone did not establish
  a consistent speed/memory improvement and was removed; `repo.tooling.008` records that trial.
- Next: trace rebuilds and mutating passes externally on GUI and Pixel to size the win, then keep the
  SSA state valid across the mutations that preserve it — a deleted instruction, a renamed
  operand, a folded constant — and rebuild only the blocks a pass touched otherwise. Measure `core_rebuild` with
  `bench/compile.py --against`; `hello_build` belongs to the full `tools/bench.swgs` campaign,
  which also checks generated code across the seven benchmark tasks.
- Complete when: `core_rebuild` and `hello_build` move by the share the profile attributes to SSA
  rebuilds, at identical generated code on the seven bench tasks, and the `native` suite is green.
- Related: compiler.core.004, compiler.core.030.

### compiler.optimization.006 — A hot loop's loop-carried locals all live in stack slots

- Recorded: 2026-08-15 08:48
- Updated: 2026-09-11 22:17 — Correct the experiment count and retain the current split-allocator rebaseline boundary.
- Area: compiler/backend
- Found while: making `Compress.Inflate` fast. The library side of that is done and shipped —
  the block loop keeps its cursors in locals and refills branchlessly, and it went from 62 MB/s
  to 119 MB/s. What this entry keeps is the part no source shape could reach: the same algorithm
  written line by line in C and compiled by clang-cl `/O2` runs at 191 MB/s, so 1.6x is left and
  all of it is in the emitted code.
- Observation: `#[Swag.PrintMicro("post-emit")]` on the block loop against clang's assembly for
  that C transcription. **Every loop-carried local is a stack slot.** The bit buffer, the bit
  count, the source cursor, the output cursor and the decoded symbol are each loaded and stored
  on every symbol; a table entry read once in the source is stored to a stack temporary and
  re-loaded twice. In the literal fast path — ten live scalars, fifteen usable registers — that
  is 31 stack loads and 8 stack stores against clang's zero. The prologue also materializes ~25
  field addresses and spills each one. mem2reg is not the culprit and was checked:
  `pre-mem-to-reg`/`post-mem-to-reg` differ by 212 promoted instructions, so it promotes what it
  should and the allocator puts the values back.
- Evidence: measured 2026-08-15 on an otherwise idle machine, release config, on the 12.8 MB
  deflate payload of `8_9_2025_15_43_58.scc` (17.0 MB out, 14.76 M symbols, 1.21 bytes per
  symbol — a stored photograph, so the loop runs about once per output byte). Best of several
  alternating runs: clang-cl `/O2` 88.8 ms (191 MB/s), a bare Swag prototype of the same loop
  121.7 ms (139 MB/s), the shipped `Compress.Inflate` 141.9 ms (119 MB/s). Swag block loop 619
  instructions against clang's 411. **Machine load moves every one of these numbers by up to 3x,
  so only same-run comparisons mean anything** — an earlier pass of this measurement read
  122 ms for clang and 176 ms for Swag, and the ratio was the only part that survived.
- Five experiments ruled out by measurement, so they are not retried:
  - **zlib's two-level decode table.** Written in C beside the current design, same payload:
    93.8 ms against 88.8 ms — *slower*. Only 6.7% of length codes and no distance code at all
    miss the nine-bit fast table on this data.
  - **Lifting the cold paths out of the loop.** The Huffman fallback and the slow refill moved
    into `#[Swag.NoInline]` functions taking the bit cursor by value and handing it back: 3%.
    So the allocator is not evicting the loop-carried scalars because cold blocks compete with
    them; it evicts them anyway.
  - **Eliding the shift width guard.** Implemented in `CodeGenSafety::emitShiftIntLike` (skip
    the materialized count, width compare and conditional move when the count is a constant or
    a mask by one, looking through casts and parentheses), verified to fire — 14 conditional
    moves down to 8 in the block loop — and measured at **zero**, twice, on a quiet machine.
    The loop is latency-bound on the serial bit-cursor chain and its stack round-trips, so
    removing twelve independent instructions changes nothing. Reverted. Since 2026-09-10 the
    guard no longer exists at all: a shift amount must be below the value's width, and release
    emits the bare instruction — so this workload should be re-timed without it.
  - **Two symbols per refill, and pre-tabulated masks and packed base+extra words.** Zero each.
  - **A shuffle-based fill for matches closer than eight bytes**, which libdeflate carries and
    this loop still copies one byte at a time. Counted rather than timed, over the IDAT of the
    PNG fixtures: matches at a distance of two to seven bytes produce 2.7% of the output on
    `rgb.png` and 3.3% on `rgba.png`, against 78% for distances of sixteen bytes and up, which
    already run on vectors. The whole path is too small to pay for the two shuffle tables.
- Current boundary: `Pass.RegisterAllocation.Interval.cpp` now supplies live-range splitting for
  optimizing builds, with the older scan retained for `-O0` and failed preconditions. The historical
  spill counts above predate that allocator and cannot establish the current gap.
- Next: repeat the same Inflate/clang comparison and count frame accesses with the current Release
  compiler. If a gap remains, attribute it to the split allocator or its fallback before selecting
  a change; do not implement a second interval allocator.
- Complete when: the current emitted loop and alternating timing decide whether an allocator gap
  remains, with any surviving cause reduced to one actionable change.
- Related: compiler.optimization.005, compiler.optimization.024.

### compiler.optimization.036 — A constant offset ahead of an indexed access is not folded into it

- Recorded: 2026-09-12 13:05
- Area: compiler/backend
- Evidence, read from LLVM's output on the H.264 CABAC residual parser (clang-cl /O2 /arch:AVX on
  the same algorithm, scratch `cabacres/resbench.c`): clang reads the context array with one
  operand, `movzx r11d, byte ptr [rdx + r8]`, where Swag computes the array's address first,
  `lea rcx, [r10 + 0x98]`, and then indexes it. `tryFoldLeaConstIntoAmcIndex` folds such an offset
  into the *index* of an indexed access; nothing folds it into the *base*.
- Attempted 2026-09-12, reverted: `tryFoldLeaConstIntoAmcBase`, refusing a frame-derived base and
  an address with more than one reader, and erasing the folded computation. It pays where it was
  read from - the five residual parsers 3563 to 3536 instructions and 264 to 240 frame accesses,
  `bookkeepMb` 590 to 574, `parseResidualCabac` 243 to 229 - and `intraPredict8x8` pays for all of
  it: 927 to 1083 instructions and 340 to 452 memory operands, fifty more address computations and
  the spills they cost. Narrowing the rule to reads, or to stores, or off the address-computation
  form, moves nothing: the regression follows the reads of the predictor's own reference arrays,
  which are frame locals, though `isFrameDerivedAddress` answers for their base.
- Next: reduce the predictor's regression to a probe and find why folding the offset of a frame
  array into its reads costs a sixth of the function, before re-enabling the rule. The suspicion is
  that slot promotion or the vectorizer recognizes the array by the shape of its address.
- Complete when: the fold lands with the CABAC gain and no kernel regression.

### compiler.optimization.037 — Asking whether a call failed costs an opaque call

- Recorded: 2026-09-12 14:10
- Area: compiler/backend, runtime
- Evidence: every call to a `fail` function is followed by `sub rsp, 0x28`, `call __hasErr`,
  `add rsp, 0x28`, `movzx`, `test`, `jcc`. `__hasErr` is 23 instructions and reaches the thread
  context through `__tlsAlloc`/`__tlsGetPtr`, two further calls, to read one 32-bit field. The
  check is therefore an opaque call in the middle of whatever loop contains it: the allocator
  must spill every caller-saved value around it, which is most of why
  `Slice.parsePlaneResidualCabac` spent 104 frame accesses on 427 instructions.
- What it cost the H.264 decoder: the arithmetic layer raised errors per residual block, so a
  macroblock paid about twenty-seven of these. Moving the two conditions to the macroblock loop,
  where FFmpeg puts them, took the CABAC path from 81 calls to 62 and the kernel set from 19603
  to 19452 instructions. The library is fixed; the compiler cost remains for every other `fail`
  in every program.
- Next: emit the check inline. The context pointer a function already needs can be fetched once
  and the check becomes `cmp dword ptr [ctx + hasError], 0` and a branch - two instructions
  against an opaque call. `Swag.setContext` inside the callee is what makes a cached pointer
  unsound, so either the fetch stays per check (still no call if `__tlsGetPtr` is inlined) or the
  language states that the context register may be cached across a call.
- Complete when: a fail-call's error check emits no call, and the decoder's macroblock path shows
  it.

### compiler.optimization.035 — Legalization cannot stage a value without a free register

- Recorded: 2026-09-12 11:40
- Area: compiler/backend
- Evidence: the interval allocator holds one callee-saved integer register out of its pool for the
  legalization that runs on its own output. Measured on the 76 H.264 kernels at build 497, giving
  that register back is worth 80 instructions and 177 frame accesses (19676 to 19596, 1914 to
  1737), against 39 more prologue saves. It cannot simply be given back: without the reserve the
  `pixel` and `gui` modules fail to compile, the scan allocator reaching
  `SWC_INTERNAL_CHECK(false)` with no register it may name.
- What exists: the reserve is now paid only by a function whose allocation took every integer
  register **and** that carries a shape whose legalization may need a register of its own
  (`Encoder::mayNeedLegalizeScratchRegister`). Ordinary functions keep the register. The H.264
  kernels still pay it: they carry shifts by a register and multiplies, whose rewrites move an
  operand through a named register and save the occupant in a fresh virtual.
- Boundary: `Pass.Legalize.cpp` stages through a virtual register and forbids it every physical
  register live across the instruction, so a saturated function leaves it nothing. The
  scratch-frame scaffolding (`stackScratchFrameSize` / `insertScratchFrame` /
  `computeStackScratchBaseOffset`) is wired and unused, and the float-immediate rewrite already
  demonstrates the other way out, a transient push/pop around the staged sequence.
- Next: make the staged rewrites fall back to a frame slot (or a push/pop pair that the stack
  adjustment normalization already understands) when no physical register is admissible, then
  drop the reserve entirely and re-measure the kernels.
- Complete when: no allocation holds a register back for legalization, `pixel` and `gui` compile,
  and the kernel frame traffic drops by the measured amount.

### compiler.optimization.034 — Keep Dijkstra heap values across stores and branches

- Recorded: 2026-09-07 10:46
- Updated: 2026-09-07 11:12 — Narrow the remaining gap to aliasing and control-flow reuse
- Area: compiler/backend, memory optimization
- Found while: the generated-code campaign, comparing Dijkstra's heap loops with current
  clang-cl and MSVC output at `8d3f0498b` on 2026-09-07.
- Evidence: after local identical-target load forwarding, Swag release's sift-up loop has
  26 instructions / 15 explicit memory operations, against clang-cl's 16 / eight and MSVC's
  15 / eight. Five Swag accesses reload global pointer cells; ten access heap elements,
  including the values read again after the comparison branch. These are program-memory
  accesses, not allocator spill slots. The sift-down loop still has 39 / 20.
- Boundary: the local forwarding cache is flushed by control flow and potentially aliasing
  stores. Reusing a global pointer across an arbitrary heap write needs a provenance proof;
  keeping the heap elements already read by a comparison needs control-flow-aware memory
  availability. An exact relocation identity alone proves neither.
- Next: establish which heap stores cannot reach the global pointer cells, and propagate a
  compared element only along paths with no intervening aliasing write. Preserve the global
  reload when a pointer can address that global, and exercise both branch outcomes, calls,
  and zero-trip loops. Recount the individual heap loops and check register pressure across
  every benchmark task before broadening the alias analysis.
- Complete when: the remaining repeated pointer/element reads disappear with sound alias and
  control-flow proofs, or a focused experiment identifies the register-residency constraint.

### compiler.optimization.032 — Partially unroll the SHA-256 compression rounds

- Recorded: 2026-09-06 14:53
- Updated: 2026-09-07 09:52 — Reject two- and four-round clones that increase frame traffic
- Area: compiler/backend
- Found while: comparing current SHA-256 output with both C++ compilers, 2026-09-06.
- Evidence: the 2026-09-07 comparison at `8d3f0498b` reproduces the earlier counts. With
  `/O2 /EHsc /std:c++20`, clang-cl and Swag release both emit 74 instructions and five explicit
  memory operations per compression round. MSVC emits 224 instructions and eight memory
  operations for four rounds, or 56 / two per round; its accesses read only `KTAB` and the
  message schedule. Counts exclude labels and do not count address-only instructions as memory.
- Attempted 2026-09-07, reverted: bounded partial unrolling of divisible exact trip counts,
  retaining the original counter and inserting its add/compare between cloned bodies so that
  counter readers, forward exits, and incoming CPU flags keep their original behavior. Internal
  labels and relocations were cloned as in the existing full unroller. Four rounds emitted
  296 instructions / 25 memory operations (74 / 6.25 per round); two emitted 146 / 12
  (73 / six per round). Neither approaches MSVC's register residency. The sixteen-word input
  decode improved from 16 / five per word to 58 / 20 per four words or 30 / ten per two words,
  but that smaller win does not justify increasing traffic in the compression loop. No timing
  claim or correctness acceptance was made for either rejected prototype.
- Observation: duplicating the body alone does not eliminate the carried-state frame accesses
  described in compiler.optimization.005. The current pass only fully unrolls at most eight
  trips; merely raising that limit is a different experiment, compiler.optimization.002.
- Next: trace which carried-state values acquire the extra frame accesses after cloning, and
  evaluate copy coalescing or independent register webs before retrying partial unrolling.
  Compare every hot loop across the seven tasks, with counter, exit, relocation, and carried-value
  regression coverage if a prototype improves the emitted code.
- Complete when: grouping rounds lowers both instructions and frame traffic per compression round
  with correctness coverage, or the remaining register-residency prerequisite is isolated.
- Related: compiler.optimization.005, compiler.optimization.016.

### compiler.optimization.033 — CSV aggregation retains a cross-file map-probe call

- Recorded: 2026-09-07 09:33
- Area: compiler/inlining, generated-code performance
- Found while: the generated-code campaign, comparing current clang-cl, MSVC, and Swag release
  output at `8d3f0498b` on 2026-09-07.
- Evidence: both C++ compilers inline `mapProbe` into CSV aggregation. Swag calls it once for
  each of 400,000 input rows. Its declaration is in `bench/src/swagnat/bytemap.swg`, while the
  caller is in `csvagg.swg`; `shouldAutoInline` in `SemaInline.cpp` rejects a different source Ast before
  considering the body budget. The delimiter scans already match C++ at five instructions and
  one memory operation per character. The extra extension in the numeric scans preserves Swag's
  byte-width subtraction and cannot be removed merely because C++ promotes that subtraction.
- Constraint: cross-Ast inlining requires safe publication and rebinding of the callee body,
  and an acyclic completion dependency. The generic cross-Ast attempt in std.video.005
  miscompiled the `aoc2019` smoke; removing the source-Ast gate alone is not a safe fix.
- Next: establish a same-module, non-generic cross-file eligibility and publication contract,
  then compare the inlined map-probe loop and its caller's frame traffic. Keep benchmark sources
  unchanged and exercise cross-file binding and the script smokes with parallel compilation.
- Complete when: the call disappears with correct cross-file binding and better emitted code,
  or a focused experiment identifies which remaining eligibility rule prevents the gain.
- Related: std.video.005.

### compiler.optimization.005 — Complex loop-carried frame slots still lose registers

- Recorded: 2026-08-07 08:30
- Updated: 2026-09-06 14:45 — git: Narrow the remaining SHA-256 frame-residency lead
- Area: compiler/backend
- Found while: the same campaign, asking why the identical loop compiles differently in two places
- Observation: loop-invariant reloads and a single read/write carried slot are promoted, but the
  pass refuses a group of mutually dependent carried slots and a carried slot whose register is
  reused between its load and store. Those are the shapes left in the hottest benchmark loops.
- Historical evidence, before the current split allocator: sha256's `a`..`h` were eight
  slots at once and each one's register IS reused between its load and store, so the
  carries-nothing-else test fails on all eight. Leven's DP loop writes `row1[y+1]` through a
  program pointer, which makes the body opaque to the aliasing model: any non-frame write may alias
  any frame slot.
- Current evidence (2026-09-06, release, `6ac854243`): Leven's inner DP loop has 22 instructions
  and five memory operations, all through program arrays, with no allocator spill. Its enclosing
  loops still access the frame; do not infer an inner-loop promotion opportunity from their
  inclusive spans. The separate adjacent-element reuse opportunity is compiler.optimization.030.
- Current sha256 evidence (`d4cc0a0cd`, same configuration): the compression round has 74
  instructions and five memory operations. Two loads read `KTAB[i]` and `w[i]`; one frame load and
  one frame store carry `d` through `[rsp + 0x438]`, while another store writes the new `e` to
  `[rsp + 0x440]`. The other carried state is already in registers. The historical eight-slot
  diagnosis no longer describes this loop.
- Next: trace the remaining `d` carry and the stored copy of `e` through pre/post allocation,
  then inspect Leven's enclosing loops before selecting a change. `promoteCarriedSlots`
  still requires one load/store pair, an unredefined register and one converged exit; if these
  restrictions bind the current code, evaluate group promotion or narrower residency. For Leven,
  distinguish allocator spill storage from addressable program objects before refining aliasing.
- Complete when: current loop dumps either retire this lead or identify a measured promotion or
  residency improvement with aliasing and multi-slot regression coverage.

### compiler.optimization.030 — Carry adjacent DP row values between Leven iterations

- Recorded: 2026-09-06 14:23
- Area: compiler/backend
- Found while: comparing the unchanged Leven benchmark with clang-cl and MSVC, 2026-09-06.
- Evidence: after the boolean-select fold, Swag's inner DP loop has 22 instructions / five memory
  operations; clang-cl has 16 / three and MSVC 18 / five. Swag's five accesses name the input byte
  and DP rows, not allocator spill slots. Clang carries the already loaded `row0[y+1]` forward as
  the next `row0[y]`, and the just-stored `row1[y+1]` forward as the next `row1[y]`.
- Next: establish the two rows' disjointness, then evaluate forwarding those adjacent elements
  across one loop backedge. Prove the entry values, affine stride, intervening writes, and exits;
  keep this separate from frame-slot promotion and compare every benchmark loop for new spills.
- Complete when: the two repeated loads disappear with aliasing and zero-trip coverage, or a
  current experiment identifies the specific missing proof or register-pressure cost.

### compiler.optimization.004 — Tracking frame addresses transitively through mem2reg does not pay on its own

- Recorded: 2026-08-07 08:30
- Updated: 2026-09-06 07:51 — git: prompt 6
- Area: compiler/backend
- Found while: closing the generated-code gap `bench/` measures (campaign 20260806-202546,
  geometric mean 1.41-1.54x the better of clang-cl and MSVC over two baseline campaigns)
- Observation: mem2reg records direct copies and constant-offset addresses of its detected frame
  base. It does not derive arbitrary second-level addresses transitively, so `mov %x, %ar` and
  `lea %x, [%ar + off]` from an already derived address — a copy of a known frame address, and a second-level offset from one —
  both read as escapes and poison the whole variable. Instrumenting the escape analysis, those two
  shapes are the top cause in the timed function of five of the seven bench tasks (csvagg main
  56 and 29 times, chacha main 222, wordfreq 24, leven 16). Deriving them transitively instead —
  a bounded fixed point over copies and constant leas, with disqualification propagating down the
  chain — is a correct generalization and buys nothing measurable.
- Evidence: two A/B sweeps per binary on csvagg, leven, sha256 and wordfreq, each sweep
  self-normalized by the clang-cl and MSVC numbers measured in it: csvagg -7%, leven +12%,
  sha256 +1%, wordfreq +6%, every one of them smaller than the same binary's own spread across
  sweeps (csvagg's baseline alone ranged 1.473x to 1.785x). Statically it costs instructions:
  csvagg main 781 -> 796, leven 526 -> 538, sha256 main 449 -> 421. Reading the loop bodies
  explains it — no hot loop changed, and csvagg's four byte-scan loops got worse, `p += 1` going
  from `add r8, 1` to `lea r10, [r8+1]` plus `mov r8, r10`. Reverted.
- Re-tested after memory-form mem2reg support and loop reload hoisting, on the suspicion that the
  `lea`+`mov` regression was only the copy-forwarding gap those changes closed. It is not: judged on the loop bodies rather than the
  clock, the emitted code moves AWAY from clang-cl. csvagg's four byte-scan loops go back from 6
  instructions to 7 (clang-cl emits 6), leven's inner loop 206/80 to 218/89, and over every loop
  body 3258 to 3299 instructions and 1170 to 1180 memory operations. Reverted a second time.
- Next step: the escape counts were real but not binding, so the remaining value is in what they
  were masking rather than in the derivation itself. Do not re-attempt the derivation on its own a
  third time. If it returns, it has to come with an explanation of why promoting those extra slots
  makes register allocation emit FEWER memory operations in the loops, not more — the two
  measurements so far both say it emits more.
- Related: [compiler.optimization.005](#compileroptimization005--complex-loop-carried-frame-slots-still-lose-registers)

### compiler.optimization.011 — A SIMD routine keeps its strides and counts in the frame

- Recorded: 2026-08-24 13:31
- Updated: 2026-09-06 07:51 — git: prompt 6
- Area: compiler/backend
- Found while: std.video.001, after mem2reg was taught the vector load and store and the memory traffic
  of the motion-compensation path fell by a quarter.
- Observation: promotion now reaches the vector temporaries, so the intermediate values of a
  `#simd` expression stay in registers. What is still in memory is everything the local
  allocator put there: `Video.H264.mcChroma` emits 635 instructions with 81 frame stores and 119
  frame loads, and its interpolation loop reloads the two splat sources on every row. The loop of
  `Video.H264.copyPlane` shows what the shape should be — after post-RA hoisting learned that a
  private frame cannot be reached by a store through a program pointer, its sixteen-byte copy is
  seven instructions with no frame access at all — and mcChroma does not get there because its
  own locals escape into helpers, which keeps its frame from being private.
- Evidence: 2026-08-24, release, `#[Swag.PrintMicro("post-emit")]`. mcChroma 707 -> 635
  instructions and 108 -> 81 frame stores across this pass; copyPlane 111 -> 104 instructions,
  its hot loop 10 -> 7 with 3 -> 0 frame accesses. The decode of one 2496x1440 picture went from
  10.1 to 8.5 ms of processor time (minimum of five interleaved pairs), and motion compensation
  is 44 percent of that picture.
- **The same shape was measured in H.265 before the split allocator (2026-08-26, std.video.005).** Three hot routines dumped at pre-emit, all of them
  already vectorized and already at their instruction budget on paper:
  - `Hevc.Decoder.filterLumaEdge` emits 776 instructions with **87 frame stores and 84 frame
    loads** — 22 percent of the function is stack traffic. It filters 101,633 four-line
    segments a picture at about 575 cycles each, where the instructions a segment executes
    predict something closer to a hundred.
  - `Hevc.Decoder.interpolateLuma` keeps twelve vector spills and twelve reloads inside its
    innermost body. One call filters about 800 samples in 1.73 microseconds, which is 8.6
    cycles a sample against about three from the instruction count.
  - Reading the filter taps once a block instead of once a pair removed fifteen table-pointer
    loads and twenty multiplies from the same function and **changed the measured time by less
    than one percent**, which is what says the loop is not bound by those instructions.
- **What that is worth, measured against another compiler on the same algorithm (2026-08-26)**:
  the loop filter of clause 8.7.2.5 was written twice, once in C and once in Swag, statement
  for statement, over the same synthetic 3840x2076 plane with the same thresholds and the same
  decision mix — 1,612 flat, 430,398 strong and 65,229 weak segments a picture in both. Per
  picture, best of several runs on a quiet machine:
  - clang 21 `-O2 -msse2`: **18.3 ms** (37 ns a filtered segment)
  - clang 21 `-O2 -march=native -fno-vectorize -fno-slp-vectorize`: 18.7 ms
  - clang 21 `-O2 -march=native`: 34.1 ms — **its own auto-vectorizer costs it 1.9x here**,
    which is worth knowing before reading any clang figure as the answer sheet
  - this compiler, release: **40.6 ms** (82 ns a segment)
- In that historical comparison the backend was **2.2x behind clang's best on identical scalar code**, the
  largest single factor in the 3x the H.265 decoder is behind FFmpeg — larger than the 256-bit
  forms of cpu.simd.002, and larger than anything left in the decoder's own algorithms. The frame
  traffic above is the visible half of it: 171 frame accesses in 776 instructions for one
  routine, against 61 in 443 for clang's build of the same function.
- The per-object view shipped (2026-08-26): `Pass.PostRALoopHoist` now classifies escapes per
  source object from the extents `SymbolFunction::localVariables()` carries, recognizes the
  prologue's local-base register, and keeps the two address spaces apart — a value use of the
  stack pointer (call staging) reaches sp-addressed slots, never the locals behind the base. A
  slot inside no escaped object hoists even when the frame as a whole is handed out.
- What that revealed: the pass fires only about twenty times across the whole `video` workspace,
  and in none of the hot decoder functions. The binding constraint is not aliasing any more — it
  is that a hoist needs the reload's destination register to have **no other definition in the
  whole loop body**, and after allocation every register in a fat body is reused many times.
  Post-RA hoisting cannot rename, so it is capped by the allocator's register reuse; the fix
  belongs in allocation (keep the value resident so no hoist is needed), not in a smarter hoist.
  The remaining traffic is
  [compiler.optimization.006](#compileroptimization006--a-hot-loops-loop-carried-locals-all-live-in-stack-slots) again.
- Next: rebaseline `Hevc.Decoder.filterLumaEdge` and `Hevc.Decoder.interpolateLuma` with the now
  shipped split allocator, recording frame accesses and per-segment time. Attribute a remaining
  gap to the selected allocator or its fallback; extend the post-RA hoist only if a current dump
  first shows an invariant value with a reusable destination.
- Complete when: current dumps and alternating timings establish the remaining allocation cost
  on both large kernels and identify a specific next change or retire this lead.
- Related: compiler.optimization.006, compiler.optimization.024.

### compiler.optimization.015 — Carried-slot promotion still rejects multiple accesses or distinct exits

- Recorded: 2026-08-27 07:57
- Updated: 2026-09-06 07:51 — git: prompt 6
- Intent: `promoteCarriedSlots` promotes a carried frame slot accessed N times across several
  branch arms with M exits - one seed load before the header, register-only accesses inside, one
  write-back store per exit edge - instead of only the exactly-one-load, exactly-one-store,
  single-exit shape, mirroring LLVM's `promoteLoopAccessesToScalars`. Branch-dense codec
  accumulators updated in several arms are exactly what the current gate misses.
- Next: extend `promoteCarriedSlots` to a slot with several arms and exits, seed load before
  the header and one write-back per exit edge, and audit the rewrite with the std.video.005 trace.
- Complete when: an accumulator written in two arms of a hot loop keeps its register across the
  back edge with no per-iteration store (dump-verified), a trace-based drop/store audit like
  std.video.005's validates the rewrite, and HEVC serial decode does not regress.
- Related: std.video.005, compiler.optimization.011.

### compiler.optimization.016 — Independent virtual-register webs need a new normalization measurement

- Recorded: 2026-08-27 07:57
- Updated: 2026-09-06 07:51 — git: prompt 6
- Intent: a normalization pass gives every def-use web of a virtual register its own fresh
  register - the SSA property LLVM's passes get from their IR, reconstructed by renaming, with no
  phi nodes needed because a web that spans a join keeps its one name. The lowering reuses
  virtual registers across unrelated computations, so today a loop-invariant chain shares its
  register with code elsewhere in the function (measured on the deblock probe: the `pass % 3`
  chain's register carries five definitions, one outside the loop), and any pass that reasons
  per-register - the web hoisting now in LICM first among them - must refuse the whole register.
- Next: recover or reconstruct the normalization prototype and compare it with the current split
  allocator. Splitting may change the earlier interference tradeoff; it does not prove that
  renaming will now pay.
- Complete when: after the pass, every virtual register's definitions form one connected def-use
  web (verified on a corpus dump); the deblock probe's modulo chain hoists out of its x-loop; and
  the pre-RA fixpoint shows no oscillation with copy elimination (pure renaming inserts no
  instructions, so none is expected).
- Attempted 2026-08-27, parked: a union-find pass over `MicroSsaState` value ids (phi unions
  gated on transitive instruction uses so dead phis stop gluing webs, read-modify-write defs
  unioned with their reaching def) renames soundly - 58 video functions change, both probe
  checksums hold, and the deblock chain does hoist once the pass runs inside the pre-RA loop
  after strength reduction, which is what creates the chain. But the corpus regresses:
  `interpolateLuma` 1583 -> 1684 instructions and 314 -> 398 frame references, video.dll +2 KB.
  The shared names the lowering leaves behind are accidental coalescing the hull allocator
  depends on - splitting them multiplies concurrent hulls, and the allocator pays in spills more
  than the loop passes earn. That result predates the split allocator now shipped here. Re-measure before treating
  the old hull interference as a current blocker. The old session named `webrename-parked/`,
  but no `Pass.WebRename` prototype is present in this checkout; the recorded algorithm is the
  recoverable starting point.
- Related: compiler.optimization.015, compiler.optimization.017; unlocks the full yield of the web hoisting shipped in LICM.

### compiler.optimization.017 — Jump-entered loops have no general preheader normalization

- Recorded: 2026-08-27 07:57
- Updated: 2026-09-06 07:51 — git: prompt 6
- Intent: a small structural pass gives every natural-loop header entered by a jump a fresh
  preheader label - non-back-edge jumps retargeted to it, fall-in preserved - so LICM, RA loop
  residency, `VecLoopPromote`, `PostRALoopHoist` and carried-slot promotion stop declining
  those loops outright. LLVM makes this shape (LoopSimplify) a precondition of its whole loop
  stack; with no phi nodes in the Micro IR it is pure label rewiring here.
- Next: count the loops LICM and `VecLoopPromote` refuse for a jump-entered header on the
  video corpus; implement the preheader only if that count is not zero.
- Complete when: the five loop passes accept a previously jump-entered loop (counted on a corpus
  dump), `BranchSimplify::redirectJumpChains` provably does not thread the new preheader away,
  and the suites stay green.
- Measured 2026-08-27 at the post-RA stage: all 33 natural loops of the release probe corpus
  plus `filterLumaEdge` and `interpolateLuma` enter their header by clean fall-through - the
  rotate pass has already normalized every hot entry by then. The post-RA half has no substrate;
  only the pre-RA half (LICM, `VecLoopPromote`) remains unmeasured. Deprioritized until a pre-RA
  count shows refused loops.
- Related: compiler.optimization.015, compiler.optimization.016.

### compiler.optimization.018 — Dead spill stores have no byte-liveness elimination pass

- Recorded: 2026-08-27 07:57
- Updated: 2026-09-06 07:51 — git: prompt 6
- Intent: a post-RA pass runs a backward byte-liveness fixed point over
  `[spillAreaLo, spillAreaHi)` on the instruction CFG and deletes every spill store no path
  reloads before overwrite - the write-back protocol audited from the consumption side, since the
  allocator manufactures stores wholesale and nothing checks whether any path reads them.
- Next: recover or reconstruct the byte-liveness prototype, check its assumptions against the
  current split allocator, and run the focused spill cases before the full video Release run.
- Complete when: the pass lands with the three known landmines closed - exact read widths (a
  16-byte over-approximation pins the neighbouring 8-byte slot), push/pop and stack-pointer
  arithmetic not treated as area barriers (or the epilogue keeps everything alive), and any
  function with a stack-pointer adjustment between its first and last spill access skipped
  (call-argument setup shifts the offset coordinate system) - and the full video release run stays
  green. An older session recorded a `dse-parked` prototype; it is not present in this checkout.
- Related: the historical lane-count failure was fixed on 2026-08-27; current allocator changes still require fresh validation.

### compiler.optimization.020 — Memory optimizations maintain separate frame alias analyses

- Recorded: 2026-08-27 07:57
- Updated: 2026-09-06 07:51 — git: prompt 6
- Intent: the three existing private frame analyses - LICM's `analyzeFramePrivacy`,
  `PostRALoopHoist`'s `FrameReachability` root model, SLP's parameter-root classification -
  become one shared `MicroPassHelpers` analysis (sp-space / parameter-space / unknown),
  consumed by store-to-load forwarding (a frame-slot cache entry survives an unrelated pointer
  store), the combine passes' window aborts, and `ValueNumbering`'s memory epochs (a store to a
  provably disjoint space stops killing all load numbering; a label whose only predecessor is its
  fall-through stops advancing the epoch). LLVM's analog is BasicAA feeding EarlyCSE and GVN.
- Next: lift `analyzeFramePrivacy` into `MicroPassHelpers` and make the other two users
  consume it, then let store-to-load forwarding survive a disjoint-space store.
- Complete when: the shared analysis replaces all three private copies, forwarding survives
  across a disjoint-space store in a codec inner loop (dump-verified), and instruction counts on
  the video corpus do not regress.
- Related: compiler.optimization.015.

### compiler.optimization.022 — An inlined by-value aggregate argument is copied even when the body only reads it

- Recorded: 2026-08-28 15:42
- Updated: 2026-09-06 07:51 — git: prompt 6
- Area: compiler/sema
- Found while: giving `Core.Math.Simd` its 4x4 and 8x8 transposes (2026-08-28).
- Evidence: `func transpose4x4(rows: [4] U32x4)->[4] U32x4` inlined into a caller that already
  holds the block still emitted four 128-bit loads and four stores copying the argument into a
  fresh frame slot, then read every row back out of that copy, around the eight interleaves that
  are the whole operation: 40 instructions and a 0x1C8 frame for eight instructions of work. The
  same body taking `rows: *[4] U32x4` in place compiles to 28 instructions and a 0x80 frame, which
  is what the API now does. `materializeInlineBindings` binds a by-value aggregate argument to a
  concrete local because the callee may write to its parameter; when the inlined body never
  assigns that parameter, the local is pure traffic and the caller's storage could be named
  directly.
- Next: in `SemaInline`, measure the homes still required by indexed/foreach aggregate uses.
  Elide a copy only when the caller's storage remains unchanged through all reads, including
  indirect calls and alias writes, and when copy/drop hooks and argument evaluation retain their
  semantics. Absence of a direct assignment to the parameter is not sufficient.
- Complete when: a proven stable, side-effect-free by-value aggregate parameter costs no copy
  after inlining, written or indirectly mutable storage still preserves value semantics, and the value-returning shape of a block transform is as cheap as the in-place
  one on the video corpus.

### compiler.optimization.024 — The split allocator claims a whole instruction for an implicit operand

- Recorded: 2026-08-29 15:41
- Updated: 2026-09-05 16:27 — git: Add unit tests for TaskProvider in providers.test.js
- Area: compiler/backend
- State: the interval-splitting linear scan of Wimmer & Mössenböck (VEE 2005, the allocator
  of HotSpot's client compiler) is what every optimizing build allocates with. `-O0` keeps
  the earlier scan, which also remains the fallback whenever a precondition fails or the
  walk bails, and the C++ conformity cases run both.
- Evidence: the walk describes every concrete claim by the position it occupies, except
  for the forms that name a register implicitly - the `rax`/`rdx` pair of a multiply-high,
  the `cl` of a variable shift, a compare-exchange. Those keep a claim on the whole
  instruction, so no operand of theirs can share it, and the second legalization sweep can
  then need the scratch register `tryBorrowReservedRegister` only lends when the first sweep
  left one free.
- Next: give those forms their real fixed intervals - the implicit register from its input
  slot, the operands free elsewhere - then check on a whole-library build whether the borrow
  still fires at all.
- Complete when: the three forms carry position-precise fixed intervals, the borrow path no
  longer fires on a whole-library build, and the suites stay green.
- Related: compiler.optimization.016.

### compiler.optimization.002 — Unrolling the key-stream loop still has to prove it pays

- Recorded: 2026-08-06 20:18
- Updated: 2026-09-03 11:39 — git: Convert early-return chains into conditional moves
- Area: compiler/backend
- Found while: chasing the second half of the ChaCha20 gap after the round loop stopped spilling
- Observation: the dominant cost is the key-stream application — sixteen words XOR-ed one at a
  time, a loop the unroller refuses because `K_MAX_TRIPS` is 8. Raising it to 16 unrolled the
  loop and bought nothing (2026-08-22, static census, release: chacha main 627 -> 763
  instructions, sha256 725 -> 878, every other task unchanged), because the per-element body
  carried three instructions a constant cannot remove. Those are gone (2026-09-03): the
  zero-extension after a 32-bit load and the `& M32` after a 64-bit add of two zero-extended
  words fold in `Pass.InstructionCombine.ZeroExtend.cpp` (a 32-bit write clears the upper half
  of its register, a contract `MicroInstr.h` now states), and the `load; op; store` round trip
  folds into `xor [r9], r11`. That fold always existed on paper; two defects kept it out of
  every loop. Every single-consumer fold counted the dead header phi of a loop-defined value
  as a second reader (`valueHasSingleUse` now looks through phis nothing reads), and
  legalization rewrote every memory-destination form back into registers because it read a
  virtual register as "not an integer". The folds now leave a frame slot or a global alone
  inside a loop, where slot promotion, the vectorizer and the instruction-pointer-relative
  access own it (the round loop of chacha lost its SLP packing otherwise, 229 -> 483).
- Evidence: release, static census of the bench mains, 2026-09-03: chacha 229 -> 223, sha256
  394 -> 369 (25 zero-extensions -> 2), csvagg 699 -> 695, wordfreq 322 -> 318, dijkstra
  276 -> 275, raytrace 115 -> 114, leven unchanged. The key-stream body alone is 24
  instructions against 28.
- Next: re-measure chacha with `K_MAX_TRIPS = 16` on a quiet machine, and only then ask whether
  the SLP pass sees the sixteen `[frame + K]` loads it now has.
- Complete when: a dynamic measurement on a quiet machine decides the unroll limit either way.

### compiler.optimization.008 — The hand-written sign-bit clamps of the H.264 decoder may be retired

- Recorded: 2026-08-19 14:16
- Updated: 2026-09-03 11:39 — git: Convert early-return chains into conditional moves
- Area: compiler
- Found while: std.video.001, profiling the H.264 decoder on a 1080p30 Main stream in release.
- Observation: `cond ? a : b`, `Swag.min`, `Swag.max`, `Swag.abs` and `Math.clamp` through them lower to a
  compare and a conditional move: the ternary diamond converts when both arms are short, pure
  and cannot fault (`Pass.BranchSimplify`, `convertDiamondsToConditionalMoves`), the intrinsics
  through the single-arm conversion beside it. The select written as a statement — the
  `if v < lo do return lo` / `if v > hi do return hi` chain — now converts too (2026-09-03,
  `convertEarlyReturnsToSelects`): each statement is a triangle whose body leaves the function,
  so the innermost pair folds into one return fed by a conditional move, and the fixed point
  folds the chain from the bottom, under the diamond's rules (pure, short, one value leaving
  each path, the compare re-issued when a path wrote the flags). What still compiles to a branch
  is an `if`/`else` whose arms do more than produce one value.
- Evidence: `#[Swag.PrintMicro("pre-emit")]` in release on the three-way early-return clamp:
  15 instructions with two `jump_cond` and three `ret` before, 12 with two `cmov` and one `ret`
  after; the nested ternary is 10. The decoder's conversion stage went from 1495 ms to about
  470 ms over 59 frames when its clamps were rewritten branch-free by hand (3.2x, byte-identical
  output; the sign-bit forms in `decode/h264/transform.swg`).
- Next: re-measure the decoder's deblock and conversion loops with the clamps written as
  statements against the hand-written sign-bit forms, and retire those if the select matches
  them.
- Complete when: the decoder's conversion stage measures the same with statement clamps as with
  the sign-bit forms, and the sign-bit forms are gone.

### compiler.optimization.027 — Binding a fallible call's result deep-copies instead of adopting the temporary

- Recorded: 2026-09-02 23:05
- Evidence (2026-09-02, PNG campaign): `let z = catch produce()` on a struct with lifecycle
  hooks runs `opPostCopy` once — the call's sret result lands in an `ErrorManagementExpr`
  runtime temporary, and the variable initializer copies it. For `Image.decode` that was one
  full pixel-buffer copy (about 1.1 ms per 6 MB) on every `try`/`catch`/`expect` call whose
  result initializes a variable. A non-fallible `let z = produce2()` binds the slot and copies
  nothing. Probe: a fallible `produce()->Payload fail` returning a 20-byte struct, called as
  `let z = catch produce()`, counts exactly one `opPostCopy`; the same chain without `fail`
  counts zero.
- The codegen side already anticipates the fix: `initPayloadAliasesSymbolStorage`
  (CodeGen.Identifier.cpp) accepts an init whose payload storage IS the declared variable when
  the init node is an `ErrorManagementExpr`. What is missing is the sema side binding the
  declared variable as the runtime storage of a fallible-call initializer, the way
  `AstSingleVarDecl::semaPostNodeChild` (Sema.Var.cpp) already does for arrays, closures, and
  `retval` — including the inferred-type shape, which never enters that type-child hook.
- Fallback shape if the binding is unreachable for inferred types: at
  `emitVarInitPostCopy`, an init from an `ErrorManagementExpr`-owned unique temporary could run
  `opPostMove` and reset the temporary instead of copying, but that requires knowing how the
  temporary's scope drop is registered so the adoption does not double-drop.
- Next: bind the declared variable as the fallible initializer's runtime storage in sema for
  both the typed and the inferred shape, then assert zero `opPostCopy` in a native-suite case
  shaped like `lifecycle_return_move.swg`.
- Complete when: `let x = try/catch/expect call()` initializes a lifecycle struct with no
  `opPostCopy` and no extra drop, with a native-suite regression guarding it.
