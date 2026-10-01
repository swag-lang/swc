# Optimization Backlog

Backend optimization passes, register allocation, and the performance of the code `swc` generates.
Frontend and lowering defects are [compiler.core.md](compiler.core.md).

Entries are ordered from the most recently updated down. [README.md](README.md) defines
the shared backlog conventions.

Several entries address register residency, loop-entry shape, spill traffic, aliasing and
inline argument materialization. Earlier measurements used the whole-hull allocator; optimizing
builds now use interval splitting, so those measurements identify workloads to recheck rather than
current performance guarantees. `MicroSsaState` reconstructs SSA and phi values for analysis, while
the executable Micro instruction stream has no explicit phi instruction. Since build 438, a call
that the straight-line path steps over — a safety panic, a cold refill — no longer constrains the split
allocator: a value crossing it in a caller-saved register is parked in its home inside the cold
block, and the hot path keeps the register.

### compiler.optimization.105 — Keep lz77's outer index resident through the match loop

- Recorded: 2026-09-30 08:42
- Updated: 2026-10-01 13:13 — Hoisted the repeatedly used address and compared the remaining spill with the current Zig winner.
- Area: compiler/backend, register allocation and value ranges.
- Comparison: accepted campaign `20261001-103647` names Zig 0.15.2 `ReleaseFast` as the
  fastest other runtime at 19.9267 ms, versus Swag native at 21.3543 ms. Its byte-match
  loop at `0x140001500..0x140001512` has six instructions and two memory reads. The
  candidate span at `0x1400014F0..0x140001553` has 29 non-NOP instructions and three
  actual memory operands; two LEAs are address calculations, not memory accesses.
  Zig retains the outer index in `rdx` and forms the current-position address before
  entering the candidate loop.
- Current evidence: the Swag byte-match loop retains six non-label instructions,
  two memory reads and `CHECK=622942003053`. LICM now recognizes an invariant address
  consumed by a single textual reader inside a nested loop: when the address runs
  on every enclosing iteration and no call crosses its lifetime, it can move to the
  enclosing preheader. The candidate span falls from 30 to 29 non-label instructions
  (35 to 34 including labels), with the same four actual memory operands and one
  frame read; its two LEAs become one. This closes the repeated-address gap.
- Remaining spill: the byte load reuses `rax`, which held the outer index. The latch
  reloads that index from `[rsp + 0x200]`. The first pre-allocation dump keeps the index
  as `%1227` without a frame round trip; the first post-allocation dump introduces it.
  Whole-function totals remain 517 Microinstructions, 479 non-label instructions,
  106 actual memory operands and 32 actual frame operands. The older 131/34 counts
  included 25 address calculations, two frame-relative; the counters now distinguish
  those from memory accesses. These totals do not describe the candidate-loop cost.
- Range boundary: `cand % WINDOW` is already a mask, justified by `cand >= 0`.
  Swag's signed `i` and `p` remainders retain sign correction. Zig uses `@mod`, whose
  floor-modulo result for a positive power-of-two divisor permits masking even for
  negative inputs; Swag's signed remainder has a different contract. The previously
  inspected C++/Clang 20.1.8 winner also retained sign correction. Simplifying Swag's
  remaining remainders requires proving the counters' bounds under its own semantics.
- Next: follow the outer index's interval and the spill election. Keep it across
  the match loop without adding per-byte traffic or moving another frequently used
  value to memory. The address-hoisting change does not resolve this allocation decision.
- Complete when: the candidate latch no longer reloads the outer index and the match
  loop retains its six instructions and two memory operands without a loss elsewhere.

### compiler.optimization.104 — The n-body pair loop keeps its pairs scalar

- Recorded: 2026-09-30 08:42
- Updated: 2026-10-01 12:54 — Added the accepted noon campaign without attributing individual timing effects.
- Area: compiler/backend, loop unrolling, memory forwarding and SLP vectorization.
- Comparison: accepted campaign `20260930-195406` reports Zig 0.15.2 at 15.2582 ms and
  Swag native Release at 30.3729 ms, with `CHECK=169096566666`. The inspected Zig
  `ReleaseFast` timestep has 348 machine instructions and 101 memory operands, retains
  body state across timesteps, and executes four packed and two scalar square roots.
- Regression evidence: the preceding accepted campaign `20260930-152655` reports Swag
  native at 24.8768 ms; the raw increase is 22.1%, amplified to 38.5% by the campaigns'
  different control factors. JIT moves from 25.6579 to 24.8732 ms. A fresh dump from the
  preserved `f0a34dcf4` compiler shows why the two modes are not the same code: `#run`
  retains the call to `advance`, while `#main` inlines it. JIT's 470 non-label Micro
  operations in `advance` exactly match the native function from `819dd7872`, before
  borrowed-slice inlining. An accepted controlled comparison must still separate the
  earlier register/forwarding changes, inlining, and the current scalar dependency fixes.
- Latest accepted campaign `20261001-103647`, built from `49f7e665d`, reports native
  at 23.5431 ms (23.1885 after its task normalization), JIT at 25.9971 ms and the same
  Zig 0.15.2 winner at 16.45 ms. The native raw result is below the September 30 evening
  result again; it is still 1.431x the current winner. This full-campaign observation
  is not a same-session causal comparison of the retained batches. Its calibration
  drift is 17.35%, so the separate historical attribution below remains necessary.
- Measurement limit: the October 1 historical comparisons at 07:36, 10:21 and 11:23
  all fail the declared control gates. Even after a 30-second warmup, nbody's
  control p90/p10 is 1.304 and its half-window median drift is 1.243; raytrace's
  control p90/p10 is 1.298. The gates remain 1.20 and 15% respectively, with every
  sample retained. These cohorts cannot quantify the regression's individual causes
  or establish a speedup from the retained changes. Repeat on a stable machine.
- Current shape: main's timestep is 449/131/24 Microinstructions/memory operands/explicit
  frame operands, including the 16/6/0 position loop. The prior inlined shape was
  464/117/24. The slice-header vector round trip is gone, as are the timestep's transfers
  between the integer and floating register files. The fourteen extra memory operands
  replace cached integer bits; this is a code-level tradeoff, not a measured speedup.
  All 32 register-to-register scalar copies in the timestep are full-width copies with
  no dependency on the old destination's unused lanes. Its ten roots are encoded as
  actual scalar roots, rather than computing an unused second lane.
- Remaining gap: the pair roots and divisions still operate on one interaction at a
  time. A useful pack must share the coordinate producers and scalar consumers without
  retaining more live state than the register file can hold. The position loop already
  packs x/y updates and has no frame traffic inside it.
- Rejected root-pair scheduling after inlining: hoist the second independent distance's
  proven pure producers across disjoint same-base stores, rename their SSA values, then
  pack two scalar square roots. Main's timestep uses three packed and four scalar roots,
  but changes from 464/117/24 to 511/148/76 instructions/memory operands/frame operands.
  The standalone step reaches five packed roots, at 529/176/107 instead of 473/134/44.
  Both checksums remain exact; Raytrace remains unchanged. Extending coordinate lifetimes
  costs more memory than the packed roots save, so the prototype was removed.
- A second schedule caches the hoisted coordinates and upper root lane in integer registers
  until their original uses. Main's loop still regresses to 532/145/73; the standalone step
  is 575/172/103. The integer transfers do not remove enough XMM interference and add more
  instructions. This prototype was also removed. A profitable next design needs packed
  coordinate producers and their scalar consumers planned together, with a register-pressure
  estimate; pairing the expensive operations alone is not sufficient.
- Rejected scalar-prefix trial: capturing common magnitudes before store-tree vectorization,
  and allowing untouched prefix/suffix roots, grows the step from 464/152/44 to 576/222/119
  instructions/memory operands/frame operands. Scalar coordinate work remains live for the
  distance reductions, while packed velocity trees recompute it and keep the captures live.
  The checksum stays exact, but the static regression rejects this approach. Packing needs
  shared scalar/vector producers or independent pair scheduling, not late store trees alone.
- Failed earlier trials: outer-unroll temporary renaming alone changed no benchmark function.
  Broad LICM address reassociation grew SHA-256 main from 370 to 553 instructions by hiding
  the four-byte swap idiom; keep the narrowed reassociation guard.
- Next: finish the controlled historical attribution, then plan packed producers and
  consumers together with a register-pressure estimate. Compare each interaction region
  and the position loop separately; fewer memory operands alone did not settle the
  previous integer-cache tradeoff.
- Complete when: the step retains or packs body state with no redundant pair work and
  matches the winner's packed roots/divisions without a generated-code loss in other tasks.
- Related: compiler.optimization.016, language.design.037.

### compiler.optimization.094 — Defer callee-saved XMM traffic past an early exit

