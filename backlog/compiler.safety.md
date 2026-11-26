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

### compiler.safety.032 — Confirm native terminal-expect reporting on Windows

- Evidence: commit `017485df` changed the fixtures to match the safe contract: a terminal panic
  cleans up captured errors and records one failed test, then stops the native process instead of
  running another test after its frame was abandoned. The current tests are
  `Compiler_NativePanicReleasesCapturedErrorsBeforeStop` and
  `Compiler_ExplicitExpectStopsThroughInlineExpansion`; both pass in the Linux DevMode C++
  filesystem suite. Windows has not been rechecked against these updated expectations.
- Next: run `swc.dm unittest --dev-full` on Windows and verify both fixtures report
  the failed tally before the native process stops.
- Done when: both fixtures pass with the terminal panic contract on Windows.

### compiler.safety.031 — Preserve inline-string views across interface calls

- Evidence: `Core.Log.print` produced fourteen zero bytes when it passed a local `String`'s
  `toString()` view through a local `string` variable to `ILogWriter.print`. The local owner remained
  in scope, and calling `w.print(rendered.toString())` directly fixed the log test. Longer,
  heap-backed messages did not reproduce the failure. Linux native DevMode and Release tests now
  pass for both a short inline `String` view passed through a local interface callback and
  `Core.Log.print` with a short formatted result. A direct/interface comparison also found that
  escape analysis diagnosed a concrete retaining call but missed the same call through an interface.
  Concrete implementation summaries now cover statically known local and imported interface targets;
  focused sanity and workspace consumer tests keep non-retaining calls silent and reject retained
  local views. Mutable frame-local interface bindings also use the concrete summary while their
  storage remains unaddressed; assignments, address-taking and by-reference captures invalidate
  that proof.
- Next: reproduce the original fourteen-byte failure on Windows with a regression that preserves
  the exact `StringBuilder` and writer call path. Then trace borrow/liveness analysis and generated
  code, and ensure an actual escaping view still receives its existing diagnostic.
- Done when: the compiler either keeps the inline string valid through the callback or rejects the
  invalid lifetime before code generation, with positive and negative regressions covering both
  cases.

### compiler.safety.030 — Measure the runtime cost of value-borrow guards

- Evidence: `bin/unittests/native/functions/value_borrow_cost.swg` compares identical
  native small-argument and block-sum calls with only `.ValueBorrow` toggled. Shared-machine
  drift prevents a tight timing bound.
  Frame-write proofs and an inline address-extent test avoid unnecessary runtime checks.
  `Pass.ValueBorrowFastPath` also hoists the extent load before eligible loops, or to function
  entry when the function calls only write checks and fault reports; a call-free function
  with no remaining write check registers no borrow. Earlier same-program comparisons found
  about 1.9x for nbody, 1.4x for fannkuch and 1.3x for dijkstra; they predate the latest hoists
  and do not establish their current overhead.
  On the full `aoc2024` console workload with always-active result checks,
  `release-safe` took 2585 ms median versus 545 ms with only `.ValueBorrow`
  disabled (twelve alternating samples each). Disabling `.BoundCheck` or `.Overflow`
  individually yielded a smaller reduction.
  CPU backdrop convolution also exposes process-wide registration-lock contention: a native
  DevMode Gaussian pass exceeded 300 seconds with the default worker pool, while a single
  worker completed the scene. Small `Vector4` arithmetic repeatedly enters and leaves the
  same registry. Packed SIMD channel arithmetic removes that pressure from this renderer,
  and address-based registry shards reduce contention for ordinary parallel value calls.
  On the Vault form-fit case with the original presentation path, the sharded registry
  reduced the DevMode case from 90.2 s to 4.1 s with the host worker budget. The one-worker
  sample moved from 3.0 s to 8.0 s. The conservative extent stays widened after the last
  borrow closes, so the generated guards may call the runtime even while the registry is empty.
