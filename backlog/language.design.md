# Language Backlog

This backlog covers deliberate changes to Swag language semantics and syntax. Comparative
examples describe specific documented alternatives, not an exhaustive ranking of languages.
The compiler that implements it is [compiler.core.md](compiler.core.md).

Compiler defects stay in [compiler.core.md](compiler.core.md). This file keeps deliberate language design,
surprising but specified rules, their comparative evidence, and their next decisions together.


The design pass distinguishes missing capabilities from changes to an existing policy.
The following are already available and are not new feature requests:

- Non-null required fields and definite initialization, including rejection of incomplete
  aggregates: [the initialization fixture](../bin/unittests/errors/sema/sema_err_type_requires_init.swg).
  The remaining construction obstacle is moved-source reset (language.design.035), not the absence
  of constructors or safe initialization. `expect` accepts results without a default value.
- Aggregate literals and a local that every return in its scope returns construct directly in
  the return slot, and other eligible named-local returns transfer ownership. See
  [return storage](../bin/reference/modules/language/src/007_008_returntype.swg) and
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
belong to compiler.language.service.008 in [compiler.language.service.md](compiler.language.service.md), rather than the formatter.
Public API consistency remains a module-by-module design requirement under
[design-swag-bin-modules](../.agents/skills/design-swag-bin-modules/SKILL.md): value returns,
options structs, slices and ownership contracts are available today. A concrete API defect belongs
in its module backlog; a general request for better names is not a missing language feature.

### language.design.038 — Flag side effects inside a disabled-by-configuration assertion

- Evidence: release disables `.Assert` outside `swc test`, so an assertion's argument is not
  evaluated there. `Swag.assert(re.match(l[]))` in `bin/examples/modules/aoc2017` silently
  skipped its regex in release (fixed in f995a79ae), and nothing diagnosed the dependence on
  the argument's effect.
- Proposed contract: diagnose an assertion argument that calls a non-`const` method, assigns,
  or otherwise writes observable state. Decide whether it is a warning in the warning-policy
  layer or an error, and whether const receivers are enough to mark calls that are safe to
  elide.
- Next: add an `errors/sema` case for a mutating call inside `Swag.assert`, measure how many
  existing assertions in `bin/` the rule would flag, and pick the severity from that count.
- Done when: a mutating call inside an assertion argument is diagnosed and `bin/` is clean.

### language.design.032 — Produce values directly from a switch

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
  language.design.001; use the terminal failure contract of `expect` for non-returning arms.
- Done when: a local initializer and a function return can use a total multi-arm expression
  without a mutable relay; JIT/native tests cover type inference, evaluation order, cleanup and
  borrowed-result escapes, and the formatter/reference/editor agree on the chosen syntax.
- Related: language.design.001, language.design.002.

### language.design.035 — Move a non-defaultable owner without resetting its consumed source

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
- Done when: a valid non-defaultable owner can be transferred without a dummy default,
  consumed storage cannot be read/dropped twice, and failures/branch merges preserve ownership.
- Related: language.design.024 owns implicit copies at consuming boundaries. `expect` already
  accepts non-defaultable results; this entry concerns resetting consumed sources.


### language.design.033 — Choose one canonical instance-method declaration

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
- Done when: one receiver grammar is selected and applied across compiler/reference/editor
  and bin/ without a permanent synonym, or a measured comparison rejects the simplification and
  this entry is removed rather than left as an indefinite style preference.

### language.design.034 — Make custom iteration independent of manual control-flow injection

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
- Done when: a custom collection needs no manual loop-keyword remapping, the existing
  consumer loop forms still behave correctly, and owning/borrowed/fallible providers have a
  tested lifetime and cost contract with a migration path for opVisit.
- Related: language.design.018; compiler.safety.014 in [compiler.safety.md](compiler.safety.md).


### language.design.001 — Enum switches are silently non-exhaustive

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
- Done when: adding a closed enum member exposes incomplete consumers, deliberate partial handling
  remains explicit, and guarded, aliased, flags, and open-type switches have executable rules.