- Recorded: 2026-09-28 09:58
- Updated: 2026-09-30 19:55 — Closed the focused round with retained-code validation.
- Area: compiler/backend, register allocation, prologue and unwind information
- Evidence: The latest accepted campaign (`20260928-105618`) names C++/MSVC as raytrace's fastest other runtime (9.249 ms versus Swag's 10.469 ms; ratio 1.132). In `trace`, Swag saves XMM6–XMM15 before its first `intersect` call and reloads all ten on the no-hit return. MSVC saves six XMM registers before that call; after `g_HitI >= 0` it saves XMM9 and XMM13–XMM15, which the no-hit path never touches. The no-hit path therefore avoids four stores and four loads in MSVC. Swag's frame reserves `0x168` bytes and MSVC's `0x128`, though allocation size alone does not measure the path cost.
- Unwind evidence: `dumpbin /unwindinfo` on the accepted MSVC executable shows a primary `trace` range `0x1440–0x14DA` with six `SAVE_XMM128` records and a chained range `0x14DA–0x16F0` with saves for XMM9/XMM13/XMM14/XMM15 plus RBX/RDI. The no-hit return at object offset `0x74` lies in the primary range; the four later saves begin at offset `0xB4`. Two further chained ranges describe later control-flow regions. Swag currently builds one `UNWIND_INFO` blob in `X64UnwindWindows`, one native `.pdata` entry per function in `DebugInfoCodeView`, and one JIT `RUNTIME_FUNCTION` per allocation in `Os.Windows`. Those three interfaces must represent multiple code ranges before a delayed save can be correct under Windows unwinding.
- Contract: [Microsoft's x64 unwind specification](https://learn.microsoft.com/en-us/cpp/build/exception-handling-x64?view=msvc-170#chained-unwind-info-structures) permits chained code regions for delayed register saves, but excludes an additional push or fixed stack allocation in the delayed region. The save slots must therefore remain in the entry frame. The encoder currently closes unwind tracking after the first ordinary instruction, while `MachineCode` exposes a single unwind byte array; `DebugInfoCodeView::appendUnwindSections` writes one `.pdata` record, and `Os::addHostJitFunctionTable` registers one runtime range. `PrologEpilogSanitize` also shares identical return tails, so the early and hit exits must carry the right saved-register state after that rewrite.
- Binarytrees audit (Node 20.15.1 winner in `20260930-152655`): the retained `check`
  is 25 instructions/three memory operands, including two pushes and two pops (excluded
  from the memory-operand count). A leaf still pays the prologue and restores. Delaying that work across the first null guard is not a local
  peephole: the current single unwind range cannot describe the leaf's different frame.
- Rejected short-tail sharing: admitting the four-instruction scalar epilogue in
  `collectReturnTail` changes `check` from 25/3 to 23/3 static instructions/memory operands,
  but adds one executed unconditional jump to the recursive return and removes no executed
  restore. Nbody, Raytrace, ChaCha and SHA-256 counts and all five checksums are unchanged.
  This is a size tradeoff, not a speed-path improvement; the existing two-XMM-restore gate
  was retained. Together with the two nbody root schedules, this ends the focused static
  round after three consecutive attempts without a retained gain. Eight earlier batches
  remain integrated; the winner mechanisms have not yet converged. No further local
  rewrite is justified by the evidence: the remaining work needs register-pressure-aware
  vector plans, allocator strategy, or multiple unwind ranges.
- Final retained-code validation: 1205 C++ tests, 3532 native-suite tests in each of
  devmode and release (JIT and native), semantic positive/negative suites, scripts, the
  repository checks and all five inspected benchmark checksums pass. Restoring the failed
  prototypes restores the accepted instruction counts. No new timing campaign was run.
- Next: represent unwind ranges and parent links in `MachineCode`, emit them from the final physical instruction stream, and publish all ranges in native `.pdata` and the JIT function table. Then move only saves for registers first defined below the guard, with a proof for each path to a restore. Test both arms, nested calls and exceptional unwinding before and after the delayed saves in native and JIT output; compare no-hit and hit paths against MSVC.
- Complete when: the short path skips unused saves and restores without adding spill traffic to the hit path, and unwind and ABI checks pass; otherwise keep the current eager save plan.

### compiler.optimization.016 — General value-web normalization still extends live ranges too far

- Recorded: 2026-08-27 07:57
- Updated: 2026-09-30 18:31 — Rechecked scalar-double web splitting with the current interval allocator.
- Intent: give independent def-use webs separate virtual registers so LICM, value numbering
  and memory forwarding can distinguish computations that lowering gave the same name.
  Live phi joins and destructive updates must retain a common name. Dead phi cycles must not
  glue otherwise independent values together.
- Existing boundary: the unroller already renames independent temporaries in straight-line
  copies, but leaves carried values and bodies with internal labels unchanged. A flattened
  nested loop can therefore still contain independent values sharing a register.
- Rejected with the former hull allocator: the union-find prototype hoisted the deblock
  modulo chain, but grew `interpolateLuma` from 1583 to 1684 instructions and 314 to 398 frame
  references. No prototype from that experiment remains in the repository.
- Current experiment: a scalar-double union-find reconstruction over SSA values, with live
  phi and read-modify-write unions, still worsens unrelated floating code under interval
  splitting. Raytrace `intersect` grows from 205 to 211 instructions, 44 to 48 memory operands
  and 22 to 26 frame references; `trace` grows from 172 to 176 instructions and 56 to 58 memory
  operands. ChaCha, SHA-256 and binarytrees are unchanged. The broad rule was discarded.
- A narrower experiment splits only a reused register whose old value was stored and whose
  memory location is subsequently read. This leaves raytrace unchanged and enables nbody's
  cross-group velocity forwarding; see compiler.optimization.104. It does not establish a
  general normalization policy for arbitrary arithmetic temporaries.
- Next: attribute the extra floating interference and improve residency before expanding
  eligibility beyond a concrete store-to-load forwarding opportunity. Recheck the deblock
  consumer and raytrace alongside any broader rule; do not infer a win from renaming alone.
- Complete when: independent webs expose the intended hoisting and forwarding without
  worsening the affected hot paths through additional transfers or spill traffic.
- Related: compiler.optimization.015, compiler.optimization.104.

### compiler.optimization.039 — Two test functions still sit at the sweep budget

- Recorded: 2026-09-16 12:12
- Updated: 2026-09-30 16:42 — Recorded the sweep distribution in both configurations; one chain fixed, two test functions remain at 20 and 24 sweeps.
- Area: compiler/backend, compilation time
- Evidence: the pre-RA optimization loop sweeps at most twenty-four times, and a function that
  still changes on the last sweep stops the build. A temporary counter, final unchanged sweep
  included, over `bin/std` with six workers: the release build runs the loop 30,944 times with a
  median of 3 sweeps and a maximum of 15 (`Slice.predictIntraPlane`, `Pixel.Webp.vp8Reconstruct`);
  the DevMode configuration reaches 14 (`Core.Base64.digitValue`). The release test builds go
  further: `expectedCountOnes16` of `std/core` needs 20 sweeps, and one `#test` body of 404
  instructions needs 24, which is the budget itself. One more link in its chain stops the build.
- Already taken: the pre-RA address forward rewrote one reader of a `lea` per run, so an unrolled
  sixteen-trip copy (`ScalingLists.setDefaults` and `setDefaultMatrix` of the HEVC decoder) took
  20 sweeps. It now rewrites every reader on the straight line in one run, and the reduced case
  settles in 8 with the same final code.
- Next: trace which pass still advances one link per sweep in `expectedCountOnes16` (sixteen
  unrolled copies of a bit count) and in the 24-sweep test body, and make it finish its chain in
  one run, as the induction-variable pass and the address forward now do.
- Complete when: no function of `bin/std`, tests included, needs more than sixteen sweeps in
  either configuration, or the chain that does is identified and bounded.
- Related: compiler.optimization.029, compiler.core.004.

### compiler.optimization.103 — The CABAC significance loop reloads two pointers at its latch

- Recorded: 2026-09-29 18:46
- Area: compiler/backend, post-allocation reload placement
- Evidence: the 4x4 luma significance loop of `Slice.residualCabac` spends 33 Micro instructions
  on a no-hit iteration, against about 23 in FFmpeg's `decode_significance_x86`. Since the
  interval allocator joins a copy with its source where both hold the same value
  (`coalesceSameValueCopies`), the renormalizing shifts write the loop-carried range and offset
  directly; what remains on that path is two frame reloads at the loop latch, the slice and the
  significance-state pointer (`rax = [rsp + 0x2B0]`, `r12 = [rsp + 0x2E8]`). The refill path and
  the hit path both reuse those registers, so the reloads would have to move to the end of each
  of those cold regions, past two joins, which `sinkFrameReloadToFallthrough` does not reach.
- Tried and reverted: after allocation, sinking a frame reload that stands just after a join into
  the fallthrough edges of the predecessor regions that clobbered its register, planned with a
  forward must-analysis of "register equals slot" across up to four planted reloads. Both latch
  reloads stayed (the slice pointer arrives as a copy of the register that was stored, which the
  analysis does not follow; why the state pointer failed was not diagnosed), while csvagg's main
  grew by 14 instructions and leven's by 4.
- Next: follow register copies in the must-analysis, diagnose the state pointer, and sink a latch
  reload into every cold predecessor region that clobbers its register, across nested joins.
- Complete when: the no-hit significance iteration reloads nothing at its latch and no decoder
  function or benchmark program grows.
- Related: std.video.001, compiler.optimization.037

### compiler.optimization.034 — Keep Dijkstra heap values across stores and branches

- Recorded: 2026-09-07 10:46
- Updated: 2026-09-29 17:22 — Measured the alias-proof upper bound with explicit local pointers.
- Area: compiler/backend, memory optimization
- Found while: the generated-code campaign, comparing Dijkstra's heap loops with current
  clang-cl and MSVC output at `8d3f0498b` on 2026-09-07.
- Evidence: after local identical-target load forwarding, Swag release's sift-up loop has
  26 instructions / 15 explicit memory operations, against clang-cl's 16 / eight and MSVC's
  15 / eight. Five Swag accesses reload global pointer cells; ten access heap elements,
  including the values read again after the comparison branch. These are program-memory
  accesses, not allocator spill slots. The sift-down loop still has 39 / 20.
- Current static comparison: in the Release `push` sift-up loop, Swag executes 19 Micro
  instructions and 12 explicit memory operations on a swapping iteration, versus 15 instructions
  and eight memory operations in the accepted winner's MSVC object. Swag reloads `g_HeapD` and
  `g_HeapN` after stores through those pointers; MSVC retains both pointer values in registers.
  Swag's `pop` and its inlined copy now place their address calculation and relocated heap-size
  load at the back edge, removing one executed unconditional jump per sift-down step. These
  current counts supersede the September 7 loop counts above; they are static code evidence,
  not a timing claim. The Dijkstra checksum remains `4431000`.
- A scratch source copy loads `g_HeapD` and `g_HeapN` once into local pointers at `push` entry.
  Its Release `push` shrinks from 32 to 28 Micro instructions, and the inlined `main` from
  439 to 435. A swapping sift-up step then executes 15 instructions and eight memory operations,
  matching MSVC's counts; `CHECK=4431000` remains exact. This is an upper bound for a compiler
  rule, since caching a raw global pointer would change a program whose pointee aliases the
  pointer's global cell. `benchAlloc` returns fresh allocator storage for this task, but Micro
  has no provenance proof from that return through the global assignment and call to `push`.
- Boundary: the local forwarding cache is flushed by control flow and potentially aliasing
  stores. Reusing a global pointer across an arbitrary heap write needs a provenance proof;
  keeping the heap elements already read by a comparison needs control-flow-aware memory
  availability. An exact relocation identity alone proves neither.
- Next: establish which heap stores cannot reach the global pointer cells, and propagate a
  compared element only along paths with no intervening aliasing write. Preserve the global
  reload when a pointer can address that global, and exercise both branch outcomes, calls,
  and zero-trip loops. Check `pop` and register pressure across every benchmark task before
  broadening the alias analysis.
- Complete when: the remaining repeated pointer/element reads disappear with sound alias and
  control-flow proofs, or a focused experiment identifies the register-residency constraint.

### compiler.optimization.102 — Retain one floating zero across unrolled arms

- Recorded: 2026-09-29 15:48
- Updated: 2026-09-29 16:02 — Reject branched-body renaming without zero reuse.
- Area: compiler/backend, value numbering and register allocation
- Evidence: the accepted raytrace winner is C++/MSVC. Its unrolled four-sphere `intersect` clears
  XMM5 once and compares each discriminant against that retained zero. Swag's corresponding
  205-instruction function clears XMM9 immediately before each of the four comparisons, adding
  three executed zeroing instructions to this path. Both implementations fully unroll the sphere
  loop, so loop rotation is not the missing mechanism.
- A scratch source copy named the zero explicitly before the loop; Release `intersect` remained
  205 instructions with four clears. A scratch value-numbering trial admitted `ClearReg` on virtual
  floating registers to share dominating definitions, with a C++ dominance test. It also left
  `intersect` at 205 instructions with four clears, and left `trace` and `main` at 172 and 136.
  The trial was reverted because it made no generated-code improvement; no runtime timing was
  taken. The full unroller renames private temporaries only when its body has no internal labels;
  `intersect` has conditional branches and `continue`, so the copies reuse the original virtual
  zero register. Value numbering requires the earlier result still held in its register, which
  each copy has overwritten before the next clear.
- A second scratch trial renamed private virtual values in a branched unrolled body only when
  each had one definition dominating all in-body uses and no outside reader. On its own it made
  `intersect` 209 instructions, up four, with all four clears intact. Combining it with the
  `ClearReg` value-numbering change also produced 209 instructions and four clears. The wider
  renaming perturbed XMM allocation and inserted extra copies; no executed path improved. Both
  trial edits were reverted without timing or broad correctness tests.
- Next: inspect a control-flow-aware way to split a private zero definition across cloned arms. A candidate should
  retain a single zero only where that saves executed clears without adding copies, spills, or
  saved registers. Compare an unrelated unrolled floating loop and a case with intervening calls
  before changing general value numbering or allocation.
- Complete when the repeated clears disappear with no new spill traffic in `intersect`, an
  unrelated case improves under the same rule, and native/JIT behavior remains correct.

### compiler.optimization.083 — Retain the probe mask without increasing spills

- Recorded: 2026-09-26 12:46
- Updated: 2026-09-29 15:37 — Inspect csvagg's executed hash and digit loops.
- Area: compiler/backend, LICM and register allocation
- Evidence: LDC retains wordfreq's `ByteMap.mask` in a callee-saved register across `memcmp`, while Swag reads `[m+mask]` during each collision step. Running LICM before instruction combine and allowing every invariant structure-field load across a read-only call moved that read out of the loop, but `mapProbe` grew from 81 to 98 instructions. The frame grew from `0x28` to `0x98`, the length and mask values spilled and reloaded, and an extra return tail appeared. The broad trial was reverted. A retained mask is only a gain if allocation keeps the loop's other live values resident too; one fewer memory operand in the collision step is insufficient evidence on its own. No timing was used.
- Repeating the early-LICM schedule after `mapProbe` was inlined into wordfreq's two token-finalization loops did not retain the mask: the resulting `main` still reads `[m+mask]` three times, stays at 451 instructions, and `qsort` grows from 132 to 133. The checksum remains 130489. This schedule trial was reverted without using timing.
- With the subsequent caller-test threading, wordfreq `main` was 443 instructions. Its first inlined probe still read `[rbx+0xC8]` for the initial hash mask and again for each collision step; LDC held that mask in `r10` across `memcmp`, saving and restoring it around the call. The Swag collision step retained the extra memory operand, while the checksum remained 130489. This was a code comparison, not a new LICM trial.
- Post-allocation loop rotation now recognizes the exit label after any run of adjacent labels following the back edge. It duplicates the `used[idx]` comparison at the collision tail and removes the unconditional jump: the first wordfreq collision path falls from seven to six runtime instructions, with three memory operands still versus LDC's two. The two inlined probes add two compares and two labels in total, so `main` rises from 443 to 447 static Micro instructions. The entry comparison remains on the cold entry path, and neither allocation nor spills change. All seven task checksums pass with `--validate-micro`; the other six selected function counts are unchanged. A C++ regression covers adjacent exit aliases and an intervening instruction. This closes .091; the mask load remains this entry's gap. No timing sample informed the decision.
- The accepted campaign `20260928-051818` named C++/clang-cl as wordfreq's fastest other runtime; the newer `20260929-105508` campaign names it again. Its inlined probe uses `and esi, 3FFFh` at collision, followed by the `used` and length tests: six instructions and two memory operands. A scratch-only trial marked `mapInit` inline; it exposed the constant `0x3FFF` to Swag, but enlarged `main` from 447 to 516 Micro instructions and reintroduced stack reloads and a back-edge jump in the collision loop. The checksum was 130489; the trial was rejected on static code quality, without timing.
- A post-allocation rule now moves a folded bitwise memory operand into an already saved, idle persistent register. It replaces the same address's straight-line entry read with a load and register operation, then rewrites every matching use in the loop. Eligibility requires a stable base, no loop memory writes, only direct calls annotated `ReadOnly`, and a register that is dead from the entry read through the loop. In wordfreq's first inlined probe, `r15` carries the mask across `memcmp`: the hot collision path remains six instructions and falls from three memory operands to two, matching the winner's counts. The entry still reads the mask once; it gains one encoded instruction but no memory access, while the frame and spill traffic stay unchanged. Thus `main` rises from 447 to 448 static Micro instructions. The final-token probe is unchanged because its entry read uses a different base expression. All seven task checksums pass under `--validate-micro`, and the other six selected function counts are unchanged. C++ tests cover an unrelated OR/XOR loop, a writable call, a memory write, a changing base, no prior read, a live scratch register, and no saved register. This is static evidence, not a measured runtime gain.
- Csvagg's newly accepted winner is Zig, which encodes the 64-slot probe mask as an immediate.
  A scratch-only `#[Swag.Inline]` on `mapInit` also exposes `0x3F` to Swag, but enlarges the
  Release `main` from 1,003 to 1,015 Micro instructions. The collision path gains register
  copies, two frame reloads, and unconditional jumps after key-length mismatch; it loses the
  conditional back edge that the preceding rotation established. This repeats the earlier
  wordfreq failure: exposing one constant by inlining the whole allocator-heavy initializer
  worsens the hot loop. The trial was rejected on static code quality without timing.
- A scratch-only post-RA refinement crossed the allocator spill stores at `[rsp+0x838]` and
  `[rsp+0x840]` before csvagg's probe loop, identified `rbx` as the local base despite a
  temporary `rcx = rsp` and the return-tail `pop rbx`, and kept the mask in the already saved
  `r15`. The collision step fell from three to two memory operations, but the entry mask
  operation grew from one instruction to two. The benchmark's eight region names hash to
  distinct slots modulo 64 (`21, 36, 16, 32, 12, 31, 14, 5`), so its collision step never
  executes; every lookup pays the extra entry instruction with no collision saving. The
  csvagg checksum remained 24828641 and the six other task checksums passed. The refinement
  was rejected on this executed-path evidence without a timing sample; no compiler rule was
  retained from the trial.
- The Release hash loop already reads four key bytes per iteration through the partial indexed-read
  unroller. Manually grouping four reads in a scratch source copy preserves checksum 24828641 but
  grows `main` from 1,003 to 1,007 Micro instructions, adding four address calculations before
  the grouped loop. This does not close a hot-path gap. The quantity and integer-price scans
  already reuse the delimiter-tested byte in the digit calculation. Their dynamic starting index,
  delimiter branch, and accumulator updates do not fit the current indexed-read unroller's
  zero-based, branch-free body; Zig's extra four-byte grouping applies to the two-digit fractional
  scan and needs its own setup and scalar tail. No compiler edit was retained from these probes.
- Next: compare wordfreq's complete probe paths and measure its retained mask at a clean paired
  campaign milestone. For csvagg, compare the successful `memcmp` and occupied-slot update with
  Zig's executed path; focus on register and frame traffic rather than its absent collisions.
- Complete when: a focused rule retains the mask without increasing spill traffic and improves paired wordfreq runs, or measurements show that retaining it is not profitable and this lead is retired.

### compiler.optimization.098 — Feed adjacent array updates from a packed state

- Recorded: 2026-09-29 08:04
- Updated: 2026-09-29 10:25 — Archived the full milestone campaign under machine drift.
- Area: compiler/backend, SIMD dataflow and memory aliasing
- Evidence: after ChaCha's packed round loop, Swag stores four vectors to the local state array, then emits 16 repetitions of a scalar state load, an add from the initial array, and an indexed XOR into the output array: four vector stores and 48 scalar Micro instructions per output block. The latest accepted campaign names C++/clang-cl as the fastest other runtime. Its emitted code packs one four-word slice for a vector add, XOR, and store while updating the remaining words individually. This identifies an output path left scalar after Swag's round vectorization, not a measured cost for a compiler edit.
- Mechanism: `InstructionCombine::tryMemoryFoldTriple` folds each scalar load/XOR/store into `OpBinaryMemReg` before SLP runs. A bounded four-word-store filter now defers the 32-bit XOR fold until SLP has checked the block, then the cleanup loop folds any residual scalar triples. In a scratch function with an incoming output pointer and a stack-resident four-word input, SLP emits one vector load of the input, one splat, add, vector load of the output, XOR, and vector store: seven operations instead of twelve scalar load/add/memory-XOR operations. An unrelated four-store case with different add constants retains its four memory XOR instructions and 36-function-instruction count; two overlapping parameter pointers also stay scalar and preserve sequential results. A global suppression without cleanup had grown an earlier scalar case from 30 to 38 instructions and was removed.
- Constraint: packing several output updates changes when later state and initial elements are read relative to earlier output writes. The output comes from `benchAlloc`, a wrapper around the runtime allocator; the current Micro pass does not carry a freshness or no-alias proof from that call. A rewrite based only on adjacent addresses could change programs whose output overlaps an input array.
- Further inspection: each source iteration has one indexed read-modify-write; the existing loop unroller makes sixteen adjacent instances, which `tryMemoryFoldAmcTriple` folds before SLP. SLP rejects every indexed read and write as unresolved, and its root proof recognizes stack and incoming-parameter disjointness but gives allocator returns an unknown root. Extending only the earlier four-store deferral therefore cannot vectorize this loop. A new path needs both a proof across the unrolled iterations and either a documented fresh-allocation contract or a checked overlap fallback.
- Validation: native Release and DevMode tests for the packed and overlapping cases, JIT Release, 1,156 C++ tests, and all seven benchmark checksums pass. The selected functions of all seven benchmarks have unchanged normalized Micro instructions, including ChaCha's 51-instruction packed round and 457-instruction main. No individual runtime timing informed the decision.
- Milestone: the full campaign `20260929-082219` passed every checksum but was archived under `bench/results/rejected/`. Its reference workload moved 65.9% between neighbouring probes (40% limit), and unchanged build controls spread by 30.7% (25% limit). Other compiler builds and test suites were active on the shared machine during the sweep. The accepted baseline and runtime winners remain `20260928-170009`; no speedup or regression is inferred from the rejected timings.
- Next: establish the allocator result's usable provenance and the exact stack/heap disjointness contract, or guard the overlap case at run time. Extend the deferral and SLP proof to four indexed output updates only when their stable base and adjacent offsets are known. Test overlapping and disjoint indexed arrays, then compare the output path's instructions, memory operations, and spills with clang-cl. Keep the benchmark's computation unchanged.

### compiler.optimization.097 — Keep a short loop step on the advancing edge beyond a cold-block size limit

- Recorded: 2026-09-28 16:35
- Updated: 2026-09-29 07:16 — Recorded the next accepted full campaign and its revised runtime winners.
- Area: compiler/backend, post-allocation loop layout
- Audit: `placeShortLoopStep` searched only 80 Micro instructions ahead for the step label. That distance did not participate in the branch or register proof; it excluded otherwise identical loops with a longer cold arm. A label-to-ordinal map now resolves the target in constant expected time and allows the same structural rewrite at any distance. The test covers a 96-instruction cold arm, the original short arm, and a non-unit step that must remain unchanged.
- Evidence: the long-arm case removes one executed unconditional jump from its advancing path without adding an instruction there. All seven benchmark tasks retain their selected function counts and checksums, so this batch has no claimed benchmark gain. C++ (1,156), native Release (3,483), and JIT Release (1,500) pass.
- Milestone: the full campaign `20260928-153255` was archived under `bench/results/rejected/`: every task and runtime passed its checksum, but the reference workload moved 101.8% between neighbouring probes (40% limit). Its build-control spread was 10.7%. No runtime conclusion comes from that run. The later `20260928-170009` campaign passed every checksum with 10.48% reference spread and 2.7% build-control spread. It is the latest accepted full campaign; its per-task winners are in `repo.prompts.md`.
- Follow-up: a partial execution-only sweep of wordfreq and raytrace passed every runtime checksum and had 24.1% worst reference departure, but individual runtime samples varied by more than 900% in several cases. The partial sweep recorded nothing and cannot establish a runtime change.
- Next: at the next full campaign milestone, inspect any larger ordinary loop newly reached by this layout rule and check its hot and cold branch balance before closing this lead.


### compiler.optimization.095 — Keep loop values off the stack on the common branch

- Recorded: 2026-09-28 14:04
- Updated: 2026-09-28 15:18 — Move the index spill store to the cold branch and remove the loop-latch store.
- Area: compiler/backend, path-sensitive spill placement
- Evidence: In wordfreq's character scan, the alphabetic path reaches a join where `r12` still holds the index, while token processing may reuse `r12`. The interval allocator had put the reload from `[rsp+0x210]` at that join, so every alphabetic character read the index from the stack. A post-allocation rule now moves the reload to the join's fallthrough edge only when every direct jump into the join can trace the same register value back to a matching frame store or reload without an intervening register definition, memory write, or call. It rejects a cyclic proof through the reload being moved. The common path loses one memory read; `main` grows from 448 to 450 static Micro instructions because subsequent branch layout changes, with no new instruction on that path. The checksum remains 130489; the other six benchmark checksums and selected function counts are unchanged. C++ (1,154), native Release (3,483), and JIT Release (1,500) tests pass. No timing sample was taken for this edit.
- A second post-allocation rule now moves a private spill store to the cold branch that dominates its sole read. It checks every explicit access to the eight-byte slot, rejects overlapping or indexed accesses, proves that the register still equals the slot on every incoming path, and tracks balanced stack-pointer adjustments along paths to the read. It removes later writes only when the new store lies on every route to the read. It applies only when at least one redundant write is removed: wordfreq's header and latch stores become one cold-entry store. The common alphabetic path now avoids the header store, join reload, and latch store, while `main` has 448 static Micro instructions and checksum 130489. A wider version moved a store in Leven without removing another write and raised its `main` from 474 to 478 instructions; the narrower rule restores 474 and checksum 67441. The other five benchmark checksums and selected function counts are unchanged. C++ (1,155), native Release (3,483), and JIT Release (1,500) tests pass with the final rule, as do all seven benchmark checksums. No timing sample was taken for this edit.
- The bound reload is placed the same way: once on the cold edge before the join and once after loop exit.
- Next: obtain a clean paired measurement at a campaign milestone.
- Complete when: the common character path has no index or bound spill traffic without adding costs to the token-processing path or changing JIT/native behavior; otherwise retain only the proven reload placement.

### compiler.optimization.092 — Reuse one relocation base for indexed constant arrays

- Recorded: 2026-09-28 09:14
- Updated: 2026-09-28 10:42 — Separate address materialization from the AVX memory-fold tradeoff.
- Area: compiler/backend, constant-address relocation and indexed loads
- Evidence: In the latest accepted full campaign (`20260928-051818`), raytrace's fastest other runtime is C++/MSVC (9.601 ms versus Swag's 10.742 ms; ratio 1.119). Its `trace` function materializes one image base with `lea rdi, [__ImageBase]` and reads eight distinct constant arrays through indexed memory operands. Swag's Release Micro for the same function uses eight `LoadRegPtrReloc` instructions followed by eight indexed loads, four for `SRAD`/`SCX`/`SCY`/`SCZ` and four for `SR`/`SG`/`SB`/`SRE`: 16 instructions for those reads versus MSVC's nine. This is an instruction and address-dependency gap, not a timing claim about an edit.
- A post-allocation rewrite that keeps the first array pointer and adds source-address differences to later loads is invalid for native artifacts: `NativeRDataCollector` emits only reachable allocations and may compact the gaps between them. JIT constants are resolved from shard and offset at patch time. Each indexed consumer therefore needs a relocation relative to a reusable segment or image base, or an equivalent layout contract that survives both backends. The existing emitter binds only RIP-relative scalar accesses, not indexed displacements.
- The native linker already understands `IMAGE_REL_AMD64_ADDR32NB` as an image-relative `Rva32` relocation, but code emission has no base-relative indexed relocation form, and the internal linker does not expose `__ImageBase` as a code symbol. The JIT's 2 GiB proximity arena can host code and constant shards together; its exhaustion fallback needs an explicit range or copy strategy for any base-relative displacement. In `trace`, the transient pointer register is clobbered by the intervening `intersect` call, so reusing that register alone yields at most two four-array groups. One base across both groups requires an allocation and callee-save decision.
- Folding a scalar indexed load into each floating operation is not an independent instruction saving here. Swag's load plus AVX three-register `fsub`/`fmul` is two encoded instructions; MSVC's copy plus memory-form SSE operation is also two in the corresponding `SCX`/`SCY`/`SCZ` and colour paths. The existing post-RA fold requires the destination to hold the left operand because the memory-form SSE instruction overwrites it. Adding a copy to force that fold would leave the instruction count unchanged and add a copy dependency.
- A separate check of `trace`'s missing `refl > 0` branch found no correctness defect: all four benchmark reflectivities are positive. A scratch function with a variable float retained both tests and produced `0,1,0` for negative, positive, and depth-limited inputs; changing one reflectivity to a negative value in an external source copy restored the floating compare in `trace`.
- Next: design and validate a relocation-aware indexed displacement against one reusable base in JIT and native output. Compare eight-array code with MSVC; include unrelated arrays in different allocations and shards, a library artifact, and a negative case whose address cannot share the base. Account for register lifetime across the intervening call and JIT arena exhaustion before selecting the base.
- Complete when: indexed reads of separate immutable arrays reuse one base without relying on source allocation spacing, pass JIT/native relocation checks, and close the eight-materialization gap without extra spills.

