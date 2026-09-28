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

### compiler.optimization.097 — Keep a short loop step on the advancing edge beyond a cold-block size limit

- Recorded: 2026-09-28 16:35
- Area: compiler/backend, post-allocation loop layout
- Audit: `placeShortLoopStep` searched only 80 Micro instructions ahead for the step label. That distance did not participate in the branch or register proof; it excluded otherwise identical loops with a longer cold arm. A label-to-ordinal map now resolves the target in constant expected time and allows the same structural rewrite at any distance. The test covers a 96-instruction cold arm, the original short arm, and a non-unit step that must remain unchanged.
- Evidence: the long-arm case removes one executed unconditional jump from its advancing path without adding an instruction there. All seven benchmark tasks retain their selected function counts and checksums, so this batch has no claimed benchmark gain. C++ (1,156), native Release (3,483), and JIT Release (1,500) pass.
- Next: at the next full campaign milestone, inspect any larger ordinary loop newly reached by this layout rule and check its hot and cold branch balance before closing this lead.

### compiler.optimization.094 — Defer callee-saved XMM traffic past an early exit

- Recorded: 2026-09-28 09:58
- Updated: 2026-09-28 16:34 — Identified MSVC's chained unwind regions and Swag's single-record boundary.
- Area: compiler/backend, register allocation, prologue and unwind information
- Evidence: The latest accepted campaign names C++/MSVC as raytrace's fastest other runtime (9.601 ms versus Swag's 10.742 ms; ratio 1.119). In `trace`, Swag saves XMM6–XMM15 before its first `intersect` call and reloads all ten on the no-hit return. MSVC saves six XMM registers before that call; after `g_HitI >= 0` it saves XMM9 and XMM13–XMM15, which the no-hit path never touches. The no-hit path therefore avoids four stores and four loads in MSVC. Swag's frame reserves `0x168` bytes and MSVC's `0x128`, though allocation size alone does not measure the path cost.
- Unwind evidence: `dumpbin /unwindinfo` on the accepted MSVC executable shows a primary `trace` range `0x1440–0x14DA` with six `SAVE_XMM128` records and a chained range `0x14DA–0x16F0` with saves for XMM9/XMM13/XMM14/XMM15 plus RBX/RDI. The no-hit return at object offset `0x74` lies in the primary range; the four later saves begin at offset `0xB4`. Two further chained ranges describe later control-flow regions. Swag currently builds one `UNWIND_INFO` blob in `X64UnwindWindows`, one native `.pdata` entry per function in `DebugInfoCodeView`, and one JIT `RUNTIME_FUNCTION` per allocation in `Os.Windows`. Those three interfaces must represent multiple code ranges before a delayed save can be correct under Windows unwinding.
- Next: introduce region-aware unwind records across the encoder, native object writer, and JIT function table, then move only registers first defined below the guard. Test both arms, nested calls and exceptional unwinding in native and JIT output, and compare no-hit and hit paths against MSVC.
- Complete when: the short path skips unused saves and restores without adding spill traffic to the hit path, and unwind and ABI checks pass; otherwise keep the current eager save plan.

### compiler.optimization.096 — Remove the loop-bound reload from wordfreq's common path

- Recorded: 2026-09-28 15:46
- Updated: 2026-09-28 16:15 — The cold-edge placement passed C++, native, JIT, and all seven benchmark checksums.
- Area: compiler/backend, path-sensitive frame reload placement
- Evidence: LDC's wordfreq character loop compares its index with the bound retained in `rbp`. Swag's corresponding alphabetic path retains the index in `r12` after compiler.optimization.095, but reloads the bound into `r13` from `[rsp+0x200]` immediately before the loop comparison on every character. A second reload from that slot is needed only after leaving the scan loop for token finalization. The current `main` contains 448 optimized Micro instructions and checksum 130489.
- Investigation: the post-allocation CFG exposes a join label followed by the index increment and the bound reload. An earlier adjacent-label trial did not match this shape. The accepted rule looks past that independent increment and places the reload between the preceding cold-edge label and the join label. Its backward proof tracks balanced stack adjustments, rejects writes overlapping the private spill slot and paths without an initial value, and checks every direct jump into the join. An entry without a matching store initially exposed an unsound cycle in the proof; the regression test caught it before integration.
- Evidence: the final Micro for wordfreq keeps the bound store at `[rsp+0x200]`, reloads it once on the cold edge before the join label and once after loop exit, and compares `r12` and `r13` on the alphabetic path. The common increment-and-compare path goes from three instructions with one memory read to two instructions with none; the cold path gains that read. `main` remains at 448 optimized Micro instructions and checksum 130489. The C++ unit test covers an independent loop, balanced stack adjustments, an unrelated memory write, missing initialization, a register clobber, an overlapping slot write, and a slot outside the private spill area. No individual runtime timing was taken.
- Validation: 1,156 C++ tests, 3,483 native Release tests, 1,500 JIT Release tests, and all seven deterministic benchmark checksums pass. The six other selected benchmark function counts are unchanged.

