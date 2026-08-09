# Findings — Language

Surprises in the language itself: rules that are consistent on their own page and stop being
consistent once two pages meet, spellings that carry more than one meaning, and defaults that
read one way and behave another. These are observations against the reference
([bin/reference/modules/language/src](../bin/reference/modules/language/src)), not compiler
defects — the compiler does what the reference says. What is in question is whether the reference
should say it.

Design questions already open *by choice* — exhaustive switches, tagged unions, generic contracts,
concurrency — are the roadmap in [todo.language.md](todo.language.md) and are not repeated here.
Compiler defects are in [findings.compiler.md](findings.compiler.md).

Conventions, the identifier counter, and the rest of the backlog are in [README.md](README.md).
Entries are sorted by identifier, ascending; position carries no priority.

### F-045 — Positional destructuring binds by position even when every name matches a field

- Area: language
- Found while: a reading pass over the whole language reference
- Observation: `let {a, b} = tuple` is positional, and the reference says so
  ([004_003_tuple.swg:86-102](../bin/reference/modules/language/src/004_003_tuple.swg#L86-L102)).
  What it does not say is that the names in the pattern are *ignored* rather than checked, so a
  pattern whose names are exactly the source's own field names, written in the other order, binds
  each one to the wrong field and compiles without a word. The named form (`{y: vertical}`) exists
  and is the correct spelling, but nothing steers a reader towards it: the positional form is the
  one every example uses, and it accepts the named-looking pattern silently.
- Evidence: with `let point = {x: 10, y: 20}`, `let {y, x} = point` gives `y == 10` and `x == 20`.
  Confirmed under both the JIT and the forged binary.
- Next step: decide whether a positional pattern whose every name matches a field of the source —
  in a different order — should be a warning (`sema_warn_positional_pattern_shadows_field`) or an
  error. A warning is enough: the shape is unambiguous to detect, and the fix is one colon per
  binding. It also needs the warning-policy layer that now exists, so it is cheap.
- Related: the same pattern syntax is what `let {r, g, b} = getWhite()` uses in
  [007_008_retval.swg:49](../bin/reference/modules/language/src/007_008_retval.swg#L49), where the
  names read as field names and happen to be in order.

### F-046 — One default in a grouped declaration silently defaults every name in the group

- Area: language
- Found while: the same pass
- Observation: `x, y: s32 = 0` declares two parameters and gives *both* the default `0`. The
  grouped form was introduced to share a type
  ([003_005_variables.swg:26-35](../bin/reference/modules/language/src/003_005_variables.swg#L26-L35));
  sharing the initializer as well is the same rule applied one token further, and it means a
  parameter list can hand out a default nobody asked for. A caller can then omit an argument that
  reads as required, and get a zero.
- Evidence: `func f(x, y: s32 = 0) => x + y * 2` accepts `f(x: 10)` (→ 10) *and* `f(y: 10)` (→ 20).
  The reference shows exactly this call pair and treats it as ordinary
  ([007_001_declaration.swg:102-107](../bin/reference/modules/language/src/007_001_declaration.swg#L102-L107)).
- Next step: sweep `bin/` for grouped parameter declarations carrying a default and count how many
  are deliberate. If the honest answer is "almost none", the rule to consider is that a default in a
  grouped declaration applies to the last name only, or is rejected outright — both are mechanical
  migrations. Decide it before the surface grows further.

### F-047 — `#scope` swallows `break`, and `continue` turns a plain block into a loop

- Area: language
- Found while: the same pass
- Observation: `break` "exits the nearest enclosing control structure"
  ([005_006_break.swg:4-8](../bin/reference/modules/language/src/005_006_break.swg#L4-L8)), and a
  `#scope` block counts as one. Wrapping a piece of a loop body in a `#scope` — to name a jump
  target, or just to group — therefore retargets every `break` already inside it, with no
  diagnostic. The reverse surprise is `continue`: inside a `#scope` that is not a loop, it jumps
  back to the start of the block, so a brace block silently *is* a loop.
- Evidence: a `for 3` whose body opens a `#scope { break }` runs all three iterations and executes
  everything after the scope each time. A bare `#scope { n += 1; if n == 4 do break; continue }`
  runs four times. Both confirmed under the JIT and the forged binary.
- Next step: the retargeting is the dangerous half. Consider requiring `break to <Name>` inside a
  *named* scope and rejecting a bare `break` whose nearest enclosing structure is an unnamed
  `#scope` that sits inside a loop — the ambiguous case is exactly that one. Check first how many
  `#scope` uses in `bin/` rely on the current reading.

### F-048 — Mixing a signed and an unsigned operand of the same width converts the signed one

- Area: language
- Found while: the same pass
- Observation: when two integer operands have the same width and differ in signedness, "the
  unsigned type wins"
  ([003_006_operators.swg:243-265](../bin/reference/modules/language/src/003_006_operators.swg#L243-L265)).
  Because Swag deliberately does *not* promote 8- and 16-bit operands to 32 bits the way C does,
  that rule has no wider type to escape into: `s8 + u8` is computed in `u8`, so a negative left
  operand is not added, it is reinterpreted. The expression that looks like arithmetic is a guarded
  conversion, and the guard is a `release`-time no-op.
- Evidence: a constant `-1's8 + 1'u8` is rejected at compile time ("cannot cast '-1' to 'u8' …
  value is negative, but the target type is unsigned"). The same expression through runtime
  variables panics with "integer overflow" in `fast-debug` — and in `release`, where the overflow
  guard is off, it wraps.
- Next step: the promotion table is a deliberate design choice and should not be re-litigated
  wholesale. What can be decided narrowly is whether a *mixed-signedness* operation, specifically,
  deserves a warning at the operator rather than a panic at the conversion — the operand types are
  known statically, so it costs nothing, and it is the one case where the "no C promotion" rule and
  the "unsigned wins" rule combine into something neither one predicts.

### F-049 — `for it in x` binds a live view, never a copy

- Area: language
- Found while: the same pass
- Observation: the element binding is a reference to the element, for scalars as much as for
  structs. The reference introduces `&it` as the way to "visit elements by address and modify them"
  ([005_003_for_elements.swg:148-169](../bin/reference/modules/language/src/005_003_for_elements.swg#L148-L169)),
  which reads as though the plain form were a copy and `&` opted into indirection. It does not:
  `&` opts into *mutability*. A plain `it` already sees writes made to the collection during the
  iteration, which is not what a reader who wrote `for value in values` expects to have signed up
  for.
- Evidence: `for it in cells { cells[1].v = 99; seen += it.v }` sums 100, not 3. Identical with a
  `[2] s32` and a plain `it`. Confirmed under the JIT and the forged binary.
- Next step: this is a documentation fix before it is anything else — say plainly that the binding
  names the element, and that `&` adds the right to write through it. Then decide whether the
  invalidation half of the borrow rules should also cover an in-place element write read back
  through the binding, or whether that is deliberately out of scope.
- Related: the borrow rules already reject *structural* mutation during iteration
  ([013_004_borrowing.swg:186-196](../bin/reference/modules/language/src/013_004_borrowing.swg#L186-L196)).

### F-050 — A by-value closure capture erases `let` immutability

- Area: language
- Found while: the same pass
- Observation: a capture is "a plain byte copy into the closure"
  ([007_003_closure.swg:9-14](../bin/reference/modules/language/src/007_003_closure.swg#L9-L14)),
  and the copy is mutable regardless of how the source was declared. Capturing a `let` therefore
  produces a mutable, persistent cell that outlives the binding it was copied from and shares its
  name. The reference's own example does exactly this and presents it as the way to build stateful
  behaviour
  ([007_003_closure.swg:131-154](../bin/reference/modules/language/src/007_003_closure.swg#L131-L154)).
- Evidence: `let base = 10` captured as `func|base|()->s32 { base += 1; return base }` returns 11
  then 12 across calls, while the outer `base` stays 10.
- Next step: the capacity is wanted; the spelling is the question. Consider requiring `var` on a
  capture the closure body writes (`func|var base|`), which keeps the stateful-counter idiom, keeps
  a read-only capture read-only, and makes the name-shadowing visible at the capture list rather
  than at the assignment.

### F-051 — Error propagation has three spellings, one of them invisible and one context-dependent

- Area: language
- Found while: the same pass
- Observation: inside a `fail` function, calling a fallible function propagates *implicitly*, so
  `try` is optional and an error can leave a function with nothing at the call site marking it
  ([013_001_error_management.swg:113-129](../bin/reference/modules/language/src/013_001_error_management.swg#L113-L129)).
  Separately, inside `#test`, `try` is redefined to mean `expect`
  ([013_001_error_management.swg:188-203](../bin/reference/modules/language/src/013_001_error_management.swg#L188-L203)),
  so the same three characters propagate in one context and panic in another. The visible-
  propagation-point argument that justifies having `try` at all is undone by the first rule, and the
  second makes a test's success path stop matching the code it is testing.
- Evidence: `func f()->u64 fail { return count(name) }` propagates without `try`. `try f()` inside
  `#test` returns the value where the identical line in a non-test function would propagate.
- Next step: these are two independent decisions and should be taken separately. For the first,
  measure how much `bin/` relies on the implicit form before considering making `try` mandatory. For
  the second, `expect` already exists and says what it means; the `#test` aliasing buys three saved
  characters and costs a reader the ability to read one line in isolation.

### F-052 — `catch` without a capture substitutes the type default and says nothing

- Area: language
- Found while: the same pass
- Observation: `catch f()` handles the error, drops it, and yields the default value for the result
  type
  ([013_001_error_management.swg:70-86](../bin/reference/modules/language/src/013_001_error_management.swg#L70-L86)).
  It is a one-word conversion of a failure into a zero, with no `discard`-style ceremony — while the
  language elsewhere refuses to let an ordinary return value be ignored without `discard`
  ([007_007_discard.swg](../bin/reference/modules/language/src/007_007_discard.swg)). The two
  policies point in opposite directions: an unread `s32` is an error, an unread *failure* is a zero.
- Evidence: `func swallow()->s32 { return catch mustFail() }` returns 0 with no diagnostic.
- Next step: the shape is legitimate and has real uses. What it lacks is the deliberateness the rest
  of the language asks for. Consider making the discarding form its own spelling — `catch discard
  f()`, or requiring the `as err` capture and letting an unread `err` be the thing the warning layer
  reports — so that "I looked at the error and chose to ignore it" and "I did not look" stop reading
  the same.

### F-053 — The apostrophe carries three unrelated roles

- Area: language
- Found while: the same pass
- Observation: `'` opens a character literal, introduces a literal suffix, and introduces a generic
  argument list. Which one applies depends on the token *before* it
  ([003_003_string.swg:108-130](../bin/reference/modules/language/src/003_003_string.swg#L108-L130)),
  so `5's32`, `genericTwice's64(12)`, `floatWindow.at'1()`, `Duration = 500'ms` and `'a'` all use
  the same character for four different jobs — and a user-defined literal suffix
  ([006_010_custom_literals.swg](../bin/reference/modules/language/src/006_010_custom_literals.swg))
  makes the suffix set open, so `x'foo` cannot be read without knowing what `x` is. Blanks do not
  disambiguate: `5 's32` is the suffixed literal, not `5` followed by a character.
- Evidence: `let spaced = 5 's32` yields 5 as an `s32`; `idOf's32(7)` is a generic call and reads
  like a suffixed identifier; `' 'u32` is a space literal followed by a suffix.
- Next step: nothing here is broken, and changing a sigil is expensive. What is worth measuring is
  the cost paid elsewhere: check how the syntax highlighter, the formatter's classifier, and the
  language reference each disambiguate, and whether any of the three gets it wrong. If they all
  carry a copy of the same lookbehind rule, that is the argument for a distinct generic-argument
  spelling.

### F-054 — The leading dot carries four unrelated roles

- Area: language
- Found while: the same pass
- Observation: `.name` means "member of `me`" in a method
  ([006_002_impl.swg:60-63](../bin/reference/modules/language/src/006_002_impl.swg#L60-L63)),
  "member of the `with` subject" in a `with` block
  ([011_004_with.swg](../bin/reference/modules/language/src/011_004_with.swg)), "value of the
  inferred enum type" in an expression or a `case`
  ([004_004_enum.swg:266-283](../bin/reference/modules/language/src/004_004_enum.swg#L266-L283)),
  and "member of the interface scope" in `pt2.IReset.set(10)`. Inside a method containing a `with`
  block and switching on an enum, three of them are live at once, and the resolution order between
  `with` and `me` had to be fixed by hand in the compiler.
- Evidence: the ordering fix is in the tree (`Sema.Member.Auto.cpp`), and the ambiguous-`.member`
  diagnostic is already a separate finding (F-025 in
  [findings.compiler.md](findings.compiler.md)).
- Next step: this is a design question rather than a defect, and it should be written down as one
  before the next construct that wants a leading dot is added. The concrete deliverable is a
  precedence table in the reference — one place stating which subject a leading dot binds to, in
  which order — rather than four pages that each mention their own case.

### F-055 — A `switch` accepts several `default` clauses

- Area: language
- Found while: the same pass
- Observation: a `default` can carry a `where`, and once it can, a switch can hold several of them
  ([005_005_switch.swg:261-278](../bin/reference/modules/language/src/005_005_switch.swg#L261-L278)).
  The word means "everything not matched above" in every language that has it; a guarded `default`
  is a `case` whose condition happens to be written without a value, and the plural makes "default"
  stop naming the fallback.
- Evidence: a switch holding `default where y == 10:` followed by `default:` compiles and takes the
  first one.
- Next step: `case where <cond>` already expresses a valueless guarded arm in an expression-less
  `switch` ([005_005_switch.swg:343-367](../bin/reference/modules/language/src/005_005_switch.swg#L343-L367)).
  Check whether `default where` can be spelled that way instead and `default` restored to exactly
  one unguarded arm — a small change with a mechanical migration, if `bin/` does not lean on it.

### F-056 — The default visibility inverts between a declaration and a field

- Area: language
- Found while: the same pass
- Observation: the same four words mean opposite defaults depending on what they annotate. A
  top-level declaration is `internal` unless it says otherwise; a struct field is `public` unless it
  says otherwise
  ([002_009_visibility_and_exports.swg](../bin/reference/modules/language/src/002_009_visibility_and_exports.swg#L1-L78)).
  So a module's *functions* are closed by default and its *state* is open by default, which is the
  reverse of what a module API wants, and the reverse of the rule the page states two paragraphs
  earlier.
- Evidence: the reference documents both defaults, back to back — "`internal` is the default" for
  declarations, "`public` is the default: a field is part of the surface unless it says otherwise"
  for fields.
- Next step: count how many public struct fields under `bin/` are deliberately part of the surface
  versus incidentally exposed. If the second number dominates, flipping the field default to
  `internal` is the change, and `#[Swag.ExportType]`-style reflection walkers are the compatibility
  risk to check first.
- Related: [design-swag-bin-modules](../.agents/skills/design-swag-bin-modules/SKILL.md) reviews
  module surface as one contract, and this default is upstream of it.

### F-057 — The slice upper bound is inclusive

- Area: language
- Found while: the same pass
- Observation: `str[1 to 3]` is three elements, `str[1 until 3]` is two
  ([004_002_slice.swg:88-111](../bin/reference/modules/language/src/004_002_slice.swg#L88-L111)).
  Inclusive-by-default is a defensible choice for a *loop*, where `to` reads as "up to and
  including". For a *slice* it is the one convention no neighbouring language uses, and it makes
  the half-open form — the one that composes, the one whose length is `high - low`, the one that
  handles the empty case without a special rule — the longer word.
- Evidence: `s[1 to 3]` is `"tri"`, `s[1 until 3]` is `"tr"`. The empty and inverted cases then need
  their own paragraph and their own runtime guard
  ([004_002_slice.swg:113-135](../bin/reference/modules/language/src/004_002_slice.swg#L113-L135)),
  which the half-open form would not.
- Next step: not a change to make — both spellings exist and the inclusive one is the shorter word
  by design. What is worth doing is measuring: count `to` versus `until` in slice position across
  `bin/`, and check whether the off-by-one it invites shows up in the test corpus. That number
  decides whether this is a wart or a trap.

### F-058 — `#[Swag.EnumFlags]` silently renumbers every member

- Area: language
- Found while: the same pass
- Observation: adding the attribute changes `A` from 0 to 1, `B` from 1 to 2, `C` from 2 to 4
  ([004_004_enum.swg:145-161](../bin/reference/modules/language/src/004_004_enum.swg#L145-L161)).
  The attribute reads as a statement about how the values are *used*; it is in fact a statement
  about what the values *are*. On a serialized, persisted, or ABI-visible enum, adding it is a
  silent wire-format break, and the first member loses the zero that a flag set needs for "none".
- Evidence: the reference's own example asserts `MyFlags.A == 0b00000001` for an enum declared
  `{ A, B, C, D }`.
- Next step: this repository already knows what a silently-renumbered enum costs
  (`TagBin` flag values are wire format). The cheap guard is a warning when `Swag.EnumFlags` is
  added to an enum that has no explicit values *and* is reachable from a public API — or, more
  simply, requiring an explicit `= 0` first member on a flags enum, which documents the "none" case
  and makes the renumbering visible in the source.

### F-059 — `++` is compile-time only, and there is no runtime string concatenation at all

- Area: language
- Found while: the same pass
- Observation: `++` joins strings and constants at compile time, and two runtime strings cannot be
  joined by any operator — `+` is not defined on `string`, and `++` reports that it needs a constant
  ([003_003_string.swg:64-89](../bin/reference/modules/language/src/003_003_string.swg#L64-L89)).
  The operator is also the one C-family spelling every reader arrives with a different meaning for.
  Meanwhile the compile-time diagnostics (`#print`, `#assert`, `#error`, `#warning`) each take
  exactly one expression, so `++` is not really an operator so much as the argument separator those
  four directives lack
  ([002_008_sigils.swg:101-121](../bin/reference/modules/language/src/002_008_sigils.swg#L101-L121)).
- Evidence: `let c = "a" ++ (b + 1) ++ "!"` is folded at compile time; the same line with a runtime
  `b` does not compile, and the fix is a `Std.Core` builder.
- Next step: the honest question is whether the four diagnostics should be variadic instead, which
  removes most of `++`'s remaining job. That is a small parser change and it would let `++` be
  judged on its own merits — as a constant-folding operator that a `#[Swag.ConstExpr]` function
  could arguably provide instead.

### F-060 — Mixins resolve their body in the caller's scope

- Area: language
- Found while: the same pass
- Observation: a mixin body names variables that do not exist where it is written and are expected
  to exist wherever it is called
  ([015_001_mixins.swg:20-36](../bin/reference/modules/language/src/015_001_mixins.swg#L20-L36)).
  That is dynamic scoping, in a language whose macros went to the trouble of being hygienic
  ([015_002_macros.swg:94-116](../bin/reference/modules/language/src/015_002_macros.swg#L94-L116)).
  A mixin cannot be checked at its declaration, a typo in it is reported once per call site, and
  renaming a local in a *caller* can break a mixin declared in another file.
- Evidence: `#[Swag.Mixin] func myMixin() { a += 1 }` compiles with no `a` in sight and resolves to
  whatever `a` the call site has.
- Next step: check how many mixins under `bin/` actually rely on free identifiers rather than on
  parameters and `#code` blocks. If the number is small, the interesting question is whether the
  free-identifier form still earns its keep now that `#code(...)` block parameters exist — they
  cover the same ground with a declared contract.
- Related: `#uniq0`..`#uniq9` exist precisely to work around the collisions this creates, and there
  are exactly ten of them.

### F-061 — A macro can redefine `break` and `continue` inside the block the caller wrote

- Area: language
- Found while: the same pass
- Observation: `#inject(what, break = break to Outer, continue = break)` rewrites the meaning of
  two keywords in code the caller wrote and can see
  ([015_002_macros.swg:236-312](../bin/reference/modules/language/src/015_002_macros.swg#L236-L312)).
  The caller's `break` is not shadowed or wrapped — it is replaced, with nothing at the call site
  indicating that the block's control flow is under someone else's control.
- Evidence: the reference's `repeatSquare` remaps `continue` to `break`, so a `continue` written in
  the user block exits the inner loop instead of continuing it — the two keywords trade places.
- Next step: the capacity is what makes `opVisit` work at all and should not be removed. What is
  missing is disclosure: consider requiring the block literal to acknowledge it
  (`#code(break, continue) { ... }`, the same shape the call site already uses to rename block
  parameters), so a reader of the call site knows the keywords are not the ones they look like.

### F-062 — Struct parameters are always const references, and there is no by-value form

- Area: language
- Found while: the same pass
- Observation: declaring a struct or tuple type as a parameter is defined to be a const reference
  ([004_008_references.swg:105-121](../bin/reference/modules/language/src/004_008_references.swg#L105-L121),
  [006_001_declaration.swg:166-171](../bin/reference/modules/language/src/006_001_declaration.swg#L166-L171)).
  The signature says `v: Struct3` and means `const &Struct3`, so a callee cannot take a scratch copy
  it is free to modify, and a caller cannot tell from the signature that the callee sees its
  storage. A small POD passed to a hot leaf function pays an indirection the signature does not
  show, which is the opposite of the trade the syntax suggests.
- Evidence: the reference states it twice, in both chapters, as a property of the declaration rather
  than of the type.
- Next step: measure before designing. Instrument or sample the `bin/` call sites where a struct
  parameter is 16 bytes or less, and check what the backend already does — if it is passing them in
  registers regardless, this is a documentation gap; if it is not, an explicit by-value spelling is
  worth a proposal, and it interacts directly with `#move`/`#fwd`
  ([006_009_custom_copy_and_move.swg](../bin/reference/modules/language/src/006_009_custom_copy_and_move.swg)).

### F-063 — `if let x = f() where cond` reads as a conjunction and is not one

- Area: language
- Found while: the same pass
- Observation: the declaration in an `if` is converted to a boolean — non-zero, non-null — and the
  `where` clause runs only if that hidden test passed
  ([005_001_if.swg:58-112](../bin/reference/modules/language/src/005_001_if.swg#L58-L112)). So the
  line has two conditions, only one of which is written down, and the unwritten one is a truthiness
  coercion the rest of the language is careful about. `if let a = 0` takes the `else` branch, which
  is a surprise for anyone reading it as a binding.
- Evidence: `if let str = retNothing() where str[0] == 's'` takes the `else` branch without
  evaluating the `where`. Confirmed under the JIT and the forged binary.
- Next step: decide whether the implicit truthiness test should be restricted to nullable-capable
  types, where "did I get something" is the intended reading and `#null` already marks it in the
  type. On a plain `s32` the same line silently means "is it non-zero", which the ternary already
  spells out — and the reference makes that exact argument when it explains why `orelse` refuses a
  non-nullable operand
  ([003_006_operators.swg:209-227](../bin/reference/modules/language/src/003_006_operators.swg#L209-L227)).

### F-064 — There are two metaprogramming systems and they do not meet

- Area: language
- Found while: the same pass
- Observation: `#ast` generates code by returning a *string* of Swag source, built with `++` or a
  byte buffer
  ([015_003_generated_code_with_ast.swg](../bin/reference/modules/language/src/015_003_generated_code_with_ast.swg)),
  while macros and mixins generate code by injecting *parsed blocks* with declared, typed, hygienic
  parameters
  ([015_002_macros.swg](../bin/reference/modules/language/src/015_002_macros.swg)). The two share
  nothing: `#ast` cannot take a `#code`, a macro cannot emit a declaration, and the string half is
  the only route to a generated *field* or *member*, which is exactly where a type error is most
  expensive to diagnose.
- Evidence: the reference's own real-world example builds struct fields by string-formatting a
  reflected field list into `"%: bool\n"`; a typo there surfaces as a parse error in generated
  source.
- Next step: no rewrite is proposed. The narrow, useful step is to find out what `#ast` is actually
  used for across `bin/` — if it is overwhelmingly "one field per reflected field", that shape
  deserves a declarative spelling, and the string escape hatch can stay for everything else.

### F-086 — `==` on two slices compares the view, not the content

- Area: language
- Found while: T-039, writing a test that a dragged payload carries the bytes a producer made
- Observation: `==` between two slices of the same element type compiles and answers whether they
  are the *same view*, not whether they hold the same bytes. Two slices with identical content over
  different storage compare `false`, silently. The neighbouring spellings all behave differently:
  `slice == "literal"` compares content and is what
  [004_002_slice.swg:98](../bin/reference/modules/language/src/004_002_slice.swg#L98) teaches, while
  `[..] u8 == string` is rejected outright with "cannot compare". So the same operator means
  content, identity, or nothing at all depending on which of three closely related types each side
  has, and only the middle one is silent.
- Evidence: an isolated probe, `swc test -d <dir>` on one standalone file:

  ```swag
  let src = cast(const [..] u8) "produced"       // 8 bytes, no terminator
  var buf: [8] u8
  for [i] in 8 do
      buf[i] = src[i]
  let copy: const [..] u8 = buf[0 to 7]
  @assert(copy == src)                          // fails
  ```

  The cost in practice was a passing-looking test that asserted the wrong thing; the fix was
  `Gui.Testing.bytesAre`, which spells the content comparison with `Memory.compare`.
- Next step: decide which of the three the operator should mean, then make the other two say so.
  Content equality is the reading a reader brings from `slice == "literal"`, so the candidates are
  making `[..] T == [..] T` compare content for a comparable `T`, or rejecting it the way
  `[..] u8 == string` already is and offering a named `Slice.contentEquals`. Either beats a silent
  identity test. Search `bin/` for `== ` between two slice-typed operands first: any existing site
  is either already relying on identity or is a latent defect of this shape.
