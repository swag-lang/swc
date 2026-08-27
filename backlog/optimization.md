# Optimization Backlog

Backend optimization passes, register allocation, and the performance of the code `swc` generates.
Frontend and lowering defects are [compiler.md](compiler.md).

Entries are grouped by the optimization capability they advance. [README.md](README.md) defines
the shared backlog conventions.

## Loop vectorization

### F-034 — Unrolling the key-stream loop no longer loses its constant offsets, and still does not pay

- Area: compiler/backend
- Found while: chasing the second half of the ChaCha20 gap after the round loop stopped spilling
- Observation: the dominant cost is the key-stream application — sixteen words XOR-ed one at a
  time, a loop the unroller refuses because `K_MAX_TRIPS` is 8. The first attempt at raising it
  to 16 unrolled the loop and bought nothing, because the indexed accesses survived as `Amc`
  forms; that part is fixed — `tryFoldConstIndexAmc` (2026-08-04) turns each copy's `state[i]`
  and `initial[i]` into `[frame + K]`, and the lea-into-index fold gives `data[offset + i]` its
  constant displacement. What survives in the unrolled body is what a constant cannot remove.
- Evidence: measured again 2026-08-22 with `K_MAX_TRIPS = 16` (static census, release): chacha
  main 627 -> 763 instructions, sha256 725 -> 878 (its sixteen-trip schedule loops unroll too),
  every other task unchanged. Per element the unrolled body reads `[rbx + 0xAC]` and
  `[rbx + 0x58]` directly, but still spends three instructions on the data word — `lea r9,
  [rdi + rsi*4 + K]`, `load [r9]`, `store [r9]` — where clang writes one `xor dword ptr
  [rdi + rsi*4 + K], reg`, and three zero-extensions on the two u32 adds — `load b32; zext
  b64<-b32` although a 32-bit load already zero-extends, and `add b64; zext b64<-b32` for the
  `& M32`, which a 32-bit add would do in one. Reverted: no dynamic measurement yet shows the
  sixteen copies winning over the loop, and the change reaches every counted loop of up to
  sixteen trips.
- Next step: two peepholes come first, because they pay whether or not the loop unrolls — drop
  the zero-extension that follows a 32-bit load or a 32-bit-masked 64-bit add of two
  zero-extended words, and fold a `lea; load; op; store` round trip on the same address into a
  memory-destination op. Then re-measure chacha with the limit at 16 on a quiet machine, and
  only then ask whether the SLP pass sees the sixteen `[frame + K]` loads it now has.

## Register allocation and frame-slot promotion

### F-036 — Folding copy-then-operate before register allocation miscompiles

- Area: compiler/backend
- Found while: generalizing non-destructive pre-RA operations to the float paths, where
  `raytrace`'s intersect loop carried 16 copies and
  11 stores in a loop that only computes, and the post-RA fold converted 6 pairs out of ~22
- Observation: rewriting an adjacent `mov %d, %a` / `%d op= %b` into `%d = %a op %b` in the
  PRE-RA peephole does what it promises statically - the loop's copies drop 16 to 6, its stores
  11 to 5, and three-operand forms go 6 to 22 - and then every script crashes with 0xC0000005
  under the JIT, after compiling cleanly. The same rewrite is sound post-RA, where it has shipped
  for a while.
- Evidence: `swc tools/scripts.swgs dm` fails on every script, right after "tuned"; the failure is an
  access violation in JIT-executed code, not a compiler error. Minimal float arithmetic through
  the JIT is fine, so the broken shape needs the surrounding std modules. Unit tests, the native
  optimizer tests and the earlier phases of `tests.swgs dm` all pass, which is what let it get as
  far as the scripts.
- Ruled out by inspection, so the next attempt does not re-walk them: value numbering keys
  instructions through an explicit per-opcode shape table and simply declines the ones it does not
  list, so a three-operand form is never numbered, let alone numbered wrongly; copy elimination and
  dead-code elimination make no positional operand assumptions; the encoder's conformance rules for
  `OpBinaryRegReg` only fire on integer shapes (shift counts in rcx, mul/div in rax/rdx), which
  float operations never reach. Above all, the vectorizer already emits `OpBinaryRegRegReg` pre-RA
  and that path is sound - but at B128. The defect is therefore specific to the B32/B64 float form,
  not to the opcode existing before allocation.
- Next step: two suspects remain. LICM treats an adjacent copy plus two-address compute as a pair it
  hoists together (`isEligiblePairedComputeOpcode`), and the fused form is not in its eligible list;
  that should only cost a missed hoist, but the interaction is worth confirming rather than
  assuming. Otherwise it is the register allocator meeting a float destination that is write-only,
  where every float three-operand instruction it has seen so far arrived after allocation. Bisect
  cheaply first: restrict the fold to `FloatAdd` alone and run `swc tools/scripts.swgs dm` - a crash
  there means the shape, a pass means the operation.