### compiler.optimization.095 — Keep loop values off the stack on the common branch

- Recorded: 2026-09-28 14:04
- Updated: 2026-09-28 15:18 — Move the index spill store to the cold branch and remove the loop-latch store.
- Area: compiler/backend, path-sensitive spill placement
- Evidence: In wordfreq's character scan, the alphabetic path reaches a join where `r12` still holds the index, while token processing may reuse `r12`. The interval allocator had put the reload from `[rsp+0x210]` at that join, so every alphabetic character read the index from the stack. A post-allocation rule now moves the reload to the join's fallthrough edge only when every direct jump into the join can trace the same register value back to a matching frame store or reload without an intervening register definition, memory write, or call. It rejects a cyclic proof through the reload being moved. The common path loses one memory read; `main` grows from 448 to 450 static Micro instructions because subsequent branch layout changes, with no new instruction on that path. The checksum remains 130489; the other six benchmark checksums and selected function counts are unchanged. C++ (1,154), native Release (3,483), and JIT Release (1,500) tests pass. No timing sample was taken for this edit.
- A second post-allocation rule now moves a private spill store to the cold branch that dominates its sole read. It checks every explicit access to the eight-byte slot, rejects overlapping or indexed accesses, proves that the register still equals the slot on every incoming path, and tracks balanced stack-pointer adjustments along paths to the read. It removes later writes only when the new store lies on every route to the read. It applies only when at least one redundant write is removed: wordfreq's header and latch stores become one cold-entry store. The common alphabetic path now avoids the header store, join reload, and latch store, while `main` has 448 static Micro instructions and checksum 130489. A wider version moved a store in Leven without removing another write and raised its `main` from 474 to 478 instructions; the narrower rule restores 474 and checksum 67441. The other five benchmark checksums and selected function counts are unchanged. C++ (1,155), native Release (3,483), and JIT Release (1,500) tests pass with the final rule, as do all seven benchmark checksums. No timing sample was taken for this edit.
- The loop still reloads the bound `r13` from `[rsp+0x200]` at the latch, though it remains intact on the alphabetic path. Moving that reload needs a separate proof over the loop back edge and cold exits.
- Next: prove the bound register remains equal to its frame slot on every hot edge before moving its reload. Compare complete hot and cold paths and obtain a clean paired measurement at a campaign milestone.
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

### compiler.optimization.083 — Retain the probe mask without increasing spills

