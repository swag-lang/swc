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

### compiler.optimization.084 — Rebase an indexed load on a related address

- Recorded: 2026-09-26 12:47
- Area: compiler/backend, indexed address folding
- Evidence: MSVC `/O2` computes Dijkstra's child index `2*i+1` once per `pop` iteration. Swag computed both `2*i` and `2*i+1`, then addressed the same child through `[heap + (2*i)*8 + 8]`. Instruction combine now recognizes two address definitions with identical reaching source values and scale, and replaces a single-use index with the related index plus an adjusted displacement. The dead `lea` drops out in the cleanup sweep. Dijkstra's `pop` falls from 49 to 48 Micro instructions and `__main_0` from 436 to 435; the inner `pop` loop has one fewer instruction and no extra memory access. Its checksum remains 4431000 with `--validate-micro`. Wordfreq `mapProbe`/`qsort`/main remain 81/72/328, raytrace `trace`/`intersect` remain 183/206, ChaCha main remains 431, and CSV main remains 1000. All 1,138 C++ tests and the independently drawn six native Release pointer-arithmetic tests pass. The focused C++ test accepts equivalent source values and rejects a source redefinition. No runtime timing informed the decision.
- Next: compare Dijkstra's remaining heap-loop memory accesses against MSVC's pointer residency without assuming that an arbitrary heap pointer cannot alias a global.

### compiler.optimization.083 — Hoisting a probe mask before load folding increases spills

- Recorded: 2026-09-26 12:46
- Area: compiler/backend, LICM and register allocation
- Evidence: LDC retains wordfreq's `ByteMap.mask` in a callee-saved register across `memcmp`, while Swag reads `[m+mask]` during each collision step. Running LICM before instruction combine and allowing every invariant structure-field load across a read-only call moved that read out of the loop, but `mapProbe` grew from 81 to 98 instructions. The frame grew from `0x28` to `0x98`, the length and mask values spilled and reloaded, and an extra return tail appeared. The broad trial was reverted. A retained mask is only a gain if allocation keeps the loop's other live values resident too; one fewer memory operand in the collision step is insufficient evidence on its own. No timing was used.
- Next: find a register-pressure-aware way to retain the mask, then compare the complete hash and collision loops and the call frame against LDC.

### compiler.optimization.082 — Rotate packed 32-bit words by 16 with two shuffles

- Recorded: 2026-09-26 12:00
- Area: compiler/backend, SLP vectorization and x64 encoding
- Evidence: ChaCha's vectorized round loop rotated four 32-bit words by 16 using a packed left shift, right shift, and OR. `pshuflw` swaps the two 16-bit words in the lower half, and `pshufhw` does the same in the upper half, so the two instructions perform the same four rotations. The SLP plan now selects the shuffles for rotation by 16; the x64 encoder and its byte-level tests cover both forms. The final ChaCha main falls from 433 to 431 pre-emit Micro instructions, removing two instructions on every ten-round iteration without adding memory traffic. Disassembly confirms two `pshuflw`/`pshufhw` pairs, and `--validate-micro` preserves checksum 633277775. All 1,136 C++, 3,480 native Release, and 1,500 JIT Release tests pass. No runtime timing informed the decision.
- Next: compare ChaCha's scalar output and checksum loops with clang-cl's issued instructions, then move to the next largest unexhausted gap.

### compiler.optimization.081 — Price memory intrinsics as possible calls when auto-inlining

- Recorded: 2026-09-26 11:47
- Area: compiler/parser, automatic inlining cost
- Evidence: `Swag.memcmp` is an `IntrinsicCallExpr`, so the parse-time body scan treated wordfreq's `mapProbe` as a call-free leaf. Its runtime-sized comparison emits a call. Inlining the probe at two call sites duplicated its hash and collision loops and spilled the caller's byte index across the whole tokenization loop. The cost scan now counts the four memory intrinsics that can lower to runtime calls. Wordfreq's main falls from 452 to 328 pre-emit Micro instructions, with no per-byte index spill/reload on the loop backedge; its `mapProbe` remains an 81-instruction out-of-line function. This matches LDC's out-of-line probe and register-resident token index more closely. The checksum remains 130489 with `--validate-micro`. A C++ regression asserts that a repeatedly called memory-intrinsic wrapper is recognized as containing a possible call and is not auto-inlined. All 1,136 C++, 3,480 native Release, and 1,500 JIT Release tests pass. No runtime timing informed the decision.
- Next: compare wordfreq's remaining per-character branch and `mapProbe` hash loop with LDC, then inspect the next benchmark's excess operations.

### compiler.optimization.080 — Add a doubled value with one scaled address

- Recorded: 2026-09-26 11:35
- Area: compiler/backend, post-allocation integer address folding
- Evidence: Odin forms raytrace's `ir + 2 * ig` with one `lea` in the pixel loop. Swag first formed `2 * ig` in a temporary register, then added it to `ir`. A post-allocation rule rewrites the adjacent pair to `lea dst, [dst + source * 2]` only when the temporary is dead, the widths match, the encoder accepts the address, and no later instruction needs the original `add` flags. Raytrace's `__main_0` falls from 139 to 138 post-emit Micro instructions, with one fewer instruction on every pixel iteration and unchanged memory references. The checksum remains 56061776 with `--validate-micro`. All 1,136 C++ and 1,500 JIT Release tests pass; the independently drawn native Release `float_literal_rounding.swg` passes 2 tests. The focused C++ test accepts a dead temporary and refuses a later temporary read, live flags, or another scale. No runtime timing informed the decision.
- Next: compare raytrace's remaining pixel and `trace` dependency chains against Odin, then inspect wordfreq's tokenization path against LDC.

### compiler.optimization.079 — Share identical floating-register return tails

- Recorded: 2026-09-26 11:26
- Area: compiler/backend, final return layout
- Evidence: Odin's raytrace `trace` uses one XMM restore and stack-release epilogue. Swag emitted the same ten XMM restores, stack release, three pops, and return twice. The final Micro pass now shares return tails only when every restore, offset, width, stack adjustment, and pop matches. The early return jumps to the later tail, leaving the hot hit path as fallthrough. `trace` falls from 196 to 183 post-emit Micro instructions; direct stack reads fall from 21 to 11. Its checksum remains 56061776 with `--validate-micro`. C++ coverage checks an identical pair and refuses a different restore offset. All 1,135 C++, 3,480 native Release, and 1,500 JIT Release tests pass, as does the independently drawn native `return_conversion_storage.swg` test. No runtime timing informed the decision.
- Negative lead: After the prior spill-reload forwarding, the store at `[rsp+0xF0]` appeared unread. Erasing it under an allocator-spill-range and direct-access scan reduced `trace` from 196 to 195 instructions with the same checksum, but a guard for intermediate stack-pointer adjustments blocked that deletion before final frame sanitation. The scan did not prove aliases across all stack-pointer states, so the store-erasure experiment was reverted. The earlier read elimination remains.
- Next: compare raytrace's remaining `trace` call setup and pixel accumulation against Odin. Revisit dead spill stores only after final stack layout or with a CFG-aware stack-address proof.

### compiler.optimization.078 — Produce converted colors in their selected registers

