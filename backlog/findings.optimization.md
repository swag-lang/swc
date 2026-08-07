# Findings — Optimization

Backend optimization passes, register allocation, and the performance of the code `swc` generates.
Frontend and lowering defects are [findings.compiler.md](findings.compiler.md).

Conventions, the identifier counter, and the rest of the backlog are in [README.md](README.md).
Entries are sorted by identifier, ascending; position carries no priority.

### F-029 — ChaCha20 throughput is bounded by memory round-trips, not by round arithmetic

- Area: std/core (crypto), compiler/backend
- Found while: benchmarking the auto-vectorized ChaCha20 rounds (sCrypt entry 2)
- Observation: with the rounds fully vectorized (the double-round loop compiles to ~90 packed
  instructions instead of ~500 scalar ones, `chacha20Block` overall 2794 -> 915), end-to-end
  `chacha20Xor` throughput did not move measurably (medians 34.4 vs 34.0 MiB/s vectorized vs
  scalar, DLL-swap interleaved protocol, though on a machine whose baseline drifted 2-40 MiB/s
  between sweeps). Two structural costs were identified: the vectorized state round-tripping
  through the frame on every round-loop iteration, and the byte-/word-granular per-block
  plumbing (the word-at-a-time key-stream application landed with the original investigation).
- Status: the register-resident half is implemented. `Pass.VecLoopPromote` claims the loop
  region the block-scoped SLP pass cannot see: the packed load of a frame chunk moves to the
  preheader, the packed store to the loop's unique fall-through exit, and the body accesses
  become 128-bit copies of one loop-carried virtual register, which the allocator pins in a
  callee-saved XMM (verified on the ChaCha rounds: the ten iterations run entirely in
  xmm6-xmm9, with four packed loads before the loop and four packed stores after it). Two
  mem2reg escape refinements feed it on real shapes: a frame-base APPEARING AS A VALUE (stored
  to a slot) or as the BASE OF AN INDEXED Amc access is the address of the object at offset
  zero and now poisons that object instead of bailing the whole function - without this, a
  function whose first local's address escapes (every inlined pointer-parameter home) lost all
  scalar promotion, the inline indices stayed in memory, and the SLP pass never fired.
- Measured (2026-08-06, interleaved ABBA DLL-swap, 6 pairs, medians of 8 in-process samples,
  every run asserting by file size which core.dll it staged): pure double-rounds kernel
  121.6 -> 196.6 MQR/s (+62%, the vectorized side won every pair), `chacha20Block` key-stream
  generation 88.8 -> 113.1 MiB/s (+27%), end-to-end `chacha20Xor` 90.5 -> 109.4 MiB/s (+21%
  median; +3-4% on the pairs that landed in the machine's stable phase - the block-level
  plumbing around the rounds still dominates end-to-end). The kernel gain is bounded by the
  packed dependency chain, not by instruction count: the scalar rounds run four independent
  chains in parallel on the out-of-order core, so 6x fewer instructions buys ~1.6x, the known
  single-block ChaCha SIMD profile. Beware: every earlier throughput comparison (including the
  original "unchanged, 34.4 vs 34.0" measurement) compared two identical vectorized binaries -
  `--cpu-vectorize` from the command line assigned its value but never raised
  `cpuVectorizeExplicit`, so the override was silently dropped; fixed alongside this pass.
- Next step, in likely order of value: process several blocks per loop iteration (the real
  SIMD ChaCha win: four independent block states fill the packed dependency chain and the
  counter is the only lane-varying input, which also needs splat constants and vector build of
  mixed-source chunks), parameter-rooted chunks (`chachaRounds` over a caller's array keeps
  its round-trips), loops whose exit is a taken branch rather than a fall-through, and the
  AVX2 256-bit tier.

### F-033 — The vectorizer emitted destructive shapes and the allocator paid for them in memory

- Area: compiler/backend
- Found while: closing the ChaCha20 gap the new `bench/` task exposed (swag 2.26x clang-cl, the
  worst of the seven tasks; the other six sit between 0.98x and 1.64x)