- Recorded: 2026-09-26 12:46
- Updated: 2026-09-28 08:29 — Keep the probe mask in a saved register without another entry load.
- Area: compiler/backend, LICM and register allocation
- Evidence: LDC retains wordfreq's `ByteMap.mask` in a callee-saved register across `memcmp`, while Swag reads `[m+mask]` during each collision step. Running LICM before instruction combine and allowing every invariant structure-field load across a read-only call moved that read out of the loop, but `mapProbe` grew from 81 to 98 instructions. The frame grew from `0x28` to `0x98`, the length and mask values spilled and reloaded, and an extra return tail appeared. The broad trial was reverted. A retained mask is only a gain if allocation keeps the loop's other live values resident too; one fewer memory operand in the collision step is insufficient evidence on its own. No timing was used.
- Repeating the early-LICM schedule after `mapProbe` was inlined into wordfreq's two token-finalization loops did not retain the mask: the resulting `main` still reads `[m+mask]` three times, stays at 451 instructions, and `qsort` grows from 132 to 133. The checksum remains 130489. This schedule trial was reverted without using timing.
- With the subsequent caller-test threading, wordfreq `main` was 443 instructions. Its first inlined probe still read `[rbx+0xC8]` for the initial hash mask and again for each collision step; LDC held that mask in `r10` across `memcmp`, saving and restoring it around the call. The Swag collision step retained the extra memory operand, while the checksum remained 130489. This was a code comparison, not a new LICM trial.
- Post-allocation loop rotation now recognizes the exit label after any run of adjacent labels following the back edge. It duplicates the `used[idx]` comparison at the collision tail and removes the unconditional jump: the first wordfreq collision path falls from seven to six runtime instructions, with three memory operands still versus LDC's two. The two inlined probes add two compares and two labels in total, so `main` rises from 443 to 447 static Micro instructions. The entry comparison remains on the cold entry path, and neither allocation nor spills change. All seven task checksums pass with `--validate-micro`; the other six selected function counts are unchanged. A C++ regression covers adjacent exit aliases and an intervening instruction. This closes .091; the mask load remains this entry's gap. No timing sample informed the decision.
- The latest accepted full campaign, `20260928-051818`, names C++/clang-cl as wordfreq's fastest other runtime. Its inlined probe uses `and esi, 3FFFh` at collision, followed by the `used` and length tests: six instructions and two memory operands. A scratch-only trial marked `mapInit` inline; it exposed the constant `0x3FFF` to Swag, but enlarged `main` from 447 to 516 Micro instructions and reintroduced stack reloads and a back-edge jump in the collision loop. The checksum was 130489; the trial was rejected on static code quality, without timing.
- A post-allocation rule now moves a folded bitwise memory operand into an already saved, idle persistent register. It replaces the same address's straight-line entry read with a load and register operation, then rewrites every matching use in the loop. Eligibility requires a stable base, no loop memory writes, only direct calls annotated `ReadOnly`, and a register that is dead from the entry read through the loop. In wordfreq's first inlined probe, `r15` carries the mask across `memcmp`: the hot collision path remains six instructions and falls from three memory operands to two, matching the winner's counts. The entry still reads the mask once; it gains one encoded instruction but no memory access, while the frame and spill traffic stay unchanged. Thus `main` rises from 447 to 448 static Micro instructions. The final-token probe is unchanged because its entry read uses a different base expression. All seven task checksums pass under `--validate-micro`, and the other six selected function counts are unchanged. C++ tests cover an unrelated OR/XOR loop, a writable call, a memory write, a changing base, no prior read, a live scratch register, and no saved register. This is static evidence, not a measured runtime gain.
- Next: compare the complete hash and collision paths with clang-cl, including entry frequency and frame traffic; obtain a clean paired wordfreq measurement at a campaign milestone before closing this lead.
- Complete when: a focused rule retains the mask without increasing spill traffic and improves paired wordfreq runs, or measurements show that retaining it is not profitable and this lead is retired.

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

### compiler.optimization.090 — CSV aggregation regresses with the shadow-free Swag ABI

- Recorded: 2026-09-27 10:24
- Updated: 2026-09-27 10:57 — Confirmed workload-size crossover with identical module names
- Area: compiler/backend, native code layout and calling convention
- Evidence: in eight alternating, pinned pairs, the six-integer/six-float Swag ABI with
  no caller shadow space makes `bench/src/swagnat/csvagg.swg` about 14.6% slower than
  the preceding ABI (median candidate/baseline). The application returns the same
  checksum. Seven application benchmarks and sixteen no-inline call signatures were
  also compared; CSV aggregation is the largest confirmed application regression.
- Rebuilding both compilers with the identical module name `csvagg` in separate
  output directories still gives a median 8.9% regression over eight paired runs
  at the original 400,000 rows. With only `ROWS` changed to 4,000,000 and an
  identical `csvagg4m` module name, the candidate instead improves by 4.7% over
  six paired runs. Both sizes must be kept in the performance gate: the larger
  working set does not invalidate the smaller workload's regression.
- The old ABI compiled with the new convention-independent backend passes is at
  parity with the preceding compiler over six pairs (median about 0.99). A temporary
  32-byte pad in the caller's body frame leaves CSV about 8% slower. Aligning native
  functions to 64 bytes leaves it about 10% slower. A temporary independent-bank ABI
  with 32 bytes of call shadow is near parity on CSV, but makes alternating six- and
  eight-argument calls about 5% and 4% slower in the call matrix. None of these
  experiments is part of the retained implementation.