- Recorded: 2026-09-26 10:12
- Updated: 2026-09-26 10:55 — Removed one stack reload from raytrace's `trace` path.
- Area: compiler/backend, post-allocation conversion and comparison forwarding
- Evidence: Odin's raytrace pixel loop converts each color directly into the integer register it later clamps, while Swag copied all three converted values to separate registers before comparing them. A post-allocation rule now retargets a float-to-integer conversion and its sole later comparison to the copy destination when the original register is dead after that comparison. It proves the intervening instructions, encoder legality, and physical liveness on the current Micro stream. The three copies disappear: `__main_0` falls from 142 to 139 post-emit Micro instructions, with 35 stack/RIP memory references unchanged. The raytrace checksum remains 56061776 with `--validate-micro`. All 1,132 C++ tests pass, including a positive chain and cases with an extra source read, destination clobber, or live source; an independent native release test (`static_control.swg`) and a focused JIT/native conversion-and-clamp probe pass. No runtime timing informed the decision.
- Evidence (2026-09-26): Odin reserves its outgoing call area outside raytrace's pixel loop. A late Micro pass now moves one balanced `sub rsp`/`add rsp` pair from a contiguous natural loop to its single entry and exit, after proving the loop's CFG edges, stack-pointer uses, one-call balance, and flag liveness. In raytrace the pair moves outside the pixel loop, removing two instructions from every pixel iteration without changing the function's total instruction count. The `--validate-micro` raytrace checksum remains 56061776. All 1,133 C++, 3,480 native Release, and 1,500 JIT Release tests pass; the scripts campaign also passes. A C++ test covers the nested-loop hoist, an external stack use, and an early exit. No runtime timing informed the decision.
- Evidence (2026-09-26): Immediately before raytrace's second `intersect` call, Swag stored a scalar XMM value to `[rsp+0xF0]`, replaced its source register, then reloaded the same slot into a persistent XMM register. Odin kept that value in a register. A post-allocation rule for this adjacent store/copy/reload sequence now copies the old value before the source overwrite and then performs the original replacement. It keeps the store for later readers. `trace` remains at 196 post-emit Micro instructions but loses one stack read; the raytrace checksum remains 56061776 with `--validate-micro`. C++ coverage includes the positive float sequence, a different stack slot, and an overlapping replacement register. No runtime timing informed the decision.
- Next: prove whether the now-unread `[rsp+0xF0]` spill store can be removed generally without weakening alias or control-flow safety, then compare the remaining `trace` hot path with Odin.

### compiler.optimization.077 — Reuse constant float sign masks across branches

- Recorded: 2026-09-26 10:01
- Area: compiler/backend, value numbering of immutable relocated operands
- Evidence: Odin computes raytrace's sphere intersections with one floating sign inversion for each sphere, while Swag repeated the same `fxor [rip]` on both root-selection paths. Value numbering now recognizes `FloatXor` with a constant-pool RIP operand as a pure expression keyed by its input value and full relocation identity. Dominance and the existing reaching-definition check permit reuse after a branch; mutable globals and different constant offsets remain distinct. `intersect` falls from 214 to 206 post-emit Micro instructions, from eight to four `fxor [rip]` operations, from 27 to 23 float-register copies, and from 44 to 40 stack/RIP memory references. The raytrace checksum remains 56061776 with `--validate-micro`. All 1,131 C++ tests pass, including new f32/f64 positive and mutable/different-mask negative cases; an independent native release test (`enum_progress.swg`) and a focused JIT/native f32/f64 branch probe pass. No runtime timing informed the decision.
- Next: compare raytrace's `trace` and pixel accumulation loops against Odin's emitted code and remove the next general instruction or memory-operation excess.

### compiler.optimization.076 — Keep local pointers across disjoint spills

- Recorded: 2026-09-26 00:47
- Updated: 2026-09-26 00:47 — Removed one csvagg row-path pointer load.
- Area: compiler/backend, post-allocation frame value forwarding
- Evidence: Csvagg's inlined table probe keeps `agg.used` in `r14`, but the caller reloaded that pointer for its indexed test. A spill store to `[rsp+offset]` between the two reads made the previous all-writes barrier decline the proof. The frame allocator exposes its private spill byte range, and the function symbol exposes each local object's extent. The backward path walk now permits only a direct store wholly inside that spill range when the earlier pointer load lies wholly inside a known local object; other stores still stop it. If the reloaded physical register is dead after the branch, the indexed compare uses the persistent register directly and the reload is erased. Csvagg's `main` falls from 1,001 to 1,000 Micro instructions and loses one memory read on the row path, matching clang-cl's retained table pointer more closely. Wordfreq stays at 452. Both programs pass `--validate-micro` and checksums 130489 and 24828641. A C++ test covers a declared local object and spill, an unknown object, and a store outside the spill area. All 1,130 C++, 3,480 native, and 1,500 JIT tests pass before integration. No millisecond reading informed the decision.
- Next: the caller still repeats `used[idx]` after the inlined probe in both programs; eliminate that test only with a path-sensitive memory fact that survives the read-only comparison call and every loop backedge.

### compiler.optimization.075 — Forward private-frame pointers through read-only branches

- Recorded: 2026-09-26 00:20
- Updated: 2026-09-26 00:20 — Removed two wordfreq probe-pointer reloads.
- Area: compiler/backend, post-allocation frame value forwarding
- Evidence: After an inlined `mapProbe`, wordfreq reloads `counts.used` from the local frame for the caller's indexed test, although the probe still holds the same pointer in a persistent register. A bounded backward walk of the instruction CFG now requires every path to reach the earlier frame load, with no register clobber or memory write in between. It permits a call only when its function is marked `Swag.ReadOnly` and the ABI preserves both the held pointer and frame base. When the indexed store after the branch is the final use of the reloaded register on either edge, it retargets the test and store and removes both loads. Wordfreq's `main` falls from 454 to 452 Micro instructions; the generated machine code uses the retained register directly. Csvagg remains at 1,001 because a frame spill between the two loads blocks this deliberately conservative proof. Both benchmark checksums remain 130489 and 24828641. The C++ test covers a valid branch join, an intervening store, a register clobber, and a path that bypasses the first load; all 1,129 C++, 3,480 native, and 1,500 JIT tests pass before integration. No millisecond reading influenced this decision.
- Next: determine whether a disjoint frame spill can be proved harmless for csvagg without weakening the call and path guards, then revisit the still-repeated `used[idx]` memory comparison at the probe/caller join.

### compiler.optimization.074 — Reuse private frame pointers after a branch

- Recorded: 2026-09-25 23:43
- Updated: 2026-09-25 23:43 — Removed two redundant `used` pointer reloads from wordfreq.
- Area: compiler/backend, post-allocation private-frame load elimination
- Evidence: In both wordfreq token-finalization paths, the inlined probe returns an index, then the caller loads the `used` pointer from its private frame, tests the indexed byte, branches if occupied, and loads the same pointer into the same physical register again on the empty fallthrough before storing. A guarded post-allocation rule removes that second load only when the base is the compiler-identified private stack base, the intervening operations are one read-only indexed compare and conditional jump, and both pointer loads have identical width and address. Wordfreq's `main` falls from 456 to 454 Micro instructions. Csvagg's `main` remains at 1,001; neither hash/collision loop changes. Both programs pass `--validate-micro` with checksums 130489 and 24828641. A C++ regression covers a private frame, a nonprivate base, and a different reload address. All 1,128 C++, 3,480 native, and 1,500 JIT tests pass. No elapsed-time sample informed the decision.
- Next: prove the inlined probe's empty/occupied result across the caller's redundant `used[idx]` test, or find a narrower path-specific branch thread that avoids additional jumps. Compare the remaining wordfreq tokenization and csvagg row path against LDC and clang-cl assembly.

### compiler.optimization.073 — Reserve call shadow once in fixed local frames

