# Safety Backlog

What the language guarantees about memory, and where it stops guaranteeing.

Four layers carry that today, and they are not interchangeable:

| Layer | Spelling | On in `release` | Cost |
| --- | --- | --- | --- |
| Borrow rules | none — part of the language | yes | none |
| Static sanity proofs | `#[Swag.Sanity]`, `buildCfg.sanityGuards` | yes | none |
| Runtime guards | `#[Swag.Safety]`, `buildCfg.safetyGuards` | no | measured per guard |
| Runtime poison | `.Lifecycle` half of `#[Swag.Safety]` | no | stores on abandoned storage |

The reference states the line between them
([013_000](../bin/reference/modules/language/src/013_000_error_management_and_safety.swg),
[013_004_borrowing.swg](../bin/reference/modules/language/src/013_004_borrowing.swg)): the borrow
rules are the language and no attribute turns them off; everything else is tooling a caller can
switch off, and a guarantee a caller can switch off is not a guarantee.

The runtime guards are deliberately absent from `release`, and no entry here proposes putting one
back by default. `release` is the configuration that costs nothing, a build that wants the guards
turns them on — `buildCfg.safetyGuards`, or a target of its own — and a fix that adds an
instruction to a guard-free build is not a fix. What the entries below ask for instead is more
proof at compile time, where the cost is the compiler's rather than the program's.

Measured against that line, the frame is in good shape and the heap is catching up. Escapes, view
invalidation, iterator invalidation, definite initialization, non-null types and mandatory error
handling are all enforced without a single annotation, and a value that owns a release now states
no copy without being annotated either. The use-after-free proof reaches the storage a program
actually keeps a pointer in — a parameter, an element of a local table, a field, a copy into
another local — and survives an ordinary call: what a function never hands an address to, no callee
can reassign. What is left on the heap side is the shape nothing marks as an owner at all, a
release proven on only one path, storage whose address the function does hand over, a release
reached through a field of a receiver, and the operations that forge a pointer out of nothing being
spelled like ordinary code.

The fault-class entries use [bin/unittests/safety/corpus](../bin/unittests/safety/corpus):
one file per CWE, a fault half that names the diagnostic it expects and a sound half that must
stay silent. Unsafe gap examples are commented out and tagged with their owning entry; safe
wrong-value probes may remain executable. Analysis, API, performance, and documentation entries
also name their own evidence below; they do not all have a CWE reproducer. `rg "GAP " bin/unittests/safety/corpus`
is the current scorecard.

[README.md](README.md) defines the shared backlog conventions.

### compiler.safety.030 — Prove that nothing changes a struct argument while the call runs

- Area: compiler/sema, call-site storage provenance and effect analysis; `SemaEscape` summaries;
  immutable-storage facts in code generation.
- Evidence: [the struct parameter contract](../bin/reference/modules/language/src/006_001_declaration.swg)
  forbids changes to the caller's struct during a value call. `isImmutableIndirectParameter` in
  [CodeGenFunctionHelpers.cpp](../src/Compiler/CodeGen/Core/CodeGenFunctionHelpers.cpp) marks
  its storage invariant across stores and calls without a call-site stability proof. A const
  access path alone does not establish this invariant. The observable failure can depend on
  inlining, scalarization and optimization; it is not confined to one build configuration.
- ABI boundary: [CallConv.cpp](../src/Backend/ABI/CallConv.cpp) passes structs of exactly
  1, 2, 4 or 8 bytes directly; other sizes are indirect. Direct Swag calls borrow the storage.
  C currently resolves to Windows x64 and requires an indirect copy. The normal call lowering's
  `materializePreparedIndirectCopyArg` reserves stack storage rounded to the ABI's 16-byte
  alignment, copies the bytes, and passes that address. Runtime function-value calls also request
  defensive aggregate copies. Existing cases in
  [Test.ABI.FFI.cpp](../src/Unittest/ABI/Test.ABI.FFI.cpp) check native mutation of the copy and
  preservation of the source. Keep C value semantics separate from the Swag borrow rule.
