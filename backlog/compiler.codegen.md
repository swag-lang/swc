# Compiler Code Generation Backlog

This file owns lowering, ABI handling, the Micro backend, register allocation, instruction selection, and emitted-code shape. Program transformations belong in [compiler.optimization.md](compiler.optimization.md); compilation speed and workspace orchestration belong in [compiler.build.md](compiler.build.md).

### compiler.codegen.001 — Reduce the PDF spill-slot regression to a standalone language test

- Evidence: `sinkFrameStoreIntoBranchTarget` once compared raw stack displacements across
  outgoing-call stack adjustments and erased a live spill store in `Pdf.parseContent`.
  Comparing entry-relative addresses fixed it, and the C++ Micro test
  `PostRAPeephole_SpillStoreSinkingTracksStackDepth` fails without that fix. No source under
  `bin/unittests` does: Core-only and two-loop reductions change register allocation and no
  longer place the two loops' spills at the conflicting adjusted displacements.
- Next: reduce the interacting loops and their register pressure while checking the pre-fix
  post-allocation instruction stream, then keep a native suite case that fails without the
  fix.
- Done when: `bin/unittests/native` reproduces this stack-depth aliasing independently of
  GUI, alongside the existing C++ regression and PDF consumer tests.

### compiler.codegen.002 — WebP's macroblock reconstruction takes seconds to generate and holds back `pixel`