- Recorded: 2026-09-25 23:28
- Updated: 2026-09-25 23:28 — Removed repeated call-frame adjustments from wordfreq and csvagg parsing loops.
- Area: compiler/backend, final stack layout and call ABI
- Evidence: Unlike LDC and clang-cl, Swag adjusted `rsp` down and up by 40 bytes around every ordinary call from the two benchmark main functions, including their collision-loop `memcmp` calls. Each function has a frame-pointer anchor, a copied base for its local frame, and a final argument frame. A conservative final pass now reserves the 40-byte Windows x64 shadow/alignment area once immediately after the local-base copy, rebases only direct accesses proven inside that local frame, and removes only individually matched simple call pairs with no stack operand between them. It shrinks the later final argument-frame subtract by 40 bytes, restoring the exact original `rsp` before that frame is addressed; its contents and epilogue are unchanged. Wordfreq's `main` falls from 483 to 456 Micro instructions (14 pairs removed, one reserve added); csvagg's `main` falls from 1,020 to 1,001 (10 pairs removed, one reserve added). The final 144-byte argument-frame subtract becomes 104 bytes in both and encodes with a short immediate. Both programs pass `--validate-micro` with checksums 130489 and 24828641. The focused C++ regression covers re-based locals and rejects a stack argument or stack-pointer copy within a candidate call frame. All 1,127 C++, 3,480 native, and 1,500 JIT tests pass, including the native recovery probes. No elapsed-time sample informed the decision.
- Next: revisit the redundant used-slot retest after inlined `mapProbe` with a memory-safe CFG proof, and compare remaining wordfreq tokenization and csvagg row parsing operations against the competitor assembly.

### compiler.optimization.072 — Fold dead scalar increments after allocation

- Recorded: 2026-09-25 23:08
- Updated: 2026-09-25 23:08 — Matched direct memory increments in wordfreq and csvagg.
- Area: compiler/backend, post-allocation integer memory operations
- Evidence: LDC increments wordfreq's new-key count in memory, and clang-cl does the same for csvagg's new-slot count. Swag's loop-local field update was `mov reg,[base+offset]; add reg,1; mov [base+offset],reg`. A post-allocation rule now replaces this exact adjacent triple with one memory add only when load/store address and width match, the result register differs from the address base and is dead after the store, and the x64 encoder accepts the replacement. Wordfreq's generated `main` falls from 485 to 483 Micro instructions; csvagg's `main` falls from 1,022 to 1,020. Their collision/hash loops retain the same instructions. Both builds pass `--validate-micro`, and their checksums remain 130489 and 24828641. The focused C++ regression covers a dead value, a live value, an address-register overlap, and a different store address. All 1,126 C++, 3,480 native, and 1,500 JIT tests pass. No elapsed-time sample informed the decision.
- Negative lead: Allowing the pre-allocation memory-combine rule to fold frame-derived updates inside loops reduced wordfreq by two instructions but grew csvagg's `main` from 1,022 to 1,036 after register allocation. That broad trial was reverted; the post-allocation rule achieves both two-instruction gains without perturbing register assignment.
- Next: inspect the redundant used-slot retest after inlined `mapProbe` in both programs, then assess whether reserved call shadow space can be reused in the main parsing loops without moving local or outgoing argument slots.

### compiler.optimization.071 — Trim empty call frames to their ABI reserve

- Recorded: 2026-09-25 22:45
- Updated: 2026-09-25 22:45 — Removed unused local space from wordfreq's collision-probe frame.
- Area: compiler/backend, final stack-frame layout and wordfreq probing
- Evidence: Wordfreq's generated `mapProbe` retained a 136-byte frame after optimization, although its body has no surviving direct stack access; it only needs call shadow space and alignment for `memcmp`. LDC saves seven registers and reserves 32 bytes, a total of 88 bytes. Swag saves six registers and now reserves 40 bytes, also 88 in total. The paired `sub`/`add` instructions now encode with 8-bit rather than 32-bit immediates, removing six machine-code bytes per call while leaving the 81-instruction probe and its hash and collision loops unchanged. The rule requires one fixed frame, a single release/return, an actual call, no address escape or direct stack access, and preserves the original frame's alignment residue. Wordfreq's `qsort` remains at a 72-byte frame and 132 Micro instructions; csvagg's `main` remains at 1,022. Focused C++ coverage includes an empty call frame and a nonempty frame that must stay fixed. All 1,125 C++, 3,480 native, and 1,500 JIT tests pass; the independently drawn safety suite exits successfully with its expected failing cases. Both benchmarks pass `--validate-micro`, with checksums 130489 and 24828641. No elapsed-time sample informed the decision.
- Negative lead: Extending the post-allocation `ADD` plus result-copy fold across one independent instruction changed neither wordfreq's `qsort` or `main` nor csvagg's `main`. The intervening instruction in the targeted `memcmp` setup reads the old destination register, so moving the result definition earlier would be incorrect. The rule and its test were reverted.
- Next: inspect the two-pointer argument setup around `memcmp` as a scheduling and register-allocation problem, then compare csvagg's row parser and hash-mask residency with clang-cl.

### compiler.optimization.070 — Compact private spill frames after allocation

- Recorded: 2026-09-25 22:25
- Updated: 2026-09-25 22:25 — Reduced wordfreq's recursive sort frame after register allocation.
- Area: compiler/backend, stack-frame layout and wordfreq sorting
- Evidence: The final `qsort` stream used only three allocator-owned spill slots at `rsp+168`, `+176`, and `+184`, but reserved 200 bytes. LDC's corresponding sort reserves 88 bytes. A final guarded pass now moves only proven spill accesses and reduces the paired frame adjustments by the same aligned amount; `qsort` reserves 72 bytes and uses slots `rsp+40`, `+48`, and `+56`. The `sub` and `add` each encode with an 8-bit rather than 32-bit immediate, removing six machine-code bytes per function without changing the comparator loops' 115 machine instructions or their memory access count. The guard requires one fixed frame, a single return, no address escape, no physical debug stack base, and every direct stack access inside the allocator-owned spill area. An initial broader rewrite moved the stack-passed arguments of an eight-argument call and failed a native test; the spill-area guard excludes that call. The focused C++ regression covers a private spill frame, an outgoing stack argument, a lower non-spill access, an address escape, and a physical debug stack base. All 1,124 C++, 3,480 native, and 1,500 JIT tests pass; the independently drawn workspace suite passes. Wordfreq and csvagg pass `--validate-micro` with checksums 130489 and 24828641; csvagg's `main` remains at 1,022 Micro instructions. No elapsed-time sample informed the decision.
- Negative lead: Forcing csvagg's `mapInit` inline exposed the constant mask but grew `main` from 1,022 to 1,037 instructions and added row-path spills. Replacing its mask read with literal 63 grew `main` to 1,023 instructions because a two-instruction collision step became three instructions. Both source-only trials were reverted.
- Next: compare wordfreq's spill and pointer residency through `memcmp` against LDC, and csvagg's decimal parsing and existing-slot branch against clang-cl, using per-loop assembly counts.

### compiler.optimization.069 — Compare indexed float slots in memory

