# Swag AI-First Migration

Swag targets AI agents as primary authors and maintainers. The migration should make a
compiling patch more likely to satisfy the task, make semantic changes visible, and shorten
the path from a concrete failure to a verified repair. The compiler's plain-text reports
carry the evidence for these tasks.

Start with runtime fault parity (`compiler.ai.035`), semantic queries (`compiler.ai.037`), and
reproducible tests with observed values (`compiler.ai.040`, `compiler.ai.041`). Use the
behavioral benchmark in `compiler.ai.059` to decide the order of compatibility-heavy changes.
[README.md](README.md) defines entry and completion rules.

### compiler.ai.004 — A scalar `is/as` binding reads like a value but binds a pointer

- Evidence: the language reference writes `if value is s32 as number where number[] > 0 do`
  ([005_001_if.swg](../bin/reference/modules/language/src/005_001_if.swg)). The name `number`
  suggests an `s32`, yet the binding has pointer type and needs `[]` even for a comparison.
- Elsewhere: Rust identifier patterns copy or move a matched value by default; `ref` requests a
  borrow explicitly ([Rust patterns](https://doc.rust-lang.org/reference/patterns.html#identifier-patterns)).
- Next: decide whether scalar `is/as` bindings should copy the value while aggregate bindings
  keep borrowing, and how a caller requests a mutable view. Check `where` guards, `const any`
  sources, and pointer-valued payloads before choosing syntax.
- Done when: the binding type and mutation rules are explicit in the reference and JIT/native tests,
  and the example can compare a scalar without an unexplained dereference.

### compiler.ai.005 — Mixing a signed and an unsigned operand of the same width converts the signed one

- Evidence: when two integer operands have the same width and differ in signedness, "the
  unsigned type wins"
  ([003_006_operators.swg](../bin/reference/modules/language/src/003_006_operators.swg)).
  Because Swag deliberately does *not* promote 8- and 16-bit operands to 32 bits the way C does,
  that rule has no wider type to escape into: `s8 + u8` is computed in `u8`, so a negative
  signed operand first converts to an unsigned value before addition. The expression includes a guarded
  conversion, and the guard is a `release`-time no-op.
- Evidence: a constant `-1's8 + 1'u8` is rejected at compile time ("cannot cast '-1' to 'u8' …
  value is negative, but the target type is unsigned"). The same expression through runtime
  variables panics in `devmode`. A runtime `s8` value of −2 plus a `u8` value of 1 instead
  yields 255 in `release`, where the conversion guard is off.
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
  compiler.ai.006 and language.design.022.
- Done when: one promotion/comparison table is selected and tested at constant, JIT, guarded native
  and release boundaries, without configuration-dependent changes to signedness meaning.

### compiler.ai.006 — The base a number is written in decides its signedness

- Evidence: a decimal literal is an unsized constant of *unknown* sign, and a hexadecimal or
  binary one is an unsized constant of *unsigned* sign. Both adapt to an imposed type, so the
  difference is invisible wherever the target is written down — and it becomes the constant's real
  type the moment nobody writes one. `const Mask = 0xF0` is a `u32`, `const Mask = 240` is an `s32`,
  and from there the difference travels into every expression the constant enters, where compiler.ai.005's
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
  maximum, including bit masks and enum values. Coordinate with compiler.ai.005 so changing
  the default does not merely move a surprising promotion to a different boundary.
- Done when: equal unsuffixed values share a base-independent default policy, explicit suffixes stay
  stable, and named constants, bare contextual literals, masks and boundary values are tested.
- Related: [compiler.ai.005](compiler.ai.md#compilerai005--mixing-a-signed-and-an-unsigned-operand-of-the-same-width-converts-the-signed-one)
  is what turns the difference into arithmetic.

### compiler.ai.008 — Flag side effects inside a disabled-by-configuration assertion

- Evidence: release disables `.Assert` outside `swc test`, so an assertion's argument is not
  evaluated there. `Swag.assert(re.match(l[]))` in `bin/examples/modules/aoc2017` silently
  skipped its regex in release (fixed in f995a79ae), and nothing diagnosed the dependence on
  the argument's effect.
- Proposed contract: diagnose an assertion argument that calls a non-`const` method, assigns,
  or otherwise writes observable state. Reject provable observable effects, including writes through aliases and transitive
  callees. Treat a non-const receiver as a lead for effect analysis rather than proof of a write.
- Next: add an `errors/sema` case for a call with an observable effect inside `Swag.assert`, measure how many
  existing assertions in `bin/` the rule would flag, and pick the severity from that count.
- Done when: a call with proven observable effects in an assertion operand is rejected and `bin/`
  is clean.

### compiler.ai.009 — Start new projects with guards and test the shipped configuration

- Evidence: `release-safe` already enables runtime guards with release optimization. A
  `release` test enables `.Assert` by default even though a `release` program normally
  disables it. [The effective safety mask](../src/Compiler/Sema/Core/Sema.cpp#L34) changes with
  the command.
- Next: make `release-safe` the default for new script and module starters. Add a native
  delivery check that can run targeted tests with the actual shipped safety and optimization
  settings, including assertion elision when the application ships that way. Keep test verdicts
  on `Swag.require` and `Swag.check` and report the effective artifact settings.
- Done when: a new project starts guarded, the delivery check detects regressions hidden by
  a guard present only in tests, and explicit preset choices retain their defined behavior.
- Related: compiler.ai.008, compiler.ai.053.

### compiler.ai.010 — Require a qualifier when a leading dot can rebind

- Evidence: the [leading-dot rules](../bin/reference/modules/language/src/011_005_leading_dot.swg)
  combine the contextually expected type, the innermost `with` target and the receiver. Two
  different members can share the spelling and the type, so an edit can change the binding
  without breaking type checking.
- Next: detect competing bindings on source in `bin/`. Keep type-directed shorthand in
  unambiguous positions. Diagnose collisions with both targets and their explicit qualifications,
  then migrate existing calls without changing which member they select.
- Done when: a newly competing receiver, `with` target or contextual type asks for a qualifier
  instead of silently rebinding an existing access.
- Related: compiler.ai.011, compiler.ai.037, compiler.ai.038.

### compiler.ai.011 — Keep a receiver method call in the receiver's overload family

- Evidence: [call resolution](../src/Compiler/Sema/Match/Match.Func.cpp#L2450) can select a
  free function from a lower-priority scope when its conversion ranks higher. An import can
  therefore change the target of an untouched dot call.
- Next: compare the current rule with a receiver-first rule on existing method and UFCS
  calls. Reserve `value.method(...)` for the receiver's method family when that family
  exists. Keep UFCS for names without a receiver method and allow qualified calls to a free
  function. Produce a checked migration for calls whose target would change.
- Done when: introducing a free function or import cannot redirect an existing receiver-method
  call, and a caller can still choose the free function explicitly.
- Related: compiler.ai.010, compiler.ai.030, compiler.ai.038.

### compiler.ai.012 — Choose a consistent half-open convention for collection APIs

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
  Pass an exclusive end to custom `opSlice` implementations so empty slices are representable.
  Do not mechanically replace to: converting an inclusive last index to an exclusive endpoint
  can overflow at the maximum integer. Change grammar only if this audit finds a real gap.
- Done when: the collection convention is documented and represented consistently in examples and
  APIs, with empty, adjacent, inverted and maximum-endpoint cases covered using existing syntax.

### compiler.ai.014 — Make units checkable at standard-library boundaries

- Evidence: [string count and indexing](../bin/reference/modules/language/src/003_003_string.swg)
  use bytes, while [UTF-8 operations](../bin/std/modules/core/src/text/utf8.swg) also use rune
  indices. Equal integer types allow those units to be swapped. Similar pairs appear in time
  and geometry APIs.
- Next: start with byte offsets and rune indices. Use existing `Swag.Strict` aliases or
  domain types at public boundaries where interchanging the values would be a bug. Use
  unit-specific names and the existing types such as `Time.Duration` where they already fit.
  Migrate real callers and provide explicit conversions at mixed-unit boundaries.
- Done when: passing a rune index to a byte-offset operation is diagnosed and common callers
  can obtain and combine the right quantities without generic casts.
- Related: compiler.ai.012.

### compiler.ai.015 — Produce values directly from a switch

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
  and source lifetime before migrating real helpers. Reuse the statement switch coverage rules
  and the terminal failure contract of `expect` for non-returning arms.
- Done when: a local initializer and a function return can use a total multi-arm expression
  without a mutable relay; JIT/native tests cover type inference, evaluation order, cleanup and
  borrowed-result escapes, and the formatter/reference/editor agree on the chosen syntax.
- Related: compiler.ai.016.

### compiler.ai.016 — Describe a tagged union's tag in reflection

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
- Related: compiler.ai.017, std.gui.pdf.043, std.core.036. compiler.safety.010 owns forged tags coming
  from `Swag.memcpy`, `#relocate`, a binary read or a `#[Foreign]` call: the `!` check and the
  Switch guard catch them only when safety is enabled.

### compiler.ai.017 — Pass a tagged-union case as a call argument

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

### compiler.ai.018 — Move a non-defaultable owner without resetting its consumed source

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
- Related: compiler.ai.019 owns implicit copies at consuming boundaries. `expect` already
  accepts non-defaultable results; this entry concerns resetting consumed sources.

### compiler.ai.019 — Make nontrivial copies explicit at owning call boundaries

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
  diagnostic. Non-defaultable source reset is compiler.ai.018.
- Done when: the selected owning-call contract exposes every nontrivial duplication and
  intentional transfer, without making ordinary borrowed struct calls consume or allocate.

### compiler.ai.020 — Raw memory operations have no common unsafe opt-in

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
- Related: compiler.ai.016, compiler.safety.007, compiler.ai.021.

### compiler.ai.021 — Nothing states what the safe subset guarantees

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
  Publish the resulting guarantee once compiler.ai.020 settles the unchecked boundary.
- Done when: the reference carries one page stating, per fault class, whether the safe subset
  excludes it, in which build configurations, and by which mechanism — and every claim on it is
  backed by a test in `bin/unittests`.
- Related: compiler.ai.020, compiler.safety.008.

### compiler.ai.022 — Declare recoverable error categories in public APIs

- Evidence: `fail` exposes fallibility and [`Swag.err`](../bin/reference/modules/language/src/013_001_error_management.swg)
  exposes a borrowed `any`. A caller handling only a missing file must otherwise learn which
  payloads can occur outside the signature.
- Next: prototype declared error categories with file reading and parsing. Use existing
  `fail` and `try` propagation, with an explicit open case for dynamic or foreign error
  sources. Check propagation into declared contracts and coverage for handlers that claim
  to handle the entire closed set.
- Done when: consumers can recover from absence, propagate access errors and distinguish
  invalid input without guessing payloads or treating every error as the same outcome.
- Related: compiler.ai.016, compiler.ai.051.

### compiler.ai.023 — Mixins resolve their body in the caller's scope

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

### compiler.ai.024 — A macro can redefine `break` and `continue` inside the block the caller wrote

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
  has preserved its behavior. That provider protocol is owned by compiler.ai.025.
- Next: Specify explicit control-flow capabilities for arbitrary #code blocks and classify current
  remaps as loop implementation or intentional interception. Coordinate the former with
  compiler.ai.025; test nested loops, labeled exits, early return, fail and defer for both.
- Done when: callers can identify any nonlexical control-flow interception, ordinary iteration needs
  no hand-authored remapping, and regression tests observe the exact exit and cleanup targets.

### compiler.ai.025 — Make custom iteration independent of manual control-flow injection

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
- Related: compiler.ai.024; compiler.ai.021.

### compiler.ai.026 — There are two metaprogramming systems and they do not meet

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

### compiler.ai.027 — A parallel loop cannot combine per-partition results

- Evidence: every partition of a `parallel for` receives the same captures. A loop that computes
  one value -- a sum, a maximum, a count, a first match, an accumulated bounding box -- cannot
  say that each partition needs its own accumulator and that the accumulators combine at the
  join. Consumers write one of two workarounds: an atomic on the shared destination, which
  serializes the loop's hot line and, with `AtomicValue.store` lowered to a locked exchange,
  pays a full barrier per iteration; or an array indexed by a partition number the language does
  not expose, which forces the body to know the partitioning it is explicitly told not to depend
  on.
- Evidence: the general escape, one accumulator per thread, is also expensive. Every access to a
  `tls` global calls the runtime's `__tlsVarPtr`
  (`CodeGenMemoryHelpers::emitGlobalVariableAddress`), which reads the global's slot identifier
  with an atomic compare-exchange before the host thread-storage lookup; the direct slot load of
  `2f353d606` serves only the runtime context. The per-thread block is released at thread exit
  without running `opDrop`, so it can only hold a plain value.
- Next: design the combining form as part of the statement, stating the identity, the
  per-partition storage and the combining operation together, and combining at the join rather
  than in the body. Settle whether the operation must be associative and commutative or only
  associative -- floating-point addition is not associative -- and say what result the program is entitled
  to when it is not. Decide whether the form is a clause of `parallel for` or a value the
  statement produces.
- Done when: a parallel sum, a parallel maximum and a parallel bounding box are written
  without an atomic on the hot line and without indexing a partition, and a single-worker run of
  the same source produces the same value the loop promises.
- Elsewhere: OpenMP has `reduction(+:x)` and user-declared reducers; Rayon, .NET PLINQ and Java
  streams reduce through the iterator; Chapel writes `+ reduce`. All of them treat reduction as
  the second data-parallel primitive after the map, not as a library afterthought.
- Related: language.parallelism.001, compiler.ai.028, std.core.025

### compiler.ai.028 — Partitions cannot prove disjointness

- Evidence: `try/catch/expect parallel for` now carries failures across the join, but there is
  still no way to express an exclusive view of part of a container. Consumers index captured
  buffers, including H.264 reconstruction, and the compiler proves nothing about those indices.
- Next: add exclusive row, tile, chunk, stride, split and zip views with bounds and overlap
  contracts, and a checked partition constructor for the cases static proof cannot reach. That
  validation is semantic input checking, not a release-disabled guard. Read-only source halos
  beside disjoint destination tiles must be expressible, because stencils and image transforms
  need them. Preserve the fallible loop's join and partial-effect contract while adding views.
- Done when: a partitioned image operation needs no manual indexing into a captured buffer,
  overlapping mutable views are rejected, and success still means every index ran exactly once.
- Related: language.parallelism.001, compiler.ai.027, compiler.ai.029.

### compiler.ai.029 — Captures do not prove task lifetime or race freedom

- Evidence: borrow analysis follows named and initialized captures, including addresses, field
  references, slices, aggregates and deferred call-result summaries. It rejects the tested local
  borrows returned in a closure or stored in a task from an outer lexical scope. Local destructor
  ordering also matters: a task declared before its captured source joins after that source is
  destroyed. Borrow merges retain the shortest local lifetime across captures, fields and flow
  alternatives. The unexecuted regression cases are in
  `bin/unittests/sanity/borrow_escape_drop_order.swg`. This does not
  establish race freedom: two partitions writing the same element and a captured pointer whose
  pointee is mutated elsewhere still compile.
- Linked-storage gap: the group no longer demonstrates it. `Swag.TaskGroup` holds its first
  children itself, so `reserveChild` can return a pointer into the group, `spawn` feeds a
  stores-into-group summary, and `groupBeforeCapture` in
  `bin/unittests/sanity/borrow_escape_drop_order.swg` is rejected with its expected diagnostic.
  The rule itself did not change: only block pointers carry owned payload, because treating every
  `*T` as owned would confuse parent and callback back-references with ownership, so a child
  reached solely through `blocks: *GroupBlock?` is still invisible to the ownership analysis.
  Find or build another case before extending the rule to linked storage.
- Both `Swag.Task.opDrop` and `Swag.TaskGroup.opDrop` join their work, including on early return
  and failure. An owner can still release a borrowed field in its own destructor before the
  implicit destruction of its task field; it must join before releasing that storage.
- Next: follow owned linked storage through accessors, with both an owned child and a non-owned
  parent pointer as regression cases. Then infer transferable (`Send`) and shared-readable
  (`Sync`) properties from fields, allocation, copy, move and destruction effects, and require
  them at captures. `NoCopy` does not imply `Send`, `const` does not imply deep immutability, and
  an atomic reference count does not synchronize its pointee. Raw pointers, opaque owners, native
  handles and foreign calls need a stated contract rather than automatic acceptance.
- Done when: a rejected capture names the concrete alias, allocator, destructor or executor
  constraint and points at a valid partition or ownership alternative; semantic tests reject
  hidden aliases, escaped borrows and cross-module global writes without optional analysis.
  Until then the capture list states intent rather than proving race freedom.
- Related: compiler.ai.020, compiler.safety.007, compiler.ai.021,
  language.parallelism.001.

### compiler.ai.030 — Choose one canonical instance-method declaration

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

### compiler.ai.033 — The apostrophe carries three unrelated roles

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
- Proposed contract: If paired generation and refactoring tasks show a benefit, use a delimited
  generic-argument form distinguishable from character literals and
  numeric/unit suffixes. This is a readability/syntax proposal, not a missing generics feature or
  an unresolved coloring bug. Compare angle brackets with another dedicated delimiter rather
  than assuming familiar punctuation has no parse cost.
- Next: Translate Array'u8, HashTable'(K, V), genericTwice's64(12), and value arguments such as
  at'1() into each candidate. Test nesting, comparisons/shifts next to generic calls, inferred
  arguments, formatting and incomplete editor input. Select one spelling and an AST-based
  migration; literal suffixes and character literals must retain an independent grammar.
- Done when: compiler.ai.059 settles whether a new delimiter reduces mistakes. If adopted,
  the parser, formatter, reference and editor agree on one spelling, including nested and
  value arguments.

### compiler.ai.034 — `[2, 2] T` and `[2][2] T` are different types indexed the same way

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
  `bin/`. Use composition and generation tasks in compiler.ai.059 to decide whether to
  migrate. If one form is vestigial, converge on the other. If both earn their place,
  diagnose ambiguous exposure in public APIs where it causes incorrect use.
- Done when: both multidimensional-array forms are measured in implementation and public APIs,
  and their compatibility or intentionally distinct use-site contract is documented and enforced.

### compiler.ai.035 — Verify runtime fault evidence across Windows run modes

- Evidence: the [bounds and panic fixtures](../src/Unittest/Compiler/Test.Compiler.Failure.cpp)
  exercise index, slice and count faults in scripts, JIT tests and native tests on Linux.
  Windows needs execution coverage for the same diagnostics and termination paths.
- Next: run the DevMode filesystem tests on Windows. Check that the native runner records
  the failed test and that a script reports the fault once and runs its drop hooks.
- Done when: the decisive values and original source location agree across the three modes,
  and a compile-time panic remains distinguishable from a script runtime panic.
- Related: compiler.ai.040, compiler.ai.042, compiler.safety.032.

### compiler.ai.036 — Suppress dependent errors while keeping independent diagnostics

- Evidence: [the semantic wait checker](../src/Compiler/Sema/Helpers/SemaCycle.cpp)
  suppresses stalled dependency reports once an error is known. Pending identifier lookups
  still report individually. Ordinary failed aliases, initializers and function signatures
  already leave independent errors visible.
- Next: reduce a cascading error from generic, imported or generated declarations to a
  fixture alongside an independent error. Suppress the dependent lookup only when it can
  be linked to the failed declaration or publication.
- Done when: the primary and independent diagnostics remain visible, with no secondary
  report caused by the failed declaration in that fixture.
- Related: compiler.ai.035, compiler.ai.037, compiler.ai.039.

### compiler.ai.037 — The compiler answers no semantic question from the command line

- Evidence: the compiler has no editor service and no retained analysis process: an autonomous
  caller compiles with one-shot commands. What a text search cannot answer still has no command:
  the type of an expression, the overload a call selected, the exact signature of an imported
  symbol, the callers of a function. Semantic analysis resolves each of them
  (`NodePayload::resolveSymbols`); nothing prints them. A definition reached through an import
  resolves to the generated API file, and a generated source view has no physical mapping.
- Next: add a one-shot `swc query` beside `swc sema` that analyzes a module and answers one
  question about a source position or a symbol. Start with the type and definition, then
  add refined types, the selected signature, implicit conversions and defaults, applicable
  methods and UFCS functions, and references keyed by symbol identity.
- Done when: one command each returns the resolved type, the selected
  overload, the declaration at its original source location across modules and expansions, and
  the references inside a workspace. Report unresolved and ambiguous positions explicitly. Reuse
  the module and prelude caches for cold latency.
- Related: compiler.ai.045, compiler.ai.044, compiler.ai.046, compiler.ai.039,
  compiler.ai.051, compiler.ai.042.

### compiler.ai.038 — Report semantic changes at untouched call sites

- Evidence: a new import, overload or changed default can change the meaning of source
  that still compiles. Text diffs and exit status cannot identify those callers.
- Next: compare two snapshots through the query engine. Start with selected callees,
  implicit conversion categories and applied defaults at unchanged call-site expressions.
  Map sites and symbols to stable source identities so a location shift does not look
  like a binding change.
- Done when: fixtures for adding a competing import, changing a parameter type and
  changing a default expose exactly the affected calls. Pure formatting produces no
  semantic changes.
- Related: compiler.ai.010, compiler.ai.011, compiler.ai.037, compiler.ai.043.

### compiler.ai.039 — Offer semantic cleanup edits with explicit preservation checks

- Evidence: candidate cleanups (direct-return bodies, declaration-bound `with`, relay locals)
  also match deliberate language-test syntax, owning locals and typed temporaries, which a
  textual rewrite cannot safely remove. The formatter normalizes source shape but cannot
  decide ownership, overload selection or evaluation effects.
- Proposed contract: a compiler-backed suggestion produces a previewable, versioned source edit
  only after checking the relevant semantic contract. Preserve evaluation count and order,
  receiver binding, contextual type, selected overload, lexical scope and destruction timing.
  A single-use variable is a candidate, not proof of redundancy.
- Boundaries: distinguish semantics-preserving cleanup from a diagnostic explaining a costly copy
  and from a breaking language migration. Never turn a copy into a move, a required receiver into
  an optional call, or a named owner into a temporary borrow automatically. Preserve comments and
  do not rewrite intentional syntax fixtures as part of an unfiltered bulk operation.
- Next: implement a semantic rewrite query on an ordinary compiler snapshot with a dry-run diff.
  Start with a unique verified import, explicit qualification of an existing target, and explicit
  argument names that preserve evaluation order. Check positive and negative cases on the resulting
  snapshot. Then extend it to expression bodies, declaration-bound `with` and relay returns.
  Route API-family renames through explicit semantic migration.
- Done when: suggested edits apply only to the analyzed document version, are idempotent,
  compile with the same relevant contracts, and regression tests reject transformations that
  alter effects, ownership, overload resolution or scope. A CLI preview shows each edit before it applies.
- Related: compiler.ai.037, compiler.ai.019, compiler.ai.043.

### compiler.ai.040 — Rerun one failed test by stable identity

- Evidence: file and tag filters and per-test events already exist. An
  [anonymous JIT test](../src/Main/Command/Command.Test.cpp#L675) is reported with its source
  location, but moving it changes that identity and a file filter can rerun its neighbors.
- Next: add an explicit test name or stable ID, with exact selection and a printed
  reproduction command carrying its workspace, module, effective preset, backend and
  explicit test inputs. Summarize selected, executed, failed and unexecuted tests,
  distinguishing a failed test from later tests skipped when the run had to stop.
- Done when: a printed command reruns one reported failure after a line-only edit and
  the result clearly identifies unmatched selections and incomplete runs in JIT and native.
- Related: compiler.ai.035, compiler.ai.041, compiler.ai.042.

### compiler.ai.041 — Show both values of a failed test comparison

- Evidence: `Swag.check(actual == expected)` reports the expression but gives no values
  for a failure such as 11 versus 10. [Existing verdicts](../bin/runtime/intrinsics.swg#L14)
  already distinguish stopping at a failure from recording it and continuing.
- Next: add a comparison assertion or a lowering of comparisons in test checks that
  captures each operand once and prints bounded values on failure. Start with scalars and
  strings, then locate the first differing element of a sequence.
- Done when: the report includes actual and expected values at the same source location
  in JIT and native tests, and evaluation-order tests prove operands and overloaded
  comparisons execute exactly once.
- Related: compiler.ai.035, compiler.ai.040.

### compiler.ai.042 — Separate program output from compiler records

- Evidence: a program run by the JIT writes unframed output to the same stdout as the
  compiler. The current line format is described in
  [the message guide](../.agents/skills/write-swag-compiler-messages/SKILL.md).
- Next: separate the program byte stream from driver records on JIT and native paths.
  Use a distinct channel for runtime output, and attach captured failure output to its
  owning test. Keep one readable compiler format, publish its grammar version in `swc info`
  and test the located diagnostic, stage and final command boundaries.
- Done when: program output can be consumed independently, text resembling a compiler
  record stays program output, and failures and final command results remain identifiable
  when a child exits early or a JIT test panics.
- Related: compiler.ai.035, compiler.ai.037, compiler.ai.040, compiler.ai.047.

### compiler.ai.043 — Check a proposed edit over the real workspace in memory

- Evidence: [in-memory semantic analysis](../src/Unittest/Compiler/Test.Compiler.InMemorySource.cpp#L1107)
  exists internally. The CLI takes files and directories, or a workspace and module,
  so checking a prospective edit currently requires writing the source first.
- Next: accept a versioned overlay of additions, substitutions and deletions keyed by
  workspace paths. Feed it to ordinary module analysis and the semantic query command,
  retaining source locations and the actual import graph. Report a blocked query when
  reaching a phase that needs compile-time execution under a read-only request.
- Done when: a proposed edit can be checked against the real module and its dependencies
  without changing the checkout. Overlay and on-disk checks agree for the same inputs,
  and incomplete or stale overlays produce explicit results.
- Related: compiler.ai.037, compiler.ai.038, compiler.ai.044, compiler.ai.047.

### compiler.ai.044 — Front-end invalidation is module-wide

- Evidence: front-end state is not persisted, so the compiler.core.004 `core_touch` workload
  rebuilds every file of the module. The AST is not an immutable parse cache. Semantic
  analysis replaces expressions and appends generated nodes to the per-file AST, and
  `SourceFile::setContent` rejects a change once an AST owns the source view. Invalidation needs the dependencies each file observed.
  Append-only symbol maps also keep retired declaration ASTs alive.
- Next: separate an immutable per-file parse result from semantic substitutions. Then persist
  lexical, parsed and semantic state per file, keyed by source content, relevant
  configuration and fingerprints of the imported public symbols the file observed.
- Done when: a private-body edit reanalyzes only the changed file and its semantic
  dependents. A public-signature change invalidates every consumer that observed it.
  Adding, removing or renaming a file, or changing configuration or compiler version,
  invalidates the correct state. `core_touch` lands far below `core_rebuild`, and
  equivalent-result tests cover clean and incremental workspace builds.
- Related: compiler.ai.045, compiler.core.004, compiler.core.003, compiler.core.016.

### compiler.ai.045 — Replace generated dependency source with a reusable module interface

- Evidence: `CompilerInstance::appendImportedApiSnapshot` creates an `ImportedApi` source
  file for every published API source. `Command::sema` sends those files through
  `parseSourceFiles`, declaration sema, and full sema in each consumer. Dependency source
  snapshots and native artifact reuse do not preserve the resolved interface for a consumer
  that needs recompilation. `canDelayImportedFunctionBody` already defers eligible free
  function bodies, but excludes methods, interface implementations and other
  context-sensitive cases. Restoring methods' declaration contexts is insufficient by itself:
  delayed `ConcatBuffer.addBytes` and `reserveInPlace` can remain unresolved when native/JIT
  preparation waits on their semantic completion through allocation-failure reporting.
  Repeated closure application remains a local lead: a per-consumer capture set improves
  a 1,000-file shared dependency, but a standard eight-root graph was about 2.7% slower
  overall in Release despite neutral setup timing.
  Parse-image prototypes still required original source loading and a fresh semantic pass;
  their read and reconstruction costs did not establish a whole-command gain.
  `MachineCodeCache` preserves supported compiled bodies, while imported declaration and
  type resolution remain fresh.
- Next: measure imported API bytes, tokens, AST memory, parse time and declaration/body sema
  work separately from consumer sources on a small consumer, a large module graph, and a
  diamond dependency, including consumers of the core, pixel and gui API closures. Compare
  cold and warm imports with both compiler executables. Use
  that baseline to prototype a versioned binary interface for resolved non-generic
  declarations; retain the source import path for unsupported declarations while expanding
  coverage. Before widening lazy imported methods, close body materialization across cyclic
  method/free-function calls, then verify both compile-time execution and native presolve.
  Account for whole-command effects before adopting per-capture closure deduplication.
- Interface contract: preserve namespace and overload membership, exported and supporting
  symbols, canonical type identity, layouts, constants and default arguments, attributes
  including safety/borrow contracts, interface implementations, ABI/link identities, and
  source provenance. Index declarations for selective materialization without hiding
  overloads or implementations from lookup. Keep generic templates and required
  inline/macro/mixin bodies in separately indexed sections; instantiate or expand them in
  the consumer context when required. Resolved ordinary bodies can later use the typed-body
  representation from compiler.optimization.107. Importing metadata must not replay module
  setup or compile-time side effects; requested compile-time calls retain their execution
  behavior. Keep readable `.swg` export for inspection and compatibility.
- Ownership: compiler instances own their identifier, type and constant managers, and symbols
  point into mutable ASTs. Serialize stable interface-local identities and remap them into
  the consumer; do not persist raw pointers or share live semantic state across consumers.
  Reuse immutable interface bytes within a workspace invocation, with consumer-owned
  materialization and generic-instance state.
- Cache/publication: validate format and compiler identity, target/ABI, relevant configuration,
  exported content including required bodies, and transitive interface fingerprints. Publish
  the interface with the matching API/native artifact generation under the existing
  publication protocol. Reject partial, corrupt or incompatible entries; use a complete
  matching source API or rebuild rather than mixing generations.
- Done when: supported workspace imports skip API lexing, parsing and declaration sema;
  complete coverage removes the generated-source import path from ordinary builds. Warm
  imports show lower wall time and peak memory on the measured consumers. Fresh and reused
  paths preserve diagnostics, source locations, overload resolution, generic/inline/macro
  behavior, compile-time execution and native behavior. Workspace regressions cover diamond
  dependencies, configuration and transitive API/body changes, stale/corrupt entries and
  concurrent publication under both compiler executables with real parallelism.
- Related: compiler.ai.044, compiler.ai.046, compiler.ai.037, compiler.core.030, compiler.optimization.107.

### compiler.ai.046 — Reuse analyzed prelude state

- Evidence: each fresh compiler process analyzes the unchanged runtime prelude before compiling
  a module or script. Machine-code archives amortize backend emission, but original runtime
  source loading, lexing, parsing and semantic analysis still repeat for each instance.
- Next: serialize the prelude through the ordinary module-interface mechanism and include source, compiler, target, and relevant configuration in its cache key.
- Done when: warm module builds and script launches skip prelude lexing, parsing, and semantic analysis, while fresh and reused paths produce identical diagnostics and artifacts.
- Related: compiler.ai.045, compiler.core.004, compiler.core.016.

### compiler.ai.047 — An autonomous caller cannot tell what a command may execute or change

- Evidence: compiling Swag can execute `#run` and JIT code; `run`, `test`, format, clean, tool
  setup, and example commands have different filesystem, process, and machine-configuration effects.
  `Command.DryRun.cpp` already reports a suppressed-execution plan, and `syntax` stops after parsing.
  What is missing is a discoverable command effect contract that can answer before any project code executes.
- Intent: give all callers an explicit effect model. Read-only discovery and parsing have a defined
  no-execution contract; planning reports what would execute or change; mutation and launch commands
  name their targets before acting. Existing safe defaults such as `new` refusing collisions become
  part of the public contract.
- Next: encode the existing dry-run and syntax boundaries, then inventory each command's reads,
  writes, process launches, compile-time execution, native
  linking, cache use, and shell/registry changes. Define safe inspection modes and the boundary at
  which semantic analysis necessarily requires user code. Report the actual blocked phase
  and its source or module on read-only requests.
- Done when: an autonomous caller can enumerate a command's effects without executing user
  code, choose a documented non-executing inspection path, and receive a precise report before a
  command writes outside the project or configured cache roots, launches an artifact, contacts a
  network endpoint, or edits user shell configuration.
- Related: compiler.ai.053, compiler.ai.042, platform.portability.009,
  platform.portability.080.

### compiler.ai.049 — Use one contract for a normal lookup miss

- Evidence: [`HashTable.find`](../bin/std/modules/core/src/collections/hashtable.swg#L811)
  asserts on a missing key, while [`Regexp.find`](../bin/std/modules/core/src/text/regexp/regexp.swg#L231)
  returns a flag and span and changes capture state. UTF-8 index searches can return
  `Swag.U64.Max`. A caller guessing from the names can mishandle absence or mutate state.
- Next: normalize the Core collection, regex and text search families. Make normal absence
  explicit in the result, name required-presence operations separately, and expose when a
  search updates capture state. Choose a representation that cannot expose an unchecked
  span or index for a miss. Test empty input and an empty successful match separately.
- Done when: the same operation vocabulary predicts the miss, ownership and mutation
  contract across the audited families, and a miss cannot be consumed as a valid result.
- Related: compiler.ai.014, compiler.ai.016.

### compiler.ai.050 — There is no serializable documentation model

- Evidence: the pipeline collects `DocItem`/`DocOverload` ([DocTypes.h](../src/Doc/DocTypes.h))
  and renders straight to HTML, so nothing else can consume it. `--export-api-dir` publishes
  the public surface as Swag source, but not the items with their documentation and links.
- Next: publish the collected model with stable item identity, kind, signature, documentation,
  source location, imports, target restrictions and available ownership summaries. Emit
  it from `swc doc` beside the HTML.
- Done when: a documentation run can write the serialized model, its item identities stay
  stable across runs on unchanged sources, and a test reads it back.
- Related: compiler.command.doc.004, compiler.command.doc.005

### compiler.ai.051 — Documentation is not available as version-matched local data

- Evidence: the language reference and standard-library documentation are maintained in the
  repository and the website is generated from them, but the command help points at remote pages.
  The `doc` pipeline has no serializable documentation model yet (compiler.ai.050), so an
  agent or offline command cannot ask a stable local semantic question without scraping HTML.
- Intent: publish documentation as local, version-matched data, with both
  concise terminal rendering and structured retrieval. It includes the language tour, command-line
  reference, runtime and standard-module APIs, ownership/lifetime rules, platform limits, and the
  source-backed examples needed by first use. A release may also offer browser-opening HTML, but no
  task may require a browser or Internet connection.
- Next: make compiler.ai.050's documentation serialization the source of the local index;
  define `swc docs show <topic>`, `swc docs search <terms>`, and API/module lookup around that
  index. Every returned item carries a release version, stable identifier, local source/topic
  reference, signatures, imports, platform requirements, and a minimal compilable example where
  one exists. Index by operation and input/output type as well as by symbol, and expose
  the owner and invalidation rules of borrowed results.
- Done when: the compiler can answer an offline query for a language feature, a standard symbol,
  an import, a lifetime contract, and a command option from data built by the same release. A query
  cannot accidentally combine documentation, runtime, or standard-library data from different
  compiler builds.
- Related: compiler.ai.052, compiler.command.doc.002, compiler.ai.050,
  compiler.ai.053, compiler.ai.037.

### compiler.ai.052 — Code examples in documentation are rendered, never compiled

- Evidence: every ```` ```swag ```` fence goes through `DocMarkdown::renderCodeBlock`, which
  only syntax-colors it. Nothing compiles it, so examples such as the worked example in the
  `truetype` module header ([module.swg](../bin/std/modules/truetype/module.swg)) are
  unchecked.
- Next: synthesize one `#test` per documentation example and compile and run it with the
  module's tests. Mark intentionally incomplete or illustrative snippets explicitly. Give
  diagnostic examples expected failures and executable examples behavioral checks.
- Done when: every unmarked ```` ```swag ```` example in `bin/` compiles, behavioral examples
  run, and a broken example reports its location inside the documentation comment.
- Elsewhere: rustdoc compiles and runs every example; Go compiles `Example` functions and
  checks their output.

### compiler.ai.053 — The first command does not close the first-program loop

- Evidence: `swc help` shows `new script`, `new module` and their follow-up commands, but its
  links lead to the website and GitHub's moving `master` branch
  (`CommandLineParser.Help.cpp`). `swc new` embeds only a script and a module starter
  (`Command.New.cpp`). An offline user has no local route from a command,
  an error, or a generated starter to version-matched explanation.
- Next: give every command a local documentation topic in `swc help <command>`, with
  examples, defaults, side effects and destructive behavior. Add named embedded templates
  to `swc new` (workspace executable, tests, command-line arguments, files, errors, minimal
  GUI). Include the first test or verification command for each starter. Extend the existing
  collision-safe creation result with expected output and a local topic. Reuse `--dry-run`
  for the creation plan.
- Done when: an offline newcomer can complete a script and workspace tutorial with
  `swc` and its local resources, inspect a build before it runs, and recover from an intentional syntax error and a
  missing-toolchain error without a browser or repository.
- Related: compiler.ai.051, compiler.ai.054, compiler.ai.052, compiler.ai.009.

### compiler.ai.054 — Examples are repository files, not a runnable catalogue

- Evidence: useful scripts, module demonstrations, applications, and tested reference pages exist
  below `bin/examples` and `bin/reference`, but their discovery depends on the repository tree and
  GitHub. Names alone do not tell a beginner whether an example writes files, opens a window,
  requires assets, imports native libraries, or is the right minimum for one concept.
- Intent: turn the repository examples into a local catalogue with `list`, `show`, `copy`, `run`, and
  `test` operations. Each example names its learning goal, difficulty, required modules and host
  capabilities, source/assets, expected output, runtime bound, and exact verification command.
- Constraints:
  - The catalogue supplies all assets each example needs and runs without accessing
    temporary developer paths or the network.
  - `copy` creates a user-owned project and refuses collisions; `show` is read-only; `run` makes
    its execution and output location explicit.
  - The catalogue begins with small composable examples before games and applications. Every
    advertised example is built or tested with the matching compiler.
- Next: turn the repository examples into a local catalogue with list, show, copy, run, and test operations
  and the stated provenance and limits.
- Done when: a user can find, inspect, copy, run, and test one example for scripts, workspaces,
  imports, tests, errors, compile-time execution, core collections, and GUI from the same catalogue. The catalogue gives a useful prerequisite report rather than attempting an impossible
  native or GUI example.
- Related: compiler.ai.053, compiler.ai.051, compiler.ai.052.

### compiler.ai.059 — Measure reliable agent changes on repository tasks

- Next: freeze tasks with independent behavioral tests for adding an enum case, changing an
  overload, repairing an invalidated borrow, preserving a destination on file failure and
  reproducing a native test failure. Include code that compiles but violates the requirement.
  Run paired trials across multiple agents at matched tool and time budgets.
- Done when: the campaign reports first-patch and final behavioral success, false greens,
  repair attempts, time to verified success and use of unchecked assertions or escape
  hatches. Use the results to rank migrations with compatibility costs, including generic
  delimiters, multidimensional array forms, conditional chains and control-body delimiters.
- Related: compiler.ai.033, compiler.ai.034, compiler.ai.038, compiler.ai.040,
  compiler.ai.060, compiler.ai.061, compiler.core.004.

### compiler.ai.060 — Use one spelling for chained conditions

- Evidence: Swag spells a continuation `elif` in both ordinary and `#static if` chains.
  The parser already represents each continuation as another conditional in the else slot.
  `else if` currently lacks that same grammar, and `else do if` is parsed as an embedded
  statement. A word search finds about 1,900 `elif` occurrences across 530 Swag files in `bin/`,
  including the bootstrap runtime.
- Proposed contract: compare one canonical `else if` spelling with the existing `elif`.
  In the prototype `else if` continues the same chain and uses the same scope and guard rules
  in both phases. An explicitly braced `else` containing an `if` remains a nested statement.
- Next: prototype `else if` in the runtime and compiler parsers and migrate a representative
  slice with the formatter, including comments between branches and `#static` declarations.
  Compare syntax-repair rate and task success on compiler.ai.059; record the source migration
  and old-compiler bootstrap cost before choosing one spelling.
- Done when: one spelling is selected; if it changes, ordinary, binding and compile-time
  chains preserve branch order, short-circuiting, name visibility and formatter behavior.

### compiler.ai.061 — Use one delimiter for control bodies

- Evidence: `if`, `while`, `for` and `#static if` accept a braced body or `do` followed by
  one statement or declaration. `do` followed by braces is diagnosed, except when the braces
  open a destructuring assignment. The parser has separate runtime and compile-time entry
  points, and the formatter has a branch-body uniformity option. A word search finds about
  31,500 `do` occurrences across 2,825 Swag files in `bin/`.
- Proposed contract: compare braced control bodies with the current two forms, including a
  compact `{ statement }` layout for simple guards. Use an explicit inner block for constructs
  that need one. Classify trailing code passed to macros and single-statement forms on `with`
  and `defer` before deciding which grammar the rule covers.
- Next: prototype a syntax-aware `do`-to-brace rewrite for guards, loops and top-level
  `#static if`. Keep a destructuring assignment inside its new body, as in
  `{ {field: target} = record }`. Check bindings, scope and cleanup order, `break` and
  `continue`, comments and generated source. Compare edit reliability on compiler.ai.059 and report
  source growth and formatter stability before selecting a syntax.
- Done when: one rule for supported control bodies is selected from those results, with
  a verified syntax migration and consistent parser, formatter, reference and editor behavior
  if the rule changes.
