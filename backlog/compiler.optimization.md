# Optimization Backlog

This file owns transformations of Swag programs: local and intermodule analysis, specialization,
inlining, loop optimization, profile feedback, and final program layout. It does not track the
speed or memory use of compiling swc; that belongs in [compiler.build.md](compiler.build.md).
Lowering, ABI, register allocation, and instruction selection belong in
[compiler.codegen.md](compiler.codegen.md).

The intermodule program below applies to **every Swag module whose matching implementation is
available locally**: application modules, sibling workspaces, vendored dependencies, package
caches, third-party checkouts, and the standard library. Availability and semantic proof decide
eligibility; origin, license, module name, and installation path do not. An open-source dependency
benefits because its implementation can be analyzed. A proprietary dependency supplied with source
gets the same benefit. No transformation in this program may require a `std` whitelist or a
library-specific name match.

Source availability and a closed set of callers are separate facts. A body can be available for
optimizing a known direct call while exports, plugins, callbacks, or a replaceable shared library
still prevent whole-program assumptions. Preserve a canonical externally callable version wherever
the boundary requires it. A local file with the same module name is not proof that it implements
the binary selected by the build. Other-language sources require a supported frontend or compatible
optimization representation; merely finding their text does not make them Swag bodies.

The intended optimization pipeline is resolved typed bodies and summaries, global symbol/call resolution,
then bounded interprocedural transformations. ABI lowering, the Micro pipeline, and instruction emission
belong to [compiler.codegen.md](compiler.codegen.md). Reuse semantic analysis and local passes. Keep compile-time execution as
a separate consumer of the resolved program; importing a body must not re-execute module setup
or compile-time side effects.

These waves express dependencies, not promises of measured speedups. Each entry owns an
independently finishable outcome and stays here while its next outcome remains open.

| Wave | Deliverable | Entry identifiers |
| --- | --- | --- |
| Foundation | Local implementation discovery, typed bodies, global index, incremental reuse | compiler.optimization.106, compiler.optimization.107, compiler.optimization.108, compiler.optimization.109 |
| First useful release | Effect summaries and automatic intermodule inlining | compiler.optimization.110, compiler.optimization.111 |
| Contextual optimization | Specialization, devirtualization, aggregate transport, allocation elimination, loop proofs, partial inlining | compiler.optimization.112, compiler.optimization.113, compiler.optimization.114, compiler.optimization.115, compiler.optimization.116, compiler.optimization.117 |
| Late code and data | Callee register contracts and whole-image liveness | compiler.optimization.118, compiler.optimization.119 |
| Measured deployment | Profile feedback and final code/data placement | compiler.optimization.120, compiler.optimization.121 |
| Advanced experiments | Partial evaluation, CPU variants, private data representations | compiler.optimization.122, compiler.optimization.123, compiler.optimization.124 |

For each implementation, select validation using
[validate-swag-changes](../.agents/skills/validate-swag-changes/SKILL.md). Import, publication,
identity, and cache cases belong in `bin/unittests/workspace`; runtime code shapes in `native`;
compile-time behavior in `jit`; guarded paths in `safety` or `sanity`; graph, cache, IR, ABI,
linker, and profile helpers in the corresponding C++ tests. Dedicated debug-information fixtures
opt into `--debug`. Scheduling/publication changes also exercise both compiler executables and
real parallelism.

Before the first transformation, establish baselines for small and large module graphs, deep wrapper
chains, diamond dependencies, recursion, generics, callbacks, aggregate returns, and mixed source,
binary, and shared dependencies. Include a standalone third-party workspace outside `bin/std`.
Compile equivalent eligible modules under different names and roots, including a read-only package
root, and require equivalent decisions after path normalization. Synthetic cases prove decisions;
representative applications measure value.

Record runtime distributions, text/data size, startup and allocation counts where affected, cold
and warm build wall/CPU time, peak committed memory, imported-body counts, and incremental
invalidation fan-out. Compare enabled/disabled transformations with identical inputs/compiler
builds, unchanged-binary controls, and alternating runs on a quiet machine. Set explicit code-growth,
compile-time, and memory budgets from those baselines before default rollout; instruction-count
reductions alone do not establish a performance win. Measure a private helper edit, public signature
edit, unrelated edit, and profile change separately.

Expose deterministic decision records: unavailable/incompatible body, open binding, unsupported
semantics, insufficient benefit, exhausted budget, imported body, selected clone, and invalidating
dependencies. Preserve source/inline provenance, stack walking, diagnostics, cleanup, error
propagation, evaluation order, and effective safety/sanity/FP contracts. Optimization level must
not change which source programs are well-typed. Cheap proven transformations should become normal
for eligible modules; costly experiments stay selectable until measured. Keep existing `Never`,
`Inline`, and `NoInline` contracts explicit. This plan invents no command-line spellings or
new language syntax.

SIMD work is owned by the compiler, platform, or consuming module according to the change. Consumer kernels keep a scalar fallback, prove boundary and tail parity, and compare Release performance.


### compiler.optimization.126 — Preserve nullable value-pointer types in automatic inline bindings

- Evidence: nullable inline bindings retain their declared parameter contract, including widened
  non-null arguments and constants (`nullable_parameter_widening.swg`). Automatic eligibility
  still excludes nullable value-pointer wrappers with calls or postfix assertions; repeated
  single-site wrappers with nullable block pointers qualify. The inline frame also bounds flow
  facts so a callee assertion cannot change the caller's subsequent `unwrap value`
  (`inline_nullable_assert.swg`).