- Recorded: 2026-09-25 21:33
- Updated: 2026-09-25 21:33 — Matched the memory-operand comparison in csvagg's existing-slot path.
- Area: compiler/backend, x64 scalar comparison and csvagg row aggregation
- Evidence: clang-cl compares price to `slotMax[slot]` with `ucomisd xmm9, [base + index*8]`. Swag had a separate indexed load followed by `comisd xmm10, xmm0`. A guarded post-allocation rewrite now emits a new `CmpRegAmc` form only for adjacent f32/f64 loads whose loaded register dies at the compare. The x64 encoder uses the existing register-register `comis` opcode, preserving its floating-point exception behavior while reading the second operand directly from memory. The actual binary contains `comisd xmm10, qword ptr [r14 + 8*rcx]`; csvagg's generated `main` falls from 1,023 to 1,022 Micro instructions, and the row path loses the separate load. Csvagg's checksum stays 24828641. Wordfreq's `mapProbe`, `qsort`, and `main` remain at 81, 132 (115 machine instructions), and 485 Micro instructions, checksum 130489. The focused C++ test checks f32/f64 and rejects a live loaded register. All 1,123 C++, 3,480 native, and 1,500 JIT tests pass; the sema positive and expected-error suites pass. Both benchmarks pass `--validate-micro`. No elapsed-time sample informed the decision.
- Negative lead: naming one cached length across wordfreq's `memcmp` did not reduce the 115 machine instructions in `qsort`; stack accesses rose from 6 to 8 because the extra live range displaced a persistent register. Making the preferred debug stack-base register available to allocation left this code unchanged. Both experiments were reverted.
- Next: continue comparing csvagg's decimal parser and row-loop branches with clang-cl, and find a wordfreq length or pointer residency improvement that accounts for spill cost across `memcmp`.

### compiler.optimization.068 — Let count-mismatch comparisons fall through

- Recorded: 2026-09-25 21:08
- Updated: 2026-09-25 21:08 — Removed one executed back-edge jump from each wordfreq comparator advance.
- Area: compiler/backend, post-allocation loop layout and wordfreq sorting
- Evidence: In both `qsort` comparator loops, a count mismatch that advances `i` or `j` previously executed an unconditional jump back to the indexed load. LDC places the increment or decrement before the header, branches backward to it on a mismatch, then falls through to the next load. A guarded post-allocation layout rewrite now uses that shape for the one- or two-load header followed by a count comparison, equality branch, ordered exit, unit index update, and back edge. Each advancing mismatch path loses one executed jump; a one-time jump enters the header. The generated `qsort` still contains 115 machine instructions, while the Micro listing grows from 130 to 132 entries only because it includes two new zero-byte labels. The register and memory operands in both comparator loops remain unchanged. Wordfreq's `mapProbe` stays at 81 instructions and its checksum at 130489. Csvagg's `main` remains at 1,023 instructions with checksum 24828641. A C++ test covers both header lengths, increment/decrement steps, and rejection of a non-unit step. All 1,122 C++, 3,480 native, and 1,500 JIT tests pass; parser positive and expected-error suites pass. Both benchmarks pass `--validate-micro`. No elapsed-time sample informed the decision.
- Next: inspect the spill-backed global pointers and comparator lengths around `memcmp` against LDC, accounting for the register pressure caused by any longer live range; continue examining csvagg's row parsers against clang-cl.

### compiler.optimization.067 — Share identical post-allocation return tails

- Recorded: 2026-09-25 20:58
- Updated: 2026-09-25 20:58 — Gave wordfreq's collision probe one return epilogue.
- Area: compiler/backend, post-allocation control flow and wordfreq probing
- Evidence: LDC's `mapProbe` branches from a successful `memcmp` to one common return after the collision step, while Swag emitted the same register copy, stack release, six pops, and `ret` twice. A guarded post-allocation rule now recognizes a conditional branch followed by a simple return tail, its collision label, a short continuation, and a second identical tail. It inverts the branch to the later tail and removes the first; the collision path becomes fallthrough with no added jump. The generated `mapProbe` falls from 90 to 81 instructions, versus LDC's 84, while the collision loop's memory operations remain unchanged. Wordfreq's `qsort` and `main` stay at 130 and 485 instructions, checksum 130489. Csvagg's `main` stays at 1,023 instructions, checksum 24828641. A C++ test checks an identical copied result, stack release and pop sequence, plus a different-return-value refusal. All 1,121 C++, 3,480 native, and 1,500 JIT tests pass; lexer positive and expected-error suites pass. Both benchmarks pass `--validate-micro`. No elapsed-time sample informed the decision.
- Next: compare wordfreq's `qsort` inner comparator path with LDC, especially the spill-backed pointer reloads around `memcmp`, and inspect whether csvagg's field loads can be reduced without adding spills.

### compiler.optimization.066 — Fold indexed scalar accumulation into the add

- Recorded: 2026-09-25 20:47
- Updated: 2026-09-25 20:47 — Matched clang-cl's indexed memory addition in csvagg's existing-slot path.
- Area: compiler/backend, post-allocation float peephole and csvagg aggregation
- Evidence: clang-cl adds the previous slot revenue from `[base + index*8]` to the newly computed product and stores the product register back to the same indexed slot. Swag loaded the previous value into a separate XMM register before `fadd`. A guarded post-allocation rule now recognizes the adjacent indexed load, scalar addition, and same-address store; it rewrites the addition to use the indexed memory operand and stores from the product register. The rule requires matching memory width and dead loaded/product values after the store. The existing-slot sequence falls from three instructions to two with the same one memory read and one write. Csvagg's `main` falls from 1,024 to 1,023 instructions, its row region from 243 to 242, and its checksum remains 24828641. Wordfreq's `mapProbe`, `qsort`, and `main` remain 90, 130, and 485 instructions with checksum 130489. A focused C++ test covers the fold, a different store address, a live product, and mismatched memory width. All 1,120 C++, 3,480 native, and 1,500 JIT tests pass; the sema positive and expected-error suites pass. Both benchmarks pass `--validate-micro`. No elapsed-time sample informed the decision.
- Next: compare wordfreq's `qsort` register residency and collision-probe code with LDC; for csvagg, inspect repeated field loads and decimal parser branches against clang-cl without lengthening hot live ranges.

### compiler.optimization.065 — Forward indexed store addresses through conversion chains

- Recorded: 2026-09-25 20:22
- Updated: 2026-09-25 20:22 — Removed an address calculation from csvagg's existing-slot row path.
- Area: compiler/backend, pre-allocation address forwarding
- Evidence: clang-cl writes the accumulated revenue directly to `[base + index*8]`. Swag previously computed that address with `lea`, then carried it through the integer-to-float conversion, an indexed load and the addition before storing through the temporary pointer. The pre-allocation address-forwarding walk already proves that the base and index stay unchanged, but its eight-instruction window ended immediately before this store. Extending the bounded walk to sixteen instructions lets it rewrite the store to an indexed form; later dead-code elimination removes the `lea`. The generated csvagg row region shrinks from 244 to 243 instructions with stack accesses unchanged at 17; `main` shrinks from 1,027 to 1,024 instructions. Csvagg keeps checksum 24828641. Wordfreq's `mapProbe` and `qsort` remain at 90 and 130 instructions with checksum 130489. A focused C++ test covers a nine-operation gap and a base-register redefinition that blocks the rewrite; all 1,119 C++ tests pass. The randomly drawn parser suite passed its positive and expected-error files. Both benchmark programs pass `--validate-micro`. No elapsed-time sample informed the decision.
- Next: inspect the scalar floating-point load/add/store on this same row path; clang-cl adds the old value as a memory operand and stores without the separate load. Check operand-order and floating-point semantics before changing the combiner.

### compiler.optimization.064 — Price speculative loop loads by resulting spill traffic