- Next: repeat the paired fixture on a quiet machine with an unchanged A/A control.
  Attribute the application's loop checks, argument copies,
  cold failure-call layout and per-value-parameter borrow registration before choosing another
  change. Isolate the one-worker cost of retaining the conservative extent, compare it with
  shard bookkeeping, and measure writes after the last borrow closes. Include parallel
  small-value arithmetic and shard collisions. Retain cross-thread conflicts and panic
  checkpoints. Checking a writing
  function's own ranges inline still needs a runtime entry that
  reports a conflict. Tiny-call ratios must not stand in for application overhead.
- Done when: reproducible measurements state the workload, compiler and program configurations,
  guard settings and variability, and give a bounded assessment of the runtime overhead.
- Related: compiler.safety.033, compiler.safety.020,
  language.parallelism.015.

### compiler.safety.019 — Bound current sanity cost and attribute retained-state storage

- Evidence: a prior profile puts sanity at 5.5% of compiler CPU cycles on core devmode
  and 2.8% on full-std
  release, with no iteration-cap hits. Propagation and checking perform most transfer
  work. Logical retained register/stack payload peaks at 1.26/1.86 MiB per invocation;
  spare capacity, hash storage, transient copies and allocator overhead remain unattributed.
  Unchanged timing controls varied by over 10x, preventing a tight wall/CPU-time bound.
- Next: measure actual retained capacity and heap overhead, then repeat quiet A/A controls
  before accepting an elapsed-time bound. Use the phase and visit counts to isolate
  transfer/state work without weakening proofs or changing analysis limits.
- Done when: current CPU and state-heap costs are attributed and accepted or reduced with
  a repeatable comparison and the safety/sanity behavior preserved.
- Related: compiler.build.005.

### compiler.safety.008 — Runtime bound guards still impose measurable hot-loop cost

- Evidence: `release` builds without runtime guards; `devmode`, and any build enabling
  `.BoundCheck`, pays them. Range and repeated-guard proofs plus cold-block layout already
  remove settled checks and move failure paths off the common path. Remaining costs include
  loop-bounded indices, repeatedly loaded counts and loop-invariant `late` checks.
- A full `aoc2024` comparison found that removing `.BoundCheck` alone did not
  reduce the measured wall time. Its large whole-preset gap is mainly
  `.ValueBorrow` (compiler.safety.030).
- A first guarded `late` read inside a loop still leaves the check at the body read site on
  every trip: `SemaInitFlow::walkLoopBody` analyzes the body once and does not carry that
  fact across a loop that may execute zero times. A safe hoist must run only after the first
  iteration is known to enter, then let the back-edge skip the check. Cover initialized and
  unset values with nonzero counts, plus an unset value with a zero count that must not panic.
- Next: implement that entry check for a narrow unconditional read with no writes, calls, or
  escaping aliases that could change it, then measure the affected loops with guards enabled
  and disabled.
- Done when: loop-bounded indices and invariant `late` values need no repeated guard, and
  the residual cost of runtime guards is measured on the affected loops with behavior
  preserved.

### compiler.safety.020 — A release through storage a callee could re-establish is not judged

- Evidence: caller-side use after a call can escape detection for receiver fields and globals.
  The body-local release/use check is already covered; this entry is only about what the caller can
  prove after a callee returns. A focused `use_after_free.swg` probe with a global pointer and two
  known helpers (one frees it; one frees and replaces it) confirms that caller aliases used after
  either call currently receive no use-after-free diagnostic. Because a missing diagnostic lets
  the test execute the invalid access, its regression must use a retaining allocator, as the
  double-free corpus does, rather than freeing the block physically.
- A release summary alone cannot prove the storage remains empty on return. An earlier prototype
  omitted that post-call write proof and failed the reset-safe sanity case. Establishing the proof
  requires excluding writes through aliases, so a release-only summary is insufficient.
