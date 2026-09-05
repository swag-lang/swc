# Optimization Backlog

Backend optimization passes, register allocation, and the performance of the code `swc` generates.
Frontend and lowering defects are [compiler.core.md](compiler.core.md).

Entries are grouped by the optimization capability they advance. [README.md](README.md) defines
the shared backlog conventions.

## Loop vectorization

### compiler.optimization.002 — Unrolling the key-stream loop still has to prove it pays

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

## Register allocation and frame-slot promotion

### compiler.optimization.028 — Scalar float literals still reload in the raytrace pixel loop

- Area: compiler/backend
- Found while: comparing the unchanged `bench/src/swagnat/raytrace.swg` with both C++ ports on
  `9574fdd43`, with the scalar-copy and conversion-web improvements applied (2026-09-05).
- Evidence: the release pixel loop falls from 76 instructions / 21 memory operations to 65 / 18
  when the vertical conversion and arithmetic move to the scanline. Clang-cl emits 46 / 6 and
  MSVC 53 / 6, including its cold sqrt path. The remaining Swag memory operations comprise twelve
  literal loads, three global loads and three argument stores. In particular, the three positive
  zero arguments reload a constant while both C++ compilers clear their XMM registers.
- Observation: before LICM these constants are floating `LoadRegImm` instructions. They become
  RIP-relative loads during legalization, after LICM's profitability filter has treated their
  single-use materializations as cheap. The conversion-web improvement adds two saved XMM
  registers outside both loops; further hoisting must account for that register pressure.
- Next: lower exact positive-zero scalar literals to XMM clears, preserving negative zero and
  relocations; then evaluate hoisting nonzero scalar literals using their eventual load cost.
  Compare each loop in all seven tasks before keeping either change. Do not reopen relocated
  address materialization hoisting, whose sha256 spill regression is documented in LICM.
- Complete when: zero arguments no longer read memory and the remaining literal loads have a
  measured register-pressure decision, with native and script correctness coverage.

### compiler.optimization.004 — Tracking frame addresses transitively through mem2reg does not pay on its own

- Area: compiler/backend
- Found while: closing the generated-code gap `bench/` measures (campaign 20260806-202546,
  geometric mean 1.41-1.54x the better of clang-cl and MSVC over two baseline campaigns)
- Observation: mem2reg roots its address tracking at the frame base only, so `mov %x, %ar` and
  `lea %x, [%ar + off]` — a copy of a known frame address, and a second-level offset from one —
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

### compiler.optimization.005 — Complex loop-carried frame slots still lose registers

- Area: compiler/backend
- Found while: the same campaign, asking why the identical loop compiles differently in two places
- Observation: loop-invariant reloads and a single read/write carried slot are promoted, but the
  pass refuses a group of mutually dependent carried slots and a carried slot whose register is
  reused between its load and store. Those are the shapes left in the hottest benchmark loops.
- Evidence: sha256's `a`..`h` are eight
  slots at once and each one's register IS reused between its load and store, so the
  carries-nothing-else test fails on all eight. Leven's DP loop writes `row1[y+1]` through a
  program pointer, which makes the body opaque to the aliasing model: any non-frame write may alias
  any frame slot.
- Next step: promote sha256's eight carried slots as one group, or rank their live ranges over the
  loop hull rather than the whole function. For Leven, record the allocator spill boundary so a
  program pointer can be proved unable to alias those slots.

## Decompression

### compiler.optimization.006 — A hot loop's loop-carried locals all live in stack slots

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
- Four things ruled out by measurement, so they are not retried:
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
    removing twelve independent instructions changes nothing. Reverted. Worth revisiting only
    *after* the register half lands, when the loop may become instruction-bound.
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

### compiler.optimization.008 — The hand-written sign-bit clamps of the H.264 decoder may be retired

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

### compiler.optimization.010 — A short branching function spills with the whole register file free

- Area: compiler/backend
- Found while: std.video.001, closing the distance between the H.264 entropy parse and FFmpeg's, starting
  from the emitted code of one bin as that entry says to.
