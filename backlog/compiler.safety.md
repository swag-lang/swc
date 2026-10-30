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

### compiler.safety.030 — Measure the runtime cost of value-borrow guards

- Evidence: `bin/unittests/native/functions/value_borrow_cost.swg` compares identical
  native small-argument and block-sum calls with only `.ValueBorrow` toggled. The
  [focused measurements](../bench/results/safety/20261016-value-borrow.md) retain samples
  and compiler rebuild CPU/memory controls, but shared-machine drift prevents a tight bound.
  Frame-write proofs and an inline address-extent test avoid unnecessary runtime checks.
  `Pass.ValueBorrowFastPath` also hoists the extent load before eligible loops, or to function
  entry when the function calls only write checks and fault reports; a call-free function
  with no remaining write check registers no borrow. Earlier same-program comparisons found
  about 1.9x for nbody, 1.4x for fannkuch and 1.3x for dijkstra; they predate the latest hoists
  and do not establish their current overhead.
  CPU backdrop convolution also exposes process-wide registration-lock contention: a native
  DevMode Gaussian pass exceeded 300 seconds with the default worker pool, while a single
  worker completed the scene. Small `Vector4` arithmetic repeatedly enters and leaves the
  same registry. Packed SIMD channel arithmetic removes that pressure from this renderer,
  but ordinary parallel value calls still need a scalable guard. A sharded prototype passes
  128 native borrow tests, including cross-thread writes, but its permanently widened extent
  and empty-registry write cost need measurement before adopting that runtime design.
- Next: repeat the paired fixture on a quiet machine with an unchanged A/A control, then
  measure a representative application. Attribute remaining loop checks, argument copies,
  cold failure-call layout and per-value-parameter borrow registration before choosing another
  change. Include parallel small-value arithmetic, shard collisions, and writes after the last
  borrow closes; retain cross-thread conflicts and panic checkpoints. Checking a writing
  function's own ranges inline still needs a runtime entry that
  reports a conflict. Tiny-call ratios must not stand in for application overhead.
- Done when: reproducible measurements state the workload, compiler and program configurations,
  guard settings and variability, and give a bounded assessment of the runtime overhead.
- Related: compiler.safety.006, compiler.safety.020, compiler.safety.023,
  language.parallelism.005.

### compiler.safety.023 — Opaque results lack pointer-field provenance

- Evidence: a no-inline factory can store `&local` in `carrier.borrowed` and an independent
  allocation in `carrier.owned`. `release(carrier.borrowed)` is then accepted with no
  diagnostic, while a direct `release(&local)` reports `sanity_err_free_borrowed`. Copied-field
  lifetime routes and returned payload projections (`25b9598b6`, `e1b81113e`) do not
  distinguish the borrowed pointee of this opaque heap result. Propagating the carrier's
  enclosing borrow wholesale would also reject releasing the independently allocated field.
- Next: trace this returned-field route through the existing projection and frees-summary
  machinery, then preserve each field's provenance. Cover both fields through generated
  module APIs; never execute an invalid free merely to probe its diagnostic.
- Done when: borrowed returned fields are diagnosed without rejecting releases of
  independently allocated fields, and the focused sanity and workspace regressions pass
  with measured cost.

### compiler.safety.019 — Bound current sanity cost and attribute retained-state storage

- Evidence: the [current profile](../bench/results/safety/20261016-moved-writes-and-sanity.md)
  observes sanity at 5.5% of compiler CPU cycles on core devmode and 2.8% on full-std
  release, with no iteration-cap hits. Propagation and checking perform most transfer
  work. Logical retained register/stack payload peaks at 1.26/1.86 MiB per invocation;
  spare capacity, hash storage, transient copies and allocator overhead remain unattributed.
  Unchanged timing controls varied by over 10x, preventing a tight wall/CPU-time bound.
- Next: measure actual retained capacity and heap overhead, then repeat quiet A/A controls
  before accepting an elapsed-time bound. Use the phase and visit counts to isolate
  transfer/state work without weakening proofs or changing analysis limits.
- Done when: current CPU and state-heap costs are attributed and accepted or reduced with
  a repeatable comparison and the safety/sanity behavior preserved.
- Related: compiler.core.005.

### compiler.safety.008 — Runtime bound guards still impose measurable hot-loop cost

- Evidence: `release` builds without runtime guards; `devmode`, and any build enabling
  `.BoundCheck`, pays them. Range and repeated-guard proofs plus cold-block layout already
  remove settled checks and move failure paths off the common path. The guards still cost
  `devmode` about 1.24x across the twelve `bench/` programs against the same build without
  runtime guards. Hot gaps: loop-bounded indices, repeatedly loaded counts, and
  loop-invariant `late` checks.
- Next: prove an index against the dominating loop bound and hoist a `late` check from a
  loop that does not assign it. Measure the affected loops with guards enabled and disabled.
