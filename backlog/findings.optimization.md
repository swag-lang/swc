# Findings — Optimization

Backend optimization passes, register allocation, and the performance of the code `swc` generates.
Frontend and lowering defects are [findings.compiler.md](findings.compiler.md).

Conventions, the identifier counter, and the rest of the backlog are in [README.md](README.md).
Entries are sorted by identifier, ascending; position carries no priority.

## Loop vectorization

### F-029 — ChaCha20 still processes one block per packed dependency chain

- Area: std/core (crypto), compiler/backend
- Found while: benchmarking the auto-vectorized ChaCha20 rounds ([T-088](todo.vaultdrive.md#t-088--chacha20-processes-one-block-per-dependency-chain))
- Observation: the rounds are vectorized and remain in registers, but one invocation still carries
  one block state through one packed dependency chain. Four independent blocks would expose the
  parallelism a single state cannot provide; the counter is the only lane-varying input.
- Evidence: measured 2026-08-06 with an interleaved ABBA DLL-swap, 6 pairs and medians of 8
  in-process samples,
  every run asserting by file size which core.dll it staged): pure double-rounds kernel
  121.6 -> 196.6 MQR/s (+62%, the vectorized side won every pair), `chacha20Block` key-stream
  generation 88.8 -> 113.1 MiB/s (+27%), end-to-end `chacha20Xor` 90.5 -> 109.4 MiB/s (+21%
  median; +3-4% on the pairs that landed in the machine's stable phase - the block-level
  plumbing around the rounds still dominates end-to-end). The kernel gain is bounded by the packed
  dependency chain rather than instruction count: the scalar rounds run four independent chains
  in parallel on the out-of-order core, so 6x fewer instructions buys about 1.6x, the known
  single-block ChaCha SIMD profile.
- Next step: process four blocks per loop iteration, adding splat constants and vector construction
  for the mixed-source counter chunks, then measure the block and end-to-end rates with the same
  interleaved protocol.

### F-034 — Unrolling a loop does not hand it to the vectorizer

- Area: compiler/backend
- Found while: chasing the second half of the ChaCha20 gap after the round loop stopped spilling
- Observation: after the rounds were fixed, the dominant cost became the key-stream application -
  sixteen words XOR-ed one at a time, a loop the unroller refuses because `K_MAX_TRIPS` is 8. The
  obvious move (raise it to 16, since `K_MAX_TOTAL_INSTR` already bounds the blow-up) unrolls the
  loop and buys nothing: the sixteen copies stay scalar, so the whole function doubles - 187 to
  377 instructions - for the loop overhead alone. The gain hoped for was the SLP pass seeing
  sixteen adjacent stores; it does not see them.
- Evidence: the unrolled body keeps 16 `load_addr_amc_reg_mem`, 71 loads and 49 zero-extensions.
  The indexed (Amc) addressing survives unrolling instead of folding into constant offsets, and an
  Amc access is exactly what makes the SLP scan give up on a block
  (`hasUnresolvedMemRead`/`Write`). Raising the limit also perturbed the round loop, 23
  instructions to 39. Reverted; the limit stays at 8.
- Next step: the missing step is constant-index folding after unrolling, not a bigger unroller. A
  cloned body whose induction variable is now a constant should have `[base + i*4]` rewritten to
  `[base + K]`, which is what turns the Amc form into the constant-offset form the vectorizer
  reads. Check whether instruction-combine already does this and is simply not re-run after the
  unroll, or whether it has no rule for Amc-with-constant-index at all.

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

### F-069 — A byte the loop compares is loaded again to use it

- Area: compiler/backend
- Found while: reading csvagg's digit loop after the hoisting pass above
- Observation: `while p < eol and text[p] != ',' { qty = qty * 10 + (text[p] - 48) }` reads the same
  byte twice — once through `cmp_amc_imm [base + p], ','` and once through
  `load_amc_reg_mem r, [base + p]`. Instruction-combine folded the first load into the compare,
  which leaves nothing for the second to reuse, and value numbering does not number indexed memory
  reads so it never merges them.
- Evidence: csvagg's digit loop, 15 instructions with 4 memory operations, of which two are this
  one byte. clang-cl reads it once into a register and both compares and uses that.
- Next step: two candidate rules, and the cheaper one first — decline the fold into a compare when
  the loaded value has another use (the fold is only a win when it kills the load), or number
  indexed loads in value numbering when no intervening write can alias them. The first is local to
  `Pass.InstructionCombine.LoadFold`; the second is worth more but needs the aliasing question the
  post-RA hoist above already answers conservatively.

### F-121 — Text shading and bilinear texture lerps still dominate a CPU-rendered widget frame

- Area: std/pixel (RenderCpu)
- Found while: cutting headless-test frame times with the batch rasterizer fast paths
- Observation: after the constant-fill, copy-blit, DstIn-skip, and BGRA8 fetch fast paths, a
  900x700 fast-debug frame fell from 141 ms to 29 ms when empty, but a frame carrying 80 themed
  buttons stays near 200 ms. Adding 40 text labels changes almost nothing, and the residual
  concentrates in the paths that cannot keep bytes stable without care: `shadeMsdf` evaluates
  four supersample coverages of four bilinear atlas fetches plus a `pow` per shaded pixel, and
  a bilinear texture paint runs three `lerpColor` round trips through `fromArgbF32` per pixel.
- Evidence: isolated probe module driving `Gui.Testing.HeadlessHost` (2026-08-12, fast-debug,
  serial painter scenes): full-surface opaque fill 366 -> 19.6 ms, alpha fill 394 -> 31 ms,
  empty host frame 141 -> 29 ms, 80-button frame 480 -> ~200 ms, and buttons+labels ~= buttons.
  The gui suite run dropped 26.9 s -> 10.8 s for 379 tests on the same change.
- Next step: three leads, in decreasing value. Lower the presentation blit (Copy, Pixel
  interpolation, content scale 1, same-size integer rectangles) to row copies once the
  nearest-neighbour mapping is proved an identity over that domain. Share atlas fetches between
  the four MSDF coverage taps, validating against the pixel image goldens and refreshing them
  deliberately if bytes move. Replace the bilinear `lerpColor` chain with integer arithmetic
  under the same golden policy.

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
- The register half was then traced to its mechanism and moved to
  [F-138](#f-138--a-whole-hull-reservation-cannot-keep-a-loops-working-set-in-registers), which
  carries the numbers.
- Next step: this is [F-068](#f-068--complex-loop-carried-frame-slots-still-lose-registers) seen
  from a second workload, and the case is small enough to drive the fix — a loop whose whole
  live set fits in registers twice over and is spilled anyway. Same conclusion as
  [F-029's](#f-029--chacha20-still-processes-one-block-per-packed-dependency-chain) neighbours: the
  bottleneck is the allocator's policy, local linear scan with furthest-use eviction, and the
  work that addresses it is the global interval allocator, not another peephole.

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

### F-165 — Integer ternaries lower to branches and starve pixel loops

- Found while: T-504, profiling the H.264 decoder on a 1080p30 Main stream in release.
- Observation: `Math.clamp`, `Math.min`, `Math.max`, `Math.abs`, and every integer ternary
  compile to compare-and-branch. `#[Swag.PrintMicro("pre-emit")]` on the YUV-to-RGB inner loop
  shows two conditional jumps per clamped store plus per-iteration reloads of loop-invariant
  pointers from the frame — every branch is an allocation boundary, so the loop's live set
  flushes at each pixel. Rewriting the decoder's clamps as sign-bit arithmetic (the
  `value & ~(value >> 31)` family now in `h264.transform.swg`) took the conversion stage from
  1495 ms to about 470 ms over 59 frames — 3.2x from removing branches alone, byte-identical
  output — and the deblocking filters gained another ~30% from the same treatment.
- Also measured: forcing `#[Swag.Inline]` on the ~25-instruction `CabacReader.decision` at its
  ~40 call sites regressed the parse stage ~10% — inlining raised pressure and the allocator
  spilled more, the same mechanism as
  [F-138](#f-138--a-whole-hull-reservation-cannot-keep-a-loops-working-set-in-registers).
- Next step: lower integer `cond ? a : b` — and through it the Math min/max/clamp/abs family —
  to a compare-and-select without a branch in the backend, then re-measure the decoder's
  deblock and conversion loops and retire the hand-written sign-bit forms if the select
  matches them.