- Next: evaluate automatic nullable value-pointer eligibility without adding unnecessary homes
  or volunteering one-time setup. Broad nullable eligibility previously added frame
  loads and stores to an inlined scan. Inspect actual call-site conversions and use a nullable
  scan as a control.
- Done when: repeated wrappers with nullable value-pointer parameters auto-inline with their
  flow contract intact and no static per-iteration loss on reachable benchmark hot paths.
- Related: compiler.codegen.008, compiler.optimization.117.

### compiler.optimization.020 — Share the remaining frame alias proofs across memory passes

- Current boundary: LICM and SLP consume MicroPassHelpers::analyzeFramePrivacy.
  SLP additionally checks escape reachability so an escape after a loop does not
  invalidate its earlier private-frame proof. MemToReg now reconciles direct SP
  accesses with the captured frame using shared CFG displacement facts when SP moves.
  PostRALoopHoist still owns a separate frame-object reachability model.
- Next: reconcile the post-allocation object model with the shared proof without
  losing byte-range precision, including stable frame-derived pointer offsets
  and moving-SP paths, then use disjoint spaces in forwarding and value
  numbering. Inspect the four H.264 allocation changes caused by the necessary SP
  alias repair: applyMotion, deriveDirectTemporal, deriveDirectSpatial, parseSubMvs
  together add four instructions and five memory operands; preserve the repair.
- Done when: shared facts cover those consumers, forwarding crosses a proven
  disjoint store in a real codec loop, and remaining local allocation costs are resolved.
- Related: compiler.codegen.006.

### compiler.optimization.032 — Control register pressure in wider partial unrolling

- Current boundary: exact even loops too large to fully unroll can group two straight-line
  bodies, reusing the full unroller's temporary renaming and retaining counter updates and
  relocations. Calls, internal control flow and CPU-flag consumers remain outside the rule.
  Write-only private spill homes can use the existing free-XMM loop cache.
- Evidence: two SHA-256 rounds execute 95 instructions / four memory reads / zero frame
  accesses, against 100 / four / zero before, but whole `main` gains 42 instructions and
  six explicit RSP accesses outside that compression loop.
  A four-round prototype executed 180 instructions with a back-edge register copy and four
  frame stores per group: its three transient XMM registers for integer values left too
  few for all four write-only homes.
- Next: trace the remaining register-copy and store placement across four-round groups,
  and the six additional outer-loop frame accesses in the retained two-round form. Extend
  only with a joint allocation plan that preserves the now spill-free compression loop.
- Done when: wider grouping reduces per-round work without reintroducing hot frame
  traffic, and the retained two-round form's outer spill cost is resolved.
- Related: compiler.optimization.005, compiler.codegen.006, compiler.codegen.009.

### compiler.optimization.022 — An inlined by-value aggregate argument is copied even when the body only reads it

- Evidence: `materializeInlineBindings` binds a by-value aggregate argument to a concrete
  local. `classifyInlineBinding` can keep a direct binding, but an indexed or foreach
  by-value aggregate still requires a home through `use.indexOrFor`, even if those uses only
  read. Pure leaf inlines already borrow a plain array from a stable caller variable when
  every argument is a same-type bare variable or constant; parameter writes,
  addresses/buffers, captures, calls, generated source and nontrivial copy/drop types keep
  snapshots.
  A by-value `[4] U32x4` transpose inlined into a caller cost 40 instructions and a 0x1C8
  frame against 28 and 0x80 for the pointer form, which `Core.Math.Simd.transpose4x4` now
  takes. Read-only syntax alone does not prove the caller's storage stays unchanged while
  the inlined body runs.
- Next: extend the stability proof to larger/non-leaf bodies and argument evaluations that
  currently fail the conservative leaf/constant-or-variable boundary. Revisit the SIMD
  transpose with evidence from its actual caller, preserving copy/drop and alias semantics.
- Done when: the value-returning block transform is as cheap as its in-place shape on
  the video corpus, including bodies outside the retained pure-leaf boundary.

### compiler.optimization.005 — Investigate the remaining Levenshtein outer-loop allocation costs

- Evidence: the exact indexed load/store copy loop now has a four-way scalar unroll with the
  original loop retained as its tail. Leven's checksum is unchanged, but its full `main` grows by
  15 instructions and noisy paired samples do not establish a timing gain. Odin vectorizes the
  row-copy loop; Swag's SLP pass does not, and a general vectorization proof is still absent.
  A runtime overlap guard made longer straight-line copies legal after allocation, but
  Fannkuch slowed by 4.8% to 5.1% in independent paired comparisons despite fewer memory
  operations. Account for the guard, wide-store forwarding and critical-path costs; amortize
  an indexed-loop guard outside the repeated region rather than assuming packing alone wins.
- Next: reproduce the row-copy shape with current sources and inspect native code in a paired
  comparison. Keep the unroll only if measurements confirm the hot-path estimate without a loss; investigate SIMD
  separately with an alias/disjointness proof and cost model.
- Done when: outer-region accesses are eliminated or attributed to unavoidable carry
  initialization/lifetime costs while preserving any confirmed inner-loop gain.

### compiler.optimization.029 — Reduce SSA rebuilding after definition-changing and redirected-use rewrites

- Evidence: CFG identity and unchanged definitions now allow operand refresh and several analyses to
  reuse current SSA values, phi inputs, reaching definitions, and rename trees. Definition-changing
  rewrites still rebuild SSA; copy elimination is one remaining caller.
- Next: identify remaining rebuild callers at a measurement milestone. Any reuse contract must
  preserve reaching values, phi edges, duplicate uses, and visit order, with a safe fallback when a
  later instruction invalidates its assumptions.
