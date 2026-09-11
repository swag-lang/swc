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
spelled like ordinary code. The entries below are ordered from the most recently updated down.

The fault-class entries use [bin/unittests/safety/corpus](../bin/unittests/safety/corpus):
one file per CWE, a fault half that names the diagnostic it expects and a sound half that must
stay silent. Unsafe gap examples are commented out and tagged with their owning entry; safe
wrong-value probes may remain executable. Analysis, API, performance, and documentation entries
also name their own evidence below; they do not all have a CWE reproducer. `rg "GAP " bin/unittests/safety/corpus`
is the current scorecard.

[README.md](README.md) defines the shared backlog conventions.

### compiler.safety.023 — Opaque result provenance is incomplete for fields and early JIT

- Recorded: 2026-09-08 20:48
- Updated: 2026-09-11 15:47 — Narrow the remaining work to returned fields and pre-drain guarded releases.
- Area: compiler/sema, `SemaEscape`
- Evidence: an opaque factory returning a heap carrier whose `target` field holds `&local`
  leaves `release(carrier.target)` undiagnosed. This was confirmed in a semantic-only helper
  body with `swc.dm` 0.1.417 in `release`, without executing the invalid free. The early
  `propagateCompletedFreesSummaries` pass also skips guarded edges while `#run` drives sema:
  their return routes have not reached the module-wide fixpoint yet.
- Cause: the member-access walker deliberately drops a copied pointer field's enclosing
  borrow, because that field need not alias the container. A factory's return-borrow mask
  cannot identify the field carrying each parameter. Early JIT emission needs completed
  return routes before a guarded release can distinguish an alias from an owned payload.
- Next: design returned-field provenance before extending pointer-field diagnostics. Cover
  a carrier with both a borrowed field and an independently allocated field, including through
  generated module APIs. For `#run`, resolve guarded return routes within the completed call
  graph before publishing frees; never read an unfinished callee's summary or execute an
  invalid free merely to probe whether it is diagnosed.
- Complete when: borrowed returned fields and early guarded releases are diagnosed without
  rejecting releases of independent allocations or payloads, and the focused sanity, JIT and
  workspace regressions pass with measured cost.

### compiler.safety.020 — A release through storage a callee could re-establish is not judged

- Recorded: 2026-09-08 09:05
- Updated: 2026-09-11 14:38 — The nullable projection prerequisite is implemented and covered by borrow regressions.
- Area: compiler/sema, `SemaEscape`
- The half that no longer needs anything: a release helper that reaches for what it just
  released is proven inside its own BODY, because the receiver names the object there and
  no summary has to cross a call. `mtd releaseThenTouch() { heapFree(.data!, 4); .data![] = 0 }`
  is a compile-time error, while the same method putting the field back - with null or with
  a fresh allocation - stays silent. What remains is the CALLER side alone.
- Evidence: two shapes, one blocker. A release reached through a FIELD of the receiver:

  ```
  impl Node { mtd release() { if .data != null do heapFree(.data!, 4) } }
  var node: Node
  node.data = cast(*s32) heapAlloc(4)
  node.release()
  return node.data![]     // silent
  ```

  and a release of what a GLOBAL owns:

  ```
  var owned: *s32?
  owned = cast(*s32) heapAlloc(4)
  heapFree(owned!, 4)
  return owned![]         // silent
  ```

  Every other storage class a program keeps a pointer in — a parameter, an element of a
  local table, a field of a local, a copy into another local, and the return itself — is
  proven. These two are what is left.
- The per-field summary was implemented end to end and reverted, because a release is not
  on its own a statement about what the storage holds on return:

  ```
  mtd reset() { heapFree(.data!, 4); .data = cast(*s32) heapAlloc(4) }
  node.reset()
  node.data![] = 1     // CORRECT, and a per-field FREES mark reports it
  ```

  A release helper normally does something with the storage afterwards, and the summary
  cannot tell that apart from leaving it dangling. The global shape has the same hole from
  the other side: any callee may write any global, so the freeing call is itself what would
  invalidate the fact it creates.