- Evidence: in 16-worker DevMode `gui` rebuilds, the longest code-generation job is one WebP
  function, `Pixel.Webp.decodeLossy` or `Pixel.Webp.vp8Reconstruct` depending on the run, 3–8 s in
  one slice. The `pixel` module's first code-generation round lasts exactly that long: the round is
  bounded by one job, not by when it starts. Per-pass timing on `decodeLossy` (DevMode, six
  workers) spreads about 4 s over the whole pipeline — register allocation 0.8–0.9 s in one run,
  branch-simplify 0.7 s, instcombine 0.5 s, const-fold 0.5 s, copy-elim 0.4 s, most pre-RA passes
  running eight or nine times — so no single pass misbehaves; the function is simply enormous.
  `vp8ReconstructMacroblock` runs two 4×4 loops that call `vp8Predict4` and `vp8InverseDct4`;
  single-call auto-inlining (`K_AUTO_INLINE_LAST_CALL_COST`, 4 096 tokens per callee, no cap on
  the caller's growth) folds the whole chain into its caller, and unrolling then repeats it sixteen
  times. Code generation now enqueues functions largest first, estimated from their own size plus
  what semantic analysis inlined into them, which removes late starts but not this length.
- Next: bound the growth a caller may receive from last-call auto-inlining and from unrolling
  loops whose bodies contain inlined calls, then compare WebP decoding speed and `pixel` build time
  before and after with the benchmark harness.
- Done when: no single function's code generation in `bin/std` takes more than a tenth of its
  module's wall time at 16 workers, without a measurable loss in WebP decoding speed.
- Related: compiler.build.069

### compiler.codegen.003 — Build shared libraries to identical bytes

- Evidence: executables, static libraries and the benchmark tasks rebuild identically with six
  workers; `core.dll`, `pixel.dll` and `gui.dll` still differ. Two sources remain. The set of
  generic instances varies: one build of `core.dll` emits one more `Core.Math.max` instance than
  the next, and a shared library emits every instance its analysis created. And `.rdata` holds a
  duplicated 16-byte string constant in some builds only: `Core.Env.showInFileExplorer` reaches
  three such constants in one build and two in the next. The machine-code cache keys ignore
  both string copies and global placement; the varying instance set alone still adds one or two
  records per six-worker `core` build.
- The generated GUI API also varies: `Lens.View.create(owner: *Wnd)->*View` exports a
  `BorrowSummary` return mask of zero in one frozen-input control and one in other captures,
  including captures without the allocator experiment. This is semantic metadata, not an image
  timestamp; retain it in reproducibility comparisons. See the
  [memory experiment](../bench/results/memory/20261030-devmode/no-large-pages-experiment.json).
- Linux DevMode control with three workers and frozen `std` sources: the native location sort
  assigned the same key to distinct generic struct and constant-function instances. Including
  both sets of arguments removed those collisions; only cloned local `isLowerUtf8` and
  `isUpperUtf8` functions retained equal keys in `core`. A second source of variation was the
  completion order of interface implementations in reflection: `Core.Hash.IHash32` and
  `Core.StrConv.IConvert` swapped table slots and relocations between builds. Sorting the
  reflection copy by full interface name removed that swap. A third source was the order of
  static candidates for `Swag.makeInterface`: two generated checks in `StrConv.convertStruct`
  exchanged their typeinfo pointers and CRCs. Candidates now sort by full type name before
  code generation. Five subsequent `core.so` builds matched, but an earlier three-build control
  with this candidate sort still produced two hashes. `truetype.so` and all generated API files
  matched in a full two-build control; `ogl.so`, `pixel.so` and `gui.so` still differed.
- Next: trace when `Lens.View.create` acquires its return-borrow mask and whether export observes
  completed callee effects. Log which call sites create `Core.Math.max` instances in two builds and find the
  speculative instantiation; then trace the `showInFileExplorer` string constants back to
  `materializeRuntimeStringConstant` and `materializeRuntimeBufferConstant` to see which cache
  lets one value materialize twice. Compare the remaining Linux `ogl`, `pixel` and `gui`
  section deltas before assuming they share the Windows causes.
- Done when: rebuilding `core`, `pixel` and `gui` twice with six workers produces identical
  shared libraries apart from the image timestamp.

### compiler.codegen.004 — A null-valued string enum case aborts code generation

- Evidence: with `enum State: string? { Absent = null, Ready = "ready" }`, a runtime
  `switch state` with `case .Absent` and an explicit `default` aborts in
  `CodeGen::emitConstant`, which asserts `isStruct()` on the case constant.
  The failure predates implicit enum exhaustiveness.
- Next: reduce enum constant lowering for a nullable string to one source fixture. Trace
  the null representation from the enum constant to case comparison and preserve its
  storage type through lowering.
- Done when: matching a null-valued enum case reaches code generation without an
  assertion, and JIT and native tests exercise the declared case, a present value,
  and the explicit fallback with the documented string comparison rules.

### compiler.codegen.005 — Keep hot SIMD values out of the frame

- Evidence: `Video.H264.mcChroma`, `Hevc.Decoder.filterLumaEdge`, and `Hevc.Decoder.interpolateLuma` have had frame traffic in their hot loops. Previous measurements predate the split allocator and are no longer a current baseline.
- Next: dump the current Release functions and measure per-segment time. Attribute each remaining spill to register pressure or a missed allocation/hoist opportunity before changing the backend.
- Done when: current evidence identifies a profitable change with byte-exact decoder output, or shows the remaining frame traffic is necessary and the entry is removed.

### compiler.codegen.006 — Extend carried-slot promotion beyond private 64-bit spills

- Current boundary: post-allocation promotion caches private 64-bit spills across eligible loops,
  including call and shared-exit cases when entry seeding, clobber handling, and write-back are
  proven. Mixed-width and source-object slots remain outside the rule.
- Evidence: retained codec rewrites show fewer hot-loop frame operations without extra pushes;
  detailed per-function diffs and correctness results are in the linked generated-code reports in
  Git history. No runtime speedup has been established.
- Next: inspect hot source-object slots and mixed-width spills. Any extension must prove reuse on
  each call-delimited path and account for aliases, exits, and write-back.
- Done when: current codec dumps identify and resolve the remaining promotion boundary with
  aliasing, exit-path, and reference-frame coverage; do not repeat the completed private 64-bit
  multi-access rewrite.
- Related: std.video.005, compiler.codegen.005, compiler.optimization.020.

### compiler.codegen.007 — Improve spill choices after register and memory promotion

- Evidence: after removing the permanent integer legalization reserve,
  `Slice.parsePlaneResidualCabac` gained one memory operation and
  `Slice.parsePlaneResidualCavlc` gained six plus thirteen instructions.
  The full register pool remains available; the
  [retained comparison](../bench/disassembly/generated-code/20261006-legalize-reserve/README.md)
  owns the exact baseline.
- Additional case: promoting whole-copied locals with scalar lane reads removes
  frame traffic in ChaCha, nbody and H.264. In CSV data generation, a copied region
  string's pointer/length become GP values live across several multiplications.
  The printed bodies gain 18 instructions / 11 memory operations, 14 explicit
  RSP accesses and 64 frame bytes. The suffix from the first timing call remains
  444 instructions / 151 memory operations, and the checksum remains 24828641.
  [Allocation diff](../bench/disassembly/generated-code/20261006-vector-lanes/csvagg-allocation.diff).
- Next: inspect splitting and rematerialization around the implicit multiply
  claims in CSV setup, and compare the two H.264 functions' interval choices.
  Preserve the extra register and legal packed promotion while correcting these
  local allocation costs. No elapsed-time regression is inferred.
- Done when: these local increases are removed or explained by a necessary tradeoff.

### compiler.codegen.008 — Defer callee-saved XMM traffic past an early exit

- Evidence: MSVC avoids saving and restoring four XMM registers on `raytrace`'s no-hit path by
  saving them only after the early guard. Swag's native and JIT unwind interfaces currently publish
  one range per function/allocation, so delayed saves cannot yet describe every path correctly.
  The save slots must remain in the entry frame and each return path needs the matching unwind state.
- Next: represent chained unwind ranges in `MachineCode`, emit them from the final instruction
  stream, and publish all ranges in native `.pdata` and the JIT function table. Then delay only saves
  for registers first defined below the guard. Cover both arms, nested calls, and exceptional unwind
  in native and JIT output; compare hit and no-hit paths with MSVC.
- Done when: the short path skips unused saves and restores without adding spill traffic to the hit
  path, and unwind and ABI checks pass; otherwise keep the current eager save plan.

### compiler.codegen.009 — General value-web normalization still extends live ranges too far

- Intent: give independent def-use webs separate virtual registers so LICM, value numbering
  and memory forwarding can distinguish computations that lowering gave the same name.
  Live phi joins and destructive updates must retain a common name. Dead phi cycles must not
  glue otherwise independent values together.
- Existing boundary: the unroller already renames independent temporaries in straight-line
  copies, but leaves carried values and bodies with internal labels unchanged. A flattened
  nested loop can therefore still contain independent values sharing a register.
- Evidence: a union-find reconstruction over SSA values, with live phi and read-modify-write
  unions, worsens unrelated floating code under interval splitting (raytrace `intersect`
  and `trace` gain instructions, memory operands and frame references) and was discarded.
  Splitting only a reused register whose stored old value is later read leaves raytrace
  unchanged and enables nbody's cross-group velocity forwarding;
  it is not a general policy for arithmetic temporaries.
- Next: attribute the extra floating interference and improve residency before expanding
  eligibility beyond a concrete store-to-load forwarding opportunity. Recheck the deblock
  consumer and raytrace alongside any broader rule; do not infer a win from renaming alone.
- Done when: independent webs expose the intended hoisting and forwarding without
  worsening the affected hot paths through additional transfers or spill traffic.
- Related: compiler.codegen.006.

### compiler.codegen.010 — Retain one floating zero across unrolled arms

- Evidence: MSVC's unrolled four-sphere raytrace `intersect` clears XMM5 once and compares
  each discriminant against it; Swag's clears XMM9 before each of the four comparisons,
  three extra executed instructions. The full unroller renames private temporaries only in
  bodies without internal labels, so `intersect`'s copies reuse one virtual zero register,
  overwritten before the next clear. These attempts all kept the four clears: naming the
  zero in source, sharing dominating `ClearReg` definitions in value numbering, and renaming
  single-definition private values in branched unrolled bodies (which also added four
  instructions).
- Next: inspect a control-flow-aware way to split a private zero definition across cloned
  arms. A candidate should retain a single zero only where that saves executed clears
  without adding copies, spills, or saved registers. Compare an unrelated unrolled floating
  loop and a case with intervening calls before changing general value numbering or
  allocation.
- Done when: the repeated clears disappear with no new spill traffic in `intersect`, an
  unrelated case improves under the same rule, and native/JIT behavior remains correct.

### compiler.codegen.011 — Retain the probe mask without increasing spills

- Evidence: a post-allocation rule (`PostRALoopHoist`) moves a folded bitwise memory operand
  into an idle, already saved register when the base is stable, the loop has no memory
  writes and only `ReadOnly` direct calls. In wordfreq's first inlined probe `r15` now
  carries the mask across `memcmp`, matching LDC's two memory operands on the collision
  step. The final-token probe still reads `[m+mask]` because its entry read uses a
  different base expression. Csvagg's eight region keys never collide modulo 64, so
  retaining its mask would only add an entry instruction.
- Rejected: hoisting every invariant field load across a read-only call, and inlining
  `mapInit` to expose the mask constant. Both enlarged the probe or `main` with spills,
  frame reloads and jumps.
- Regression lead: [protocol 3 csvagg samples](../bench/results/windows/20261021-173259.json) put
  native Release at a 22.694 ms median against Odin's 20.861 ms. Earlier protocol 2 reports
  selected minima, so their displayed advantage is not a paired regression measurement.
  The preserved October 12 and October 19 timed row loops have 194 instructions and 60
  memory operands, including indexed extensions; the current loop has 191 and 57. The
  byte-scan loops retain their instruction and memory counts. This narrows the lead to
  executed dependencies, callees, emitted layout or measurement rather than a larger row loop.
- Next: compare wordfreq's complete probe paths and measure its retained mask at a clean
  paired campaign milestone. For csvagg, compare the successful `memcmp` and occupied-slot
  update with Odin's executed path, focusing on dependencies, register and frame traffic;
  inspect emitted layout against the preserved compiler before attributing the reported
  slowdown to an optimization pass. Use the twelve-task static comparison for each candidate.
- Done when: a focused rule retains the mask without increasing spill traffic and improves
  paired wordfreq runs, or measurements show that retaining it is not profitable; csvagg's
  reported gap is attributed to an executed-path difference or a measurement effect.

### compiler.codegen.012 — Reuse one relocation base for indexed constant arrays

- Evidence: C++/MSVC's raytrace `trace` function materializes one image base with `lea rdi, [__ImageBase]` and reads eight distinct constant arrays through indexed memory operands. Swag's Release Micro for the same function uses eight `LoadRegPtrReloc` instructions followed by eight indexed loads, four for `SRAD`/`SCX`/`SCY`/`SCZ` and four for `SR`/`SG`/`SB`/`SRE`: 16 instructions for those reads versus MSVC's nine. This is an instruction and address-dependency gap, not a timing claim about an edit.
- A post-allocation rewrite that keeps the first array pointer and adds source-address differences to later loads is invalid for native artifacts: `NativeRDataCollector` emits only reachable allocations and may compact the gaps between them. JIT constants are resolved from shard and offset at patch time. Each indexed consumer therefore needs a relocation relative to a reusable segment or image base, or an equivalent layout contract that survives both backends. The existing emitter binds only RIP-relative scalar accesses, not indexed displacements.
- The native linker already understands `IMAGE_REL_AMD64_ADDR32NB` as an image-relative `Rva32` relocation, but code emission has no base-relative indexed relocation form, and the internal linker does not expose `__ImageBase` as a code symbol. The JIT's 2 GiB proximity arena can host code and constant shards together; its exhaustion fallback needs an explicit range or copy strategy for any base-relative displacement. In `trace`, the transient pointer register is clobbered by the intervening `intersect` call, so reusing that register alone yields at most two four-array groups. One base across both groups requires an allocation and callee-save decision.
- Folding a scalar indexed load into each floating operation is not an independent instruction saving here. Swag's load plus AVX three-register `fsub`/`fmul` is two encoded instructions; MSVC's copy plus memory-form SSE operation is also two in the corresponding `SCX`/`SCY`/`SCZ` and colour paths. The existing post-RA fold requires the destination to hold the left operand because the memory-form SSE instruction overwrites it. Adding a copy to force that fold would leave the instruction count unchanged and add a copy dependency.
- Next: design and validate a relocation-aware indexed displacement against one reusable base in JIT and native output. Compare eight-array code with MSVC; include unrelated arrays in different allocations and shards, a library artifact, and a negative case whose address cannot share the base. Account for register lifetime across the intervening call and JIT arena exhaustion before selecting the base.
- Done when: indexed reads of separate immutable arrays reuse one base without relying on source allocation spacing, pass JIT/native relocation checks, and close the eight-materialization gap without extra spills.

### compiler.codegen.013 — Keep unsigned 64-bit float conversion branchless in hot loops

- Evidence: Swag lowers `u64` to `f64` branchlessly with a packed low/high-32-bit conversion
  and two vector constants (`CodeGen.Cast.cpp`). MSVC uses a signed conversion on the
  common lower half and a shift/or/double fallback for values with the high bit set. Both
  execute five instructions on csvagg's common path. MSVC's formula, tried in Swag, stayed
  exact but added eight static jumps to csvagg's timed row loop and a conditional plus an
  unconditional jump to every conversion. It was reverted.
- Next: find a range proof that a conversion input stays below `2^63`, or a branchless
  lowering that uses fewer operations and less XMM pressure than the current packed
  conversion. Compare both sides of the range and an unrelated cast before revisiting the
  lowering.
- Done when: a general rule improves the complete hot conversion path without extra
  branches or spills, and preserves full-range nearest-even results in native and JIT
  output; otherwise retain the current branchless algorithm.

### compiler.codegen.014 — Mixed scalar calls slow down with six independent argument lanes

- Evidence: the Swag convention passes up to six integer and six floating arguments in
  independent banks, the floats in transient XMM0-XMM5 (`CallConv.cpp`). A no-inline
  microbenchmark measured on an earlier bank layout found alternating six-`u64`/six-`f64`
  calls slower than under the former positional convention, while six-integer and
  six-float calls got faster. Register count alone did not explain the floating-body cost.
  Assigning floating arguments by signature position restored mixed-call speed but gave
  up independent floating lanes. The move to transient XMM0-XMM5 has not been timed on
  those signatures.
- Next: compare the mixed-call signatures and the seven tasks in a paired campaign with
  the current float bank; isolate any signature or task that regresses.
- Done when: repeated paired runs put the mixed calls at parity or better and the
  six-integer and six-float gains remain.

### compiler.codegen.015 — Finish the AVX boundary cost and caller-state audit

- Evidence: native, JIT, foreign-return and callback dirty-AVX-state probes match
  clean-state results and performance after the boundary fix
  ([evidence](../bench/disassembly/generated-code/20261006-avx-vex/README.md)). Two things are
  not established: which AVX state reached the unmodified benchmark when its timing
  changed, and the compiler cost of the boundary handling.
- Next: at a measurement milestone, check the compiler cost of the boundary handling and
  establish which AVX state reaches the unmodified benchmark. Do not repeat the completed
  encoding work.
- Done when: the unmodified caller-state question is resolved and compiler cost is assessed.
- Related: compiler.optimization.121, platform.portability.103.

### compiler.codegen.016 — Drop the default clear of a value built in the return slot

- Evidence: a struct literal or a defaulted local built in the caller's storage first clears it,
  then stores every field: `return P{a: x, b: 2, c: 3, d: 4, e: 5}` emits two 16-byte zero stores
  that the field stores overwrite. On a stack slot the dead stores disappear; through the hidden
  return pointer they stay, because the optimizer removes dead stores only on frame storage.
- Next: remove a store fully overwritten before any load, call, or escape of the same base address,
  whatever that base is, or skip the clear when the literal names every field and the type has no
  padding.
- Validation: include the native Scope video consumer after complete dependency rebuilds. A
  full-coverage literal prototype passed the language suites but did not establish a reliable
  asynchronous-consumer comparison; isolate that behavior before enabling clear removal.
- Done when: the literal above and a local of the return type filled field by field write each
  byte of the slot once.

### compiler.codegen.017 — Reduce reflection metadata and absolute-pointer relocations in native images

- Evidence: a Release Swag Capture image contains 132,370 distinct base-relocation sites;
  110,541 are attributed to runtime reflection metadata. Live type descriptors retain their
  complete reflection closure even where runtime code only needs identity or dispatch.
- Next: trace reflection demand from retained code through constants and imported functions.
  Discard undemanded metadata edges before extracting their allocation and callback closures,
  then attribute the remaining roots before considering graph interning or a runtime ABI change.
- Done when: only demanded reflection metadata survives across module and executable boundaries,
  substantially reducing metadata and relocation size while preserving type identity, reflection,
  serialization, dynamic dispatch, lifecycle callbacks, rebased loading, and native/JIT behavior.
  Measure compiler CPU time and memory as well as image size.

### compiler.codegen.018 — Measure the runtime-symbol opt-out on Windows images

- Evidence: `--no-runtime-symbols` omits the `.swagdbg` runtime stack table independently of native
  debugger information. ELF executable and shared-library checks cover clean and incremental
  switches, file sizes, panic output and static-library frames. A Release PE size comparison remains
  unmeasured; a Linux cross-target attempt stopped at unresolved `TlsSetValue` without Windows API
  link inputs.
- Next: build the same Release executable and shared library with and without the flag on a Windows
  link host, compare file and `.swagdbg` sizes, then check default stack frames and static-library
  consumers after incremental switches in both directions.
- Done when: the opt-out is measured on a Release PE as well as ELF, while the default retains runtime
  frames and static-library consumers keep composing them.

### compiler.codegen.019 — 256-bit vectors are not expressible

- Next: extend the type constructor to 32-byte geometry (`#simd [32] u8`, `#simd [8] f32`) gated
  on AVX2, with YMM registers, 32-byte spills/constants/alignment, operators, intrinsics, arguments,
  returns, type information, cross-module exports, and matching `Math.Simd` aliases.
- Done when: every supported 32-byte shape compiles and runs, crosses a module boundary, and
  128-bit code generation remains byte-identical when the wider path is not selected.
- Related: platform.portability.103, compiler.codegen.023.

### compiler.codegen.020 — 512-bit vectors and AVX-512 masks have no representation

- Next: add 64-byte `#simd` shapes, ZMM register allocation, and explicit predicate-mask values
  for AVX-512 targets without making AVX-512 a baseline requirement.
- Done when: arithmetic, comparison, masked load/store, calls, spills, constants, reflection,
  and cross-module use work behind feature gating, with the x86-64-v3 baseline selected on
  supported machines that lack the optional feature.
- Related: platform.portability.103, compiler.codegen.019, std.core.043, std.core.044.

### compiler.codegen.021 — Packed integer division and modulo have no portable lowering

- Next: define integer lane division/remainder semantics and implement constant-divisor strength
  reduction plus a profitable target-independent sequence or explicit fallback, instead of treating
  the absence of one machine instruction as a permanent operator restriction.
- Done when: signed/unsigned lanes, zero divisors, `Min / -1`, constant and variable divisors,
  constant folding, and runtime execution have one documented contract and the cost model declines
  transformations that would lose to scalar code.
- Related: std.core.050, std.pixel.040, std.pixel.042.

### compiler.codegen.022 — Dot products have no VNNI form

- Next: select the VNNI dot-product instructions where the host has them. Unsigned and signed
  byte SAD (`psadbw`), the 16-bit pairwise product (`pmaddwd`) and the unsigned/signed byte
  product (`pmaddubsw`) are the baseline forms and are already selected.
- Done when: a VNNI accumulation is chosen on a host that reports the feature, the baseline
  sequence still runs everywhere else, and both answer the same on the differential tests.
- Related: platform.portability.103, compiler.codegen.023, std.core.052, std.pixel.041, std.pixel.image.054, std.pixel.image.055.

### compiler.codegen.023 — Packed code generation misses idiomatic hardware forms

- Intent: complete dynamic lane insertion and extraction and prove the remaining 64-bit lane constructions.
  Immediate lane shuffles, horizontal reductions and SAD already lower through dedicated
  operations. Under `backend.math.fma` (on in `release`), a post-RA peephole contracts eligible
  scalar and packed product accumulations when the product is otherwise dead in every lane;
  packed contraction also requires `backend.math.noNaN`. Explicit scalar and vector `Swag.mulAdd`
  preserve separate multiply and add rounding, including when contraction is enabled.
- Evidence: a constant lane read of a register-resident vector never touches the frame. A 32- or
  64-bit lane is a `movd`/`movq`, through one `pshufd` past lane zero; an 8- or 16-bit lane slides
  down by bytes (`psrldq`) and leaves through the same move, extended from its own width. A
  constant lane written into a vector local is one `vpinsrb`/`vpinsrw`/`vpinsrd` where it was a
  sixteen-byte spill, a narrow store and a wide reload stalled behind it.
  `bin/unittests/native/simd/lanes.swg` covers signed and unsigned narrow reads and all four
  insertion widths, including `vpinsrq` when a whole stored vector is updated. A trial that also
  built vectors from two qword stores changed H.264 output; those stores can form slices and other
  scalar aggregates, so that broader rewrite is not retained without a stronger proof. Every
  dynamic index still goes through the frame: `v[i]` spills the vector and reads `[rsp + i * 4]`,
  `v[i] = x` spills, stores the lane and reloads sixteen bytes.
- Next: isolate the two-qword aggregate failure and prove its alias and lifetime conditions;
  lower a dynamic lane read through a byte shuffle with a computed control where that beats the
  spill, preserving the explicit `mulAdd` rounding contract.
- Done when: encoder tests and `PrintMicro` show each idiom on a representative standard-module
  kernel and end-to-end benchmarks show no regression on the fallback target.
- Related: compiler.codegen.022.
