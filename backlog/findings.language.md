# Findings — Language

Surprises in the language itself: rules that are consistent on their own page and stop being
consistent once two pages meet, spellings that carry more than one meaning, and defaults that
read one way and behave another. These are observations against the reference
([bin/reference/modules/language/src](../bin/reference/modules/language/src)), not compiler
defects — the compiler does what the reference says. What is in question is whether the reference
should say it.

Design questions already open *by choice* — exhaustive switches, tagged unions, generic contracts,
concurrency — are the roadmap in [todo.language.md](todo.language.md) and are not repeated here.
Compiler defects are in [findings.compiler.md](findings.compiler.md). Two entries break the "the
compiler does what the reference says" premise and are kept here anyway, because for both the fix is
a sentence in the reference rather than a change to `swc`: F-097, where the safety page states the
opposite of what the guard does, and F-098, where two pages describe the same conversion in
incompatible terms.

Every entry carries an `Elsewhere` line: what the neighbouring languages do about the same
question. A wart no one else has and a convention half the industry shares are different problems,
and the line exists so the difference is on the page before anyone argues from taste. It is not an
argument that Swag should follow the majority — several entries below record a rule Swag shares
with exactly one language and keeps deliberately.

Conventions, the identifier counter, and the rest of the backlog are in [README.md](README.md).
Entries are sorted by identifier, ascending; position carries no priority.

