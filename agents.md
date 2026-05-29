# Agents Guide

## Hard Rules

- Always fix the **root cause** of problems. Do not introduce hacks or workarounds.
- Follow the rules defined in `@coding-rules.md` when designing and writing code.

---

### Validation Workflow

- After any change:
    1. Compile a **DevMode** build.
    2. Run `test.bat dm`.
    3. If either step fails, fix the issue before proceeding.
    4. Run `all.bat dm` (only if you have change c++ files)
    5. Compile the **Release** build (`swc.exe`).
    6. Run `test.bat`.
    7. If either release step fails, fix the issue before proceeding.
    8. Do not run `all.bat` in release mode as part of the default validation workflow.

---

### Testing

- Any new swag language feature must include **relevant tests**:
    - Place them in the appropriate `bin/tests` folder.

- **C++ unit tests**:
    - Must be placed in `src/Unittest`

- Individual tests must not exceed **40 seconds** of runtime
  (compilation time excluded).

---

### Clean Workspace

- Remove any **temporary files or folders** created during debugging or investigation before finishing.