- Required proof: treat the argument's inline storage (including embedded fields and arrays) as
  a shared read borrow for the call. Every reachable write, move, destruction, release or
  reallocation must be proven disjoint from that storage, and its lifetime must cover all uses.
  Multiple read aliases are legal. A copied pointer or slice header does not freeze its external
  pointee; follow a pointee only when its provenance can lead back into the borrowed storage.
  Self-pointers, enclosing-object pointers, byte views and overlapping union fields defeat a
  same-type-only check. Do not promote storage invariance into unrestricted `noalias`.
- Static implementation path:
  1. Resolve storage roots and projections at the call site: `f(x, &x)`, `f(x, &x.field)` and
     `f(x.field, &x)`, then saved aliases, field-carried aliases and indexed regions. Compare
     overlapping storage, not just matching AST syntax. A mutable route that may overlap and
     has no proven read-only effect is a conflict; two read-only routes stay accepted.
  2. Infer transitive write and invalidation effects through parameters, receiver projections,
     globals and closure captures. Reuse `SemaEscape`'s deferred checks and summary fixpoint,
     but add effects: current `stores` describes retention, not arbitrary memory writes, and
     `observesExternal` is not a no-write proof. Export effects with module APIs; an absent or
     opaque summary means unknown, never pure. Model callbacks and indirect calls conservatively,
     even when the outer function has no direct store, and include lifecycle hooks.
  3. Prove easy positive cases first: non-escaping local storage with no reachable mutable alias,
     fresh temporary storage, genuine immutable storage, and calls whose complete effect set is
     disjoint. Freeze from the language-defined argument evaluation point through the final use;
     account for later argument evaluation, default expressions and reentrant calls. Keep hidden
     return storage disjoint too: destination reuse in `x = f(x)` must not overwrite live input.
  4. Make unresolved overlap an explicit policy decision. Keeping guaranteed zero-copy calls
     requires rejecting unproven cases in safe code, with an explicit snapshot or pointer API as
     the remedy. Alternatively, copying at unproven sites preserves value semantics and the ABI
     pointer shape but gives up guaranteed zero-copy. A snapshot must respect `NoCopy`, copy/drop
     hooks, self-borrows and lifetime rules; a raw byte copy is not a universal remedy.
- Mandatory boundary: the proof must run independently of optional sanity guards, optimization,
  inlining and ABI size classification if this is a language safety guarantee. A diagnostic for
  obvious overlap is a useful first increment, not completion. Unknown provenance from raw memory,
  forged pointers or uncontracted foreign code needs the unsafe boundary of compiler.safety.006.
  Concurrent mutation can be excluded statically by ownership, immutable sharing or checked
  capabilities, but present capture/lifetime summaries do not establish race freedom. Atomics
  prevent some races; they do not make a by-value object's bytes invariant during a call.