### F-066 — Tracking frame addresses transitively through mem2reg does not pay on its own

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
- Related: [F-068](#f-068--complex-loop-carried-frame-slots-still-lose-registers)

### F-068 — Complex loop-carried frame slots still lose registers

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

### F-136 — A hot loop's loop-carried locals all live in stack slots

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
  deflate payload of `8_9_2025_15_43_58.scapture` (17.0 MB out, 14.76 M symbols, 1.21 bytes per
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
- The register half was then traced to its mechanism and moved to
  [F-138](#f-138--a-whole-hull-reservation-cannot-keep-a-loops-working-set-in-registers), which
  carries the numbers.
- Next step: this is [F-068](#f-068--complex-loop-carried-frame-slots-still-lose-registers) seen
  from a second workload, and the case is small enough to drive the fix — a loop whose whole
  live set fits in registers twice over and is spilled anyway. The bottleneck is the allocator's
  policy, local linear scan with furthest-use eviction, and the work that addresses it is the
  global interval allocator, not another peephole.

### F-138 — A whole-hull reservation cannot keep a loop's working set in registers

- Area: compiler/backend
- Found while: chasing the register half of
  [F-136](#f-136--a-hot-loops-loop-carried-locals-all-live-in-stack-slots) into
  `assignGlobalRegisters`, with a temporary trace over its candidate list.
- Observation: a value that crosses a control-flow boundary is either given one physical
  register for **the whole hull of its live range**, or it is given a stable spill slot and
  lives in memory for the rest of the function (`preallocateLoopCarriedSlots`). There is
  nothing in between. Three things follow, and they compound:
  - **The ranking inverts on exactly the values the mechanism exists for.** Candidates are
    ordered by density — benefit divided by span length — which is right between comparable
    values, because a hull is held across its holes too. A loop cursor lives from the top of
    the function to the bottom, so its density is microscopic while its reload count is the
    largest in the function. It queues behind every short-lived candidate and finds the
    registers gone.
  - **The benefit model cannot tell a cursor from a base pointer.** `computeGlobalBenefits`
    counts boundary crossings weighted by loop depth, so a value read six times an iteration
    and one read once score the same if they cross the same boundaries. Fixing the ranking
    alone therefore hands the registers to the function's parameters.
  - **The supply is four.** In a function with calls, a hull crossing one may only ride a
    callee-saved register, and the floor keeps two back
    (`totalPersistent - K_MIN_FREE_PERSISTENT_INT` = 6 - 2). Whole-function hulls all overlap,
    so each needs its own register: four, for a loop whose working set is ten.
- Evidence: measured 2026-08-15 on `Inflate.parseBlock` (1469 instructions, 124 candidates,
  6 callee-saved and 7 caller-saved int registers free, all 6 callee-saved proven-free). The
  four loop cursors carry a raw benefit of 163,201,810 each and are rejected; twenty-five
  candidates carrying 2,000,000 — eighty times less — are granted. Raising the ranking with a
  raw-benefit tier fixes the order and changes nothing: the four registers go to the
  parameters, whose raw benefit ties at 164,701,810 because the model counts crossings, not
  uses. Forcing the cursors in by hand pinned two of the four, worth about 4% on a machine
  too noisy to resolve it.
- Ruled out on the way, and worth not repeating: a raw-benefit tier gated only relatively
  (`maxRawBenefit / 4`) degenerates on functions with no hot loop — `__setupRuntime`, whose
  busiest candidate is worth 4, puts every candidate in the first tier, loses the density
  ranking entirely and **miscompiles** (access violation writing through a null context). Any
  such tier needs an absolute floor as well, high enough to mean a deep loop.
- Next step: interval splitting, which is the thing whole-hull reservation cannot express.
  clang keeps ten values in registers here not by picking better hulls but by holding a value
  in a register where it is hot and letting it live in memory where it is not. Reordering or
  reweighting redistributes four registers; it cannot produce ten. This is the same conclusion
  the float side reached from `raytrace` — the bottleneck is the policy, local linear scan with
  furthest-use eviction — and the two workloads now bracket it: a float kernel with no calls,
  and an integer loop with calls in its body. Start from the existing candidate machinery,
  which already computes the spans, the benefits and the concrete-claim positions a splitting
  allocator needs.

### F-165 — Integer selects written as early returns still lower to branches

- Area: compiler
- Found while: T-504, profiling the H.264 decoder on a 1080p30 Main stream in release.
- Observation: `cond ? a : b`, `@min`, `@max`, `@abs` and `Math.clamp` through them lower to a
  compare and a conditional move: the ternary diamond converts when both arms are short, pure
  and cannot fault (`Pass.BranchSimplify`, `convertDiamondsToConditionalMoves`), the intrinsics
  through the single-arm conversion beside it. What still compiles to compare-and-branch is the
  select written as a statement — the `if v < lo do return lo` / `if v > hi do return hi` chain,
  and an `if`/`else` whose arms do more than produce one value — and every such branch is an
  allocation boundary, so the loop's live set flushes around it.
- Evidence: `#[Swag.PrintMicro("pre-emit")]` in release on a three-way early-return clamp: two
  `jump_cond`, three `ret`, 26 instructions; the same clamp as a nested ternary: 11 instructions
  and two `cmov`. The decoder's conversion stage went from 1495 ms to about 470 ms over 59 frames
  when its clamps were rewritten branch-free by hand (3.2x, byte-identical output; the sign-bit
  forms in `decode/h264/transform.swg`), which is the gain the statement form still leaves where
  it is used.
- Next step: if-convert the early-return chain — a triangle whose body is a `ret` of a pure value
  — into a select feeding one `ret`, then re-measure the decoder's deblock and conversion loops
  against the hand-written sign-bit forms and retire those if the select matches them.

### F-187 — An atomic read is a locked read-modify-write

- Area: optimization
- Found while: T-504, giving the H.264 decoder per-row reference progress so pictures overlap.
- Observation: `Core.Atomic.get` is written as `@atomcmpxchg(addr, 0, 0)`, so every atomic read
  compiles to a `LOCK CMPXCHG`. That takes the cache line exclusively, writes it, and orders the
  whole pipeline, for what is only a read. On x86-64 an aligned load of that width is already
  atomic and already carries acquire ordering, so the locked form buys nothing and costs the line
  to every other reader.
- Evidence: reconstruction consulted a per-picture progress counter before each predicted block.
  With sixteen frame threads reading the same counter it turned a read-mostly value into a
  contended write, and the reconstruction of one 3840x2160 picture measured about 42 ms instead of
  the 22 ms the same work takes without it. The decoder now caches the last value it observed per
  reference picture, so the locked read happens about once per macroblock row rather than several
  times per macroblock, and the time came back. Every other spin in the repository still pays it:
  `Jobs.isDone`, `Jobs.wait`, the deblocking wavefront, `Frame.heldByCaller`, and the frame-pool
  scan in `startPicture` all poll through `Atomic.get`.
- Next step: add a relaxed atomic load to the language — an `@atomget` intrinsic lowering to a
  plain `MOV` on x86-64, with the same acquire guarantee the current form provides — and make
  `Atomic.get` use it. Measure `tools/unittests.swgs dm cpp` for the intrinsic itself, then the
  `Jobs` scheduler and the deblocking wavefront before and after; both spin on it today.

### F-190 — A short branching function spills with the whole register file free

- Area: compiler/backend
- Found while: T-504, closing the distance between the H.264 entropy parse and FFmpeg's, starting
  from the emitted code of one bin as that entry says to.
- Observation: `CabacReader.decision` decodes one arithmetic bin. It is small, straight-line apart
  from one two-way branch, and its whole live set is about eight scalars. It is called roughly
  568,000 times per 3840x2160 picture, which is where the parse spends most of its time.
  `#[Swag.PrintMicro("post-emit")]` in release showed the function opening with seven callee-saved
  pushes and `sub rsp, 0xA0`, then storing three values — the address of the context byte, `mps`,
  and the result — to that frame before the branch and reloading them on both sides. Sixteen
  integer registers exist and the function needs about half of them.
- This is [F-136](#f-136--a-hot-loops-loop-carried-locals-all-live-in-stack-slots) and
  [F-138](#f-138--a-whole-hull-reservation-cannot-keep-a-loops-working-set-in-registers) without
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
  [F-136](#f-136--a-hot-loops-loop-carried-locals-all-live-in-stack-slots) and measured at zero.
- Two of the three costs are gone (2026-08-24). `@bitcountlz` no longer branches: the scan runs
  unconditionally and a conditional move supplies the operand-width answer for zero, so the
  sequence is one basic block instead of two and the caller keeps one fewer allocation boundary.
  And the function no longer carries a frame register: it names none, its stack shape is one
  subtract at entry and one add before the return, so the unwind codes describe it in full
  without one. The prologue is six pushes and `sub rsp, 0x98`, and the emitted function is 138
  instructions against 143.
- Next step: what remains is the spills themselves — three values still cross the one branch
  through the frame while a dozen registers are free. That half is the global interval
  allocator's case, not a peephole's. Use it as the small reproducer while that work proceeds:
  `#[Swag.PrintMicro("post-emit")]` on `CabacReader.decision`, release. Separately, `lzcnt`/`tzcnt`
  would retire the remaining bit-scan sequence, but they are ABM/BMI1 and the backend's stated
  baseline is AVX, so adopting them raises the Intel floor from Sandy Bridge to Haswell — a
  decision about what the compiler targets, not an optimization to slip in.

### F-193 — A SIMD routine keeps its strides and counts in the frame

- Area: compiler/backend
- Found while: T-504, after mem2reg was taught the vector load and store and the memory traffic
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
  one of its stages (2026-08-26, T-563).** Three hot routines dumped at pre-emit, all of them
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
  forms of T-506, and larger than anything left in the decoder's own algorithms. The frame
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
  [F-136](#f-136--a-hot-loops-loop-carried-locals-all-live-in-stack-slots) again.
- Next step: use `Hevc.Decoder.filterLumaEdge` and `Hevc.Decoder.interpolateLuma` as the large
  acceptance workloads for F-136's interval allocator work. Re-run the recorded frame-access and
  per-segment measurements after that allocator can split live ranges; do not extend the post-RA
  hoist unless one of these dumps first shows an invariant value with a reusable destination.

### F-194 — Loop-invariant code motion stops at a lane broadcast

- Area: compiler/backend
- Found while: T-504, reading the chroma interpolation loop of the H.264 decoder after the
  vector temporaries stopped round-tripping through the frame.
- Observation: the loop rebuilds the same four lane broadcasts on every row. Each is `movd`
  from an integer register followed by `pshufd`, and both operands are loop-invariant: the
  replication that feeds them (`zero_extend` then `imul 0x10001`) is already in the preheader,
  so the pass is running and hoisting from this very loop. It just stops one instruction short.
- Evidence: `#[Swag.PrintMicro("pre-legalize")]` on `Video.H264.mcChroma`, release. The four
  `imul 0x10001` sit between the loop guard and the header label; the four `LoadRegReg` /
  `VecShuffleRegRegImm` pairs that consume them sit inside the body. Adding
  `OpBinaryRegRegReg`, `OpBinaryRegRegImm`, `VecShuffleRegRegImm`, `VecUnaryRegReg` and
  `LoadVecRegMem` to `isEligibleOpcode` — none of them touches memory, the flags or the stack,
  and all write a destination they do not read — changed nothing: `pixel.dll` came out byte for
  byte identical, and the loop kept its broadcasts. So the opcode filter is not what refuses
  them, and that change was reverted rather than shipped dead.
- Next step: instrument the candidate loop of `hoistRound` for one function — print, per body
  instruction, which of `isEligibleOpcode`, `defCount`, `allInvariant` and the memory guards
  turned it away. The `movd` is `LoadRegReg` with a float destination and an integer source,
  which is already eligible today, so the answer is in one of the other four tests and the
  trace names it in one run.
### F-195 — A loop header drops every mapping, and the register to fix it is already spoken for

- Area: compiler/backend
- Found while: taking
  [F-138](#f-138--a-whole-hull-reservation-cannot-keep-a-loops-working-set-in-registers) and
  [F-190](#f-190--a-short-branching-function-spills-with-the-whole-register-file-free) at their
  word and instrumenting the allocator instead of reading its output.
- Observation: **the allocator reloads values at points where it has registers to spare, so what
  costs is the decision that put them in memory, not the supply at the use.** Over a release build
  of `core` — twelve thousand emitted reloads, each recorded with the pool state at that
  instruction and with why the value had lost its register — four reloads in five happen with at
  least one usable register, and one in three with eight or more. Eviction under genuine pressure
  accounts for 7%. Everything above it is a rule that gave a register away while registers were
  plentiful, and one rule dominates: **a label with a back-edge predecessor drops every mapping,
  because the linear scan has not seen the back-edge state yet.**
- Evidence: `swc tools/std.swgs dm build core -bc release --rebuild`, one line per emitted reload.
  12211 reloads. Why the value had lost its register:

  | cause | reloads | share |
  | --- | --- | --- |
  | boundary drop: next use more than 48 instructions away | 3795 | 31% |
  | join: a back-edge, or an edge with no recorded state | 2147 | 18% |
  | join: the incoming edges disagreed on the register | 1874 | 15% |
  | never mapped: first use of a value with a memory home | 1691 | 14% |
  | its register was taken by a copy destination | 1181 | 10% |
  | evicted to make room | 820 | 7% |
  | boundary: not live out | 353 | 3% |
  | cleared after a terminator that does not fall through | 350 | 3% |

  The first row is not a cause, and that is the useful part. Removing
  `K_KEEP_MAX_NEXT_USE_DISTANCE` entirely — keeping every mapping across a boundary however far
  its next use — moves the total by **59 reloads out of 12211**. Its 3795 do not disappear; they
  redistribute, 1787 of them onto the back-edge row, which grows to 3934 and becomes a third of
  all reloads on its own. So the constant is only the first mechanism that happens to catch these
  values, and tuning it is pointless in either direction. The same measurement retires the other
  cheap idea beside it: letting the edge-register hint outrank a copy's transfer source, which the
  code declines to do, is worth 12 reloads out of 1874 on the row it targets.
- **The shape of what the back-edge drops, and why the obvious repair does not land.** Of the 2113
  mappings dropped at a loop header, **1696 — four in five — are values the loop never writes**.
  Such a value asks for almost nothing: give it a register for `[header, back-edge tail]` and the
  two edges agree by construction, its memory home stays coherent so leaving the loop owes no
  store, and no edge anywhere needs a reconciliation copy. All it costs is one load, placed before
  the header label so the back-edge jumps over it. Every loop header measured is entered by
  falling into it, so even the load has nowhere awkward to go.

  That was built and measured, as a reservation pass running after `assignGlobalRegisters`. All
  suites pass and it is worth **17 reloads out of 12211**, because it almost never fires: 30
  grants against 491 refusals for a class budget already spent by the whole-span reservations, and
  899 refusals for no register free of concrete claims over the loop's extent. Most loop bodies
  contain a call, which claims every caller-saved register across the range, so only callee-saved
  registers qualify — and those are exactly what the whole-span reservations took first. Two
  mechanisms cannot be appended one after the other when they compete for the same six registers.
- A first pass at this entry read all of this from the wrong counter, and the mistake is worth
  stating so it is not repeated: counting the times `allocatePhysical` exhausts its free pools says
  almost nothing. Those counts came out as 100% hull-owned, which looked decisive. They are not,
  because an exhausted pool is followed by an eviction that is usually free — `isCandidateBetter`
  ranks dead values first and `allocatePhysical` takes them without emitting a spill. Measure
  emitted spills and reloads, never failed lookups.
- Ruled out, with numbers, so none of it is tried again. Admitting values that cross no
  control-flow boundary as hull candidates on the access ranking: the raytrace kernel gained 7
  instructions and 3 frame accesses, the Levenshtein loop lost 7 and 6, a byte scan lost 3 and 4.
  A callee-saved fallback for ordinary floats gated on loop depth (the variant F-136 left open):
  seventeen failed lookups became eleven for two more instructions. Reserving only the live
  sub-ranges of a hull instead of its whole span: the blocking hulls were live at every contended
  point in all four kernels, so there is nothing to hand back. And removing every hull from the
  CABAC bin of F-190 changes its emitted code by not one instruction, so the mechanism is inert
  there.
- The candidate-list route was built next and measured to lose, so it is retired: one loop-scoped
  reservation candidate per (value, loop), competing on the whole-span ranking, displaces short
  whole-span hulls that were already loop-scoped in effect and are strictly better (no fill, no
  write-through, no out-of-range reload) — `Decoder.interpolateChroma` gained 15 stores that way.
  Granting loop candidates only on leftover capacity was neutral: the same budgets that starve the
  standalone pass starve the leftovers.
- **What shipped instead (2026-08-26): loop residency in `rewriteInstructions`.** At the header of
  a sealed loop — entered only by falling in, no outside jump landing past it
  (`collectLoopRegions`) — the boundary flush keeps the arriving mappings instead of dropping
  them, preloads home-resident values the loop reads into whatever registers are free, and every
  back-edge restores exactly that committed state before jumping (`conformLoopResidency`), so the
  two sides of each back-edge agree by construction with no edge split. The mappings stay
  ordinary — evictable under pressure — and a pair nothing ever read through the mapping is
  demoted at the back-edge rather than refilled forever. On the `video` workspace the back-edge
  reload cause fell 5060 to 242 and `Video.H264.mcChroma` lost 19 of its 61 emitted reloads; the
  serial HEVC conformance decode (wpp-main10 + ipred, processor time of the test binary, order
  alternated) came out 3 to 7 percent faster across five interleaved campaigns — real, and far
  from the 2.2x.
- Three invariants paid for in miscompiles while building it, recorded so they are not
  rediscovered: **exporting a pair through a boundary snapshot is a consumption** — the adoption
  at the target lets later iterations read the register, so a snapshotted pair may never be
  demoted (`interpolateChroma` read a demoted taps pointer as garbage through exactly that path);
  back-edge fixups must be emitted before the jump's own operands are allocated and the pair
  values protected from that allocation, or a fixup overwrites the register the jump just chose;
  and preloads must stop above a per-class free floor, or they take exactly the claim-free
  registers and push the body's short-lived values onto ABI-touched ones where every concrete
  touch spills them.
- Next step: from the residency-era cause histogram of the hot decoder functions
  (`interpolateLuma` with residency: keep 31, back-edge 7, evict 65 of 117 use-reloads): the
  boundary family is now mostly paid for, and what is left is eviction churn under genuine
  pressure in fat bodies plus the join-disagree row. Swapping eviction priority to
  distance-before-clean measured flat on the HEVC decode and was reverted; the remaining lever is
  allocation quality with a real cost model — interval-style assignment with live-range
  splitting, whose justification stands unchanged in
  [F-190](#f-190--a-short-branching-function-spills-with-the-whole-register-file-free): at equal
  supply this allocator spills an order of magnitude more than clang on the same body.
- Re-measured 2026-08-27 with the cause trace rebuilt on build 224 (the patch is parked in the
  session scratchpad, `ratrace-parked.diff` — reapply it locally, never land it). Whole video
  workspace, release, static counts: 19928 spill reloads. Concrete-touch is now the largest row
  (5840, 29% — a new code the old taxonomy folded elsewhere; `Decoder.configureMetadata`, a cold
  call-dense builder, owns 1747 of them alone), then boundary-48 (3576, 17%), join-disagree
  (3567, 17% — diamond-heavy comparison chains: the generated `opEquals` bodies, `@typecmp`,
  `Allocator.reallocate`), evict (2736, 14%), residency-prune (2382, 11%). Join-backedge is down
  to 149 — residency holds — and join-nosnap is zero: every conditional-jump edge does record a
  snapshot, so there is no missing-snapshot lot to take. The static join-disagree row lives in
  cold code; the HOT decoder functions are all eviction-bound: `Decoder.idct` 101 reloads, every
  one an eviction; `interpolateLuma` 72 of 119; `filterLumaEdge` 34 of 77; `interpolateChroma`
  40 of 71. An edge-resolution pass (copies where edges disagree, the phase this allocator
  deliberately lacks) would clean the cold 17% and barely touch the decoder. The decoder's row
  is the fat-body pressure the entry's conclusion already names — see B-012.

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

### B-001 — Rematerialized invariants are hoisted back out of loops

- Intent: `PostRALoopHoist` re-hoists what the allocator re-materialized into a loop body -
  `LoadRegImm`, `ClearReg`, `LoadRegPtrReloc`, `LoadAddrRegMem` whose destination register
  has no other definition in the body and is dead at preheader live-out - the way post-RA
  MachineLICM repairs the spiller's insertions, cancelling the measured LICM-versus-remat fight
  from the consumer side.
- Complete when: an invariant constant or address re-made on every iteration of a hot loop is
  emitted once in the preheader (verified on a `PrintMicro` dump), relocations survive the
  move, and the video workspace decodes byte-exact.
- Measured 2026-08-27, closed without implementing: on the probe corpus at release, 44 remat
  instructions sit inside loop bodies, and only 4 satisfy the single-def-in-loop condition
  `HoistRegionPostRA` requires - all marginal invariant leas; the other 38 write registers the
  body reuses for other values (the deblock line loop re-makes its clamp constants into rdx,
  r10 and rsi in different arms). Dedicating one of the free registers instead (rax and rbp are
  untouched across that body) was checked against the answer sheet first: clang re-makes the
  same constants at the same sites (`mov r13d, 1023`, `mov edi, 6`, `mov edx, -6` inside the
  loop) rather than pinning a register - in-loop constant rematerialization is the behavior
  LLVM itself chooses on this kernel, because an immediate materialization is dependency-free
  and near-zero cost on an out-of-order core. There is no gap here to close.
- Related: the loop-invariant recomputation half of F-193; B-009 closed the eviction-policy route.

### B-002 — Loop-carried slot promotion covers multi-access, multi-exit loops

- Intent: `promoteCarriedSlots` promotes a carried frame slot accessed N times across several
  branch arms with M exits - one seed load before the header, register-only accesses inside, one
  write-back store per exit edge - instead of only the exactly-one-load, exactly-one-store,
  single-exit shape, mirroring LLVM's `promoteLoopAccessesToScalars`. Branch-dense codec
  accumulators updated in several arms are exactly what the current gate misses.
- Complete when: an accumulator written in two arms of a hot loop keeps its register across the
  back edge with no per-iteration store (dump-verified), a trace-based drop/store audit like
  T-563's validates the rewrite, and HEVC serial decode does not regress.
- Related: T-563, F-193.

### B-003 — Virtual-register webs get unique names

- Intent: a normalization pass gives every def-use web of a virtual register its own fresh
  register - the SSA property LLVM's passes get from their IR, reconstructed by renaming, with no
  phi nodes needed because a web that spans a join keeps its one name. The lowering reuses
  virtual registers across unrelated computations, so today a loop-invariant chain shares its
  register with code elsewhere in the function (measured on the deblock probe: the `pass % 3`
  chain's register carries five definitions, one outside the loop), and any pass that reasons
  per-register - the web hoisting now in LICM first among them - must refuse the whole register.
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
  than the loop passes earn. LLVM affords SSA-grade names because greedy RA re-splits and
  re-coalesces live ranges; this allocator does not yet. Blocked behind pre-RA re-coalescing of
  non-interfering webs or live-range splitting in the allocator. Prototype parked in the session
  scratchpad (`webrename-parked/`: `Pass.WebRename.{h,cpp}` plus the registration diff).
- Related: B-001, B-002, B-004; unlocks the full yield of the web hoisting shipped in LICM.

### B-004 — Jump-entered loops get a dedicated preheader

- Intent: a small structural pass gives every natural-loop header entered by a jump a fresh
  preheader label - non-back-edge jumps retargeted to it, fall-in preserved - so LICM, RA loop
  residency, `VecLoopPromote`, `PostRALoopHoist` and carried-slot promotion stop declining
  those loops outright. LLVM makes this shape (LoopSimplify) a precondition of its whole loop
  stack; with no phi nodes in the Micro IR it is pure label rewiring here.
- Complete when: the five loop passes accept a previously jump-entered loop (counted on a corpus
  dump), `BranchSimplify::redirectJumpChains` provably does not thread the new preheader away,
  and the suites stay green.
- Measured 2026-08-27 at the post-RA stage: all 33 natural loops of the release probe corpus
  plus `filterLumaEdge` and `interpolateLuma` enter their header by clean fall-through - the
  rotate pass has already normalized every hot entry by then. The post-RA half has no substrate;
  only the pre-RA half (LICM, `VecLoopPromote`) remains unmeasured. Deprioritized until a pre-RA
  count shows refused loops.
- Related: B-002, B-003.

### B-005 — Spill-area stores no path reloads are deleted

- Intent: a post-RA pass runs a backward byte-liveness fixed point over
  `[spillAreaLo, spillAreaHi)` on the instruction CFG and deletes every spill store no path
  reloads before overwrite - the write-back protocol audited from the consumption side, since the
  allocator manufactures stores wholesale and nothing checks whether any path reads them.
- Complete when: the pass lands with the three known landmines closed - exact read widths (a
  16-byte over-approximation pins the neighbouring 8-byte slot), push/pop and stack-pointer
  arithmetic not treated as area barriers (or the epilogue keeps everything alive), and any
  function with a stack-pointer adjustment between its first and last spill access skipped
  (call-argument setup shifts the offset coordinate system) - and the full video release run stays
  green. A parked prototype with all three fixes exists (session scratchpad,
  `dse-parked`).
- Related: F-190. The machine-dependent lane-count assertion that failed the prototype's validation run (h264.test.swg, fixed 2026-08-27) is gone, so the parked prototype can be retried as-is.

### B-006 — Integer reloads fold into their consumers' memory operands

- Intent: the post-RA peephole folds an integer reload from a private frame slot into its
  arithmetic consumer - `add rax, [rsp+X]` instead of a `mov` plus a register - the way
  `tryFoldLoadIntoFloatBinary` already does for floats and LLVM's fold tables do wholesale,
  covering `OpBinaryRegReg` (add, sub, and, or, xor, signed multiply) and
  `CmpRegReg`-to-`CmpMemReg`.
- Complete when: the integer rule ships with the float rule's guards (claiming, dst-dead-after,
  encoder conformance probe, `spillAreaLo/Hi` alias guarantee), a spill-heavy hot function
  shows the folds in its dump, and the suites stay green.
- Measured 2026-08-27: the single-reader-then-dead shape the fold needs occurs 3 times in
  `filterLumaEdge`, 11 in `interpolateLuma`, 3 in the deblock probe kernel - about 6% of their
  frame reloads. Real but small; the fold removes the instruction, not the load micro-op. Worth
  taking as a cheap sweep someday, not as a lot of its own. The same simulation ran a full
  forward availability dataflow (register still holds the slot - LLVM's
  `InlineSpiller::eliminateRedundantSpills` shape) over the corpus: 1-2 deletable accesses per
  hot function out of 167-288 - between a boundary store and its reload the register really is
  reused, so post-RA cleanup cannot remove the traffic. The demapping decision itself is the
  target (F-195).
- Related: B-005.

### B-007 — One alias oracle serves every pre-RA memory optimization

- Intent: the three existing private frame analyses - LICM's `analyzeFramePrivacy`,
  `PostRALoopHoist`'s `FrameReachability` root model, SLP's parameter-root classification -
  become one shared `MicroPassHelpers` analysis (sp-space / parameter-space / unknown),
  consumed by store-to-load forwarding (a frame-slot cache entry survives an unrelated pointer
  store), the combine passes' window aborts, and `ValueNumbering`'s memory epochs (a store to a
  provably disjoint space stops killing all load numbering; a label whose only predecessor is its
  fall-through stops advancing the epoch). LLVM's analog is BasicAA feeding EarlyCSE and GVN.
- Complete when: the shared analysis replaces all three private copies, forwarding survives
  across a disjoint-space store in a codec inner loop (dump-verified), and instruction counts on
  the video corpus do not regress.
- Related: B-001, B-002.

### B-008 — Inlining is a cost model, not a disqualification list

- Intent: the parse-time auto-inline verdict prices a call in the body as a penalty instead of a
  disqualifier, and a non-generic same-module function with exactly one call site inlines
  near-unconditionally (LLVM's `CallPenalty` and `LastCallToStaticBonus`) - the measured
  ceiling of everything above, since un-inlined helpers blind LICM, residency, value numbering
  and the alias oracle to the real loop nest, and force-inlining the deblock segment helper alone
  moved the kernel from 1.71x to 1.39x against clang.
- Complete when: the deblock segment helper auto-inlines without its `#[Swag.Inline]`, the
  cross-AST and generic cases stay excluded (the mechanism deliberately disabled after the
  aoc2019 miscompile), compile time and code size stay within the campaign's budgets, and the
  full validation campaign passes. Sema ordering races (the parse-time verdict, the
  CalleeReturn=CALLER gate) make this the last entry to attempt.
- Related: B-001 through B-007 all gain from it; the inlining half of F-193.

### B-009 — Eviction-policy changes have no purchase while loop residency covers the hot loops

- Area: compiler/backend
- Found while: the first recommendation of the LLVM study (2026-08-27), attempted before the
  entries above.
- Observation: three eviction-comparator variants in `Pass.RegisterAllocation.cpp` - next-use
  loop depth ranked first, an LLVM-style suffix sum of 10^depth over remaining uses, and a
  back-edge-wrapped next-use distance (the linear use cursor reads a loop-carried value whose
  static uses are behind the scan as infinitely cold, which is exactly backwards) - produced
  either regressions or byte-identical code on every measured function.
- Evidence: deterministic dump counts on the deblock C-twin probe and the real
  `Hevc.Decoder.filterLumaEdge` / `interpolateLuma`. Depth-first: 712 -> 719 instructions;
  suffix weights: 712 -> 723, damage concentrated in the straight-line segment preamble where
  flat next-use distance is near-Belady-optimal and depth weights over-protect multiples the
  per-line preloads already serve once per segment. Wrapped distance alone (comparator and the
  `K_KEEP_MAX_NEXT_USE_DISTANCE` boundary drop): byte-identical on all probes and hot
  functions; corpus-wide, release DLL sizes moved by at most one 512-byte alignment quantum in
  mixed directions. The sealed-loop residency of T-563 already exempts resident values from both
  the boundary drop and back-edge eviction, which is where the predicted pathology would have
  lived.
- Next step: none while residency holds the hot loops; re-measure only if B-002, B-003 or B-004
  creates loop pressure the residency machinery does not absorb. The wrapped-distance diff is
  parked in the session scratchpad (`r1-wrap-parked.diff`).
- Related: F-190, F-195.

### B-012 — A splitting interval allocator behind a per-function gate

- Intent: port the interval-splitting linear scan of Wimmer & Mössenböck (VEE 2005, the
  algorithm HotSpot's client compiler and LLVM's old linear scan implement) as a second
  allocator the pass selects per function, with the current allocator as the always-available
  fallback. Live intervals with holes and use positions replace the convex hulls; concrete
  claims become fixed intervals; allocation failure splits the current or the competing interval
  at the position the paper names instead of evicting whole values; and a resolution phase
  inserts register moves at block boundaries where locations differ — the phase whose absence
  today forces every disagreement through memory. This is the route every cheaper repair now
  points at from measurement: post-RA cleanup finds 1-2 removable accesses per hot function
  (B-006), eviction-policy tuning is inert (B-009), the proven-free reservation fires 17 times
  in 12211 (F-195), and the hot decoder functions lose their registers to genuine fat-body
  pressure the one-value-one-register model cannot price (idct: 101 of 101 reloads are
  evictions). At equal register supply this allocator spills an order of magnitude more than
  clang on the same body (F-190); splitting is how clang does it.
- The v4 lesson bounds the design: the 2026-07-31 whole-hull attempt died of four successive
  miscompiles because it patched agreement invariants into the existing machinery, and each
  repair uncovered the next. The port therefore does not touch the existing scan: it is a
  separate assignment path selected only for functions that satisfy its preconditions (precise
  CFG, first sweep, initially call-free leaf functions of the hot corpus), gated so a failed
  precondition falls back to the current allocator, and grown outward one class of functions at
  a time with the reload-cause trace and byte-exact decode as the gate at each step.
- Complete when: the gated allocator compiles the HEVC hot four (idct, interpolateLuma,
  filterLumaEdge, interpolateChroma) with materially fewer emitted reloads than the cause-trace
  baseline (idct 101, interpolateLuma 119, filterLumaEdge 77, interpolateChroma 71), the video
  workspace decodes byte-exact under it, the full suites stay green with the gate open on its
  supported class, and the serial HEVC conformance decode improves measurably.
- Related: F-190, F-195, B-003 (unblocks web renaming), B-002; supersedes the abandoned v4
  whole-hull design (`global-regalloc-wip/global-regalloc-v4.patch`).
