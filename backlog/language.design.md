# Language Backlog

This backlog covers the Swag language and its syntax, measured against what it competes
with: Rust, Go, Zig, Swift, D, and the self-hosted tier of Jai and Odin. The compiler that
implements it is [compiler.core.md](compiler.core.md).

Compiler defects stay in [compiler.core.md](compiler.core.md). This file keeps deliberate language design,
surprising but specified rules, their comparative evidence, and their next decisions together.

Entries are ordered by decreasing value, not by decreasing effort. An entry disappears when it
ships; history lives in git, not here.

---

## Data modeling and exhaustive control flow

### B-174 — Enum switches are silently non-exhaustive

- A `switch` over a three-value enum that handles two of them compiles with no error, no warning,
  and no `default`; the third value simply falls through to nothing. Exhaustiveness exists but is
  opt-in through `switch #complete`
  ([005_005_switch.swg:178](../bin/reference/modules/language/src/005_005_switch.swg#L178)).
- Every language that made exhaustiveness the default — Rust, Swift, Kotlin, and Zig for tagged
  unions — did so because the failure is invisible at the time it is introduced and shows up when
  a value is *added* to the enum later, in code nobody re-read.
- The decision to make: whether `#complete` should be the default for enum switches, with an
  explicit `else` as the opt-out. That is a breaking change with a mechanical migration, and it
  rides on the warning policy layer that now exists (`#[Swag.Warning]`, `cfg.warnings`,
  `--warn-*`) — without one, the only two answers available are "error" and "silence".

### B-175 — There is no tagged union

- `union` is C-style and untagged: all fields share offset 0 and reading a field that was not the
  one written is legal and meaningless
  ([004_006_union.swg](../bin/reference/modules/language/src/004_006_union.swg)). `any` covers the
  dynamic case. There is nothing in between — no discriminated union, no payload-carrying enum,
  no destructuring in `case`.
- Consequence: a sum type has to be hand-encoded as a tag next to an untagged union, and the
  invariant lives in a comment. `pixel`'s painter command is exactly that — `id: CommandId`
  followed by `using params: union`, documented as "Command-specific payload selected by `id`;
  inactive members must not be read"
  ([painter.swg:147-149](../bin/std/modules/pixel/src/painter/painter.swg#L147-L149)). Nothing
  checks that sentence. Rust, Swift, Zig and modern C# all consider the checked version table
  stakes; it is arguably the single largest expressiveness gap in the language.
- It interacts with B-174 (a tagged union is where exhaustive matching earns its keep) and with
  the error-handling design already shipped (`fail`/`try`/`catch`), which chose a different axis
  and should not be re-litigated by the same feature.

## Generic contracts and execution semantics

### B-176 — The generic instantiation chain omits the call site

- The diagnostic is already better than most: it reports the error inside the generic *and*
  attaches a note naming the specialization (`while checking generic function 'doubleIt' with
  T = Point`). What it does not do is name the call site that caused the instantiation — the one
  line the user has to change. Adding that frame to the instantiation chain is a small, immediate
  win.
- Related: B-257

### B-257 — Generic constraints cannot name a required interface

`where` is a compile-time boolean over generic parameters
([009_003_where_constraints.swg](../bin/reference/modules/language/src/009_003_where_constraints.swg)).
There is no declaration-site way to state that `T` must provide a member or satisfy a named
contract, so a missing operation fails only inside an instantiation. Decide named contracts versus
predicates after B-176 makes the current model's diagnostics complete.

- Related: B-176

### B-177 — The concurrency model is undecided

- The library omissions are split into B-195 (tasks), B-286 (channels), B-287 (condition
  variables), and B-288 (asynchronous I/O). This entry owns only the language-level concurrency
  decision that must precede those API choices.
- Go answered with goroutines and channels, Rust with `async` and a futures machinery that reaches
  into the type system, .NET with `Task`. Each answer changed the language, not just the library.
- The forcing function is already scheduled: [B-190](std.core.md#b-190--no-blocking-tcp-sockets) puts
  non-blocking sockets on the path, and deciding this *under* that pressure is how languages end up
  with two concurrency models. Decide it early and deliberately, and record the decision here.

---

The entries below were open investigations when the unified backlog was introduced. Their `F-*`
identifiers remain permanent; update their next action in place as the evidence matures. They retain
their former order until re-triaged, so position in this imported block carries no priority claim.

Surprises in the language itself: rules that are consistent on their own page and stop being
consistent once two pages meet, spellings that carry more than one meaning, and defaults that
read one way and behave another. These are observations against the reference
([bin/reference/modules/language/src](../bin/reference/modules/language/src)), not compiler
defects — the compiler does what the reference says. What is in question is whether the reference
should say it.

Compiler defects are in [compiler.core.md](compiler.core.md).

Every entry carries an `Elsewhere` line: what the neighbouring languages do about the same
question. A wart no one else has and a convention half the industry shares are different problems,
and the line exists so the difference is on the page before anyone argues from taste. It is not an
argument that Swag should follow the majority — several entries below record a rule Swag shares
with exactly one language and keeps deliberately.

## Binding, defaults, and local control flow

### B-580 — Positional destructuring binds by position even when every name matches a field

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

### B-581 — One default in a grouped declaration silently defaults every name in the group

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

## Value and conversion semantics

### B-582 — Mixing a signed and an unsigned operand of the same width converts the signed one

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

## Failure handling

### B-583 — Error propagation has three spellings, one of them invisible and one context-dependent

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

### B-584 — `catch` without a capture substitutes the type default and says nothing

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

### B-585 — The apostrophe carries three unrelated roles

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

### B-586 — The leading dot carries four unrelated roles

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
  diagnostic is already a separate finding (B-571 in
  [compiler.core.md](compiler.core.md)).
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

### B-587 — A `switch` accepts several `default` clauses

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

### B-588 — The slice upper bound is inclusive

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

### B-589 — `#[Swag.EnumFlags]` silently renumbers every member

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

### B-590 — `++` is compile-time only, and there is no runtime string concatenation at all

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

### B-591 — Mixins resolve their body in the caller's scope

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

### B-592 — A macro can redefine `break` and `continue` inside the block the caller wrote

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

### B-593 — `if let x = f() where cond` reads as a conjunction and is not one

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

### B-594 — There are two metaprogramming systems and they do not meet

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

### B-600 — The base a number is written in decides its signedness

- Area: language
- Found while: a second reading pass over the reference, checking what the type of a literal depends
  on
- Observation: a decimal literal is an unsized constant of *unknown* sign, and a hexadecimal or
  binary one is an unsized constant of *unsigned* sign. Both adapt to an imposed type, so the
  difference is invisible wherever the target is written down — and it becomes the constant's real
  type the moment nobody writes one. `const Mask = 0xF0` is a `u32`, `const Mask = 240` is an `s32`,
  and from there the difference travels into every expression the constant enters, where B-582's
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
  Swag.print(#nameof(#typeof(value & Mask)))       // u32
  Swag.print(#nameof(#typeof(value & DecMask)))    // s32
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
  number is the argument either way. If the rule stays, B-582's proposed warning at a
  mixed-signedness operator covers the damage, and the `#print`-visible surprise is worth one
  sentence on the number-literals page.
- Related: [B-582](#b-582--mixing-a-signed-and-an-unsigned-operand-of-the-same-width-converts-the-signed-one)
  is what turns the difference into arithmetic.

### B-601 — The width of an inferred float literal depends on its digits

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

### B-602 — A blank `cast()` performs whatever conversion the target turns out to need

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
  Swag.print(takeS32(cast() 1.9), " ", takeU8(cast() 1.9))     // 1 1
  ```

- Elsewhere: target-inferred conversion exists, but never lossy and never as one spelling for every
  kind of loss. Rust's `.into()` is inferred from the target and is restricted to `From`
  implementations, which are lossless by contract; the lossy conversion is `as`, and `as` always
  names its type. Zig infers the destination of `@intCast` from context — the closest analogue —
  but the conversion kind is in the name (`@intCast`, `@floatFromInt`, `Swag.truncate`), and an
  out-of-range `@intCast` panics in safe builds instead of arriving as a value. C++ has no
  type-inferred cast at all, and the guidance that produced `static_cast` was precisely that a cast
  should say what it does. Swag's `cast()` is one token covering the whole set.
- Next step: count the `cast()` uses in `bin/` and sort them by what the conversion turned out to
  be. If they are overwhelmingly widening or same-kind, the narrow rule worth proposing is that a
  blank `cast()` performs only the conversions that would have been implicit anyway plus the
  same-kind narrowing, and that a float-to-integer truncation needs its type written. That keeps the
  convenience where it is a convenience and removes it where it is a silent behaviour change.

### B-603 — A `#move` parameter accepts a plain value and copies it

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

## Declining and leaking

### B-604 — A `catch ... as err` capture is a declaration that leaks into the enclosing scope

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
  at the error" question B-584 wants to ask has nowhere to be asked from.
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
- Next step: this is worth settling together with B-584, since both are about what happens to a
  caught error nobody looked at. The narrow question here is whether the capture could scope to the
  statement plus the statements dominated by its test — which is what every use in the reference
  actually needs — and whether anything in `bin/` reads an `err` outside the block that produced it.
  Count that first; if the answer is nothing, the change is a scope narrowing with a mechanical
  migration.
- Related: [B-584](#b-584--catch-without-a-capture-substitutes-the-type-default-and-says-nothing)

## Types and bindings that do not own what they name

### B-605 — `[2, 2] T` and `[2][2] T` are different types indexed the same way

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

### B-606 — The index binding has three different integer types depending on what is iterated

- Area: language
- Found while: the same pass, while reviewing index bindings
- Observation: one role, three types. Binding the index over a collection gives a `u64`, over a
  counted loop a `u32`, and over a range an `s32`. Nothing at the use site distinguishes the three,
  and the difference is exactly the one B-582 turns into arithmetic: an index that is unsigned in
  two of the three forms, next to a `.count` that is always `u64` and a signed computation that is
  `s32`. The reference asserts the collection case (`#assert(#typeof(index) == u64)`
  ([005_003_for_elements.swg:29-40](../bin/reference/modules/language/src/005_003_for_elements.swg#L29-L40)))
  and never mentions that the other two forms answer differently.
- Evidence: an isolated probe, `swc test -d <dir>`, printing `#nameof(#typeof(index))` in three
  neighbouring loops over the same data:

  ```
  for ?, index in values  ->  u64
  for index in 3          ->  u32
  for index in 0 to 2     ->  s32
  ```

  The reference already documents the consequence without naming the cause: it warns not to write
  `for i in 0 to count - 1` on an unsigned counter, because `count - 1` wraps when `count` is zero
  and only the overflow guard reports it
  ([005_002_for.swg:161-180](../bin/reference/modules/language/src/005_002_for.swg#L161-L180)).
- Elsewhere: the question mostly does not arise, because the index is a value someone produced
  rather than a binding the loop invents. Rust's `enumerate()` yields `usize` and `0..n` yields
  whatever `n` is, so the type is written in the expression; Go's `range` index is `int` — signed —
  for every form, which is the property Swag lacks; Python has one integer type; C# `for` and
  `Enumerable.Range` both give `int`. Where a language does use an unsigned index everywhere,
  as C++ does with `size_t`, the uniformity is the point, and the `i >= 0` loop bug that comes with
  it is a single well-known hazard rather than a per-form one.
- Next step: decide whether the three should agree, and on what. `u64` matches `.count` and is the
  only one that cannot overflow on a real collection; `s32` is the one that makes `i - 1` behave.
  The cheapest useful step first: add the three-way result above to the `for` chapter, since a
  reader today has no way to know which one they have without `#typeof`. Then check whether a
  counted `for i in N` could simply take the type of `N`, which would remove one of the three
  without touching the other two.

## Where a move can land

### B-621 — A moved value cannot initialize an aggregate literal field or a conditional branch

- Area: language
- Found while: fixing a case where those two expressions asserted in code generation instead of
  being diagnosed
- Observation: `blocks.add(Block{kind, #move text})` and
  `var value = condition ? String.from("rule") : #move block.text` now report a clear error
  rather than crashing the compiler, but both read like ordinary Swag and the language has no
  short spelling for what they mean. The workaround is to write the move as its own statement
  first, which costs a named temporary every time.
- Evidence: `#move x` produces a move reference, and only a `#move` parameter consumes one. A
  literal is materialized as a value and a conditional joins two values, so neither offers a slot
  for the transfer to land in. `SemaCheck::noMoveRefType` states that from
  `finalizeAggregateStruct` ([SemaHelpers.Type.cpp](../src/Compiler/Sema/Helpers/SemaHelpers.Type.cpp)),
  `AstArrayLiteral::semaPostNode`, and `AstConditionalExpr::semaPostNode`.
- Elsewhere: C++ and Rust both accept it. `Pair{kind, std::move(text)}` move-constructs the field,
  and Rust moves out of a binding in any value position, a `match` arm included. No neighbouring
  language with move semantics restricts a move to a call argument.
- Next step: decide whether a literal field and a conditional branch should move-construct their
  destination. The rule is not the obstacle, the lowering is: an aggregate literal is materialized
  as one value through `emitAggregateLiteralPayload`, so a moved field needs its own store plus
  the source's post-move invalidation instead of that path.

## What a payload pointer promises

### B-631 — '.buffer' answers a non-null pointer for a payload that can be absent

- Area: language
- Found while: widening the never-null condition rule. The `bin/` sweep it forced stopped
  on `if (ptrAny[]).buffer` in `convertAny`, which reads as "does this value carry a payload" and
  which the type system now calls a constant.
- Observation: `.buffer` of a `string` or `cstring` now carries the source's `#null`, but the `any`
  and `interface` cases still answer a non-null block pointer whatever the payload is. The
  container's own nullability is not the payload's: a non-null `any` built by `Swag.makeAny(null, type)`
  and an interface whose `obj` was never set both hand back null, and `bin/std` already tests for
  it — `encoder.swg` writes `if !itf.obj` on the raw field precisely because `.buffer` would not
  let it ask.
- Evidence: `semaIntrinsicDataOf` ([Sema.Intrinsic.cpp](../src/Compiler/Sema/Ast/Sema.Intrinsic.cpp))
  builds the `any` and `interface` results with `TypeInfo::makeBlockPointer(typeVoid(), flags)`,
  where `flags` comes from the container type. Probe — `convertAny` had to read its `any` through
  `[as #null any]` to keep asking the question at all. Verified against 0.1.186.
- Elsewhere: Rust's `Option<&T>` and C#'s nullable references both attach absence to the payload
  reference, never to the handle that carries it.
- Next step: decide whether the `any` and `interface` payload pointers are always nullable-capable,
  which is what the runtime says. The obstacle is scale, not doctrine: `bin/` holds around 1300
  `.buffer` uses and the interface form is the common one, so the sweep is `cast(*T) itf.buffer!`
  at every site. Measure it before committing, and consider whether a non-null `any` should instead
  be the type that promises a payload, making `Swag.makeAny(null, type)` the thing that needs `#null`.