- Recorded: 2026-09-25 20:03
- Updated: 2026-09-25 20:15 — Checked register availability and hash arithmetic against both winning compilers.
- Area: compiler/backend, loop-invariant motion and register allocation
- Evidence: LDC keeps the byte-map mask in `r12` across collision probes; Swag folds its mask read into `and index, [map+40]`. Preventing that fold and hoisting the field made `mapProbe` grow from 90 to 98 instructions, because the mask occupied a volatile register and the `memcmp` path added a save, reload and register shuffles. Reducing the allocator's persistent-register reserve from two to one did not change this code. Admitting the preferred local-stack-base register when no debug base is pinned, together with the mask hoist, still gave 98 instructions in `mapProbe` and enlarged wordfreq's `main` to 497 instructions; the new register was not selected for this value. In `qsort`, LDC retains both key lengths across `memcmp`. A scratch-source experiment that named both lengths once removed the three memory operands on one equality path, but whole-function instructions rose from 130 to 131 and stack operands from 2 to 10. Allowing non-dominating RIP-relative global pointer loads to hoist across read-only calls moved several pointers to the inner-loop preheader, but `qsort` rose from 130 to 150 instructions and stack operands from 2 to 18; the new spill and reload traffic outweighed the removed global loads. Narrowing the XOR before each 32-bit hash multiply matched LDC's operand width, but left `mapProbe` at 90 instructions with the same memory operations and encoding size for its extended register operands; it also diverged from clang-cl's 64-bit XOR in csvagg. All compiler-source trials were reverted. These are static instruction and memory counts; elapsed milliseconds were not used.
- Next: select residency using a cost that includes additional live ranges and spills, or reuse the lengths across `memcmp` without extending their lifetime through both comparator loops. Continue comparing csvagg's row loop with clang-cl.

### compiler.optimization.057 — Price constant-pool hoists by register pressure

- Recorded: 2026-09-25 13:59
- Updated: 2026-09-25 19:36 — Kept CSV conversion constants in vector registers across the row loop and shared their reads across writes.
- Area: compiler/backend, loop-invariant code motion and value numbering
- Evidence: clang-cl loads the two 128-bit constants used for `u64` to `f64` conversion before csvagg's row loop and reuses them for price and quantity conversion. Swag previously read the pair three times per row. LICM now recognizes a RIP-relative `ConstantAddress` vector load as immutable across calls and pointer stores; value numbering likewise permits identical constant-pool reads to match across memory epochs, while global loads retain the epoch barrier. In the generated CSV row region, the six per-row constant reads disappear, the instruction count drops from 251 to 244, and stack accesses stay at 17. The whole `main` changes from 1,028 to 1,027 instructions after register allocation; its checksum remains 24828641. Wordfreq's `mapProbe` and `qsort` stay at 90 and 130 instructions with checksum 130489. Raytrace's `main` and `trace` stay at 142 and 196 instructions with checksum 56061776. Focused C++ tests distinguish constant-pool reads from mutable globals, missing relocations and distinct constant targets. All 1,118 C++, 3,480 native, and 1,500 JIT tests pass; csvagg, wordfreq and raytrace pass `--validate-micro`. An earlier trial was rejected because the whole function grew; the row-loop comparison with clang-cl provides the relevant static evidence. No elapsed-time sample informed the decision.
- Next: compare the remaining CSV parsing and aggregation instructions with clang-cl, especially repeated map-field loads and integer-to-float conversion steps; revisit constant residency only if loop spills appear.

### compiler.optimization.063 — Keep decimal byte values zero-extended through parsing

- Recorded: 2026-09-25 19:13
- Updated: 2026-09-25 19:13 — Removed three redundant byte extensions from csvagg's row parsers.
- Area: compiler/backend, post-allocation peephole and csvagg parsing
- Evidence: clang-cl loads each digit with `movzx` before the decimal arithmetic. In csvagg's quantity and integer-price loops, Swag already used a zero-extending indexed byte load but repeated `movzx` after subtracting `'0'` in the low byte. The x86 byte subtraction preserves the previously zero high bits, including when the byte wraps. A guarded rule removes that second extension after a delimiter compare and an independent LEA. In the fractional-price loop, Swag used a plain byte load followed by the same subtraction and extension; a second rule moves the extension into the indexed load when no instruction reads the original high bits between the load and the final extension. The three inner loops each lose one instruction per digit. Csvagg's generated `main` shrinks from 1,031 to 1,028 instructions and the timed row span from 256 to 253; its checksum remains 24828641. Wordfreq's `mapProbe` stays at 90 and `qsort` at 130 instructions, with checksum 130489. Focused C++ cases cover indexed and simple loads, a nonzero-extended load, a wider subtraction, an intervening high-bit read, and an LEA that modifies the digit register. All 1,116 C++, 3,480 native, and 1,500 JIT tests pass; both benchmark programs pass `--validate-micro`. No elapsed-time sample informed the decision.
- Next: compare csvagg's remaining row-loop memory traffic with clang-cl after the constant-pool improvement in compiler.optimization.057.

### compiler.optimization.056 — Branch directly on an inlined comparator's result

- Recorded: 2026-09-25 11:40
- Updated: 2026-09-25 18:43 — Placed short loop-step blocks on the common comparator fall-through path after register allocation.
- Area: compiler/backend, inlining and loop block layout
- Evidence: The earlier branch-threading and flag-reuse rules removed `setcc`, a copy, a retest, and one repeated comparison in wordfreq's inlined comparator. The remaining unequal-count path was `cmp; je tie; ja advance; jmp stop`, while LDC lays out the advance as fall-through after a branch to stop. A guarded post-RA loop layout rule now moves a one-instruction increment/decrement block and its back edge before the tie block, inverts the second conditional to stop, and redirects the tie block's old fall-through to the moved step. It requires exact adjacent labels, a unit-width step, and a backward loop edge. Both qsort comparator directions now use `cmp; je tie; jbe stop; advance` on the unequal-count path, matching LDC's branch count. The function shrinks from 132 to 130 instructions because later branch cleanup removes two redundant jumps. The checksum remains 130489; csvagg's main stays at 1,031 instructions with checksum 24828641. Focused C++ cases cover an eligible loop and a non-unit step; all 1,114 C++, 3,480 native, and 1,500 JIT tests pass, as does wordfreq with `--validate-micro`. No millisecond sample informed the decision.
- Next: compare the remaining global-pointer reloads at the boundary between wordfreq's two comparator loops with LDC; continue csvagg's parser and aggregation comparison with clang-cl.

### compiler.optimization.062 — Update masked probe indices in place

- Recorded: 2026-09-25 18:22
- Updated: 2026-09-25 18:22 — Folded the guarded LEA/AND/copy probe update into an in-place increment and mask.
- Area: compiler/backend, post-allocation peephole and byte-map probing
- Evidence: LDC advances a probe index with `inc index; and index, mask`. Swag used `lea temp, [index + 1]; and temp, [mask]; mov index, temp` in the collision path. The post-allocation rule now emits `inc index; and index, [mask]` after proving the temporary dies, the mask address uses neither the index nor the temporary, the width and increment are exact, and the following AND replaces the increment's flags. It removes one instruction per collision probe and matches LDC's two-instruction in-place shape; the remaining mask memory operand is a separate register-residency question. Wordfreq's `mapProbe` shrinks from 91 to 90 instructions and csvagg's `main` from 1,032 to 1,031, with its timed row span returning from 257 to 256 instructions. Checksums remain 130489 and 24828641. A C++ regression covers an index-dependent mask address, a live temporary, and a different increment. The 1,113 C++, 3,480 native, and 1,500 JIT tests pass; the random `sema` suite passed its positive and expected-error files. No elapsed-time sample informed the decision.
- Next: compare the remaining mask memory operand and branch layout in wordfreq's probe with LDC, and keep testing csvagg's parser loop against clang-cl's assembly.

