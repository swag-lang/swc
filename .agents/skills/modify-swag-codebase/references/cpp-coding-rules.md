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