- External comparison: [Zig issue 5973](https://github.com/ziglang/zig/issues/5973) identifies the
  hidden-reference aliasing problem and records removal of PRO during the 0.16.0 cycle. A sound
  borrow proof addresses that objection; a const pointer plus selected warnings does not.
  [D const/immutable](https://dlang.org/spec/const3.html) distinguishes a read-only access path
  from transitively immutable data. `immutable` is useful positive evidence but cannot safely be
  manufactured by casting still-aliased mutable storage. D's
  [`in` parameters](https://dlang.org/spec/function.html#in-params), with `-preview=in`, permit
  compiler-chosen reference passing and add `const scope`; scope limits escape, not mutation
  through another alias. They are not themselves a general alias-exclusion proof.
- Next: implement the direct overlapping-root check with read-only controls, then prototype
  write/invalidation summaries on saved-alias, enclosing-object, global and callback cases.
  Measure compile-time cost and rejected valid consumers before choosing the unknown-case policy.
  Cover semantic diagnostics, cross-module summary export and native invariant-load behavior;
  include small/odd/large layouts, explicit copies, self-borrows and hidden return destinations.
- Done when: every accepted safe Swag value call has a storage-stability and lifetime proof,
  or the chosen policy supplies a semantically valid copy; unknown cases cannot silently retain
  invariant-load assumptions. C copy isolation remains covered, and unproven concurrency/raw-memory
  cases have an explicit enforced boundary rather than a warning-only contract.
- Related: compiler.safety.006, compiler.safety.020, compiler.safety.023,
  language.parallelism.005, language.parallelism.007.

### compiler.safety.025 — The box-content release summary stops at the module boundary

- Area: compiler/sema, `SemaEscape`; `Swag.BorrowSummary`; `Sanitizer`
- Evidence: a function that releases the pointer stored in the box its parameter designates
  (`if let item = slot[] { Memory.delete(item); slot[] = null }`) now records
  `SymbolFunction::freesIndirectParamsMask` instead of claiming it frees the box, and a caller
  handing it `&local` has every other frame copy of the released pointer marked released
  ([use_after_free_box_content.swg](../bin/unittests/sanity/use_after_free_box_content.swg)).
  The mask is inferred inside the module only: `ModuleApiExport` re-emits `frees` but has no
  indirect counterpart, so an importer calling `Wnd.stopTimer(&timer)` and then reading a copy
  of the old timer pointer gets no diagnostic. Wrappers that hand their own box parameter on
  (`func w(slot: **T) => stop(slot)`) do not forward the indirect bit either.
- Next: add a `freesIndirect` argument to `Swag.BorrowSummary` (runtime `api.swg`, `Sema.Attributes`,
  `AttributeList`, the export), then forward the bit along direct edges whose argument is
  exactly the caller's parameter.
- Done when: a cross-module caller of a box-content release reports the old-copy read the
  in-module suite case reports, and wrappers keep the summary.

### compiler.safety.005 — A write through a pointer into a moved value is not reported

- Area: compiler/backend, `Sanitizer`
- Evidence: a struct holding a pointer into its own storage keeps that pointer after `#move`, and
  the pointer then addresses the abandoned source. Reading through it is now a compile-time error:
  `source.cursor = &source.values[0]; var target = #move source; return target.cursor![]` reports
  `sanity_err_use_after_move` for whole, packed, first-field and indexed self-pointers
  ([self_borrow_move.swg](../bin/unittests/sanity/self_borrow_move.swg),
  [self_borrow_indexed_move.swg](../bin/unittests/sanity/self_borrow_indexed_move.swg), since
  `d2672787e`), and an `opPostMove` hook can repair the pointer in its new storage.
- What remains: a write through the same pointer, `target.cursor![] = 7`, still stores into the
  abandoned source with no diagnostic. The check reports only loads from a moved range
  (`UseAfterMoveCheck::run` calls `Sanitizer::reportLoadFromMovedRange`), and a store into moved
  storage is also how a moved-from variable is legitimately reinitialized. The commented
  `GAP compiler.safety.005` case in
  [cwe672_use_after_move.swg](../bin/unittests/safety/corpus/cwe672_use_after_move.swg) is that write.
- Next: separate a store through a pointer derived from the source before the move from a direct
  reassignment of the moved-from variable, and report the first with the same diagnostic. If the
  analysis cannot tell them apart, document the limit next to the move rules instead.
- Done when: the corpus write case is a fault case naming its diagnostic, or the reference
  documents the limit; reassignment after a move and `opPostMove` repair stay accepted.

### compiler.safety.023 — Opaque results lack pointer-field provenance

- Area: compiler/sema, `SemaEscape`
- Evidence: a fresh semantic-only helper on 2026-10-04 still accepts
  `release(carrier.borrowed)` after a no-inline factory stores `&local` in that field and
  an independent allocation in `carrier.owned`. The DevMode compiler at `ce515e405` in
  `release` reports no errors; releases of the independent field and carrier also stay
  silent. A companion direct `release(&local)` control reports `sanity_err_free_borrowed`,
  confirming the check is active. Neither invalid free was executed.
- Current boundary: copied-field lifetime routes and returned payload projections already
  exist (`25b9598b6`, `e1b81113e`). They do not yet distinguish the borrowed pointee of this
  opaque heap result when judging a release. Propagating the carrier's enclosing borrow
  indiscriminately would also reject its independently allocated field.
- Next: trace this returned-field route through the existing projection and frees-summary
  machinery, then preserve each field's provenance. Cover both fields through generated
  module APIs; never execute an invalid free merely to probe its diagnostic.
- Done when: borrowed returned fields are diagnosed without rejecting releases of
  independently allocated fields, and the focused sanity and workspace regressions pass
  with measured cost.

### compiler.safety.019 — Remeasure sanity cost after live-state pruning

- Area: compiler/backend, `Sanitizer`
- Historical evidence: six-worker Release-compiler profiles on 2026-09-23 attributed about
  8-10% of a core devmode rebuild's busy CPU to `Sanitizer::run`, principally conditional-branch
  narrowing and value transfer. The measured fixed point took about 1.19 propagation visits
  and 0.99 checking visits per instruction. These figures precede the current state layout.
- Current boundary: `Sanitizer::pruneDeadRegs` keeps only registers live at each stored chain
  head, and rarely populated state maps allocate on first use. The live-state change is already
  implemented and tested; compiler.core.005 records its memory reduction and a faster ChaCha
  devmode compilation. Neither that workload nor the earlier profiles establish the current
  sanitizer share of a core or full-std build. Subsequent register, stack-lane, and freed-parameter
  lookups also changed without a separate attribution measurement.
- Next: profile the current core devmode and full-std release rebuilds, reporting sanitizer CPU,
  state memory, propagation/check visits, and wall time separately. Use those measurements to
  choose between branch narrowing, value transfer, and state storage; do not exclude state
  layout using a profile taken before live-state pruning.
- Done when: the current sanity pass's cost is attributed and either accepted or reduced
  with a repeatable comparison and the safety/sanity behavior preserved.
- Related: compiler.core.005.

### compiler.safety.008 — Release bound guards still impose measurable hot-loop cost

- Area: compiler/backend, optimization
- Evidence: dynamic bounds guards now remain enabled in Release. Range and repeated-guard proofs,
  plus cold-block layout, avoid checks when their conditions are established or move the failure
  path off the common path. The remaining guards still cost about 1.24x across the twelve
  `bench/` programs relative to the same build without runtime guards. Hot gaps include
  loop-bounded indices, repeatedly loaded counts, and loop-invariant `late` checks.
- Next: prove an index against the dominating loop bound and hoist a `late` check from a loop that
  does not assign it. Measure the affected loops with guards enabled and disabled.
- Done when: loop-bounded indices and invariant `late` values need no repeated guard, and the
  residual cost of runtime guards is measured on the affected loops with behavior preserved.
- Related: compiler.optimization.105.

### compiler.safety.024 — A mutable cast can write through an any that borrows a literal

- Evidence: the DevMode compiler at the parent revision `e3e20baae` accepts
  `var boxed: any = 42's32; if let number = cast #try (*s32) boxed do number[] += 1`
  (spelled `try cast(*s32, boxed)` or `if boxed is s32 as number` since `102f0efb4`).
  Its JIT test passes, but the generated native executable raises `0xC0000005` while writing
  the literal in read-only storage. The same issue is observable through the new type patterns;
  their casts preserve the existing conversion contract. A variable holding an `any` does not
  itself own mutable storage for the borrowed value.
- Next: decide and enforce the constness of literal-backed and constant-backed `any` views.
  Inspect constant boxing, runtime type qualifiers, and dynamic cast destinations together;
  choose rejection of mutable views or deliberate writable materialization without turning
  `any` into an owning variant. Audit existing casts of literal-backed views before migration.
- Done when: JIT and native execution agree, a mutable cast cannot expose read-only
  literal storage, and tests cover literal, constant, mutable-local, and const-local sources.

### compiler.safety.006 — Raw memory operations have no common unsafe opt-in

- Area: language
- Evidence: Swag has no common opt-in or compiler mode for operations that can violate memory
  safety: integer-to-pointer casts, unchecked raw-memory construction and access, pointer
  arithmetic, union reinterpretation, byte-copy intrinsics, lifecycle bypasses, and foreign calls.
  Pointer casts between unrelated structs are already rejected. Checked dynamic casts have explicit
  `try`, `expect`, and `assume` forms and must be distinguished from unchecked assumptions.
- Next: inventory the remaining operation families across shipped `bin/` sources and tagged native
  integration tests. Use that inventory to choose expression-level and file-level opt-ins, then
  define and enforce which faults the safe subset excludes.
- Done when: the unsafe operation list is fixed and documented, safe code cannot reach any of
  them without a visible marker, `bin/` compiles with the boundary enforced, and the reference
  states which faults the safe subset excludes.
- Related: language.design.002, compiler.safety.007, compiler.safety.014.

### compiler.safety.020 — A release through storage a callee could re-establish is not judged

- Area: compiler/sema, `SemaEscape`
- Evidence: caller-side use after a call can escape detection for receiver fields and globals.
  The body-local release/use check is already covered; this entry is only about what the caller can
  prove after a callee returns.
- A per-field summary was prototyped and reverted because a release does not prove the storage
  remains empty on return. The missing proof is negative: the callee did not restore storage
  reachable from the caller. Establishing it requires excluding writes through aliases, so a
  release-only summary is insufficient.
- Next: assess whether the required alias proof is affordable and identify the smallest sound summary
  for callees whose bodies are unavailable.
- Done when: caller-side releases through receiver fields and globals are diagnosed without
  rejecting a reset that restores valid storage, with both cases covered in
  `bin/unittests/sanity/use_after_free.swg`.
- Related: compiler.safety.017.

### compiler.safety.011 — `!` and `late` stop asserting in release

- Area: language, runtime guards
- Evidence: `p!` is guarded by `.Expect` and an unset `late` read by `.Null` — two different
  assertions under two different flags, both off in `release` by default. A violated invariant gets a located panic in `devmode`; in unguarded `release`,
  the assertion itself does not diagnose the null. A later dereference can fault or reach an
  unrelated mapped address, depending on the address and offset. Naming either flag in `#[Swag.Safety]` restores its guard in `release`, so the gap is the
  default rather than the mechanism.
- Consequence: the located invariant diagnostic disappears exactly
  where it is hardest to reproduce. `!` is the spelling the language recommends for "an invariant
  makes this present, and a null here is a bug worth stopping on"; in `release` it stops on nothing
  it can name.
- Elsewhere: Rust's `unwrap` panics with a message in every profile. Zig makes it the difference
  between `ReleaseSafe` and `ReleaseFast`, which is the shape Swag already has — except that Swag
  has no named configuration for it, so every project that wants the guards has to discover
  `buildCfg.safetyGuards` and assemble one.
- Next: this is a packaging gap, not a default to flip. A guarded release — optimized code with
  `safetyGuards` on — should be a configuration the compiler registers and the reference names, so
  "ship it with the checks" is one flag rather than a build file nobody writes. Then measure it
  once, on an application, so the trade is a number and not a guess.
- Done when: a guarded release configuration exists and is documented, and its cost on one
  application workload is recorded.
- Related: compiler.safety.008 is what makes that configuration affordable.

### compiler.safety.017 — Allocation ownership has no static leak proof

- Area: compiler/sema, language
- Evidence: the four allocation-loss shapes in `cwe401_memory_leak.swg` compile without a static
  diagnostic: no release, release on one path, overwritten pointer, and an owner without `opDrop`.
  The runtime half already exists: `Allocator.stats` counts live allocations, `printLeaks` reports
  them at release, and `allocatorTrackAllocations` adds allocation details. DevMode enables
  `allocatorLeaks`; Release disables it by default. `allocator_debug_modes.swg` covers live counts,
  tracking and quarantine.
- What the "decide first" step now answers, and it is the obstacle rather than the cost: a static
  leak proof needs to know that a block MUST be released, and the language does not say so. Every
  allocation reaches the same `Swag.IAllocator.alloc`, whichever allocator is behind the interface,
  and the interface is a runtime value. `Memory.tempAlloc` in
  [alloc.swg](../bin/std/modules/core/src/memory/alloc.swg) allocates from the context's temporary
  allocator through that same method, and a block from an arena is legitimately never released —
  the arena is reset whole. A rule seeded on the interface would therefore report every temporary
  allocation as a leak, which is the false positive that decides a sanity rule's fate.
- Next: settle the ownership question before the analysis. Either the interface distinguishes an
  owning allocator from an arena (a property on `IAllocator`, or a distinct interface for one that
  never requires a release), or the leak rule is seeded on the standard entry points that promise
  ownership rather than on the interface, or leak detection stays with the allocator report. Count
  the arena and temporary allocation sites in `bin/` before choosing: that count is what says
  whether an interface split is affordable.
- Done when: the compiler either diagnoses a documented set of proven leak shapes with sound
  counterparts, or the reference explicitly limits leak detection to allocator diagnostics and
  the corpus reflects that decision.
- Related: compiler.safety.018.

### compiler.safety.018 — A release proven on one path only is never reported

- Area: compiler/backend, `Sanitizer`
- Evidence: `conditionalFree` in `cwe416_use_after_free.swg` releases inside an `if` and reads
  after it. The engine's join is an intersection, so the fact does not survive the merge and
  nothing is reported — which is what keeps the analysis free of false positives, and also what
  makes the shape a real program has, a release under a condition, invisible. The neighbouring
  limits were closed: a copy of the pointer into another local is now proven, and a release
  survives an ordinary call.
- Elsewhere: a path-sensitive analyzer (clang's, Infer) reports this class and accepts the false
  positives that come with it. That trade is not this repository's: a sanity proof is an error
  that fails the build in `release`, so it cannot be a maybe.
- Next: decide whether a MAY-release fact deserves a diagnostic of its own — a warning under the
  warning policy layer rather than an error, so the report exists without a build failing on a
  guess. Start by counting how many sites in `bin/` a may-analysis would name, which is what says
  whether the report is readable or noise.
- Done when: either a warning exists with its count on `bin/` recorded, or the reference states
  that a conditional release is outside what the proof covers and the corpus records the decision.
- Related: compiler.safety.017.

### compiler.safety.010 — An integer becomes an enum value that no member names

- Area: language
- Evidence: `cast(Color, 99)` is accepted with no check in any configuration, and the result is used
  as an ordinary `Color` — compared, switched on, indexed with. Nothing distinguishes it from a
  declared member. A plain switch can fall through on it. `switch #complete` already panics when
  `.Switch` safety is enabled; with that guard disabled, the conversion still permits a value
  outside the cases. The missing contract is at conversion, not the guarded switch.
- Elsewhere: Rust makes an out-of-range enum discriminant undefined behavior and forbids the
  conversion in safe code, requiring a `TryFrom` that returns an error; Swift's `init?(rawValue:)`
  returns an optional; C# permits it and is routinely criticized for it. A checked conversion is the
  majority position and the only one that composes with exhaustive matching.
- Next: decide the spelling. `cast(Color, i)` becoming a guarded conversion under `.DynCast` costs a
  compare in `devmode` and nothing in `release`; a fallible `Color.from(i)` returning `#null` puts
  the check in the type and needs no guard at all, which is the only form that also holds in a
  build with the dynamic guards off. `#[Swag.EnumFlags]` types accept combinations and must be
  excluded either way.
- Done when: converting an integer to an enum has one documented rule, the flags case is
  specified separately, and `bin/unittests` covers a valid value, an out-of-range value, and a flags
  combination.

### compiler.safety.014 — Nothing states what the safe subset guarantees

- Area: documentation, language
- Evidence: [013_002_safety.swg](../bin/reference/modules/language/src/013_002_safety.swg),
  [013_003_sanity.swg](../bin/reference/modules/language/src/013_003_sanity.swg) and
  [013_004_borrowing.swg](../bin/reference/modules/language/src/013_004_borrowing.swg) each describe
  a mechanism accurately, and no page says what a program written without the unsafe operations
  cannot do. A reader can learn that indexes are checked in `devmode` and that views cannot outlive
  their storage; they cannot learn whether a use-after-free is possible.
- Consequence: the language's actual position is stronger than its documentation implies in some
  places — definite initialization is total and there is no `undefined` escape hatch, non-null is the
  default with use-site proofs, errors must be handled, `const` cannot be cast away — and weaker in
  others. Neither is legible, so the language gets judged on its mechanisms rather than on its
  guarantee.
- Next: this entry is written last on purpose. The statement cannot be written honestly until
  compiler.safety.006 and 008 are decided, because each one changes what belongs in it. What can
  be done now is the inventory: one page listing every fault class, what excludes it today, and in
  which configuration.
- Done when: the reference carries one page stating, per fault class, whether the safe subset
  excludes it, in which build configurations, and by which mechanism — and every claim on it is
  backed by a test in `bin/unittests`.
- Related: compiler.safety.006, compiler.safety.008.

### compiler.safety.007 — A foreign function is opaque to every safety analysis

- Area: compiler/sema, `SemaEscape`
- Evidence: `#[Swag.BorrowSummary]` can be written by hand on a `#[Foreign]` declaration, and the
  reference says so — but nothing requires it, nothing checks it against the callee, and a foreign
  function with no summary is treated as borrowing, storing and freeing nothing. A C function that
  keeps the pointer it was handed is indistinguishable from one that does not.
- Consequence: every `win32` and system binding is a hole in the borrow rules that no diagnostic
  marks. This is inherent — the compiler cannot see the callee — which is exactly why it belongs on
  the unsafe surface rather than inside the analysis.
- Next: decide the default. Either a foreign call is one of the operations that requires the marker
  from compiler.safety.006, or a foreign declaration without a written summary is assumed to store
  everything it receives and the bindings are annotated. Measure the second option against
  `bin/std/modules/win32` before choosing.
- Done when: the foreign boundary has one documented default, and the reference says what
  crossing it suspends.
- Related: compiler.safety.006.

### compiler.safety.029 — Converting an indexed heap pointer invents a container borrow

- Area: compiler/sema, `SemaEscape::indexEscapeInfo`
- Evidence: storing allocated blocks in `[2] ([*] u8?)` and passing `blocks[0]` to an
  inline release wrapper taking `[*] void?` reports `sanity_err_free_borrowed` against
  the local array. Reading the element through value iteration is accepted. The
  allocator benchmark's aligned batch exposed this with `Core.Memory.free`.
- Next: distinguish the element's type before a contextual pointer conversion from
  the converted result while retaining the stored pointee's provenance. Reading
  only the index's stored type accepts the owned case, but also loses the diagnostic
  for a slice over an array containing a pointer to a local. Trace that alias back to
  its element projection; do not treat every indexed pointer as independently owned.
- Done when: releasing owned pointer elements works through arrays, slices, and
  pointer conversions, while releases of local borrows stored in those containers
  remain diagnosed by focused sanity tests.
