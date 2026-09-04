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

Measured against that line, the frame is in good shape and the heap is not. Escapes, view
invalidation, iterator invalidation, definite initialization, non-null types and mandatory error
handling are all enforced without a single annotation. Ownership of heap memory is not modelled at
all: a value that owns a resource is copied like an integer, the use-after-free proof rarely
survives contact with real code, and the operations that forge a pointer out of nothing are spelled
like ordinary code. The entries below are ordered by how much of that gap each one closes.

Every entry below is backed by a compilable case in
[bin/unittests/safety/corpus](../bin/unittests/safety/corpus): one file per CWE, a fault half
that names the diagnostic it expects and a sound half that must stay silent, with each gap
commented out and tagged with the entry that owns it. `grep -rn "GAP " bin/unittests/safety/corpus`
is the current scorecard.

[README.md](README.md) defines the shared backlog conventions.

## Ownership of the heap

### compiler.safety.002 — A value that owns a resource is copied implicitly, and both copies release it

- Area: compiler/sema, lifecycle
- Evidence: a struct with an `opDrop` that releases what it points at is bitwise-copyable with no
  diagnostic. `var o2 = o1` then drops the same allocation twice at scope exit; run against the
  compile-time JIT it corrupts the compiler's own heap, which is how it was found. The same shape
  without `opDrop` — a plain struct holding a pointer, released through a helper — double-frees the
  same way. Neither is reported in any configuration.
- Consequence: `opDrop` is currently a destructor without the rule that makes a destructor safe.
  Every owning type in `bin/` relies on nobody writing the copy, and the analysis that would catch
  the use-after-free proof cannot see a second owner: it tracks one pointer, and here there are
  two, each released once.
- Elsewhere: this is the one rule every ownership language shares, whatever else it disagrees on.
  Rust makes `Drop` imply `!Copy` and requires `Clone` to be written; C++ turns it into the rule of
  three and a linter; Swift reference-counts instead; Zig has no destructor at all, so the question
  does not arise. Nobody allows a silent bitwise copy of a type that owns a release.
- The machinery already exists and needs no new syntax. `#[Swag.NoCopy]` already rejects the copy
  with the right message ("cannot copy a value of non-copyable type 'Owner'; [help] transfer
  ownership with '#move'"), `#move` already transfers, `#fwd` already gives one function both call
  styles, and `opPostCopy` already declares what a duplicate means. What is missing is the
  inference: a type that declares or contains `opDrop` and does not declare `opPostCopy` is not
  copyable. That is zero annotation at the use site, zero runtime cost, and it closes the whole
  double-free class rather than one shape of it.
- Next: mark every `opDrop`-without-`opPostCopy` type `#[Swag.NoCopy]` in a throwaway branch and
  count the copies `bin/` then rejects — that count, and how many of them are real bugs, is what
  decides whether the rule ships as an inference or as a diagnostic first. 75 files under
  `bin/std/modules` and `bin/apps` declare `opDrop` without `opPostCopy`, but a type that is never
  copied costs nothing to migrate.
- Complete when: copying a value that owns a release is rejected without the type having to say so,
  the reference states the rule next to `opDrop`, and `bin/unittests` covers the inferred case, the
  `opPostCopy` opt-in, the `#move` transfer, and a type that owns through a member.
- Related: compiler.safety.004 is the same fault caught later and less
  reliably; this entry is the one that removes the fault instead. language.design.002 depends on it:
  a tagged union with an owning payload is exactly this shape, and the compiler would be the one
  generating its drop, so shipping one before this rule turns an author's double-free into the
  compiler's.

### compiler.safety.016 — Compile-time execution is judged against summaries that are still growing

- Area: compiler/sema, `SemaEscape`
- Found while: building the CWE corpus, whose first wrapper cases would not fire.
- Evidence: a release reached through one wrapper is reported when the body is code generated
  the ordinary way, and silent when the same body is forced through `#run`. The difference is
  timing, not analysis: the per-function summaries are chained by a mask fixpoint at the end of
  `Sema::waitDone`, and a `#run` compiles its callee DURING sema, before the wrapper has been
  given the transitive FREES bit its callee seeds. The base bit is set when the summary is
  first recorded, which is why a direct call to the freeing function is judged either way.
- Consequence: narrower than it first looked - ordinary programs get the check - but
  compile-time execution is exactly where a missed use-after-free hurts most, because the fault
  lands in the compiler's own heap and surfaces later inside an unrelated allocation.
- Next: decide what a `#run` is entitled to. Either accept the weaker judgement and say so in
  the reference next to `#run`, or make the JIT path run the fixpoint over the edges recorded so
  far before compiling a body - the masks only grow, so an early pass is sound and merely
  incomplete.
- Complete when: the two wrapper cases in the corpus are reported through `#run` as well as
  through ordinary code generation, or the reference states which checks a `#run` body does not
  get and the corpus notes say so.
- Related: compiler.safety.004 is what covers the shapes no must-analysis can prove.

### compiler.safety.017 — Memory leaks are not modelled at all

- Area: compiler/sema, language
- Evidence: nothing in the language or the tooling tracks whether an allocation is released.
  Not the borrow rules, not the lifetime proofs, not a runtime guard. Four shapes were written
  in `cwe401_memory_leak.swg` and all four are silent in every configuration: an allocation
  never released; one released on a single path; a pointer overwritten before its block is
  released; and a type that owns an allocation without an `opDrop` to release it.
- Consequence: this is the third of SV-COMP's memory-safety sub-properties (`valid-memtrack`,
  next to `valid-deref` and `valid-free`), and the only one Swag does not attempt. A leak is
  not a memory-safety fault in the exploitable sense, which is why it sits below the other
  entries, but a systems language that says nothing about it cannot claim the property.