- Why this is not a small addition: the missing half is a NEGATIVE fact — *the callee does
  not write this storage before returning*. A positive fact needs one witness; a negative
  one needs every write form excluded, including a store through a pointer that could reach
  the storage, which is alias analysis. That is the honest size of this entry, and it is why
  the implemented half was not shipped on its own.
- What the attempt established, for whoever takes it: the seeding (a call argument whose
  storage projection is a field of one of the caller's parameters), a `FieldToFrees` summary
  edge kind, and the fact that the chaining must ALSO run in
  `propagateCompletedFreesSummaries` — the early fixpoint — because the backend reads these
  summaries while it lowers, and a fact only the final drain publishes arrives after the
  call site it judges. `storageProjection` now sees through `x!`; nullable receiver paths
  are covered by `bin/unittests/sanity/borrow_invalidation.swg`.
- Next: decide whether the negative fact is affordable at all. The cheaper direction this
  entry named has since landed on its own — the body of a release helper is judged where it
  is written — so what is left is only the caller, and only for a helper whose body the
  caller cannot see. Weigh that against the cost before building it.
- Complete when: both shapes above are compile-time errors, the `reset` shape and the
  carrier case stay silent, and all of them are in `bin/unittests/sanity/use_after_free.swg`.
- Related: compiler.safety.017.

### compiler.safety.006 — Raw memory operations have no common unsafe opt-in

- Recorded: 2026-09-04 17:05
- Updated: 2026-09-10 19:35 — Preserve the dated reinterpretation census without presenting it as a current inventory.
- Area: language
- Evidence: a short list of operations can produce a pointer to anything, and none of them is
  subject to one common unsafe opt-in or a compiler mode that excludes all of them. Individual
  casts and intrinsics are visible, but no single marker identifies the boundary:
  - `cast(*T) someInteger` — an arbitrary integer becomes a pointer;
  - `cast(*Big) &small` — CLOSED on 2026-09-08: a pointer cast between two structs with no `using`
    path either way is `sema_err_cast_unrelated_structs`, and the deliberate reinterpretation is
    spelled `cast(*Big) cast(*void) &small`;
  - `Swag.makeSlice(ptr, count)` / `makeString` / `makeAny` / `makeInterface` — a length paired with
    storage that need not have it, after which every bounds check faithfully checks the lie;
  - pointer arithmetic on `[*] T`, which has neither provenance nor extent;
  - reading a `union` member that was not the one written, which turns an integer into a pointer
    with no cast at all;
  - `Swag.memcpy` / `memset` / `memmove`, whose byte count is unrelated to either operand;
  - `#relocate` and `#nodrop`, which suspend the lifecycle;
  - any call to a `#[Swag.Foreign]` function (compiler.safety.007).
  Each was verified to compile and to read out of bounds with no diagnostic, except the struct-pointer
  one, now closed.
- Historical census (2026-09-08): the rule rejected **32 sites in 3 files** in the
  `bin/` build exercised then, and every one of them is a Win32/COM binding -
  `audio/driver/xaudio2.swg` (10, a COM voice handed to a base-voice entry point),
  `gui/dragdrop.win32.swg` (7) and its test (15), which recover a Swag object from the OLE
  interface pointer it starts with. That run reported none in its application, example, reference, or runtime selections.
  This is historical evidence, not a census of all four current applications and tagged tests;
  the health reset subsequently corrected a cast in Vault's explicitly tagged COM integration test. The reinterpretation surface is therefore not spread through the
  codebase: it is a binding-layer boundary, small enough that the marker this entry wants can be
  written for it, and `*void` already makes each one visible to `grep`.
- Consequence: Swag cannot state what its safe subset guarantees, because it has no safe subset —
  only a set of checks with no boundary. That is the difference between "the compiler catches a lot"
  and "this class of fault cannot occur here", and it is the difference a reader arriving from Rust
  is actually asking about.
- The shape must be Swag's, not Rust's. A block that swallows a page of code is the wrong unit here:
  the operations above are single expressions, and Swag already spells a compiler instruction on an
  expression with `#`. A modifier on the operation (`#unsafe cast(*T) addr`) plus one file-level
  opt-in (`#global #[Swag.Unsafe]`) for a binding or codec layer costs application code nothing,
  marks `bin/std`'s low-level modules once, and makes `grep` the audit tool.
- The census the previous next action asked for, run on 2026-09-08 13:34 over `bin/` with the vendored
  `.dep` and `.output` copies and `bin/unittests` excluded, so every number is a shipped site:

  | Operation | std | apps | examples | reference | runtime | shipped |
  | --- | --- | --- | --- | --- | --- | --- |
  | pointer-producing `cast` | 889 | 551 | 13 | 24 | 116 | **1593** |
  | `Swag.makeSlice` | 348 | 55 | 2 | 11 | 10 | 426 |
  | `Swag.makeString` | 79 | 32 | 1 | 4 | 13 | 129 |
  | `Swag.memcpy` / `memset` / `memmove` | 27 | 25 | 0 | 12 | 20 | 84 |
  | `Swag.makeInterface` | 35 | 2 | 0 | 3 | 3 | 43 |
  | `#relocate` | 26 | 0 | 0 | 6 | 0 | 32 |
  | `#nodrop` | 26 | 0 | 0 | 6 | 0 | 32 |
  | `Swag.makeAny` | 5 | 0 | 0 | 4 | 2 | 11 |
  | `#[Swag.Foreign]` | 9, plus 21 in the win32 family | 13 | 0 | 7 | 3 | 53 |

- What the count answers is not what the question expected: the cast row is the whole
  problem, and it is not pointer forging. Of the 551 casts in the applications, 537 name a
  user type and 9 name a primitive; 343 of them read as `cast(*MainWnd) cxt.wnd!`,
  `cast(*HexViewer) wnd`, `cast(*TextView) session.view!` — recovering a concrete type from
  a base pointer in a hand-rolled hierarchy. `bin/std` is the same story, 404 user types
  against 56 primitives, plus the opaque-handle round trip the drivers and the generic
  containers are written with. An integer becoming a pointer is nowhere in that population.
- Consequence for the design: the marker is unaffordable while the dominant idiom has no
  safe spelling. Marking 1593 sites, or opting most of `bin/std` and all three applications
  out at file level, does not draw a boundary - it moves it. The affordable order is the
  reverse of what this entry assumed: give the downcast a checked spelling first, then count
  what is left, and only then choose the marker.
- The mechanism already exists, and half of it is already hand-rolled. `Swag.typeAs` and
  `Swag.typeIs` (`bin/runtime/core.swg:21,57`) already walk the `using` graph: they iterate
  `usingFields`, recurse into nested bases, adjust the pointer by each field's offset, and follow
  a `using` on a pointer field. Every `case T as x` over an `any` or an interface calls them. What
  they need is `fromType`, the CONCRETE type - exactly what a bare `*Wnd` does not carry. The
  missing piece is one fact, not a mechanism.
- And `Gui.Wnd` already carries that fact by hand: `late type: typeinfo` ("Runtime type of the
  concrete window allocation"), written as `res.type = T` in the generic `Wnd.create'T`, the single
  funnel every window is born through. The language would be sanctioning a field the library
  already maintains, not inventing one.
- Measured on `bin/` on 2026-09-08 15:08: 259 structs compose with `using`; the `using` member is
  the FIRST member in 288 of 299 declarations, and in every window, view and event type, so a
  `*Wnd` IS the address of the complete object - no offset-to-complete, no per-subobject tag, none
  of the C++ multiple-inheritance vptr machinery. The deepest chain is 3
  (`EditWnd` - `ScrollWnd` - `FrameWnd` - `Wnd`), and only two shipped structs carry several
  `using` members (`Surface{native, state}`, `EditBox{wnd, minMax}`): in both, one base plus a data
  mixin nothing ever recovers.
- A fat pointer carrying the typeinfo beside the address was considered and rejected. Inside a
  method of the base, `me` is already a plain `*Wnd`, so the concrete type is lost before the value
  is ever stored; keeping it would force `children`, `parent` and every `*Wnd` parameter to widen -
  viral, and it doubles the window tree. The tag belongs in the object.
- What the absence costs, measured while writing this: `Wnd.revealFocus` tested
  `parent.type == ScrollWnd`, an EQUALITY, so revealing the focus silently did nothing for all five
  shipped viewports built by composition (`EditWnd`, `QuickWnd`, `RecentWnd`, `SheetWnd`,
  `WidgetWall`). Fixed with `Swag.typeAs` and a regression test in
  `bin/std/modules/gui/src/tests/scroll.test.swg`; `isEditorWnd` in `properties.keyboard.swg` had
  the same shape and was made robust. Hand-rolling the tag makes the exact-versus-ancestor mistake
  the default one.
- Next: recount the current reinterpretation boundary, including tagged native integration
  tests, then give the remaining operations their marker. They are one population - a binding
  recovering its own object from an ABI header - so a file-level opt-in on the two binding files
  costs application code nothing and states the boundary in two places instead of thirty-two.
  Decide between that and a per-expression `#unsafe`, then apply it and delete the `*void` hops.
- Complete when: the unsafe operation list is fixed and documented, safe code cannot reach any of
  them without a visible marker, `bin/` compiles with the boundary enforced, and the reference
  states which faults the safe subset excludes.
- Related: language.design.002 narrows the union bullet rather than removing it. The census in that
  entry found eight anonymous unions in `bin/`: two sum types that a tag would check, five C-ABI
  bindings that must stay byte-compatible, and one deliberate bit view. The untagged form therefore
  survives at the interop and bit-punning boundary, which is where the marker belongs and where it
  joins compiler.safety.007. Also compiler.safety.014.

### compiler.safety.011 — `!` and `late` stop asserting in release

- Recorded: 2026-09-04 17:05
- Updated: 2026-09-10 19:35 — Use the current late-field spelling and qualify the unchecked-null outcome.
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
- Complete when: a guarded release configuration exists and is documented, and its cost on one
  application workload is recorded.
- Related: compiler.safety.008 is what makes that configuration affordable.

### compiler.safety.022 — A COM object's ABI header is held first by a comment, not by the language

- Recorded: 2026-09-08 18:59
- Area: `std/gui`, language
- Evidence: the four OLE objects in `gui/dragdrop.win32.swg` each open with the interface header
  OLE calls through, and each says so in a comment - `lpVtbl: *IDropTargetVtbl?  // Interface
  header OLE calls through; must stay first.` Recovering the Swag object is then C's `container_of`:
  `cast(*SurfaceDropTarget) itf`. Nothing checks the invariant the comment states, so inserting a
  field above `lpVtbl` silently breaks every callback OLE makes.
- The fix the language already offers, and why it did not land with compiler.safety.006: writing
  `using base: IDropTarget` instead of the copied field makes the composition real, the recovery a
  checked descent, and the offset computed rather than assumed. It was built and reverted the same
  day: `IDropTarget.lpVtbl` is non-nullable, so composing it leaves `SurfaceDropTarget` with no
  valid implicit default, and `Memory.new'DragFormatEnum()` and `Memory.new'Surface()` stop
  compiling. The blocker is a zero-initialized struct owning a non-nullable pointer, not the
  composition itself.
- Next: decide how a composed ABI header reaches its vtable pointer under zero-initialization -
  a nullable `lpVtbl` in the four `ole32.swg` interface structs, a `late` field, or an explicit
  constructor at each creation site - then compose the four objects and delete their `cast(*void)`.
- Complete when: the four OLE objects compose their interface, the recovery is a checked descent,
  and no comment in the file asks a field to stay first.
- Related: compiler.safety.006 counts these among its 32 residual reinterpretation sites.

### compiler.safety.017 — Allocation ownership has no static leak proof

- Recorded: 2026-09-04 19:35
- Updated: 2026-09-08 09:18 — the allocator is a runtime value, so "allocated" does not imply "must be released"
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
- Complete when: the compiler either diagnoses a documented set of proven leak shapes with sound
  counterparts, or the reference explicitly limits leak detection to allocator diagnostics and
  the corpus reflects that decision.
- Related: runtime.allocator.010, compiler.safety.018.

### compiler.safety.019 — The sanity pass's own cost is unmeasured after the lifecycle widening

- Recorded: 2026-09-08 07:59
- Area: compiler/backend, `Sanitizer`
- Evidence: the lifecycle facts now survive calls, which keeps the engine's per-instruction maps
  populated over far more of a function than before, and the transfer function gained a scan of
  the convention's argument registers at every call. One cold `std` build with each compiler gave
  1 min 23 s against 2 min 21 s, but the per-module split of that same pair is incoherent — `core`
  20.6 s against 4.6 s, `pixel` 7.3 s against 56.6 s — so the run measured machine noise, not the
  pass. No conclusion may be drawn from it in either direction.
- Next: measure the pass alone rather than a whole build: `--stats` build-phase profiling on one
  module, DevMode compiler, three runs each, with the machine otherwise idle.
- Complete when: the sanity pass's share of compile time is recorded before and after, and either
  found acceptable or reduced.

### compiler.safety.018 — A release proven on one path only is never reported

- Recorded: 2026-09-08 07:59
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
- Complete when: either a warning exists with its count on `bin/` recorded, or the reference states
  that a conditional release is outside what the proof covers and the corpus records the decision.
- Related: compiler.safety.017.

### compiler.safety.004 — Diagnostic allocation does not intercept a stale heap read

- Recorded: 2026-09-04 17:05
- Updated: 2026-09-06 07:51 — git: prompt 6
- Area: runtime/allocator, `bin/runtime`
- Evidence: lifecycle guards poison moved or dropped storage. The runtime allocator also supports
  allocation tracking, freed-byte fill, a bounded diagnostic quarantine, double-free diagnostics
  and electric allocations ending at a guard page. Electric mode retains freed addresses, but
  `freeHeaderBlock` leaves their payload readable; `checkFree` can find a changed fill pattern,
  not a read that leaves it intact. `allocator_debug_modes.swg` explicitly reads the freed pattern.
  Ordinary page allocations reuse storage and provide no stale-read instrumentation.
- Next: evaluate a diagnostic mode that makes a freed payload inaccessible while retaining enough
  metadata to diagnose release errors, or instrument reads. Measure its cost on an application
  workload and specify how it composes with the existing electric/quarantine modes.
- Complete when: a stale read through an alias is detected at the read in the selected diagnostic
  mode, with its limits and measured cost documented; Release defaults remain unchanged.
- Related: runtime.allocator.010.

### compiler.safety.008 — Dynamic bounds checking is switched off in release instead of being made cheap

- Recorded: 2026-09-04 17:05
- Updated: 2026-09-06 07:51 — git: prompt 6
- Area: compiler/backend, optimization
- Evidence: `buildCfg.safetyGuards` is `None` in `release`, so `a[i]` with a runtime `i` reads out of
  bounds silently; the same program panics in `devmode`. The static half still covers what it can
  prove — a constant index, and an index the value analysis folds to a constant, are rejected at
  compile time *in release* — but a genuinely dynamic index is unchecked.
- Prior decision (2026-07-08, do not re-litigate on the same evidence): the cost was measured at
  +7-8% on a worst-case tight indexed-sum loop and +2% on a data-dependent double lookup, and
  `release` deliberately kept `safetyGuards = None`.
- What has not been measured is the same question with the checks made cheap. That measurement was
  taken against code generation that emits `cmp`/`jb`/call at every index and has no pass dedicated
  to removing them. The two idiomatic Swag forms — `for v in arr` and `for i in arr.count` — are
  provably in range on every iteration, and a range analysis over the Micro SSA removes those checks
  where a guard was emitted for an explicit index. Direct element iteration already uses the
  compiler's own traversal; it must be measured separately from indexed accesses. The remaining
  cost belongs to checks that cannot be proven redundant.
- Next: implement bound-check elimination as a backend pass (induction-variable range against the
  container's `.count`, dominating comparisons, constant indices), then re-measure the two loops
  above with guards on. The deliverable is the pass, not a change of default: `release` stays
  guard-free, `devmode` pays this cost on every index today, and a build that turns the guards on
  deliberately is exactly the build the pass is for.
- Complete when: a bound-check-elimination pass exists, `devmode` compile time and generated code
  are measured before and after, and the residual cost of `.BoundCheck` on the two loops above is
  recorded next to the 2026-07-08 numbers.
- Related: [compiler.optimization.md](compiler.optimization.md) owns the pass once it is scoped.

### compiler.safety.010 — An integer becomes an enum value that no member names

- Recorded: 2026-09-04 17:05
- Updated: 2026-09-06 07:51 — git: prompt 6
- Area: language
- Evidence: `cast(Color) 99` is accepted with no check in any configuration, and the result is used
  as an ordinary `Color` — compared, switched on, indexed with. Nothing distinguishes it from a
  declared member. A plain switch can fall through on it. `switch #complete` already panics when
  `.Switch` safety is enabled; with that guard disabled, the conversion still permits a value
  outside the cases. The missing contract is at conversion, not the guarded switch.
- Elsewhere: Rust makes an out-of-range enum discriminant undefined behavior and forbids the
  conversion in safe code, requiring a `TryFrom` that returns an error; Swift's `init?(rawValue:)`
  returns an optional; C# permits it and is routinely criticized for it. A checked conversion is the
  majority position and the only one that composes with exhaustive matching.
- Next: decide the spelling. `cast(Color) i` becoming a guarded conversion under `.DynCast` costs a
  compare in `devmode` and nothing in `release`; a fallible `Color.from(i)` returning `#null` puts
  the check in the type and needs no guard at all, which is the only form that also holds in a
  build with the dynamic guards off. `#[Swag.EnumFlags]` types accept combinations and must be
  excluded either way.
- Complete when: converting an integer to an enum has one documented rule, the flags case is
  specified separately, and `bin/unittests` covers a valid value, an out-of-range value, and a flags
  combination.

### compiler.safety.014 — Nothing states what the safe subset guarantees

- Recorded: 2026-09-04 17:05
- Updated: 2026-09-05 10:30 — git: Take the copy away from a type that owns what it releases
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
- Complete when: the reference carries one page stating, per fault class, whether the safe subset
  excludes it, in which build configurations, and by which mechanism — and every claim on it is
  backed by a test in `bin/unittests`.
- Related: compiler.safety.006, compiler.safety.008.

### compiler.safety.005 — A pointer into a value survives the move of that value

- Recorded: 2026-09-04 17:05
- Area: compiler/sema, `SemaEscape`
- Evidence: a struct holding a pointer into its own storage keeps that pointer after `#move`, and it
  then addresses the abandoned source. `a.head = &a.buf[0]; var b = #move a; b.head![] = 7` writes
  into the dead `a`, and `b.buf[0]` is unchanged. Silent in every configuration.
- Consequence: narrow but real, and it is the one place where Swag's byte-copy move has no
  counterpart to the rule that protects it elsewhere. The analysis already tracks a borrow of a
  local across a move (`let p = &a.x; var b = #move a; p[]` is caught); what it does not track is a
  borrow stored *inside* the value being moved.
- Next: decide whether this deserves a rule at all before building one. The honest first step is a
  sweep: does any type in `bin/` hold a pointer into itself? If none does, record the answer and
  reduce this entry to the documentation of a known limit.
- Complete when: self-referential storage is either rejected at the move, or documented as
  unsupported with the sweep result recorded.

### compiler.safety.007 — A foreign function is opaque to every safety analysis

- Recorded: 2026-09-04 17:05
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
- Complete when: the foreign boundary has one documented default, and the reference says what
  crossing it suspends.
- Related: compiler.safety.006.
