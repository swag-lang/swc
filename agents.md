# Agents Guide

## Hard Rules

- Always fix the **root cause** of problems. Do not introduce hacks or workarounds.

---

### Validation Workflow

- After any change:
    1. Compile a **DevMode** build.
    2. Run `test_dm.bat`.
    3. If either step fails, fix the issue before proceeding.
    4. Run `all_dm.bat`.

- When `all_dm.bat` completes successfully (no crashes or errors):
    1. Compile `swc` in **Release** mode.
    2. Run `all.bat`.
    3. Ensure no regressions occur.

---

### Determinism

- When modifying **code generation**:
    - Run `test.bat` **10 consecutive times**.
    - Investigate and fix any nondeterministic behavior.

---

### Testing

- Any new swag language feature must include **relevant tests**:
    - Place them in the appropriate `bin/tests` folder.

- **C++ unit tests**:
    - Backend only
    - Must be placed in `src/Unittest`

- Individual tests must not exceed **40 seconds** of runtime  
  (compilation time excluded).

---

### Clean Workspace

- Remove any **temporary files or folders** created during debugging or investigation before finishing.

---

## Coding Rules

- Follow the rules defined in `@coding-rules.md` when designing and writing code.