- Release-safe probes confirm the boundary: a helper freeing `n.data` or a global pointer is not
  reported by the caller; counterparts that free and replace the field or global remain silent.
  At a call, the sanitizer drops facts about heap locations when their owner is passed, because the
  callee may change them. `freesParamsMask` summarizes a pointer parameter, and its indirect form
  summarizes a pointer held in a pointer parameter; neither carries struct-field offsets or global
  effects. A sound field summary has to mark aliases of the old pointer as released while leaving a
  field that the callee reset usable. A global needs the same before/after distinction. The summary
  also has to survive module API publication and unknown call targets.
- Prototype: `BorrowSummary` now has `freesFields` and `resetsFields` entries for first-level
  pointer fields, and caller-side sanitizer transfer distinguishes a released field from a reset
  field. Same-module positive and reset-safe probes pass in Release-safe with summaries supplied.
  Consumer probes with explicit summaries confirm that the generated API imports the field effect,
  diagnoses a reload and a copy of the old pointer, keeps a replacement field usable, and leaves a
  sibling field alone. An imported `freesIndirect` summary also catches a copy of the old pointer
  held in the passed box; the box itself stays unclassified because the callee may reassign it.
  Inferred summaries now retain a first-level field identity through `AllocatorRequest.address`:
  the static-provider API emits `freesFields` for a release-only method, and the consumer diagnoses
  its field reload. If the method writes that field or passes its carrier to another call, inference
  suppresses the field release because no must-reset proof exists. The field remains usable after
  an unannotated release-and-replace method, but aliases copied before that call are not yet
  diagnosed. Known direct wrappers now forward explicit and inferred field effects after module
  analysis; release-and-replace wrappers preserve both the old-alias diagnostic and safe field
  reload. A pointer value projected from a field also carries a callee's direct `frees` effect back
  to that field through wrappers. For body-visible carrier calls, possible field writes now
  propagate separately from releases: a known read-only call no longer suppresses a later
  field-release summary. Generated APIs publish possible writes in `writesFields`; the
  `writesFieldsComplete` marker lets the backend preserve alias provenance through bodyless calls
  for fields outside that complete list. An incomplete or unavailable summary remains
  conservative. Consumer regressions verify a no-write API preserves release diagnostics and a
  writer of `data` does not suppress a release through `other`; a wrapper API exports both effects
  together and the consumer keeps `data` usable while diagnosing the released `other`. Replacement
  and refill-before-release cases keep aliases to the old allocation valid. Globals and automatic
  reset inference remain unsolved. Aggregate `into` effects deliberately omit the complete-write marker
  when their field set cannot be proven. Linux `release-safe` validation passes the complete
  `workspace` suite (56/56 stages), the complete `sanity` suite, the focused `use_after_free.swg`
  corpus from the preceding validation pass, and 1,699 C++ unit tests.
- One `api_static_provider` Release-safe compile sample measured 1.42 s before and 1.52 s after
  projected-field forwarding, with peak compiler-session RSS of 261244 and 230592 KiB. This is a
  single run; repeat it before treating the small timing difference as a regression.
- Next: add an exact global-storage identity to release/write summaries and the caller's alias
  state, then consume it at known calls with the same before/after distinction used for fields.
  Start with same-module functions and a retained-allocation regression proving a free marks old aliases released;
  then add a free-and-replace case proving the new global pointee remains usable. Only after that
  works, publish/import the effect through module APIs and infer guaranteed resets where every
  return proves valid storage. Keep unknown targets and incomplete write summaries conservative.
- Done when: caller-side releases through receiver fields and globals are diagnosed without
  rejecting a reset that restores valid storage, with both cases covered in
  `bin/unittests/sanity/use_after_free.swg`.
- Related: compiler.safety.017.

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

### compiler.safety.010 — An integer becomes an enum value that no member names