## Binding, defaults, and local control flow

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
  Confirmed under both the JIT and the forged binary. The same indifference to names governs
  assignment: a `{width, height}` tuple takes a `{x, y}` tuple of the same field types, and
  [004_003_tuple.swg:63-82](../bin/reference/modules/language/src/004_003_tuple.swg#L63-L82)
  documents it — "tuples can be assigned to each other if their field types match, even if field
  names differ", with `#typeof(x) != #typeof(y)` asserted on the same page.
- Elsewhere: the languages that have both forms use a different delimiter for each. JavaScript
  binds `{y, x}` by *name* and `[a, b]` by position; Rust does the same, by name in `Point { y, x }`
  and by position in the tuple-struct pattern `Point(a, b)`. Swift destructures tuples with
  parentheses and requires labels where names matter. So the brace is the by-name spelling almost
  everywhere it exists, and Swag gives it to the by-position one. C# is the closest precedent for
  the fix rather than for the rule: tuple element names are cosmetic there too, and the compiler
  emits CS8123 — "the tuple element name is ignored because a different name is specified by the
  target type" — for exactly the shape this entry is about.
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
  The *type* travels the same way: `func sum3(x, y = 0.0)` gives both parameters `f32`, so one
  omitted annotation types the whole group
  ([007_001_declaration.swg:54-58](../bin/reference/modules/language/src/007_001_declaration.swg#L54-L58)).
- Elsewhere: no language combines the two halves. Go has the grouped-type parameter list
  (`func f(x, y int)`) and no default values at all. Python, C++ and C# have default values and no
  grouped form — each parameter repeats its type. Where C++ *does* allow several declarators on one
  line, `int a = 0, b;` gives the initializer to `a` alone, which is the reading this entry proposes:
  the language that looks most like Swag here already decided the other way.
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
- Elsewhere: every language that can exit a plain block makes the label mandatory, and for this
  exact reason. Java's `label: { ... break label; }` is legal, a *bare* `break` never targets a
  block, and `continue` on a non-loop label is a compile error. Rust's `'a: { break 'a v }` and
  Zig's `blk: { break :blk v; }` both require the label in the `break`. So the retargeting Swag
  performs silently is the one case those designs went out of their way to make impossible — and
  no language turns a brace block into a loop.
- Next step: the retargeting is the dangerous half. Consider requiring `break to <Name>` inside a
  *named* scope and rejecting a bare `break` whose nearest enclosing structure is an unnamed
  `#scope` that sits inside a loop — the ambiguous case is exactly that one. Check first how many
  `#scope` uses in `bin/` rely on the current reading.

## Value and conversion semantics

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
- Elsewhere: nobody narrows the signed operand. C and C++ promote both to `int` first, so `s8 + u8`
  is computed in a type that holds every value of each — the "unsigned wins" hazard exists there
  only at 32 bits and above, which is the width where it cannot be escaped. Java and C# do the same
  promotion (and Java has no unsigned type at all). Rust, Go and Zig refuse the expression: mixed
  integer types do not convert implicitly, and Zig's peer-type resolution additionally requires the
  result to hold both operands. So the two rules Swag combines — no promotion, and unsigned wins —
  are each held by a different half of the field, and no language holds both.
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
- Elsewhere: the copy is the default everywhere the sigil exists. C++ `for (auto x : v)` copies and
  `for (auto& x : v)` is the reference — the `&` selects indirection, which is exactly the reading
  Swag's `&` invites and does not have. Go's `range` copies the element into the loop variable, and
  Swift's value semantics make the binding a copy too. Rust splits the difference: `for x in &v`
  yields a reference *and* the borrow checker rejects the mutation this entry demonstrates, so the
  aliasing is visible in the type and unobservable in practice. Swag is alone in binding a live
  reference implicitly and letting the write be read back through it.
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
- Elsewhere: three languages with the same capture-by-copy model all make the writable copy a
  separate spelling. C++ copies into a `const` member unless the lambda is declared `mutable`.
  Rust requires the closure to be `FnMut` and the binding `mut`. Swift's capture list produces a
  `let`, and the stateful-counter idiom is written by shadowing with a `var` outside the closure.
  C# takes the other road entirely — captures are by reference, so mutating one changes the
  original — but there too the two behaviours are never spelled the same. The proposed
  `func|var base|` is C++'s `mutable`, moved to the capture it applies to.
- Next step: the capacity is wanted; the spelling is the question. Consider requiring `var` on a
  capture the closure body writes (`func|var base|`), which keeps the stateful-counter idiom, keeps
  a read-only capture read-only, and makes the name-shadowing visible at the capture list rather
  than at the assignment.

## Failure handling

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
- Elsewhere: every language that models errors as values makes the propagation point mandatory and
  visible — Rust's `?`, Zig's `try`, Go's explicit `if err != nil`. Swift goes further and requires
  `try` on the *call* even though propagation is implicit in the signature, precisely so a reader
  can see which calls can leave. The invisible form is the exception model — C++, Java, C# — and
  none of those also offers a visible keyword meaning the same thing, so no reader has to decide
  which of two spellings is in force. The second half has no precedent at all: no language changes
  what a keyword means inside a test.
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
- Elsewhere: the type default is nobody else's answer. Swift's `try?` yields an *optional*, so the
  failure survives in the type and cannot be mistaken for a real value — the closest spelling to
  `catch`, and the difference is the whole point. Zig writes the fallback by hand
  (`catch default`, `catch unreachable`), Rust names it (`unwrap_or_default()`, and a discarded
  `Result` trips `#[must_use]`), Go makes the discard explicit with `_`. Swag's `catch` is the only
  one that both handles and substitutes with no mark, in a language that otherwise requires
  `discard` for an unread `s32`.
- Next step: the shape is legitimate and has real uses. What it lacks is the deliberateness the rest
  of the language asks for. Consider making the discarding form its own spelling — `catch discard
  f()`, or requiring the `as err` capture and letting an unread `err` be the thing the warning layer
  reports — so that "I looked at the error and chose to ignore it" and "I did not look" stop reading
  the same.

## Overloaded syntax and declaration rules

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
- Elsewhere: two of the four roles have precedent, the generic one has none. C++ gave the quote a
  second job as a digit separator (`1'000'000`) and lives with the lexer lookbehind. Rust overloads
  it three ways — character literal, lifetime `'a`, loop label `'outer` — disambiguated by whether a
  closing quote follows, and it is a known papercut. Nobody spells generic arguments with a quote:
  C++, Java and C# use `<>` and pay for it with the `>>` and less-than ambiguities, Go chose `[]`,
  and Rust's turbofish `::<>` exists *because* generic arguments in expression position need a
  marker the parser cannot confuse — which is the same problem `'` is solving here, with the one
  character already carrying three other meanings.
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
- Elsewhere: the languages with a leading dot give it exactly one rule. Swift's `.member` is
  implicit-member lookup on the contextual type, and Zig's `.Field` is resolved by the expected
  type — one subject, decided by the type checker, with no second candidate to order against.
  Neither has a `with`. The `with` reading is the Pascal family's, and Visual Basic spells it the
  same way Swag does (`.member` inside `With`); it is also the feature whose scoping ambiguity is
  the standard cautionary tale — Wirth left it out of Oberon, and Delphi documentation still warns
  that a `with` silently captures names the reader expected to come from the enclosing scope. Swag
  stacks that reading on top of Swift's, plus `me`, plus interface scope.
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
  first one. The rule is narrower than "several defaults" and worth stating exactly, because the
  compiler is stricter than the shape suggests: an *unguarded* second `default` is rejected with
  `sema_err_switch_multiple_default`, and duplicate constant `case` values are rejected too, guard
  or no guard (`checkDuplicateConstCaseValue`). What a `where` buys is an exemption from both
  checks — `if (nodeWhereRef.isValid()) return Result::Continue;` in
  [Sema.Switch.cpp:645-653](../src/Compiler/Sema/Ast/Sema.Switch.cpp#L645-L653). So a switch holds
  any number of guarded defaults plus one plain one, and only the guarded ones are unexamined.
- Elsewhere: a second `default` is a compile error in C, C++, C#, Java and Go ("multiple defaults in
  switch"), and Swift additionally requires `default` to come last. Rust has no `default` — the
  catch-all is the `_` pattern, and a second one is reported as an unreachable pattern. So every
  neighbour that could hold two fallbacks rejects the shape outright rather than ordering them; what
  Swag has that they do not is the guard, which is what makes the plural expressible in the first
  place. Guarded arms themselves are ordinary: Rust's `match` guards and Swift's `case ... where`
  are first-match-wins exactly like these, but neither calls a guarded arm `default`.
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
- Elsewhere: one rule for both is the norm. Rust is private-by-default for items and fields alike,
  Java is package-private for both, C# is private for both, Go decides both by capitalization. The
  single precedent for two defaults is C++, where `class` members are private and `struct` members
  public — and there the choice is made by the *keyword the author picked*, not by whether the thing
  being declared is a function or a field, so a reader can still name the rule in one sentence. The
  C++ split also exists only for C source compatibility, which is not an argument available here.
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
- Elsewhere: every language a Swag user is likely to arrive from slices half-open — Python `a[1:3]`,
  Go `a[1:3]`, Rust `&a[1..3]`, JavaScript `slice(1, 3)`, C# `a[1..3]`. Rust has an inclusive form
  (`..=`) and still made the plain `..` the half-open one. The mainstream language that defaults to
  inclusive is Ruby (`a[1..3]`, with `a[1...3]` for exclusive), and its one-dot difference is a
  standing complaint; the Pascal and Ada families are inclusive but 1-based, so their ranges do not
  compose the way a slice of a slice must. Dijkstra's EWD831 is the canonical argument for the
  half-open convention, and its two points are the ones this entry lists: the length is the
  difference of the bounds, and the empty case needs no special rule.
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
- Elsewhere: the language with the identically named attribute made it deliberately inert. C#'s
  `[Flags]` changes `ToString` and nothing else — the values stay whatever the author wrote, and the
  documented convention is to assign the powers of two by hand *and* to declare a `None = 0` member,
  which is precisely the "explicit `= 0` first member" this entry proposes. Rust's `bitflags!` also
  requires every value to be written out. Java has no flags attribute; `EnumSet` packs by ordinal and
  never rewrites a declared value. So the one thing no neighbour does is let an annotation change the
  numbers a serialized enum already shipped with.
- Next step: this repository already knows what a silently-renumbered enum costs
  (`TagBin` flag values are wire format). The cheap guard is a warning when `Swag.EnumFlags` is
  added to an enum that has no explicit values *and* is reachable from a public API — or, more
  simply, requiring an explicit `= 0` first member on a flags enum, which documents the "none" case
  and makes the renumbering visible in the source.

## Strings, mixins, and macros

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
- Elsewhere: the restriction has one exact precedent and the spelling has none. Zig's `++` is also
  compile-time only — both operands must be comptime-known, and runtime text goes through
  `std.fmt` — so the design is not an oddity, it is Zig's. What Zig does not do is give that
  operator a spelling the reader arrives with another meaning for: `++` is increment in C, C++,
  Java, C# and JavaScript, and it is *runtime* concatenation in Haskell and Elixir. D chose `~` for
  concatenation precisely to keep it clear of the arithmetic operators. Rust refuses `&str + &str`
  outright and makes the allocation visible (`String + &str`, `format!`), which is the same
  "concatenation is not an operator" position Swag takes at runtime.
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
- Elsewhere: this is the C preprocessor's behaviour, and macro hygiene was invented to end it —
  Scheme's `syntax-rules` named the concept, and Rust's `macro_rules!` carries it: an identifier the
  macro writes cannot capture one the caller wrote, in either direction. D is the closest living
  relative, with `mixin template` inserting declarations into the instantiation scope, and D had to
  add named mixin scopes so a collision could be resolved at all. The sharpest comparison is
  internal, though: Swag's *macros* already chose hygiene, so the language holds both answers at
  once. Even the workaround is smaller than the C one it copies — `__COUNTER__` is unbounded, and
  `#uniq0`..`#uniq9` stop at ten.
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
- Elsewhere: nothing mainstream allows it. A `break` written inside a block passed to a Rust
  `macro_rules!` still targets the caller's loop; the macro can emit its own `break`, never rebind
  the caller's. C++ has no construct that reaches inside a lambda body to redefine a keyword. The
  nearest thing is Common Lisp's `macrolet`, which can shadow *named* blocks — and the name is
  written at the site, so a reader can see which block a `return-from` leaves. That naming is what
  the proposed `#code(break, continue)` restores. The other half of the comparison is that the
  problem is usually solved by not having the feature: languages that need user blocks in a
  library-defined loop either make the block a closure, where `break` is a compile error (Swift's
  `forEach`, Kotlin without an inline function), or make the construct part of the language.
- Next step: the capacity is what makes `opVisit` work at all and should not be removed. What is
  missing is disclosure: consider requiring the block literal to acknowledge it
  (`#code(break, continue) { ... }`, the same shape the call site already uses to rename block
  parameters), so a reader of the call site knows the keywords are not the ones they look like.

## Cross-feature semantic consistency

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
- Elsewhere: by-value is the default everywhere, and the reference is what gets a keyword. C++ copies
  unless the signature says `const&`; Rust moves or copies unless it says `&T`; Go, C# and Swift pass
  values, with C#'s `in` and Swift's `borrowing` as the opt-in indirections. D is the interesting
  one: its `in` parameters were redefined to mean `const scope ref`, letting the compiler choose the
  indirection — the same trade Swag makes — but D kept `in` as a *written* keyword, so the signature
  still says which contract is in force. Swag has no by-value spelling at all, which is the part
  none of them share: elsewhere the missing annotation means "copy", here it means "alias".
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
- Elsewhere: the two languages with this exact construct both restrict it to a type where "did I get
  something" is the only reading. Swift's `if let x = opt` accepts an *optional* and rejects anything
  else, and Rust's `if let Some(x) = opt` is a pattern match with no coercion at all — in both,
  `if let a = 0` does not compile. Swift also removed `where` from condition clauses in Swift 3 (SE-0099)
  and replaced it with a comma, on the argument that `where` read as though it introduced a different
  kind of condition than the one before it, which is the reading this entry is about. The truthiness
  half comes from C, where `if (int x = f())` does coerce — and C has no `where` to sit next to it.
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
- Elsewhere: D is the precedent for having both and is where the cost is documented — string mixins
  (`mixin("...")`) and template mixins coexist there exactly as `#ast` and macros do here, and the
  string form remains the only route to some generated declarations. Zig is the counterexample: one
  system, `comptime`, with `@Type` and `std.builtin.Type` building a struct's fields from typed
  values rather than from source text, so a mistake is a type error at the construction site. Rust
  has two macro systems but both consume and produce token streams, so a declaration-generating
  macro and an expression-generating one meet in the same representation. C# source generators emit
  strings like `#ast` — and there the diagnostic problem is the same one this entry names.
- Next step: no rewrite is proposed. The narrow, useful step is to find out what `#ast` is actually
  used for across `bin/` — if it is overwhelmingly "one field per reflected field", that shape
  deserves a declarative spelling, and the string escape hatch can stay for everything else.

## Literal typing

### F-093 — The base a number is written in decides its signedness

- Area: language
- Found while: a second reading pass over the reference, checking what the type of a literal depends
  on
- Observation: a decimal literal is an unsized constant of *unknown* sign, and a hexadecimal or
  binary one is an unsized constant of *unsigned* sign. Both adapt to an imposed type, so the
  difference is invisible wherever the target is written down — and it becomes the constant's real
  type the moment nobody writes one. `const Mask = 0xF0` is a `u32`, `const Mask = 240` is an `s32`,
  and from there the difference travels into every expression the constant enters, where F-048's
  "the unsigned type wins" rule applies it to the other operand. The reference documents the
  defaulting ("hexadecimal or binary literals default to type `u32`"
  ([003_002_number_literals.swg:38-57](../bin/reference/modules/language/src/003_002_number_literals.swg#L38-L57)))
  as a fact about magnitude, and says nothing about it being a fact about signedness.
- Evidence: `Sema.Literal.cpp` builds a decimal literal with `TypeInfo::Sign::Unknown`
  ([Sema.Literal.cpp:557](../src/Compiler/Sema/Ast/Sema.Literal.cpp#L557)) and a hex or binary one
  with `Sign::Unsigned`
  ([Sema.Literal.cpp:469](../src/Compiler/Sema/Ast/Sema.Literal.cpp#L469),
  [Sema.Literal.cpp:509](../src/Compiler/Sema/Ast/Sema.Literal.cpp#L509)). An isolated probe,
  `swc test -d <dir>`, prints two types for one value:

  ```swag
  const Mask    = 0xF0
  const DecMask = 240
  var value: s32 = 0x7F
  @print(#nameof(#typeof(value & Mask)))       // u32
  @print(#nameof(#typeof(value & DecMask)))    // s32
  ```

  A `let bound = 0xF0` behaves like the `const`. The boundary is worth stating exactly, because it
  is what makes the rule hard to see: a *bare* literal still adapts, so `x | 0b0001` on an `s32`
  compiles and yields `s32`. The signedness only survives once the literal has been named — a
  `const`, or a `let` with no annotation — and from then on it is the constant's type, not a
  literal's default. The reference's operators page writes `x = x | cast(s32) 0b0001`
  ([003_006_operators.swg:41](../bin/reference/modules/language/src/003_006_operators.swg#L41))
  where the plain form compiles, which is some evidence that the boundary is not obvious even to the
  page documenting the operators.
- Elsewhere: C is the source of the rule and stops short of it. A decimal constant with no suffix
  takes its type from a signed-only list (`int`, `long`, `long long`), while an octal or hex one
  takes it from a list that also holds the unsigned types — so `0xFFFFFFFF` is `unsigned int` where
  `4294967295` is `long`, but a small `0xFF` is a plain `int` like any other, because the list is
  consulted in order and the first entry fits. Swag applies the unsigned reading at every magnitude.
  Nobody else applies it at all: `0xFF` is `i32` in Rust, `int` in C# and Java, an untyped constant
  in Go, and a signless `comptime_int` in Zig, where the base is purely notation.
- Next step: decide whether the base should pin the sign, or only the width. The cheap experiment is
  to build `swc` with the hex and binary paths using `Sign::Unknown` like the decimal one and run
  the suites: what breaks is the set of places relying on a bare `0x...` being unsigned, and that
  number is the argument either way. If the rule stays, F-048's proposed warning at a
  mixed-signedness operator covers the damage, and the `#print`-visible surprise is worth one
  sentence on the number-literals page.
- Related: [F-048](#f-048--mixing-a-signed-and-an-unsigned-operand-of-the-same-width-converts-the-signed-one)
  is what turns the difference into arithmetic.

### F-094 — The width of an inferred float literal depends on its digits

- Area: language
- Found while: the same pass
- Observation: the reference states plainly that "by default, floating-point literals are of type
  `f32`", twice, and contrasts it with C
  ([003_002_number_literals.swg:99-111](../bin/reference/modules/language/src/003_002_number_literals.swg#L99-L111)).
  What actually happens is narrower: an untyped float literal is an `f32` only when its decimal text
  is exactly representable in `f32`, and an `f64` otherwise. So the rule holds for `1.5` and fails
  for `0.1`, `3.14` and most decimals anyone writes — and two locals initialized on adjacent lines
  can have different types with nothing in the source saying so. The choice is defensible on its own
  terms: it is the rule that never loses a digit the author wrote. What it is not is "the default
  is `f32`".
- Evidence: an isolated probe, `swc test -d <dir>`, same result under the JIT and the forged binary:

  ```
  1.5 = f32      16777216.0 = f32      16777217.0 = f64
  0.1 = f64      3.1415927  = f64      3.141592653589793 = f64
  ```

  `let sum = 1.5 + 16777217.0` is therefore an `f64`, and `#typeof(a) == #typeof(b)` is false for two
  literals that read alike. The reference's assertion `#assert(#typeof(a) == f32)` passes only
  because its example is `1.5`
  ([003_002_number_literals.swg:82-86](../bin/reference/modules/language/src/003_002_number_literals.swg#L82-L86));
  the same assertion two lines below it, on the `let b = 0.11` of the same test, would fail — and
  the page does not make it.
- Elsewhere: no language makes a literal's width depend on its value. C, C++, Java, C#, JavaScript
  and Swift all default to 64-bit; Go's untyped float constant carries arbitrary precision and
  becomes `float64` when it needs a type; Rust infers `f64`; Zig's `comptime_float` is 128-bit and
  resolves to `f64`. Where a language does police the digits it does so at the *annotation* and as a
  diagnostic — Rust rejects a literal outside the range of the type it was annotated with — never by
  letting the digits choose how wide the variable is. So the "widen instead of round" rule is
  genuinely Swag's own, and the 32-bit default it is attached to is already unusual on its own.
- Next step: fix the page first, because it is wrong today for the common case and one paragraph
  fixes it — state the rule as "the narrowest of `f32` and `f64` that holds the written value
  exactly". Then decide whether the value-dependence should be visible in a second way: an
  inferred-`f64` literal in a context the author expected to be `f32` changes arithmetic width in a
  hot loop, and the only current way to see it is `#typeof`. A warning is the wrong tool here — a
  query on the doc page, and the habit of writing `'f32` where the width matters, is probably
  enough. Measure how many `bin/` locals are inferred from a float literal before deciding.

## Conversions the call site does not show

### F-095 — A blank `cast()` performs whatever conversion the target turns out to need

- Area: language
- Found while: the same pass
- Observation: `cast()` with no type "allows the compiler to infer the target type"
  ([003_007_cast.swg:20-45](../bin/reference/modules/language/src/003_007_cast.swg#L20-L45)), and
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
  @print(takeS32(cast() 1.9), " ", takeU8(cast() 1.9))     // 1 1
  ```

- Elsewhere: target-inferred conversion exists, but never lossy and never as one spelling for every
  kind of loss. Rust's `.into()` is inferred from the target and is restricted to `From`
  implementations, which are lossless by contract; the lossy conversion is `as`, and `as` always
  names its type. Zig infers the destination of `@intCast` from context — the closest analogue —
  but the conversion kind is in the name (`@intCast`, `@floatFromInt`, `@truncate`), and an
  out-of-range `@intCast` panics in safe builds instead of arriving as a value. C++ has no
  type-inferred cast at all, and the guidance that produced `static_cast` was precisely that a cast
  should say what it does. Swag's `cast()` is one token covering the whole set.
- Next step: count the `cast()` uses in `bin/` and sort them by what the conversion turned out to
  be. If they are overwhelmingly widening or same-kind, the narrow rule worth proposing is that a
  blank `cast()` performs only the conversions that would have been implicit anyway plus the
  same-kind narrowing, and that a float-to-integer truncation needs its type written. That keeps the
  convenience where it is a convenience and removes it where it is a silent behaviour change.

### F-096 — A `#move` parameter accepts a plain value and copies it

- Area: language
- Found while: the same pass
- Observation: `#move` in a parameter position is documented as part of the signature — "they select
  how an argument reaches the callee"
  ([002_008_sigils.swg:144-155](../bin/reference/modules/language/src/002_008_sigils.swg#L144-L155)).
  At the call site it selects nothing: a `#move` parameter also accepts a plain argument, and the
  compiler materializes a call-site copy and moves *that*
  ([006_009_custom_copy_and_move.swg:93-98](../bin/reference/modules/language/src/006_009_custom_copy_and_move.swg#L93-L98)).
  So a signature that reads "this callee consumes your value" is satisfied by a caller that keeps
  it, and the difference between the two call styles is one hidden copy of the whole aggregate,
  visible in the source as nothing at all. The capacity is deliberate and `#fwd` exists to avoid the
  copy; what is not marked anywhere is *which* call paid for it.
- Evidence: the reference measures the copy itself. With `Vector3.opPostCopy` adding 1 and
  `opPostMove` adding 2, `assign(&b, a)` through a `#move` parameter yields `4, 5, 6` — one copy then
  one move — while `assign(&b, #move a)` yields `3, 4, 5`
  ([006_009_custom_copy_and_move.swg:141-162](../bin/reference/modules/language/src/006_009_custom_copy_and_move.swg#L141-L162)).
- Elsewhere: the two ends of the field are both represented, and Swag is at one of them. C++ makes
  the refusal the whole point: a `T&&` parameter cannot bind an lvalue, so a caller who still owns
  the value must write `std::move` and the transfer is visible at every call site. Rust is stricter
  still — a by-value parameter moves, the source becomes unusable, and there is no copy to insert.
  Swift went the other way with `consuming` parameters: when the caller still needs the value the
  compiler inserts a copy, exactly as here. So the behaviour has a precedent, and it is the
  precedent from the language with implicit copies everywhere else; in Swag, where `#move` is
  written at the call site in every example, the same rule reads as a guarantee it is not.
- Next step: decide whether the copy should be reportable rather than whether it should exist.
  The call site already distinguishes the two forms syntactically, so a warning at a plain argument
  passed to a `#move` parameter of a type with `opPostCopy` is mechanical, names the exact line, and
  has a one-token fix. Check first whether `bin/` relies on the copy path through lambdas and
  interface methods, where the reference says a single `#move` function is what makes both styles
  work at all — those call sites are the ones a warning must not drown.

## Where a page and the compiler disagree

### F-097 — The `.Switch` runtime guard covers only `switch #complete`, and the safety page says the opposite

- Area: language
- Found while: the same pass, reconciling the safety chapter with
  [T-009](todo.language.md#t-009--enum-switches-are-silently-non-exhaustive)
- Observation: the safety page states that "without `switch #complete`, an unmatched value reaches
  no case and Swag panics"
  ([013_002_safety.swg:248-273](../bin/reference/modules/language/src/013_002_safety.swg#L248-L273)).
  The guard is installed under the exact opposite condition: `setupSwitchRuntimeSafety` returns
  immediately unless the switch *is* `#complete`. A plain enum switch missing a case therefore falls
  through to nothing, in every configuration, which is what T-009 says and what the roadmap is
  measured against — while a reader of the safety page believes debug builds already report it. The
  guard that does exist is the useful one and should be described: on a `#complete` switch every
  declared value has an arm, so the only value that can reach no case is one outside the declared
  set, and that is what panics.
- Evidence: `if (!payload.isComplete) return Result::Continue;`
  ([Sema.Switch.cpp:31-37](../src/Compiler/Sema/Ast/Sema.Switch.cpp#L31-L37)), where `isComplete`
  is set from `AstModifierFlagsE::Complete`
  ([Sema.Switch.cpp:499-510](../src/Compiler/Sema/Ast/Sema.Switch.cpp#L499-L510)). An isolated
  probe, `swc test -d <dir>` in `fast-debug`, returns `-1` rather than panicking:

  ```swag
  enum Color { Red, Green, Blue }

  func colorRank(color: Color)->s32
  {
      switch color
      {
      case .Red:   return 1
      case .Green: return 2
      }

      return -1
  }

  #test { @assert(colorRank(Color.Blue) == -1) }
  ```

  The guard that *does* exist was observed firing while probing F-101: a `#complete` switch handed a
  value outside its enum's declared set reports "complete switch received a value not covered by its
  cases". So the mechanism works and only its documented trigger is wrong.
- Elsewhere: not applicable to the contradiction, which is a documentation defect. On the underlying
  rule, the field splits cleanly and T-009 already holds the decision: Rust, Swift and Kotlin require
  exhaustiveness at compile time, Zig requires an `else` on a switch that does not cover its tag,
  and C, C++, C#, Java and Go let an unmatched value fall through — which is what Swag does today.
- Next step: fix the page, in the direction the code chose: describe the guard as the one that
  catches a value outside an enum's declared set on a `#complete` switch. Whether a plain switch
  should also be guarded is T-009's decision and must not be settled by a sentence in the safety
  chapter. Add the probe above to the `sanity` or `native` suite as a positive so the two statements
  cannot drift apart again.
- Related: [T-009](todo.language.md#t-009--enum-switches-are-silently-non-exhaustive)

### F-098 — `any` is a box on one page and a reference on another

- Area: language
- Found while: the same pass, checking which of the two readings the compiler implements
- Observation: the `any` chapter opens with a warning that it is "**not** a variant. It holds a
  reference to an existing value plus its runtime type info"
  ([004_009_any.swg:3-10](../bin/reference/modules/language/src/004_009_any.swg#L3-L10)), and the
  intrinsics chapter says "ordinary assignment **boxes** a value as `any`"
  ([008_003_value_and_type_intrinsics.swg:37-42](../bin/reference/modules/language/src/008_003_value_and_type_intrinsics.swg#L37-L42)).
  The two words carry opposite lifetime contracts, and the difference is the whole question a reader
  has when they store an `any` in a field: a box owns a copy and outlives its source, a reference
  dies with it. The compiler implements the reference reading — and, per F-105, does not yet judge
  it, so the wrong belief is not caught by the build either. The same page also groups `@mkslice`
  and `@mkstring` under "constructing non-owning views" with an explicit warning that the result
  must not outlive its backing memory; `@mkany` sits under the next heading with no such line,
  although it takes an address exactly the same way.
- Evidence: the two sentences, two chapters apart. `@mkany(&value, s32)` on the intrinsics page takes
  an address, which settles which reading is the implemented one.
- Elsewhere: every neighbour with a dynamic any-type copies. Go's `any` stores a copy of the value in
  the interface, C# and Java box onto the heap, Swift's `Any` holds a value. Rust is the one that
  offers both and keeps them apart in the type: `Box<dyn Any>` owns, `&dyn Any` borrows and carries a
  lifetime. So Swag's `any` behaves like Rust's `&dyn Any` while being spelled like Go's `any` — the
  name a reader arrives with is the one that promises a copy.
- Next step: pick the word and use it on both pages; "boxes" is the one to drop, since it is the one
  the implementation contradicts. Then give the `@mkany` paragraph the same non-owning warning its
  `@mkslice` neighbour already carries, and say on the `any` page that an `any` is a view for the
  purposes of the borrow rules — which is what
  [013_004_borrowing.swg:5-8](../bin/reference/modules/language/src/013_004_borrowing.swg#L5-L8)
  already lists, without the `any` page ever pointing at it.
- Related: F-105 in [findings.safety.md](findings.safety.md), the escape the rule currently misses.

## Declining and leaking

### F-100 — A `catch ... as err` capture is a declaration that leaks into the enclosing scope

- Area: language
- Found while: the same pass
- Observation: `as err` "binds a fresh local ... visible in the enclosing scope, after the catch, so
  each capture in a given scope needs its own name"
  ([013_001_error_management.swg:24-30](../bin/reference/modules/language/src/013_001_error_management.swg#L24-L30)).
  The declaration is written inside an expression, in the middle of an initializer, and its effect
  reaches outward past the statement it appears in. Nothing else in the language does this: `if let`
  scopes its binding to the branch, `for` to the body, `switch ... as` to the case. The consequence
  the reference states — two catches in one scope collide — is the visible half; the invisible half
  is that the name is live for the rest of the block whether or not it was read, so the "did I look
  at the error" question F-052 wants to ask has nowhere to be asked from.
- Evidence: the reference's own paragraph, and its `blockCatchCode` example, where `err` is declared
  by a `catch { ... } as err` block and tested two statements later
  ([013_001_error_management.swg:148-160](../bin/reference/modules/language/src/013_001_error_management.swg#L148-L160)).
- Elsewhere: every language with an error capture scopes it inward. Zig's `catch |e|` binds `e` to
  the handler block, Swift's `catch let e` to the `catch` body, Rust binds in the match arm. Go is
  the closest to Swag's shape and it is not an exception: `v, err := f()` is an ordinary declaration
  written in declaration position, not smuggled out of an expression — and Go's rule that `err` must
  be re-declared or reassigned per scope is the same collision problem, solved by making the
  declaration visible. Even the constructs that deliberately extend a binding's reach — C's
  `for (int i = ...)`, C++17's `if (auto x = f(); x)` — scope inward, never outward.
- Next step: this is worth settling together with F-052, since both are about what happens to a
  caught error nobody looked at. The narrow question here is whether the capture could scope to the
  statement plus the statements dominated by its test — which is what every use in the reference
  actually needs — and whether anything in `bin/` reads an `err` outside the block that produced it.
  Count that first; if the answer is nothing, the change is a scope narrowing with a mechanical
  migration.
- Related: [F-052](#f-052--catch-without-a-capture-substitutes-the-type-default-and-says-nothing)

## Types and bindings that do not own what they name

### F-101 — An enum that imports another's values does not own them

- Area: language
- Found while: the same pass, checking what `using` inside an `enum` actually produces
- Observation: `using BasicErrors` inside `enum MyErrors` is documented as importing values, with the
  note that they "keep their original enum type"
  ([004_004_enum.swg:189-221](../bin/reference/modules/language/src/004_004_enum.swg#L189-L221)).
  That note is doing more work than it looks. The import is a name-lookup alias and nothing else:
  `MyErrors.FailedToLoad` is a `BasicErrors`, `@countof(MyErrors)` does not count it, and
  `for value in MyErrors` does not visit it. So an enum spelled as the union of two sets behaves as
  neither — it answers to every name, owns only its own values, and any exhaustive treatment of it
  (a `switch #complete`, a `[MyErrors] T` table, a reflected walk) silently covers the smaller set.
- Evidence: an isolated probe, `swc test -d <dir>`, on the reference's own declaration pair:

  ```
  typeof(MyErrors.FailedToLoad) = BasicErrors      typeof(MyErrors.NotFound) = MyErrors
  countof(MyErrors) = 1                            countof(BasicErrors) = 2
  for value in MyErrors  ->  1 iteration
  ```

  The implementation is a scope merge — `sema.curScope().addUsingSymMap(usingSymMap)` and
  `ownerEnum.addUsingSymMap(usingSymMap)`
  ([Sema.Enum.cpp:205-219](../src/Compiler/Sema/Ast/Sema.Enum.cpp#L205-L219)) — so the members are
  reachable through the owner and belong to the imported enum, exactly as observed.

  `switch #complete` follows the same count, which is where it starts to matter. A switch over a
  `MyErrors` is accepted as complete with a single `case .NotFound` — one arm for a type that spells
  three names — and the function needs no `return` after it, because the switch is exhaustive as far
  as the flow analysis is concerned. Feeding it an imported value is caught, but only by the runtime
  guard:

  > error: complete switch received a value not covered by its cases

  That is the `.Switch` guard of F-097, which `release` turns off. There, the same call falls off
  the end of a function with a declared return type.
- Elsewhere: no language lets one enum absorb another's members, so the comparison is with what is
  offered instead. C++20's `using enum` brings the names into a scope for unqualified use, and it is
  explicitly a lookup convenience: the members keep their own type, and the importing entity is a
  scope rather than an enum claiming to hold them. Rust and Swift make the union case a real type —
  a variant that wraps the other enum — so the count and the match arms follow. Java has no
  extension at all, by design. The shape Swag has is C++'s `using enum` written *inside* a type
  declaration, where the name of the construct promises the Rust answer.
- Next step: take the `#complete` half first, because it is a correctness question and the rest is a
  design one. `#complete` currently means "covers every value the owner declared itself", which is
  not what the word promises on a type whose members include the imported names; decide whether it
  should require the imported values too, or whether an enum carrying a `using` should be refused by
  `#complete` outright until the design question below is settled. Either way the answer must not be
  "the runtime guard catches it", since that guard is off in `release`.

  Then decide what the construct is. If it is a lookup convenience, say so on the page in the words
  C++ uses for `using enum`, and stop calling it importing *values*. If it is meant to be a union,
  `@countof`, iteration and the member type all have to follow, and the imported members have to be
  re-typed on import — at which point the base-type restriction the page already imposes is the
  beginning of that design rather than an implementation detail.

### F-102 — `[2, 2] T` and `[2][2] T` are different types indexed the same way

- Area: language
- Found while: the same pass
- Observation: the two spellings produce unrelated types that do not convert to each other, and the
  reference warns about it
  ([004_001_array.swg:159-184](../bin/reference/modules/language/src/004_001_array.swg#L159-L184)).
  What makes it a trap rather than a choice is that `[i, j]` indexes both. The one place a reader
  could notice which type they have — the use site — reads identically for the two, so the
  distinction is visible only in the declaration and only if it is nearby. The advice the page gives
  is to "pick one spelling per API and keep it", which is the shape of a rule the compiler could
  enforce and does not.
- Evidence: the reference's own example declares `[2, 2] s32` and `[2][2] s32` side by side and
  indexes both with `array[0, 1]`.
- Elsewhere: C# is the language with the same pair, and it kept them apart at the use site: `int[,]`
  is indexed `a[i, j]` and `int[][]` is indexed `a[i][j]`, so the spelling of the access tells you
  which one you have. Everyone else has one form as the array type — C, C++, Java, Rust and Go build
  the rectangular case out of nested arrays, while Fortran and Ada make it a single type with a
  single spelling — and in each case there is nothing to confuse. Swag is alone in offering both
  *and* giving them one access syntax.
- Next step: measure before proposing anything: count `[a, b] T` versus `[a][b] T` declarations in
  `bin/`. If one form is vestigial, deleting it is better than documenting it. If both are used, the
  cheap guard is a warning when the two appear in one module's public surface, since the cost lands
  on the consumer who cannot see the declarations side by side.

### F-103 — The bracketed `for` binding names a position, not an index

- Area: language
- Found while: the same pass, reading the custom-iteration chapter after the `for` chapters
- Observation: brackets are introduced as the index spelling — "put a name in brackets to bind the
  index without binding the element"
  ([005_003_for_elements.swg:23-27](../bin/reference/modules/language/src/005_003_for_elements.swg#L23-L27)).
  Over a custom iterator they mean the *second block parameter*, whatever that parameter is. In the
  reference's own `opVisitPairs`, `for #Pairs left, [right] in windows` binds `right` to the second
  element of a pair, and the brackets say nothing about indices
  ([006_008_custom_iteration.swg:216-262](../bin/reference/modules/language/src/006_008_custom_iteration.swg#L216-L262)).
  A reader who learned the built-in rule reads that line as an index binding and gets a value.
- Evidence: the two pages, and the fact that `for [i] in myStruct` over a struct whose `opVisit`
  declares `(item, index)` binds the second parameter, which happens to be called `index` in that
  example and does not have to be
  ([006_008_custom_iteration.swg:84-93](../bin/reference/modules/language/src/006_008_custom_iteration.swg#L84-L93)).
- Elsewhere: no language marks the index with a sigil, so none has this collision. Python, Rust,
  Swift and JavaScript all destructure a pair with ordinary tuple syntax — `for i, x in
  enumerate(v)`, `for (i, x) in v.iter().enumerate()` — and the index is present only because
  something produced it, which makes the second name obviously positional. The one thing they all
  keep is that the binding form does not claim a role: `(a, b)` says "two things", not "an index and
  an element".
- Next step: the honest fix may be naming rather than syntax. A custom visitor already declares its
  block parameters, and `#inject` binds them by name, so the call site could name them too —
  `for left, right: ... in windows`, or a named form for the second slot — leaving brackets to mean
  the index over built-in collections where they are unambiguous. Check first how many `opVisit`
  variants in `bin/` declare a second parameter that is not an index; if `opVisitPairs` in the
  reference is the only one, this is a documentation sentence, not a syntax change.

### F-104 — The `[i]` binding has three different integer types depending on what is iterated

- Area: language
- Found while: the same pass, after F-103
- Observation: one spelling, three types. Binding the index over a collection gives a `u64`, over a
  counted loop a `u32`, and over a range an `s32`. Nothing at the use site distinguishes the three,
  and the difference is exactly the one F-048 turns into arithmetic: an index that is unsigned in
  two of the three forms, next to a `@countof` that is always `u64` and a signed computation that is
  `s32`. The reference asserts the collection case (`#assert(#typeof(index) == u64)`
  ([005_003_for_elements.swg:29-40](../bin/reference/modules/language/src/005_003_for_elements.swg#L29-L40)))
  and never mentions that the other two forms answer differently.
- Evidence: an isolated probe, `swc test -d <dir>`, printing `#nameof(#typeof(index))` in three
  neighbouring loops over the same data:

  ```
  for [index] in values   ->  u64
  for [index] in 3        ->  u32
  for [index] in 0 to 2   ->  s32
  ```

  The reference already documents the consequence without naming the cause: it warns not to write
  `for [i] in 0 to count - 1` on an unsigned counter, because `count - 1` wraps when `count` is zero
  and only the overflow guard reports it
  ([005_002_for.swg:161-180](../bin/reference/modules/language/src/005_002_for.swg#L161-L180)).
- Elsewhere: the question mostly does not arise, because the index is a value someone produced
  rather than a binding the loop invents. Rust's `enumerate()` yields `usize` and `0..n` yields
  whatever `n` is, so the type is written in the expression; Go's `range` index is `int` — signed —
  for every form, which is the property Swag lacks; Python has one integer type; C# `for` and
  `Enumerable.Range` both give `int`. Where a language does use an unsigned index everywhere,
  as C++ does with `size_t`, the uniformity is the point, and the `i >= 0` loop bug that comes with
  it is a single well-known hazard rather than a per-form one.
- Next step: decide whether the three should agree, and on what. `u64` matches `@countof` and is the
  only one that cannot overflow on a real collection; `s32` is the one that makes `i - 1` behave.
  The cheapest useful step first: add the three-way result above to the `for` chapter, since a
  reader today has no way to know which one they have without `#typeof`. Then check whether a
  counted `for [i] in N` could simply take the type of `N`, which would remove one of the three
  without touching the other two.

## What equality compares

### F-106 — Equality accepts fewer slice operand pairs than assignment does

- Area: language
- Found while: F-087, probing which operand pairs `[..] T == [..] T` accepts now that it compares content
- Observation: a comparison never writes through its operands, yet equality between two slices demands
  that both types match exactly. `[..] u8 == const [..] u8` is rejected with "cannot compare", although
  the very same value converts implicitly when it is passed to a `const [..] u8` parameter, and
  `slice == [1, 2, 3]` is rejected although the literal converts implicitly on assignment. The
  neighbouring rules already say otherwise: `checkEqualEqual` accepts any pointer pair whatever their
  `const`, and `widenNullableCompareOperand` widens a bare operand to `#null` precisely because a
  comparison cannot write. Slices are the odd one out, and arrays and structs share the gap.
- Evidence: this predates the F-087 fix — a compiler built before it rejects the same three lines.
  Isolated probe, `swc test -d <dir>` on one standalone file:

  ```swag
  var bytes: [4] u8       = [1, 2, 3, 4]
  const cst: const [..] u8 = [1, 2, 3, 4]
  @assert(bytes[to] == cst)                                 // cannot compare '[..] u8' with 'const [..] u8'
  @assert(bytes[to] == [1'u8, 2'u8, 3'u8, 4'u8])            // cannot compare with 'array literal'

  var maybe: #null const [..] u8
  @assert(maybe == bytes[to])                               // cannot compare '#null const [..] u8' with '#null [..] u8'
  ```

- Next step: decide whether equality unifies its operands the way assignment does, for every aggregate
  rather than for slices alone. `widenNullableCompareOperand` in
  [Sema.Relational.cpp](../src/Compiler/Sema/Ast/Sema.Relational.cpp) is the shape to copy: widen the
  narrower operand, then let the regular promotion unify the rest. Check what `[4] u8 == const [4] u8`
  and `S == const S` already do first — a slices-only rule would trade one inconsistency for another.

### F-107 — A struct compares its bytes, so a string or slice member compares as a view

- Area: language
- Found while: F-087, checking where else content equality stops
- Observation: `==` between two structs without an `opEquals` compares their storage byte for byte,
  so a member whose own `==` compares content does not. Two structs holding equal text over
  different buffers answer `false` while the two members answer `true`, and nothing says so at the
  call site. This is not new for `string` — it is what byte comparison has always meant — but it is
  now the only place a slice still compares as the view it is, which makes the split visible:
  `a.text == b.text` and `a == b` disagree about the same bytes.
- Evidence: isolated probe, `swc test -d <dir>`, identical under the JIT and from the binary:

  ```swag
  struct Holder { text: string, tag: s64 }
  var g_holders: [2] Holder = undefined
  var g_left, g_right: [3] u8

  #[Swag.Optimize(false)]
  func eqHolder(a, b: Holder)->bool => a == b

  g_left  = ['a', 'b', 'c']
  g_right = ['a', 'b', 'c']
  g_holders[0].text = cast(string) @mkslice(cast(const [*] u8) &g_left[0], 3'u64)
  g_holders[1].text = cast(string) @mkslice(cast(const [*] u8) &g_right[0], 3'u64)

  @assert(g_holders[0].text == g_holders[1].text)     // passes
  @assert(eqHolder(g_holders[0], g_holders[1]))       // fails
  ```

  A `const [..] u8` member behaves the same way. `emitAggregateEqualsBool` in
  [CodeGen.Relational.cpp](../src/Compiler/CodeGen/Ast/CodeGen.Relational.cpp) is the byte compare
  in question.
- Next step: measure the blast radius before choosing. Count the structs under `bin/` that hold a
  `string` or a slice and are compared with `==`; a member-wise compare is only worth its cost if
  that set is small and the current answer is wrong for it. Padding is the other half of the
  question: the byte compare already reads padding bytes, so a member-wise rule would change more
  answers than the string ones. Whatever is decided, say it in
  [003_006_operators.swg](../bin/reference/modules/language/src/003_006_operators.swg) — today the
  reference states neither rule.