- Done when: remaining rebuilds are reduced without changing generated code and a repeatable
  compiler-time gain is distinguishable from the measurement floor.
- Related: compiler.build.004, compiler.build.030, compiler.optimization.005.

### compiler.optimization.036 — Finish shared address folding and isolate its remaining allocation cost

- Evidence: late pre-allocation scheduling folds a single-use constant-offset address into
  indexed and ordinary memory operands. Cross-block candidates need an SSA proof that the
  base is unchanged.
  It costs `Slice.parsePartitions` three instructions and two memory operations. Shared
  addresses stay outside the single-use rule, including the context-array base at
  Slice + 0x98 that feeds four copies in `residualCabac`.
- Next: attribute `parsePartitions`' new spill choice, and consider shared-base substitution
  only when every use preserves the base and removing the address does not extend pressure.
  Keep the late stage so array promotion/vectorization retain their input shape.
- Done when: the local allocation cost is resolved or explained and profitable shared
  address cases have a bounded all-use proof.

### compiler.optimization.121 — Optimize final code and data layout with retained structure

- Evidence: local cold-block placement and loop alignment exist; the integrated linker owns
  final symbols/relocations and can retain function/block boundaries and profile edges
  instead of reconstructing them from an executable. DevMode `fannkuch` lost 7.14% when its
  `main` moved from RVA `0xaee0` to `0xafd0` with unchanged hot instructions. Blanket
  modulo-32 alignment (candidate `5d3338007`, not on master) recovered 5.10% on `fannkuch`
  but cost 4.50% on `binarytrees` and grew text by 3.32%, so the trial was discarded.
- Next: investigate selective alignment and repeat independent quiet blocks across native
  execution, compiler time/memory, and binary size with unchanged-binary controls. Then retain
  layout metadata through object/cache boundaries and reorder functions by weighted
  call locality with deterministic static fallback. Measure instruction-cache behavior and binary
  size before expanding to block splitting or data placement.
- Expansion: global hot/cold separation, constants near consumers, final-size/profile-aware
  alignment, and eligible branch relaxation/re-encoding once distances are known. Respect
  displacement limits and identity constraints; allow bounded feedback when final sizes change
  earlier profitability estimates.
- Output: update relocations, debug ranges/inline provenance, unwind/exception records, runtime
  symbol tables, and cached offsets together. Keep target-specific restrictions behind backend
  interfaces; deterministic placement needs stable global-data identities too.
