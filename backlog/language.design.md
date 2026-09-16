# Language Backlog

This backlog covers deliberate changes to Swag language semantics and syntax. Comparative
examples describe specific documented alternatives, not an exhaustive ranking of languages.
The compiler that implements it is [compiler.core.md](compiler.core.md).

Compiler defects stay in [compiler.core.md](compiler.core.md). This file keeps deliberate language design,
surprising but specified rules, their comparative evidence, and their next decisions together.

Entries are ordered from the most recently updated down. An entry disappears when it
ships; history lives in git, not here.

The design pass distinguishes missing capabilities from changes to an existing policy.
The following are already available and are not new feature requests:

- Non-null required fields and definite initialization, including rejection of incomplete
  aggregates: [the initialization fixture](../bin/unittests/errors/sema/sema_err_type_requires_init.swg).
  The remaining construction obstacles are error fallback (language.design.031) and moved-source
  reset (language.design.035), not the absence of constructors or safe initialization.
- Aggregate literals construct directly in the return slot, retval supports incremental filling,
  and eligible named-local returns transfer ownership. See
  [return storage](../bin/reference/modules/language/src/007_008_retval.swg) and
  [copy/move](../bin/reference/modules/language/src/006_009_custom_copy_and_move.swg).
- Swag.Strict already supplies distinct aliases. No new nominal-type feature is requested merely
  to replace an attribute by a keyword; see the
  [strict-alias reference](../bin/reference/modules/language/src/003_008_alias.swg). Require a
  concrete usability gain before adding syntax.
- Optional chaining, orelse, dynamic is/as patterns, declaration-bound with, expression bodies,
  filtered/indexed loops, and zero-allocation reversed views already exist. The entries below
  target their remaining composition or policy gaps, not their reintroduction.

Related work has one owner: the unsafe boundary remains compiler.safety.006 and the safe-subset
contract compiler.safety.014 in [compiler.safety.md](compiler.safety.md). Semantic cleanup edits
belong to compiler.core.048 in [compiler.core.md](compiler.core.md), rather than the formatter.
Public API consistency remains a module-by-module design requirement under
[design-swag-bin-modules](../.agents/skills/design-swag-bin-modules/SKILL.md): value returns,
options structs, slices and ownership contracts are available today. A concrete API defect belongs
in its module backlog; a general request for better names is not a missing language feature.

### language.design.032 — Produce values directly from a switch

- Recorded: 2026-09-16 16:06
- Evidence: the [switch reference](../bin/reference/modules/language/src/005_005_switch.swg)
  and [statement parser](../src/Compiler/Parser/Parser/Parser.Stmt.cpp) expose a statement;
  [expression parsing](../src/Compiler/Parser/Parser/Parser.Expression.cpp) does not introduce
  switch expressions. Ternaries and expression-bodied functions already produce values, so
  this request is specifically for multi-arm selection, not expression-oriented code in general.
- Proposed contract: evaluate the subject once, select one arm using the existing case/pattern
  rules, and use that arm's value as the result. Conceptually, `let label = switch kind { ... }`
  should replace an auxiliary mutable local assigned in every arm; this is illustrative proposed
  syntax, not accepted Swag. Every reachable path must yield a compatible value or exit.
  An unselected arm must not run effects, transfer ownership, allocate, or drop its payload.
- Decisions: choose how a multi-statement arm yields its value; keep return as a return from the
  enclosing function. Define contextual typing, non-returning arms, failure propagation and
  whether the result borrows or owns. Reject fallthrough in a value-producing switch unless a
  precise single-result rule is justified. Do not require tagged unions for the first version.