- Elsewhere: Rust ties release to ownership, so the default is no leak and `mem::forget` is
  the deliberate exception; C++ has the same through RAII plus a linter for the rest; Go and
  Java collect instead. Zig makes the allocator explicit and ships a debug allocator that
  reports leaks at shutdown — which is the cheapest useful answer and the one that fits Swag's
  own `IAllocator`.
- Next: the runtime answer before the static one. A `devmode` allocator that counts live
  blocks and reports what is still held at shutdown costs nothing in `release`, needs no
  analysis, and finds real leaks the day it lands. Whether a static rule follows — a type that
  allocates and has no `opDrop` — is a separate decision, and depends on how much
  compiler.safety.002 changes about ownership first.
- Complete when: a `devmode` run reports the blocks an application leaked, and the four cases
  in `cwe401_memory_leak.swg` are either reported or documented as out of scope with a reason.
- Related: compiler.safety.002 and compiler.safety.004.

### compiler.safety.004 — Nothing makes a missed use-after-free fail deterministically

- Area: runtime/allocator, `bin/runtime`
- Evidence: `.Lifecycle` poisons storage abandoned by a move or a drop with `0xDD` so hidden
  violations fail loudly, and that half is deliberate and documented. The heap has no equivalent: a
  freed block goes straight back to the allocator's free list, so a read after free returns whatever
  the next allocation put there. The aliasing probes in `cwe416_use_after_free.swg` read garbage and kept
  running; the double-free probe corrupted mimalloc's free list and killed the process inside an
  unrelated allocation, far from the fault.
- Consequence: aliases and conditional frees are documented misses of the static proof "by design",
  which is the right call — the proof now reaches fields, elements, casts and the generic release,
  so what is left for it to miss is exactly what a must-analysis cannot decide. That is the half a
  runtime net is for, and there is none on the heap side.
- Next: measure what a devmode-only quarantine costs. mimalloc already ships the pieces
  (`MI_SECURE`, `mi_option_guarded_*`); the question is whether poisoning freed blocks and delaying
  their reuse is affordable in `devmode` on the heaviest consumer in `bin/`, not whether it is
  desirable.
- Complete when: a freed block read in `devmode` faults or reports at the read, the cost is measured
  on an application workload, and `release` is unaffected.