### compiler.optimization.093 — Keep unsigned 64-bit float conversion branchless in hot loops

- Recorded: 2026-09-28 09:31
- Area: compiler/codegen, integer-to-float conversion
- Evidence: The latest accepted campaign names C++/MSVC as csvagg's fastest other runtime (17.340 ms versus Swag's 18.304 ms; ratio 1.056). MSVC lowers each `u64` to `f64` price conversion with a signed conversion on the common lower half and a shift/or/double fallback for values with the high bit set. Swag instead uses a branchless packed low/high-32-bit conversion with two vector constants. Both have five instructions on the common path, but the operations and register pressure differ.
- A scratch compiler change used MSVC's general signed-fast-path formula. The 15 native boundary cases and a new JIT boundary case passed; 200,000 pseudo-random values and neighborhoods of powers of two agreed with the existing conversion. Csvagg's checksum stayed 24828641; all six other task checksums and selected function sizes were unchanged. The complete native Release suite passed 3,483 tests, JIT Release passed 1,501, and scripts passed.
- The emitted csvagg `main` grew from 993 to 1,022 Micro instructions. Its XMM saves fell from five to three and the saved area from `0x50` to `0x30`, but the timed row loop still had 13 frame operands and gained eight static jumps (34 to 42). Each common conversion still executed five instructions, now including a conditional and an unconditional jump. The two saves are paid once; the extra branches run for every row. This is a concrete hot-loop code-quality loss, so the trial and its JIT-only test were reverted without timing.
- Next: find a range proof that a conversion input stays below `2^63`, or a branchless lowering that uses fewer operations and less XMM pressure than the current packed conversion. Compare both sides of the range and an unrelated cast before revisiting the lowering.
- Complete when: a general rule improves the complete hot conversion path without extra branches or spills, and preserves full-range nearest-even results in native and JIT output; otherwise retain the current branchless algorithm.