- Elsewhere: [BOLT](https://github.com/llvm/llvm-project/blob/main/bolt/README.md) demonstrates
  profile-guided post-link layout. Its ELF implementation is a design reference, not a drop-in
  replacement for Swag's PE backend.
- Done when: large modular consumers have reproducible valid images and measured locality gains,
  stack-walking/debug fixtures pass, unprofiled builds retain useful placement, and runtime, size,
  startup, and build costs are evaluated separately.
- Related: compiler.optimization.118, compiler.optimization.119, compiler.optimization.120,
  compiler.codegen.003.

### compiler.optimization.107 — Preserve resolved bodies before ABI lowering

- Evidence: ordinary inlining clones and re-analyzes syntax in `SemaInline.cpp`. Automatic selection
  excludes generic and fallible functions and most aggregate signatures; all ordinary inline modes
  reject bodies declaring static storage.
  [CodeGenCallHelpers.Call.cpp](../src/Compiler/CodeGen/Core/CodeGenCallHelpers.Call.cpp) assigns
  concrete argument registers/stack slots through `ABICall::prepareArgs` before Micro passes.
- Next: prototype an immutable, typed, serializable scalar body with calls, parameters, returns,
  memory objects, and symbolic globals above the ABI. Compare a frozen resolved-body representation
  with a compact new IR on size and lowering cost; select the smallest correct design.
- Scope: stable symbol/type identities, control flow, explicit effects, source provenance,
  configuration, and ownership/cleanup/error edges. Private helpers remain compiler-visible without
  becoming source-public. Cloned function-local globals/TLS still refer to their original storage.
- Expansion: preserve generic-instance identity, moves/copies/drops, `defer`, fallible returns,
  nullable facts, receivers, closures, and variadics before admitting each shape. Macros/mixins and
  compile-time constructs retain their semantic expansion rules; optimize their resolved runtime
  result without replaying expansion in the consumer.
- Done when: body round trips and cross-module cloning preserve behavior and locations, static
  storage has one identity, unsupported shapes fall back cleanly, and existing Micro lowering
  consumes bodies without a second semantic analysis of ordinary function syntax.
- Related: compiler.optimization.106, compiler.optimization.108.

### compiler.optimization.123 — Generate profitable CPU variants across source modules

- Evidence: a final application may target a known CPU or a baseline with optional extensions.
  Source-visible dependency kernels can follow the same target policy as their callers instead of
  being limited to a separately built library's instruction selection.
- Next: prove consistent fixed-target propagation through imports/caches/specialized callees,
  then prototype two measured kernel variants behind one baseline-safe dispatcher. Select kernels
  by cost/profile evidence instead of cloning whole dependencies.
- Boundary: reuse the optional-feature query and dispatch contract owned by platform.portability.103; this
  entry owns variant generation and reuse across source-module boundaries.
- Scope: account for OS-enabled vector state as well as CPU features; isolate unsupported
  instructions behind the guard; hoist dispatch outside hot loops when stable. Preserve canonical
  exported/address-taken identity, unwind, and debug behavior.
- Policy: bound variant count and code growth, key profiles/caches by feature sets, and omit dispatch
  for fixed-target builds. This is ahead-of-time multiversioning; deploying the compiler's JIT
  inside applications would require a separate runtime/deployment decision.
- Done when: a third-party kernel has a measured faster variant on supporting hardware, the
  baseline runs on the declared minimum target, dispatch is correctly gated/amortized, and build
  cost plus artifact growth justify the chosen variants.
- Related: compiler.optimization.109, compiler.optimization.112, compiler.optimization.120,
  platform.portability.103.

### compiler.optimization.106 — Resolve local implementations and optimization boundaries

- Evidence: `shouldAutoInline` in
  [SemaInline.cpp](../src/Compiler/Sema/Helpers/SemaInline.cpp) rejects another module namespace.
  [ModuleApiExport.Generate.cpp](../src/Compiler/ModuleApi/ModuleApiExport.Generate.cpp) normally
  publishes ordinary functions as `Foreign` declarations and preserves explicit inline bodies.
  A source installation alone therefore does not supply an optimization body.
- Resolution seam: `DependencyPlanBuilder::resolveNode` in
  [CompilerInstance.Module.cpp](../src/Main/CompilerInstance.Module.cpp) already captures API bytes
  under `ModuleApi::DirectoryAccess`, retains original artifact paths in `sourcePaths`, and records
  consumer mirror paths separately. `ModuleSetupInputApplier` selects static/shared linkage for
  the actual closure. Extend that resolved graph rather than adding a second module search.
- Next: prototype a provider mapping the selected module/function identity to its exact immutable
  implementation and build contract. Compare in-process handoff for sibling modules with a
  published descriptor/body store for independently built packages. Prove both through two local
  workspaces and an unannotated scalar helper before expanding the supported body shapes.
- Publication: `exportModuleApi` publishes before native generation; deferred linking can overlap
  compilation of the next module. Freeze the API/body generation together, then certify its match
  to the selected artifact at native publication/link consumption. A later reread of a source path,
  a matching module name, or unchanged size/timestamps is insufficient. Do not introduce a mandatory
  native-link barrier before consumers can analyze bodies; final binding must validate assumptions
  or discard/recompile affected variants before emitting the image.
- Scope: track source/IR availability, implementation identity, binding stability, external visibility,
  address escape, and whether all callers are known as separate facts. Distinguish a Swag import
  lowered through `Foreign` from an opaque external implementation without changing its ABI.
  Cover transitive imports, overrides, multiple versions, generated sources, and read-only packages.
  Resolve the dependency selected by the build; do not scan unrelated files or fetch missing source.
- Fallback: absent/incompatible optional optimization material keeps the ordinary verified artifact
  path. A source/binary mismatch must never optimize one implementation while linking another;
  use normal rebuild policy or decline the optimization.
- Regression matrix: source/API/artifact edits with preserved sizes and timestamps; interrupted and
  concurrent publication; original versus mirrored dependency paths; relocated read-only packages;
  the same module name at different versions; and shared/static alternatives of one dependency.
  Capture generated and compile-time-dependent implementation context through the build model;
  source-file hashes alone cannot reconstruct a resolved body or authorize its reuse.
- Done when: equivalent local, vendored, and third-party implementations expose equivalent
  eligible bodies; mismatched and opaque imports stay correct; shared exports retain their required
  binding; decision records identify the exact eligibility reason.
- Related: compiler.optimization.107, compiler.optimization.109.

### compiler.optimization.108 — Build a bounded global call index and optimization driver

- Evidence: [MicroPassManager.cpp](../src/Backend/Micro/MicroPassManager.cpp) operates on individual
  functions; semantic automatic inlining has a limited call graph; the linker resolves emitted
  symbols. These are not a general selective importer and interprocedural transformation driver.
- Next: summarize identities, cost, direct edges, possible indirect targets, address uses, visibility,
  and referenced data. Resolve a combined index for the actual link closure and import only selected
  bodies. Analyze recursive strongly connected components with conservative fixed points.
- Algorithm: publish completed immutable facts, use change-driven worklists and explicit widening/
  budgets, and reschedule only affected functions. Revisit reachability after graph changes.
  Alternate specialization, devirtualization, inlining, and local simplification in bounded rounds,
  then lower ABI and run Micro. Separate proof facts from profitability estimates.
- Scheduling: parallel independent partitions under a memory budget, evict unused imports, and use
  stable work ordering and deterministic budget allocation. Avoid semantic wait cycles and
  publication barriers that require every dependency to finish native linking first.
- Elsewhere: [ThinLTO](https://clang.llvm.org/docs/ThinLTO.html) combines compact summaries, selective
  function importing, parallel backends, and incremental reuse.
- Done when: recursive, diamond, and large sparse graphs converge deterministically with bounded
  imported memory; newly direct/dead edges trigger targeted reanalysis; unrelated partitions stay
  reusable; instrumentation accounts for time and memory by phase.
- Related: compiler.optimization.107, compiler.optimization.109, compiler.build.073.

### compiler.optimization.109 — Cache bodies and the assumptions used by callers

- Evidence: [NativeBackendBuilder.cpp](../src/Backend/Native/NativeBackendBuilder.cpp) fingerprints
  Micro for its native function cache and currently excludes bodies with relocations. Importing
  implementations creates dependencies that public API fingerprints alone cannot describe.
- Next: define separate immutable caches for typed bodies/summaries and native variants. Key variants
  by body, referenced types/constants, compiler/IR schema, target/CPU, semantic configuration,
  optimization policy, and relevant profile identity.
- Dependencies: track imported private bodies, propagated effects/value facts, specialized arguments,
  binding resolution, and devirtualization assumptions. Include negative/global facts: adding a
  target or caller may invalidate uniqueness or all-callers proofs without changing an old body.
- Publication: content-addressed records, atomic completion, schema rejection, concurrent readers,
  cancellation-safe writes, and consumer-owned writable caches for read-only packages. Logical
  identity should allow harmless path relocation without confusing distinct builds. Track generated
  and compile-time inputs through the build model; untracked environmental dependencies prevent reuse.
- Done when: private edits invalidate affected callers/variants, unrelated edits retain hits,
  target/configuration/summary/profile changes cannot reuse stale code, and interrupted concurrent
  builds cannot publish partial artifacts. Measure cold, warm, and edit/rebuild costs separately.
- Related: compiler.optimization.106, compiler.optimization.108, compiler.build.030.

### compiler.optimization.110 — Infer interprocedural memory and value summaries

- Evidence: `SymbolFunction` already carries borrow/escape/release summaries; API publication exports
  `BorrowSummary` and `ReadOnly`; LICM and selected post-allocation passes consume direct readonly
  calls. Extend this foundation instead of introducing a separate incompatible effect system.
- Next: summarize reads/writes by parameter-derived/global region, capture, allocation/release,
  ambient-state access, callback effects, and return ranges/nullability/alignment/argument relations.
  Compute transitive facts over recursive components and serialize them with their body/configuration.
- Consumers: preserve facts through calls in value numbering, load/store elimination, LICM, and
  range propagation. Unknown external/indirect behavior remains unknown. Keep noncapture, readonly,
  purity, no-alias, termination, and failure distinct; model atomics, volatile accesses, TLS/context
  mutation, aliasing, and reentrant callbacks.
- Proof: deleting an unused call also needs termination/error and other observable effects to permit
  removal; readonly alone is insufficient. Reuse existing borrow proofs where their meaning matches,
  without treating a lifetime guarantee as a stronger alias guarantee.
- Done when: a third-party readonly helper preserves an unrelated load without being inlined;
  transitive writers/callbacks invalidate it; recursion converges; summary-only imports help callers
  even when their bodies are not imported.
- Related: compiler.optimization.108, compiler.optimization.109, compiler.optimization.020.

### compiler.optimization.111 — Inline ordinary functions across module boundaries

- Evidence: the namespace guard in `shouldAutoInline` in `SemaInline.cpp` prevents automatic
  intermodule inlining. Its signature/body exclusions are correctness boundaries; deleting the guard
  or marking every export `Inline` does not implement general importing.
- Next: inline resolved unannotated scalar/pointer direct callees from any eligible module using
  typed bodies. Fold caller constants and simplify immediately, then expand supported shapes with
  focused regression coverage.
- Cost model: estimate residual work after substitution, loop depth/frequency, duplicated code,
  register pressure, frame growth, and downstream vectorization. Bound total caller growth,
  recursion, imported bytes, and compilation work. A single-caller bonus requires proof that the
  final call/body can disappear; share growth budgets with unrolling.
- Semantics: retain effective callee contracts, evaluation order, cleanup, and unique storage.
  Preserve canonical bodies for remaining calls/observed addresses. Honor `Never` and `NoInline`;
  define interaction with explicit `Inline` without incidentally changing its semantics.
- Done when: profitable unannotated helpers and private helper chains in unrelated packages
  inline automatically, forbidden/oversized cases remain calls, and runtime, size, compile-time,
  and memory results justify the default policy. Import visibility never changes source validity.
- Related: compiler.optimization.107, compiler.optimization.108, compiler.optimization.110,
  compiler.codegen.002, compiler.optimization.022.

### compiler.optimization.112 — Specialize ordinary calls on constants and known callbacks

- Evidence: separately compiled functions lose call-site constants and callback identities. Existing
  generics and constant folding do not constitute a general intermodule residual-function pipeline.
- Next: clone an ordinary function for a proven constant scalar/enum/mode argument, simplify it,
  and redirect eligible calls without requiring generics in source. Extend to lengths, alignment,
  known callback targets, and profitable type/context facts.
- Sharing: intern semantic specialization keys so callers reuse variants. Propagate through wrappers
  and recursive components with bounded variant counts; preserve a general version where needed.
  Never duplicate a static/TLS object along with a cloned body.
- Policy: charge growth/work to the shared driver budgets. Profile-frequent values require a guard
  and general fallback; proven constants do not. Avoid cloning for large or rare constant domains.
- Elsewhere: [GCC interprocedural options](https://gcc.gnu.org/onlinedocs/gcc/Optimize-Options.html)
  describe constant propagation and cloning.
- Done when: consumers share useful mode-specific variants with dead branches removed, known
  comparators become direct calls, general callers remain correct, and bounded clone families show
  measured value beyond merely removing call instructions.
- Related: compiler.optimization.109, compiler.optimization.110, compiler.optimization.111,
  compiler.optimization.120.

### compiler.optimization.113 — Devirtualize interfaces, callbacks, and stable context regions

- Evidence: `SemaInline::tryInlineCall` leaves dynamic interface dispatch intact. Global value flow
  can establish targets more precisely than an interface type; local source availability alone does
  not prove a closed implementation set.
- Next: track function/interface targets through construction, assignment, parameters, returns, and
  closures, then replace proven singleton targets with direct calls across modules. Preserve receiver
  adjustment, capture layout, lifetime, and canonical function identity.
- Expansion: identify regions with a stable allocator, writer, comparator, or other interface value,
  using context read/write summaries. Specialize their call chains for that proven context; stop at
  mutation, unknown callbacks/reentrancy, or external escape.
- Boundaries: exported interfaces, plugins, shared libraries, and unknown FFI callbacks retain
  open-world behavior. Profile-dominant targets may get guarded fast paths with complete fallbacks;
  frequency never proves that other targets are impossible.
- Elsewhere: [LLVM WholeProgramDevirt](https://llvm.org/docs/doxygen/WholeProgramDevirt_8cpp_source.html)
  demonstrates whole-program virtual-call reasoning.
- Done when: a third-party interface pipeline becomes direct where proven, dynamic implementations
  still work, new reachable targets invalidate cached proofs, and context mutation/reentrancy defeats
  invalid region specialization.
- Related: compiler.optimization.108, compiler.optimization.110, compiler.optimization.112.

### compiler.optimization.114 — Specialize aggregate transport and internal signatures

- Evidence: compiler.optimization.022 owns a local aggregate-copy gap. Cross-module body/use
  information additionally permits changing internal calls instead of transporting the entire
  public ABI representation.
- Next: create an internal worker taking only needed scalar fields and returning consumed values;
  keep a canonical ABI entry for external/indirect/unrewritten calls. Apply argument promotion,
  unused-argument elimination, return decomposition, and caller return-storage reuse.
- Proof: preserve by-value snapshots under alias writes, argument effects, copy/drop hooks, moves,
  failures, and address identity. Unused result fields do not authorize removing observable work.
  Materialize objects whose address, layout, or whole-object operations remain observable.
- Expansion: scalarize short-lived aggregates through module boundaries and feed existing
  memory-to-register/vectorization passes. Keep the existing local copy-materialization entry as
  the owner of that defect rather than duplicating its work here.
- Done when: eligible third-party aggregate round trips lose redundant copies/hidden return
  storage, external wrappers retain their ABI, and alias/lifecycle regressions prove value semantics.
  Report throughput, frame size, and code size.
- Related: compiler.optimization.107, compiler.optimization.110, compiler.optimization.022.

### compiler.optimization.115 — Eliminate proven temporary allocations across calls

- Evidence: borrowing, escape, release, and ownership analysis already exists; imported bodies can
  expose producer/consumer lifetimes hidden by module calls. Nonescape alone does not permit
  suppressing allocations with observable behavior.
- Next: choose one temporary with bounded size/lifetime and matched cleanup; prove scalar replacement,
  stack placement, or construction directly into consumer storage. Start with existing contracts.
- Proof: preserve allocator hooks, allocation failure behavior, finalization, address comparisons,
  alignment, provenance, and diagnostics required by the configuration. Custom allocators may
  observe every operation. If current semantics lack the necessary freedom, first decide a narrowly
  scoped explicit contract rather than silently changing those semantics.
- Expansion: eliminate redundant ownership transfers/copies along the same lifetime and fuse
  construction/consumption where effects allow it. Bound stack growth; reject unbounded promotion.
- Done when: an ordinary dependency pipeline loses a measured temporary allocation while escapes,
  observable allocators, failures, and cleanup ordering retain their behavior. Report allocation count,
  stack footprint, compilation cost, and runtime.
- Related: compiler.optimization.110, compiler.optimization.113, compiler.optimization.114.

### compiler.optimization.116 — Carry intermodule proofs into loop and vector optimization

- Evidence: Micro already has LICM, induction analysis, unrolling, and SLP. Existing leads identify
  lost alias/range facts; imported bodies can expose simpler loops and stronger facts to these passes.
- Next: propagate proven lengths, strides, alignment, disjoint regions, and return ranges through
  calls. Remove repeated enabled guards, hoist stable memory, simplify induction, and expose
  vectorizable work after specialization/inlining.
- Expansion: investigate bounded loop unswitching, runtime alias/alignment versioning, loop
  vectorization, and producer/consumer loop fusion where dependence/effect proofs permit. Keep the
  general path when a runtime precondition fails; coordinate growth with inlining and unrolling.
- Semantics: respect signed arithmetic/overflow, configured FP behavior, traps/error order, zero-trip
  loops, atomics, and observable memory. This work does not change safety-guard defaults.
- Done when: loops crossing third-party helper boundaries retain facts and gain demonstrated
  optimization; overlap, changing lengths, overflow, and guarded fallback cases remain correct.
  Existing local gaps remain with their existing entries.
- Related: compiler.optimization.110, compiler.optimization.111, compiler.optimization.112,
  compiler.optimization.020, compiler.safety.008.

### compiler.optimization.117 — Inline fast paths while sharing cold continuations

- Evidence: `MicroColdBlockLayoutPass` moves selected cold blocks within a function, but whole-body
  inlining can still duplicate refill, allocation, and error paths. Current allocator comparisons
  are not attributable: Java drops tree references after checking them, while Swag visits and frees
  each node inside the timed region.
- Next: match the timed work and object lifetimes first. Then compare caller-plus-callee Micro work
  for the direct default `Allocator.alloc` fast path against the indirect interface call, preserving
  custom allocator dispatch.
- Contracts: preserve live-in/live-out values, stack and borrow lifetimes, cleanup ownership, error
  edges, and source locations. Share continuations only when state, effects, and identity permit.
- Done when: a package-local refill or checked-operation pattern gains an inlined fast path and one
  correct shared slow path, growth is bounded, and failure/cleanup/stack-walking coverage passes.
- Related: compiler.optimization.111, compiler.optimization.114, compiler.optimization.120.

### compiler.optimization.118 — Extend precise callee register contracts beyond leaves

- Evidence: optimized direct calls already consume clobber masks from proven semantically
  leaf callees whose lowered code contains no call. `MachineCode::leafCallClobbers` reads
  final physical writes, and `SymbolFunction::narrowCallClobbers` lets callers retain values
  in preserved transient registers. Machine-code and incremental-function caches retain
  those masks. A body containing a call still publishes the full conservative mask, so
  transitive non-leaf contracts remain unavailable.
  Expanding candidates to calls erased by inlining reduced Wordfreq partition traffic
  (27 to 26 instructions, 11 to 10 memory operations), but independent paired timings
  regressed the whole task by 8.8% to 9.5% beyond unchanged controls. Keep the existing
  eligibility until the new register assignment and hot dependencies are understood.
- Next: extend the existing masks to transitive callees and retain caller values in proven
  preserved registers. Lower acyclic callees first; use conservative fixed points or the
  ordinary ABI inside recursive components, preserving the existing leaf path.
- Expansion: measure internal worker conventions with argument/result placement chosen for a call
  cluster, redundant save/restore removal, and legal sibling/tail calls. Preserve platform unwind
  requirements and canonical ABI entries for external/indirect/address-taken uses.
- Stability: invalidate callers when contracts change, avoid allocation oscillation, and do not
  infer preservation through unknown calls, instrumentation, or patchable targets. Bound the
  compilation serialization introduced by bottom-up lowering.
  Joining every direct callee after lowering retained caller bodies and raised fresh core
  build peak RSS by 21.5%; selective published-candidate joins avoided that memory increase.
- Elsewhere: [GCC interprocedural register allocation](https://gcc.gnu.org/onlinedocs/gcc/Optimize-Options.html#index-fipa-ra)
  exploits registers known not to be clobbered by callees.
- Done when: noninlined third-party helpers permit fewer caller spills under verified contracts,
  recursive/opaque cases remain sound, and runtime savings justify code-size and scheduling costs.
- Related: compiler.optimization.108, compiler.optimization.109, compiler.optimization.114.

### compiler.optimization.119 — Recompute whole-image liveness after specialization

- Evidence: `partitionArchiveObjects` already emits one function/read-only allocation per archive
  member; `PELinker::resolveSymbols` extracts demanded members and folds some identical functions/
  data. Transformations can create new dead code/data and reveal equivalence before machine emission.
- Next: extend the emitted-reference reachability boundary to incremental objects and library
  binding. Cached functions without an in-memory relocation stream still retain their semantic
  dependency sets. Global initialization scans also root every recorded constant/function target,
  even when its allocation is not emitted. Recover precise roots without dropping initializer
  effects, exports, address uses, callback registrations, interface tables, runtime type
  information, TLS, or explicitly retained symbols.
- Expansion: omit unreachable bodies, data, and metadata edges; remove initialization only when
  its effects permit; recover granularity where unrelated writable globals share an object.
  Evaluate semantic merging of specialized/generic bodies beyond byte equality while preserving
  observable function/data addresses and mutable-storage identity.
- Boundaries: reflection and dynamic lookup contribute roots under their actual contracts.
  Unknown external behavior stays conservative. Debug provenance must not unnecessarily retain
  executable code, and unused globals do not imply effect-free initializers.
- Done when: specialized third-party features lose their unused implementation/data closure,
  registered callbacks and reflection survive, initialization order/effects remain correct, and
  text/data/startup gains are measured against the existing linker.
- Related: compiler.optimization.108, compiler.optimization.112, compiler.optimization.113.

### compiler.optimization.120 — Collect and consume stable application profiles

- Evidence: no general profile-feedback pipeline was found in the inspected optimization/linking
  paths. Call frequency, branch bias, and target/value distributions can distinguish profitable
  specialization from harmful code growth.
- Next: implement end-to-end function/call/branch instrumentation with stable logical identities,
  including imported/inlined origins. Define versioning, merging, saturation, workload weighting,
  and matching to compiler/configuration/body identity.
- Expansion: bounded indirect-target and useful value histograms, followed by a separate assessment
  of sampling import on supported platforms. Attribute counts through cloning/inlining/outlining
  without double counting or applying old binary addresses to a new layout.
- Consumption: feed inlining, specialization, devirtualization, loop decisions, and cold paths.
  Missing/partial/stale profiles fall back predictably with decision records. Profiles guide
  profitability; they never prove an unobserved branch/target impossible.
- Done when: training and held-out workloads show repeatable benefit, collection overhead and
  storage are measured, profile changes correctly affect variants/caches, and unprofiled or changed
  dependencies compile correctly.
- Related: compiler.optimization.109, compiler.optimization.112, compiler.optimization.113,
  compiler.optimization.117.

### compiler.optimization.122 — Partially evaluate dependency code and freeze eligible data

- Evidence: Swag already has compile-time execution and purity analysis. Imported resolved bodies
  could extend constant reasoning to ordinary functions with partly static inputs without explicit
  compile-time annotations at every call.
- Next: reuse typed-body evaluation for bounded pure computations with known inputs, or residualize
  partly known computations into smaller runtime bodies. Do not replay module setup or execute
  arbitrary effectful dependency code while trying an optimization.
- Expansion: precompute deterministic dispatch/parsing tables, immutable initialization, and
  schema/format-dependent work when inputs and target behavior are known. Keep data relocatable
  and shareable; host-process pointers are not target-program addresses.
- Proof: preserve observable I/O/state, nondeterminism, allocation effects, and failure timing.
  Respect target integer/FP semantics and configuration. Bound steps, recursion, memory, and output
  size; exhaustion retains the runtime computation.
- Done when: ordinary third-party computations lose proven static work, partial inputs yield
  bounded reusable residual bodies, host/target differences are respected, and unsupported/effectful/
  expensive computations reliably remain at runtime.
- Related: compiler.optimization.107, compiler.optimization.110, compiler.optimization.112,
  compiler.optimization.119.

### compiler.optimization.124 — Evaluate private data representation specialization

- Evidence: global use/escape facts can expose internal data, but source availability alone does
  not allow changing Swag layout, reflection, addresses, or serialized representations. This is
  an exploratory outcome after the shared proof infrastructure.
- Next: inventory representation-observing operations and select one workload with known producers/
  consumers. Compare field elimination, hot/cold splitting, compact tags, or array-of-structures
  to structure-of-arrays conversion; prototype one only after establishing legality and expected value.
- Proof: account for offsets, size/alignment queries, pointer arithmetic/casts, whole-object copies/
  comparisons, reflection, serialization, FFI, debug inspection, concurrency, and identity. Preserve
  observed representation or establish a correct boundary conversion. Do not silently redefine
  ordinary public/source-observable types.
- Decision: determine whether current semantics admit useful cases or a narrowly scoped explicit
  representation-freedom contract is needed. Any language/API change follows its own syntax,
  documentation, and compatibility workflow; this plan does not preselect one.
- Done when: the investigation delivers a legal measured prototype and bounded implementation
  decision, or establishes why the benefit does not justify the required semantic freedom.
  Speculative transformations must not become default behavior without that evidence.
- Related: compiler.optimization.110, compiler.optimization.114, compiler.optimization.115,
  compiler.optimization.119.

### compiler.optimization.085 — Measure short-key comparison cost against the current winner

- Evidence: `Swag.memcmp`'s fallback compares 8/4/2/1-byte chunks, with no byte loop for
  wordfreq's 3-8-byte keys. Go, the current wordfreq winner, inlines `compareBytes` into
  `byteMap.probe`. Swag inlines the probe into its timed `__main_0` but still calls
  `Swag.memcmp` after the length check. Static listings do not establish a net hot-path
  gain from inlining it. A `<8`-byte dispatch guard in front of the vector and word loops
  grew `Swag.memcmp` in all twelve tasks and was rejected.
- Next: inspect whether a shared fast-path inlining rule can remove caller and callee work
  for short comparisons without growing the other task hot paths; require a concrete Micro
  gain before editing.
- Done when: final short-key code and repeated paired wordfreq measurements establish
  competitive cost, or isolate a reproducible remaining gap whose implementation can be
  specified here.

### compiler.optimization.133 — Calibrate optional optimizer work independently of convergence guards

- Evidence: two earlier probes reached no pre-RA/post-RA stops and often changed code in the
  final pre-prologue sweeps. Reducing SLP depth from 512 to 32 doubles a supported deep chain's Micro
  instructions. Timing controls remain too noisy to select a replacement default or O3 multiplier.
- Workspace `build --optimizer-stats` reports zero pipelines even when module compilers ran
  the optimizer: each `CompilerInstance` owns its totals, and the driver report does not include
  the module instances that performed the work.
- Next: aggregate module profiles into the workspace report, then correlate `--optimizer-stats`
  with function listings and add function/sweep attribution for late useful rewrites and SLP
  rejection reasons. Cover remaining analysis budgets where
  observed work warrants it; distinguish retained plan size from failed exploration. Evaluate
  cached tuple reuse before depth rejection and measure selected policies on a quiet machine,
  keeping convergence guards, optional work, output growth and pressure independent.
- Done when: representative paired campaigns identify repeatable Pareto improvements, the chosen
  defaults preserve the relevant code/semantic boundaries, and any O3 policy increases useful work
  without changing arithmetic, FP or allocation-feasibility contracts.
- Related: compiler.optimization.029, compiler.optimization.032, compiler.codegen.007.

### compiler.optimization.134 — Share the cleanup of a function's failure exits

- Evidence: every `try` that can leave a function emits the deferred drops of the live locals on
  each failure branch, and the error check has two branches (the TLS fast test and `__hasErr`).
  Releasing the local built in the return slot on failure, which the former `retval` leaked, took
  `TrueType.parseCffFont` from 120 to 588 inlined drop calls and 1 033 to 2 180 final instructions
  in release; 104 other fallible constructors grew the same way (+3 266 instructions in all).
- Next: give the failure exits of one scope a shared landing block that runs the drops once and
  jumps to the function's failure return, keeping the fast success path unchanged.
- Done when: a fallible constructor with several `try` calls emits its live-local drops once per
  scope rather than once per failure branch, with failure-path drop counts unchanged in the
  `native` lifecycle tests.
- Related: compiler.optimization.117.

### compiler.optimization.138 — Generalize loop reductions and prove vector memory access

- Evidence: the registered vectorizer is basic-block SLP (`Pass.SlpVectorize`).
  `Pass.LoopUnroll` recognizes fixed-bound indexed 32-bit XOR and the unsigned
  32-bit conditional sum into a 64-bit accumulator. The sum supports a runtime bound with
  four-element groups and a scalar tail. Other reduction forms still need a general analysis
  and loops that write memory need alias proofs or runtime checks.
- Next: add loop vectorization that recognizes associative reductions, versions
  alias/alignment checks, and generates masked or peeled tails using the explicit SIMD
  operation set.
- Done when: sum/min/max/bitwise reductions and an unknown-length byte loop vectorize under
  the supported target policy with scalar-equivalent results and profitable cost decisions.
- Related: std.core.043, std.core.048.