- Observation: the SLP vectorizer expanded every packed operation into the two-address shape
  legacy SSE requires - a copy of one operand into the destination, then the operation in place.
  A rotate needs its source twice, so it produced two copies; the register allocator gave one of
  them a stack home instead of one of the six free XMM registers, and the vectorized ChaCha round
  loop carried four stores and four reloads per iteration, all on the store-to-load forwarding
  chain. The copies were the cause: the post-RA peephole that folds a copy into a VEX
  three-operand form (which now also covers the packed operations) never saw them, because the
  allocator had already turned one into a spill/reload pair.
- Evidence: the round loop went from 40 instructions with 8 memory operations to 23 with none,
  once the vectorizer emitted `OpBinaryRegRegReg` / `OpBinaryRegRegImm` directly instead of
  copy-then-operate. Read clang's assembly first: it does not vectorize these rounds at all - it
  keeps the sixteen state words in sixteen scalar registers with `rol` and touches no memory in
  the loop - which is what made the memory traffic on our side stand out as the anomaly rather
  than the vectorization itself.
- Next step: the same shape almost certainly appears elsewhere. Any pass that emits a two-address
  sequence pre-RA is asking the allocator to preserve a value it has no instruction to preserve
  cheaply; the allocator's answer is a spill. Audit the remaining pre-RA producers of
  copy-then-operate pairs (the float paths in particular) against the same rule: when the target
  has a non-destructive encoding, emit it and let the allocator see two independent sources.

### F-034 — Unrolling a loop does not hand it to the vectorizer