- Related: compiler.safety.010 owns forged enum values, including fall-through past `switch #complete`
  when the runtime Switch guard is disabled, independently of this default. language.design.002
  owns closed payload-carrying choices; decide their exhaustiveness policy alongside enum switches.

### language.design.002 — Describe a tagged union's tag in reflection

- Evidence: tagged unions ship ([004_006_union.swg](../bin/reference/modules/language/src/004_006_union.swg)):
  `union(Kind)` and `union Name(Kind)` with case-labelled members, `.Case`/`.Case{...}`
  construction, `switch`, `is`, `Swag.kindOf`, flow proofs and the postfix `!`, and lifecycle and
  equality dispatched on the tag. `EditBox`, `Pixel.Command` and `TrueType.OutlineCommand` use
  them. Reflection does not know them: `TypeInfoStruct` lists the members at their payload offset
  and says nothing about the tag, so a reflection-driven serializer writes every member and cannot
  restore which one is active.
- Consequence: `Scc.MetadataValue` stays a wide struct, because the SCC header is TagBin-encoded
  through reflection ([scc.swg](../bin/std/modules/core/src/filesystem/scc.swg)).
- Proposed contract: a tagged union's type info publishes its tag type and, for each member, the
  tag values that select it. TagBin writes the tag and only the active member, and refuses on
  decode a tag that no value of the tag type names.
- Decisions: where the case sets live in `TypeInfoStruct` and its C++ mirror, and how the runtime
  cache identity moves with that layout; whether TagBin's wire format grows a tagged-union record
  or writes the tag as an ordinary enum field. Separately, whether `?.` should also skip a payload
  access when another case is active; `if u is .Case` covers that need today.
- Next: add the tag type and per-member case sets to `TypeInfoStruct`, then teach the TagBin
  encoder and decoder to write the tag and the active member, and migrate `Scc.MetadataValue`.
- Done when: a tagged union round-trips through TagBin with only its active member, a forged tag
  is rejected on decode, and `Scc.MetadataValue` is a tagged union.
- Related: language.design.001 — a switch over a tagged union has a closed domain, which is the
  strongest case for default exhaustiveness; decide both together. language.design.039,
  compiler.safety.033, std.gui.pdf.043, std.core.036. compiler.safety.010 owns forged tags coming
  from `Swag.memcpy`, `#relocate`, a binary read or a `#[Foreign]` call: the `!` check and the
  Switch guard catch them only when safety is enabled.

### language.design.039 — Pass a tagged-union case as a call argument

- Evidence: `f(.Circle{radius: 2})` does not resolve. A call argument has no binding type before
  overload resolution, and the deferred resolution of leading-dot arguments (`probeAutoEnumArg` in
  [Match.Func.cpp](../src/Compiler/Sema/Match/Match.Func.cpp)) only knows payload-less enum values.
  This is why `Painter.newCommand` returns a slot the caller then assigns:
  `.newCommand(.Clear).op = .Clear{color}`
  ([painter.swg](../bin/std/modules/pixel/src/painter/painter.swg)).
- Proposed contract: once the overload is selected, a leading-dot argument whose parameter is a
  tagged union names a case of it, with or without braces, exactly as in a typed initializer.
- Next: resolve `.Case` and `.Case{...}` arguments against a tagged-union parameter in the
  deferred argument pass, then let `Painter.newCommand` take its case.
- Done when: a case reaches a tagged-union parameter in a direct, a method and a UFCS call, and
  `Painter.newCommand` takes the case it records.

### language.design.008 — Mixing a signed and an unsigned operand of the same width converts the signed one

- Evidence: when two integer operands have the same width and differ in signedness, "the
  unsigned type wins"
  ([003_006_operators.swg](../bin/reference/modules/language/src/003_006_operators.swg)).
  Because Swag deliberately does *not* promote 8- and 16-bit operands to 32 bits the way C does,
  that rule has no wider type to escape into: `s8 + u8` is computed in `u8`, so a negative
  signed operand first converts to an unsigned value before addition. The expression includes a guarded
  conversion, and the guard is a `release`-time no-op.