### compiler.optimization.074 — Eliminate the caller's redundant used-slot test after an inlined probe

- Recorded: 2026-09-25 23:43
- Updated: 2026-09-28 00:30 — Thread the inlined probe's proven empty and occupied return paths.
- Area: compiler/backend, post-allocation branch threading and private-frame load elimination
- Evidence: In both wordfreq token-finalization paths, the inlined probe returns an index, then the caller loads the `used` pointer from its private frame, tests the indexed byte, branches if occupied, and loads the same pointer into the same physical register again on the empty fallthrough before storing. A guarded post-allocation rule removes that second load only when the base is the compiler-identified private stack base, the intervening operations are one read-only indexed compare and conditional jump, and both pointer loads have identical width and address. Wordfreq's `main` falls from 456 to 454 Micro instructions. Csvagg's `main` remains at 1,001; neither hash/collision loop changes. Both programs pass `--validate-micro` with checksums 130489 and 24828641. A C++ regression covers a private frame, a nonprivate base, and a different reload address. All 1,128 C++, 3,480 native, and 1,500 JIT tests pass. No elapsed-time sample informed the decision.
- Before branch threading, the loop-guided wrapper rule inlined both `mapProbe` call sites in wordfreq `main`, which grew from 327 to 451 optimized Micro instructions. Both paths still tested the `used[idx]` byte after the inlined probe's empty-slot exit; the probe could also return an occupied matching key after `memcmp`, so deleting the second test required a proof over the predecessor paths. The checksum was 130489. The other six benchmark tasks kept their optimized function counts and checksums. No timing sample informed that change.
- The post-allocation loop-layout pass now proves the indexed byte's zero/nonzero state backward along every incoming edge of the two adjacent return labels. It stops at a memory write, an address-register definition, an unannotated call, an unsupported edge, or a cycle; direct `ReadOnly` calls preserve the fact. It also keeps a label when an indirect jump targets it, since that jump cannot be retargeted here. Proven direct incoming jumps go straight to the caller's empty or occupied arm, and the repeated compare and branch disappear. Both wordfreq token-finalization paths make this change: `main` falls from 451 to 443 instructions, and an occupied key found by `memcmp` now branches directly to the value increment. LDC's winning `main` also follows its successful `memcmp` with a collision branch and a direct value increment, without a second `used` comparison. Csvagg's corresponding row path falls from 996 to 993 instructions; Odin's winner similarly goes straight from successful `memcmp` to its occupied update. The collision loop has no extra hot-path instruction. Checksums remain 130489 and 24828641 with `--validate-micro`; the other five tasks retain their selected function counts and checksums. A C++ regression covers both branch directions, a writable call, an intervening memory write, an index change, a different cell, and an indirect incoming jump. All 1,149 C++, 3,483 native Release, and 1,500 JIT Release tests pass. No timing sample informed the change.
- Next: recheck a full accepted benchmark campaign when the shared machine stays quiet.
- Complete when: broad validation and a clean full campaign confirm the generated-code gain without a runtime regression; retire the entry if no further path gap remains.