- Elsewhere: Rust [match expressions](https://doc.rust-lang.org/reference/expressions/match-expr.html)
  select an arm value and combine arm types. This is a comparison for value selection, not a
  requirement to import all Rust patterns or coercion rules.
- Next: prototype enum-to-string selection, an owning String factory and a borrowed pointer
  result using existing cases. Verify side-effect counters, a failing arm, a non-returning arm,
  and source lifetime before migrating real helpers. Coordinate exhaustiveness with
  language.design.001 and non-returning result typing with language.design.031.
- Complete when: a local initializer and a function return can use a total multi-arm expression
  without a mutable relay; JIT/native tests cover type inference, evaluation order, cleanup and
  borrowed-result escapes, and the formatter/reference/editor agree on the chosen syntax.
- Related: language.design.001, language.design.002, language.design.006, language.design.031.

### language.design.033 — Choose one canonical instance-method declaration

- Recorded: 2026-09-16 16:06
- Evidence: the [impl reference](../bin/reference/modules/language/src/006_002_impl.swg)
  explicitly equates mtd f() with func f(me), and mtd const with an explicit const receiver.
  [FileStream](../bin/std/modules/core/src/filesystem/filestream.swg) uses func isOpen(const me)
  beside mtd declarations. Both forms already work; this is a syntax simplification proposal,
  not missing methods, named receivers or UFCS.
- Proposed contract: one canonical declaration should tell the reader whether there is an
  instance receiver and whether it is mutable. Keep associated functions without a receiver
  and ordinary [UFCS functions](../bin/reference/modules/language/src/007_006_ufcs.swg) distinct:
  a function taking an ordinary typed first argument does not become an instance declaration
  merely because it can be called with dot syntax.
- Decisions: compare a single func form with an explicit receiver against mtd as the sole
  instance shorthand. Preserve a way to name the receiver when that helps nested with blocks;
  compare total syntax and semantic cases, not keyword count alone. Include const receivers,
  generic methods, interface implementations, special operators and reflected method signatures.
- Elsewhere: Rust [associated functions and methods](https://doc.rust-lang.org/reference/items/associated-items.html#methods)
  use a receiver parameter to distinguish methods. That shows one possible distinction, not a
  reason to discard Swag's existing receiver semantics or UFCS.
- Next: inventory both spellings and translate representative FileStream, collection and GUI
  methods into each candidate. Choose one complete declaration grammar and a semantic migration
  which preserves overloads, visibility, receiver mutability and method reflection.
- Complete when: one receiver grammar is selected and applied across compiler/reference/editor
  and bin/ without a permanent synonym, or a measured comparison rejects the simplification and
  this entry is removed rather than left as an indefinite style preference.

### language.design.034 — Make custom iteration independent of manual control-flow injection

- Recorded: 2026-09-16 16:06
- Evidence: [Array.opVisit](../bin/std/modules/core/src/collections/array.swg) is a macro with
  #code bindings and pointer stepping specifically arranged to preserve continue. The
  [list visitor](../bin/std/modules/core/src/collections/list.swg) supplies #scope labels and
  explicit break/continue remapping. These are provider implementation costs, not missing
  consumer features: for value/index, for &value, where, reversed() and pairs() already exist.
- Proposed contract: define a checked iteration provider whose step/visit operation supplies
  elements while the compiler owns ordinary loop control flow. Compare a pull cursor with a
  compiler-recognized visitor; neither alternative should require a user-defined macro to
  reinterpret the loop body's keywords. Preserve borrowed struct elements and explicit mutable
  iteration rather than copying elements to make a protocol easier to implement.
- Decisions: distinguish a yielded borrow valid until the next step from one valid for the
  collection's lifetime; define exhaustion, early exit, failure, source mutation and invalidation.
  Prove composition on one reversed traversal and one lazy filter/map view, without adding new
  filtering syntax or claiming all collection adapters are missing. Allocation-free means the
  adapter adds no allocation; the callback may still allocate deliberately.
- Elsewhere: Rust's [Iterator](https://doc.rust-lang.org/std/iter/trait.Iterator.html) has a next
  operation and composes adapters around it. Its ordinary Item contract is not by itself a
  complete model for a value borrowing the cursor until its next mutation; settle that boundary
  explicitly for Swag instead of assuming a direct transcription is sufficient.
- Next: implement equivalent experimental providers for Array, List and a fallible decoder.
  Compare inlining, allocations and generated loops with opVisit. Test nested break/continue,
  enclosing-function return, defer, failure and source invalidation before choosing a replacement.
- Complete when: a custom collection needs no manual loop-keyword remapping, the existing
  consumer loop forms still behave correctly, and owning/borrowed/fallible providers have a
  tested lifetime and cost contract with a migration path for opVisit.
- Related: language.design.018; compiler.safety.014 in [compiler.safety.md](compiler.safety.md).

### language.design.035 — Move a non-defaultable owner without resetting its consumed source

- Recorded: 2026-09-16 16:06
- Evidence: safe definite initialization and non-defaultable fields already exist. The remaining
  obstacle is [sema_err_nonull_move_source_no_default.swg](../bin/unittests/errors/sema/sema_err_nonull_move_source_no_default.swg):
  an owner with opDrop and a required non-null field rejects assignment, initialization and call
  transfers with #move, plus #fwd, because the source cannot be reset. The
  [copy/move reference](../bin/reference/modules/language/src/006_009_custom_copy_and_move.swg)
  documents this contract. A dummy default weakens the type's invariant just to make it movable.
- Proposed contract: a consuming move transfers ownership and leaves the source uninitialized,
  unavailable to reads or drop until assigned a complete replacement. It does not construct a
  new empty owner behind the caller's back. Use the existing definite-initialization and borrow
  machinery to describe that state. Keep an explicit replace/take operation when a caller really
  needs the source immediately reset to a chosen valid value.
- Decisions: start with whole locals. Specify branch merges, deferred/captured observations,
  aliases, failure after a completed transfer, and exactly-once destruction. Moving a field or
  array element is a separate capability: either track partially consumed storage or reject it
  until whole-value restoration is proven. opPostMove invariant repair is distinct from source
  reinitialization and must not be lost by changing the latter.
- Elsewhere: Rust's [moved values](https://doc.rust-lang.org/reference/expressions.html#moved-and-copied-types)
  leave the source location logically uninitialized. The comparison concerns the consumed state;
  it does not prescribe changing Swag's borrowed by-value parameters into consuming ones.
- Next: use the existing rejection fixture as the design witness and define the exact new
  accepted/rejected cases before changing it. Prototype whole-local transfers with a required
  non-null field and a counted resource; cover reinitialization, a conditional move, deferred
  observations, a throwing later operand and outstanding borrows in JIT and native execution.
- Complete when: a valid non-defaultable owner can be transferred without a dummy default,
  consumed storage cannot be read/dropped twice, and failures/branch merges preserve ownership.
- Related: language.design.024 owns implicit copies at consuming boundaries;
  language.design.031 owns non-defaultable results at error-handling boundaries.

### language.design.006 — Positional destructuring binds by position even when every name matches a field

- Recorded: 2026-08-07 07:43
- Updated: 2026-09-16 16:04 — separated existing capabilities from the remaining design contract
- Area: language
- Found while: a reading pass over the whole language reference
- Observation: `let {a, b} = tuple` is positional, and the reference says so
  ([004_003_tuple.swg](../bin/reference/modules/language/src/004_003_tuple.swg)).
  The reference explicitly states that binding names do not select source fields and tests
  a reordered `{y, x}` pattern. The named form (`{y: vertical}`) selects by field name. The
  documentation gap is closed; the remaining design question is whether positional and named
  patterns should share a form that lets a reordered field-looking pattern mean something else.
- Evidence: with `let point = {x: 10, y: 20}`, `let {y, x} = point` gives `y == 10` and `x == 20`.
  Confirmed under both the JIT and the forged binary. The same indifference to names governs
  assignment: a `{width, height}` tuple takes a `{x, y}` tuple of the same field types, and
  [004_003_tuple.swg](../bin/reference/modules/language/src/004_003_tuple.swg)
  documents it — "tuples can be assigned to each other if their field types match, even if field
  names differ", with `#typeof(x) != #typeof(y)` asserted on the same page.
- Elsewhere: Rust distinguishes tuple patterns from named-field struct patterns, where a bare field name
  abbreviates a binding to that same field
  ([Rust patterns](https://doc.rust-lang.org/reference/patterns.html#destructuring)).
- Proposed contract: Named destructuring already exists as field: binding. The change is to make named
  shorthand actually select the named fields and give positional tuples/patterns a distinct form.
  On a record with x = 10 and y = 20, a named y, x pattern must produce 20, 10; positional extraction
  must visibly request positions. Specify record compatibility as well as pattern spelling so
  assignment does not discard field names while destructuring depends on them.
- Next: Compare positional parentheses and named braces against existing tuple literals, grouped
  expressions, one-element tuples, ignored fields, renaming and rest patterns. Inventory the
  migration of {a, b}, including inferred field names; settle equality, assignment and parameter
  compatibility before choosing syntax. Preserve evaluation and binding order.
- Complete when: named and positional construction, assignment and destructuring have separate predictable
  contracts, and reordered-name tests cannot silently select the wrong fields.
- Related: the same pattern syntax is what `let {r, g, b} = getWhite()` uses in
  [007_008_retval.swg](../bin/reference/modules/language/src/007_008_retval.swg), where the
  names read as field names and happen to be in order.

### language.design.001 — Enum switches are silently non-exhaustive

- Recorded: 2026-08-08 06:23
- Updated: 2026-09-16 16:04 — separated existing capabilities from the remaining design contract
- Evidence: a `switch` over a three-value enum that handles two of them compiles with no error, no warning,
  and no `default`; the third value simply falls through to nothing. Exhaustiveness exists but is
  opt-in through `switch #complete`
  ([005_005_switch.swg](../bin/reference/modules/language/src/005_005_switch.swg)).
- Elsewhere: Swift requires exhaustive switches, including a fallback when the cases do not cover the domain
  ([Swift control flow](https://raw.githubusercontent.com/swiftlang/swift-book/main/TSPL.docc/LanguageGuide/ControlFlow.md)).
- Proposed contract: Closed enum statements should be exhaustive without #complete. Existing type-pattern
  switches over any/interfaces remain open and need an explicit fallback when their result must
  be total. Guards do not cover a case unless coverage is proven; flags combinations are not a
  finite list of mutually exclusive cases. Do not add a second exhaustiveness mechanism.
- Next: Prototype the default on ordinary closed-enum switches, classify missing arms in bin/,
  and distinguish deliberate ignore arms from accidentally omitted cases. Reuse the current
  #complete diagnostics and coverage analysis; define the treatment of aliases and duplicate enum
  values. Value-producing switches are a separate outcome in language.design.032.
- Complete when: adding a closed enum member exposes incomplete consumers, deliberate partial handling
  remains explicit, and guarded, aliased, flags, and open-type switches have executable rules.
- Related: compiler.safety.010 owns forged enum values, including fall-through past `switch #complete`
  when the runtime Switch guard is disabled, independently of this default. language.design.002
  owns closed payload-carrying choices; decide their exhaustiveness policy alongside enum switches.

### language.design.002 — There is no tagged union

- Recorded: 2026-08-08 06:23
- Updated: 2026-09-16 16:04 — separated existing capabilities from the remaining design contract
- Evidence: `union` is C-style and untagged: all fields share offset 0 and reading a field that was not the
  one written has no active-member check
  ([004_006_union.swg](../bin/reference/modules/language/src/004_006_union.swg)). `any` covers the dynamic
  case, and an interface hierarchy covers the open one — `case CreateEvent as ptr` is idiomatic; the 2026-09-04 census counted
  135 sites, [wnd.swg](../bin/std/modules/gui/src/wnd/wnd.swg) among them. What is missing is only
  the **closed** choice: no discriminated union, no payload-carrying enum, no destructuring of a case.
- Census (2026-09-04, `bin/` excluding `.output` and `.dep`): the shape to support is not "a standalone sum
  type", it is "a closed choice next to shared fields". Eight anonymous unions exist. Two are sum types, and
  both already name their tag as an ordinary sibling field:
  [painter.swg](../bin/std/modules/pixel/src/painter/painter.swg) (`using params: union` selected by
  `id`, documented as "inactive members must not be read") and
  [editbox.swg](../bin/std/modules/gui/src/controls/widgets/editbox.swg) (numeric bounds selected by
  `inputMode`). Five are C-ABI bindings (`win32` x4, `xaudio2`) that must stay byte-compatible, and
  [guid128.swg](../bin/std/modules/core/src/system/guid128.swg) is a deliberate bit view of one
  storage, not a choice. Other inspected sum-like representations are **wide structs** — a `kind` field, mutually
  exclusive fields, and the invariant in a comment:
  [outline.swg](../bin/std/modules/truetype/src/outline.swg) ("the fields used by the command depend
  on `kind`; unused points remain zero"),
  [prefilter.swg](../bin/std/modules/core/src/text/regexp/prefilter.swg) (15 fields commented
  "Sequence form:" / "Literal form:"), [scc.swg](../bin/std/modules/core/src/filesystem/scc.swg)
  ("selects which value field is meaningful"),
  [item.swg](../bin/std/modules/gui/src/controls/pdf/item.swg),
  [program.swg](../bin/std/modules/core/src/text/regexp/program.swg),
  [ast.swg](../bin/std/modules/core/src/text/regexp/ast.swg), `HtmlLength`, `HtmlCalcNode`. 228
  switches run on such a discriminant, 182 of them `switch #complete`.
- Consequence: nothing checks any of those sentences, and the untagged form costs more than the missing
  check. Without a custom equality operation, a union compares as bytes: `structComparesAsBytes`
  has no active member to select. An enclosing struct may still generate member-wise equality
  for its other fields, but the union part retains that byte comparison
  ([SemaSpecOp.Generated.cpp](../src/Compiler/Sema/Helpers/SemaSpecOp.Generated.cpp)). Equal active
  payloads can therefore compare unequal when inactive bytes differ. A wide struct also keeps
  every payload's storage alive: `MetadataValue` holds a `String` and an `Array'u8` whatever its
  `kind` says. The missing contract is active-payload checking and lifecycle dispatch.
- Elsewhere: Rust enum variants may carry tuple or named-field payloads
  ([Rust enumerations](https://doc.rust-lang.org/reference/items/enumerations.html)). This is a concrete
  comparison for a closed choice; an ordinary C# record hierarchy is not an equivalent guarantee.
- Earlier compatibility-oriented analysis: a Swag enum is a table of typed constants (`enum V: string`, `const [..] s32`,
  `.count`, `#[Swag.EnumFlags]`, enum-indexed arrays), and the tag is almost always an existing **public**
  enum that other code stores, compares and serializes (`CommandId`, `OutlineCommandKind`, `MetadataKind`).
  Attaching a payload changes that model. The clean-slate comparison below deliberately reopens
  the earlier requirement to preserve the published tag API.
- Candidate shape, to confirm against the census rather than assume: the union names an existing sibling
  field as its tag — `using params: union(id) { Clear: struct{ color: Color } ... }`. It reuses
  existing tokens but adds declaration and construction grammar. No tag argument keeps today's
  C semantics so the
  six interop and bit-view sites are untouched, shared fields stay where they are, and the 228 discriminant
  switches keep their header — only the arms that read a payload gain `as p`. Open inside that shape: the
  atomic write that sets tag and payload together (`cmd.params = .Clear{color: .White}`, with a direct write
  to the tag rejected), and whether `.Clear{...}` in a typed position is the existing type plane of
  [011_005_leading_dot.swg](../bin/reference/modules/language/src/011_005_leading_dot.swg) or a fifth role
  that page says the leading dot no longer has room for.
- What the feature must carry, and what it therefore depends on:
  - Lifecycle dispatched on the tag: initialization, `opDrop`, `opPostCopy`, `#move` and assignment.
    Untagged unions can have methods but cannot select an active payload automatically. A tagged
    union with an owning payload is a type that owns a release, so the rule
    that takes the copy away from a type declaring `opDrop` has to reach its generated drop too; without
    that, the compiler would generate a drop for a type it also lets you copy bitwise.
  - Changing the case invalidates every borrow of the payload:
    `let p = &cmd.color; cmd.params = .Font{...}; p[]` reads the wrong case with no free involved. That is
    view invalidation, which `SemaEscape` already models for containers, and it has to be designed in rather
    than retrofitted.
  - Payload access rides the narrow facts already shipped for nullability
    ([SemaFrame.h](../src/Compiler/Sema/Core/SemaFrame.h)), which need a fact kind carrying a value
    ("this path has tag `.Clear`") next to `NonNull` and `NonZero`.
  - The earlier sibling-tag candidate used the zero tag as its default case. The new comparison
    must instead justify any default case explicitly; a type may require construction. Flags
    cannot be tags, since a combination is not one mutually exclusive case.
- Migration order once the shape is fixed, cheapest proof first: `editbox`'s bounds (3 POD cases, one file, a
  tag that already exists), then `painter`'s `Command` (the entry's own example, and it exercises `using`),
  then the POD wide structs (`OutlineCommand`, `Regex.Node`, `Regex.Inst`, `HtmlLength`), then the ones whose
  payloads own storage and therefore test the generated lifecycle (`Regex.Prefilter`, `Scc.MetadataValue`,
  `Pdf.Item`). `win32`, `xaudio2` and `Guid128` stay untagged, and the GUI event tree stays an interface
  hierarchy: it is the open choice, which the language already answers.
- Proposed contract: Provide a closed sum with atomic construction of tag and payload, checked payload
  access, and lifecycle dispatch on the active case. Dynamic type patterns already handle open
  hierarchies; do not replace those or call them missing. Compare a dedicated sum declaration
  with a checked union tied to an existing tag, without requiring preservation of current public
  enum names. Shared fields remain outside the choice. Default construction must select a valid
  explicit or defined default case; a zero tag alone is not a justification for inventing one.
- Next: Write both candidate shapes for editbox bounds, painter commands, and Scc.MetadataValue.
  Show construction, a shared-field update, an owning-payload transition, and borrowed matching.
  Decide whether matching consumes or borrows, when case changes invalidate views, and what a
  failed payload construction leaves behind. Prototype the smallest POD case before owning ones.
- Complete when: a closed choice has atomic construction, exhaustive matching and correct copy/move/drop
  behavior; tests reject inactive payload reads and stale payload borrows in JIT and native code.
  C ABI unions keep an explicitly separate unchecked representation.
- Related: language.design.001 — a tagged union is where exhaustive matching earns its keep, and the two
  defaults are better decided together, since the case for `#complete` is far stronger on a closed choice
  than on an open enum. compiler.safety.010 owns tag-domain validation: the existing Switch runtime guard already
  catches unmatched values in guarded `#complete` switches. A tagged-union contract must also
  define what can be constructed and what happens when that guard is disabled.
  The ownership rule that denies the copy of a type declaring `opDrop` has to cover the generated drop of
  an owning payload. compiler.safety.010 is where a forged tag
  comes from, with `Swag.memcpy`, `#relocate`, a binary read into the struct and a
  `#[Foreign]` call as the other routes. compiler.safety.011 applies to whatever spelling asserts a tag. It
  narrows, rather than removes, the union bullet of compiler.safety.006: the untagged form stays for C
  interop and bit views, which is where the marker belongs. The error-handling design already shipped
  (`fail`/`try`/`catch`) chose a different axis and is not re-litigated here.

### language.design.008 — Mixing a signed and an unsigned operand of the same width converts the signed one

- Recorded: 2026-08-07 07:43
- Updated: 2026-09-16 16:04 — separated existing capabilities from the remaining design contract
- Area: language
- Found while: the same pass
- Observation: when two integer operands have the same width and differ in signedness, "the
  unsigned type wins"
  ([003_006_operators.swg](../bin/reference/modules/language/src/003_006_operators.swg)).
  Because Swag deliberately does *not* promote 8- and 16-bit operands to 32 bits the way C does,
  that rule has no wider type to escape into: `s8 + u8` is computed in `u8`, so a negative
  signed operand first converts to an unsigned value before addition. The expression includes a guarded
  conversion, and the guard is a `release`-time no-op.
- Evidence: a constant `-1's8 + 1'u8` is rejected at compile time ("cannot cast '-1' to 'u8' …
  value is negative, but the target type is unsigned"). The same expression through runtime
  variables panics with "integer overflow" in the guarded configuration now named `devmode` — and in `release`, where the overflow
  guard is off, it wraps.
- Elsewhere: Go requires explicit conversions between distinct numeric types in expressions
  ([Go numeric types](https://go.dev/ref/spec#Numeric_types)). This is one alternative to Swag
  choosing a common integer type.
- Proposed contract: Choose a common numeric type only when it can represent both runtime operand domains.
  For example, s8/u8 could widen to s16; s64/u64 needs an explicit policy because no ordinary
  integer covers both. Comparison need not share arithmetic lowering, but must compare mathematical
  values rather than reinterpret a negative operand as unsigned. Constant adaptation is separate
  from runtime promotion. This is not a request to add existing explicit casts.
- Next: Compare lossless common-type promotion with rejection of all mixed signedness on actual
  bin/ callers. Cover arithmetic, ordering, bitwise operators and compound assignment separately;
  specify the destination check for compound assignment. Coordinate literal defaulting with
  language.design.021 and language.design.022 and conversion categories with language.design.023.
- Complete when: one promotion/comparison table is selected and tested at constant, JIT, guarded native
  and release boundaries, without configuration-dependent changes to signedness meaning.

### language.design.030 — Inside `#test`, `try` means `expect`

- Recorded: 2026-08-07 07:43
- Updated: 2026-09-16 16:04 — separated existing capabilities from the remaining design contract
- Evidence: the error-management reference explicitly defines `try` inside `#test` as `expect`.
  Success returns the same value; failure terminates the test instead of propagating to a caller.
  Moving the expression into a fallible helper therefore changes its failure path.
- Elsewhere: Swift distinguishes propagation (`try`) from asserting success (`try!`) in the
  spelling ([Swift error handling](https://raw.githubusercontent.com/swiftlang/swift-book/main/TSPL.docc/LanguageGuide/ErrorHandling.md)).
- Proposed contract: Try propagates in every context; the test runner owns a fallible test body and reports
  an unhandled error as a failed test. Expect remains an invariant assertion. Inline decisions
  must not change either contract, and fixtures still finish their deferred cleanup.
- Next: Prototype the fallible test boundary on direct, helper and inline-helper calls. Compare
  failure attribution and cleanup with the existing alias, including non-defaultable results
  that try already supports outside tests. Update the documented alias only with runner coverage.
- Complete when: try has the same propagation meaning inside and outside tests, the runner reports its
  failures with source context, and cleanup and successful result types remain unchanged.

### language.design.010 — `catch` without a capture substitutes the type default and says nothing

- Recorded: 2026-08-07 07:43
- Updated: 2026-09-16 16:04 — separated existing capabilities from the remaining design contract
- Area: language
- Found while: the same pass
- Observation: `catch f()` handles the error, drops it, and yields the default value for the result
  type
  ([013_001_error_management.swg](../bin/reference/modules/language/src/013_001_error_management.swg)).
  It is a one-word conversion of a failure into a zero, with no `discard`-style ceremony — while the
  language elsewhere refuses to let an ordinary return value be ignored without `discard`
  ([007_007_discard.swg](../bin/reference/modules/language/src/007_007_discard.swg)). The two
  policies point in opposite directions: an unread `s32` is an error, an unread *failure* is a zero.
- Evidence: `func swallow()->s32 { return catch mustFail() }` returns 0 with no diagnostic.
- Elsewhere: Swift's `try?` preserves failure as an optional result, while `try!` asserts success
  ([Swift error handling](https://raw.githubusercontent.com/swiftlang/swift-book/main/TSPL.docc/LanguageGuide/ErrorHandling.md)).
  These make different promises from substituting the ordinary result type's default.
- Proposed contract: A handler either supplies an explicit replacement of the result type, propagates or
  exits, or deliberately discards a failure from an operation whose result is not needed.
  It never synthesizes zero/null as successful output. The error should be accessible inside
  the handler and fallback evaluation must be lazy. Existing fail/try/catch and error-as-value
  support remain the baseline; this entry does not add a second Result/exception system.
- Next: Specify value-producing catch handlers using safeCount, blockCatchElse and GUI font
  loading as before/after cases. Classify bare catches as discard, fallback or preserved error.
  Define owned-result adoption and failed-path cleanup, including non-defaultable results.
  Coordinate local capture scope with language.design.025 and divergence with language.design.031.
- Complete when: fallback, propagation, termination and explicit discard cannot be confused, a successful
  result never requires a fabricated failure value, and side effects/lifetimes are tested.

### language.design.019 — `if let` combines binding with an implicit truthiness test

- Recorded: 2026-08-07 07:43
- Updated: 2026-09-16 16:04 — separated existing capabilities from the remaining design contract
- Area: language
- Found while: the same pass
- Observation: the declaration in an `if` is converted to a boolean — non-zero, non-null — and the
  `where` clause runs only if that hidden test passed
  ([005_001_if.swg](../bin/reference/modules/language/src/005_001_if.swg)). So the
  line has two conditions, only one of which is written down, and the unwritten one is a truthiness
  coercion the rest of the language is careful about. `if let a = 0` takes the `else` branch, which
  is a surprise for anyone reading it as a binding.
- Evidence: `if let str = retNothing() where str[0] == 's'` takes the `else` branch without
  evaluating the `where`. Confirmed under the JIT and the forged binary.
- Elsewhere: Rust `if let` matches a pattern, which may be irrefutable; `if let a = 0` is accepted with
  an irrefutable-pattern warning rather than rejected as an integer condition
  ([Rust if expressions](https://doc.rust-lang.org/reference/expressions/if-expr.html)).
  This differs from converting the bound integer to a boolean.
- Proposed contract: Conditional binding tests presence or a pattern, never scalar truthiness. Nullable
  strings/slices already distinguish an empty present value from null; preserve that behavior.
  A nullable pointer to a zero-valued object is present. A future tagged case carrying false is
  a successful case match. Plain scalar predicates remain explicit comparisons/booleans.
- Next: Inventory if/while/case bindings by source type and distinguish ordinary boolean conditions
  from binding syntax. Migrate nonzero scalar bindings to explicit predicates and preserve
  where short-circuiting. Reuse existing is/as dynamic patterns rather than inventing them again.
- Complete when: bindings distinguish absence from zero/false/empty payloads, evaluate once, scope names
  to successful branches, and preserve those rules through guards and nested patterns.

### language.design.023 — A blank `cast()` performs whatever conversion the target turns out to need

- Recorded: 2026-08-10 07:44
- Updated: 2026-09-16 16:04 — separated existing capabilities from the remaining design contract
- Area: language
- Found while: the same pass
- Observation: `cast()` with no type "allows the compiler to infer the target type"
  ([003_007_cast.swg](../bin/reference/modules/language/src/003_007_cast.swg)), and
  the conversion it then performs is whichever one that target requires — including a float
  truncation and an integer narrowing, in a language that otherwise refuses both without a written
  cast. The spelling is a blanket permission attached to a call site rather than to a conversion:
  it says "convert this", never "convert this to that", so changing a parameter's type at the callee
  silently changes what every `cast()` argument does. The reference's own example is a truncation
  presented as a convenience.
- Evidence: `testAutoCast(cast() 1.4)` is the reference's illustration, and `1.4` arrives as `1`. An
  isolated probe, `swc test -d <dir>`: one source expression, two targets, two different silent
  conversions.

  ```swag
  func takeS32(value: s32)->s32 => value
  func takeU8(value: u8)->u8 => value
  Swag.print(takeS32(cast() 1.9), " ", takeU8(cast() 1.9))     // 1 1
  ```

- Elsewhere: Zig names conversion categories separately, including `@intCast` and `@truncate`, while
  inferring destinations from context
  ([Zig language reference](https://ziglang.org/documentation/master/#intCast)).
  Target inference and the permitted conversion category are independent choices.
- Proposed contract: Keep existing cast #bit, dynamic cast #try/#assume, and type patterns distinct from
  numeric conversion. The gap is target-inferred numeric permission: checked narrowing, fractional
  truncation and saturation must not become interchangeable when a callee changes type. Infer
  the target only after fixing the conversion category; remove conversions that are lossless
  and already implicit.
- Next: Classify blank numeric casts and compare explicit operations or modifiers for checked
  narrowing, truncation and saturation. Reuse existing bit reinterpretation. Specify NaN,
  infinity, negative-to-unsigned, boundary overflow and whether failure is recoverable; these
  semantics must remain defined when optional safety guards are disabled.
- Complete when: numeric conversion categories and failure policies are explicit and tested, target
  inference cannot silently choose another category, and no existing dynamic/bit cast is duplicated.

### language.design.011 — The apostrophe carries three unrelated roles

- Recorded: 2026-08-07 07:43
- Updated: 2026-09-16 16:04 — separated existing capabilities from the remaining design contract
- Area: language
- Found while: the same pass
- Observation: `'` opens a character literal, introduces a literal suffix, and introduces a generic
  argument list. Which one applies depends on the token *before* it
  ([003_003_string.swg](../bin/reference/modules/language/src/003_003_string.swg)),
  so `5's32`, `genericTwice's64(12)`, `floatWindow.at'1()`, `Duration = 500'ms` and `'a'` all use
  the same character across those three roles — and a user-defined literal suffix
  ([006_010_custom_literals.swg](../bin/reference/modules/language/src/006_010_custom_literals.swg))
  makes the suffix set open, so `x'foo` cannot be read without knowing what `x` is. Blanks do not
  disambiguate: `5 's32` is the suffixed literal, not `5` followed by a character.
- Evidence: `let spaced = 5 's32` yields 5 as an `s32`; `idOf's32(7)` is a generic call and reads
  like a suffixed identifier; `' 'u32` is a space literal followed by a suffix.
- Elsewhere: Rust also overloads the apostrophe, distinguishing character literals from lifetime tokens
  ([Rust tokens](https://doc.rust-lang.org/reference/tokens.html)). This is a lexer comparison,
  not evidence that Swag must change its generic delimiter.
- Current editor evidence: `vscode/tests/grammar.test.js` now exercises generic type arguments
  beside a call, including whitespace before the apostrophe. It reproduced and protects the
  corrected builtin-type scope; the broader comparison of lexical roles remains to be measured.
- Proposed contract: Use one delimited generic-argument form distinguishable from character literals and
  numeric/unit suffixes. This is a readability/syntax proposal, not a missing generics feature or
  an unresolved coloring bug. Compare angle brackets with another dedicated delimiter rather
  than assuming familiar punctuation has no parse cost.
- Next: Translate Array'u8, HashTable'(K, V), genericTwice's64(12), and value arguments such as
  at'1() into each candidate. Test nesting, comparisons/shifts next to generic calls, inferred
  arguments, formatting and incomplete editor input. Select one spelling and an AST-based
  migration; literal suffixes and character literals must retain an independent grammar.
- Complete when: one generic syntax is chosen from a measured corpus and parser, formatter, reference and
  editor grammar agree, including value arguments and incomplete code; no competing alias remains.

### language.design.021 — The base a number is written in decides its signedness

- Recorded: 2026-08-10 07:44
- Updated: 2026-09-16 16:04 — separated existing capabilities from the remaining design contract
- Area: language
- Found while: a second reading pass over the reference, checking what the type of a literal depends
  on
- Observation: a decimal literal is an unsized constant of *unknown* sign, and a hexadecimal or
  binary one is an unsized constant of *unsigned* sign. Both adapt to an imposed type, so the
  difference is invisible wherever the target is written down — and it becomes the constant's real
  type the moment nobody writes one. `const Mask = 0xF0` is a `u32`, `const Mask = 240` is an `s32`,
  and from there the difference travels into every expression the constant enters, where language.design.008's
  "the unsigned type wins" rule applies it to the other operand. The reference documents the
  defaulting ("hexadecimal or binary literals default to type `u32`"
  ([003_002_number_literals.swg](../bin/reference/modules/language/src/003_002_number_literals.swg)))
  alongside the signed decimal default. The remaining question is whether that deliberate
  base-dependent default should change.
- Evidence: `Sema.Literal.cpp` builds a decimal literal with `TypeInfo::Sign::Unknown`
  ([Sema.Literal.cpp](../src/Compiler/Sema/Ast/Sema.Literal.cpp)) and a hex or binary one
  with `Sign::Unsigned`
  ([Sema.Literal.cpp](../src/Compiler/Sema/Ast/Sema.Literal.cpp),
  [Sema.Literal.cpp](../src/Compiler/Sema/Ast/Sema.Literal.cpp)). A historical isolated probe,
  `swc test -d <dir>`, prints two types for one value:

  ```swag
  const Mask    = 0xF0
  const DecMask = 240
  var value: s32 = 0x7F
  Swag.print(#nameof(#typeof(value & Mask)))       // u32
  Swag.print(#nameof(#typeof(value & DecMask)))    // s32
  ```

  A `let bound = 0xF0` behaves like the `const`. The boundary is worth stating exactly, because it
  is what makes the rule hard to see: a *bare* literal still adapts, so `x | 0b0001` on an `s32`
  compiles and yields `s32`. The signedness only survives once the literal has been named — a
  `const`, or a `let` with no annotation — and from then on it is the constant's type, not a
  literal's default. The reference's operators page writes `x = x | cast(s32) 0b0001`
  ([003_006_operators.swg](../bin/reference/modules/language/src/003_006_operators.swg))
  where the plain form compiles, which is some evidence that the boundary is not obvious even to the
  page documenting the operators.
- Elsewhere: Go integer literals remain untyped constants until context or defaulting supplies a type
  ([Go constants](https://go.dev/ref/spec#Constants)). The spelling base does not choose an
  unsigned default for a small hexadecimal value.
- Proposed contract: Equal integer values should infer the same unsuffixed type regardless of decimal,
  hex or binary spelling. Contextual adaptation already exists; keep it. Explicit signed/unsigned
  suffixes remain the way to request a representation. Name binding must not preserve a hidden
  base-dependent signedness that the same bare literal would lose.
- Next: Prototype Sign::Unknown for hex/binary constants and compare current bin/ inferred
  declarations and overload choices. Specify the default width and behavior above the signed
  maximum, including bit masks and enum values. Coordinate with language.design.008 so changing
  the default does not merely move a surprising promotion to a different boundary.
- Complete when: equal unsuffixed values share a base-independent default policy, explicit suffixes stay
  stable, and named constants, bare contextual literals, masks and boundary values are tested.
- Related: [language.design.008](#languagedesign008--mixing-a-signed-and-an-unsigned-operand-of-the-same-width-converts-the-signed-one)
  is what turns the difference into arithmetic.

### language.design.014 — Choose a consistent half-open convention for collection APIs

- Recorded: 2026-08-07 07:43
- Updated: 2026-09-16 16:04 — separated existing capabilities from the remaining design contract
- Area: language
- Found while: the same pass
- Observation: `str[1 to 3]` is three elements, `str[1 until 3]` is two
  ([004_002_slice.swg](../bin/reference/modules/language/src/004_002_slice.swg)).
  There is no implicit endpoint choice here: the author writes `to` or `until`. Half-open
  intervals compose at adjacent boundaries and have length `high - low`; choosing that form
  consistently for collections is a convention decision, not missing functionality.
- Evidence: `s[1 to 3]` is `"tri"`, `s[1 until 3]` is `"tr"`. The empty and inverted cases then need
  their own paragraph and their own runtime guard
  ([004_002_slice.swg](../bin/reference/modules/language/src/004_002_slice.swg)),
  which remain necessary for inverted or out-of-bounds half-open ranges too. Equal half-open
  bounds are the empty case and already have reference tests.
- Elsewhere: Rust provides both half-open and inclusive ranges with distinct operators
  ([Rust range expressions](https://doc.rust-lang.org/reference/expressions/range-expr.html)).
  Swag also exposes both choices, using words rather than punctuation.
- Proposed contract: Both inclusive to and half-open until already exist, and each explicitly states its
  endpoint policy. The missing decision is a consistent collection convention, not a missing
  half-open range operator. Prefer until in slices and index loops when the upper value denotes
  a boundary/count. Keep to where an inclusive domain is the actual intent.
- Next: Classify bin/ slice and index-loop callers by boundary meaning. Migrate examples and
  coherent API families to until where they already operate on lengths or exclusive endpoints.
  Do not mechanically replace to: converting an inclusive last index to an exclusive endpoint
  can overflow at the maximum integer. Change grammar only if this audit finds a real gap.
- Complete when: the collection convention is documented and represented consistently in examples and
  APIs, with empty, adjacent, inverted and maximum-endpoint cases covered using existing syntax.

### language.design.015 — `#[Swag.EnumFlags]` changes implicitly assigned member values

- Recorded: 2026-08-07 07:43
- Updated: 2026-09-16 16:04 — separated existing capabilities from the remaining design contract
- Area: language
- Found while: the same pass
- Observation: adding the attribute changes `A` from 0 to 1, `B` from 1 to 2, `C` from 2 to 4
  ([004_004_enum.swg](../bin/reference/modules/language/src/004_004_enum.swg)).
  The attribute reads as a statement about how the values are *used*; it is in fact a statement
  about what the values *are*. On a serialized, persisted, or ABI-visible enum, adding it is a
  silent wire-format break, and the first member loses the zero that a flag set needs for "none".
- Evidence: the reference's own example asserts `MyFlags.A == 0b00000001` for an enum declared
  `{ A, B, C, D }`.
- Elsewhere: C# documents explicit powers-of-two member values alongside its `Flags` attribute
  ([C# enumeration types](https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/builtin-types/enum)).
  The attribute itself does not assign those powers of two.
- Proposed contract: Flag sets already exist. Decide whether their semantic identity should be a dedicated
  declaration form rather than an attribute changing an ordinary enum's implicit values.
  Distinguish an empty set, individual flags and combinations; do not conflate flags with the
  closed mutually exclusive variants in language.design.002. Any new spelling must replace
  the old mechanism, not permanently duplicate it.
- Next: Compare the existing attributed declaration with a direct flags declaration on public
  and serialized types. Specify zero, automatic bit allocation, combined constants, masks and
  explicit ABI values. A source edit that changes representation must be visible in the schema
  or API review; choose whether stable representations require explicit values.
- Complete when: the selected declaration and representation contract is documented and migrated, and
  tests cover empty sets, combinations, reflection, serialization and public numeric stability.

### language.design.017 — Mixins resolve their body in the caller's scope

- Recorded: 2026-08-07 07:43
- Updated: 2026-09-16 16:04 — separated existing capabilities from the remaining design contract
- Area: language
- Found while: the same pass
- Observation: a mixin body names variables that do not exist where it is written and are expected
  to exist wherever it is called
  ([015_001_mixins.swg](../bin/reference/modules/language/src/015_001_mixins.swg)).
  That is expansion-time lookup in the caller, in a language whose macros went to the trouble of being hygienic
  ([015_002_macros.swg](../bin/reference/modules/language/src/015_002_macros.swg)).
  Free identifiers in a mixin cannot be fully resolved at its declaration, a typo in it is reported once per call site, and
  renaming a local in a *caller* can break a mixin declared in another file.
- Evidence: `#[Swag.Mixin] func myMixin() { a += 1 }` compiles with no `a` in sight and resolves to
  whatever `a` the call site has.
- Elsewhere: Rust macros have mixed-site hygiene: local variables and labels resolve at the definition
  site, while other symbols resolve at the invocation site
  ([Rust macro hygiene](https://doc.rust-lang.org/reference/macros-by-example.html#hygiene)).
  Hygiene is not a blanket claim that every identifier resolves in one scope.
- Proposed contract: Resolve ordinary metaprogram names lexically and require explicit parameters or
  declared captures for caller-owned state. Macros already have hygiene and #code parameters;
  the gap is mixin free-name lookup. Reuse that existing machinery instead of introducing a
  third expansion system. Declared intentional capture must remain distinguishable from a typo.
- Next: Classify free-name mixins and rewrite representative cases with current parameters and
  block bindings. Specify any capture capability those cannot express. Test helper imports,
  shadowing and caller-local renames, and diagnose undeclared free names at the definition.
- Complete when: a mixin cannot silently depend on an unrelated caller identifier, intentional captures
  are declared, and definition/call-site diagnostics preserve useful expansion provenance.
- Related: `#uniq0`..`#uniq9` exist precisely to work around the collisions this creates, and there
  are exactly ten of them.

### language.design.018 — A macro can redefine `break` and `continue` inside the block the caller wrote

- Recorded: 2026-08-07 07:43
- Updated: 2026-09-16 16:04 — separated existing capabilities from the remaining design contract
- Area: language
- Found while: the same pass
- Observation: `#inject(what, break = break to Outer, continue = break)` rewrites the meaning of
  two keywords in code the caller wrote and can see
  ([015_002_macros.swg](../bin/reference/modules/language/src/015_002_macros.swg)).
  The caller's `break` is not shadowed or wrapped — it is replaced, with nothing at the call site
  indicating that the block's control flow is under someone else's control.
- Evidence: the reference's `repeatSquare` remaps `continue` to `break`, so a `continue` written in
  the user block exits the inner loop instead of continuing it — `continue` becomes an exit from that generated inner loop.
- Elsewhere: Rust macros can transcribe token trees and parsed blocks into surrounding control flow
  ([Rust macros](https://doc.rust-lang.org/reference/macros-by-example.html)). A captured bare
  `break` is not guaranteed to target a loop outside the expansion. Swag separately exposes explicit
  break/continue remapping through `#inject`.
- Proposed contract: Keep ordinary loop break/continue/return targets lexical. A general code-block API
  that deliberately intercepts control flow must expose that effect at its boundary. Existing
  opVisit relies on remapping; it cannot simply be prohibited before an alternative protocol
  has preserved its behavior. That provider protocol is owned by language.design.034.
- Next: Specify explicit control-flow capabilities for arbitrary #code blocks and classify current
  remaps as loop implementation or intentional interception. Coordinate the former with
  language.design.034; test nested loops, labeled exits, early return, fail and defer for both.
- Complete when: callers can identify any nonlexical control-flow interception, ordinary iteration needs
  no hand-authored remapping, and regression tests observe the exact exit and cleanup targets.

### language.design.020 — There are two metaprogramming systems and they do not meet

- Recorded: 2026-08-07 07:43
- Updated: 2026-09-16 16:04 — separated existing capabilities from the remaining design contract
- Area: language
- Found while: the same pass
- Observation: `#ast` generates code by returning a *string* of Swag source, built with `+` or a
  byte buffer
  ([015_003_generated_code_with_ast.swg](../bin/reference/modules/language/src/015_003_generated_code_with_ast.swg)),
  while macros and mixins generate code by injecting *parsed blocks* with declared, typed, hygienic
  parameters
  ([015_002_macros.swg](../bin/reference/modules/language/src/015_002_macros.swg)). The input representations differ: `#ast` reparses generated source text, whereas
  `#inject` expands parsed code. Macros can contain declarations in their expanded scope and
  can use `#ast`; the missing convenience is typed generation of repeated struct or enum members.
  `#ast(...)` already accepts text parts, so callers do not always need a concatenation buffer.
- Evidence: the reference's own real-world example builds struct fields by string-formatting a
  reflected field list into `"%: bool\n"`; a typo there surfaces as a parse error in generated
  source.
- Elsewhere: Rust macros accept parsed fragments as well as token trees, and can expand to items or
  expressions ([Rust macro fragments](https://doc.rust-lang.org/reference/macros-by-example.html#metavariables)).
  This is a useful comparison for which generated shapes share an input representation.
- Proposed contract: Add structured, typed generation for repeated declarations instead of formatting
  source strings. Existing #run, reflection, hygienic macros and #code injection remain useful.
  The concrete missing shape is generating fields/cases from reflected members with checked
  names, types and attributes; arbitrary text can remain an explicit escape hatch.
- Next: Classify #ast outputs, starting with
  [CommandLine.IsSet](../bin/std/modules/core/src/system/commandline.swg) and the reference's
  reflected-field example. Prototype one typed field-generation operation
  expressing that same transformation without a StringBuilder. Specify lexical lookup, duplicate
  names, source locations, generated docs and visibility before generalizing to all syntax.
- Complete when: the reflected-field transformation uses checked declarations, errors identify both the
  generator and source member, and the implementation does not add a competing macro language.

### language.design.024 — Make nontrivial copies explicit at owning call boundaries

- Recorded: 2026-08-10 07:44
- Updated: 2026-09-16 16:04 — separated existing capabilities from the remaining design contract
- Area: language
- Found while: the same pass
- Observation: `#move` in a parameter position is documented as part of the signature — "they select
  how an argument reaches the callee"
  ([002_008_sigils.swg](../bin/reference/modules/language/src/002_008_sigils.swg)).
  The caller can still choose a copy: a `#move` parameter also accepts a plain copyable argument, and the
  compiler materializes a call-site copy and moves *that*
  ([006_009_custom_copy_and_move.swg](../bin/reference/modules/language/src/006_009_custom_copy_and_move.swg)).
  So a signature that reads "this callee consumes your value" is satisfied by a caller that keeps
  it, and the difference between the two call styles is one hidden copy of the whole aggregate,
  visible in the source as nothing at all. The capacity is deliberate and `#fwd` exists to avoid the
  copy; what is not marked anywhere is *which* call paid for it.
- Evidence: the reference measures the copy itself. With `Vector3.opPostCopy` adding 1 and
  `opPostMove` adding 2, `assign(&b, a)` through a `#move` parameter yields `4, 5, 6` — one copy then
  one move — while `assign(&b, #move a)` yields `3, 4, 5`
  ([006_009_custom_copy_and_move.swg](../bin/reference/modules/language/src/006_009_custom_copy_and_move.swg)).
- Elsewhere: Rust copies values implementing `Copy` and otherwise moves them in value contexts
  ([Rust moved and copied values](https://doc.rust-lang.org/reference/expressions.html#moved-and-copied-types)).
  Saying that every Rust by-value call moves would omit the copyable case.
- Proposed contract: Make nontrivial duplication explicit at owning boundaries. An opDrop type already
  denies copying without opPostCopy; ordinary by-value struct parameters already borrow a const
  address, and named-local returns already transfer in the unobserved case. Preserve these gains.
  The remaining question is the implicit opPostCopy performed for an unmarked argument to a
  consuming parameter, not whether every function argument should consume its source.
- Next: Compare mandatory explicit copy with default transfer specifically for owning assignment,
  initialization and consuming parameters. Use String, Array and a copy-counting fixture; include
  callbacks, interfaces and deferred observations. Choose one rule, measure migration, and never
  auto-insert #move merely to silence a warning. Non-defaultable source reset is language.design.035.
- Complete when: the selected owning-call contract exposes every nontrivial duplication and intentional
  transfer, without making ordinary borrowed struct calls consume or allocate.

### language.design.025 — A `catch ... as err` capture is a declaration that leaks into the enclosing scope

- Recorded: 2026-08-10 07:44
- Updated: 2026-09-16 16:04 — separated existing capabilities from the remaining design contract
- Area: language
- Found while: the same pass
- Observation: `as err` "binds a fresh local ... visible in the enclosing scope, after the catch, so
  each capture in a given scope needs its own name"
  ([013_001_error_management.swg](../bin/reference/modules/language/src/013_001_error_management.swg)).
  The declaration is written inside an expression, in the middle of an initializer, and its effect
  reaches outward past the statement it appears in. Other binding constructs use different scopes: `if let`
  scopes its binding to the branch, `for` to the body, `switch ... as` to the case. The consequence
  the reference states — two catches in one scope collide — is the visible half; the invisible half
  is that the name is live for the rest of the block whether or not it was read, so an unused-capture policy would have to examine the enclosing scope.
- Evidence: the reference's own paragraph, and its `blockCatchCode` example, where `err` is declared
  by a `catch { ... } as err` block and tested two statements later
  ([013_001_error_management.swg](../bin/reference/modules/language/src/013_001_error_management.swg)).
- Elsewhere: Go returns an error into an ordinary short declaration, whose rules permit reuse of an
  existing name when at least one non-blank name is new
  ([Go short declarations](https://go.dev/ref/spec#Short_variable_declarations)).
  Rust match bindings instead belong to the arm and its guard
  ([Rust match bindings](https://doc.rust-lang.org/reference/expressions/match-expr.html)).
- Proposed contract: Give a handler's error binding the handler's lexical scope. If a caller needs to
  retain success/failure for later statements, it must declare that result explicitly in the
  outer scope. Existing error values and type patterns suffice for inspecting dynamic errors;
  static error-set typing is not required to fix binding scope.
- Next: Count later reads and deferred captures of catch-as locals. Specify a migration to scoped
  handlers for local recovery and explicit stored outcomes for delayed inspection. Test two
  handlers using the same error name, shadowing, success paths, borrowed payloads and cleanup.
- Complete when: handler-only errors cannot leak into the enclosing block, intentionally stored errors
  have an explicit owner/lifetime, and the migration preserves delayed inspection.
- Related: [language.design.010](#languagedesign010--catch-without-a-capture-substitutes-the-type-default-and-says-nothing)

### language.design.022 — The cost of value-dependent float inference is unmeasured

- Recorded: 2026-08-10 07:44
- Updated: 2026-09-16 16:04 — separated existing capabilities from the remaining design contract
- Evidence: `ApFloat::minBits` and scalar concretization select `f32` when the parsed value fits
  without further rounding, otherwise `f64`. The number-literals reference now states that rule
  and tests `1.5`, `0.1`, `16777216.0`, `16777217.0` and an explicitly rounded `f32`.
- Proposed contract: Choose one stable default width for unconstrained floating literals instead of using
  exact representability to choose f32 or f64. Prefer evaluating f64 as the default candidate;
  contextual f32 and explicit suffixes remain supported. This is a type-default change, not a
  claim that decimal fractions can all be represented exactly.
- Next: Compare the resulting types, overloads, storage and arithmetic for 1.5, 0.1, 16777216.0
  and 16777217.0 under a fixed default. Measure bin/ numeric kernels and serialized/public fields;
  migrate intentional f32 data explicitly and define rounding at contextual conversion.
- Complete when: the default no longer depends on the literal's exact representability, its cost and
  migration are recorded, and contextual/suffixed/defaulted literals have executable rules.

### language.design.031 — Let expect consume a result without inventing a default value

- Recorded: 2026-09-16 15:52
- Evidence: the error-management reference specifies that expect panics only while the Expect
  safety guard is enabled and otherwise yields the result type's default. It consequently rejects
  non-null pointer results. The clean pass found adapters whose only job is to weaken a successful
  pointer to nullable: createCorpusTypeFace in
  [pdf.corpus.test.swg](../bin/std/modules/gui/src/tests/pdf.corpus.test.swg) wraps TypeFace.create,
  and its caller immediately writes `(expect createCorpusTypeFace(...))!`.
  [pdf.fontprogram.test.swg](../bin/std/modules/gui/src/tests/pdf.fontprogram.test.swg) has the same
  nullable adapter for catch-based recovery. The restriction is documented in
  [error management](../bin/reference/modules/language/src/013_001_error_management.swg);
  this is a design limitation, not a newly reproduced compiler defect.
- Proposed direction: expect returns the successful T or does not return, in every configuration.
  Its failure path must not require T to have a default. Model non-returning expressions in typing
  so a panic or an early exit can inhabit a handler without a dummy value. Keep a deliberately
  unchecked assumption separate from ordinary expect.
- Elsewhere: Rust's [Result::expect](https://doc.rust-lang.org/std/result/enum.Result.html#method.expect)
  returns T or panics and does not require T: Default; its
  [never type](https://doc.rust-lang.org/reference/types/never.html) represents computations that
  do not complete and can coerce to another type. These are specific contracts to compare, not a
  recommendation to copy Rust's complete error model.
- Next: specify the always-diverging failure contract and its cost, including the deliberate break
  with disabling the Expect guard. Prototype a direct `expect TypeFace.create(...)` and a handler
  that exits on failure, then remove the adapters only after the compiler supports them. Test
  non-null pointers, non-defaultable owning results, successful ownership transfer, and cleanup
  during failure in JIT, native devmode, and native release.
- Complete when: expect can produce a non-defaultable result without nullable adapters, its failure
  cannot continue with a fabricated value, and the reference and lifecycle tests enforce that
  contract in every supported configuration.
- Related: language.design.010, language.design.025, language.design.030; compiler.safety.011.

### language.design.027 — Loop index types follow different count, range, and collection rules

- Recorded: 2026-08-10 07:53
- Updated: 2026-09-06 17:53 — the reference now carries executable assertions for the count/range distinction
- Evidence: `SemaHelpers::resolveCountOfResult` concretizes unsized integer counts with an
  unsigned preference but preserves a runtime integer's type. `AstForStmt` uses that count type
  or the range expression's type. `foreachElementTypes` ordinarily supplies `u64`, but an
  enum-indexed array supplies its enum index type. Custom `opVisit` code defines its own bindings.
  Sources: [Sema.Loop.cpp](../src/Compiler/Sema/Ast/Sema.Loop.cpp),
  [SemaHelpers.Symbol.cpp](../src/Compiler/Sema/Helpers/SemaHelpers.Symbol.cpp).
- Evidence: the old three-loop probe (`values`, `3`, `0 to 2`) gives `u64`, `u32`, `s32`, but
  these are examples rather than three fixed per-form types. Existing
  [for.swg](../bin/unittests/sema/flow/for.swg) checks a runtime `s32` count, and
  [for_elements.swg](../bin/unittests/sema/flow/for_elements.swg) checks enum-indexed arrays.
  The reference explains the count/range distinction and includes executable assertions for it.
- Elsewhere: Go array/slice indices are `int`, while integer-range values take the integer
  expression's type when it has one ([Go range clauses](https://go.dev/ref/spec#For_range)).
  Thus Go also distinguishes collection and integer iteration; the old uniformity claim was false.
- Next: measure whether the existing count/range rules cause real migration or arithmetic
  problems before proposing a common type. Include typed counts, large constants, enum-indexed
  arrays, and custom iterators rather than extrapolating from three small literals.
- Complete when: a measured policy decision retains or changes these rules and compiler and
  reference tests cover each selected boundary.
- Related: language.design.008.

### language.design.007 — One default in a grouped declaration silently defaults every name in the group

- Recorded: 2026-08-07 07:43
- Updated: 2026-09-06 07:51 — git: prompt 6
- Area: language
- Found while: the same pass
- Observation: `x, y: s32 = 0` declares two parameters and gives *both* the default `0`. The
  grouped form was introduced to share a type
  ([003_005_variables.swg](../bin/reference/modules/language/src/003_005_variables.swg));
  sharing the initializer as well is the same rule applied one token further, and it means a
  parameter list can hand out a default nobody asked for. A caller can then omit an argument that
  reads as required, and get a zero.
- Evidence: `func f(x, y: s32 = 0) => x + y * 2` accepts `f(x: 10)` (→ 10) *and* `f(y: 10)` (→ 20).
  The reference shows exactly this call pair and treats it as ordinary
  ([007_001_declaration.swg](../bin/reference/modules/language/src/007_001_declaration.swg)).
  The *type* travels the same way: `func sum3(x, y = 0.0)` gives both parameters `f32`, so one
  omitted annotation types the whole group
  ([007_001_declaration.swg](../bin/reference/modules/language/src/007_001_declaration.swg)).
- Elsewhere: Go permits grouped parameter names with one type, but its parameter grammar has no default
  initializer ([Go function types](https://go.dev/ref/spec#Function_types)). This separates the two
  design choices that Swag combines.
- Next: sweep `bin/` for grouped parameter declarations carrying a default and count how many
  are deliberate. If the honest answer is "almost none", the rule to consider is that a default in a
  grouped declaration applies to the last name only, or is rejected outright — both are mechanical
  migrations. Decide it before the surface grows further.
- Complete when: grouped defaults have a measured compatibility cost and one documented rule, with
  reference and compiler tests covering named calls that omit each member of the group.

### language.design.013 — A `switch` accepts several `default` clauses

- Recorded: 2026-08-07 07:43
- Updated: 2026-09-06 07:51 — git: prompt 6
- Area: language
- Found while: the same pass
- Observation: a `default` can carry a `where`, and once it can, a switch can hold several of them
  ([005_005_switch.swg](../bin/reference/modules/language/src/005_005_switch.swg)).
  A guarded `default` only runs when its condition succeeds, so several such arms can precede
  the final unconditional fallback. The open question is whether their spelling communicates that order.
- Evidence: `AstSwitchCaseStmt::semaPreNodeChild` exempts guarded defaults from duplicate-default
  checking. Constant case values are checked only when the guard is absent or folds to true;
  nonconstant guards may repeat a value. The old assertion that duplicate values were rejected
  regardless of their guard was incorrect. See `checkDuplicateConstCaseValue` and
  `checkDuplicateCaseValuesAfterWhere` in
  [Sema.Switch.cpp](../src/Compiler/Sema/Ast/Sema.Switch.cpp).
- Elsewhere: Rust permits guarded wildcard patterns and checks arms in order
  ([Rust match expressions](https://doc.rust-lang.org/reference/expressions/match-expr.html#match-guards)).
  Guarded catch-all arms therefore have a precedent even though Rust does not call them `default`.
- Next: `case where <cond>` already expresses a valueless guarded arm in an expression-less
  `switch` ([005_005_switch.swg](../bin/reference/modules/language/src/005_005_switch.swg)).
  Check whether `default where` can be spelled that way instead and `default` restored to exactly
  one unguarded arm — a small change with a mechanical migration, if `bin/` does not lean on it.
- Complete when: a switch has one unmistakable fallback form, guarded fallback usage has been
  measured and migrated or retained deliberately, and duplicate-arm tests protect the rule.

### language.design.026 — `[2, 2] T` and `[2][2] T` are different types indexed the same way

- Recorded: 2026-08-10 07:44
- Updated: 2026-09-06 07:51 — git: prompt 6
- Area: language
- Found while: the same pass
- Observation: the two spellings produce unrelated types that do not convert to each other, and the
  reference warns about it
  ([004_001_array.swg](../bin/reference/modules/language/src/004_001_array.swg)).
  What makes it a trap rather than a choice is that `[i, j]` indexes both. The one place a reader
  could notice which type they have — the use site — reads identically for the two, so the
  distinction is visible only in the declaration and only if it is nearby. The advice the page gives
  is to "pick one spelling per API and keep it", which is the shape of a rule the compiler could
  enforce and does not.
- Evidence: the reference's own example declares `[2, 2] s32` and `[2][2] s32` side by side and
  indexes both with `array[0, 1]`.
- Elsewhere: C# distinguishes rectangular and jagged arrays in both declaration and indexing syntax
  ([C# arrays](https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/builtin-types/arrays)).
  Their reference-storage representation is not the same as two Swag fixed-array layouts.
- Next: measure before proposing anything: count `[a, b] T` versus `[a][b] T` declarations in
  `bin/`. If one form is vestigial, deleting it is better than documenting it. If both are used, the
  cheap guard is a warning when the two appear in one module's public surface, since the cost lands
  on the consumer who cannot see the declarations side by side.
- Complete when: both multidimensional-array forms are measured in implementation and public APIs,
  and their compatibility or intentionally distinct use-site contract is documented and enforced.

### language.design.029 — '.buffer' answers a non-null pointer for a payload that can be absent

- Recorded: 2026-08-23 09:26
- Updated: 2026-09-06 07:51 — git: prompt 6
- Area: language
- Found while: widening the never-null condition rule. The `bin/` sweep it forced stopped
  on `if (ptrAny[]).buffer` in `convertAny`, which reads as "does this value carry a payload" and
  which the type system now calls a constant.
- Observation: `.buffer` of a `string` or `cstring` now carries the source's `?`, but the `any`
  and `interface` cases still answer a non-null block pointer whatever the payload is. The
  container's own nullability is not the payload's: a non-null `any` built by `Swag.makeAny(null, type)`
  and an interface whose `obj` was never set both hand back null, and `bin/std` already tests for
  it — `encoder.swg` writes `if not itf.obj` on the raw field precisely because `.buffer` would not
  let it ask.
- Evidence: `semaIntrinsicDataOf` ([Sema.Intrinsic.cpp](../src/Compiler/Sema/Ast/Sema.Intrinsic.cpp))
  builds the `any` and `interface` results with `TypeInfo::makeBlockPointer(typeVoid(), flags)`,
  where `flags` comes from the container type. Probe — `convertAny` had to read its `any` through
  `[as any?]` to keep asking the question at all. At the historical
  2026-09-02 HEAD (0.1.315), a raw tracked-source inventory reports 3,972 `.buffer` occurrences
  under `bin/**/*.swg` and `bin/**/*.swgs`; that is an upper bound, not the number requiring a
  nullable assertion, because the receiver types have not yet been classified.
- Elsewhere: Rust represents an optional borrowed reference with `Option<&T>`
  ([Rust Option](https://doc.rust-lang.org/std/option/)). The comparison concerns the payload's
  absence; it does not by itself choose a contract for Swag's erased container.
- Next: decide whether the `any` and `interface` payload pointers are always nullable-capable,
  which is what the runtime says. Classify the inventory by receiver type before estimating the
  migration; the eventual sweep may require `cast(*T) itf.buffer!` at affected sites. Also consider
  whether a non-null `any` should instead
  be the type that promises a payload, making `Swag.makeAny(null, type)` the thing that needs `?`.
- Complete when: `.buffer` uses are classified by receiver type, the payload-pointer nullability
  contract is documented, and the resulting migration plus compiler and module tests agree.

---

## Generic contracts and execution semantics

Native concurrency and parallel execution are covered in
[language.parallelism.md](language.parallelism.md#languageparallelism001--the-shipped-model-and-the-promises-it-does-not-yet-make).

Surprises in the language itself: rules that are consistent on their own page and stop being
consistent once two pages meet, spellings that carry more than one meaning, and defaults that
read one way and behave another. These are observations against the reference
([bin/reference/modules/language/src](../bin/reference/modules/language/src)), not compiler
defects — the compiler does what the reference says. What is in question is whether the reference
should say it.

Compiler defects are in [compiler.core.md](compiler.core.md).

Each comparative investigation carries an `Elsewhere` line: what the neighbouring languages do about the same
question. A wart no one else has and a convention half the industry shares are different problems,
and the line exists so the difference is on the page before anyone argues from taste. It is not an
argument that Swag should follow the majority — several entries record a rule Swag shares
with exactly one language and keeps deliberately.