- Rule: casts to ordinary enums require a compile-time value matching a declared member. Runtime
  values cannot be converted, even with `try cast`; use `#[Swag.EnumFlags]` for bit sets.
  `#[Swag.Incomplete]` enums intentionally accept values outside their declared members. This
  avoids invalid values for closed enums regardless of runtime safety settings while a checked
  conversion API is unspecified.
- Evidence: semantic checks reject runtime ordinary-enum casts and preserve flags-enum casts.
- Binary and TagBin deserialization now reject undeclared members of closed enums; numeric flags
  and `#[Swag.Incomplete]` enum payloads retain their declared semantics. TagBin validates enums in
  raw arrays, including enums nested in raw structs and fixed arrays. JSON string-backed enums map
  only to declared constants so decoded values do not borrow a temporary parser buffer. Custom
  `ISerialize.read` and `readElement` hooks are checked recursively after they fill a value.
- Audit: generic `cast` calls use the same specialized sema rules; reflection assignment copies
  values of one runtime type; text parsing accepts declared enum names; command-line parsing uses
  that parser. `assume cast` remains the explicit unchecked escape hatch.
- Next: run the application tests in a GUI-capable environment, including the migrated Swag Capture
  enum storage and user-data paths.
- Done when: JIT/native and semantic suites pass, including constant member values, rejected runtime
  values, a runtime flags combination, an open enum, and the migrated shipped call sites; the cast
  reference documents the rule.

### compiler.safety.007 — A foreign function is opaque to every safety analysis

- Evidence: `#[Swag.BorrowSummary]` can be written by hand on a `#[Foreign]` declaration, and the
  reference says so — but nothing requires it, nothing checks it against the callee, and a foreign
  function with no summary is treated as borrowing, storing and freeing nothing. A C function that
  keeps the pointer it was handed is indistinguishable from one that does not.
- Consequence: every `win32` and system binding is a hole in the borrow rules that no diagnostic
  marks. This is inherent — the compiler cannot see the callee — which is exactly why it belongs on
  the unsafe surface rather than inside the analysis.
- Next: decide the default. Either a foreign call is one of the operations that requires the marker
  from compiler.safety.033, or a foreign declaration without a written summary is assumed to store
  everything it receives and the bindings are annotated. Measure the second option against
  `bin/std/modules/win32` before choosing.
- Done when: the foreign boundary has one documented default, and the reference says what
  crossing it suspends.
- Related: compiler.safety.033.

### compiler.safety.033 — Raw memory operations have no common unsafe opt-in

- Evidence: Swag has no common opt-in or compiler mode for operations that can violate memory
  safety: integer-to-pointer casts, unchecked raw-memory construction and access, pointer
  arithmetic, union reinterpretation, byte-copy intrinsics, lifecycle bypasses, and foreign calls.
  Pointer casts between unrelated structs are already rejected. Checked dynamic casts have explicit
  `try`, `expect`, and `assume` forms and must be distinguished from unchecked assumptions.
- Next: require a visible lexical boundary around unchecked assumptions and raw operations.
  Inventory the remaining operation families across shipped `bin/` sources and tagged native
  integration tests. Use that inventory to choose expression-level and file-level opt-ins, then
  define and enforce which faults the safe subset excludes.
- Done when: the unsafe operation list is fixed and documented, safe code cannot reach any of
  them without a visible marker, `bin/` compiles with the boundary enforced, and the reference
  states which faults the safe subset excludes.
- Related: language.design.055, compiler.safety.007, compiler.safety.034.

### compiler.safety.034 — Nothing states what the safe subset guarantees

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
- Next: inventory each fault class, what excludes it today and in which configuration.
  Publish the resulting guarantee once compiler.safety.033 settles the unchecked boundary.
- Done when: the reference carries one page stating, per fault class, whether the safe subset
  excludes it, in which build configurations, and by which mechanism — and every claim on it is
  backed by a test in `bin/unittests`.
- Related: compiler.safety.033, compiler.safety.008.