### compiler.optimization.055 — Keep both quicksort global pointers resident across comparator calls

- Recorded: 2026-09-25 11:15
- Updated: 2026-09-28 00:16 — Reject a call-aware value-numbering trial after hot-loop spill growth.
- Area: compiler/backend, loop-invariant code motion and call effects
- Evidence: LDC keeps `g_Idx` and `g_Cnt` pointers outside wordfreq's inner quicksort comparisons; Swag previously reloaded them from RIP-relative globals each turn. An earlier LICM experiment using `SymbolFunction::isPure()` did not help because the bodyless `Swag.memcmp` declaration was not pure; increasing the purity budget and recognizing `Swag.vecmask` also left it impure. A `ReadOnly` call contract now explicitly promises no caller-visible writes and survives module API export. LICM uses that contract only for direct 64-bit global loads. The resulting `qsort` initially grew from 126 to 134 instructions because it spilled hoisted pointers. The allocator then proved to reserve a whole persistent register for legalization solely because `mayNeedLegalizeScratchRegister` reported `true` for a zero-operand `ret` (its only reported instruction in `qsort`). Correcting that answer lets the allocation use `r15` and removes two instructions: the first comparator loop drops from 10 instructions and 5 memory operands per unequal-count iteration to 9 and 4, and the second from 9 and 4 to 8 and 3. The full function has 132 instructions. An experiment admitting the preferred local-stack-base register to the interval pool alone changed no emitted instructions and was reverted. The wordfreq checksum remains 130489. Csvagg's 1,076-instruction `main`, 271-instruction row span, and checksum 24828641 remain unchanged. The 1,107 C++, 3,480 native, and 1,500 JIT tests pass. No timing sample informed the decision.
- Current evidence: the new loop-guided wrapper rule inlines both `less` calls in `qsort`. Its optimized body grows from 72 to 132 Micro instructions, while each unequal-count comparison now reads the retained `g_Idx` and `g_Cnt` pointers without a `less` call or a global reload. The tie path still calls `memcmp`, and the second comparator loop reloads both global pointers on entry. LDC also retains its pointers during the unequal-count loop and reloads after a call. Wordfreq's checksum is 130489; csvagg's selected function counts and checksum are unchanged. No timing sample informed the rule.
- A value-numbering trial preserved mutable global loads across a direct `ReadOnly` call. It removed four instructions from `qsort` as a whole (132 to 128), including a repeated global pointer load after `memcmp`, and kept checksum 130489. The extra live value changed allocation in the first comparator loop: each increment path acquired a stack reload of the count pointer and an unconditional back-edge jump. That hot-path regression outweighed the colder tie-path saving, so the trial was reverted without timing it. A direct-call regression test for this trial was reverted with the rule.
- Next: compare the full tie path and post-call pointer recovery against LDC, then use paired runs when machine load permits to determine whether remaining reloads warrant a focused allocation change.
- Complete when: both pointers remain resident through the comparator calls without extra spill traffic and checksums remain correct, or the current dump shows this gap has already closed and the entry is retired.

### compiler.optimization.089 — Mixed scalar calls slow down with six independent argument lanes

- Recorded: 2026-09-27 08:13
- Updated: 2026-09-27 21:13 — Retained the mixed-call measurement gate after changing float lanes
- Area: compiler/backend, Swag calling convention and register allocation
- Evidence: with the independent six-integer/six-float Swag argument banks, a release
  executable making 20 million no-inline calls with alternating six `u64` and six `f64`
  parameters takes about 61–64 ms after warmup, versus 34–36 ms with the prior
  positional convention on this machine. Both return the same value. Six-integer calls
  improve from roughly 37–41 ms to 31–33 ms over 40 million calls; six-float calls stay
  near 59–62 ms. These are process-wall microbenchmarks, not application measurements.
  With the same twelve-parameter signature but an integer-only body, the candidate
  improves to roughly 22–25 ms from 26–30 ms; with a floating-only body, it takes
  56–60 ms against 26–30 ms. Full-width XMM copies, pruning unused XMM saves,
  making XMM6/XMM7 volatile, and reducing Swag's float bank to three registers
  did not close the mixed-case gap in local experiments. The last result suggests
  that register count alone does not explain the slow floating body.
- The post-RA Micro dump for the floating-only body has a 17-instruction leaf
  callee under the old ABI, with three floating adds reading stack operands.
  The candidate has 25 instructions after dead-code elimination: five register
  floating adds plus a prologue and epilogue that save XMM6 and XMM7. Its first
  floating register copy is removed after the save plan is made. A temporary
  late save-pruning experiment still measured around 58 ms, so the saved-register
  instructions alone do not explain the entire gap.
- An experimental mapping that kept six independent integer lanes but assigned
  floating arguments by their position in the full signature measured roughly
  37–42 ms on the mixed sum, close to the old 39–42 ms in the same run. It gives
  up independent floating lanes for mixed signatures, so it was not selected as
  the new Swag convention.
- The preceding candidate used the already persistent XMM6–XMM11 as floating argument
  lanes. Pre-prologue dead-definition elimination avoids saving unused persistent
  registers; a property-based loop pass hoists invariant persistent-argument copies.
  In five alternating call-matrix pairs, six-integer calls are about 10% faster,
  six-float calls about 16% faster, and alternating six/eight mixed calls remain
  about 3% slower than the preceding ABI. These backend passes apply by convention
  properties and remain useful even if the Swag ABI changes again.
- The transient XMM0–XMM5 experiment removes two per-pixel row reloads from raytrace's
  inner loop and reduces its `main` and `trace` from 155/201 to 136/173 optimized Micro
  instructions. All seven benchmark checksums remain unchanged; the six other tasks
  retain their instruction counts. C++ (1,147), native Release
  and DevMode (3,483 each), JIT Release (1,500), and workspace Release pass with the
  cache identity advanced to build 1173. The old persistent-argument copy hoist became
  unreachable and was removed. No elapsed-time sample informed the choice.
- Next: compare the mixed-call signatures and the seven tasks in a paired campaign with
  the new float bank; isolate any signature or task that regresses before closing this entry.
- Complete when: repeated paired runs put the mixed calls at parity or better and
  the six-integer and six-float gains remain.

### compiler.optimization.085 — Measure short-key comparison cost against LDC

- Recorded: 2026-09-26 13:10
- Updated: 2026-09-27 17:44 — Retain the unmeasured short-key performance comparison after the completed runtime change.
- Area: generated runtime code, wordfreq byte-map keys and comparators
- Evidence: wordfreq and LDC both call `memcmp` for variable-length keys of 3–8 bytes. Swag's runtime fallback scanned the sub-eight-byte tail one byte per loop iteration; a matching three-byte key therefore repeated two byte loads, a comparison, an increment, and a loop branch three times. The fallback now compares four-, two-, and one-byte chunks without reading past `size`, and uses the lowest set bit of a nonzero XOR (or the first clear SIMD equality bit) to return the exact first unsigned byte difference. The whole `memcmp` body grows from 96 to 115 optimized Micro instructions, but the frequently used short equal-key path has no byte loop; a three-byte key needs one two-byte comparison and one byte comparison. `mapProbe`, `qsort`, and wordfreq main remain 81/72/328 instructions, and the checksum remains 130489 with `--validate-micro`. The new native test checks every mismatch position in sizes 1–64 with unaligned inputs and both operand orders. Its five focused tests pass in Release and DevMode; the 3,481-test native Release, 1,500-test JIT Release, and focused core memory suites pass. No elapsed-time sample informed the decision.
- Next: compare the issued short-key path against the C runtime used by LDC and recheck the wordfreq ratio only after further static gains, since the larger generic fallback alone does not establish a benchmark speedup.
- Complete when: final short-key code and repeated paired wordfreq measurements establish competitive cost, or isolate a reproducible remaining gap whose implementation can be specified here.

