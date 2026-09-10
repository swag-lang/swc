# Language Backlog

This backlog covers deliberate changes to Swag language semantics and syntax. Comparative
examples describe specific documented alternatives, not an exhaustive ranking of languages.
The compiler that implements it is [compiler.core.md](compiler.core.md).

Compiler defects stay in [compiler.core.md](compiler.core.md). This file keeps deliberate language design,
surprising but specified rules, their comparative evidence, and their next decisions together.

Entries are ordered from the most recently updated down. An entry disappears when it
ships; history lives in git, not here.

### language.design.011 — The apostrophe carries three unrelated roles

- Recorded: 2026-08-07 07:43
- Updated: 2026-09-10 21:00 — recorded the fixed generic-argument coloring regression without claiming a syntax redesign
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
- Next: changing a sigil is expensive. What is worth measuring is
  the cost paid elsewhere: check how the syntax highlighter, the formatter's classifier, and the
  language reference each disambiguate, and whether any of the three gets it wrong. If they all
  carry a copy of the same lookbehind rule, that is the argument for a distinct generic-argument
  spelling.
- Complete when: the lexer, formatter, editor grammar, and reference share one tested
  disambiguation rule, or generic arguments have a distinct spelling migrated across all four.

### language.design.021 — The base a number is written in decides its signedness

- Recorded: 2026-08-10 07:44
- Updated: 2026-09-10 20:58 — removed an already completed reference clarification from the remaining policy work
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
- Next: decide whether the base should pin the sign, or only the width. The cheap experiment is
  to build `swc` with the hex and binary paths using `Sign::Unknown` like the decimal one and run
  the suites: what breaks is the set of places relying on a bare `0x...` being unsigned, and that
  number is the argument either way. If the rule stays, language.design.008's proposed warning at a
  mixed-signedness operator would expose the conversion. The number-literals page already
  documents and tests the distinction between a named constant and a context-adapted bare literal.
- Complete when: the unsigned-literal experiment is measured, base and signedness have one stable
  rule, and literal, operator, and reference tests cover named and context-adapted constants.
