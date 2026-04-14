# Agents Guide (C++)

## Code Quality Guidelines

### 1. Simplify and Clarify

- Prefer **named functions** over unnecessary lambdas.
- Avoid **inline struct construction** in function calls. Use local variables or pass them as arguments instead.
- Keep code easy to read and reason about.

---

### 2. Function Design

- Avoid functions with **too many parameters**.
- Group related parameters into **structs or objects** when appropriate.
- When returning values via parameters:
    - Place **output parameters first**, after global/context parameters (e.g., managers).

---

### 3. Type Usage (C++)

- Do not place `const` on the right side of a type (avoid `int const x`).
- Prefer `const` correctness where meaningful.
- Use `auto` when it:
    - Improves readability
    - Avoids repeating complex or verbose types
    - Reduces redundancy
- Use explicit types when they better communicate intent or avoid ambiguity.
- Do not use references in structs or classes fields, prefer pointers.

---

### 4. Formatting

- Function declarations must be written on a **single line** (no multi-line parameter lists).
- Function calls must be written on a **single line** (no multi-line arguments).
- There's no theorical limit to the length of a line, but keep it short and readable.
- If a function declaration is very long, then refactor it to reduce the number of parameters.

---

### 5. Code Reuse

- Eliminate duplication:
    - Extract **helper functions**
    - Reuse existing utilities when available
- Avoid copy-paste logic.

---

### 6. Assertions vs Defensive Code

- Avoid unnecessary defensive programming.
- Prefer using `SWC_ASSERT` to enforce assumptions and invariants.
- Fail fast when invariants are violated.

---

### 7. Comments

- Write comments like an experienced developer:
    - Explain **why**, not **what** (the code should already show what it does).
    - Document **non-obvious decisions**, constraints, and trade-offs.
- Avoid over-commenting:
    - Do not restate obvious code.
    - Remove outdated or redundant comments.
- Prefer **clear code over comments**:
    - Refactor confusing code instead of explaining it.
- Use comments to:
    - Clarify complex logic
    - Highlight assumptions and invariants
    - Warn about edge cases or pitfalls

---

### 8. General Principles

- Prioritize **readability over cleverness**.
- Keep functions **small and focused**.
- Write code that is **easy to maintain, test, and refactor**.
- Make intent explicit and avoid hidden behavior.