- The emitted Micro instructions in CSV's hot loop are essentially identical after
  accounting for stack offsets. PDB-assisted disassembly shows the hot loop's
  machine instructions are also essentially identical; its address and the
  frame offsets change. Aligning loops with at least 64 Micro instructions to
  32 bytes lowers CSV's median regression to about 1.6% but makes some mixed
  call cases about 4–6% slower. A 128-instruction threshold puts CSV at parity
  but makes mixed calls up to 7% slower. Restricting alignment to large nested
  loops makes CSV more than 15% slower. These heuristics were reverted.
- Next: use hardware counters to distinguish instruction fetch, branch, and
  memory-alias effects before changing native code layout or call-frame policy.
- Complete when: the shadow-free ABI no longer regresses CSV in repeated paired runs,
  the call matrix remains at least at parity, and the broader native/JIT/app tests pass.

### compiler.optimization.039 — Nothing measures how close a function comes to the sweep budget

- Recorded: 2026-09-16 12:12
- Updated: 2026-09-26 17:47 — Validated later prompt-4 backend workspace savings in Release.
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
- 2026-09-26 Release diagnosis: the budget is now 24. `Slice.predictIntraPlane` in `std/video`
  still mutated on sweep 24 with both the current compiler and an earlier unmodified master.
  Temporarily allowing 80 sweeps showed 29 changing sweeps followed by a stable thirtieth;
  this was a finite chain, not oscillation. The induction-variable pass reduced only one natural
  loop per call, forcing the whole pre-RA pass battery to run between independent loop reductions.
  Reducing distinct loops inside that pass, with a local 32-round bound and a fresh CFG per
  reduction, lets this function converge under the unchanged 24-sweep budget. Each loop is
  processed at most once per invocation, preserving the product-before-sum ordering protected by
  the C++ pass tests. The `video` module's 117 tests, 3,481 native tests, and 1,500 JIT tests
  passed on this refined form. This resolves the observed outlier; it does not measure the full
  distribution.
- Five order-alternated pairs against the exact previous master `a5a2414b2` gave candidate /
  parent medians of 3,875 / 3,638 ms for core rebuild, 59 / 985 ms for no-op, 3,528 / 8,051 ms
  for core touch, and 215 / 207 ms for hello build. Both binaries suffered unrelated load spikes:
  a parent touch took 24 s, a candidate rebuild 12 s, and no-op runs reached 687 ms candidate
  and 1,907 ms parent. The final quieter pair was near parity (2,829 / 2,827 ms rebuild). These
  observations establish no percentage speedup or regression.
- The integrated Release campaign passed repository checks, compiler suites, 3,481 native and
  1,500 JIT tests, workspace tests, and built every standard module including `video`; it stopped
  while executing `std/pixel` tests when `swc.exe` crashed with `0xC0000005`. The exact parent
  reproduced the crash after tuning the same 6,580 functions. A GUI test fixture also needed
  its property attribute qualified as `#[Properties.ReadOnly]` after the runtime added a
  same-named attribute. Manual continuation then passed all 783 `std/gui` tests, 117 `std/video`
  tests, 479 reference tests, every script smoke, and the first 228 application tests.
  `Swag Scope` then stopped in semantic analysis on a forward
  `arDecimalAt` reference. The examples smoke stopped when `pixel4` exhausted memory in polygon
  cleanup; the parent also grew beyond 100 GiB of committed memory in the same smoke and was
  stopped to protect the shared machine. These failures limit whole-repository validation and
  are not evidence of a regression in this optimization.
- 2026-09-26 follow-up: the `arDecimalAt` failure came from macro-injected caller code resolving
  file-private symbols against the macro's source file. Lookup now uses the identifier's source
  file namespace when it differs from the active AST; all 23 focused `Swag Scope` Release tests
  pass. The `pixel4` memory growth came from a malformed RoundAnchor/SquareAnchor stroke: its
  starting point became zero and created a huge diagonal polygon. A Pixel regression checks the
  generated vertices; all 571 Pixel Release tests pass in JIT and native execution, and the
  `pixel4` Release smoke completes. The separate window-close panic was fixed by releasing the
  render context before Win32 destroys the window; manual close exits normally.