- Related: compiler.safety.002.

### compiler.safety.005 — A pointer into a value survives the move of that value

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

## The unsafe surface

### compiler.safety.006 — The operations that forge memory are spelled like ordinary code

- Area: language
- Evidence: a short list of operations can produce a pointer to anything, and none of them is
  distinguishable from safe code by reading it, by grepping for it, or by any compiler flag:
  - `cast(*T) someInteger` — an arbitrary integer becomes a pointer;
  - `cast(*Big) &small` — a reinterpreting cast between unrelated pointee types, reading past the
    object;
  - `Swag.makeSlice(ptr, count)` / `makeString` / `makeAny` / `makeInterface` — a length paired with
    storage that need not have it, after which every bounds check faithfully checks the lie;
  - pointer arithmetic on `[*] T`, which has neither provenance nor extent;
  - reading a `union` member that was not the one written, which turns an integer into a pointer
    with no cast at all;
  - `Swag.memcpy` / `memset` / `memmove`, whose byte count is unrelated to either operand;
  - `#relocate` and `#nodrop`, which suspend the lifecycle;
  - any call to a `#[Swag.Foreign]` function (compiler.safety.007).
  Each was verified to compile and to read out of bounds with no diagnostic.
- Consequence: Swag cannot state what its safe subset guarantees, because it has no safe subset —
  only a set of checks with no boundary. That is the difference between "the compiler catches a lot"
  and "this class of fault cannot occur here", and it is the difference a reader arriving from Rust
  is actually asking about.
- Elsewhere: `unsafe` is not a safety mechanism in Rust and never was — it is an *audit* mechanism,
  and it is most of why the guarantee is believed. Zig marks the same boundary by making
  `@ptrCast`/`@intFromPtr` visibly intrinsic and its undefined behavior builtin-checked; C# has
  `unsafe` blocks and a compiler switch; Swift puts `Unsafe` in the name of every type that can do
  it. There is no safe-by-default systems language whose unsafe operations are invisible.
- The shape must be Swag's, not Rust's. A block that swallows a page of code is the wrong unit here:
  the operations above are single expressions, and Swag already spells a compiler instruction on an
  expression with `#`. A modifier on the operation (`#unsafe cast(*T) addr`) plus one file-level
  opt-in (`#global #[Swag.Unsafe]`) for a binding or codec layer costs application code nothing,
  marks `bin/std`'s low-level modules once, and makes `grep` the audit tool.
- Next: fix the list before designing the spelling. Enumerate every operation that can produce an
  invalid pointer or an out-of-extent view, then count how many sites in `bin/` use each — that
  count decides whether the boundary is affordable and where the file-level opt-in has to sit.
- Complete when: the unsafe operation list is fixed and documented, safe code cannot reach any of
  them without a visible marker, `bin/` compiles with the boundary enforced, and the reference
  states which faults the safe subset excludes.
- Related: language.design.002 narrows the union bullet rather than removing it. The census in that
  entry found eight anonymous unions in `bin/`: two sum types that a tag would check, five C-ABI
  bindings that must stay byte-compatible, and one deliberate bit view. The untagged form therefore
  survives at the interop and bit-punning boundary, which is where the marker belongs and where it
  joins compiler.safety.007. Also compiler.safety.014.

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
- Complete when: the foreign boundary has one documented default, and the reference says what
  crossing it suspends.
- Related: compiler.safety.006.

## What `release` stops checking

### compiler.safety.008 — Dynamic bounds checking is switched off in release instead of being made cheap

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
  entirely rather than hoisting them. What would remain is the set of checks that genuinely cannot
  be proven, which is precisely the set worth paying for.
- Elsewhere: Rust keeps bounds checks in release and pays 1-5% for them, and that single fact is the
  one most often cited both for and against it. Go keeps them and has a documented elimination pass
  for exactly the loop shapes above. Zig keeps them in `ReleaseSafe` and drops them in
  `ReleaseFast`, making it the user's build-time choice — which is what Swag has today, minus the
  elimination that makes the safe choice affordable.