### compiler.optimization.045 — Branch simplification is a quarter of the backend, and every new pattern taxes every function

- Recorded: 2026-09-23 09:25
- Updated: 2026-09-25 11:16 — Ruled out cumulative graph invalidation gating under variable machine load.
- Area: compiler/backend, compilation time
- Evidence: instrumented Release 0.1.1035 on `swc build -w bin/std -bc release --rebuild
  --num-cores 6`. The micro pipeline spends 65.3 s of worker CPU over 33,062 functions;
  branch simplification alone is 16.2 s of it, **24.8%**, across 72,546 runs of which 38.6%
  rewrite something. The next pass is register allocation at 11.3%, then instruction combine
  at 7.9%. A six-worker stack profile of the same build puts the pass at 12.9% of busy CPU,
  spread over some twenty sub-transforms none of which reaches 1.5% — there is no hot spot,
  only a battery of scans.
- How it got there: the cold release rebuild of the big modules slowed by half in one week at
  unchanged sources. Paired, order-alternated rebuilds give gui 12.3 s → 18.4 s and pixel
  6.5 s → 11.1 s between 0.1.684 (2026-09-16) and 0.1.1035 (2026-09-21), while gui's sources
  moved from 105,315 to 105,483 lines. Bisecting the same measurement puts 0.1.823
  (2026-09-17 01:33) still at the old speed and 0.1.885 (2026-09-17 13:29) already at the new
  one — the window that added some fifty narrowing, diamond and short-circuit patterns.
- Taken in 0.1.1046: seven transforms opened on the same walk of the function and ten more
  rebuilt the same jump-target counts and relocation set; one shared walk now serves a run and
  is dropped when a transform rewrites the stream. Single-core, alternated: core 0.97, pixel
  0.93, gui 0.95, video 0.92, seven of eight pairs favourable. `buildProgramLayout` fell from
  1.67% to 0.73% of busy CPU.
- What remains: the pass still runs about thirty-seven transforms, and each one scans the whole
  function looking for a shape most functions do not hold. The cost is therefore the number of
  patterns times the size of every function compiled, which is why a pattern campaign shows up
  as a compile-time regression with no single culprit.
- Measured, and the obvious gate is not worth it: instrumenting the pass over the same rebuild,
  38 592 runs land on a function holding no conditional jump at all and cost 2.42 s of the pass's
  33.1 s — **7.3%**, about 0.9% of the compilation. Gating them would also have to spare the
  structural loop, which threads unconditional jump chains and erases unreachable code in exactly
  those functions, so the reachable share is smaller still. Do not spend a gate on it.
- What the same probe does say: a run on a 28-instruction branchless function still costs 63 us,
  against 485 us for a 126-instruction branchy one. The pass has a large **fixed** cost per run —
  entering some thirty-seven transforms, each with its own scratch containers — that does not
  scale with the function. That, not the scanning, is what a pattern campaign multiplies.
- Where the fixed cost was (timed per transform, 0.1.1047): fourteen transforms opened by asking
  for the next free virtual integer register index, which walks every instruction and collects
  every register operand, and then used it only when the transform actually rewrote something;
  the short-circuit coalescer opened with a use/def query per instruction and a pair of ordinal
  lists per register, read only after three filters had matched. Collecting both on first request
  took the pass from 16.7 s to 9.1 s of summed worker time over a bin/std release rebuild.
- The same shape again, taken in 0.1.1048: `areCpuFlagsDeadAfterInCfg` mapped an instruction
  reference back to its graph index with a linear search of the graph's instruction list, and
  eleven sites ask it once per candidate they examine - quadratic in the function.
  `MicroControlFlowGraph::indexOf` now answers from a table built on first request.
- Ranking at 0.1.1048, as a share of the pass: `fuseMaterializedBoolBranches` 10.6%, rebuilding
  SSA through `MicroSsaState::ensureFor` 10.3%, `convertEqualityChainsToBitTests` 9.9%,
  `convertGuardedSelectDiamonds` 8.9% (which rebuilds SSA of its own), `coalesceShortCircuitResults`
  7.2%, and a tail of thirty-odd transforms under 4% each. The measured quadratic and virtual-register
  prologues were removed; what remains is the cost of asking thirty-seven questions about every function.
- Taken in 0.1.1136: equality-chain bit tests, packed switches, three-way signs and repeated memory
  compares had each built a hash set from the same relocation list. They now share one index while
  the instruction stream is unchanged and rebuild it after a rewrite. A run without rewrites makes
  one relocation walk instead of four; the transforms consult the same instruction references as
  before. Four focused native Release tests and one rotating JIT test passed. Five order-alternated
  pairs against the same master source gave candidate/baseline wall and CPU ratios of 0.836/0.763
  for core rebuild, 0.968/0.969 for core touch and 0.860/0.955 for hello build; the no-op guardrail
  stayed below 100 ms. Rebuild times drifted from 1.8 to 3.4 s during the run, so this is a
  correctness-certified structural saving, below the measurement floor rather than a claimed
  percentage speedup. Peak working-set ratios were 0.992, 1.000 and 0.983 for those three builds.
- Taken in 0.1.1138: `coalesceShortCircuitResults` and `threadShortCircuitExits` each rebuilt the
  program layout in every short-circuit round. They now use the same layout when coalescing makes
  no change, and rebuild it when coalescing rewrites the stream. This removes one full instruction
  walk from each unchanged round, with no change to either transformation. The prior profile put
  all `buildProgramLayout` calls at 0.73% of busy CPU, so this is expected below the whole-build
  timing floor. The focused `short_circuit_booleans` and `short_circuit_past_join` native Release
  tests passed; the rotating `std/core` TweakFile file ran four passing tests. On the rebased master,
  five order-alternated pairs gave candidate/baseline core-touch ratios of 1.013 wall and 0.989
  CPU. Hello-build ratios of 1.126 wall and 1.150 CPU reversed in a second seven-pair run with
  A/B roles swapped: 0.995 wall and 0.857 CPU. The series therefore supports no percentage claim.
  Peak working-set ratios were 1.014 for core touch and 1.034 for hello build in the five-pair run.
- Ruled out on 2026-09-24: recording whether each function has `SetCondReg` in the shared branch
  scan and using it to skip the equality-chain, branchless-or and three-way-sign transforms when
  none exists. This requires one extra opcode comparison per instruction in every branch scan.
  The three focused native Release tests and a rotating JIT test passed, but five alternated pairs
  measured candidate/baseline at 1.090 wall and 1.030 CPU for core rebuild, and 1.144 wall and
  1.190 CPU for hello build. Peak working-set ratios were 1.010 and 0.993. An earlier sweep was
  discarded when unrelated machine load stretched one rebuild to 29.5 s. The completed sweep still
  shows the always-paid scan cost outweighing the scans avoided here; the gate was reverted.
- Taken in 0.1.1140: the early unused-label sweep reused the pass's relocation-reference index
  instead of walking the same relocation list and allocating another hash set. A run without
  rewrites now builds this index once for the early sweep and the later equality-chain, packed-switch,
  three-way-sign and repeated-memory-compare transforms. The index is invalidated after a rewrite.
  The focused native Release branch-simplification and packed-switch files passed, as did four
  tests in the rotating JIT `defer.catch` file. Three order-alternated pairs against the same
  master source gave candidate/baseline core-rebuild ratios of 0.985 wall, 0.944 CPU and 1.005
  peak working set. Hello-build ratios of 1.198 wall and 1.244 CPU reversed in a seven-pair run
  with A/B roles swapped: baseline/candidate 0.999 wall and 1.036 CPU. Other attempted pairs
  were discarded when shared-machine load stretched individual builds to 26-35 seconds. The
  saving is therefore below the measurement floor, with no percentage speedup claim or stable
  memory regression.
- Ruled out on 2026-09-24: returning an unusable diamond scan when its existing label-reference
  map is empty. This skips the diamond transform family for functions with no direct jumps,
  without adding an opcode check to the instruction walk. Two focused native Release tests and
  the rotating JIT `move_value_expression` file (15 tests) passed. Five alternated pairs gave
  candidate/baseline ratios of 1.058 wall and 1.044 CPU for core rebuild, and 1.041 wall and
  1.038 CPU for hello build; peak working-set ratios were 0.998 and 1.014. A reverse series
  became unusable when unrelated load stretched a baseline rebuild to 42.8 seconds. With no
  observed gain and a possible guardrail regression, the gate was reverted.
- Final validation on 2026-09-24: the Release campaign passed 1,500 JIT tests and 3,478 native
  tests, then stopped in `std/gui` on the pre-existing semantic error described in
  a semantic error in `std/gui`, since fixed by preserving the source view of generated `is`
  casts. The pre-campaign compiler build 1131 reproduced that error on unchanged GUI sources.
  A final five-run four-workload timing attempt was stopped after three runs:
  unrelated machine load moved a core rebuild from 4.8 to 7.3 seconds and a touched-file
  build from 3.0 to 9.2 seconds. These samples support no final percentage speedup claim.
- A final three-pair, order-alternated comparison of build 1131 with build 1140 on the same
  checkout measured final/initial ratios of 1.035 wall, 1.051 CPU and 1.010 peak working set
  for core rebuild; hello build measured 1.005 wall, 1.000 CPU and 1.011 peak working set.
  Several other compiler changes landed between those versions, and the shared machine drifted
  during the campaign. This end-to-end comparison neither proves a speedup nor attributes the
  small slowdown to one batch. The remaining distance to the subsecond core target is large.
