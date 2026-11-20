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
  The remaining construction obstacle is moved-source reset (compiler.ai.018), not the absence
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

The language work in the AI-first migration is tracked in [compiler.ai.md](compiler.ai.md).
Public API consistency remains a module-by-module design requirement under
[design-swag-bin-modules](../.agents/skills/design-swag-bin-modules/SKILL.md): value returns,
options structs, slices and ownership contracts are available today. A concrete API defect belongs
in its module backlog; a general request for better names is not a missing language feature.

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
  closed mutually exclusive variants in compiler.ai.016. Any new spelling must replace
  the old mechanism, not permanently duplicate it.
- Next: Compare the existing attributed declaration with a direct flags declaration on public
  and serialized types. Specify zero, automatic bit allocation, combined constants, masks and
  explicit ABI values. A source edit that changes representation must be visible in the schema
  or API review; choose whether stable representations require explicit values.
- Done when: the selected declaration and representation contract is documented and migrated, and
  tests cover empty sets, combinations, reflection, serialization and public numeric stability.

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
- Related: compiler.ai.005.

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

### language.design.044 — Declare parameters that need named arguments

- Evidence: [named arguments](../bin/reference/modules/language/src/007_001_declaration.swg)
  are optional at the call site. An API with two same-typed parameters can give them distinct
  names, but its declaration cannot prevent a positional call that reverses their roles.
- Elsewhere: Python supports keyword-only parameters after `*`
  ([PEP 3102](https://peps.python.org/pep-3102/)).
- Next: prototype an opt-in parameter attribute such as `#[Swag.Named]` using the existing
  parameter-attribute syntax. Have argument matching reject a positional binding to a marked
  parameter and point to the required label. Define how a defaulted parameter may be omitted,
  how the rule affects overload selection, and how exported signatures and indirect calls
  carry the requirement. Compare the prototype with a named-field request record.
- Done when: there is a documented decision on declaration-side enforcement. If adopted,
  executable cases cover positional rejection, named calls, omission with defaults, overloads,
  and calls through imported or indirect signatures.
- Related: std.core.041.

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