### compiler.optimization.061 — Keep byte-map probe pointers resident across read-only calls

- Recorded: 2026-09-25 18:15
- Updated: 2026-09-25 18:15 — Hoisted invariant structure fields only when their value is used as a memory base in the loop.
- Area: compiler/backend, loop-invariant motion in wordfreq and csvagg map probing
- Evidence: LDC keeps the byte-map `used` and `keyLen` pointers in persistent registers through `memcmp` while probing occupied slots. Swag loaded both fields from the map object on each probe. The read-only-call LICM rule now admits a 64-bit field load from an invariant virtual base when that loaded pointer is dereferenced in the same loop; existing dominance and store-alias proofs still apply. This excludes the map mask, whose speculative hoist in an earlier wider rule spilled to the stack in csvagg. In wordfreq's `mapProbe`, an occupied-slot check now uses two memory operands and two instructions for `used[idx]` and `keyLen[idx]`, down from four of each; the full function grows from 86 to 91 instructions because it loads and saves two extra persistent registers at entry and exit. The loop body now follows LDC's pointer residency. In csvagg, inlined probing makes generated `main` shrink from 1,034 to 1,032 instructions; the full timed row span changes from 256 to 257 instructions, so the gain is in repeated probe iterations rather than the flat span. Wordfreq and csvagg checksums remain 130489 and 24828641. A focused C++ test covers a writing call and an aliasing store as barriers. The 1,112 C++, 3,480 native, and 1,500 JIT tests pass; the random safety suite passed with 138 successes and 7 expected failures. No elapsed-time sample informed the decision.
- Next: compare the probe's `(idx + 1) & mask` update with LDC's two-instruction in-place update, and examine whether keeping the mask resident avoids a memory operand without spilling a hotter pointer.

### compiler.optimization.060 — Keep wordfreq's pivot count resident through comparator loops

- Recorded: 2026-09-25 17:08
- Updated: 2026-09-25 17:45 — Gave long-lived values a persistent register when a nominally free register ends at a call, then hoisted the indexed pivot count across read-only calls.
- Area: compiler/backend, loop-invariant motion and interval allocation
- Evidence: LDC loads the pivot's count once before wordfreq's inner comparisons and keeps it in a callee-saved register. Swag previously read that count from `g_Cnt` on every first-loop iteration. A first indexed-load hoist alone spilled the count at `Swag.memcmp` and grew `qsort` from 132 to 134 instructions. The interval trace showed all six persistent integer registers occupied at the pivot load, while a caller-saved register was free only until the call. The allocator now tries to displace the owner of a persistent register before accepting that partial free interval, and falls back to the partial register if no owner can move. This preference applies only when the free interval ends at a call: a general preference grew raytrace's `intersect` from 214 to 222 instructions, while the call-specific rule keeps it at 214. LICM can now hoist an indexed load across a read-only call when its address is invariant and the existing store-alias checks prove safety. Focused C++ tests cover the register choice and a writing call or aliasing store as barriers to the hoist. In wordfreq, the pivot count stays in a callee-saved register; the first unequal-count comparator path drops from 9 instructions and 4 explicit memory operands to 7 and 2. Full `qsort` remains 132 instructions because work outside that path grows. Csvagg's `main` drops from 1,066 to 1,034 instructions, with its timed row span from 268 to 256; its checksum remains 24828641. Wordfreq's checksum remains 130489; raytrace's remains 56061776. The 1,111 C++, 3,480 native, and 1,500 JIT tests pass. No elapsed-time sample informed the decision.
- Next: compare wordfreq's second comparator and partition branches with LDC, then reduce csvagg's remaining parser and aggregation traffic against clang-cl without regressing the other generated programs.

### compiler.optimization.059 — Fold indexed memory updates inside loops

- Recorded: 2026-09-25 17:09
- Updated: 2026-09-25 17:09 — Removed the blanket loop exclusion from exact indexed load/update/store folding.
- Area: compiler/backend, instruction combine and csvagg row aggregation
- Evidence: csvagg's existing-slot row path loaded `slotCount[slot]`, added one, then stored it; `slotQty[slot]` used the same three-instruction pattern with a register addend. clang-cl emits `inc [slot]` and `add [slot], reg`. The existing indexed memory fold already proves the load and store address, width, and single-use value match, but excluded every loop. Allowing the fold in loops emits the same two memory update forms as clang-cl, removes four instructions from csvagg's timed row span (271 to 267) and two explicit memory operands (80 to 78); generated `main` drops from 1,070 to 1,066 instructions. SLP already treats indexed accesses as opaque, so this does not hide a vectorizable scalar lane. A C++ regression covers an indexed loop update and an indexed frame-derived slot that stays scalar. The 1,109 C++, 3,480 native, and 1,500 JIT tests pass; a random lexer draw passed. Csvagg checksum remains 24828641; wordfreq checksum remains 130489, and its `qsort` remains 132 instructions. No elapsed-time sample informed the decision.
- Next: compare the remaining row parser and hash-probe blocks with clang-cl, especially branches and redundant stack traffic around the existing-slot path.

### compiler.optimization.058 — Forward stores to known global targets into following loads

- Recorded: 2026-09-25 16:43
- Updated: 2026-09-25 16:43 — Cached RIP-relative global stores by relocation identity.
- Area: compiler/backend, instruction combine and memory forwarding
- Evidence: the store-to-load cache discarded every RIP-relative store, even when its relocation identified a global exactly and the next instruction read that same location. It now clears potentially aliasing entries and retains the stored register for a matching global load until a write, call, control-flow barrier, or register redefinition. Focused C++ cases cover relocation kind/address/width mismatch and alias barriers. In csvagg's generated `main`, six global-seed reloads disappear (1,076 to 1,070 instructions); wordfreq's `main` loses one (485 to 484). Both changes are in input construction before the timed region; neither `qsort` nor csvagg's timed row loop changes. The wordfreq and csvagg checksums remain 130489 and 24828641. The 1,108 C++, 3,480 native, and 1,500 JIT tests pass. The random additional draw was `sema`, whose positive and expected-error files passed. No elapsed-time sample was used as evidence.
- Next: look for the same provable store/read pair inside a measured loop, then compare its memory operations with the winning implementation. Keep the timed-loop effort on wordfreq's comparator layout and csvagg's row parser.

### compiler.optimization.055 — Keep read-only global pointers resident across comparator calls