- A separate final three-run check of build 1140 gave a warm no-op median of 78.1 ms
  (all three runs below the 100 ms guardrail) and a touched-file median of 3,241.7 ms.
  In the paired comparison above, the final compiler's core-rebuild median was 4,890.1 ms
  and hello-build median was 244.0 ms. These are noisy three-run observations, not the
  five-run quiet-machine baseline required for a stable target claim.
- Ruled out on 2026-09-25: tracking changes since the last graph invalidation instead of using
  the pass-wide `changed` flag at each synchronization point. A Release 1142 core profile put
  `MicroBranchSimplifyPass::run` at 10.27% and `MicroControlFlowGraph::build` at 3.35% of
  sampled worker CPU, so the predicted whole-build saving was below 1%. The Release 1143 trial
  passed two focused native files and a randomly drawn JIT file (12 tests), but five loaded
  A/B pairs gave `core_rebuild` candidate/baseline ratios of 1.249 wall and 1.234 CPU, while
  `core_touch` gave 0.808 wall and 0.872 CPU. A follow-up candidate core rebuild took 39.7 and
  39.9 seconds, yet the restored baseline also took 49.5 seconds during the complete Release
  suite. Five A/A pairs of byte-identical binaries gave 1.000 wall and 1.044 CPU, with individual
  builds between 2.7 and 5.8 seconds. The evidence does not isolate the candidate from shared
  machine load or establish a repeatable benefit. The change and version bump were reverted;
  The [campaign summary](../bench/results/compilation/20260925-speed/README.md) records the outcome.
- Taken on 2026-09-26 under prompt 4: the existing program-layout scan now also records whether
  any label exists. The branch pass skips jump-threading, immediate-label, inverted-jump, CFG
  reachability and unused-label sweeps when their required label is absent; it skips the diamond
  family when the current layout has no conditional jump. Each guard uses already collected layout
  state and falls back to the original path after a rewrite. Focused native Release tests passed,
  as did the full 3,480 native and 1,500 JIT test suites. Five order-alternated four-workload pairs
  against the earlier campaign binary were too variable for a speedup claim: candidate medians were
  2,366 ms core rebuild, 53 ms no-op, 2,571 ms core touch and 144 ms hello; baseline medians were
  2,299, 41, 2,224 and 129 ms. The full Release campaign reached the known `std/gui` semantic
  error in `std/gui`, since fixed by preserving generated `is` cast source views; the
  pre-campaign master compiler also reproduced it.
- A second prompt-4 group on the merged master uses that same layout to skip range-check,
  range-and, branch-to-cmov and repeated-memory-compare scans when their required conditional
  jump or setcc is absent. The 3,480 native and 1,500 JIT Release tests passed. A five-pair A/B
  sweep was disrupted by shared load: core rebuilds grew from about 2 to 5-7 seconds during it.
  Candidate/baseline medians were 2,067/2,082 ms for core rebuild, 44/49 ms for no-op,
  1,830/1,929 ms for core touch and 126/120 ms for hello. This supports no percentage claim.
- A third prompt-4 group skips rich branch-reference scans for float selects, equality chains and
  packed switches when their required opcodes are absent. It also skips implied-branch label maps
  without an immediate compare and stores each label's reference count and jump position in one
  map instead of two. Focused tests, 3,480 native and 1,500 JIT Release tests passed. Five paired
  core rebuild medians were 3,151 ms candidate and 2,996 ms baseline under variable load; hello
  medians were 167 and 189 ms, but a seven-pair role-reversed hello series gave 181 and 187 ms
  with slightly higher candidate CPU. No speedup percentage is established. The full Release
  campaign again reached the pre-existing `std/gui` error in `compiler.core.058`.
- A fourth prompt-4 group skips settled register-allocation sweeps after checking for remaining
  virtual operands, defers implied-branch and jump-chain cycle sets, builds packed-switch jump
  counts only for qualifying chains, delays range-check used-set work until the opcode shape
  matches, and constructs short-circuit scratch maps only on paths that use them. Focused Release
  tests passed; after merging master `f196225e0`, 3,481 native and 1,500 JIT tests passed. The
  full Release campaign compiled `std/gui` and stopped in `std/video` because
  `Slice.predictIntraPlane` still changed after 24 pre-RA sweeps. The unmodified master compiler
  at `f196225e0` reproduced that exact failure with a video rebuild. Five order-alternated
  four-workload pairs against that master gave candidate/baseline medians of 3,357/3,426 ms
  core rebuild, 89/65 ms no-op, 2,734/2,576 ms core touch, and 245/242 ms hello. One touch
  took 35 seconds and one no-op 1.55 seconds under shared load; these samples establish no
  speedup percentage or stable regression.
- A fifth prompt-4 group defers the short-circuit fallthrough-label map and boolean-guard
  claimed-reference set, skips two diamond reference scans without a conditional jump, and uses
  existing layout flags to skip range and boolean-threading scans without their required
  immediate compare or setcc. Focused tests, 3,481 native and 1,500 JIT Release tests passed,
  including after merging master `0308e681d`. Five order-alternated pairs against the preceding
  integrated master `43766f77f` gave candidate/baseline medians of 2,269/2,304 ms core rebuild,
  46/57 ms no-op, 2,460/1,904 ms core touch and 152/145 ms hello. Paired rebuild and touch
  ratios were near one, individual touch runs ranged from 1.8 to 4.0 seconds, and the samples
  establish no percentage speedup. A fresh `std/video` rebuild still stops at the 24-sweep
  `Slice.predictIntraPlane` error; compiler `01e0d9e59`, before both recent master changes and
  these two prompt-4 groups, reproduces the same error.
- The 2026-09-28 prompt-4 continuation reuses the current branch scan's register-mention counts
  in short-circuit and range-AND folding, avoiding their separate whole-function counts when no
  preceding rewrite invalidated the scan. OR-chain and packed-switch candidate maps also reuse
  buckets within a run. Focused Release checks and the full 3,483 native and 1,500 JIT suites
  passed; elapsed time, CPU, and retained-memory effects remain unmeasured.
- Next: two of the five now pay for an SSA rebuild, which is compiler.optimization.029's subject
  rather than this entry's. For this entry, the remaining lever is structural — running the
  pattern battery once on the converged IR instead of in every sweep of the pre-RA loop, the way
  `lateBranchSimplifyPass_` already does for three transforms. That changes what the optimizer
  produces, so it needs the benchmark, not just a compile-time measurement.
- Complete when: adding a pattern no longer adds a full function scan to every run, or the pass
  drops below 15% of micro-pipeline CPU on the `bin/std` release rebuild.
- Related: compiler.optimization.029, compiler.optimization.039.

### compiler.optimization.054 — Prove contiguous indexed updates before packing them

- Recorded: 2026-09-24 23:10
- Updated: 2026-09-24 23:42 — Confirmed the SLP memory-effect guard leaves ChaCha's 48/48 output loop unchanged.
- Area: compiler/backend, SLP vectorization and indexed memory
- Evidence: after folding ChaCha's output address into each XOR, its unrolled
  16-word update has 48 micro instructions and 48 explicit memory operations.
  Clang-cl and MSVC also use scalar indexed read-modify-write operations there.
  `Pass.SlpVectorize.cpp` seeds groups only from plain aligned 32-bit stores at
  known root offsets. Indexed read-modify-write operations lack a fixed offset;
  treating them as invisible to the block scan could move packed stores across
  an alias, so the current pass rejects such blocks.
- Next: seek an unrelated four-lane loop with one stable base and index and
  constant offsets, then prototype a proof that the four indexed updates are
  adjacent, do not alias intervening accesses, and retain their source values.
  Compare per-loop instruction and memory counts against scalar code from both
  C++ compilers before adding a vector rewrite. Include an aliasing counterexample
  and a case where packing costs more than the scalar memory instructions.
- Complete when: either a profitable general rule and its alias tests are in
  place, or measurements show that scalar indexed updates are the better form.

### compiler.optimization.046 — A local array copied whole stays in memory, and scalarizing the copy costs the vectorizer

- Recorded: 2026-09-23 19:51
- Area: compiler/backend, mem2reg, vectorization
- Evidence: mem2reg promotes a local array's elements once its 16-byte zero fill is split into one
  store per element (build 1069). A whole-object copy - `var state = initial` in
  `bench/src/swag/chacha.swg` - is the other vector access such an array sees, and it keeps both
  arrays in memory: the copy puts a B128 access on each element of both, and the width-disagreement
  rule admits a disagreeing read but not a write.
  Splitting that copy element by element was implemented and measured: ChaCha20's state does become
  register-resident and its scalar quarter-round works in registers, but the release build goes from
  **206 to 348 instructions** because scalarizing the vector traffic destroys the SLP vectorization
  of the rounds. That is the same trade `keepAccessScalar` exists to prevent, and disabling that
  guard outright was measured separately at **52 vector operations to 0 and chacha 2.1x slower**.
  Two smaller obstacles were also identified and are real: the zero fill and the copy each
  disqualify the other's uniformity test, and lowering reuses one vector temporary across all four
  chunks of a copy, so a "no other use in the function" test never holds.
- Next: decide the shape before touching this again. Promotion and vectorization want opposite
  things here, so a split is only correct when the object is not a vectorization candidate -
  which the fill-only rule already approximates by requiring no other B128 access on the window.
  A cost model that compares the promoted scalar form against the vectorized one is the honest
  version, and it does not exist.
- Complete when: either a rule promotes a whole-copied local array without costing vectorization,
  or this records that the two cannot be reconciled and the fill-only rule is the end of it.

### compiler.optimization.029 — The pre-RA optimization loop rebuilds SSA after every mutating pass

- Recorded: 2026-09-05 22:13
- Updated: 2026-09-23 13:07 — Took the structural half; the entry keeps the rebuild count.
- Area: compiler/backend, compilation time
- Evidence: `MicroPassManager::runPass` invalidates the shared SSA state whenever a pass sets
  `passChanged`, and `MicroSsaState::ensureFor` rebuilds it before the next query. Instrumented on
  2026-09-16 (Release 0.1.687), one `swc build -w bin/std -m gui -bc release` builds SSA **78,072
  times** over 9,521,265 instruction slots. **33,923** of those builds follow a pass mutation,
  attributed as: copy elimination 13,827, instruction combine 9,717, value numbering 4,383,
  constant folding 3,645, pre-RA peephole 1,990, branch simplification 355, strength reduction 7.
  The remaining 44,149 are each loop entry's first build and are not avoidable this way.