- Next: implement bound-check elimination as a backend pass (induction-variable range against the
  container's `.count`, dominating comparisons, constant indices), then re-measure the two loops
  above with guards on. The deliverable is the pass, not a change of default: `release` stays
  guard-free, `devmode` pays this cost on every index today, and a build that turns the guards on
  deliberately is exactly the build the pass is for.
- Complete when: a bound-check-elimination pass exists, `devmode` compile time and generated code
  are measured before and after, and the residual cost of `.BoundCheck` on the two loops above is
  recorded next to the 2026-07-08 numbers.
- Related: compiler.optimization.md owns the pass once it is scoped.

### compiler.safety.009 — An enum value outside its members walks past a `switch #complete`

- Area: language, compiler/codegen
- Evidence: `switch #complete c` over a three-member enum, reached with `cast(Color) 99`, panics in
  `devmode` under the `.Switch` guard; with the guard off the value matches no case and continues
  after the switch. That is the same behavior as a plain `switch`, and it is the right one: the
  point of `#complete` is that the dispatch carries no range test at all, so the "outside the set"
  case costs zero branches and is faster, and a caller who wants the check builds a target that
  keeps `.Switch` on.
- What is left is what the value does after walking past. The missing-return rule now rejects a
  function that relied on the switch to produce its result, so the fall-off-the-epilogue case is
  closed; a `switch` that assigns rather than returns simply leaves the previous value in place.
- Next: nothing here on its own. The remaining exposure is that the out-of-range value existed at
  all, which is compiler.safety.010, and that a `release` build does not have to keep the guard,
  which is the deliberate design compiler.safety.008 records. Delete this entry once
  compiler.safety.010 is decided.
- Complete when: converting an integer to an enum has a rule (compiler.safety.010), or a measured
  reason to reopen the guard default appears.
- Related: compiler.safety.010 is where the out-of-range value comes from; language.design.001 is
  the separate question of whether exhaustiveness should be the default.

### compiler.safety.010 — An integer becomes an enum value that no member names

- Area: language
- Evidence: `cast(Color) 99` is accepted with no check in any configuration, and the result is used
  as an ordinary `Color` — compared, switched on, indexed with. Nothing distinguishes it from a
  declared member. It is a value that fails every invariant the enum was declared to express, and
  it is what walks past a `switch #complete` (compiler.safety.009).
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
- Related: compiler.safety.009.

### compiler.safety.011 — `!` and `Swag.Late` stop asserting in release

- Area: language, runtime guards
- Evidence: `p!` is guarded by `.Expect` and an unset `late` read by `.Null` — two different
  assertions under two different flags, both off in `release` by default. Each panics with a
  located message in `devmode` and, in `release`, dereferences null: a hardware fault at a low
  address for a small offset, and an unmapped-in-practice-but-not-guaranteed address for a large
  one. Naming either flag in `#[Swag.Safety]` restores its guard in `release`, so the gap is the
  default rather than the mechanism.
- Consequence: the fault is not silent, which is what matters, but the diagnostic disappears exactly
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

### compiler.safety.012 — Stack exhaustion has no defined behavior and no diagnostic

- Area: runtime, compiler/backend
- Evidence: a recursion deep enough to exhaust the stack ends the process with no message and exit
  code 0. Run through the compile-time JIT it takes the compiler down with it, so a `#run` or a
  `#test` that recurses too far reports nothing at all — the build simply stops after "tuned". Large
  frames are handled correctly: `expandLargePrologueStackAdjustments` already emits the Windows
  guard-page probes, so this is the depth case, not a stack clash.
- Consequence: the one fault class where the language produces neither a value, nor a panic, nor a
  message. Every other unchecked operation at least leaves evidence.
- Next: catch the guard-page fault and report it. The host already installs a hardware-exception
  handler (`Support/Report/HardwareException`); a stack-overflow exception needs the same treatment
  as an access violation, plus a reserved guard region so the handler itself has stack to run on.
- Complete when: exhausting the stack reports a located diagnostic under the JIT without ending the
  compiler, and a native binary exits with a stack-overflow message rather than silently.

## Borrow invalidation

### compiler.safety.001 — A pointer read out of a container is judged to view the container

- Area: compiler/sema, `SemaEscape`
- Found while: making a written `#[Inline]` honored across files (2026-08-28), which lets the
  analysis see into `Core.Array.opIndexPtr` for the first time.
- Evidence: `pixel/src/poly/clipper.swg` stops compiling. `getLastOutPt` and `addOutPt` read
  `.polyOuts[i]` out of an `Array' *OutRec?`, dereference the pointer they find there, and
  return an `OutPt` node that `Memory.new` allocated. The analysis records that return as a view
  of `me.polyOuts`, so a later `.addOutPt` or `.intersectEdges` that grows the array reports
  eleven `sanity_err_borrow_invalidated`. Growing an array of pointers moves the pointers, never
  the nodes they address, so none of the eleven is real.
- Already ruled out: the `IndexExpr` route is NOT the lever. Forcing `indexReadsElementByValue`
  to answer true - on the resolved node and on the written one - leaves all eleven in place, so
  the borrow reaches the return without passing the index at all. The summary trace says
  `addReturnBorrowOrigins` receives `viaOwnedPayload=1 payloadField=polyOuts` with the source node
  being the MEMBER ACCESS `.polyOuts`, which is where `ownedPayloadStorageRootAt` sets the flag.
  What is missing is the step that clears it when a pointer VALUE is loaded through that view.
- Next: trace `expressionEscapeInfoAt` over `let outRec = nnOutRec(.polyOuts[i])` and find which
  node carries `viaOwnedPayload` past the load - the argument path of the call is the first
  suspect, since the index rule provably never runs.
- Complete when: `pixel` builds with a written `#[Inline]` honored across files, `bin/unittests/
  sanity` still rejects everything it rejects today, and `borrow_invalidation.swg` keeps both
  directions green.
- Related: the guard on a written `#[Inline]` is restored until this is settled - see
  `simd/backlog-sweep`, "Restore the cross-file inline guard until the borrow analysis is right".

### compiler.safety.013 — A container reached through a pointer parameter is not judged

- Area: compiler/sema, `SemaEscape`
- Evidence: the invalidation check judges a view of a local owner and a view of a method receiver,
  and misses the same body when the container arrives as an ordinary pointer parameter. All three
  were probed with the identical shape:
  - `var a: Array's32` in the caller, view taken, `a.add(...)` — reported;
  - `mtd bad()` reading `.items.toSlice()` then `.items.add(...)` — reported, naming `me`;
  - `func f(a: *Array's32)` reading `a.toSlice()` then `a.add(...)` — silent, and the read returns
    garbage.
  The same asymmetry applies to a view into what a `*String` parameter owns.
- Consequence: the shape that is missed is the one a library writes. A method on the owner is covered
  because the receiver roots at `me`; the moment the same code becomes a free function taking the
  container, the rule stops applying.
- Next: root a parameter-carried owner the way `signatureParameterFor` already roots a body `me`, and
  judge the mutation against the parameter rather than dropping it. The false-positive risk is the
  one already recorded for parameter-rooted containers under the pair check — an object caching a
  pointer to a caller buffer for the duration of one call is idiomatic — so this must be swept over
  all of `bin/` before it lands, and reduced rather than annotated if it fires.
- Complete when: the third probe above reports, the `bin/` sweep is clean, and
  `borrow_invalidation.swg` covers a container reached through a pointer parameter alongside the
  receiver case.
- Related: compiler.safety.001.

## The statement

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
  compiler.safety.002, 006 and 008 are decided, because each one changes what belongs in it. What can
  be done now is the inventory: one page listing every fault class, what excludes it today, and in
  which configuration.
- Complete when: the reference carries one page stating, per fault class, whether the safe subset
  excludes it, in which build configurations, and by which mechanism — and every claim on it is
  backed by a test in `bin/unittests`.
- Related: compiler.safety.002, compiler.safety.006, compiler.safety.008.