- Recorded: 2026-09-25 11:15
- Updated: 2026-09-25 16:25 — Removed a false legalization scratch requirement and reduced both comparator loops.
- Area: compiler/backend, loop-invariant code motion and call effects
- Evidence: LDC keeps `g_Idx` and `g_Cnt` pointers outside wordfreq's inner quicksort comparisons; Swag previously reloaded them from RIP-relative globals each turn. An earlier LICM experiment using `SymbolFunction::isPure()` did not help because the bodyless `Swag.memcmp` declaration was not pure; increasing the purity budget and recognizing `Swag.vecmask` also left it impure. A `ReadOnly` call contract now explicitly promises no caller-visible writes and survives module API export. LICM uses that contract only for direct 64-bit global loads. The resulting `qsort` initially grew from 126 to 134 instructions because it spilled hoisted pointers. The allocator then proved to reserve a whole persistent register for legalization solely because `mayNeedLegalizeScratchRegister` reported `true` for a zero-operand `ret` (its only reported instruction in `qsort`). Correcting that answer lets the allocation use `r15` and removes two instructions: the first comparator loop drops from 10 instructions and 5 memory operands per unequal-count iteration to 9 and 4, and the second from 9 and 4 to 8 and 3. The full function has 132 instructions. An experiment admitting the preferred local-stack-base register to the interval pool alone changed no emitted instructions and was reverted. The wordfreq checksum remains 130489. Csvagg's 1,076-instruction `main`, 271-instruction row span, and checksum 24828641 remain unchanged. The 1,107 C++, 3,480 native, and 1,500 JIT tests pass. No timing sample informed the decision.
- Next: improve register allocation for loop-invariant pointers live across calls so both `g_Idx` and `g_Cnt` remain in persistent registers, as in LDC, rather than retaining one stack reload per first comparator iteration. Recount both inner loops and csvagg's row loop after any change.

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

### compiler.optimization.053 — Recheck scalar global loop updates with RIP memory operands

- Recorded: 2026-09-24 16:49
- Area: compiler/backend, loop memory folding
- Evidence: an independent four-element `u32` loop computes `Total += values[i]`
  and `dst[] += values[i]`; both results are 10. The final Release micro code for
  the global update contains a RIP load, an indexed-memory add into a register,
  and a RIP store per iteration. The pointer update contains an indexed load and
  an `add [rcx], r9`. `keepAccessScalar` retains some global accesses in loops to
  protect vectorization. Direct RIP memory arithmetic is now available, so the
  global scalar loop may have a remaining `load; add; store` fold opportunity.
  Entries .002 and .046 document vectorization losses from broad changes to this
  guard; this one loop does not justify changing the policy.
- Next: compare final code, vector operations, memory operations, and register
  pressure for unrelated scalar-global loops with and without a guarded RIP
  read-modify-write fold. Include a vectorization candidate and a frame slot.
  Admit only a general condition that improves scalar loops while preserving
  vectorization.
- Complete when static evidence explains which loop shapes should use direct
  memory arithmetic and which must retain the existing guard.

### compiler.optimization.052 — Check final code before adding a late indexed-select rule

- Recorded: 2026-09-24 12:30
- Area: compiler/backend, indexed memory selection
- Evidence: in `wordfreq.less`, the first post-RA sweep showed a five-instruction
  `copy; compare indexed memory; branch; reload; copy` minimum. A candidate post-RA
  rule turned it into `load; compare; cmov`, passed 1,075 C++ unit tests and the
  independently drawn native `flow/switch_complete.swg` (two tests), and kept
  `CHECK=130489`. A comparison of the **final** dumps showed that the existing
  optimizer already emits the same three-instruction minimum: `less` has 46 final
  micro instructions in both builds. The candidate was reverted; the first sweep
  was the wrong baseline for a multi-sweep pass.
- Next: only consider another post-RA indexed-select rule after locating a
  non-benchmark function whose final dump still has the redundant branch and
  reload. Compare final dumps after every optimization sweep, not adjacent stage
  snapshots from different sweeps.
- Complete when that search either identifies a genuine missed final-code shape
  with static benefit or rules out this additional post-RA rule.

### compiler.optimization.002 — Unrolling the key-stream loop still has to prove it pays

- Recorded: 2026-08-06 20:18
- Updated: 2026-09-24 11:56 — Correct the current trip limit after the later unroller changes.
- Area: compiler/backend
- Found while: chasing the second half of the ChaCha20 gap after the round loop stopped spilling
- Observation in August 2026: the dominant cost was the key-stream application — sixteen words
  XOR-ed one at a time, a loop the unroller then refused because `K_MAX_TRIPS` was 8. Raising
  it to 16 unrolled the
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
- Current boundary: `1238a3c2e` subsequently gave independent temporaries in cloned straight-line
  bodies fresh names, with coverage in `native/optimizer/unroll_renames_temporaries.swg`.
  `K_MAX_TRIPS` is now 16 for ordinary loops, and loops indexing immutable constant tables can
  exceed it within the existing code-size budget. The August/September counts above predate
  these changes; carried values are deliberately not renamed.
- Next: compare current ChaCha key-stream code against the earlier eight-trip limit using static
  per-loop instructions, memory operations, and spills. Use paired timing only if a tradeoff
  remains after inspecting the generated code.
- Complete when: the current unroll limit has profitability evidence for this loop, including
  the effects of temporary renaming and later instruction folds.

### compiler.optimization.051 — Calibrate the loop-rotation header budget

- Recorded: 2026-09-24 11:53
- Area: compiler/backend, post-RA loop rotation
- Evidence: `PostRALoopRotate` duplicates a flag-only test and the allocator's flag-neutral
  connectors at the back edge, replacing one unconditional jump per iteration. The unrelated
  `PostRALoopRotate_IndependentHeadersRotate` test rotates headers with one incoming back edge;
  `PostRALoopRotate_SecondIncomingJumpBlocks` keeps a header with another incoming edge. These
  safety guards use general control flow, and the pass now covers register and memory `test`
  instructions as well as compares. Its eight-instruction header limit is a static growth budget,
  but no cost comparison explains why a safe nine-instruction header should keep its per-iteration
  jump while an eight-instruction header is duplicated.
- Next: compare code size and executed jumps for unrelated loops with short and long connector
  runs, then derive a header budget from code growth and work saved instead of the fixed cutoff.
- Complete when the cutoff or its replacement has non-benchmark profitability evidence and tests
  around the chosen boundary.

### compiler.optimization.049 — Derive the small-loop trip limit from code benefit

- Recorded: 2026-09-24 10:33
- Updated: 2026-09-24 11:33 — The constant-table case now crosses sixteen trips within the size budget; the ordinary-loop cap remains to calibrate.
- Area: compiler/backend, loop unrolling
- Evidence: `Pass.LoopUnroll.cpp` caps full unrolling at 16 trips. Its comment names ChaCha's
  16-word output loop as the reason, while separate 96-instruction body, 384-instruction total,
  branch, and constant-table guards already describe general costs and benefits. The unrelated
  `unroll_constant_tables.swg` uses a five-trip weighted integer loop with immutable table
  indices and branches; it benefits from constant-index folding. Conversely,
  `LoopUnroll_SixteenTrips_Flattens` shows that an otherwise identical, one-instruction body
  flattens at 16 trips and remains a loop at 17, solely because of that historical cap.
- Evidence after the change: an unrelated 17-element constant-table sum uses 122 executed micro
  instructions and 17 indexed memory reads with the old cap, versus 36 executed instructions and
  no indexed reads when unrolled. Static function size grows from 11 to 36 micro instructions;
  both versions produce `CHECK=272`. A synthetic 17-trip table loop now
  flattens, while the otherwise identical plain loop still keeps its latch.
- Next: compare non-table loops around the remaining sixteen-trip boundary. Replace that cap
  only when a general work-saved versus code-growth rule improves them without expanding loops
  whose bodies retain their per-trip work.
- Complete when the ordinary-loop cap has profitability evidence beyond ChaCha and a test for
  both admitted and rejected shapes.

### compiler.optimization.048 — Check LICM's relocated address policy outside benchmarks

