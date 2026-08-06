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
