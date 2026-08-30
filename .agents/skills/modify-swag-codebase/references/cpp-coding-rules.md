# Swag C++ Coding Rules

## Simplify And Clarify

- Prefer named functions over lambdas used only as local functions, but only when the extracted helper adds real meaning or isolates non-trivial logic.
- Allow small inline struct or aggregate construction in function calls when it stays short, obvious, and readable.
- Do not introduce tiny helpers whose only purpose is to rename a short literal construction or a trivial expression.
- Keep code easy to read and reason about.
- Avoid `if (init; condition)` when initialization is non-trivial; perform the setup before the `if`.

## Design Functions

- Avoid functions with too many parameters.
- Group related parameters into structs or objects when appropriate.
- Do not return an object by reference from a function that receives that same object by reference.
- When a helper may resolve an alternate object or retain the original input, make the fallback explicit at the call site. Prefer a pointer or handle for the alternate result, or another explicit status, instead of silently aliasing the input reference in the return value.
- Place output parameters first after global or context parameters such as managers.

## Use C++ Types Deliberately

- Put `const` on the left side of a type; do not write `int const`.
- Preserve const correctness where meaningful.
- Use `auto` when it improves readability, avoids repeating a complex type, or reduces redundancy.
- Use explicit types when they communicate intent or avoid ambiguity.
- Use pointers, not references, for struct and class fields.

## Format For Readability

- Keep function declarations on one line.
- Keep function calls on one line.
- Refactor declarations with excessive parameters instead of wrapping them across lines.
- Keep lines reasonably short and readable even though the project has no theoretical line-length limit.

## Reuse At The Right Level

- Eliminate duplication.
- Extract helpers when they capture meaningful behavior, domain intent, or non-trivial repeated logic.
- Reuse existing utilities when they fit.
- Place a helper with the type or utility when it is generic to that abstraction.
- Keep file-local helpers file-local and domain-specific.
- Do not add an ad hoc local helper when an existing shared utility fits.

### Search Before Writing A File-Local Helper

A helper written in an anonymous namespace is invisible to the next author, who writes it again.
Before adding one, grep the tree for its signature and for a distinctive line of its body. When a
twin turns up, share the two instead of adding a third.

Where the shared one belongs, in order of preference:

1. On the type it interrogates. A question about a `TypeInfo`, a `TypeManager`, a
   `SymbolFunction`, or a `Token` is a member of that type — `TypeManager::builtinType`,
   `SymbolFunction::parentLexicalFunction`, `Token::isOpRelational`.
2. In the domain namespace that already owns the area — `SemaHelpers`, `CodeGenMemoryHelpers`,
   `MicroPassHelpers`, `Cast`.
3. File-local, and only then.

### Collapse Twins Onto One Parameter

Two functions whose bodies differ by a single constant, field, or diagnostic id are one function
with one more parameter. `#sizeof`/`#alignof`, `Swag.memcpy`/`Swag.memmove`, and `#safety`/`#sanity` each
collapsed this way, and so did five `registerNative*Function` methods that differed only in the
bucket they appended to. A `bool` parameter is acceptable when the call site reads clearly; pass a
pointer-to-member or an id when it does not.

## Classify In The Table, Not At Each Site

Repeated `case` lists over the same enum are a classification that never got written down. When
the same group of `TokenId`, `AstNodeId`, or `MicroInstrOpcode` values appears in more than one
switch, add the group to the definition table — a kind bit in `Tokens.Def.inc`, a flag in
`MicroInstr.Def.inc` — and give it one named predicate.

- A `bool isX(Enum)` written as a switch that only returns `true` or `false` is a table lookup in
  disguise. Make it one: it is shorter, and one masked load beats a jump table plus two branches.
- Keep such predicates inline in the header so the call costs nothing.
- Leave real dispatch switches alone. A switch whose arms each do different work is already a jump
  table, its `case` labels cost nothing at run time, and hoisting a predicate in front of it adds a
  test to a hot path to save source lines. That trade is never worth it (see below).

## Never Pay For A Shorter File

Shrinking the sources must not cost the compiler a cycle or a byte. `swc` has to stay the fastest
and the leanest compiler for the job, and a refactor that regresses either is a regression, however
much cleaner it reads.

- Prefer the rewrites that shrink *and* speed up: a table lookup replacing a switch chain, a
  duplicated body replaced by one shared out-of-line copy, a template that stops three files from
  instantiating the same code.
- Keep the early-out at the call site when factoring a family of functions. The `Sema::wait*`
  family shares its parking path but each entry point still tests its own readiness predicate
  inline, because that test is the hot path and parking is the cold one.
- Do not widen a struct that lives in a per-function container just to share it. Three peephole
  passes share their `Action` machinery through a template precisely so the post-RA pass can keep
  its smaller operand array.
- Do not introduce indirection — a virtual call, a `std::function`, a heap allocation — that was
  not there before.
- Measure when a change touches sema, codegen, or a micro pass: compare compile time and peak
  memory on the same workspace before and after.

### A Template Buys Source Lines With Binary Size

Collapsing near-identical functions into a template is the right call when the difference is a
type or a compile-time constant, and it is the only way to share code without adding an indirect
call. It is not free: every instantiation is its own body, and the linker's identical-COMDAT
folding only reclaims the ones that come out byte-identical — which the interesting instantiations,
the ones that differ by a constant, never do. Two hand-written twins the linker was already folding
become two instantiations it cannot.

Measured on this repository: a round of factoring that removed 226 source lines, mostly by
templating families of two and three near-identical functions, grew `swc.exe` by 3 072 bytes.

So reach for a template when it removes a real maintenance hazard — a list that must be kept in
step across copies, a family a new case has to be added to twice — and check the executable size
afterwards. When the only gain is a shorter file, a plain parameter is the better trade.

## Enforce Invariants

- Avoid unnecessary defensive programming.
- Prefer `SWC_ASSERT` for assumptions and invariants.
- Fail fast when an invariant is violated.

## Write Useful Comments

- Explain why, not what.
- Document non-obvious decisions, constraints, trade-offs, assumptions, invariants, and edge cases.
- Do not restate obvious code.
- Remove outdated or redundant comments.
- Refactor confusing code instead of explaining avoidable complexity.

## Keep The Design Maintainable

- Prioritize readability over cleverness.
- Keep functions small and focused.
- Make intent explicit and avoid hidden behavior.
- Write code that is easy to maintain, test, and refactor.