- What it is worth: a single-core profile of that build puts `MicroSsaState::build` at **5.65% of
  the work**. Pass-mutation invalidations are 43.5% of the builds, so removing *every* one of them
  bounds the gain at **about 2.5% of a gui release build**. The incremental use/def cache already
  took the cheap part of a rebuild; what is left is dominance, phi placement and the rename walk.
- The largest single redundancy: `MicroCopyEliminationPass::run` invalidates and rebuilds SSA in
  the middle of itself, so that `eraseDeadCopies` can ask `isRegUsedAfter`. It did so **10,497**
  times in that build - 13.4% of every SSA build in the module - after a rewrite that moved reads
  between registers and changed no definition, no instruction and no edge. The pass knows exactly
  which uses it redirected, so it can answer "does this copy's destination still have a reader"
  from that record instead of rebuilding. Worth about 0.8% of the build on its own.
- Constant folding, the case this entry used to name, is 11% of the invalidations. Its bounded
  rewrite - an isolated virtual-integer `OpBinaryRegImm` folded into `LoadRegImm`, which keeps the
  instruction reference, the definition and the CFG and only drops a read - is still the clearest
  shape for a mutation contract, but it is not where the rebuilds are.
- Experiment (2026-09-16): two local liveness replacements removed the internal rebuild: a
  scan of reaching uses, then instruction-use counts adjusted for each redirected operand with
  backward phi propagation. Both passed 825 C++ tests, including three new loop, dead-phi and
  physical-source cases. The first also preserved all 16 final Micro functions in the Levenshtein
  and ChaCha probes and passed the 29 optimizer-native cases. A broader native run found the
  unchanged baseline failure subsequently fixed by `69f480e61`.
- Measurement: three alternating, six-worker Release gui rebuild pairs, pinned to six P cores,
  gave baseline/candidate total process CPU of 232.938/233.938 seconds for the count variant.
  Median wall time was 18.571/18.046 seconds, with individual runs spanning 16.114-21.722 seconds;
  that spread does not establish a gain. Both implementations were discarded from the branch.
- 2026-09-23 (Release 0.1.1046): `MicroSsaState::build` is **7.05% of busy CPU** on a
  six-worker `bin/std` release rebuild, 300,712 builds for 33,062 functions — nine per
  function. Inside it: the rename walk 2.4%, phi placement 1.4%, the collection walk 1.6%,
  dominators 0.4%. The passes that pay for a rebuild are constant folding 2.1%, copy
  elimination 1.1%, instruction combine 1.0%, value numbering 1.0%, guarded-select diamonds
  0.9%, branch simplification 0.7%. Constant folding now spends three times as long
  rebuilding SSA as it spends folding.
- Taken in 0.1.1049, and it did read above the floor: a rebuild no longer rediscovers the basic
  blocks, the dominator tree and the frontiers. All three describe the control-flow graph alone,
  and the graph now carries a build identity taken fresh whenever it is rebuilt, so the SSA state
  keeps what it derived for as long as that identity holds - which is exactly as long as no pass
  invalidated the graph. Only the phi lists, which belong to the definitions, are recomputed.
  Single-core, alternated: gui 0.914 against the same rebuild before the morning's four batches.
- What is left of this entry is its original subject: the *number* of rebuilds, still about nine
  per function. Each one still pays for the collection walk, phi placement and the rename walk,
  which together are the 7% this entry measures. The 2026-09-16 experiment on copy elimination's
  internal rebuild remains discarded; revisit it only with the rename walk, not around it.
- The 2026-09-28 prompt-4 continuation removed redundant dominator-buffer clearing, reused
  visit stamps for frontier construction, and deferred construction of standalone SSA state
  where the pass receives shared SSA. These reduce per-pass setup and work inside rebuilds;
  they do not reduce the rebuild count. Focused Release checks and the full 3,483 native and 1,500
  JIT suites passed. No timing or peak-memory measurement was made in this campaign.
- The SLP vectorizer now constructs its standalone SSA fallback only when a block has a viable
  packed plan and asks for SSA. Blocks rejected earlier no longer initialize the fallback state;
  a supplied shared SSA state is used as before. The Release `slp_vectorize` file passed 17 native
  tests, followed by 3,483 native and 1,500 JIT tests. Timing was not measured.
- The SSA value fixed point now retains existing value entries across passes and resets only their
  validity flags. Every value read checks its flag, and successful inference overwrites its entry
  before setting that flag. This removes one full value-array fill per constant-folding, copy-
  elimination or branch-simplification run when scratch storage is reused. The Release optimizer
  selection passed 241 native tests; timing and peak memory were not measured.
- Complete when: a replacement preserves emitted code and focused SSA/native behavior and
  resolves a repeatable compilation-time gain against the roughly 3% measurement floor.
- Related: compiler.core.004, compiler.core.030, compiler.optimization.039.

### compiler.optimization.032 — Partially unroll the SHA-256 compression rounds

- Recorded: 2026-09-06 14:53
- Updated: 2026-09-14 06:25 — Account for temporary renaming already shipped in the full unroller.
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
  trips; merely raising that limit is a different experiment.
- Current boundary: since `1238a3c2e`, the full unroller gives independent temporaries fresh
  names in cloned straight-line bodies. Values read before their first write, read outside the
  body, or constrained by allocation keep their names; bodies with internal labels also keep
  them. `native/optimizer/unroll_renames_temporaries.swg` covers carried and escaping values.
  This is neither partial unrolling nor a solution for the compression round's carried state.
- Next: rebaseline the compression round, trace which carried-state values acquire extra frame
  accesses in a partial-unroll prototype, and evaluate coalescing of those values. Reuse the
  full unroller's temporary-renaming rules instead of treating all cloned names as unchanged.
  Compare every hot loop across the seven tasks, with counter, exit, relocation, and carried-value
  regression coverage if a prototype improves the emitted code.
- Complete when: grouping rounds lowers both instructions and frame traffic per compression round
  with correctness coverage, or the remaining register-residency prerequisite is isolated.
- Related: compiler.optimization.005, compiler.optimization.016.

### compiler.optimization.022 — An inlined by-value aggregate argument is copied even when the body only reads it

- Recorded: 2026-08-28 15:42
- Updated: 2026-09-14 06:25 — Identify the remaining indexed and foreach aggregate home requirement.
- Area: compiler/sema
- Found while: giving `Core.Math.Simd` its 4x4 and 8x8 transposes (2026-08-28).
- Evidence: `func transpose4x4(rows: [4] U32x4)->[4] U32x4` inlined into a caller that already
  holds the block still emitted four 128-bit loads and four stores copying the argument into a
  fresh frame slot, then read every row back out of that copy, around the eight interleaves that
  are the whole operation: 40 instructions and a 0x1C8 frame for eight instructions of work. The
  same body taking `rows: *[4] U32x4` in place compiles to 28 instructions and a 0x80 frame, which
  is what the API now does. `materializeInlineBindings` binds a by-value aggregate argument to a
  concrete local. The current `classifyInlineBinding` already examines parameter uses and can
  keep a direct binding; an indexed or foreach by-value aggregate still requires a home through
  `use.indexOrFor`, even if those uses only read. Read-only syntax alone does not establish that
  the caller's storage remains unchanged while the inlined body executes.
- Next: in `SemaInline`, measure the homes still required by indexed/foreach aggregate uses.
  Elide a copy only when the caller's storage remains unchanged through all reads, including
  indirect calls and alias writes, and when copy/drop hooks and argument evaluation retain their
  semantics. Absence of a direct assignment to the parameter is not sufficient.
- Complete when: a proven stable, side-effect-free by-value aggregate parameter costs no copy
  after inlining, written or indirectly mutable storage still preserves value semantics, and the value-returning shape of a block transform is as cheap as the in-place
  one on the video corpus.

### compiler.optimization.037 — Hoisting a constant-pool read out of a loop is undone by rematerialization

- Recorded: 2026-09-12 20:30
- Evidence: loop-invariant motion refuses to hoist a memory read when the loop writes through a
  pointer, and it applies that refusal before it looks at the address. A filter kernel reads its
  coefficients from the constant pool on every iteration and writes its result through a pointer,
  so its coefficient reads never leave the loop. Relaxing the refusal for a read whose base is the
  instruction pointer and whose relocation is `ConstantAddress` is sound, since nothing writes the
  constant pool, and it did hoist them: the sixteen-pixel body of the H.264 horizontal half-sample
  filter went from 39 instructions to 36, its two coefficient loads moving to the preheader.
- What it cost elsewhere: `intraPredict8x8` grew from 927 instructions to 1078 and from 340 memory
  operands to 445 under the same change alone. The hoist gives one definition many uses spread
  across the function, the allocator then refuses it a register, and the rematerialization recipe
  for a constant-pool read remakes the read at every one of those uses. The hoist therefore
  produces more reads than it removed. The change was reverted; build 520 is the number it used.
- Next: make rematerialization weigh where it remakes a value. A value remade inside a loop is
  remade once per iteration, and LLVM's spiller prices a remake by the block frequency of the use
  for exactly this reason. Once a remake inside a loop is no longer free, hoist the constant-pool
  read again and measure both kernels.
- Complete when: the filter kernel keeps its coefficients in registers across its loop and no
  other decoder kernel grows.
- Related: cpu.simd.035, compiler.optimization.006

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

### compiler.optimization.024 — The split allocator claims a whole instruction for an implicit operand

- Recorded: 2026-08-29 15:41
- Updated: 2026-09-05 16:27 — git: Add unit tests for TaskProvider in providers.test.js
- Area: compiler/backend
- State: the interval-splitting linear scan of Wimmer & Mössenböck (VEE 2005, the allocator
  of HotSpot's client compiler) is what every optimizing build allocates with. `-O0` keeps
  the earlier scan, which also remains the fallback whenever a precondition fails or the
  walk bails, and the C++ conformity cases run both.
- The 2026-09-28 prompt-4 continuation replaced fill-copy construction of fresh value and
  fixed-claim interval arrays with direct default construction. The call sites pass empty
  vectors, so each interval starts with the same fields while no empty `LiveInterval` is
  copied for every register. The Release `interval` selection passed two native tests; timing
  and peak memory were not measured.
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