- A temporary counter in the Release compiler recorded 29,205 pre-RA optimization-loop calls
  during `bin/std` `--rebuild` with six workers. The count includes the final unchanged sweep:
  median 3, 90th percentile 5, 95th 6, 99th 7, 99.9th 10, and maximum 15 (two functions).
  Sixteen functions needed more than ten sweeps; none exceeded fifteen. The current 24-sweep
  limit has nine sweeps of headroom on this corpus. The counter was removed after measurement;
  DevMode and other consumer workspaces remain unmeasured.
- Later prompt-4 batches avoid a boolean-fusion scan without an immediate compare, count only
  queried virtual definitions in the sanitizer, defer its call-target, diagnostic, released-location
  and escaped-object containers, and retain live-slot, visit, block-index and register-position
  storage across functions. The CFG no longer clears edge lists it is about to discard. These are
  equivalent-work allocation and traversal savings; the shared machine has not yielded a stable
  whole-build percentage. The latest Release candidate passed 3,481 native, 1,500 JIT and 781
  `std/core` tests. After the dense-register change, all 12 standard modules built; the combined
  test run first stopped once on an undiagnosed `CodeGen` error in `core`, which then passed alone
  and in the next combined run. That run stopped in `pixel` with `0xC0000005` at `ntdll+0x1ff2a`;
  the exact pre-campaign parent had crashed at the same offset earlier that day. Separate `gui`
  and `video` runs passed 783 and 117 tests before the two latest workspace changes. A five-pair
  four-workload timing attempt was stopped after unrelated load stretched one core touch to 30 s;
  the shorter A/B screens establish no percentage claim.
- The 2026-09-28 prompt-4 continuation moved the allocator's control-flow check into its
  existing use/def collection walk and removed a duplicate clearing of the same instruction
  buffer. This removes a separate instruction walk for functions without an early label or jump.
  The Release compiler passed 20 focused native and 17 focused JIT register-allocation tests,
  then 3,483 native and 1,500 JIT tests on the merged master source. Timing was not measured.
- A follow-up removes four per-instruction clears in allocator liveness collection. `clearState`
  destroys the old per-instruction lists before the collection resizes them, so every new list
  is already empty. The focused Release register-allocation file passed 20 native tests, followed
  by 3,483 native and 1,500 JIT tests. Timing was not measured.
- Post-allocation upper-half analysis now resizes its slot table without zeroing old entries.
  Both acyclic and cyclic CFG paths overwrite every live instruction slot before any caller asks
  for it; callers use live references while rewrites are still queued. This removes one
  slot-count fill per analysis after the table first reaches that size. Four focused native Release
  zero-extension tests passed, followed by 3,483 native and 1,500 JIT tests. Timing and peak
  memory were not measured.
- `MicroStorage::allocNode` no longer resets a node after obtaining it. A fresh slot is already
  default-constructed, and `erase` resets a recycled slot before it enters the free list. This
  removes one `Node` assignment per allocated micro-instruction slot. The focused Release
  register-allocation file passed 20 native tests, followed by 3,483 native and 1,500 JIT tests.
  Timing was not measured.
- `MicroBuilder::addInstructionWithRef` no longer placement-constructs operand entries after
  `MicroOperandStorage::emplaceUninitArray` has resized its `std::vector`. The resize already
  default-constructs every operand, including its `ApInt`; this removes one duplicate construction
  per emitted operand without changing its initial value. The focused Release `slp_vectorize`
  file passed 17 native tests, followed by 3,483 native and 1,500 JIT tests. Timing was not
  measured.
- Next: count DevMode sweeps and other consumer workspaces before treating the Release
  standard-library maximum as a general bound. If any function approaches 24, identify the
  pass chain that keeps changing it before raising the limit.
- Complete when: the sweep distribution over `bin/std` is recorded, and the budget is either
  justified by it or replaced by what the measurement shows is needed.
- Related: compiler.optimization.029, compiler.core.004.

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
- Complete when: static evidence explains which loop shapes should use direct
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
- Complete when: that search either identifies a genuine missed final-code shape
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
- Complete when: the cutoff or its replacement has non-benchmark profitability evidence and tests
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
- Complete when: the ordinary-loop cap has profitability evidence beyond ChaCha and a test for
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
- Complete when: the policy has static profitability evidence outside `bench/`.

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
- Complete when: the current gate or its replacement has static evidence outside `bench/` and
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