- Recorded: 2026-09-24 09:47
- Area: compiler/backend, loop-invariant code motion
- Evidence: `Pass.LoopInvariantCodeMotion.cpp` keeps a relocated `LoadRegPtrImm` inside a loop while
  it may hoist relocated memory reads. The rule uses opcode and relocation properties, not a
  benchmark name. `LICM_RetargetsDuplicateRelocationsAndKeepsUnhoistedOnes` checks both shapes
  on an unrelated synthetic loop. The recorded cost argument for keeping the address
  materialization inside cites only SHA-256 (+2 instructions and one stack slot when hoisted),
  so the profitability decision lacks a static comparison on other code.
- Next: compare loop instructions and spill traffic for the current policy and a guarded hoist on
  non-benchmark functions that repeatedly access relocated tables, plus functions without such
  accesses. Keep the current rule if hoisting merely lengthens live ranges; otherwise derive a
  register-pressure condition from those cases and add focused correctness coverage.
- Complete when the policy has static profitability evidence outside `bench/`.

### compiler.optimization.047 — Calibrate span-scoped register grants on non-benchmark code

- Recorded: 2026-09-24 09:13
- Area: compiler/backend, register allocation
- Evidence: `Pass.RegisterAllocation.cpp` grants a register named elsewhere when a candidate's
  benefit density reaches half the best density in that function. The decision uses general
  properties — loop benefit, live span, pool headroom, call crossings, and concrete claims — but
  the factor of two was selected from `bench/` results for sha256, leven, wordfreq, and csvagg.
  A review on 2026-09-24 found no benchmark-specific predicate, yet no recorded static census of
  spill traffic or rejected grants in unrelated standard-module code supports that factor.
- Next: compare divisor values 1, 2, and 4 on representative non-benchmark functions with
  different register pressure. Count granted ranges and memory operations in the affected loops
  before relying on timing; retain the factor or replace it with a pressure cost rule from that
  evidence.
- Complete when the current gate or its replacement has static evidence outside `bench/` and
  focused correctness coverage for both accepted and rejected grants.

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
- Complete when: a replacement preserves emitted code and focused SSA/native behavior and
  resolves a repeatable compilation-time gain against the roughly 3% measurement floor.
- Related: compiler.core.004, compiler.core.030, compiler.optimization.039.
### compiler.optimization.043 — Repeated scalar float constants require a vector constant representation

- Recorded: 2026-09-18 19:48
- Area: compiler/backend, constant materialization
- Evidence: four `Swag.abs(f32)` stores now form a scalar constant load, `pshufd`, packed load,
  `andps`, packed store (five body instructions). LLVM uses a 16-byte repeated sign-mask constant
  directly as the `andps` memory operand, for three body instructions. The scalar constant
  allocation owns only four bytes, so reusing it as a packed memory operand is unsound; the SLP
  pass correctly materializes a register splat instead.
- Next: design an interned 128-bit repeated-constant allocation with an explicit relocation and
  memory-operand legality contract; use it only where the packed operation can read all 16 bytes.
- Complete when: the sign-mask fixture loads or consumes a verified 128-bit constant without a
  scalar-to-vector shuffle, and relocation/JIT tests cover the allocation boundary.


### compiler.optimization.040 — Returning a fresh aggregate invokes its copy hook

- Recorded: 2026-09-16 14:37
- Area: compiler/lowering, aggregate return ownership
- Found while: implementing explicit moves in aggregate fields and conditional arms
  (`language.design.028`).
- Evidence: on the unchanged DevMode compiler 0.1.687, a non-inlined factory
  `func makeOwner(value: s64)->Owner => Owner{value}` invokes `Owner.opPostCopy` once
  for a fresh 16-byte value with drop, copy, and move hooks. Returning a named local
  instead adopts its storage. A runtime input and a copy counter reproduce the difference;
  constant folding can hide the factory's copy from runtime counters.
- Next: review `returnSourceIsOwnedTemporary` in `CodeGen.Function.Post.cpp` and the
  destination binding for fresh aggregate literals. Establish which literals can transfer
  ownership into the caller's result without a copy hook or a second destruction.
- Complete when: fresh aggregate returns have a documented ownership rule and JIT/native
  regressions cover their copy/move hooks, source cleanup, and optimized inlining.
- Related: compiler.optimization.027.

### compiler.optimization.039 — Nothing measures how close a function comes to the sweep budget

- Recorded: 2026-09-16 12:12
- Updated: 2026-09-16 13:02 — The silent failure is fixed; what remains is the unmeasured budget.
- Area: compiler/backend, compilation time
- Evidence: the pre-RA optimization loop sweeps at most sixteen times, and a function that still
  changes on the sixteenth stops the build. Lowering that budget to three with a temporary knob
  (Release 0.1.684) and building `bin/std/modules/gui` showed what that costs: eighteen errors,
  all of them semantic errors about the user's own source, because the compile-time evaluations
  those calls fold are lowered through the same loop. The loop now reports the defect itself,
  naming the function and the budget, covered by the C++ test
  `MicroPassManager_PreRa_ReportsALoopThatNeverSettles`. What it still does not say is how much
  room is left: no measurement records the sweep counts a real build reaches, so whether sixteen
  is a distant safety net or a limit some function already approaches is unknown.
- Next: count the sweeps each function needs over a full `bin/std` build in both configurations
  and record the distribution. A maximum far below sixteen makes the budget a safety net; a
  maximum near it makes the budget a live limit and the convergence of individual passes the
  thing to fix.
- Complete when: the sweep distribution over `bin/std` is recorded, and the budget is either
  justified by it or replaced by what the measurement shows is needed.
- Related: compiler.optimization.029, compiler.core.004.

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
  trips; merely raising that limit is a different experiment, compiler.optimization.002.
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

### compiler.optimization.016 — Independent virtual-register webs need a new normalization measurement

- Recorded: 2026-08-27 07:57
- Updated: 2026-09-14 06:25 — Separate existing unroller renaming from general def-use web normalization.
- Intent: a normalization pass gives every def-use web of a virtual register its own fresh
  register - the SSA property LLVM's passes get from their IR, reconstructed by renaming, with no
  phi nodes needed because a web that spans a join keeps its one name. The lowering reuses
  virtual registers across unrelated computations, so today a loop-invariant chain shares its
  register with code elsewhere in the function (measured on the deblock probe: the `pass % 3`
  chain's register carries five definitions, one outside the loop), and any pass that reasons
  per-register - the web hoisting now in LICM first among them - must refuse the whole register.
- Current boundary: `Pass.LoopUnroll.cpp` already renames independent temporaries in cloned
  straight-line bodies (`1238a3c2e`, `native/optimizer/unroll_renames_temporaries.swg`). It leaves
  carried values and bodies with internal labels unchanged; it does not normalize the original
  function's def-use webs. That narrower transform does not retire this investigation.
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

### compiler.optimization.008 — The hand-written sign-bit clamps of the H.264 decoder may be retired

- Recorded: 2026-08-19 14:16
- Updated: 2026-09-14 06:25 — Account for flag-preserving branch fixes without inferring a clamp speedup.
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
- Current boundary: `900480a3c` and `3cd5a5c77` corrected the treatment of instructions that
  preserve CPU flags, including XMM clears and integer NOT. Branch and arm analysis now uses
  `instructionActuallyDefinesCpuFlags`; a nominal opcode flag is not proof that entry flags
  were overwritten. `Test.Micro.BranchSimplify.cpp` covers the dynamic branch and arm cases,
  and `native/flow/string_condition_snapshot.swg` covers the string-condition failure.
  The sign-bit helpers remain in `decode/h264/transform.swg`; these correctness fixes supply
  no new timing evidence for replacing them.
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