- Done when: loop-bounded indices and invariant `late` values need no repeated guard, and
  the residual cost of runtime guards is measured on the affected loops with behavior
  preserved.
- Related: compiler.optimization.105.

### compiler.safety.024 — A mutable cast can write through an any that borrows a literal

- Evidence: `var boxed: any = 42's32` followed by a mutable `try cast(*s32, boxed)` (or the
  `is ... as` type pattern) and a write through the result is accepted. The JIT test
  passes, but the native executable raises `0xC0000005` writing the literal in read-only
  storage. A variable holding an `any` does not itself own mutable storage for the borrowed
  value.
- Next: decide and enforce the constness of literal-backed and constant-backed `any` views.
  Inspect constant boxing, runtime type qualifiers, and dynamic cast destinations together;
  choose rejection of mutable views or deliberate writable materialization without turning
  `any` into an owning variant. Audit existing casts of literal-backed views before
  migration.
- Done when: JIT and native execution agree, a mutable cast cannot expose read-only literal
  storage, and tests cover literal, constant, mutable-local, and const-local sources.

### compiler.safety.006 — Raw memory operations have no common unsafe opt-in

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

- Evidence: `unwrap p` is guarded by `.Expect` and an unset `late` read by `.Null` — two different
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
  once, on an application, so the trade is a number and not a guess. Making it affordable
  depends on compiler.safety.008.
- Done when: a guarded release configuration exists and is documented, and its cost on one
  application workload is recorded.
- Related: compiler.safety.008.

### compiler.safety.017 — Allocation ownership has no static leak proof

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
  compare in `devmode` and nothing in `release`; a fallible `Color.from(i)` returning `null` puts
  the check in the type and needs no guard at all, which is the only form that also holds in a
  build with the dynamic guards off. `#[Swag.EnumFlags]` types accept combinations and must be
  excluded either way.
- Done when: converting an integer to an enum has one documented rule, the flags case is
  specified separately, and `bin/unittests` covers a valid value, an out-of-range value, and a flags
  combination.

### compiler.safety.014 — Nothing states what the safe subset guarantees

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

### compiler.safety.031 — Partial reinitialization clears the entire moved-from proof

- Evidence: after `var target = #move source` on a two-s32 struct, `source.first = 23`
  makes `return source.second` compile without `sanity_err_use_after_move`, although
  the second field still contains lifecycle poison. The live safe wrong-value probe
  in [cwe672_use_after_move.swg](../bin/unittests/safety/corpus/cwe672_use_after_move.swg)
  records it. `clearMovedFromOverlaps` erases an entire range on any overlapping store
  and uses a conservative 16-byte width, including for a known four-byte store.
- Next: trim or split moved ranges with proven store widths, and test read extents
  against remaining ranges. Cover untouched-field reads and old-pointer writes after
  a partial reset; keep full reassignment, unknown writes and post-move repair sound.
- Done when: writing one field preserves proofs for untouched moved-from fields,
  complete reinitialization remains accepted, and focused corpus/sanity checks pass
  with measured cost and without a new whole-program pass.

### compiler.safety.032 — An inlined body ignores its own Sanity attributes

- Evidence: the static sanity mask is computed once per emitted function
  (`attributes().effectiveSanityMask` in `Symbol.Function.Jit.cpp`), so a callee inlined into
  its caller is judged with the caller's mask. `#[Swag.Sanity(.Math, false)]` on a function
  whose body `#run` inlines did not stop `sanity_err_invalid_argument` inside that body; the
  [cwe369 corpus case](../bin/unittests/safety/corpus/cwe369_divide_by_zero.swg) now uses
  `NoInline` instead. Runtime guards already follow the inline payload's `runtimeSafetyMask`.
- Next: carry the inline expansion's sanity mask to the instructions it lowers, the way the
  runtime mask reaches code generation, and let each sanitizer check consult the mask of the
  instruction it reports on. Cover an inlined callee that disables a check its caller keeps,
  and the reverse.
- Done when: an inlined body is judged by its own `Swag.Sanity` attributes in both
  directions, and the sanity suite passes with the new cases.
- Related: compiler.safety.019.

### compiler.safety.033 — Invalidate payload borrows when a tagged union changes its case

- Evidence: `let p = &u.circle; u = .Rect{w: 1, h: 2}; p.radius` compiles and reads the bytes of
  the rectangle. View invalidation (`sanity_err_borrow_invalidated`, recorded by
  `SemaEscape::noteBorrowInvalidation`) is tied to structural-mutation callees, and a tagged-union
  assignment is not one. Payload access itself is checked: only a view taken earlier escapes it.
- Next: record an invalidation of the union's payload views on every tagged-union assignment,
  where `SemaTagged::noteAssignedCase` already kills the case proofs, and add sanity tests for a
  view read after a transition, through a pointer and through a `using` holder.
- Done when: a payload view read after a transition of its union is diagnosed, and a view taken
  after the transition is not.
- Related: language.design.002.