- Observation: `CabacReader.decision` decodes one arithmetic bin. It is small, straight-line apart
  from one two-way branch, and its whole live set is about eight scalars. It is called roughly
  568,000 times per 3840x2160 picture, which is where the parse spends most of its time.
  `#[Swag.PrintMicro("post-emit")]` in release showed the function opening with seven callee-saved
  pushes and `sub rsp, 0xA0`, then storing three values — the address of the context byte, `mps`,
  and the result — to that frame before the branch and reloading them on both sides. Sixteen
  integer registers exist and the function needs about half of them.
- This is [compiler.optimization.006](#compileroptimization006--a-hot-loops-loop-carried-locals-all-live-in-stack-slots) and
  the earlier whole-hull allocator without
  the loop: no value here is loop-carried, no hull is being reserved, and the eviction still
  happens. That makes it a much smaller reproducer than the inflate block loop for the same
  allocator policy, which is why it is worth keeping separately.
- Evidence: the same dump also measured what source shape can and cannot reach. Holding `range`
  and `low` in locals for the length of the bin, and sharing renormalization between the two
  outcomes, took the function from 217 to 143 instructions — a third fewer — and about one percent off the
  serial decode of one picture, which is inside the noise floor of this machine — the arithmetic registers were being reloaded after every step because
  the context write in between stores into the same structure. What did not move is the frame:
  it is still 160 bytes with three spill slots live across a branch, and the seven pushes are
  still there. Two smaller costs sit in the same function and belong to the same dump:
  each of the three variable shifts carries a width guard of `cmp` plus `cmovae`, which is cheap
  next to the spills and was already elided once for
  [compiler.optimization.006](#compileroptimization006--a-hot-loops-loop-carried-locals-all-live-in-stack-slots) and measured at zero.
- Two of the three costs are gone (2026-08-24). `Swag.bitCountLz` no longer branches: the scan runs
  unconditionally and a conditional move supplies the operand-width answer for zero, so the
  sequence is one basic block instead of two and the caller keeps one fewer allocation boundary.
  And the function no longer carries a frame register: it names none, its stack shape is one
  subtract at entry and one add before the return, so the unwind codes describe it in full
  without one. The prologue is six pushes and `sub rsp, 0x98`, and the emitted function is 138
  instructions against 143.
- Current boundary: the default optimizing allocator now splits live ranges. The instruction and
  frame counts above describe the earlier scan, so they need a new dump before directing a fix.
- Next: dump `CabacReader.decision` in Release and attribute any remaining branch-crossing spills
  to the selected allocator. Keep it as the small companion to the Inflate workload. The target is
  now x86-64-v3; adopting `lzcnt`/`tzcnt` no longer needs the AVX-to-AVX2 target-policy change
  previously stated here, but still needs encoder and zero-operand tests.
- Complete when: the current dump decides whether the branch-spill gap remains and any remaining
  allocation defect has a reduced test.
- Related: compiler.optimization.006, compiler.optimization.024.

### compiler.optimization.011 — A SIMD routine keeps its strides and counts in the frame

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
- **The same shape is what the H.265 decoder is now bound by, and it is worth more than any
  one of its stages (2026-08-26, std.video.005).** Three hot routines dumped at pre-emit, all of them
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
- So this backend is **2.2x behind clang's best on identical scalar code**, and that is the
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

### compiler.optimization.012 — A lane broadcast now leaves the loop with the replication that feeds it

- Area: compiler/backend
- Found while: std.video.001, reading the chroma interpolation loop of the H.264 decoder after the
  vector temporaries stopped round-tripping through the frame.
- Observation: the loop rebuilt the same four lane broadcasts on every row, each a `movd` from an
  integer register followed by `pshufd`, while the replication feeding them (`zero_extend` then
  `imul 0x10001`) already sat in the preheader. The opcode filter was only half of the refusal:
  `VecShuffleRegRegImm`, `VecUnaryRegReg`, `OpBinaryRegRegImm`, `OpBinaryRegRegReg` and
  `LoadVecRegMem` were ineligible, but making them eligible changed nothing because the profit
  filter behind it keeps a hoist only when the instruction reads memory or feeds more than one
  consumer, and each broadcast feeds exactly one multiply. Since 2026-09-03 the filter also keeps
  a vector materialization (`isVectorMaterialization`, `Pass.LoopInvariantCodeMotion`): the
  `movd` of an integer into a float register, a shuffle, or a three-operand vector op whose
  inputs are invariant. A vector built from a scalar is cheap to keep live, and rebuilding it is
  an integer-to-float move on every trip.
- Evidence: `#[Swag.PrintMicro("post-licm")]` in release on an eight-lane `u16` row scaling:
  the `zero_extend`, `imul 0x10001`, `movd` and `pshufd` all sit between the loop guard and the
  header label, and the body multiplies straight from the hoisted register
  (`LICM_HoistsSingleUseLaneBroadcast`).
- Next: read `Video.H264.mcChroma` again in release and confirm its four broadcasts left the row
  loop.
- Complete when: the chroma interpolation loop shows no `movd` or `pshufd` in its body.

## The pipeline measured against LLVM's

A comparative study of this backend against the LLVM 18-20 pass pipeline (2026-08-26) located
the 1.7-2.2x scalar-loop gap against clang-cl `/O2` in three compounding contracts rather than
any single pass: LLVM keeps registers as the truth inside loops and places memory traffic by a
frequency-weighted model, its loop passes and allocator cooperate where ours fight, and its
inliner merges helper layers before any loop analysis runs. The entries below are that study's
recommendations in value order, each a policy change or an extension of an existing pass. Judged
not worth porting, so later entries do not relitigate them: a full greedy allocator with region
splitting, MemorySSA/GVN-PRE/jump threading/loop unswitching (all need phi nodes the Micro IR
cannot express), SCEV with LoopStrengthReduce, a post-RA scheduler and software pipelining,
cmov-to-branch back-conversion, and profile-gated passes.

### compiler.optimization.015 — Loop-carried slot promotion covers multi-access, multi-exit loops

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

### compiler.optimization.016 — Virtual-register webs get unique names

- Intent: a normalization pass gives every def-use web of a virtual register its own fresh
  register - the SSA property LLVM's passes get from their IR, reconstructed by renaming, with no
  phi nodes needed because a web that spans a join keeps its one name. The lowering reuses
  virtual registers across unrelated computations, so today a loop-invariant chain shares its
  register with code elsewhere in the function (measured on the deblock probe: the `pass % 3`
  chain's register carries five definitions, one outside the loop), and any pass that reasons
  per-register - the web hoisting now in LICM first among them - must refuse the whole register.
- Next: re-run the parked prototype. The interval allocator (compiler.optimization.024) is now the default, so
  its splitting supplies the re-coalescing the renaming needs.
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
  the old hull interference as a current blocker. Prototype parked in the session
  scratchpad (`webrename-parked/`: `Pass.WebRename.{h,cpp}` plus the registration diff).
- Related: compiler.optimization.015, compiler.optimization.017; unlocks the full yield of the web hoisting shipped in LICM.

### compiler.optimization.017 — Jump-entered loops get a dedicated preheader

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

### compiler.optimization.018 — Spill-area stores no path reloads are deleted

- Intent: a post-RA pass runs a backward byte-liveness fixed point over
  `[spillAreaLo, spillAreaHi)` on the instruction CFG and deletes every spill store no path
  reloads before overwrite - the write-back protocol audited from the consumption side, since the
  allocator manufactures stores wholesale and nothing checks whether any path reads them.
- Next: retry the parked prototype as-is on the full video release run, now that the
  lane-count assertion it tripped on is fixed.
- Complete when: the pass lands with the three known landmines closed - exact read widths (a
  16-byte over-approximation pins the neighbouring 8-byte slot), push/pop and stack-pointer
  arithmetic not treated as area barriers (or the epilogue keeps everything alive), and any
  function with a stack-pointer adjustment between its first and last spill access skipped
  (call-argument setup shifts the offset coordinate system) - and the full video release run stays
  green. A parked prototype with all three fixes exists (session scratchpad,
  `dse-parked`).
- Related: compiler.optimization.010. The machine-dependent lane-count assertion that failed the prototype's validation run (h264.test.swg, fixed 2026-08-27) is gone, so the parked prototype can be retried as-is.

### compiler.optimization.020 — One alias oracle serves every pre-RA memory optimization

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
- Next: in `SemaInline`, detect that a by-value aggregate parameter is never assigned in the
  cloned body and bind it to the argument expression instead of a materialized copy.
- Complete when: a read-only by-value aggregate parameter costs no copy after inlining, a written
  one still copies, and the value-returning shape of a block transform is as cheap as the in-place
  one on the video corpus.
### compiler.optimization.024 — The split allocator claims a whole instruction for an implicit operand

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
- Related: compiler.optimization.010, compiler.optimization.016.

### compiler.optimization.026 — Folding a constant address into a RIP-relative load miscompiles library images

- Area: compiler/backend
- Found while: a repository health reset, chasing the `render.parity.stroke.cpu-ogl` golden that
  compares the CPU and OpenGL painter backends. The OpenGL image came back entirely zero (all
  24 576 pixels differ, `(0,0)` produced 0 against the expected clear colour), and the CPU image
  was correct.
- Observation: `tryFoldRelocatedAddressIntoAccess` (added by "Fold constant addresses into direct
  loads") rewrites `LoadRegPtrReloc %base, <const K>` + `LoadRegMem %d, [%base + off]` into a
  single `LoadRegMem %d, [rip]` whose relocation carries `K + off`. Disabling only the constant
  case of that fold turns the golden green; re-enabling it turns it red again. The fold is the
  cause, and it is confirmed with nothing else changed.
- What was ruled out by inspection and by measurement, so the next attempt does not re-walk them:
  the fold is value-equivalent (the folded `[rip]` load reads the exact bytes the base-plus-offset
  load read — verified on `__utoa`'s `conv.buffer` load via `PrintMicro`); the merged-rdata REL32
  addend and the internal linker's REL32 resolution (`PEWriter.cpp`) are correct; reachability of
  the referenced constant and its transitive relocations is unchanged. The full `native` suite
  (2 983 cases, an executable artifact) passes with the fold on, including non-zero-offset folds.
  The break appears only when the folded function lands in a shared- or static-library image: the
  folds that actually fire in the failing build are all in library modules (`__utoa`, `__itoa`,
  `Argb.fromName`, `Pixel.Svg.parseColor`), none on the render path, so a library-image emission or
  register-allocation cascade the fold triggers — not a wrong value in the folded function —
  corrupts the module. `partitionArchiveObjects` is dead code, so the split-rdata archive path is
  not the difference; executable and library targets share `partitionObjects`.
- Mitigation in place: the constant case is gated to artifacts that do not emit a library image
  (`backendKind` neither `SharedLibrary` nor `StaticLibrary`) in
  `Pass.InstructionCombine.ConstProp.cpp`. Globals still fold everywhere, and executables and JIT
  still fold constants. The `InstCombine_ConstantAddressLoad_FoldsToRip` C++ unit test still
  exercises the fold.
- Next: reproduce the miscompile in a `workspace` suite case that builds a library module holding a
  pointer-carrying constant and reads it from a consumer, then bisect the library-image path
  (base-relocation emission, export handling, and the register allocation that changes when the
  address materialization is dropped) to the actual defect.
- Complete when: the constant fold is sound for shared- and static-library images, the gate in
  `Pass.InstructionCombine.ConstProp.cpp` is removed, a suite test guards the reduced repro, and
  the `render.parity.stroke.cpu-ogl` golden stays green.