- Related: [language.design.008](#languagedesign008--mixing-a-signed-and-an-unsigned-operand-of-the-same-width-converts-the-signed-one)
  is what turns the difference into arithmetic.

### language.design.006 — Positional destructuring binds by position even when every name matches a field

- Recorded: 2026-08-07 07:43
- Updated: 2026-09-10 20:58 — removed an already completed reference clarification from the remaining policy work
- Area: language
- Found while: a reading pass over the whole language reference
- Observation: `let {a, b} = tuple` is positional, and the reference says so
  ([004_003_tuple.swg](../bin/reference/modules/language/src/004_003_tuple.swg)).
  The reference explicitly states that binding names do not select source fields and tests
  a reordered `{y, x}` pattern. The named form (`{y: vertical}`) selects by field name. The
  remaining policy question is whether a field-looking positional pattern that reorders those
  names should also produce a warning; the documentation gap is already closed.
- Evidence: with `let point = {x: 10, y: 20}`, `let {y, x} = point` gives `y == 10` and `x == 20`.
  Confirmed under both the JIT and the forged binary. The same indifference to names governs
  assignment: a `{width, height}` tuple takes a `{x, y}` tuple of the same field types, and
  [004_003_tuple.swg](../bin/reference/modules/language/src/004_003_tuple.swg)
  documents it — "tuples can be assigned to each other if their field types match, even if field
  names differ", with `#typeof(x) != #typeof(y)` asserted on the same page.
- Elsewhere: Rust distinguishes tuple patterns from named-field struct patterns, where a bare field name
  abbreviates a binding to that same field
  ([Rust patterns](https://doc.rust-lang.org/reference/patterns.html#destructuring)).
- Next: decide whether a positional pattern whose every name matches a field of the source —
  in a different order — should be a warning (`sema_warn_positional_pattern_shadows_field`) or an
  error. A warning is enough: the shape is unambiguous to detect, and the fix is one colon per
  binding. It also needs the warning-policy layer that now exists, so it is cheap.
- Complete when: reordered field-looking positional patterns cannot silently bind the wrong fields,
  and the reference and compiler tests show the positional and named spellings side by side.
- Related: the same pattern syntax is what `let {r, g, b} = getWhite()` uses in
  [007_008_retval.swg](../bin/reference/modules/language/src/007_008_retval.swg), where the
  names read as field names and happen to be in order.

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

### language.design.001 — Enum switches are silently non-exhaustive

- Recorded: 2026-08-08 06:23
- Updated: 2026-09-06 07:51 — git: prompt 6
- Evidence: a `switch` over a three-value enum that handles two of them compiles with no error, no warning,
  and no `default`; the third value simply falls through to nothing. Exhaustiveness exists but is
  opt-in through `switch #complete`
  ([005_005_switch.swg](../bin/reference/modules/language/src/005_005_switch.swg)).
- Elsewhere: Swift requires exhaustive switches, including a fallback when the cases do not cover the domain
  ([Swift control flow](https://raw.githubusercontent.com/swiftlang/swift-book/main/TSPL.docc/LanguageGuide/ControlFlow.md)).
- Next: decide whether `#complete` should be the default for enum switches, with an
  explicit `default` arm or another selected opt-out. Measure the compatibility cost and use the
  existing warning-policy layer (`#[Swag.Warning]`, `cfg.warnings`, `--warn-*`) if a staged
  migration is selected.
- Complete when: enum-switch exhaustiveness has one documented default, one explicit opt-out, and
  compiler and reference tests covering a member added after the switch was written.
- Related: compiler.safety.010 owns forged enum values, including fall-through past `switch #complete`
  when the runtime Switch guard is disabled, independently of this default. language.design.002
  owns closed payload-carrying choices; decide their exhaustiveness policy alongside enum switches.

### language.design.002 — There is no tagged union

- Recorded: 2026-08-08 06:23
- Updated: 2026-09-06 07:51 — git: prompt 6
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
- Not a payload-carrying enum. A Swag enum is a table of typed constants (`enum V: string`, `const [..] s32`,
  `.count`, `#[Swag.EnumFlags]`, enum-indexed arrays), and the tag is almost always an existing **public**
  enum that other code stores, compares and serializes (`CommandId`, `OutlineCommandKind`, `MetadataKind`).
  Attaching a payload changes what an enum is, and synthesizing one renames a published API for nothing.
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
  - Default initialization picks the member whose tag value is zero. A tag enum with no zero member has no
    default case, and `#[Swag.EnumFlags]` cannot be a tag at all, since a combination is not a case.
- Migration order once the shape is fixed, cheapest proof first: `editbox`'s bounds (3 POD cases, one file, a
  tag that already exists), then `painter`'s `Command` (the entry's own example, and it exercises `using`),
  then the POD wide structs (`OutlineCommand`, `Regex.Node`, `Regex.Inst`, `HtmlLength`), then the ones whose
  payloads own storage and therefore test the generated lifecycle (`Regex.Prefilter`, `Scc.MetadataValue`,
  `Pdf.Item`). `win32`, `xaudio2` and `Guid128` stay untagged, and the GUI event tree stays an interface
  hierarchy: it is the open choice, which the language already answers.
- Next: decide the declaration shape, the atomic write, and the payload-access rule against the census above,
  then prove them end to end on `editbox`'s bounds before touching `painter`.
- Complete when: the language can declare a closed payload-carrying choice, construct every arm, destructure
  it in a switch, and diagnose a missing or mismatched arm in focused reference tests.
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

### language.design.008 — Mixing a signed and an unsigned operand of the same width converts the signed one

- Recorded: 2026-08-07 07:43
- Updated: 2026-09-06 07:51 — git: prompt 6
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
- Next: the promotion table is a deliberate design choice and should not be re-litigated
  wholesale. What can be decided narrowly is whether a *mixed-signedness* operation, specifically,
  deserves a warning at the operator rather than a panic at the conversion — the operand types are
  known statically, so it costs nothing, and it is the one case where the "no C promotion" rule and
  the "unsigned wins" rule combine into something neither one predicts.
- Complete when: mixed-signedness arithmetic has a recorded policy and its diagnostics, operator
  reference, compile-time behavior, checked-runtime behavior, and release behavior agree.

### language.design.009 — The policy for implicit error propagation remains undecided

- Recorded: 2026-09-06 07:51
- Evidence: a `fail` function may call a fallible function without a written `try`;
  `implicitTryCount` in
  [013_001_error_management.swg](../bin/reference/modules/language/src/013_001_error_management.swg)
  demonstrates and tests the documented behavior. Explicit `try` is also accepted.
- Elsewhere: Swift marks potentially throwing calls with `try`
  ([Swift error handling](https://raw.githubusercontent.com/swiftlang/swift-book/main/TSPL.docc/LanguageGuide/ErrorHandling.md)).
- Next: measure implicit propagation sites under `bin/`, then decide whether the existing choice
  of explicit or implicit propagation should stay or whether each call should require a marker.
- Complete when: the propagation policy is recorded with its migration cost and reference and
  compiler tests agree. The separate test-context alias is owned by language.design.030.

### language.design.030 — Inside `#test`, `try` means `expect`

- Recorded: 2026-08-07 07:43
- Updated: 2026-09-06 07:51 — git: prompt 6
- Evidence: the error-management reference explicitly defines `try` inside `#test` as `expect`.
  Success returns the same value; failure terminates the test instead of propagating to a caller.
  Moving the expression into a fallible helper therefore changes its failure path.
- Elsewhere: Swift distinguishes propagation (`try`) from asserting success (`try!`) in the
  spelling ([Swift error handling](https://raw.githubusercontent.com/swiftlang/swift-book/main/TSPL.docc/LanguageGuide/ErrorHandling.md)).
- Next: count test bodies relying on this alias and decide whether to retain it or migrate them
  to the existing `expect` spelling. This decision can be made independently of implicit propagation.
- Complete when: the chosen test-context rule is documented and focused tests distinguish the
  failure path in a test body from the same call in a fallible helper.
- Related: language.design.009.

### language.design.010 — `catch` without a capture substitutes the type default and says nothing

- Recorded: 2026-08-07 07:43
- Updated: 2026-09-06 07:51 — git: prompt 6
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
- Next: the shape is legitimate and has real uses. What it lacks is the deliberateness the rest
  of the language asks for. Consider making the discarding form its own spelling — `catch discard
  f()`, or requiring the `as err` capture and letting an unread `err` be the thing the warning layer
  reports — so that "I looked at the error and chose to ignore it" and "I did not look" stop reading
  the same.
- Complete when: intentional error discard is either explicit or deliberately retained as implicit,
  and the reference and compiler tests distinguish discard, fallback, capture, and propagation.

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

### language.design.014 — The slice upper bound is inclusive

- Recorded: 2026-08-07 07:43
- Updated: 2026-09-06 07:51 — git: prompt 6
- Area: language
- Found while: the same pass
- Observation: `str[1 to 3]` is three elements, `str[1 until 3]` is two
  ([004_002_slice.swg](../bin/reference/modules/language/src/004_002_slice.swg)).
  Inclusive-by-default is a defensible choice for a *loop*, where `to` reads as "up to and
  including". For a *slice* it makes
  the half-open form — the one that composes, the one whose length is `high - low`, the one that
  handles the empty case without a special rule — the longer word.
- Evidence: `s[1 to 3]` is `"tri"`, `s[1 until 3]` is `"tr"`. The empty and inverted cases then need
  their own paragraph and their own runtime guard
  ([004_002_slice.swg](../bin/reference/modules/language/src/004_002_slice.swg)),
  which remain necessary for inverted or out-of-bounds half-open ranges too. Equal half-open
  bounds are the empty case and already have reference tests.
- Elsewhere: Rust provides both half-open and inclusive ranges with distinct operators
  ([Rust range expressions](https://doc.rust-lang.org/reference/expressions/range-expr.html)).
  Swag also exposes both choices, using words rather than punctuation.
- Next: not a change to make — both spellings exist and the inclusive one is the shorter word
  by design. What is worth doing is measuring: count `to` versus `until` in slice position across
  `bin/`, and check whether the off-by-one it invites shows up in the test corpus. That number
  decides whether this is a wart or a trap.
- Complete when: slice-form usage and off-by-one failures are measured, the inclusive default is
  retained or changed explicitly, and the reference tests define empty and inverted ranges.

### language.design.015 — `#[Swag.EnumFlags]` changes implicitly assigned member values

- Recorded: 2026-08-07 07:43
- Updated: 2026-09-06 07:51 — git: prompt 6
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
- Next: measure public and persisted enums whose members omit explicit values. Decide whether
  API or serialization tooling should require explicit numeric assignments there. Requiring only
  a first `None = 0` member would document the empty set but would not preserve subsequent values;
  checking whether an attribute was added also requires a previous API baseline, not one compile.
- Complete when: applying `Swag.EnumFlags` cannot accidentally renumber a persisted or public enum,
  or that behavior requires an explicit opt-in protected by compiler and reference tests.

### language.design.017 — Mixins resolve their body in the caller's scope

- Recorded: 2026-08-07 07:43
- Updated: 2026-09-06 07:51 — git: prompt 6
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
- Next: check how many mixins under `bin/` actually rely on free identifiers rather than on
  parameters and `#code` blocks. If the number is small, the interesting question is whether the
  free-identifier form still earns its keep now that `#code(...)` block parameters exist — they
  cover the same ground with a declared contract.
- Complete when: free-identifier mixin usage is quantified and mixin name resolution has one
  documented contract, with hygiene or deliberate capture protected by declaration- and call-site
  tests.
- Related: `#uniq0`..`#uniq9` exist precisely to work around the collisions this creates, and there
  are exactly ten of them.

### language.design.018 — A macro can redefine `break` and `continue` inside the block the caller wrote

- Recorded: 2026-08-07 07:43
- Updated: 2026-09-06 07:51 — git: prompt 6
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
- Next: the capacity is what makes `opVisit` work at all and should not be removed. What is
  missing is disclosure: consider requiring the block literal to acknowledge it
  (`#code(break, continue) { ... }`, the same shape the call site already uses to rename block
  parameters), so a reader of the call site knows the keywords are not the ones they look like.
- Complete when: every block whose control-flow keywords can be remapped discloses that contract at
  its call site, and macro, compiler, and reference tests make the selected targets observable.

### language.design.019 — `if let` combines binding with an implicit truthiness test

- Recorded: 2026-08-07 07:43
- Updated: 2026-09-06 07:51 — git: prompt 6
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
- Next: decide whether the implicit truthiness test should be restricted to nullable-capable
  types, where "did I get something" is the intended reading and `?` already marks it in the
  type. On a plain `s32` the same line silently means "is it non-zero", which the ternary already
  spells out — and the reference makes that exact argument when it explains why `orelse` refuses a
  non-nullable operand
  ([003_006_operators.swg](../bin/reference/modules/language/src/003_006_operators.swg)).
- Complete when: the truthiness domain of `if let` is documented and compiler tests cover zero,
  null, nullable values, and `where` short-circuiting under the chosen rule.

### language.design.020 — There are two metaprogramming systems and they do not meet

- Recorded: 2026-08-07 07:43
- Updated: 2026-09-06 07:51 — git: prompt 6
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
- Next: no rewrite is proposed. The narrow, useful step is to find out what `#ast` is actually
  used for across `bin/` — if it is overwhelmingly "one field per reflected field", that shape
  deserves a declarative spelling, and the string escape hatch can stay for everything else.
- Complete when: `#ast` usage is classified by generated declaration shape and recurring shapes
  have either a typed generation path or a recorded reason to remain source strings.

### language.design.023 — A blank `cast()` performs whatever conversion the target turns out to need

- Recorded: 2026-08-10 07:44
- Updated: 2026-09-06 07:51 — git: prompt 6
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
- Next: count the `cast()` uses in `bin/` and sort them by what the conversion turned out to
  be. If they are overwhelmingly widening or same-kind, the narrow rule worth proposing is that a
  blank `cast()` performs only the conversions that would have been implicit anyway plus the
  same-kind narrowing, and that a float-to-integer truncation needs its type written. That keeps the
  convenience where it is a convenience and removes it where it is a silent behaviour change.
- Complete when: blank-cast usage is classified by conversion kind and the permitted target-inferred
  conversions are documented and tested, especially float-to-integer and narrowing cases.

### language.design.024 — Implicit copies into `#move` parameters have no dedicated warning

- Recorded: 2026-08-10 07:44
- Updated: 2026-09-06 07:51 — git: prompt 6
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
- Next: decide whether the copy should be reportable rather than whether it should exist.
  The call site already distinguishes the two forms syntactically, so a warning at a plain argument
  passed to a `#move` parameter of a type with `opPostCopy` could identify the copy. Adding `#move`
  transfers ownership and is not a behavior-preserving automatic fix. Check whether `bin/` relies
  on the copy path through lambdas and
  interface methods, where the reference says a single `#move` function is what makes both styles
  work at all — those call sites are the ones a warning must not drown.
- Complete when: the copy-reporting policy is recorded after a usage census, and any selected warning
  distinguishes intentional copy calls from transfers. Existing copy policy and tests, including
  [move_copy_to_move.swg](../bin/unittests/native/operators/move_copy_to_move.swg), already cover
  plain and moved arguments; non-copyable values are rejected by `Cast::castToReference`.

### language.design.025 — A `catch ... as err` capture is a declaration that leaks into the enclosing scope

- Recorded: 2026-08-10 07:44
- Updated: 2026-09-06 07:51 — git: prompt 6
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
- Next: this is worth settling together with language.design.010, since both are about what happens to a
  caught error nobody looked at. Count cross-statement reads and captures used by deferred code,
  then compare the current enclosing-block scope with an explicit declaration or handler scope.
  Define the migration against those uses; narrowing a capture's lifetime is not automatically
  behavior-preserving.
- Complete when: cross-statement catch-capture usage is counted and one scope rule is documented,
  migrated where necessary, and protected by reference and compiler tests.
- Related: [language.design.010](#languagedesign010--catch-without-a-capture-substitutes-the-type-default-and-says-nothing)

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

### language.design.028 — A moved value cannot initialize an aggregate literal field or a conditional branch

- Recorded: 2026-08-17 09:09
- Updated: 2026-09-06 07:51 — git: prompt 6
- Area: language
- Found while: fixing a case where those two expressions asserted in code generation instead of
  being diagnosed
- Observation: `blocks.add(Block{kind, #move text})` and
  `var value = condition ? String.from("rule") : #move block.text` now report a clear error
  rather than crashing the compiler, but both read like ordinary Swag and the language has no
  short expression spelling for what they mean. Statement-level destination initialization and
  field assignment already express the transfer; they do not always require an extra source temporary.
- Evidence: `SemaCheck::noMoveRefType` rejects move references in aggregate fields, array elements
  and conditional branches. Declaration/assignment transfer, `#move` parameters, and explicit
  moves into by-value call parameters already work. The existing error suite
  [sema_err_move_ref_type_context.swg](../bin/unittests/errors/sema/sema_err_move_ref_type_context.swg)
  covers both conditional arms, a struct field and an array element. The remaining proposal is
  expression placement, not general move support.
- Elsewhere: Rust may move a non-`Copy` value into an aggregate or another value context
  ([Rust moved values](https://doc.rust-lang.org/reference/expressions.html#moved-and-copied-types)).
  This is an alternative placement contract, not a claim that Swag only permits moves in calls.
- Next: decide whether a literal field and a conditional branch should move-construct their
  destination. The rule is not the obstacle, the lowering is: an aggregate literal is materialized
  as one value through `emitAggregateLiteralPayload`, so a moved field needs its own store plus
  the source's post-move invalidation instead of that path.
- Complete when: the language deliberately accepts or retains rejection of move expressions in these
  value positions. An accepting design must specify per-field lifecycle, source reset, evaluation
  order, partial initialization and branch-dependent ownership, with focused code-generation tests.

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

### language.design.022 — The cost of value-dependent float inference is unmeasured

- Recorded: 2026-08-10 07:44
- Updated: 2026-09-05 16:27 — git: Add unit tests for TaskProvider in providers.test.js
- Evidence: `ApFloat::minBits` and scalar concretization select `f32` when the parsed value fits
  without further rounding, otherwise `f64`. The number-literals reference now states that rule
  and tests `1.5`, `0.1`, `16777216.0`, `16777217.0` and an explicitly rounded `f32`.
- Next: classify inferred floating-point locals under `bin/` by their resulting width and by
  whether the width is deliberate. Use that census to decide whether value-dependent inference
  needs additional discovery or a different default; keep explicit suffixes and annotations as
  the stable way to state the desired width.
- Complete when: the census supports a recorded inference-policy decision and the reference and
  compiler tests agree with it. The documentation correction itself is complete.

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