- Area: compiler/backend
- Found while: chasing the second half of the ChaCha20 gap, once the round loop was fixed
  ([F-033](#f-033--the-vectorizer-emitted-destructive-shapes-and-the-allocator-paid-for-them-in-memory))
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

### F-036 — Folding copy-then-operate before register allocation miscompiles

- Area: compiler/backend
- Found while: generalizing [F-033](#f-033--the-vectorizer-emitted-destructive-shapes-and-the-allocator-paid-for-them-in-memory)
  to the float paths, which show the same shape: `raytrace`'s intersect loop carried 16 copies and
  11 stores in a loop that only computes, and the post-RA fold converted 6 pairs out of ~22
- Observation: rewriting an adjacent `mov %d, %a` / `%d op= %b` into `%d = %a op %b` in the
  PRE-RA peephole does what it promises statically - the loop's copies drop 16 to 6, its stores
  11 to 5, and three-operand forms go 6 to 22 - and then every script crashes with 0xC0000005
  under the JIT, after compiling cleanly. The same rewrite is sound post-RA, where it has shipped
  for a while.
- Evidence: `tools/scripts.bat dm` fails on every script, right after "tuned"; the failure is an
  access violation in JIT-executed code, not a compiler error. Minimal float arithmetic through
  the JIT is fine, so the broken shape needs the surrounding std modules. Unit tests, the native
  optimizer tests and the earlier phases of `tests.bat dm` all pass, which is what let it get as
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
  cheaply first: restrict the fold to `FloatAdd` alone and run `tools/scripts.bat dm` - a crash
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
- Re-tested on top of F-067 and F-068, on the suspicion that the `lea`+`mov` regression was only
  the copy-forwarding gap those rounds closed. It is not: judged on the loop bodies rather than the
  clock, the emitted code moves AWAY from clang-cl. csvagg's four byte-scan loops go back from 6
  instructions to 7 (clang-cl emits 6), leven's inner loop 206/80 to 218/89, and over every loop
  body 3258 to 3299 instructions and 1170 to 1180 memory operations. Reverted a second time.
- Next step: the escape counts were real but not binding, so the remaining value is in what they
  were masking rather than in the derivation itself. Do not re-attempt the derivation on its own a
  third time. If it returns, it has to come with an explanation of why promoting those extra slots
  makes register allocation emit FEWER memory operations in the loops, not more — the two
  measurements so far both say it emits more.
- Related: [F-067](#f-067--instruction-combine-folds-a-slot-load-into-an-operand-and-mem2reg-then-refuses-the-slot),
  [F-068](#f-068--a-hot-loops-base-pointer-loses-its-register-to-the-cold-code-around-it)

### F-067 — Instruction-combine folds a slot load into an operand and mem2reg then refuses the slot

- Area: compiler/backend
- Found while: the same campaign, tracing why sha256's eight compression-state words never leave
  the frame
- Observation: instruction-combine folds `load t, [slot]` + `op d, t` into `op d, [slot]`, and
  mem2reg's escape analysis did not list the memory-operand ALU and compare forms among the scalar
  accesses it understands. A slot an earlier sweep could have promoted therefore became an
  unexplained escape on the next one, and the whole variable was condemned to memory — the
  optimizer defeating itself, and irreversibly, because the pre-RA loop only ever folds further.
  Fixed by recognizing `OpBinaryRegMem`, `OpBinaryMemReg`, `OpBinaryMemImm`, `OpUnaryMem`,
  `CmpMemReg` and `CmpMemImm` as accesses of one slot and rewriting them to their register forms
  on promotion.
- Evidence: `OpBinaryRegMem` was the top escape cause in sha256's timed function (28 occurrences
  against a background of 8). A probe holding the compression loop in its own function went from
  319 to 196 instructions; the minimal shape that reproduces it — eight locals initialized from a
  pointer parameter — went from 174 to 140. Diagnosis method: a temporary env-gated trace in the
  escape scan printing the opcode of every unexplained tracked register, attributed per function.
- Next step: the same self-defeating pattern is worth auditing elsewhere. Any analysis keyed on a
  syntactic shape that a *later* fold rewrites will decay the same way as the pre-RA loop
  converges; instruction-combine's memory folds are the ones that rewrite the most shapes.

### F-068 — A hot loop's base pointer loses its register to the cold code around it

- Area: compiler/backend
- Found while: the same campaign, asking why the identical loop compiles differently in two places
- Observation: the register allocator grants a value a register for its whole live range, ranked by
  `benefit / spanLength`. A pointer a hot loop dereferences on every iteration lives for the whole
  function, so its density is microscopic, and it loses to short-lived values in cold code — in the
  bench tasks, to the *untimed* data-generation loops that share `main` with the timed one. The
  allocator then reloads it from its stack home once per iteration, forever.
- Evidence: decisive and cheap to reproduce — the same csvagg scan loop compiles to 7 instructions
  with a reload of `text` inside `main`, and to 6 instructions with no memory operation at all when
  the loop is moved to a small function (`scratchpad` probe `iso5`), which is exactly what clang-cl
  emits. The digit loop goes 16 instructions / 5 memory operations inside `main` to 14 / 0 isolated.
- Status: the case that needs no write-back is fixed. `Pass.PostRALoopHoist` splits a
  loop-invariant reload's live range at the loop boundary — the load moves to the preheader, other
  loads of the same slot in the body become register copies or disappear — guarded by exact
  post-RA physical liveness (`MicroPassHelpers::computePhysicalLiveness`, factored out of the
  post-RA dead-code pass). No loop in `bench/` regressed; the hot ones went 7/2 to 6/1 (csvagg's
  four scan loops), 12/2 to 11/1 (the FNV loop of `mapProbe`, shared by four tasks), 16/6 to 15/4
  (csvagg's digit loop) and 243/100 to 226/86 (sha256's block loop), in instructions/memory
  operations per iteration.
- Status of the loop-CARRIED case: also fixed, for the shape where one register carries the value.
  The same pass now promotes a slot the body reads once and writes once through a register that
  carries nothing else across the iteration: the load and the store leave the loop, the register is
  seeded before it and written back once on the single instruction every exit converges on. Two
  supporting details mattered. The register has to be free, and it was not: a redundant reload of an
  already-hoisted slot used to be left behind as a register copy, which pinned the register the
  accumulator needed — pointing that reload's readers at the hoisted register instead frees it, and
  is worth an instruction on its own. And the preheader usually stores the initial value into the
  slot already, so the seeding load is skipped when the register still holds it. Measured on
  csvagg's digit loops: 15/4 to 12/2 and 12/3 to 10/1, instructions/memory operations per iteration.
- Next step: the shapes still refused, in order of what they would buy. sha256's `a`..`h` are eight
  slots at once and each one's register IS reused between its load and store, so the
  carries-nothing-else test fails on all eight — that needs the eight promoted together, or the
  ranking fixed pre-RA. leven's DP loop writes `row1[y+1]` through a program pointer, which makes
  the body opaque to the aliasing model; the model is "any non-frame write may alias any frame
  slot", and it could be sharpened to "a program pointer cannot alias a REGISTER-ALLOCATOR spill
  slot" if the allocator recorded where its spill area starts. Attacking the ranking itself — a hull
  scoped to the loop region rather than the whole span — is the same idea done pre-RA, and is what
  four earlier attempts at a global allocator foundered on.

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