- Evidence: a constant `-1's8 + 1'u8` is rejected at compile time ("cannot cast '-1' to 'u8' …
  value is negative, but the target type is unsigned"). The same expression through runtime
  variables panics with "integer overflow" in `devmode` — and in `release`, where the overflow
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
- Done when: one promotion/comparison table is selected and tested at constant, JIT, guarded native
  and release boundaries, without configuration-dependent changes to signedness meaning.

### language.design.019 — `if let` combines binding with an implicit truthiness test

- Evidence: the declaration in an `if` is converted to a boolean — non-zero, non-null — and the
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
- Done when: bindings distinguish absence from zero/false/empty payloads, evaluate once, scope names
  to successful branches, and preserve those rules through guards and nested patterns.

### language.design.023 — A contextual `cast(value)` performs whatever conversion the target turns out to need

- Evidence: `cast(value)` with no type "allows the compiler to infer the target type"
  ([003_007_cast.swg](../bin/reference/modules/language/src/003_007_cast.swg)), and
  the conversion it then performs is whichever one that target requires — including a float
  truncation and an integer narrowing, in a language that otherwise refuses both without a written
  cast. The spelling is a blanket permission attached to a call site rather than to a conversion:
  it says "convert this", never "convert this to that", so changing a parameter's type at the callee
  silently changes what every `cast(value)` argument does. The reference's own example is a truncation
  presented as a convenience.
- Evidence: `testAutoCast(cast(1.4))` is the reference's illustration, and `1.4` arrives as `1`. An
  isolated probe, `swc test -d <dir>`: one source expression, two targets, two different silent
  conversions.

  ```swag
  func takeS32(value: s32)->s32 => value
  func takeU8(value: u8)->u8 => value
  Swag.print(takeS32(cast(1.9)), " ", takeU8(cast(1.9)))     // 1 1
  ```

- Elsewhere: Zig names conversion categories separately, including `@intCast` and `@truncate`, while
  inferring destinations from context
  ([Zig language reference](https://ziglang.org/documentation/master/#intCast)).
  Target inference and the permitted conversion category are independent choices.
- Proposed contract: Keep existing cast #bit, dynamic try/expect/assume cast, and type patterns distinct from
  numeric conversion. The gap is target-inferred numeric permission: checked narrowing, fractional
  truncation and saturation must not become interchangeable when a callee changes type. Infer
  the target only after fixing the conversion category; remove conversions that are lossless
  and already implicit.
- Next: Classify blank numeric casts and compare explicit operations or modifiers for checked
  narrowing, truncation and saturation. Reuse existing bit reinterpretation. Specify NaN,
  infinity, negative-to-unsigned, boundary overflow and whether failure is recoverable; these
  semantics must remain defined when optional safety guards are disabled.
- Done when: numeric conversion categories and failure policies are explicit and tested, target
  inference cannot silently choose another category, and no existing dynamic/bit cast is duplicated.

### language.design.011 — The apostrophe carries three unrelated roles

- Evidence: `'` opens a character literal, introduces a literal suffix, and introduces a generic
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
- Proposed contract: Use one delimited generic-argument form distinguishable from character literals and
  numeric/unit suffixes. This is a readability/syntax proposal, not a missing generics feature or
  an unresolved coloring bug. Compare angle brackets with another dedicated delimiter rather
  than assuming familiar punctuation has no parse cost.
- Next: Translate Array'u8, HashTable'(K, V), genericTwice's64(12), and value arguments such as
  at'1() into each candidate. Test nesting, comparisons/shifts next to generic calls, inferred
  arguments, formatting and incomplete editor input. Select one spelling and an AST-based
  migration; literal suffixes and character literals must retain an independent grammar.
- Done when: one generic syntax is chosen from a measured corpus and parser, formatter, reference and
  editor grammar agree, including value arguments and incomplete code; no competing alias remains.

### language.design.021 — The base a number is written in decides its signedness

- Evidence: a decimal literal is an unsized constant of *unknown* sign, and a hexadecimal or
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
  literal's default. The reference's operators page writes `x = x | cast(s32, 0b0001)`
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
- Done when: equal unsuffixed values share a base-independent default policy, explicit suffixes stay
  stable, and named constants, bare contextual literals, masks and boundary values are tested.
- Related: [language.design.008](#languagedesign008--mixing-a-signed-and-an-unsigned-operand-of-the-same-width-converts-the-signed-one)
  is what turns the difference into arithmetic.

### language.design.014 — Choose a consistent half-open convention for collection APIs

- Evidence: `str[1 to 3]` is three elements, `str[1 until 3]` is two
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
- Done when: the collection convention is documented and represented consistently in examples and
  APIs, with empty, adjacent, inverted and maximum-endpoint cases covered using existing syntax.

### language.design.015 — `#[Swag.EnumFlags]` changes implicitly assigned member values

- Evidence: adding the attribute changes `A` from 0 to 1, `B` from 1 to 2, `C` from 2 to 4
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
- Done when: the selected declaration and representation contract is documented and migrated, and
  tests cover empty sets, combinations, reflection, serialization and public numeric stability.

### language.design.017 — Mixins resolve their body in the caller's scope

- Evidence: a mixin body names variables that do not exist where it is written and are expected
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
- Done when: a mixin cannot silently depend on an unrelated caller identifier, intentional captures
  are declared, and definition/call-site diagnostics preserve useful expansion provenance.
- Related: `#uniq0`..`#uniq9` exist precisely to work around the collisions this creates, and there
  are exactly ten of them.

### language.design.018 — A macro can redefine `break` and `continue` inside the block the caller wrote

- Evidence: `#inject(what, break = break to Outer, continue = break)` rewrites the meaning of
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
- Done when: callers can identify any nonlexical control-flow interception, ordinary iteration needs
  no hand-authored remapping, and regression tests observe the exact exit and cleanup targets.

### language.design.020 — There are two metaprogramming systems and they do not meet

- Evidence: `#ast` generates code by returning a *string* of Swag source, built with `+` or a
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
- Done when: the reflected-field transformation uses checked declarations, errors identify both the
  generator and source member, and the implementation does not add a competing macro language.

### language.design.024 — Make nontrivial copies explicit at owning call boundaries

- Evidence: a `#move` parameter also accepts a plain copyable argument. The compiler copies it
  into a call-site temporary (`opPostCopy`) and moves that temporary. With `Vector3`, the call
  `assign(&b, a)` through a `#move` parameter yields `4, 5, 6` (one copy, then one move), and
  `assign(&b, #move a)` yields `3, 4, 5`
  ([006_009_custom_copy_and_move.swg](../bin/reference/modules/language/src/006_009_custom_copy_and_move.swg)).
  Nothing at the call site marks which call paid for the copy. `#copy value` now exists as
  an explicit copy expression, and `#fwd` avoids the temporary.
- Elsewhere: Rust copies values implementing `Copy` and otherwise moves them in value contexts
  ([Rust moved and copied values](https://doc.rust-lang.org/reference/expressions.html#moved-and-copied-types)).
- Proposed contract: make nontrivial duplication explicit at owning boundaries. Preserve what
  already holds: an opDrop type without opPostCopy is not copyable, by-value struct
  parameters borrow a const address, and unobserved named-local returns transfer. The open
  question is the implicit opPostCopy for an unmarked argument to a consuming parameter.
- Next: decide whether an unmarked copyable argument to a `#move` parameter, an owning
  assignment, or an initialization must be written `#copy`, against default transfer. Use
  String, Array and a copy-counting fixture, and include callbacks, interfaces and deferred
  observations. Measure the `bin/` migration, and never auto-insert `#move` to silence a
  diagnostic. Non-defaultable source reset is language.design.035.
- Done when: the selected owning-call contract exposes every nontrivial duplication and
  intentional transfer, without making ordinary borrowed struct calls consume or allocate.

### language.design.022 — The cost of value-dependent float inference is unmeasured

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
- Done when: the default no longer depends on the literal's exact representability, its cost and
  migration are recorded, and contextual/suffixed/defaulted literals have executable rules.

### language.design.027 — Loop index types follow different count, range, and collection rules

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
- Done when: a measured policy decision retains or changes these rules and compiler and
  reference tests cover each selected boundary.
- Related: language.design.008.

### language.design.007 — One default in a grouped declaration silently defaults every name in the group

- Evidence: `x, y: s32 = 0` declares two parameters and gives *both* the default `0`. The
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
- Done when: grouped defaults have a measured compatibility cost and one documented rule, with
  reference and compiler tests covering named calls that omit each member of the group.

### language.design.013 — A `switch` accepts several `default` clauses

- Evidence: a `default` can carry a `where`, and once it can, a switch can hold several of them
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
- Done when: a switch has one unmistakable fallback form, guarded fallback usage has been
  measured and migrated or retained deliberately, and duplicate-arm tests protect the rule.

### language.design.026 — `[2, 2] T` and `[2][2] T` are different types indexed the same way

- Evidence: the two spellings produce unrelated types that do not convert to each other, and the
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
- Done when: both multidimensional-array forms are measured in implementation and public APIs,
  and their compatibility or intentionally distinct use-site contract is documented and enforced.

### language.design.029 — '.buffer' answers a non-null pointer for a payload that can be absent

- Evidence: `.buffer` of a `string` or `cstring` carries the source's `?`, but the `any` and
  `interface` cases answer a non-null block pointer whatever the payload is.
  `semaIntrinsicDataOf` ([Sema.Intrinsic.cpp](../src/Compiler/Sema/Ast/Sema.Intrinsic.cpp))
  builds them with `TypeInfo::makeBlockPointer(typeVoid(), flags)`, where `flags` come from
  the container. A non-null `any` built by `Swag.makeAny(null, type)`, or an interface whose
  `obj` was never set, both hand back null. `encoder.swg` and `decoder.swg` test the raw
  `itf.obj` field because `.buffer` cannot ask, and `convertAny` reads its `any` through
  `[as any?]`. A raw inventory finds about 4,000 `.buffer` occurrences under `bin/`. That is
  an upper bound, because receiver types are not yet classified.
- Elsewhere: Rust represents an optional borrowed reference with `Option<&T>`
  ([Rust Option](https://doc.rust-lang.org/std/option/)).
- Next: decide whether the `any` and `interface` payload pointers are always
  nullable-capable, as the runtime behaves, or whether a non-null `any` should promise a
  payload, so that `Swag.makeAny(null, type)` needs `?`. Classify the inventory by receiver
  type before estimating the migration.
- Done when: `.buffer` uses are classified by receiver type, the payload-pointer nullability
  contract is documented, and the resulting migration plus compiler and module tests agree.

### language.design.040 — An empty slice cannot be written where a slice type is named

- Evidence: with `func f(path: const [..] string = ...)`, neither `[]` nor `{}` nor `null` is
  accepted as the default, and a call `f([])` is rejected with "array literal has no element to
  infer from; provide explicit type context elsewhere" although the parameter names the type. The
  option-sheet golden helper in `bin/std/modules/gui/src/tests/optionsheet.test.swg` had to take two
  optional labels instead of one path slice.
- Next: decide the spelling of the empty slice (`[]` typed by its destination, like a brace literal
  typed by its target struct), accept it for parameters, defaults, returns and typed
  declarations, and add sema fixtures for each position.
- Done when: `f([])` and `path: const [..] string = []` compile wherever the destination names a
  slice type, and the diagnostic only fires where nothing names one.

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
